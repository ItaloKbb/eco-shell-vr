extends Node3D
## Inicia em VR (Meta Quest via Quest Link, ou qualquer runtime OpenXR) se houver
## headset; senão usa a câmera de primeira pessoa do carro no monitor.

## Supersampling moderado: no Link, 1,10 renderiza 21% mais pixels. O antigo
## 1,25 custava 56% mais pixels e, somado ao MSAA 4x, saturava a GPU/encoder.
@export_range(1.0, 1.5, 0.05) var escala_render_vr_pc := 1.10
@export_range(1.0, 1.3, 0.05) var escala_render_vr_quest := 1.10

@onready var camera_debug: Camera3D = $CameraDebug
@onready var carro: RigidBody3D = $Carro
@onready var camera_carro: Camera3D = $Carro/Cabeca

var _xr: XRInterface
var ritual: Node
var _perfil_spawn := {}

func _ready():
	if OS.has_feature("android"):
		_ajustar_para_quest()
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

## A escala 3D atua depois que o OpenXR já escolheu a resolução recomendada do
## headset, portanto também funciona quando o runtime é Quest Link/SteamVR.
## MSAA limpa as bordas geométricas sem o borrão de filtros de pós-processamento.
func _configurar_render_vr():
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = escala_render_vr_quest if OS.has_feature("android") else escala_render_vr_pc
	# No PC/Link, 2x mantém as bordas limpas sem multiplicar demais a carga antes
	# da compressão de vídeo. No APK o tile renderer do Quest lida bem com 4x.
	viewport.msaa_3d = Viewport.MSAA_4X if OS.has_feature("android") else Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	print("Render VR: escala %.2fx, MSAA %s" % [viewport.scaling_3d_scale, "4x" if OS.has_feature("android") else "2x"])

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
		for nome in ["PistaEnergia", "Inimigos", "Portais"]:
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
	# Quest 2/3 começam em 72 Hz; pede 90 se o headset oferecer
	if OS.has_feature("android") and 90.0 in _xr.get_available_display_refresh_rates():
		_xr.display_refresh_rate = 90.0
	carro.recentralizar()

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
	# Tab alterna entre o carro e a câmera livre de debug
	elif event.keycode == KEY_TAB and not get_viewport().use_xr and not carro.em_ritual and not carro.em_transicao:
		if camera_carro.current:
			camera_debug.global_transform = camera_carro.global_transform
			camera_debug.set("rot_x", camera_debug.rotation.x)
			camera_debug.set("rot_y", camera_debug.rotation.y)
			camera_debug.make_current()
		else:
			camera_carro.make_current()
