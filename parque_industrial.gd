class_name ParqueIndustrial
extends MapaCorrida
## Mapa do portal violeta: o Parque Industrial ao entardecer, com a pista em "i"
## (PistaIndustrial): a reta longa com as rampas de salto e a praça do pingo no fim,
## onde fica o portal de volta. Galpões, chaminés e pilhas de contêineres dos dois
## lados, e pórticos de carga passando por cima da pista.

const GALPOES := 34
const CHAMINES := 14
const PILHAS := 60
## Distância entre os pórticos que cruzam a pista (m) e a altura livre embaixo
const PASSO_PORTICO := 300.0
const VAO_PORTICO := 10.0
const CORES_CONTEINER: Array[Color] = [Color(0.75, 0.18, 0.12), Color(0.1, 0.35, 0.6),
	Color(0.85, 0.6, 0.1), Color(0.2, 0.5, 0.3), Color(0.55, 0.55, 0.58)]

func _init():
	nome = "Parque Industrial"
	faixa_corrida = "res://musicas/musica_6.mp3"
	fala_chegada = "parque_industrial"

func _etapas() -> Array:
	return [
		["Pavimentando a reta", _montar_circuito],
		["Concretando o pátio", _patio],
		["Levantando os galpões", _galpoes],
		["Empilhando contêineres", _conteineres],
		["Montando os pórticos", _porticos],
	]

func _nova_pista() -> PistaCorrida:
	return PistaIndustrial.new()

## No meio da praça do pingo do i
func _posicao_portal_volta() -> Vector3:
	return (pista as PistaIndustrial).centro_pingo()

func _montar_ambiente():
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color(0.3, 0.28, 0.42)
	ceu.sky_horizon_color = Color(0.95, 0.55, 0.32)
	ceu.ground_horizon_color = Color(0.6, 0.45, 0.35)
	ceu.ground_bottom_color = Color(0.2, 0.19, 0.2)
	ceu.sun_angle_max = 25.0
	ceu.sun_curve = 0.1
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.7
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.55
	ambiente.glow_hdr_threshold = 1.0
	# Fumaça e poeira da indústria no horizonte
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = Color(0.8, 0.58, 0.45)
	ambiente.fog_depth_begin = 200.0
	ambiente.fog_depth_end = 650.0
	ambiente.fog_sky_affect = 0.45

## Sol baixo de lado: a reta corre em X, então ele não fica de frente para o piloto
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-18.0, 15.0, 0.0)
	luz.light_color = Color(1.0, 0.7, 0.48)
	luz.light_energy = 1.2

func _patio():
	# A reta tem ~2 km: o piso vai bem além da neblina nas duas pontas
	_chao_plano(Color(0.42, 0.4, 0.38), 5200.0)

## Galpões compridos dos dois lados da reta e chaminés com a ponta acesa
func _galpoes():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	var caixa := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.75
	material.metallic = 0.2
	caixa.material = material
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	for i in GALPOES:
		var lado := 1.0 if i % 2 == 0 else -1.0
		var x := lerpf(-1000.0, 1000.0, (i + rng.randf()) / GALPOES)
		var tamanho := Vector3(rng.randf_range(50.0, 90.0), rng.randf_range(12.0, 20.0), rng.randf_range(30.0, 50.0))
		var z := lado * (pista.largura * 0.5 + rng.randf_range(70.0, 160.0))
		pecas.append(Transform3D(Basis.from_scale(tamanho), Vector3(x, tamanho.y * 0.5, z)))
		var tom := rng.randf_range(0.55, 0.8)
		cores.append(Color(tom, tom * 0.98, tom * 0.95) if rng.randf() < 0.7 else Color(0.15, 0.3, 0.5))
	_instancias(caixa, pecas, cores)

	var chamine := CylinderMesh.new()
	chamine.top_radius = 2.2
	chamine.bottom_radius = 3.2
	chamine.height = 1.0
	chamine.radial_segments = 12
	chamine.rings = 1
	var tijolo := StandardMaterial3D.new()
	tijolo.albedo_color = Color(0.5, 0.25, 0.18)
	tijolo.roughness = 0.9
	chamine.material = tijolo
	var luz := SphereMesh.new()
	luz.radius = 0.8
	luz.height = 1.6
	var vermelho := StandardMaterial3D.new()
	vermelho.albedo_color = Color(1.0, 0.15, 0.1)
	vermelho.emission_enabled = true
	vermelho.emission = Color(1.0, 0.15, 0.1)
	vermelho.emission_energy_multiplier = 4.0
	luz.material = vermelho
	var corpos: Array[Transform3D] = []
	var pontas: Array[Transform3D] = []
	for i in CHAMINES:
		var lado := 1.0 if i % 2 == 1 else -1.0
		var x := lerpf(-950.0, 950.0, (i + rng.randf()) / CHAMINES)
		var alto := rng.randf_range(40.0, 70.0)
		var z := lado * rng.randf_range(190.0, 300.0)
		corpos.append(Transform3D(Basis.from_scale(Vector3(1.0, alto, 1.0)), Vector3(x, alto * 0.5, z)))
		pontas.append(Transform3D(Basis(), Vector3(x, alto + 0.8, z)))
	_instancias(chamine, corpos)
	_instancias(luz, pontas)

