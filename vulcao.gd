class_name Vulcao
extends MapaCorrida
## Mapa do portal carmesim: o I de Incrível. Um campo de lava ao anoitecer cortado pela
## pista em "i" (PistaVulcao), com seis campos de minas terrestres piscando em vermelho
## ao longo da reta e a praça do pingo no fim, onde fica o portal de volta.
## O vulcão fumegando fica no horizonte, à frente e à esquerda: ele acompanha o piloto
## (como o sol), porque a reta tem 2 km e a câmera só enxerga 600 m. Colunas de basalto
## e pedras no meio da lava, e brasas subindo em volta do carro.

## Lava um pouco abaixo do asfalto (a saia da pista fecha a borda)
const NIVEL_LAVA := -0.45
## Vulcão: direção a partir do piloto (a corrida vai para +X; -Z é a esquerda),
## distância, raio da base, altura e raio da cratera (m)
const DIRECAO_VULCAO := Vector3(0.6, 0.0, -0.8)
const DISTANCIA_VULCAO := 470.0
const BASE_VULCAO := 190.0
const ALTURA_VULCAO := 165.0
const CRATERA := 34.0
## Até onde vão as pedras e colunas (m da pista): mais longe o vulcão, que anda junto
## com o piloto, passaria por cima delas
const ALCANCE_CENARIO := 220.0
const PEDRAS := 140
const COLUNAS := 45
## Campos minados: [fração da corrida, padrão, espelhado]
const CAMPOS := [[0.12, 0, false], [0.27, 1, false], [0.42, 2, false],
	[0.58, 1, true], [0.74, 2, true], [0.9, 1, true]]
## (ds, d) de cada mina em volta do centro do campo (m). Fileiras desencontradas, mas
## sempre com faixa reta livre
const PADROES := [
	[Vector2(-5.0, -3.2), Vector2(-5.0, 4.4), Vector2(5.0, 0.6), Vector2(5.0, -7.0)],
	[Vector2(-8.0, -6.4), Vector2(-8.0, -0.9), Vector2(-8.0, 4.6),
		Vector2(0.0, -3.6), Vector2(0.0, 1.8), Vector2(0.0, 7.3),
		Vector2(8.0, -7.3), Vector2(8.0, -0.9), Vector2(8.0, 5.0)],
	[Vector2(-12.0, -8.0), Vector2(-12.0, -2.5), Vector2(-12.0, 3.0),
		Vector2(-4.0, -5.2), Vector2(-4.0, 0.4), Vector2(-4.0, 6.0),
		Vector2(4.0, -7.6), Vector2(4.0, -2.0), Vector2(4.0, 3.6), Vector2(4.0, 8.6),
		Vector2(12.0, -4.6), Vector2(12.0, 1.0), Vector2(12.0, 6.4)],
]

var obstaculos: ObstaculosPista
var campos: Array[CampoMinado] = []
## Vulcão e fumaça, levados junto com a câmera em _process
var horizonte: Node3D
var _brasas: GPUParticles3D

func _init():
	nome = "I de Incrível"
	faixa_corrida = "res://musicas/musica_7.mp3"
	fala_chegada = "vulcao"

func _etapas() -> Array:
	return [
		["Abrindo a pista na lava", _montar_circuito],
		["Derretendo o chão", _lava],
		["Erguendo o basalto", _basalto],
		["Acordando o vulcão", _vulcao],
		["Enterrando as minas", _montar_minas],
	]

func _nova_pista() -> PistaCorrida:
	return PistaVulcao.new()

## No meio da praça do pingo do i
func _posicao_portal_volta() -> Vector3:
	return (pista as PistaAberta).centro_pingo()

func _montar_ambiente():
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color(0.07, 0.04, 0.06)
	ceu.sky_horizon_color = Color(0.55, 0.16, 0.06)
	ceu.ground_horizon_color = Color(0.45, 0.12, 0.04)
	ceu.ground_bottom_color = Color(0.08, 0.03, 0.02)
	ceu.sun_angle_max = 18.0
	ceu.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.9
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.7
	ambiente.glow_hdr_threshold = 1.0
	# Cinza e fumaça no ar, avermelhadas pela lava
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = Color(0.4, 0.12, 0.06)
	ambiente.fog_depth_begin = 140.0
	ambiente.fog_depth_end = 900.0
	ambiente.fog_sky_affect = 0.5

## Sol baixo e avermelhado atrás do piloto: ilumina o vulcão sem ofuscar a reta
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-16.0, -105.0, 0.0)
	luz.light_color = Color(1.0, 0.5, 0.3)
	luz.light_energy = 0.9

func _process(_delta: float):
	if horizonte == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera:
		_seguir(camera.global_position)

## Põe o vulcão longe na mesma direção a partir de `ponto`, e as brasas em volta dele
func _seguir(ponto: Vector3):
	horizonte.global_position = Vector3(ponto.x, global_position.y + NIVEL_LAVA, ponto.z) + DIRECAO_VULCAO.normalized() * DISTANCIA_VULCAO
	if _brasas:
		_brasas.global_position = Vector3(ponto.x, global_position.y, ponto.z)

