class_name ValeTurbinas
extends MapaCorrida
## Mapa do portal verde: a usina de energia limpa do SENAI num vale ao pôr do sol.
## Morros de grama com turbinas eólicas gigantes girando, uma fazenda de painéis
## solares no miolo e o circuito (PistaTurbinas) subindo e descendo pelo vale, com
## os obstáculos móveis: o guindaste balançando a nacele, as turbinas varredoras no
## meio da pista e as comportas da represa. O portal de volta fica no centro do miolo.
## Estilo low poly (LowPoly): morros facetados em cor chapada por face (grama viva no
## vale, capim dourado subindo, rocha violeta no alto), céu de pôr do sol violeta e
## laranja, pinheiros e pedras facetados perto da pista (referência fixa de
## velocidade) e o neon rosa da pista só nos destaques (anel na base das turbinas).
## A turbina gigante no morro é o marco: de qualquer ponto da volta dá para vê-la.
## Desempenho (Quest 3): peças repetidas em MultiMesh e cada rotor numa malha só
## (~20 chamadas de desenho para as 14 turbinas, antes ~100), sem luz além do sol.

## Tamanho do chão (m) e quantos quadrados por lado
const TAMANHO := 1400.0
const DIVISOES := 128
## O terreno desce o aterro até esta distância da pista e volta ao relevo depois
const PERTO := 12.0
const LONGE := 30.0
const TURBINAS := 14
## Distância das células da grade que não ficam perto da pista (m)
const LONGE_DEMAIS := 1000.0
## Paleta do pôr do sol: céu violeta para laranja, grama viva, capim dourado, rocha
## violeta, terra do acostamento, branco das turbinas e o neon rosa da pista
const CEU_ALTO := Color("3b2a78")
const CEU_HORIZONTE := Color("ff8a4c")
const CHAO_HORIZONTE := Color("f2905a")
const CHAO_FUNDO := Color("3a2840")
const NEBLINA := Color("ff9e6e")
const GRAMA := Color("4fbf4a")
const GRAMA_CLARA := Color("8fd45a")
const CAPIM := Color("e8c25a")
const ROCHA := Color("8e7390")
const TERRA := Color("b0744a")
const BRANCO := Color("f4f1ec")
const PINHEIROS := [Color("2f9e4f"), Color("46b85a"), Color("1f7f4a")]
## Escala da turbina gigante (o marco do vale)
const ESCALA_MARCO := 1.9

var obstaculos: ObstaculosPista

var _ruido := FastNoiseLite.new()
## Distância até a pista em cada vértice da grade do terreno (para altura())
var _distancia := PackedFloat32Array()
var _rotores: Array[Node3D] = []
var _giros: Array[float] = []

func _init():
	nome = "Vale das Turbinas"
	faixa_corrida = "res://musicas/musica_2.mp3"
	fala_chegada = "turbinas"
	_ruido.seed = 2026
	_ruido.frequency = 0.006
	_ruido.fractal_octaves = 3

func _etapas() -> Array:
	return [
		["Traçando o circuito", _montar_circuito],
		["Esculpindo o vale", _terreno],
		["Aterrando o acostamento", _acostamento],
		["Erguendo as turbinas", _turbinas],
		["Instalando painéis solares", _paineis],
		["Plantando pinheiros", _arvores],
		["Ligando os obstáculos", _montar_obstaculos],
	]

func _posicao_portal_volta() -> Vector3:
	return Vector3(0.0, altura(global_position.x, global_position.z) - global_position.y, 0.0)

func _nova_pista() -> PistaCorrida:
	return PistaTurbinas.new()

func _montar_circuito():
	super()
	_calcular_distancias()
	portal_volta.position = _posicao_portal_volta()

func _process(delta: float):
	for i in _rotores.size():
		_rotores[i].rotation.z += _giros[i] * delta

# --- Relevo ---------------------------------------------------------------------

## Distância (no plano) de cada vértice da grade até o centro da pista, carimbando
## em volta de cada amostra: barato e basta para o aterro
func _calcular_distancias():
	var lado := DIVISOES + 1
	var passo := TAMANHO / DIVISOES
	_distancia.resize(lado * lado)
	# Longe da pista: valor grande, mas finito (interpolar INF com INF dá NaN)
	_distancia.fill(LONGE_DEMAIS)
	var raio_celulas := ceili(LONGE / passo) + 1
	for i in range(0, PistaCorrida.AMOSTRAS, 2):
		var p := pista.pontos[i]
		var cx := roundi((p.x + TAMANHO * 0.5) / passo)
		var cz := roundi((p.z + TAMANHO * 0.5) / passo)
		for iz in range(maxi(cz - raio_celulas, 0), mini(cz + raio_celulas, DIVISOES) + 1):
			for ix in range(maxi(cx - raio_celulas, 0), mini(cx + raio_celulas, DIVISOES) + 1):
				var x := -TAMANHO * 0.5 + ix * passo
				var z := -TAMANHO * 0.5 + iz * passo
				var k := iz * lado + ix
				_distancia[k] = minf(_distancia[k], Vector2(x - p.x, z - p.z).length())

