extends Node3D
## Gera o chão hexagonal em chunks ao redor da câmera ativa.
## Chunks perto/à frente da câmera são criados primeiro; os distantes são liberados.

const SQRT3 := 1.7320508
const HEX_SHADER := preload("res://hex_tile.gdshader")

const BODY_COLORS := [
	Color("#14143C"), Color("#14233C"), Color("#1A204A"), Color("#131735"),
	Color("#162A6B"), Color("#212165"), Color("#002060"),
]
const GLOW_WARM := [
	Color("#EB5C2E"), Color("#F59E33"), Color("#F28F32"), Color("#F07F31"), Color("#FABE63"),
]
const GLOW_COLD := [Color("#2F8DFF"), Color("#26459E")]

@export var hex_size := 0.4
## Chunks pequenos: cada um é gerado em ~1 ms, sem engasgar o frame no VR
@export var chunk_hexes := 12
## Mantenha alinhado com fog_depth_end do WorldEnvironment para esconder a borda
@export var view_distance := 45.0
@export var chunks_per_frame := 2
@export var plaza_radius := 7.0
## Variação total do relevo (em metros) ao longo de grandes distâncias
@export var terrain_amplitude := 0.6
## Desnível aleatório máximo de cada hexágono em relação ao relevo
@export var step_jitter := 0.02
@export_range(0.0, 0.2) var hole_chance := 0.02
@export var world_seed := 1337
@export_flags_3d_physics var collision_layer := 1

var _chunks := {}
var _pending: Array[Vector2i] = []
var _last_center := Vector2i(2147483647, 0)
var _noise := FastNoiseLite.new()
var _mesh := CylinderMesh.new()

func _ready():
	_noise.seed = world_seed
	_noise.frequency = 0.025
	_noise.fractal_octaves = 3

	_mesh.top_radius = 1.0
	_mesh.bottom_radius = 1.0
	_mesh.height = 2.0
	_mesh.radial_segments = 6
	_mesh.rings = 0
	var material := ShaderMaterial.new()
	material.shader = HEX_SHADER
	_mesh.material = material

## Saindo para outro mapa: apaga todos os pedaços (e a colisão deles) e para de gerar
func desligar():
	for c in _chunks:
		_chunks[c].queue_free()
	_chunks.clear()
	_pending.clear()
	_last_center = Vector2i(2147483647, 0)
	set_process(false)

## Voltando: gera de novo em volta da câmera
func ligar():
	set_process(true)

func carregando() -> bool:
	return not _pending.is_empty()

func _process(_delta):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := _world_to_chunk(cam.global_position)
	if center != _last_center:
		_last_center = center
		_refresh(cam)

	for i in chunks_per_frame:
		if _pending.is_empty():
			break
		var c: Vector2i = _pending.pop_back()
		if not _chunks.has(c):
			_chunks[c] = _build_chunk(c)

func _refresh(cam: Camera3D):
	var pos := Vector2(cam.global_position.x, cam.global_position.z)
	var fwd := Vector2(-cam.global_basis.z.x, -cam.global_basis.z.z).normalized()
	var span := _chunk_span()
	var limit := view_distance + span

	for c in _chunks.keys():
		if _chunk_center(c).distance_to(pos) > limit + span * 0.5:
			_chunks[c].queue_free()
			_chunks.erase(c)

	var reach := int(ceil(limit / span)) * 2
	var center := _last_center
	_pending.clear()
	for dq in range(-reach, reach + 1):
		for dr in range(-reach, reach + 1):
			var c := Vector2i(center.x + dq, center.y + dr)
			if not _chunks.has(c) and _chunk_center(c).distance_to(pos) <= limit:
				_pending.append(c)

	# Melhor candidato no fim do array (pop_back): perto e à frente da câmera
	var score := func(c: Vector2i) -> float:
		var to := _chunk_center(c) - pos
		return to.length() - to.normalized().dot(fwd) * span
	_pending.sort_custom(func(a, b): return score.call(a) > score.call(b))

