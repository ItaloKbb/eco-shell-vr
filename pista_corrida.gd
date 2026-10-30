class_name PistaCorrida
extends Node3D
## Circuito do deserto em forma de infinito (lemniscata de Bernoulli). As curvas são
## inclinadas como nas pistas de Carros (a inclinação sai da curvatura: mais fechada,
## mais deitada), e no cruzamento do meio uma das retas passa por cima num viaduto.
## Muro só do lado de fora das curvas (e dos dois lados no viaduto): por dentro a pista
## é aberta para o miolo, onde fica o portal de volta.
## Portões invisíveis ao longo da volta (o 0 é a linha de largada) avisam a corrida.
##
## Outros circuitos herdam daqui e trocam só o traçado: _centro(t) (t de 0 a 2π, uma
## volta), _t_largada() e, se a pista tiver relevo, _chao(x, z) com o terreno embaixo
## dela (muros, pilares e saias medem a altura a partir dele).
##
## Pista aberta (`aberta`, ver PistaAberta): ponta a ponta, sem dar a volta. A amostra 0
## é o começo do trecho do grid, a corrida vai de s_largada a s_chegada e o último
## portão é a chegada. Corrida, IA e tráfego perguntam à pista (voltas, distancia_corrida,
## avancar, delta) em vez de supor um laço fechado.

signal portao(indice: int)

## Escala do infinito (m): ~630 m de volta
const A := 115.0
const LARGURA := 12.0
const ALTURA_VIADUTO := 6.5
const AMOSTRAS := 720
## Velocidade para a qual a inclinação das curvas é calculada (m/s) e o máximo (22°)
const VELOCIDADE_PROJETO := 15.0
const INCLINACAO_MAX := 0.384
const MURO_ALTURA := 1.0
const MURO_ESPESSURA := 0.6
const PORTOES := 8
## Parâmetro da largada: trecho quase reto logo depois do cruzamento de baixo
const T_LARGADA := 5.162
## Meia largura (em parâmetro) do topo plano do viaduto e das rampas
const VIADUTO_TOPO := 0.2
const VIADUTO_RAMPA := 0.68
## Pista aberta: até onde os adversários andam antes da mureta do fim (m)
const FOLGA_FIM := 6.0
## Grid de largada: distância entre fileiras e afastamento do centro (m)
const GRID_FILEIRA := 6.5
const GRID_LADO := 3.0
## Amostra da primeira fileira, alguns metros depois da linha
const GRID_FRENTE := 10

var pontos := PackedVector3Array()
var lados := PackedVector3Array()
var cimas := PackedVector3Array()
var frentes := PackedVector3Array()
var distancias := PackedFloat32Array()
var inclinacoes := PackedFloat32Array()
## Curvatura no plano (1/m, positiva = curva para a direita), suavizada; a IA usa
## para frear antes das curvas e escolher a linha de corrida
var curvaturas := PackedFloat32Array()
var comprimento := 0.0
## Largura do asfalto (m) e meia largura onde o centro de um carro ainda cabe sem
## raspar no muro: as pistas largas mudam as duas
var largura := LARGURA
var meia_util := MEIA_UTIL
## Ponta a ponta (sem dar a volta): ver PistaAberta
var aberta := false
## Voltas da corrida (pista aberta: 1, da largada à chegada)
var voltas := 3
## Muro dos dois lados em toda a pista (senão só por fora das curvas e no viaduto)
var muro_dos_dois_lados := false
## Onde ficam a linha de largada e a de chegada (m desde a amostra 0). Fechada: a
## amostra 0 é a linha e a chegada é a mesma linha depois de `voltas` voltas
var s_largada := 0.0
var s_chegada := 0.0
## Rampas de salto (Parque Industrial); null nas pistas sem elas
var rampas: RampasPista
## Texto da viga do pórtico de largada
var letreiro := "SENAI 326 · LARGADA"
## Quanto a saia de concreto nas bordas da pista desce abaixo de _chao (0 = sem saia).
## Pista em aterro, acima do terreno, precisa dela para não mostrar o vão por baixo
var saia := 0.0
var _lampadas: Array[StandardMaterial3D] = []
## Barreira invisível das bordas (ver _barreira)
var _corpo_barreira: StaticBody3D
## Altura da barreira acima do asfalto (m): o carro não passa por cima nem saltando
const ALTURA_BARREIRA := 5.0