## Distância até a pista interpolada na grade (local)
func _distancia_pista(x: float, z: float) -> float:
	if _distancia.is_empty():
		return LONGE_DEMAIS
	var passo := TAMANHO / DIVISOES
	var lado := DIVISOES + 1
	var fx := (x + TAMANHO * 0.5) / passo
	var fz := (z + TAMANHO * 0.5) / passo
	if fx < 0.0 or fz < 0.0 or fx >= DIVISOES or fz >= DIVISOES:
		return LONGE_DEMAIS
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_distancia[iz * lado + ix], _distancia[iz * lado + ix + 1], tx)
	var b := lerpf(_distancia[(iz + 1) * lado + ix], _distancia[(iz + 1) * lado + ix + 1], tx)
	return lerpf(a, b, tz)

## Altura do chão (mundo): o relevo da pista, rebaixado em volta dela (aterro) e com
## morros crescendo conforme se afasta
func altura(x: float, z: float) -> float:
	var lx := x - global_position.x
	var lz := z - global_position.z
	var dist := _distancia_pista(lx, lz)
	var base := PistaTurbinas.relevo(lx, lz)
	var aterro := PistaTurbinas.ATERRO * (1.0 - smoothstep(PERTO, LONGE, dist))
	var morro := smoothstep(40.0, 160.0, dist)
	var crista := 1.0 - absf(_ruido.get_noise_2d(lx, lz))
	return global_position.y + base - aterro + (crista * crista * 34.0 + 3.0) * morro

func _terreno():
	var passo := TAMANHO / DIVISOES
	var lado := DIVISOES + 1
	var alturas := PackedFloat32Array()
	alturas.resize(lado * lado)
	for iz in lado:
		for ix in lado:
			var x := -TAMANHO * 0.5 + ix * passo
			var z := -TAMANHO * 0.5 + iz * passo
			alturas[iz * lado + ix] = altura(x + global_position.x, z + global_position.z) - global_position.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Low poly: normal por triângulo (as facetas aparecem com o sol baixo) e uma cor só
	# por face, pela altura do centro dela
	st.set_smooth_group(-1)
	var faces := PackedVector3Array()
	for iz in DIVISOES:
		for ix in DIVISOES:
			var v: Array[Vector3] = []
			for c: Vector2i in [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]:
				v.append(Vector3(-TAMANHO * 0.5 + c.x * passo, alturas[c.y * lado + c.x], -TAMANHO * 0.5 + c.y * passo))
			for tri in [[v[0], v[1], v[2]], [v[0], v[2], v[3]]]:
				var centro: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				st.set_color(_cor_terreno(centro))
				for p: Vector3 in tri:
					st.add_vertex(p)
			faces.append_array([v[0], v[1], v[2], v[0], v[2], v[3]])
	st.generate_normals()
	var malha := MeshInstance3D.new()
	malha.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
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

## Cor chapada do morro pela altura acima do relevo da pista: grama viva no vale,
## grama clara, capim dourado subindo e rocha violeta no alto
func _cor_terreno(p: Vector3) -> Color:
	var h := clampf((p.y - PistaTurbinas.relevo(p.x, p.z)) / 30.0, 0.0, 1.0)
	var cor := GRAMA.lerp(GRAMA_CLARA, smoothstep(0.05, 0.25, h))
	cor = cor.lerp(CAPIM, smoothstep(0.3, 0.55, h))
	return cor.lerp(ROCHA, smoothstep(0.65, 0.9, h))

