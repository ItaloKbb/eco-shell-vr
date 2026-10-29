class_name Inicializador
extends Node
## Cena inicial, sem nada visual: decide se este executável é cliente VR, servidor,
## espectador (telão) ou jogo no teclado (notebook do evento). 1) --servidor /
## --espectador / --jogo / --cliente forçam o modo; 2) Android (Quest) é sempre cliente;
## 3) no PC, OpenXR inicializado (headset via Link/Air Link) = cliente, senão pergunta
## (escolha_modo.tscn): servidor, espectador ou jogo.
## O OpenXR já tentou subir no boot (xr/openxr/enabled), aqui só lê o resultado.
## No Android o APK nem passa por aqui (run/main_scene.android abre menu.tscn).

const CENA_CLIENTE := "res://menu.tscn"
const CENA_SERVIDOR := "res://painel_servidor.tscn"
const CENA_ESPECTADOR := "res://espectador.tscn"
const CENA_ESCOLHA := "res://escolha_modo.tscn"
const FPS_SERVIDOR := 30
const FPS_ESPECTADOR := 60
## Notebook com GPU integrada: teto para não esquentar nem derrubar a física
const FPS_JOGO := 60

func _ready():
	var modo := _modo()
	if modo == "perguntar":
		_janela_pc(Vector2i(1200, 640), "Eco Shell VR")
		OS.low_processor_usage_mode = true
		get_tree().change_scene_to_file.call_deferred(CENA_ESCOLHA)
		return
	iniciar(modo)

## "cliente", "servidor", "espectador", "jogo" ou "perguntar"
func _modo() -> String:
	var args := Rede.argumentos()
	for modo in ["servidor", "espectador", "jogo", "cliente"]:
		if "--" + modo in args:
			return modo
	if OS.has_feature("android"):
		return "cliente"
	var xr := XRServer.find_interface("OpenXR")
	return "cliente" if xr != null and xr.is_initialized() else "perguntar"

## Liga a rede no modo escolhido e abre a cena dele (também chamado pela escolha_modo)
static func iniciar(modo: String):
	var cena := CENA_CLIENTE
	match modo:
		"servidor":
			_janela_pc(Vector2i(1440, 900), "Eco Shell VR · Servidor do evento")
			# Painel 2D: gastando pouco
			OS.low_processor_usage_mode = true
			Engine.max_fps = FPS_SERVIDOR
			Rede.iniciar_servidor()
			cena = CENA_SERVIDOR
		"espectador":
			if _reabrir_em_vulkan(modo):
				return
			_janela_pc(Vector2i(1600, 900), "Eco Shell VR · Espectador")
			# Transmissão: animação fluida para o telão/OBS
			OS.low_processor_usage_mode = false
			Engine.max_fps = FPS_ESPECTADOR
			Rede.iniciar_espectador()
			cena = CENA_ESPECTADOR
		"jogo":
			# Mesmo cliente do Quest, mas sem XR: teclado/mouse (ou gamepad) em tela cheia
			if _reabrir_em_vulkan(modo):
				return
			_janela_pc(Vector2i(1600, 900), "Eco Shell VR")
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			OS.low_processor_usage_mode = false
			Engine.max_fps = FPS_JOGO
			Rede.iniciar_cliente()
		_:
			Rede.iniciar_cliente()
	print("Modo: %s" % modo.to_upper())
	(Engine.get_main_loop() as SceneTree).change_scene_to_file.call_deferred(cena)

## O projeto usa D3D12 no Windows (escolhido para o VR), mas em GPU Intel integrada o
## D3D12 perde o dispositivo ao desenhar os mapas de corrida. Espectador e jogo não usam
## XR: reabre o executável em Vulkan (e sem OpenXR) já no modo e fecha este.
## --rendering-driver explícito é respeitado.
static func _reabrir_em_vulkan(modo: String) -> bool:
	if RenderingServer.get_current_rendering_driver_name() != "d3d12" or "--rendering-driver" in OS.get_cmdline_args():
		return false
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--rendering-driver", "vulkan", "--xr-mode", "off", "--", "--" + modo])
	if OS.create_process(OS.get_executable_path(), args) <= 0:
		return false
	print("%s: reabrindo em Vulkan" % modo.capitalize())
	(Engine.get_main_loop() as SceneTree).quit()
	return true

## Sem XR e em janela (servidor, espectador e a própria escolha)
static func _janela_pc(tamanho: Vector2i, titulo: String):
	var arvore := Engine.get_main_loop() as SceneTree
	arvore.root.use_xr = false
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr.uninitialize()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(tamanho)
	DisplayServer.window_set_title(titulo)
	var tela := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(tela.position + (tela.size - tamanho) / 2)