func _ready():
	meia_util = largura * 0.5 - 0.9
	_calcular()
	_malha_pista()
	_barreira()
	_suportes()
	_portoes()
	_portico()

## Centro da pista no parâmetro t (o cruzamento é a origem, em t = π/2 e 3π/2)
func _centro(t: float) -> Vector3:
	var s := sin(t)
	var c := cos(t)
	var d := 1.0 + s * s
	return Vector3(A * c / d, ALTURA_VIADUTO * _viaduto(t), A * s * c / d)

## 1 no topo do viaduto (a passagem de t = π/2), 0 no chão, rampas suaves
func _viaduto(t: float) -> float:
	var u := absf(wrapf(t - PI * 0.5, -PI, PI))
	return 1.0 - smoothstep(VIADUTO_TOPO, VIADUTO_RAMPA, u)

## Parâmetro t onde fica a linha de largada (a amostra 0)
func _t_largada() -> float:
	return T_LARGADA

## Altura do terreno embaixo da pista (local da pista): o deserto é plano
func _chao(_x: float, _z: float) -> float:
	return 0.0

## Amostra `passo` à frente (ou atrás, negativo) de i: dá a volta no laço fechado e
## para nas pontas da pista aberta
func _vizinho(i: int, passo: int) -> int:
	if aberta:
		return clampi(i + passo, 0, AMOSTRAS - 1)
	return posmod(i + passo, AMOSTRAS)

## Centro da pista nas AMOSTRAS amostras, a 0 na linha de largada
func _amostras_brutas() -> PackedVector3Array:
	var brutos := PackedVector3Array()
	var t0 := _t_largada()
	for i in AMOSTRAS:
		brutos.append(_centro(t0 + TAU * i / AMOSTRAS))
	return brutos

## Quanto a amostra i está acima do terreno (viaduto, aterro)
func _elevacao(i: int) -> float:
	return pontos[i].y - _chao(pontos[i].x, pontos[i].z)

func _calcular():
	var n := AMOSTRAS
	var brutos := _amostras_brutas()
	# Inclinação pela curvatura no plano (positiva = curva para a direita)
	var crua := PackedFloat32Array()
	crua.resize(n)
	for i in n:
		var a := brutos[_vizinho(i, -1)]
		var b := brutos[i]
		var c := brutos[_vizinho(i, 1)]
		var f1 := Vector2(b.x - a.x, b.z - a.z)
		var f2 := Vector2(c.x - b.x, c.z - b.z)
		var lado := -f1.y * f2.x + f1.x * f2.y
		var k := 2.0 * lado / maxf(f1.length() * f2.length() * Vector2(c.x - a.x, c.z - a.z).length(), 0.0001)
		crua[i] = clampf(atan(VELOCIDADE_PROJETO * VELOCIDADE_PROJETO * k / 9.8), -INCLINACAO_MAX, INCLINACAO_MAX)
	# Suaviza para a pista não "torcer" de repente
	for passada in 2:
		var lisa := PackedFloat32Array()
		lisa.resize(n)
		for i in n:
			var soma := 0.0
			for j in range(-12, 13):
				soma += crua[_vizinho(i, j)]
			lisa[i] = soma / 25.0
		crua = lisa
	inclinacoes = crua
	_calcular_curvaturas(brutos)

	pontos.resize(n)
	lados.resize(n)
	cimas.resize(n)
	frentes.resize(n)
	distancias.resize(n + 1)
	for i in n:
		var t := (brutos[_vizinho(i, 1)] - brutos[_vizinho(i, -1)]).normalized()
		var lado := t.cross(Vector3.UP).normalized()
		var cima := lado.cross(t).normalized()
		var ang := inclinacoes[i]
		frentes[i] = t
		lados[i] = lado.rotated(t, ang)
		cimas[i] = cima.rotated(t, ang)
		# Ergue o centro para a borda de baixo da curva ficar no chão
		pontos[i] = brutos[i] + Vector3.UP * (largura * 0.5 * absf(sin(ang)) + 0.08)
	comprimento = 0.0
	for i in n:
		distancias[i] = comprimento
		comprimento += pontos[i].distance_to(pontos[_vizinho(i, 1)])
	distancias[n] = comprimento
	if not aberta:
		s_largada = 0.0
		s_chegada = comprimento