# --- Cenário ------------------------------------------------------------------------

## Chão de lava até bem além da neblina nas duas pontas, com colisão na altura dela
func _lava():
	var tamanho := 5600.0
	var piso := MeshInstance3D.new()
	piso.name = "Lava"
	var plano := PlaneMesh.new()
	plano.size = Vector2(tamanho, tamanho)
	var ruido := FastNoiseLite.new()
	ruido.frequency = 0.012
	ruido.fractal_octaves = 3
	var textura := NoiseTexture2D.new()
	textura.noise = ruido
	textura.seamless = true
	textura.width = 256
	textura.height = 256
	textura.generate_mipmaps = true
	var material := ShaderMaterial.new()
	material.shader = preload("res://lava.gdshader")
	material.set_shader_parameter("ruido", textura)
	plano.material = material
	piso.mesh = plano
	piso.position.y = NIVEL_LAVA
	piso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piso)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.position.y = NIVEL_LAVA
	var forma := CollisionShape3D.new()
	forma.shape = WorldBoundaryShape3D.new()
	corpo.add_child(forma)
	add_child(corpo)

## Pedras de basalto boiando na lava e grupos de colunas sextavadas, longe dos muros
func _basalto():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1883
	var rocha := StandardMaterial3D.new()
	rocha.albedo_color = Color(0.09, 0.08, 0.08)
	rocha.roughness = 0.95
	var pedra := SphereMesh.new()
	pedra.radius = 1.0
	pedra.height = 2.0
	pedra.radial_segments = 7
	pedra.rings = 4
	pedra.material = rocha
	var pecas: Array[Transform3D] = []
	var x_max := PistaVulcao.CORRIDA * 0.5 + 200.0
	var tentativas := 0
	while pecas.size() < PEDRAS and tentativas < 3000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-x_max, x_max), rng.randf_range(-ALCANCE_CENARIO, ALCANCE_CENARIO))
		var tamanho := Vector3(rng.randf_range(2.0, 9.0), rng.randf_range(0.8, 3.0), rng.randf_range(2.0, 8.0))
		if distancia_pista(p.x, p.y) < pista.largura * 0.5 + 6.0 + maxf(tamanho.x, tamanho.z):
			continue
		var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		pecas.append(Transform3D(giro * Basis.from_scale(tamanho), Vector3(p.x, NIVEL_LAVA, p.y)))
	_instancias(pedra, pecas)

	var coluna := CylinderMesh.new()
	coluna.top_radius = 1.0
	coluna.bottom_radius = 1.0
	coluna.height = 1.0
	coluna.radial_segments = 6
	coluna.rings = 1
	var basalto := StandardMaterial3D.new()
	basalto.albedo_color = Color(0.13, 0.11, 0.11)
	basalto.roughness = 0.85
	basalto.metallic = 0.15
	coluna.material = basalto
	var colunas: Array[Transform3D] = []
	tentativas = 0
	var grupos := 0
	while grupos < COLUNAS and tentativas < 2000:
		tentativas += 1
		var centro := Vector2(rng.randf_range(-x_max, x_max), rng.randf_range(-ALCANCE_CENARIO, ALCANCE_CENARIO))
		if distancia_pista(centro.x, centro.y) < pista.largura * 0.5 + 25.0:
			continue
		grupos += 1
		# Um feixe de colunas encostadas, as do meio mais altas
		var alto := rng.randf_range(6.0, 22.0)
		for k in rng.randi_range(4, 9):
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.0, 4.0)
			var raio := rng.randf_range(1.0, 1.8)
			var h := alto * (1.0 - r / 6.0) * rng.randf_range(0.7, 1.0)
			var giro := Basis(Vector3.UP, rng.randf() * TAU)
			colunas.append(Transform3D(giro * Basis.from_scale(Vector3(raio, h, raio)),
				Vector3(centro.x + cos(a) * r, NIVEL_LAVA + h * 0.5, centro.y + sin(a) * r)))
	_instancias(coluna, colunas)

## O vulcão do horizonte: cone de encosta côncava e borda irregular, cratera acesa,
## coluna de fumaça e brasas em volta do carro
func _vulcao():
	horizonte = Node3D.new()
	horizonte.name = "Vulcao"
	add_child(horizonte)
	var cone := MeshInstance3D.new()
	cone.mesh = _malha_vulcao()
	var encosta := ShaderMaterial.new()
	encosta.shader = preload("res://vulcao.gdshader")
	cone.material_override = encosta
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizonte.add_child(cone)
	# Lago de lava dentro da cratera
	var lago := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = CRATERA * 0.95
	disco.bottom_radius = CRATERA * 0.6
	disco.height = 2.0
	disco.radial_segments = 24
	disco.rings = 1
	disco.material = ObstaculoPista.material_luz(Color(1.0, 0.4, 0.06), 6.0)
	lago.mesh = disco
	lago.position.y = ALTURA_VULCAO - 6.0
	lago.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizonte.add_child(lago)
	horizonte.add_child(_fumaca())
	_brasas = _novas_brasas()
	add_child(_brasas)
	_seguir(global_transform * pista.grid(ADVERSARIOS).origin)