## Acostamento com colisão dos dois lados da pista: rampa de terra da borda do asfalto
## até o chão do vale. O aterro deixa a pista 1,5 a 6 m acima do terreno e a saia de
## concreto é só visual: sem isso quem saía pelo lado sem muro passava por baixo da
## pista. Comprimento conforme o desnível, para a rampa não ficar íngreme (~20°)
func _acostamento():
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var faces := PackedVector3Array()
	var meia := pista.largura * 0.5
	var n := PistaCorrida.AMOSTRAS
	var passo := 2
	for lado: float in [-1.0, 1.0]:
		var bordas: Array[Vector3] = []
		var pes: Array[Vector3] = []
		for i in range(0, n, passo):
			var borda := pista.pontos[i] + pista.lados[i] * meia * lado
			var fora := Vector3(pista.lados[i].x, 0.0, pista.lados[i].z).normalized() * lado
			var chao := altura(borda.x + global_position.x, borda.z + global_position.z) - global_position.y
			var comprimento := clampf((borda.y - chao) * 2.8, 6.0, 20.0)
			var pe := borda + fora * comprimento
			# O pé entra um pouco no chão: sem fresta entre a rampa e o terreno
			pe.y = altura(pe.x + global_position.x, pe.z + global_position.z) - global_position.y - 0.2
			bordas.append(borda + Vector3.DOWN * 0.03)
			pes.append(pe)
		for k in bordas.size():
			var j := (k + 1) % bordas.size()
			var quad := [bordas[k], pes[k], pes[j], bordas[j]]
			for v in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				st.add_vertex(v)
				faces.append(v)
	st.generate_normals()
	var malha := MeshInstance3D.new()
	malha.name = "Acostamento"
	malha.mesh = st.commit()
	var terra := LowPoly.liso(TERRA)
	terra.cull_mode = BaseMaterial3D.CULL_DISABLED
	malha.material_override = terra
	add_child(malha)
	var corpo := StaticBody3D.new()
	corpo.name = "AcostamentoColisao"
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	concava.set_faces(faces)
	forma.shape = concava
	corpo.add_child(forma)
	add_child(corpo)

func _montar_ambiente():
	# Céu em gradiente (ProceduralSky, sem textura): violeta em cima, laranja no
	# horizonte, sol baixo e estilizado
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = CEU_ALTO
	ceu.sky_horizon_color = CEU_HORIZONTE
	ceu.sky_curve = 0.1
	ceu.ground_horizon_color = CHAO_HORIZONTE
	ceu.ground_bottom_color = CHAO_FUNDO
	ceu.sun_angle_max = 16.0
	ceu.sun_curve = 0.06
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.75
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Glow leve: só o neon passa do limiar (bloom forte cansa em VR)
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.35
	ambiente.glow_hdr_threshold = 1.2
	# Neblina coral do fim de tarde (esconde o fim do chão e o aparecer dos morros)
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = NEBLINA
	ambiente.fog_depth_begin = 220.0
	ambiente.fog_depth_end = 560.0
	ambiente.fog_sky_affect = 0.35

## Sol baixo e alaranjado do pôr do sol (mundos.gd aplica na luz da cena)
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-14.0, 110.0, 0.0)
	luz.light_color = Color(1.0, 0.68, 0.45)
	luz.light_energy = 1.25

# --- Cenário --------------------------------------------------------------------

