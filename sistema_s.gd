class_name SistemaS
extends MapaCorrida
## Mapa do portal ciano: o Sistema S, um campus enorme no fim da tarde cortado pela
## pista em S (PistaSistemaS), larga e ponta a ponta. Prédios de blocos em volta e
## árvores nos miolos das curvas. O portal de volta fica no fim da reta de frenagem.
## Estilo low poly: gramado em manchas chapadas, prédios em cores vivas (azul SENAI,
## laranja, branco, turquesa, amarelo) com coroa neon âmbar em alguns, árvores de
## copa facetada e a torre do campus, alta e azul com a coroa acesa, como marco no
## meio do S. Tudo em MultiMesh, sem luz além do sol.

## Quanto antes do fim da pista fica o portal de volta (m)
const PORTAL_ANTES_DO_FIM := 25.0
const PREDIOS := 70
const ARVORES := 160
## Paleta do campus no fim da tarde: fachadas (azul SENAI, laranja, branco, turquesa,
## amarelo), gramado em dois verdes, copas, céu e o neon âmbar da pista
const FACHADAS: Array[Color] = [Color("1e6ad2"), Color("f28c28"), Color("f2f4f8"),
	Color("2bb3c0"), Color("f5c542"), Color("3f86e8")]
const GRAMA := Color("5cc24a")
const GRAMA_CLARA := Color("7ed35a")
const COPAS: Array[Color] = [Color("3fae55"), Color("5cc24a"), Color("2e9450"), Color("8fd45a")]
const CEU_ALTO := Color("2a64d8")
const CEU_HORIZONTE := Color("ffb37a")
const NEBLINA := Color("ffc9a0")
const NEON := Color("ffb52e")
## Um prédio a cada quantos ganha a coroa neon no telhado
const COROA_A_CADA := 3

func _init():
	nome = "Sistema S"
	faixa_corrida = "res://musicas/musica_4.mp3"
	fala_chegada = "sistema_s"

func _etapas() -> Array:
	return [
		["Traçando o S", _montar_circuito],
		["Gramando o campus", _gramado],
		["Erguendo os prédios", _predios],
		["Plantando as árvores", _arvores],
		["Erguendo a torre do campus", _torre],
	]

func _nova_pista() -> PistaCorrida:
	return PistaSistemaS.new()

## No fim da reta de frenagem, depois de onde os adversários estacionam
func _posicao_portal_volta() -> Vector3:
	return pista.pontos[pista.amostra_em(pista.comprimento - PORTAL_ANTES_DO_FIM)]

func _montar_ambiente():
	# Céu em gradiente forte (ProceduralSky, sem textura) e sol estilizado
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = CEU_ALTO
	ceu.sky_horizon_color = CEU_HORIZONTE
	ceu.sky_curve = 0.12
	ceu.ground_horizon_color = Color("c9d98a")
	ceu.ground_bottom_color = Color("3e6b3a")
	ceu.sun_angle_max = 14.0
	ceu.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.85
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Glow leve: só o neon passa do limiar (bloom forte cansa em VR)
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.35
	ambiente.glow_hdr_threshold = 1.2
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = NEBLINA
	ambiente.fog_depth_begin = 300.0
	ambiente.fog_depth_end = 750.0
	ambiente.fog_sky_affect = 0.3

## Sol de fim de tarde, ainda alto o bastante para não ofuscar na reta
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-28.0, 60.0, 0.0)
	luz.light_color = Color(1.0, 0.82, 0.62)
	luz.light_energy = 1.35

func _gramado():
	_chao_plano(GRAMA, 3200.0, GRAMA_CLARA)

