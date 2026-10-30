class_name Deserto
extends MapaCorrida
## Mapa do primeiro portal: um deserto low poly ao meio-dia em volta do circuito em
## infinito (pista_corrida.gd), com 16 m de largura. Tudo gerado em código na primeira
## visita, em cores chapadas e facetas (LowPoly), sem textura:
##  - dunas facetadas (planície clara em volta da pista, laranja e dourado longe);
##  - mesas de arenito em degraus no horizonte, um arco de pedra e duas torres de
##    rocha como marcos (dá para se localizar no infinito pela direção deles);
##  - totens com tampa neon do lado de fora das curvas (referência de frenagem e o
##    toque Tron, sem luz real);
##  - pedras e cactos espalhados perto da pista (referência fixa de velocidade).
## Desempenho (Quest 3): cada grupo repetido é um MultiMesh (uma chamada de desenho
## cada), sem luzes além do sol, sem sombras no Quest (mundos.gd) e ~50 mil triângulos
## no total, a maior parte no chão. No miolo de um dos laços fica o portal de volta.

## Tamanho do chão (m) e quantos quadrados por lado
const TAMANHO := 1600.0
const DIVISOES := 128
## Largura da pista do Deserto (m): mais folga para disputar posição no infinito
const LARGURA_PISTA := 16.0
## Paleta do mapa: céu azul forte, areia quente, rocha vermelha, cacto verde vivo e o
## neon ciano (complementar do laranja) só nos destaques
const CEU_ALTO := Color("2f6fe0")
const CEU_HORIZONTE := Color("ffc38a")
const CHAO_HORIZONTE := Color("f2b27a")
const CHAO_FUNDO := Color("c77b48")
const POEIRA := Color("f7c79a")
const CACTO := Color("3fae55")
const ROCHA := [Color("b8452a"), Color("d9673a"), Color("ee8a4e")]
const TOTEM := Color("4b3a5a")
const NEON := Color("2ee6ff")

var _ruido := FastNoiseLite.new()
var _ruido_fino := FastNoiseLite.new()
var _rocha: ShaderMaterial

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
		["Erguendo marcos", _marcos],
		["Distribuindo vegetação", _cactos],
		["Espalhando pedras", _pedras],
		["Preparando circuito", _montar_circuito],
		["Acendendo totens", _totens],
	]

func _nova_pista() -> PistaCorrida:
	var pista_nova := PistaCorrida.new()
	pista_nova.largura = LARGURA_PISTA
	return pista_nova

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

## Altura local do chão no ponto local (x, z) do mapa
func _chao_local(x: float, z: float) -> float:
	return altura(x + global_position.x, z + global_position.z)

## Fora da caixa da pista (com `folga` m), onde pode ter cenário
func _fora_da_pista(p: Vector2, folga: float) -> bool:
	return absf(p.x) > PistaCorrida.A + folga or absf(p.y) > PistaCorrida.A * 0.36 + folga

func _montar_ambiente():
	# Céu em gradiente forte (ProceduralSky, sem textura) e sol estilizado
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = CEU_ALTO
	ceu.sky_horizon_color = CEU_HORIZONTE
	ceu.sky_curve = 0.12
	ceu.ground_horizon_color = CHAO_HORIZONTE
	ceu.ground_bottom_color = CHAO_FUNDO
	ceu.sun_angle_max = 12.0
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
	# Poeira quente no horizonte: esconde o fim do chão e o aparecer das mesas
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = POEIRA
	ambiente.fog_depth_begin = 250.0
	ambiente.fog_depth_end = 620.0
	ambiente.fog_sky_affect = 0.3

## Chão facetado: cada triângulo com a sua normal (smooth group -1), as dunas viram
## facetas que o sol pinta em tons diferentes
func _terreno():
	var passo := TAMANHO / DIVISOES
	var lado := DIVISOES + 1
	var alturas := PackedFloat32Array()
	alturas.resize(lado * lado)
	for iz in lado:
		for ix in lado:
			alturas[iz * lado + ix] = _chao_local(-TAMANHO * 0.5 + ix * passo, -TAMANHO * 0.5 + iz * passo)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
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