## Pista, fundo do viaduto e muros; colisão da pista e da parte de dentro dos muros
func _malha_pista():
	var n := AMOSTRAS
	var meia := largura * 0.5
	var pista := SurfaceTool.new()
	var fundo := SurfaceTool.new()
	var muro := SurfaceTool.new()
	pista.begin(Mesh.PRIMITIVE_TRIANGLES)
	fundo.begin(Mesh.PRIMITIVE_TRIANGLES)
	muro.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colisao := PackedVector3Array()

	# Aberta: a última amostra não se liga à primeira
	for i in (n - 1 if aberta else n):
		var j := (i + 1) % n
		var dj := distancias[i + 1]
		var e0 := pontos[i] - lados[i] * meia
		var d0 := pontos[i] + lados[i] * meia
		var e1 := pontos[j] - lados[j] * meia
		var d1 := pontos[j] + lados[j] * meia
		_quad(pista, [e0, d0, d1, e1], [Vector2(0, distancias[i]), Vector2(1, distancias[i]), Vector2(1, dj), Vector2(0, dj)], cimas[i])
		colisao.append_array([e0, d0, d1, e0, d1, e1])
		# Por baixo do tabuleiro (só aparece no viaduto)
		var baixo := Vector3.DOWN * 0.6
		_quad(fundo, [e1 + baixo, d1 + baixo, d0 + baixo, e0 + baixo], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], Vector3.DOWN)

		# Muros: do lado de fora da curva; dos dois lados no viaduto
		var alto_i := _elevacao(i) > 0.9
		var alto_j := _elevacao(j) > 0.9
		var alto := alto_i and alto_j
		# Saia: fecha a borda até o terreno onde não há muro
		if saia > 0.0:
			for lado_sinal: float in [-1.0, 1.0]:
				var b0 := pontos[i] + lados[i] * meia * lado_sinal
				var b1 := pontos[j] + lados[j] * meia * lado_sinal
				var pe0 := Vector3(b0.x, minf(_chao(b0.x, b0.z), b0.y) - saia, b0.z)
				var pe1 := Vector3(b1.x, minf(_chao(b1.x, b1.z), b1.y) - saia, b1.z)
				var face := [b0, b1, pe1, pe0]
				if lado_sinal < 0.0:
					face.reverse()
				var fora_saia := Vector3(lados[i].x, 0.0, lados[i].z).normalized() * lado_sinal
				_quad(fundo, face, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], fora_saia)
		for lado_sinal: float in [-1.0, 1.0]:
			var fora_i := inclinacoes[i] * lado_sinal < -0.05
			var fora_j := inclinacoes[j] * lado_sinal < -0.05
			if not ((fora_i and fora_j) or alto or muro_dos_dois_lados):
				continue
			var b0 := pontos[i] + lados[i] * meia * lado_sinal
			var b1 := pontos[j] + lados[j] * meia * lado_sinal
			var o0 := Vector3(lados[i].x, 0.0, lados[i].z).normalized() * lado_sinal * MURO_ESPESSURA
			var o1 := Vector3(lados[j].x, 0.0, lados[j].z).normalized() * lado_sinal * MURO_ESPESSURA
			var h := Vector3.UP * MURO_ALTURA
			var chao0 := minf(b0.y - 0.6, _chao(b0.x, b0.z) - 0.3) if not alto_i else b0.y - 0.6
			var chao1 := minf(b1.y - 0.6, _chao(b1.x, b1.z) - 0.3) if not alto_j else b1.y - 0.6
			var dentro := [b0, b1, b1 + h, b0 + h]
			var topo := [b0 + h, b1 + h, b1 + h + o1, b0 + h + o0]
			var fora := [b0 + h + o0, b1 + h + o1, Vector3(b1.x + o1.x, chao1, b1.z + o1.z), Vector3(b0.x + o0.x, chao0, b0.z + o0.z)]
			if lado_sinal < 0.0:
				dentro.reverse()
				topo.reverse()
				fora.reverse()
			var uv_muro := [Vector2(0, distancias[i]), Vector2(0, dj), Vector2(1, dj), Vector2(1, distancias[i])]
			_quad(muro, dentro, uv_muro, -o0.normalized())
			_quad(muro, topo, uv_muro, Vector3.UP)
			_quad(muro, fora, uv_muro, o0.normalized())
			colisao.append_array([dentro[0], dentro[1], dentro[2], dentro[0], dentro[2], dentro[3]])
			colisao.append_array([topo[0], topo[1], topo[2], topo[0], topo[2], topo[3]])

	var material_pista := ShaderMaterial.new()
	material_pista.shader = preload("res://pista_corrida.gdshader")
	material_pista.set_shader_parameter("comprimento", comprimento)
	var material_muro := ShaderMaterial.new()
	material_muro.shader = preload("res://muro_corrida.gdshader")
	var concreto := StandardMaterial3D.new()
	concreto.albedo_color = Color(0.55, 0.52, 0.48)
	concreto.roughness = 0.9
	if aberta:
		_muretas_pontas(muro, colisao)
	for par in [[pista, material_pista], [fundo, concreto], [muro, material_muro]]:
		var st: SurfaceTool = par[0]
		var malha := MeshInstance3D.new()
		malha.mesh = st.commit()
		malha.material_override = par[1]
		add_child(malha)

	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	concava.set_faces(colisao)
	forma.shape = concava
	corpo.add_child(forma)
	add_child(corpo)

