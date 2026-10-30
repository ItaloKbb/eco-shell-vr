extends Node3D
## Inicia em VR (Meta Quest via Quest Link, ou qualquer runtime OpenXR) se houver
## headset; senão usa a câmera de primeira pessoa do carro no monitor.

## Supersampling moderado: no Link, 1,10 renderiza 21% mais pixels. O antigo
## 1,25 custava 56% mais pixels e, somado ao MSAA 4x, saturava a GPU/encoder.
@export_range(1.0, 1.5, 0.05) var escala_render_vr_pc := 1.10
## No APK fica em 1,0. Abaixo disso (FSR ou bilinear) o Godot 4.7.2 Mobile em XR
## para de desenhar a cena (erros "!draw_list.active" a cada quadro); o ganho de GPU
## para os 90 Hz vem da foveação dinâmica e da resolução dinâmica da Meta
@export_range(0.5, 1.3, 0.05) var escala_render_vr_quest := 1.0
## Taxa de atualização pedida ao Quest (Hz); fica na padrão se o headset não oferecer.
## Medido no lobby: 90 FPS estáveis, ~9,3 ms de GPU do app (orçamento de 11,1 ms)
@export var hz_quest := 90.0
## Ajuste local no headset, sem gerar outro APK (seção [quest]: escala, fsr, hz). Num
## APK de debug: adb shell run-as br.senai.ecoshellvr para gravar em files/
const AJUSTE_LOCAL := "user://render_vr.cfg"

@onready var camera_debug: Camera3D = $CameraDebug
@onready var carro: RigidBody3D = $Carro
@onready var camera_carro: Camera3D = $Carro/Cabeca

var _xr: XRInterface
var ritual: Node
var _perfil_spawn := {}

func _ready():
	if OS.has_feature("android"):
		_ajustar_para_quest()
		# O APK abre direto aqui (sem o Inicializador, que deixava quadros sem XR no
		# boot): no Quest é sempre cliente do evento
		if Rede.modo == Rede.Modo.DESLIGADO:
			Rede.iniciar_cliente()
	_xr = XRServer.find_interface("OpenXR")
	if _xr and _xr.is_initialized():
		print("OpenXR ativo: dirigindo em VR")
		# O headset dita o ritmo; vsync do monitor só atrapalharia
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		_configurar_render_vr()
		$Carro/OrigemXR.current = true
		$Carro/OrigemXR/CameraXR.make_current()
		_xr.session_begun.connect(_sessao_iniciada)
		# Quest: o rastreamento só vale quando o app ganha o foco; e segurar o botão
		# Meta recentraliza o mundo do runtime, então a âncora do cockpit é refeita
		if _xr.has_signal("session_focussed"):
			_xr.session_focussed.connect(carro.recentralizar)
		if _xr.has_signal("pose_recentered"):
			_xr.pose_recentered.connect(carro.recentralizar)
		_sincronizar_fisica(_xr.display_refresh_rate)
	else:
		print("Sem headset: dirigindo o carro em primeira pessoa")
		camera_carro.make_current()
		# Sem rastreamento, as mãos VR ficariam paradas na frente da câmera
		$Carro/OrigemXR.visible = false
	# O ritual precisa conhecer o modo real antes de criar o painel.
	ritual = preload("res://ritual_partida.gd").new()
	add_child(ritual)
	# Assistente Yui: apresenta o lugar no começo e encoraja nas corridas
	var yui := AssistenteYui.new()
	yui.carro = carro
	yui.musica = get_node_or_null("Musica")
	add_child(yui)
	# Ranking geral do evento no céu (vem do servidor; sem servidor fica aguardando)
	add_child(TelaoRanking.new())