func _material_rocha() -> ShaderMaterial:
	if _rocha == null:
		_rocha = ShaderMaterial.new()
		_rocha.shader = preload("res://rocha.gdshader")
	return _rocha

## Prisma de rocha facetado (poucos lados, silhueta forte de longe)
func _prisma(raio_baixo: float, raio_alto: float, alto: float, lados: int) -> ArrayMesh:
	var cilindro := CylinderMesh.new()
	cilindro.bottom_radius = raio_baixo
	cilindro.top_radius = raio_alto
	cilindro.height = alto
	cilindro.radial_segments = lados
	cilindro.rings = 1
	return LowPoly.facetar(cilindro)

func _rocha_em(malha: Mesh, posicao: Vector3, giro: float, escala := Vector3.ONE):
	var m := MeshInstance3D.new()
	m.mesh = malha
	m.material_override = _material_rocha()
	m.position = posicao
	m.rotation.y = giro
	m.scale = escala
	add_child(m)

## Mesas de arenito no horizonte, metade delas em dois degraus
func _mesas():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.2, 0.2)
		var d := rng.randf_range(330.0, 540.0)
		var raio := rng.randf_range(32.0, 72.0)
		var alto := rng.randf_range(40.0, 100.0)
		var lados := rng.randi_range(6, 9)
		var giro := rng.randf() * TAU
		var achatada := Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		var base := Vector3(cos(a) * d, 0.0, sin(a) * d)
		_rocha_em(_prisma(raio, raio * rng.randf_range(0.72, 0.88), alto, lados), base + Vector3.UP * (alto * 0.5 - 4.0), giro, achatada)
		if i % 2 == 0:
			# Degrau de cima, menor e deslocado: silhueta de "mesa com torre"
			var alto_cima := alto * rng.randf_range(0.35, 0.6)
			var desvio := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)) * raio
			_rocha_em(_prisma(raio * 0.45, raio * 0.36, alto_cima, lados), base + desvio + Vector3.UP * (alto - 4.0 + alto_cima * 0.5), giro, achatada)

## Marcos perto do circuito, um de cada lado do infinito: um arco de pedra ao norte e
## duas torres de rocha ao sul. Quem está na pista sabe para onde está virado
func _marcos():
	# Arco: dois pilares inclinados e a laje em cima
	var centro := Vector3(0.0, 0.0, -(PistaCorrida.A * 0.36 + 70.0))
	var pilar := _prisma(7.0, 5.0, 34.0, 6)
	for lado: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		m.mesh = pilar
		m.material_override = _material_rocha()
		m.position = centro + Vector3(lado * 18.0, 15.0, 0.0)
		# Inclinados para dentro, o topo encostando na laje
		m.rotation = Vector3(0.0, 0.0, lado * 0.12)
		add_child(m)
	var laje := BoxMesh.new()
	laje.size = Vector3(52.0, 9.0, 12.0)
	_rocha_em(LowPoly.facetar(laje), centro + Vector3(0.0, 33.0, 0.0), 0.0)
	# Torres gêmeas: altas e finas, viradas uma para a outra
	var sul := Vector3(30.0, 0.0, PistaCorrida.A * 0.36 + 80.0)
	_rocha_em(_prisma(11.0, 6.0, 70.0, 5), sul + Vector3(0.0, 33.0, 0.0), 0.4)
	_rocha_em(_prisma(9.0, 4.5, 52.0, 5), sul + Vector3(-34.0, 24.0, 12.0), 1.3)