## Barreira invisível nas duas bordas, a pista inteira, até ALTURA_BARREIRA acima do
## asfalto: durante a corrida ninguém sai da pista (nem pelo lado aberto das curvas do
## Deserto e do Vale, nem por cima do muro numa batida ou com nitro). Só colisão, sem
## malha; a Corrida liga na largada e desliga na chegada, para o piloto poder ir até o
## portal de volta no miolo
func _barreira():
	var faces := PackedVector3Array()
	var meia := largura * 0.5
	var alto := Vector3.UP * ALTURA_BARREIRA
	for i in (AMOSTRAS - 1 if aberta else AMOSTRAS):
		var j := (i + 1) % AMOSTRAS
		for lado_sinal: float in [-1.0, 1.0]:
			var a := pontos[i] + lados[i] * meia * lado_sinal + Vector3.DOWN * 0.5
			var b := pontos[j] + lados[j] * meia * lado_sinal + Vector3.DOWN * 0.5
			faces.append_array([a, b, b + alto, a, b + alto, a + alto])
	_corpo_barreira = StaticBody3D.new()
	_corpo_barreira.name = "Barreira"
	_corpo_barreira.collision_layer = 0
	_corpo_barreira.collision_mask = 0
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	concava.set_faces(faces)
	forma.shape = concava
	_corpo_barreira.add_child(forma)
	add_child(_corpo_barreira)

## Liga/desliga a barreira invisível das bordas (Corrida, conforme a fase)
func barreira_ligada(sim: bool):
	if _corpo_barreira:
		_corpo_barreira.collision_layer = 1 if sim else 0

func tem_barreira() -> bool:
	return _corpo_barreira != null and _corpo_barreira.collision_layer != 0

## Pista aberta: mureta atravessada nas pontas (atrás do grid e no fim), para ninguém
## sair pelo fim do asfalto. Sem _mureta_no_fim() o fim fica livre (uma praça, por exemplo)
func _muretas_pontas(muro: SurfaceTool, colisao: PackedVector3Array):
	var meia := largura * 0.5 + MURO_ESPESSURA
	for ponta in ([0, AMOSTRAS - 1] if _mureta_no_fim() else [0]):
		var p := pontos[ponta]
		var lado := lados[ponta]
		var fora := frentes[ponta] * (-1.0 if ponta == 0 else 1.0)
		var h := Vector3.UP * MURO_ALTURA * 1.4
		var base := Vector3.DOWN * 0.6
		var e := p - lado * meia
		var d := p + lado * meia
		var o := fora * MURO_ESPESSURA
		var faces := [[d + base, e + base, e + h, d + h], [e + h, e + h + o, d + h + o, d + h],
			[e + base + o, d + base + o, d + h + o, e + h + o]]
		var normais := [-fora, Vector3.UP, fora]
		for k in faces.size():
			var face: Array = faces[k]
			if ponta == 0:
				face.reverse()
			_quad(muro, face, [Vector2(0, 0), Vector2(0, largura), Vector2(1, largura), Vector2(1, 0)], normais[k])
			colisao.append_array([face[0], face[1], face[2], face[0], face[2], face[3]])

func _mureta_no_fim() -> bool:
	return true