## Pilhas de contêineres coloridos perto dos muros
func _conteineres():
	var rng := RandomNumberGenerator.new()
	rng.seed = 40
	var caixa := BoxMesh.new()
	caixa.size = Vector3(12.0, 2.6, 2.5)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	material.metallic = 0.3
	caixa.material = material
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	var feitas := 0
	while feitas < PILHAS:
		var lado := 1.0 if rng.randf() < 0.5 else -1.0
		var x := rng.randf_range(-980.0, 980.0)
		var base_z := lado * (pista.largura * 0.5 + rng.randf_range(16.0, 70.0))
		# A reta ondula: confere a distância de verdade até o muro
		if distancia_pista(x, base_z) < pista.largura * 0.5 + 12.0:
			continue
		feitas += 1
		var giro := Basis(Vector3.UP, rng.randf_range(-0.1, 0.1) + (0.0 if rng.randf() < 0.7 else PI * 0.5))
		for andar in rng.randi_range(1, 4):
			var deslize := Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.3, 0.3))
			pecas.append(Transform3D(giro, Vector3(x, 1.3 + andar * 2.6, base_z) + deslize))
			cores.append(CORES_CONTEINER[rng.randi() % CORES_CONTEINER.size()])
	_instancias(caixa, pecas, cores)

## Pórticos de carga cruzando a pista: dois pilares fora dos muros e a viga lá em cima
func _porticos():
	var amarelo := StandardMaterial3D.new()
	amarelo.albedo_color = Color(0.95, 0.72, 0.1)
	amarelo.metallic = 0.5
	amarelo.roughness = 0.45
	var pilar := BoxMesh.new()
	pilar.size = Vector3(1.4, 1.0, 1.4)
	pilar.material = amarelo
	var viga := BoxMesh.new()
	viga.size = Vector3(1.0, 1.6, 1.6)
	viga.material = amarelo
	var pilares: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	var s := pista.s_largada + PASSO_PORTICO * 0.5
	while s < pista.s_chegada:
		var q := pista.quadro(s)
		var lado := Vector3(q.basis.x.x, 0.0, q.basis.x.z).normalized()
		var meio := pista.largura * 0.5 + 3.0
		for sinal: float in [-1.0, 1.0]:
			var p := q.origin + lado * meio * sinal
			pilares.append(Transform3D(Basis.from_scale(Vector3(1.0, VAO_PORTICO + 1.6, 1.0)), Vector3(p.x, (VAO_PORTICO + 1.6) * 0.5, p.z)))
		var base := Basis(lado, Vector3.UP, lado.cross(Vector3.UP))
		vigas.append(Transform3D(base * Basis.from_scale(Vector3(meio * 2.0 + 1.4, 1.0, 1.0)), Vector3(q.origin.x, VAO_PORTICO + 0.8, q.origin.z)))
		s += PASSO_PORTICO
	_instancias(pilar, pilares)
	_instancias(viga, vigas)