func _build_chunk(c: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, world_seed))

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var customs: Array[Color] = []
	var faces := PackedVector3Array()

	for q in chunk_hexes:
		for r in chunk_hexes:
			var w := _axial_to_world(c.x * chunk_hexes + q, c.y * chunk_hexes + r)
			var d := w.length()
			if d < 2.5:
				continue # escondido sob a esfera
			var wild := smoothstep(plaza_radius, plaza_radius * 3.0, d)

			# Buracos raros e isolados, só fora da praça inicial
			if rng.randf() < hole_chance * wild:
				continue

			# Planalto: ondulação suave e degraus pequenos entre vizinhos
			var top := _noise.get_noise_2d(w.x, w.y) * terrain_amplitude * wild \
				+ rng.randf_range(-step_jitter, step_jitter)
			var bottom := top - rng.randf_range(4.0, 7.0)
			var glow := 0.0 if rng.randf() < 0.2 else rng.randf_range(0.15, 0.55)

			var s := hex_size * rng.randf_range(0.82, 0.95)
			var h := top - bottom
			var basis := Basis.from_scale(Vector3(s, h * 0.5, s))
			transforms.append(Transform3D(basis, Vector3(w.x, (top + bottom) * 0.5, w.y)))
			_hex_faces(faces, w, top, bottom)

			var body: Color = BODY_COLORS[rng.randi() % BODY_COLORS.size()]
			body.a = glow
			colors.append(body)

			var palette: Array = GLOW_WARM if rng.randf() < 0.75 else GLOW_COLD
			var neon: Color = palette[rng.randi() % palette.size()]
			neon.a = rng.randf_range(0.0, 0.6)
			customs.append(neon)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
		mm.set_instance_custom_data(i, customs[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

	# Colisão do trecho: sai junto com o chunk quando ele é liberado
	var corpo := StaticBody3D.new()
	corpo.collision_layer = collision_layer
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	concava.set_faces(faces)
	forma.shape = concava
	corpo.add_child(forma)
	mmi.add_child(corpo)

	mmi.set_instance_shader_parameter("reveal", 0.0)
	mmi.create_tween().tween_method(
		func(v: float): mmi.set_instance_shader_parameter("reveal", v), 0.0, 1.0, 1.4)
	return mmi

## Prisma de colisão do hexágono. Usa o raio cheio (hex_size) e não o visual,
## para as frestas entre hexágonos não prenderem as rodas; buracos continuam buracos.
func _hex_faces(faces: PackedVector3Array, w: Vector2, top: float, bottom: float):
	var centro := Vector3(w.x, top, w.y)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var p0 := Vector3(w.x + sin(a0) * hex_size, top, w.y + cos(a0) * hex_size)
		var p1 := Vector3(w.x + sin(a1) * hex_size, top, w.y + cos(a1) * hex_size)
		var q0 := Vector3(p0.x, bottom, p0.z)
		var q1 := Vector3(p1.x, bottom, p1.z)
		faces.append_array([centro, p1, p0, p0, p1, q1, p0, q1, q0])

## Altura do relevo suave em (x, z), sem o desnível aleatório de cada hexágono
func altura(x: float, z: float) -> float:
	var wild := smoothstep(plaza_radius, plaza_radius * 3.0, Vector2(x, z).length())
	return _noise.get_noise_2d(x, z) * terrain_amplitude * wild

func _axial_to_world(q: float, r: float) -> Vector2:
	return Vector2(hex_size * SQRT3 * (q + r * 0.5), hex_size * 1.5 * r)

func _world_to_chunk(p: Vector3) -> Vector2i:
	var r := p.z / (hex_size * 1.5)
	var q := p.x / (hex_size * SQRT3) - r * 0.5
	return Vector2i(floori(q / chunk_hexes), floori(r / chunk_hexes))

func _chunk_center(c: Vector2i) -> Vector2:
	var half := chunk_hexes * 0.5
	return _axial_to_world(c.x * chunk_hexes + half, c.y * chunk_hexes + half)

func _chunk_span() -> float:
	return hex_size * SQRT3 * chunk_hexes