## Turbinas eólicas nos morros em volta (só cenário, girando devagar), low poly:
## torre facetada branca com anel neon na base, nacele, farol vermelho e o rotor de
## três pás. A primeira é a gigante, o marco do vale. Torres, naceles, faróis e anéis
## são um MultiMesh cada; cada rotor é uma malha só (gira inteiro)
func _turbinas():
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	var branco := LowPoly.liso(BRANCO)
	var torre := CylinderMesh.new()
	torre.top_radius = 1.0
	torre.bottom_radius = 2.0
	torre.height = 48.0
	torre.radial_segments = 8
	torre.rings = 1
	var nacele := BoxMesh.new()
	nacele.size = Vector3(3.0, 3.0, 7.0)
	var farol := CylinderMesh.new()
	farol.top_radius = 0.0
	farol.bottom_radius = 0.6
	farol.height = 1.0
	farol.radial_segments = 4
	farol.rings = 1
	var anel := CylinderMesh.new()
	anel.top_radius = 2.15
	anel.bottom_radius = 2.15
	anel.height = 0.6
	anel.radial_segments = 8
	anel.rings = 1
	var rotor_malha := _malha_rotor()
	var torres: Array[Transform3D] = []
	var naceles: Array[Transform3D] = []
	var farois: Array[Transform3D] = []
	var aneis: Array[Transform3D] = []
	var feitas := 0
	var tentativas := 0
	while feitas < TURBINAS and tentativas < 400:
		tentativas += 1
		var marco := feitas == 0
		var a := rng.randf() * TAU
		var d := rng.randf_range(230.0, 300.0) if marco else rng.randf_range(60.0, 420.0)
		var p := Vector2(cos(a), sin(a)) * d
		if _distancia_pista(p.x, p.y) < (90.0 if marco else 45.0):
			continue
		feitas += 1
		var escala := ESCALA_MARCO if marco else 1.0
		var chao := altura(p.x + global_position.x, p.y + global_position.z) - global_position.y
		# Todas viradas para o vento (mesma direção), com variação pequena
		var base := Transform3D(Basis(Vector3.UP, 0.6 + rng.randf_range(-0.15, 0.15)).scaled(Vector3.ONE * escala), Vector3(p.x, chao, p.y))
		torres.append(base * Transform3D(Basis.IDENTITY, Vector3.UP * 24.0))
		aneis.append(base * Transform3D(Basis.IDENTITY, Vector3.UP * 3.0))
		naceles.append(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 49.0, 1.0)))
		farois.append(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 51.0, 2.5)))
		var rotor := MeshInstance3D.new()
		rotor.mesh = rotor_malha
		rotor.material_override = branco
		rotor.transform = base * Transform3D(Basis.IDENTITY, Vector3(0.0, 49.0, -2.8))
		rotor.rotation.z = rng.randf() * TAU
		add_child(rotor)
		_rotores.append(rotor)
		_giros.append(rng.randf_range(0.35, 0.6) / sqrt(escala))
	add_child(LowPoly.espalhar(LowPoly.facetar(torre), branco, torres))
	add_child(LowPoly.espalhar(LowPoly.facetar(nacele), branco, naceles))
	add_child(LowPoly.espalhar(farol, LowPoly.neon(Color("ff3a2a"), 3.0), farois))
	add_child(LowPoly.espalhar(anel, LowPoly.neon(pista.paleta.neon if pista else Color("ff5fa2"), 2.5), aneis))

## Cubo e três pás afinando na ponta, numa malha só e facetada (o rotor gira inteiro)
func _malha_rotor() -> ArrayMesh:
	var pa := CylinderMesh.new()
	pa.top_radius = 0.25
	pa.bottom_radius = 0.9
	pa.height = 22.0
	pa.radial_segments = 4
	pa.rings = 1
	var cubo := SphereMesh.new()
	cubo.radius = 1.3
	cubo.height = 2.6
	cubo.radial_segments = 6
	cubo.rings = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cubo, 0, Transform3D.IDENTITY)
	for k in 3:
		# Pá achatada (perfil fino), girada 120° em volta do eixo do rotor
		var giro := Basis(Vector3.BACK, TAU * k / 3.0)
		st.append_from(pa, 0, Transform3D(giro * Basis.from_scale(Vector3(1.0, 1.0, 0.3)), giro * Vector3(0.0, 11.5, 0.0)))
	return LowPoly.facetar(st.commit())