## Quatro vértices em sentido anti-horário visto de quem olha a face
func _quad(st: SurfaceTool, v: Array, uv: Array, normal: Vector3):
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uv[k])
		st.add_vertex(v[k])

## Pilares do viaduto (fora do cruzamento, onde passa a pista de baixo)
func _suportes():
	var caixa := BoxMesh.new()
	caixa.size = Vector3(1.2, 1.0, 1.2)
	var concreto := StandardMaterial3D.new()
	concreto.albedo_color = Color(0.62, 0.58, 0.52)
	concreto.roughness = 0.9
	caixa.material = concreto
	var transformacoes: Array[Transform3D] = []
	for i in range(0, AMOSTRAS, 9):
		var p := pontos[i]
		if _elevacao(i) < 1.8 or _sob_viaduto(p):
			continue
		for lado_sinal: float in [-1.0, 1.0]:
			var base := p + lados[i] * (largura * 0.5 - 1.0) * lado_sinal
			var chao := _chao(base.x, base.z)
			var altura := base.y - 0.6 - chao
			transformacoes.append(Transform3D(Basis.from_scale(Vector3(1.0, altura, 1.0)), Vector3(base.x, chao + altura * 0.5, base.z)))
	if transformacoes.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = caixa
	mm.instance_count = transformacoes.size()
	for k in transformacoes.size():
		mm.set_instance_transform(k, transformacoes[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	add_child(no)

## Ponto onde não pode ter pilar porque passa outra pista por baixo (o cruzamento do infinito)
func _sob_viaduto(p: Vector3) -> bool:
	return Vector2(p.x, p.z).length() < 13.0

## Portões invisíveis de passagem: o 0 é a linha de largada/chegada. Na pista aberta
## vão da largada à chegada, e o último (total_portoes() - 1) é a linha de chegada
func _portoes():
	for k in total_portoes():
		var i := k * AMOSTRAS / PORTOES
		if aberta:
			i = amostra_em(s_largada + (s_chegada - s_largada) * k / PORTOES)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4
		area.monitorable = false
		var forma := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(largura + 2.0, 6.0, 2.0)
		forma.shape = caixa
		area.add_child(forma)
		area.transform = Transform3D(Basis(lados[i], cimas[i], -frentes[i]), pontos[i] + cimas[i] * 2.0)
		area.body_entered.connect(func(_corpo): portao.emit(k))
		add_child(area)

## Pórtico da largada (com o semáforo) e, na pista aberta, o da chegada
func _portico():
	_montar_portico(amostra_em(s_largada), letreiro, true)
	if aberta:
		_montar_portico(amostra_em(s_chegada), "CHEGADA", false)

## Dois pilares e a viga quadriculada com o nome na amostra i
func _montar_portico(i: int, texto: String, com_semaforo: bool):
	var p := pontos[i]
	var lado := Vector3(lados[i].x, 0.0, lados[i].z).normalized()
	var base := Basis(lado, Vector3.UP, lado.cross(Vector3.UP))
	var pilar := BoxMesh.new()
	pilar.size = Vector3(0.8, 8.0, 0.8)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.85, 0.85, 0.88)
	metal.metallic = 0.7
	metal.roughness = 0.35
	pilar.material = metal
	for lado_sinal: float in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		m.mesh = pilar
		m.position = p + lado * (largura * 0.5 + 1.2) * lado_sinal + Vector3.UP * 4.0
		add_child(m)
	var viga := MeshInstance3D.new()
	var caixa := BoxMesh.new()
	caixa.size = Vector3(largura + 3.2, 1.4, 0.5)
	var xadrez := ShaderMaterial.new()
	xadrez.shader = preload("res://xadrez.gdshader")
	caixa.material = xadrez
	viga.mesh = caixa
	viga.transform = Transform3D(base, p + Vector3.UP * 7.5)
	add_child(viga)
	_letreiros(texto, base, p)
	if not com_semaforo:
		return
	# Semáforo: três lâmpadas embaixo da viga, visíveis dos dois lados
	var bola := SphereMesh.new()
	bola.radius = 0.32
	bola.height = 0.64
	for k in 3:
		var material := StandardMaterial3D.new()
		_lampadas.append(material)
		for face: float in [-1.0, 1.0]:
			var lampada := MeshInstance3D.new()
			lampada.mesh = bola
			lampada.material_override = material
			lampada.position = p + Vector3.UP * 6.5 + lado * (k - 1) * 1.2 + base.z * 0.2 * face
			add_child(lampada)
	semaforo(-1)

## Um letreiro de cada lado da viga, cada um só visível pela frente
func _letreiros(texto: String, base: Basis, p: Vector3):
	for virado: bool in [false, true]:
		var nome := Label3D.new()
		nome.text = texto
		nome.font_size = 96
		nome.pixel_size = 0.012
		nome.outline_size = 16
		nome.double_sided = false
		nome.modulate = Color(1.0, 0.85, 0.2)
		var b := base.rotated(Vector3.UP, PI) if virado else base
		nome.transform = Transform3D(b, p + Vector3.UP * 9.0 + b.z * 0.3)
		add_child(nome)

## Vaga do grid (0 = pole) sobre a pista, sem folga de altura: fileiras de dois,
## a primeira embaixo do pórtico (o grid inteiro fica longe do viaduto),
## alternadas como na F1 (a da direita meia fileira atrás) e recuando
func grid(posicao: int) -> Transform3D:
	var vaga := grid_sd(posicao)
	var pose := quadro(vaga.x)
	pose.origin += pose.basis.x * vaga.y
	return pose

## Amostra que fica `metros` antes da amostra `inicio`, andando pela pista
func _amostra_atras(inicio: int, metros: float) -> int:
	var j := inicio
	var andado := 0.0
	while andado < metros and not (aberta and j == 0):
		var anterior := _vizinho(j, -1)
		andado += pontos[j].distance_to(pontos[anterior])
		j = anterior
	return j

## Amostra da pista mais perto do ponto (local da pista). `dica` é a última resposta:
## procura primeiro em volta dela e só varre tudo se o ponto saiu de perto
func amostra_perto(p: Vector3, dica := -1) -> int:
	var melhor := -1
	var menor := INF
	if dica >= 0:
		for d in range(-24, 25):
			var i := _vizinho(dica, d)
			var dist := p.distance_squared_to(pontos[i])
			if dist < menor:
				menor = dist
				melhor = i
		if menor < largura * largura:
			return melhor
	for i in AMOSTRAS:
		var dist := p.distance_squared_to(pontos[i])
		if dist < menor:
			menor = dist
			melhor = i
	return melhor

## Semáforo do pórtico: -1 apagado, 1 a 3 acende as vermelhas, 4 todas verdes
func semaforo(estado: int):
	for k in _lampadas.size():
		var m: StandardMaterial3D = _lampadas[k]
		var acesa := estado == 4 or k < estado
		m.emission_enabled = acesa
		m.emission = Color(0.2, 1.0, 0.35) if estado == 4 else Color(1.0, 0.12, 0.08)
		m.emission_energy_multiplier = 4.0
		m.albedo_color = m.emission if acesa else Color(0.08, 0.08, 0.09)

# --- Navegação (IA dos adversários) -------------------------------------------

## Meia largura útil da pista padrão (m); cada pista usa a sua em `meia_util`
const MEIA_UTIL := LARGURA * 0.5 - 0.9

func _calcular_curvaturas(brutos: PackedVector3Array):
	var n := AMOSTRAS
	var k := PackedFloat32Array()
	k.resize(n)
	for i in n:
		var a := brutos[_vizinho(i, -1)]
		var b := brutos[i]
		var c := brutos[_vizinho(i, 1)]
		var f1 := Vector2(b.x - a.x, b.z - a.z)
		var f2 := Vector2(c.x - b.x, c.z - b.z)
		var lado := -f1.y * f2.x + f1.x * f2.y
		k[i] = 2.0 * lado / maxf(f1.length() * f2.length() * Vector2(c.x - a.x, c.z - a.z).length(), 0.0001)
	for passada in 2:
		var lisa := PackedFloat32Array()
		lisa.resize(n)
		for i in n:
			var soma := 0.0
			for j in range(-8, 9):
				soma += k[_vizinho(i, j)]
			lisa[i] = soma / 17.0
		k = lisa
	curvaturas = k

## Amostra e fração (0 a 1) até a próxima para a distância s ao longo da volta
func _indice(s: float) -> Vector2:
	s = clampf(s, 0.0, comprimento) if aberta else fposmod(s, comprimento)
	var baixo := 0
	var alto := AMOSTRAS
	while alto - baixo > 1:
		var meio := (baixo + alto) / 2
		if distancias[meio] <= s:
			baixo = meio
		else:
			alto = meio
	var trecho := maxf(distancias[baixo + 1] - distancias[baixo], 0.0001)
	return Vector2(baixo, (s - distancias[baixo]) / trecho)

## Pose no centro da pista à distância s (local da pista): -Z = frente, X = direita,
## Y = normal da pista (já inclinada nas curvas)
func quadro(s: float) -> Transform3D:
	var ix := _indice(s)
	var i := int(ix.x)
	var j := _vizinho(i, 1)
	var frente := frentes[i].lerp(frentes[j], ix.y).normalized()
	var cima := cimas[i].lerp(cimas[j], ix.y).normalized()
	return Transform3D(Basis.looking_at(frente, cima), pontos[i].lerp(pontos[j], ix.y))

func curvatura(s: float) -> float:
	var ix := _indice(s)
	var i := int(ix.x)
	return lerpf(curvaturas[i], curvaturas[_vizinho(i, 1)], ix.y)

## Ponto (local da pista) em coordenadas da pista: x = distância s, y = desvio lateral d
## (positivo à direita), z = amostra mais próxima (para usar de dica na próxima vez)
func projetar(p: Vector3, dica := -1) -> Vector3:
	var i := amostra_perto(p, dica)
	var rel := p - pontos[i]
	var s := distancias[i] + rel.dot(frentes[i])
	return Vector3(clampf(s, 0.0, comprimento) if aberta else fposmod(s, comprimento), rel.dot(lados[i]), i)

## Maior velocidade com que dá para estar em s e ainda frear a tempo para as curvas
## dos próximos `olhar` metros, com aceleração lateral `lateral` e frenagem `frenagem`
func velocidade_segura(s: float, lateral: float, frenagem: float, olhar := 60.0) -> float:
	var limite := INF
	var x := 0.0
	while x <= olhar:
		var k := absf(curvatura(s + x))
		if k > 0.0001:
			var na_curva := sqrt(lateral / k)
			limite = minf(limite, sqrt(na_curva * na_curva + 2.0 * frenagem * x))
		x += 5.0
	return limite

## Vaga do grid em coordenadas da pista (s, d), a mesma de grid(). Na pista aberta o
## grid inteiro fica atrás da linha de largada, e afasta do centro com a largura
func grid_sd(posicao: int) -> Vector2:
	var recuo := (posicao / 2) * GRID_FILEIRA + (posicao % 2) * GRID_FILEIRA * 0.5
	var lado := GRID_LADO * largura / LARGURA
	lado = -lado if posicao % 2 == 0 else lado
	# Aberta: amostras espaçadas (~2,5 m), então a vaga vai direto em metros
	if aberta:
		return Vector2(s_largada - 4.0 - recuo, lado)
	return Vector2(distancias[_amostra_atras(GRID_FRENTE, recuo)], lado)

# --- Ponta a ponta ou em voltas -------------------------------------------------

## Amostra mais próxima da distância s
func amostra_em(s: float) -> int:
	var ix := _indice(s)
	return mini(int(ix.x) + (1 if ix.y > 0.5 else 0), AMOSTRAS - 1)

## Quantos portões a pista tem (na aberta o último é a linha de chegada)
func total_portoes() -> int:
	return PORTOES + 1 if aberta else PORTOES

## Metros entre a largada e a bandeirada
func distancia_corrida() -> float:
	return s_chegada - s_largada if aberta else voltas * comprimento

## Progresso de quem está parado em s antes da largada (atrás da linha é negativo)
func progresso_inicial(s: float) -> float:
	if aberta:
		return s - s_largada
	return s - comprimento if s > comprimento * 0.5 else s

## Anda ds metros a partir de s: dá a volta no laço; na aberta para antes da mureta do fim
func avancar(s: float, ds: float) -> float:
	if aberta:
		return clampf(s + ds, 0.0, comprimento - FOLGA_FIM)
	return fposmod(s + ds, comprimento)

## Metros de a até b ao longo da pista (positivo = b na frente), pelo caminho curto
func delta(a: float, b: float) -> float:
	if aberta:
		return b - a
	return wrapf(b - a, -comprimento * 0.5, comprimento * 0.5)
