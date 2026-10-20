extends Node3D
## Inicia em VR (Meta Quest via Quest Link, ou qualquer runtime OpenXR) se houver
## headset; senão usa a câmera de primeira pessoa do carro no monitor.

@onready var camera_debug: Camera3D = $CameraDebug
@onready var carro: RigidBody3D = $Carro
@onready var camera_carro: Camera3D = $Carro/Cabeca

var _xr: XRInterface

func _ready():
	if OS.has_feature("android"):
		_ajustar_para_quest()
	_xr = XRServer.find_interface("OpenXR")
	if _xr and _xr.is_initialized():
		print("OpenXR ativo: dirigindo em VR")
		# O headset dita o ritmo; vsync do monitor só atrapalharia
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		$Carro/OrigemXR.current = true
		$Carro/OrigemXR/CameraXR.make_current()
		_xr.session_begun.connect(_sessao_iniciada)
	else:
		print("Sem headset: dirigindo o carro em primeira pessoa")
		camera_carro.make_current()
		# Sem rastreamento, as mãos VR ficariam paradas na frente da câmera
		$Carro/OrigemXR.visible = false

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
	get_viewport().msaa_3d = Viewport.MSAA_4X

func _sessao_iniciada():
	_sincronizar_fisica(_xr.display_refresh_rate)
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
	elif event.keycode == KEY_TAB and not get_viewport().use_xr:
		if camera_carro.current:
			camera_debug.global_transform = camera_carro.global_transform
			camera_debug.set("rot_x", camera_debug.rotation.x)
			camera_debug.set("rot_y", camera_debug.rotation.y)
			camera_debug.make_current()
		else:
			camera_carro.make_current()