## Fazenda solar no miolo do circuito: fileiras de painéis inclinados para o sol
func _paineis():
	var painel := BoxMesh.new()
	painel.size = Vector3(3.2, 0.08, 1.8)
	# Azul chapado e pouco espelhado: reflexo forte cintila no headset
	var vidro := LowPoly.liso(Color("2e5bc4"))
	vidro.roughness = 0.45
	vidro.metallic_specular = 0.5
	painel.material = vidro
	var pecas: Array[Transform3D] = []
	var inclina := Basis(Vector3.RIGHT, deg_to_rad(-28.0))
	for fileira in range(-6, 7):
		for coluna in range(-9, 10):
			var x := coluna * 3.6
			var z := fileira * 4.2 + 28.0
			# Deixa uma clareira em volta do portal de volta
			if Vector2(x, z).length() < 22.0 or _distancia_pista(x, z) < 25.0:
				continue
			var chao := altura(x + global_position.x, z + global_position.z) - global_position.y
			pecas.append(Transform3D(inclina, Vector3(x, chao + 1.2, z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = painel
	mm.instance_count = pecas.size()
	for k in pecas.size():
		mm.set_instance_transform(k, pecas[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	add_child(no)

## Pinheiros (dois cones facetados) e pedras em volta da pista, fora do acostamento,
## da fazenda solar e da clareira do portal: referências fixas passando ao lado dão a
## noção de velocidade sem listra nenhuma no chão. Um MultiMesh por peça
func _arvores():
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 6
	cone.rings = 1
	var tronco := CylinderMesh.new()
	tronco.top_radius = 0.18
	tronco.bottom_radius = 0.25
	tronco.height = 1.0
	tronco.radial_segments = 5
	tronco.rings = 1
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 1.4
	esfera.radial_segments = 7
	esfera.rings = 3
	var copas: Array[Transform3D] = []
	var cores_copas: Array[Color] = []
	var troncos: Array[Transform3D] = []
	var pedras: Array[Transform3D] = []
	var cores_pedras: Array[Color] = []
	var tentativas := 0
	while troncos.size() < 160 and tentativas < 3000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-330.0, 330.0), rng.randf_range(-330.0, 330.0))
		var dist := _distancia_pista(p.x, p.y)
		if dist < 30.0 or dist > 160.0 or p.length() < 25.0 or (absf(p.x) < 40.0 and p.y > -5.0 and p.y < 60.0):
			continue
		var chao := altura(p.x + global_position.x, p.y + global_position.z) - global_position.y
		var alto := rng.randf_range(6.0, 12.0)
		var largo := alto * rng.randf_range(0.26, 0.34)
		var giro := Basis(Vector3.UP, rng.randf() * TAU)
		var cor: Color = PINHEIROS[rng.randi() % PINHEIROS.size()]
		troncos.append(Transform3D(giro.scaled(Vector3(1.0, alto * 0.3, 1.0)), Vector3(p.x, chao + alto * 0.15, p.y)))
		# Copa em dois andares: o de baixo largo, o de cima menor
		copas.append(Transform3D(giro.scaled(Vector3(largo, alto * 0.55, largo)), Vector3(p.x, chao + alto * 0.5, p.y)))
		cores_copas.append(cor)
		copas.append(Transform3D(giro.scaled(Vector3(largo * 0.7, alto * 0.45, largo * 0.7)), Vector3(p.x, chao + alto * 0.8, p.y)))
		cores_copas.append(cor.lightened(0.08))
		if rng.randf() < 0.35:
			var lado := Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			var tamanho := rng.randf_range(0.8, 2.6)
			var escala := Vector3(rng.randf_range(0.9, 1.5), rng.randf_range(0.6, 1.0), rng.randf_range(0.9, 1.4)) * tamanho
			var q := p + lado
			var chao_pedra := altura(q.x + global_position.x, q.y + global_position.z) - global_position.y
			pedras.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(escala), Vector3(q.x, chao_pedra + escala.y * 0.2, q.y)))
			cores_pedras.append(ROCHA.lerp(Color("b49ab0"), rng.randf()))
	add_child(LowPoly.espalhar(tronco, LowPoly.liso(Color("6b4a3a")), troncos))
	add_child(LowPoly.espalhar(LowPoly.facetar(cone), LowPoly.liso(Color.WHITE, true), copas, cores_copas))
	if not pedras.is_empty():
		add_child(LowPoly.espalhar(LowPoly.facetar(esfera), LowPoly.liso(Color.WHITE, true), pedras, cores_pedras))

# --- Obstáculos -----------------------------------------------------------------

## Os desafios da volta, na ordem: guindaste duplo, turbina varredora, comportas,
## varredora do outro lado girando ao contrário e o guindaste sozinho antes da reta
## da chegada.
## Cada um fica no trecho mais reto em volta do ponto pedido
func _montar_obstaculos():
	obstaculos = ObstaculosPista.new()
	obstaculos.pista = pista
	obstaculos.trafego = trafego
	pista.add_child(obstaculos)
	if trafego:
		trafego.obstaculos = obstaculos
	var l := pista.comprimento
	var duplo := _reto(0.16 * l)
	var primeiro := PenduloCarga.new()
	obstaculos.adicionar(primeiro, duplo)
	var segundo := PenduloCarga.new()
	segundo.fase = PI
	obstaculos.adicionar(segundo, duplo + 14.0)
	obstaculos.adicionar(TurbinaVarredora.new(), _reto(0.34 * l))
	obstaculos.adicionar(Comportas.new(), _reto(0.52 * l))
	# A segunda fica do outro lado e gira ao contrário: a faixa livre troca de lado
	var contraria := TurbinaVarredora.new()
	contraria.lado = -1.0
	contraria.giro = -0.95
	contraria.fase = 1.0
	obstaculos.adicionar(contraria, _reto(0.70 * l))
	var ultimo := PenduloCarga.new()
	ultimo.fase = 1.5
	obstaculos.adicionar(ultimo, _reto(0.86 * l))

## s de menor curvatura a até 25 m de `s`
func _reto(s: float) -> float:
	var melhor := s
	var menor := INF
	var x := -25.0
	while x <= 25.0:
		var k := absf(pista.curvatura(s + x))
		if k < menor:
			menor = k
			melhor = s + x
		x += 1.0
	return melhor