## Prédios de blocos (caixas com cor chapada por fachada) em volta do S, longe dos
## muros; um a cada COROA_A_CADA com a coroa neon âmbar no telhado
func _predios():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1946
	var caixa := BoxMesh.new()
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	var coroas: Array[Transform3D] = []
	var tentativas := 0
	while pecas.size() < PREDIOS and tentativas < 2000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-650.0, 650.0), rng.randf_range(-750.0, 650.0))
		var tamanho := Vector3(rng.randf_range(18.0, 50.0), rng.randf_range(10.0, 45.0), rng.randf_range(18.0, 40.0))
		if distancia_pista(p.x, p.y) < pista.largura * 0.5 + 18.0 + tamanho.length() * 0.5:
			continue
		var giro := Basis(Vector3.UP, rng.randf() * TAU)
		pecas.append(Transform3D(giro * Basis.from_scale(tamanho), Vector3(p.x, tamanho.y * 0.5, p.y)))
		cores.append(FACHADAS[rng.randi() % FACHADAS.size()])
		if pecas.size() % COROA_A_CADA == 0:
			# Faixa acesa na beira do telhado, um pouco maior que o prédio
			coroas.append(Transform3D(giro * Basis.from_scale(Vector3(tamanho.x + 0.5, 0.6, tamanho.z + 0.5)), Vector3(p.x, tamanho.y + 0.1, p.y)))
	_instancias(caixa, pecas, cores, LowPoly.liso(Color.WHITE, true))
	_instancias(caixa, coroas, [], LowPoly.neon(NEON, 2.2))

## Árvores (tronco e copa) espalhadas, mais nos miolos das curvas do S
func _arvores():
	var rng := RandomNumberGenerator.new()
	rng.seed = 326
	var tronco := CylinderMesh.new()
	tronco.top_radius = 0.25
	tronco.bottom_radius = 0.35
	tronco.height = 1.0
	tronco.radial_segments = 5
	tronco.rings = 1
	# Copa low poly: esfera de poucos gomos, facetada, com o verde variando por árvore
	var copa := SphereMesh.new()
	copa.radius = 1.0
	copa.height = 2.0
	copa.radial_segments = 6
	copa.rings = 3
	var troncos: Array[Transform3D] = []
	var copas: Array[Transform3D] = []
	var cores_copas: Array[Color] = []
	var tentativas := 0
	while troncos.size() < ARVORES and tentativas < 3000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-450.0, 450.0), rng.randf_range(-550.0, 450.0))
		if distancia_pista(p.x, p.y) < pista.largura * 0.5 + 8.0:
			continue
		var alto := rng.randf_range(3.0, 6.0)
		var raio := rng.randf_range(2.0, 3.5)
		troncos.append(Transform3D(Basis.from_scale(Vector3(1.0, alto, 1.0)), Vector3(p.x, alto * 0.5, p.y)))
		copas.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(raio, raio * 0.9, raio)), Vector3(p.x, alto + raio * 0.6, p.y)))
		cores_copas.append(COPAS[rng.randi() % COPAS.size()])
	_instancias(tronco, troncos, [], LowPoly.liso(Color("7a5236")))
	_instancias(LowPoly.facetar(copa), copas, cores_copas, LowPoly.liso(Color.WHITE, true))

## Torre do campus: o marco do mapa, um prisma azul alto e facetado com a coroa neon,
## ao lado do meio do S (visível da reta inteira para saber onde se está)
func _torre():
	var meio := PistaCorrida.AMOSTRAS / 2
	var lado := Vector3(pista.lados[meio].x, 0.0, pista.lados[meio].z).normalized()
	var base := pista.pontos[meio] + lado * (pista.largura * 0.5 + 70.0)
	if distancia_pista(base.x, base.z) < pista.largura * 0.5 + 40.0:
		base = pista.pontos[meio] - lado * (pista.largura * 0.5 + 70.0)
	base.y = 0.0
	var corpo := CylinderMesh.new()
	corpo.top_radius = 7.0
	corpo.bottom_radius = 11.0
	corpo.height = 110.0
	corpo.radial_segments = 6
	corpo.rings = 1
	var torre := MeshInstance3D.new()
	torre.mesh = LowPoly.facetar(corpo)
	torre.material_override = LowPoly.liso(FACHADAS[0])
	torre.position = base + Vector3.UP * 55.0
	add_child(torre)
	# Coroa e um anel no meio, acesos
	for anel: Array in [[110.5, 7.6, 2.0], [60.0, 9.3, 1.2]]:
		var faixa := CylinderMesh.new()
		faixa.top_radius = anel[1]
		faixa.bottom_radius = anel[1]
		faixa.height = anel[2]
		faixa.radial_segments = 6
		faixa.rings = 1
		var m := MeshInstance3D.new()
		m.mesh = faixa
		m.material_override = LowPoly.neon(NEON, 2.5)
		m.position = base + Vector3.UP * float(anel[0])
		add_child(m)
