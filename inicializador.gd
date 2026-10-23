extends Node
## Cena inicial, sem nada visual: decide se este executável é cliente VR ou servidor.
## 1) --servidor / --cliente forçam o modo; 2) Android (Quest) é sempre cliente;
## 3) no PC, OpenXR inicializado (headset via Link/Air Link) = cliente, senão servidor.
## O OpenXR já tentou subir no boot (xr/openxr/enabled), aqui só lê o resultado.
## No Android o APK nem passa por aqui (run/main_scene.android abre menu.tscn).

const CENA_CLIENTE := "res://menu.tscn"
const CENA_SERVIDOR := "res://painel_servidor.tscn"
const FPS_SERVIDOR := 30

func _ready():
	var servidor := _modo_servidor()
	if servidor:
		_preparar_servidor()
		Rede.iniciar_servidor()
	else:
		Rede.iniciar_cliente()
	print("Modo: %s" % ("SERVIDOR" if servidor else "CLIENTE"))
	get_tree().change_scene_to_file.call_deferred(CENA_SERVIDOR if servidor else CENA_CLIENTE)

func _modo_servidor() -> bool:
	var args := Rede.argumentos()
	if "--servidor" in args:
		return true
	if "--cliente" in args:
		return false
	if OS.has_feature("android"):
		return false
	var xr := XRServer.find_interface("OpenXR")
	return xr == null or not xr.is_initialized()

## Painel 2D: sem XR, sem câmera 3D, em janela, gastando pouco
func _preparar_servidor():
	get_viewport().use_xr = false
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		xr.uninitialize()
	OS.low_processor_usage_mode = true
	Engine.max_fps = FPS_SERVIDOR
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	DisplayServer.window_set_title("Eco Shell VR · Servidor do evento")
