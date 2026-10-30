class_name ParqueIndustrial
extends MapaCorrida
## Mapa do portal violeta: o Parque Industrial ao entardecer, com a pista em "i"
## (PistaIndustrial): a reta longa com as rampas de salto e a praça do pingo no fim,
## onde fica o portal de volta. Galpões, chaminés e pilhas de contêineres dos dois
## lados, e pórticos de carga passando por cima da pista.
## Estilo low poly: pátio de concreto em manchas chapadas, galpões e contêineres em
## cores vivas e foscas (metal espelhado cintila no headset), chaminés facetadas, a
## faixa neon verde da pista embaixo de cada pórtico e duas torres de resfriamento
## como marcos (uma em cada metade da reta). Tudo em MultiMesh, sem luz além do sol.

const GALPOES := 34
const CHAMINES := 14
const PILHAS := 60
## Distância entre os pórticos que cruzam a pista (m) e a altura livre embaixo
const PASSO_PORTICO := 300.0
const VAO_PORTICO := 10.0
## Paleta do entardecer industrial: contêineres, galpões, concreto, céu e o neon verde
## da pista
const CORES_CONTEINER: Array[Color] = [Color("e2483b"), Color("2f6fd1"), Color("f2b630"),
	Color("3bb273"), Color("8e5bd1"), Color("f07a2c")]
const CORES_GALPAO: Array[Color] = [Color("e9e6dc"), Color("dcd8cc"), Color("2f6fd1"),
	Color("2aa39a"), Color("d9483b")]
const CONCRETO := Color("8f98a6")
const CONCRETO_CLARO := Color("a3abb8")
const TIJOLO := Color("c4553a")
const AMARELO := Color("f2c230")
const CEU_ALTO := Color("3a2f6e")
const CEU_HORIZONTE := Color("ff8a50")
const NEBLINA := Color("e89a78")
const NEON := Color("3dff8a")

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
		["Erguendo as torres de resfriamento", _torres],
	]

func _nova_pista() -> PistaCorrida:
	return PistaIndustrial.new()

## No meio da praça do pingo do i
func _posicao_portal_volta() -> Vector3:
	return (pista as PistaIndustrial).centro_pingo()

func _montar_ambiente():
	# Céu em gradiente forte (ProceduralSky, sem textura): violeta para laranja
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = CEU_ALTO
	ceu.sky_horizon_color = CEU_HORIZONTE
	ceu.sky_curve = 0.1
	ceu.ground_horizon_color = Color("d98b5f")
	ceu.ground_bottom_color = Color("2e2a33")
	ceu.sun_angle_max = 16.0
	ceu.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.7
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Glow leve: só o neon passa do limiar (bloom forte cansa em VR)
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.35
	ambiente.glow_hdr_threshold = 1.2
	# Fumaça e poeira da indústria no horizonte
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = NEBLINA
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
	_chao_plano(CONCRETO, 5200.0, CONCRETO_CLARO)

## Galpões compridos dos dois lados da reta e chaminés com a ponta acesa
func _galpoes():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1942
	var caixa := BoxMesh.new()
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	for i in GALPOES:
		var lado := 1.0 if i % 2 == 0 else -1.0
		var x := lerpf(-1000.0, 1000.0, (i + rng.randf()) / GALPOES)
		var tamanho := Vector3(rng.randf_range(50.0, 90.0), rng.randf_range(12.0, 20.0), rng.randf_range(30.0, 50.0))
		var z := lado * (pista.largura * 0.5 + rng.randf_range(70.0, 160.0))
		pecas.append(Transform3D(Basis.from_scale(tamanho), Vector3(x, tamanho.y * 0.5, z)))
		cores.append(CORES_GALPAO[rng.randi() % CORES_GALPAO.size()])
	_instancias(caixa, pecas, cores, LowPoly.liso(Color.WHITE, true))

	var chamine := CylinderMesh.new()
	chamine.top_radius = 2.2
	chamine.bottom_radius = 3.2
	chamine.height = 1.0
	chamine.radial_segments = 8
	chamine.rings = 1
	# Farol de aviação na ponta: pirâmide acesa (emissão, sem luz real)
	var luz := CylinderMesh.new()
	luz.top_radius = 0.0
	luz.bottom_radius = 1.0
	luz.height = 1.6
	luz.radial_segments = 4
	luz.rings = 1
	var corpos: Array[Transform3D] = []
	var pontas: Array[Transform3D] = []
	for i in CHAMINES:
		var lado := 1.0 if i % 2 == 1 else -1.0
		var x := lerpf(-950.0, 950.0, (i + rng.randf()) / CHAMINES)
		var alto := rng.randf_range(40.0, 70.0)
		var z := lado * rng.randf_range(190.0, 300.0)
		corpos.append(Transform3D(Basis.from_scale(Vector3(1.0, alto, 1.0)), Vector3(x, alto * 0.5, z)))
		pontas.append(Transform3D(Basis(), Vector3(x, alto + 0.8, z)))
	_instancias(LowPoly.facetar(chamine), corpos, [], LowPoly.liso(TIJOLO))
	_instancias(luz, pontas, [], LowPoly.neon(Color("ff3a2a"), 3.0))