## A escala 3D atua depois que o OpenXR já escolheu a resolução recomendada do
## headset, portanto também funciona quando o runtime é Quest Link/SteamVR.
## MSAA limpa as bordas geométricas sem o borrão de filtros de pós-processamento.
func _configurar_render_vr():
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = escala_render_vr_pc
	if OS.has_feature("android"):
		var ajuste := ConfigFile.new()
		ajuste.load(AJUSTE_LOCAL)
		escala_render_vr_quest = ajuste.get_value("quest", "escala", escala_render_vr_quest)
		hz_quest = ajuste.get_value("quest", "hz", hz_quest)
		var fsr: bool = ajuste.get_value("quest", "fsr", true)
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr and escala_render_vr_quest < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = escala_render_vr_quest
	# No PC/Link, 2x mantém as bordas limpas sem multiplicar demais a carga antes
	# da compressão de vídeo. No APK o tile renderer do Quest lida bem com 4x.
	viewport.msaa_3d = Viewport.MSAA_4X if OS.has_feature("android") else Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Quest: foveação fixa (nível e dinâmica em project.godot, só .android) aplicada
	# pelo VRS do renderizador Mobile. Sem "subsampled images": era ela que, com o
	# glow e os SubViewports, deixava a tela piscando azul e preto. Junto vêm a
	# resolução dinâmica da Meta e o MQSR (supersampling + nitidez Quality na camada
	# de projeção), que recupera no compositor a nitidez do buffer menor
	if OS.has_feature("android"):
		viewport.vrs_mode = Viewport.VRS_XR
	print("Render VR: escala %.2fx (%s), MSAA %s" % [viewport.scaling_3d_scale,
		"FSR" if viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR else "bilinear", "4x" if OS.has_feature("android") else "2x"])

## Só durante o nascimento: evita renderizar tempestade e pós-processamento
## atrás da casca fechada. Restaura o perfil anterior antes de revelar a saída.
func ajustar_spawn_vr(ativo: bool):
	var env: Environment = $WorldEnvironment.environment
	if ativo:
		if not _perfil_spawn.is_empty():
			return
		for propriedade in ["volumetric_fog_enabled", "glow_enabled", "ssr_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled"]:
			_perfil_spawn[propriedade] = env.get(propriedade)
			env.set(propriedade, false)
		_perfil_spawn["atmosfera"] = $Atmosfera.visible
		_perfil_spawn["chunks"] = $HexWorld.chunks_per_frame
		_perfil_spawn["hex_visible"] = $HexWorld.visible
		_perfil_spawn["sombra"] = $DirectionalLight3D.shadow_enabled
		var nos_ocultos := {}
		for nome in ["PistaEnergia", "Portais"]:
			var no: Node3D = get_node(nome)
			nos_ocultos[nome] = [no.visible, no.process_mode]
			no.visible = false
			no.process_mode = Node.PROCESS_MODE_DISABLED
		_perfil_spawn["nos_ocultos"] = nos_ocultos
		$Atmosfera.hide()
		# Continua gerando colisões para a saída, mas não desenha o mundo escondido
		# atrás da casca do nascimento.
		$HexWorld.visible = false
		$HexWorld.chunks_per_frame = 1
		$DirectionalLight3D.shadow_enabled = false
	elif not _perfil_spawn.is_empty():
		for propriedade in ["volumetric_fog_enabled", "glow_enabled", "ssr_enabled", "ssao_enabled", "ssil_enabled", "sdfgi_enabled"]:
			env.set(propriedade, _perfil_spawn[propriedade])
		$Atmosfera.visible = _perfil_spawn["atmosfera"]
		$HexWorld.visible = _perfil_spawn["hex_visible"]
		$HexWorld.chunks_per_frame = _perfil_spawn["chunks"]
		$DirectionalLight3D.shadow_enabled = _perfil_spawn["sombra"]
		for nome in _perfil_spawn["nos_ocultos"]:
			var no: Node3D = get_node(nome)
			var estado: Array = _perfil_spawn["nos_ocultos"][nome]
			no.visible = estado[0]
			no.process_mode = estado[1]
		_perfil_spawn.clear()

