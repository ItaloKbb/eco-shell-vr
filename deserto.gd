class_name Deserto
extends MapaCorrida
## Mapa do primeiro portal: um deserto ao meio-dia com dunas, mesas de rocha vermelha no
## horizonte e cactos, em volta do circuito em infinito (pista_corrida.gd). No miolo de
## um dos laços fica o portal de volta. Tudo gerado em código na primeira visita.

## Tamanho do chão (m) e quantos quadrados por lado
const TAMANHO := 1600.0
const DIVISOES := 128

var _ruido := FastNoiseLite.new()
var _ruido_fino := FastNoiseLite.new()

func _init():
	nome = "Deserto"
	_ruido.seed = 326
	_ruido.frequency = 0.004
	_ruido_fino.seed = 81
	_ruido_fino.frequency = 0.02

func _etapas() -> Array:
	return [
		["Gerando terreno", _terreno],
		["Montando horizonte", _mesas],
		["Distribuindo vegetação", _cactos],
		["Preparando circuito", _montar_circuito],
	]

## Portal de volta no miolo do laço da direita, longe da pista (o puxão não alcança)
func _posicao_portal_volta() -> Vector3:
	return Vector3(PistaCorrida.A * 0.6, 0.0, 0.0)

## Altura do chão no ponto do mundo: plano em volta da pista, dunas mais longe
func altura(x: float, z: float) -> float:
	var p := Vector2(x - global_position.x, z - global_position.z)
	# Distância até uma caixa que cobre o circuito (com folga)
	var meia := Vector2(PistaCorrida.A + 35.0, PistaCorrida.A * 0.36 + 35.0)
	var q := (p.abs() - meia).max(Vector2.ZERO)
	var duna := smoothstep(0.0, 80.0, q.length())
	var crista := 1.0 - absf(_ruido.get_noise_2dv(p))
	return (crista * crista * 9.0 + _ruido_fino.get_noise_2dv(p) * 1.2) * duna

func _montar_ambiente():
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color(0.25, 0.48, 0.85)
	ceu.sky_horizon_color = Color(0.92, 0.8, 0.62)
	ceu.ground_horizon_color = Color(0.85, 0.7, 0.5)
	ceu.ground_bottom_color = Color(0.55, 0.42, 0.3)
	ceu.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.9
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.4
	ambiente.glow_hdr_threshold = 1.2
	# Poeira quente no horizonte (esconde o fim do chão e o limite da câmera)
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = Color(0.9, 0.76, 0.58)
	ambiente.fog_depth_begin = 250.0
	ambiente.fog_depth_end = 620.0
	ambiente.fog_sky_affect = 0.3

func _terreno():
	var passo := TAMANHO / DIVISOES
	var lado := DIVISOES + 1
	var alturas := PackedFloat32Array()
	alturas.resize(lado * lado)
	for iz in lado:
		for ix in lado:
			var x := -TAMANHO * 0.5 + ix * passo
			var z := -TAMANHO * 0.5 + iz * passo
			alturas[iz * lado + ix] = altura(x + global_position.x, z + global_position.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var ponto := func(ix: int, iz: int) -> Vector3:
		return Vector3(-TAMANHO * 0.5 + ix * passo, alturas[iz * lado + ix], -TAMANHO * 0.5 + iz * passo)
	for iz in DIVISOES:
		for ix in DIVISOES:
			var a: Vector3 = ponto.call(ix, iz)
			var b: Vector3 = ponto.call(ix + 1, iz)
			var c: Vector3 = ponto.call(ix + 1, iz + 1)
			var d: Vector3 = ponto.call(ix, iz + 1)
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
			faces.append_array([a, b, c, a, c, d])
	st.generate_normals()
	var malha := MeshInstance3D.new()
	malha.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://areia.gdshader")
	malha.material_override = material
	add_child(malha)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	concava.set_faces(faces)
	forma.shape = concava
	corpo.add_child(forma)
	add_child(corpo)

## Mesas de arenito espalhadas no horizonte
func _mesas():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var material := ShaderMaterial.new()
	material.shader = preload("res://rocha.gdshader")
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.25, 0.25)
		var d := rng.randf_range(330.0, 540.0)
		var cilindro := CylinderMesh.new()
		var raio := rng.randf_range(30.0, 70.0)
		cilindro.bottom_radius = raio
		cilindro.top_radius = raio * rng.randf_range(0.7, 0.9)
		cilindro.height = rng.randf_range(40.0, 110.0)
		cilindro.radial_segments = rng.randi_range(7, 11)
		cilindro.rings = 3
		var m := MeshInstance3D.new()
		m.mesh = cilindro
		m.material_override = material
		var x := cos(a) * d
		var z := sin(a) * d
		m.position = Vector3(x, cilindro.height * 0.5 - 4.0, z)
		m.rotation.y = rng.randf() * TAU
		m.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		add_child(m)

## Cactos saguaro (tronco e braços em cápsulas) fora da pista
func _cactos():
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var capsula := CapsuleMesh.new()
	capsula.radius = 0.35
	capsula.height = 1.0
	capsula.radial_segments = 10
	capsula.rings = 2
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.24, 0.42, 0.2)
	verde.roughness = 0.8
	capsula.material = verde
	var pecas: Array[Transform3D] = []
	var meia := Vector2(PistaCorrida.A + 25.0, PistaCorrida.A * 0.36 + 25.0)
	var feitos := 0
	while feitos < 45:
		var p := Vector2(rng.randf_range(-320.0, 320.0), rng.randf_range(-260.0, 260.0))
		if absf(p.x) < meia.x and absf(p.y) < meia.y:
			continue
		feitos += 1
		var chao := altura(p.x + global_position.x, p.y + global_position.z)
		var alto := rng.randf_range(3.5, 7.0)
		var base := Vector3(p.x, chao, p.y)
		var giro := Basis(Vector3.UP, rng.randf() * TAU)
		pecas.append(Transform3D(giro.scaled(Vector3(1.0, alto, 1.0)), base + Vector3.UP * alto * 0.5))
		for braco in rng.randi_range(0, 2):
			var lado := (giro.x if braco == 0 else -giro.x)
			var h := alto * rng.randf_range(0.4, 0.65)
			var cotovelo := base + Vector3.UP * h + lado * 0.8
			# Pedaço horizontal saindo do tronco e pedaço vertical subindo
			pecas.append(Transform3D(Basis(giro.z, PI * 0.5) * Basis.from_scale(Vector3(0.8, 1.0, 0.8)), base + Vector3.UP * h + lado * 0.4))
			var sobe := rng.randf_range(1.2, 2.2)
			pecas.append(Transform3D(Basis.from_scale(Vector3(0.8, sobe, 0.8)), cotovelo + Vector3.UP * sobe * 0.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = capsula
	mm.instance_count = pecas.size()
	for k in pecas.size():
		mm.set_instance_transform(k, pecas[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	add_child(no)