## Pilhas de contêineres coloridos perto dos muros
func _conteineres():
	var rng := RandomNumberGenerator.new()
	rng.seed = 40
	var caixa := BoxMesh.new()
	caixa.size = Vector3(12.0, 2.6, 2.5)
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
	_instancias(caixa, pecas, cores, LowPoly.liso(Color.WHITE, true))

## Pórticos de carga cruzando a pista: dois pilares fora dos muros e a viga lá em
## cima, amarelo de segurança fosco, com a faixa neon verde embaixo da viga (marca
## cada pórtico de longe; passa por cima, não no chão)
func _porticos():
	var amarelo := LowPoly.liso(AMARELO)
	var pilar := BoxMesh.new()
	pilar.size = Vector3(1.4, 1.0, 1.4)
	pilar.material = amarelo
	var viga := BoxMesh.new()
	viga.size = Vector3(1.0, 1.6, 1.6)
	viga.material = amarelo
	var filete := BoxMesh.new()
	filete.size = Vector3(1.0, 0.2, 0.5)
	var pilares: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	var filetes: Array[Transform3D] = []
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
		filetes.append(Transform3D(base * Basis.from_scale(Vector3(meio * 2.0, 1.0, 1.0)), Vector3(q.origin.x, VAO_PORTICO - 0.1, q.origin.z)))
		s += PASSO_PORTICO
	_instancias(pilar, pilares)
	_instancias(viga, vigas)
	_instancias(filete, filetes, [], LowPoly.neon(NEON, 2.5))

## Torres de resfriamento: os marcos do parque, uma de cada lado em cada metade da
## reta. Tronco facetado afinando na cintura e a borda de cima acesa em verde
func _torres():
	var baixo := CylinderMesh.new()
	baixo.bottom_radius = 30.0
	baixo.top_radius = 20.0
	baixo.height = 50.0
	baixo.radial_segments = 10
	baixo.rings = 1
	var cima := CylinderMesh.new()
	cima.bottom_radius = 20.0
	cima.top_radius = 23.0
	cima.height = 22.0
	cima.radial_segments = 10
	cima.rings = 1
	var borda := CylinderMesh.new()
	borda.bottom_radius = 23.4
	borda.top_radius = 23.4
	borda.height = 1.6
	borda.radial_segments = 10
	borda.rings = 1
	var branco := LowPoly.liso(Color("e9e6dc"))
	var malha_baixo := LowPoly.facetar(baixo)
	var malha_cima := LowPoly.facetar(cima)
	for lugar: Vector3 in [Vector3(-450.0, 0.0, -(pista.largura * 0.5 + 330.0)), Vector3(520.0, 0.0, pista.largura * 0.5 + 360.0)]:
		for parte: Array in [[malha_baixo, 25.0, branco], [malha_cima, 61.0, branco], [borda, 72.0, LowPoly.neon(NEON, 2.5)]]:
			var m := MeshInstance3D.new()
			m.mesh = parte[0]
			m.material_override = parte[2]
			m.position = lugar + Vector3.UP * float(parte[1])
			add_child(m)
