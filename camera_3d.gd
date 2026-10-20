extends Camera3D

@export var velocidade := 5.0
@export var sensibilidade := 0.003

var rot_x := 0.0
var rot_y := 0.0

func _ready():	
	rot_x = rotation.x
	rot_y = rotation.y

func _input(event):
	if not current or get_viewport().use_xr:
		return
	# Esc libera o cursor; um clique volta a capturá-lo.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rot_y -= event.relative.x * sensibilidade
		rot_x = clamp(rot_x - event.relative.y * sensibilidade, -1.5, 1.5)
		rotation = Vector3(rot_x, rot_y, 0)

func _process(delta):
	if not current or get_viewport().use_xr:
		return
	var b := global_transform.basis.orthonormalized()
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_D): dir += b.x
	if Input.is_key_pressed(KEY_E): dir += b.y
	if Input.is_key_pressed(KEY_Q): dir -= b.y

	var vel := velocidade * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += dir.normalized() * vel * delta
