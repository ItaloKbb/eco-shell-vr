class_name ValeTurbinas
extends MapaCorrida
## Mapa do portal verde: a usina de energia limpa do SENAI num vale ao pôr do sol.
## Morros de grama com turbinas eólicas gigantes girando, uma fazenda de painéis
## solares no miolo e o circuito (PistaTurbinas) subindo e descendo pelo vale, com
## os obstáculos móveis: o guindaste balançando a nacele, as turbinas varredoras no
## meio da pista e as comportas da represa. O portal de volta fica no centro do miolo.

## Tamanho do chão (m) e quantos quadrados por lado
const TAMANHO := 1400.0
const DIVISOES := 128
## O terreno desce o aterro até esta distância da pista e volta ao relevo depois
const PERTO := 12.0
const LONGE := 30.0
const TURBINAS := 14
## Distância das células da grade que não ficam perto da pista (m)
const LONGE_DEMAIS := 1000.0

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
		["Erguendo as turbinas", _turbinas],
		["Instalando painéis solares", _paineis],
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
	var faces := PackedVector3Array()
	var grama := Color(0.32, 0.48, 0.2)
	var seca := Color(0.6, 0.55, 0.32)
	var rocha := Color(0.45, 0.42, 0.4)
	for iz in DIVISOES:
		for ix in DIVISOES:
			var v: Array[Vector3] = []
			for c: Vector2i in [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]:
				v.append(Vector3(-TAMANHO * 0.5 + c.x * passo, alturas[c.y * lado + c.x], -TAMANHO * 0.5 + c.y * passo))
			for p in [v[0], v[1], v[2], v[0], v[2], v[3]]:
				# Grama no vale, capim seco subindo, pedra no alto dos morros
				var h := clampf((p.y - PistaTurbinas.relevo(p.x, p.z)) / 30.0, 0.0, 1.0)
				st.set_color(grama.lerp(seca, smoothstep(0.1, 0.5, h)).lerp(rocha, smoothstep(0.55, 0.9, h)))
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

func _montar_ambiente():
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color(0.22, 0.2, 0.48)
	ceu.sky_horizon_color = Color(1.0, 0.58, 0.32)
	ceu.ground_horizon_color = Color(0.85, 0.5, 0.3)
	ceu.ground_bottom_color = Color(0.2, 0.18, 0.2)
	ceu.sun_angle_max = 25.0
	ceu.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.75
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.5
	ambiente.glow_hdr_threshold = 1.0
	# Neblina dourada do fim de tarde (esconde o fim do chão)
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = Color(0.95, 0.62, 0.42)
	ambiente.fog_depth_begin = 220.0
	ambiente.fog_depth_end = 560.0
	ambiente.fog_sky_affect = 0.35

## Sol baixo e alaranjado do pôr do sol (mundos.gd aplica na luz da cena)
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-14.0, 110.0, 0.0)
	luz.light_color = Color(1.0, 0.68, 0.45)
	luz.light_energy = 1.25

# --- Cenário --------------------------------------------------------------------

## Turbinas eólicas gigantes nos morros em volta (só cenário, girando devagar)
func _turbinas():
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	var branco := ObstaculoPista.material_metal(Color(0.92, 0.93, 0.95), 0.25, 0.4)
	var torre := CylinderMesh.new()
	torre.top_radius = 1.0
	torre.bottom_radius = 2.0
	torre.height = 48.0
	torre.radial_segments = 12
	torre.material = branco
	var nacele := BoxMesh.new()
	nacele.size = Vector3(3.0, 3.0, 7.0)
	nacele.material = branco
	var pa := BoxMesh.new()
	pa.size = Vector3(1.6, 22.0, 0.35)
	pa.material = branco
	var luz := ObstaculoPista.material_luz(Color(1.0, 0.15, 0.1), 5.0)
	var farol := SphereMesh.new()
	farol.radius = 0.5
	farol.height = 1.0
	farol.material = luz
	var feitas := 0
	var tentativas := 0
	while feitas < TURBINAS and tentativas < 400:
		tentativas += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(60.0, 420.0)
		var p := Vector2(cos(a), sin(a)) * d
		if _distancia_pista(p.x, p.y) < 45.0:
			continue
		feitas += 1
		var chao := altura(p.x + global_position.x, p.y + global_position.z) - global_position.y
		var base := Node3D.new()
		base.position = Vector3(p.x, chao, p.y)
		# Todas viradas para o vento (mesma direção), com variação pequena
		base.rotation.y = 0.6 + rng.randf_range(-0.15, 0.15)
		add_child(base)
		var m := MeshInstance3D.new()
		m.mesh = torre
		m.position = Vector3.UP * 24.0
		base.add_child(m)
		var topo := MeshInstance3D.new()
		topo.mesh = nacele
		topo.position = Vector3(0.0, 49.0, 1.0)
		base.add_child(topo)
		var pisca := MeshInstance3D.new()
		pisca.mesh = farol
		pisca.position = Vector3(0.0, 50.8, 2.5)
		base.add_child(pisca)
		var rotor := Node3D.new()
		rotor.position = Vector3(0.0, 49.0, -2.8)
		rotor.rotation.z = rng.randf() * TAU
		base.add_child(rotor)
		for k in 3:
			var braco := Node3D.new()
			braco.rotation.z = TAU * k / 3.0
			rotor.add_child(braco)
			var lamina := MeshInstance3D.new()
			lamina.mesh = pa
			lamina.position = Vector3(0.0, 11.5, 0.0)
			braco.add_child(lamina)
		_rotores.append(rotor)
		_giros.append(rng.randf_range(0.35, 0.6))

## Fazenda solar no miolo do circuito: fileiras de painéis inclinados para o sol
func _paineis():
	var painel := BoxMesh.new()
	painel.size = Vector3(3.2, 0.08, 1.8)
	var vidro := StandardMaterial3D.new()
	vidro.albedo_color = Color(0.08, 0.14, 0.32)
	vidro.metallic = 0.8
	vidro.roughness = 0.15
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