## Rodando direto no Quest (APK): GPU de celular desenhando duas vezes (um olho cada),
## então troca a névoa volumétrica (que o renderizador Mobile nem suporta) por névoa
## comum, encurta o horizonte e liga MSAA, que no Quest é barato e tira o serrilhado.
func _ajustar_para_quest():
	var env: Environment = $WorldEnvironment.environment
	env.volumetric_fog_enabled = false
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 30.0
	env.glow_intensity = 0.6
	$HexWorld.view_distance = 30.0
	$HexWorld.chunks_per_frame = 1
	$DirectionalLight3D.shadow_enabled = false
	$Atmosfera.process_mode = Node.PROCESS_MODE_DISABLED
	$Atmosfera.visible = false

func _sessao_iniciada():
	_sincronizar_fisica(_xr.display_refresh_rate)
	if not _xr.refresh_rate_changed.is_connected(_sincronizar_fisica):
		_xr.refresh_rate_changed.connect(_sincronizar_fisica)
	# Quest: pede 90 Hz (a escala menor com FSR é o que deixa a GPU sustentar; sem
	# folga o headset reprojeta quadros, e a tremedeira é o que mais enjoa na VR)
	if OS.has_feature("android") and hz_quest in _xr.get_available_display_refresh_rates():
		_xr.display_refresh_rate = hz_quest
		_sincronizar_fisica(hz_quest)
	carro.recentralizar()
	_registrar_desempenho_vr()

## O que o runtime aceitou de foveação, resolução dinâmica e MQSR (adb logcat -s godot),
## para conferir no headset junto com o OVR Metrics Tool
func _registrar_desempenho_vr():
	var openxr := _xr as OpenXRInterface
	if openxr == null:
		return
	var camada := "xr/openxr/extensions/meta/composition_layer_settings/main_projection_layer/filtering/"
	print("Desempenho VR: foveação %s (nível %d, dinâmica %s, VRS %d) · resolução dinâmica Meta %s · MQSR supersampling %d nitidez %d · %.0f Hz · alvo %s" % [
		"suportada" if openxr.is_foveation_supported() else "NÃO suportada", openxr.foveation_level,
		openxr.foveation_dynamic, get_viewport().vrs_mode,
		ProjectSettings.get_setting("xr/openxr/extensions/meta/dynamic_resolution", false),
		ProjectSettings.get_setting(camada + "supersampling_mode", 0), ProjectSettings.get_setting(camada + "sharpening_mode", 0),
		openxr.display_refresh_rate, openxr.get_render_target_size()])
	print("Física: %d ticks/s · taxas do headset %s" % [Engine.physics_ticks_per_second, openxr.get_available_display_refresh_rates()])
	# O que vale é o que a extensão aceitou na sessão (no headset, VrApi mostra
	# ShrpLCnt/SSLCnt quando o compositor aplica)
	if Engine.has_singleton("OpenXRFbCompositionLayerSettingsExtension"):
		var ext := Engine.get_singleton("OpenXRFbCompositionLayerSettingsExtension")
		print("MQSR: extensão %s, supersampling %d, nitidez %d, filtro automático %s" % [
			"ativa" if ext.is_enabled() else "INATIVA", ext.get_projection_layer_supersampling_mode(),
			ext.get_projection_layer_sharpening_mode(), ext.is_projection_layer_auto_filter_enabled()])

## Física no mesmo ritmo da tela do headset (72/90/120 Hz): o carro anda no passo
## da física e a câmera vai junto, então ritmos diferentes causam tremedeira na VR
func _sincronizar_fisica(hz: float):
	if hz > 0.0:
		Engine.physics_ticks_per_second = roundi(hz)
		Engine.max_physics_steps_per_frame = 2

func _unhandled_input(event):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# F11 alterna entre tela cheia e janela
	if event.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Tab alterna entre o carro e a câmera livre de debug (fora do evento: no notebook
	# do modo GAME o público não pode sair voando pelo mapa)
	elif event.keycode == KEY_TAB and not get_viewport().use_xr and Rede.modo != Rede.Modo.CLIENTE 			and not carro.em_ritual and not carro.em_transicao:
		if camera_carro.current:
			camera_debug.global_transform = camera_carro.global_transform
			camera_debug.set("rot_x", camera_debug.rotation.x)
			camera_debug.set("rot_y", camera_debug.rotation.y)
			camera_debug.make_current()
		else:
			camera_carro.make_current()