## Cone em anéis: raio caindo de BASE_VULCAO até a CRATERA numa curva côncava, com a
## borda irregular (ruído pela volta). Por dentro da borda desce um pouco, para a cratera
func _malha_vulcao() -> ArrayMesh:
	var voltas := 56
	var aneis := 14
	var ruido := FastNoiseLite.new()
	ruido.seed = 7
	ruido.frequency = 1.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ponto := func(i: int, j: int) -> Vector3:
		var a := TAU * i / voltas
		var u := float(j) / aneis
		var irregular := 1.0 + 0.12 * ruido.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0 + u * 3.0)
		var raio := lerpf(BASE_VULCAO, CRATERA, pow(u, 0.55)) * irregular
		var h := ALTURA_VULCAO * u * (1.0 + 0.06 * ruido.get_noise_2d(a * 3.0, 10.0) * u)
		return Vector3(cos(a) * raio, h, sin(a) * raio)
	for j in aneis:
		for i in voltas:
			var cantos := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			var v: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for c in cantos:
				v.append(ponto.call(c[0] % voltas, c[1]))
				uv.append(Vector2(float(c[0]) / voltas, float(c[1]) / aneis))
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_uv(uv[k])
				st.add_vertex(v[k])
	# Parede de dentro da cratera, descendo até o lago
	for i in voltas:
		for k in [[i, 1.0], [i + 1, 0.0], [i + 1, 1.0], [i, 1.0], [i, 0.0], [i + 1, 0.0]]:
			var topo: Vector3 = ponto.call(int(k[0]) % voltas, aneis)
			var fundo := Vector3(topo.x * 0.92, ALTURA_VULCAO - 6.0, topo.z * 0.92)
			st.set_uv(Vector2(float(k[0]) / voltas, 1.0))
			st.add_vertex(topo if k[1] > 0.5 else fundo)
	st.generate_normals()
	return st.commit()

## Coluna de fumaça saindo da cratera, iluminada de baixo pela lava
func _fumaca() -> GPUParticles3D:
	var p := Explosao._particulas(48, 26.0, Vector2(30.0, 55.0), false)
	p.emitting = true
	p.preprocess = 26.0
	p.position.y = ALTURA_VULCAO
	p.visibility_aabb = AABB(Vector3(-250.0, -20.0, -250.0), Vector3(500.0, 450.0, 500.0))
	var m: ParticleProcessMaterial = p.process_material
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = CRATERA * 0.6
	m.direction = Vector3(0.25, 1.0, 0.0)
	m.spread = 12.0
	m.initial_velocity_min = 7.0
	m.initial_velocity_max = 11.0
	m.damping_min = 0.1
	m.damping_max = 0.2
	m.scale_curve = Explosao._curva(0.5, 2.2)
	m.color_ramp = Explosao._rampa([Color(1.0, 0.4, 0.12, 0.0), Color(0.45, 0.16, 0.08, 0.75),
		Color(0.14, 0.1, 0.1, 0.6), Color(0.08, 0.07, 0.07, 0.0)])
	return p

## Brasas subindo da lava em volta do carro (ficam no mundo; o emissor anda junto)
func _novas_brasas() -> GPUParticles3D:
	var p := Explosao._particulas(70, 5.0, Vector2(0.03, 0.08), false)
	p.emitting = true
	p.preprocess = 5.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-50.0, -5.0, -50.0), Vector3(100.0, 30.0, 100.0))
	var m: ParticleProcessMaterial = p.process_material
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(40.0, 0.5, 40.0)
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 3.0
	m.gravity = Vector3(0.3, 0.4, 0.0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.color_ramp = Explosao._rampa([Color(1.8, 0.7, 0.2, 0.0), Color(1.6, 0.5, 0.1, 1.0), Color(0.6, 0.1, 0.02, 0.0)])
	return p

# --- Minas --------------------------------------------------------------------------

func _montar_minas():
	obstaculos = ObstaculosPista.new()
	obstaculos.pista = pista
	obstaculos.trafego = trafego
	pista.add_child(obstaculos)
	if trafego:
		trafego.obstaculos = obstaculos
	for campo in CAMPOS:
		var minas: Array[Vector2] = []
		for m: Vector2 in PADROES[campo[1]]:
			minas.append(Vector2(m.x, -m.y if campo[2] else m.y))
		var minado := CampoMinado.new(minas)
		obstaculos.adicionar(minado, pista.s_largada + PistaVulcao.CORRIDA * float(campo[0]))
		campos.append(minado)