## Cactos low poly (prismas de seis lados, braços em L) fora da pista, um MultiMesh só,
## com o verde variando um pouco de um para o outro
func _cactos():
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var tronco := _prisma(0.4, 0.34, 1.0, 6)
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	var feitos := 0
	while feitos < 55:
		var p := Vector2(rng.randf_range(-320.0, 320.0), rng.randf_range(-260.0, 260.0))
		if not _fora_da_pista(p, 25.0):
			continue
		feitos += 1
		var tom := CACTO.lerp(Color("2e8f4a") if rng.randf() < 0.5 else Color("6cc24a"), rng.randf_range(0.0, 0.6))
		var chao := _chao_local(p.x, p.y)
		var alto := rng.randf_range(3.5, 7.0)
		var base := Vector3(p.x, chao, p.y)
		var giro := Basis(Vector3.UP, rng.randf() * TAU)
		pecas.append(Transform3D(giro.scaled(Vector3(1.0, alto, 1.0)), base + Vector3.UP * alto * 0.5))
		cores.append(tom)
		for braco in rng.randi_range(0, 2):
			var lado := (giro.x if braco == 0 else -giro.x)
			var h := alto * rng.randf_range(0.4, 0.65)
			# Pedaço horizontal saindo do tronco e pedaço vertical subindo
			pecas.append(Transform3D(Basis(giro.z, PI * 0.5) * Basis.from_scale(Vector3(0.8, 0.9, 0.8)), base + Vector3.UP * h + lado * 0.45))
			cores.append(tom)
			var sobe := rng.randf_range(1.2, 2.2)
			pecas.append(Transform3D(Basis.from_scale(Vector3(0.8, sobe, 0.8)), base + Vector3.UP * (h + sobe * 0.5) + lado * 0.9))
			cores.append(tom)
	add_child(LowPoly.espalhar(tronco, LowPoly.liso(Color.WHITE, true), pecas, cores))

## Pedras facetadas espalhadas entre a pista e as dunas: referências fixas que passam
## ao lado e dão a noção de velocidade (sem listra nenhuma no chão)
func _pedras():
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 1.4
	esfera.radial_segments = 7
	esfera.rings = 3
	var pedra := LowPoly.facetar(esfera)
	var lugares: Array[Transform3D] = []
	var cores: Array[Color] = []
	var feitas := 0
	while feitas < 90:
		var p := Vector2(rng.randf_range(-300.0, 300.0), rng.randf_range(-220.0, 220.0))
		if not _fora_da_pista(p, 14.0):
			continue
		feitas += 1
		var tamanho := rng.randf_range(0.8, 3.2) * (2.2 if rng.randf() < 0.12 else 1.0)
		var escala := Vector3(rng.randf_range(0.8, 1.5), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.4)) * tamanho
		var giro := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
		lugares.append(Transform3D(giro.scaled(escala), Vector3(p.x, _chao_local(p.x, p.y) + escala.y * 0.25, p.y)))
		cores.append(ROCHA[rng.randi() % ROCHA.size()])
	add_child(LowPoly.espalhar(pedra, LowPoly.liso(Color.WHITE, true), lugares, cores))

## Totens do lado de fora das curvas, a cada ~12 m: prisma escuro com a tampa em neon
## ciano. Marcam a curva de longe e casam o low poly com o Tron (dois MultiMesh)
func _totens():
	if pista == null:
		return
	var corpos: Array[Transform3D] = []
	var tampas: Array[Transform3D] = []
	var passo := 14
	for i in range(0, PistaCorrida.AMOSTRAS, passo):
		var inclinacao := pista.inclinacoes[i]
		var p := pista.pontos[i]
		# Só nas curvas, e longe do viaduto do cruzamento
		if absf(inclinacao) < 0.12 or Vector2(p.x, p.z).length() < 30.0:
			continue
		var fora := Vector3(pista.lados[i].x, 0.0, pista.lados[i].z).normalized() * -signf(inclinacao)
		var base := p + fora * (pista.largura * 0.5 + PistaCorrida.MURO_ESPESSURA + 3.5)
		base.y = _chao_local(base.x, base.z)
		var giro := Basis(Vector3.UP, atan2(fora.x, fora.z))
		corpos.append(Transform3D(giro, base + Vector3.UP * 3.0))
		tampas.append(Transform3D(giro, base + Vector3.UP * 6.35))
	if corpos.is_empty():
		return
	add_child(LowPoly.espalhar(_prisma(0.9, 0.6, 6.0, 4), LowPoly.liso(TOTEM), corpos))
	add_child(LowPoly.espalhar(_prisma(0.62, 0.15, 0.7, 4), LowPoly.neon(NEON), tampas))
