class_name PistaCorrida
extends Node3D
## Circuito do deserto em forma de infinito (lemniscata de Bernoulli). As curvas são
## inclinadas como nas pistas de Carros (a inclinação sai da curvatura: mais fechada,
## mais deitada), e no cruzamento do meio uma das retas passa por cima num viaduto.
## Muro só do lado de fora das curvas (e dos dois lados no viaduto): por dentro a pista
## é aberta para o miolo, onde fica o portal de volta.
## Portões invisíveis ao longo da volta (o 0 é a linha de largada) avisam a corrida.

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

var pontos := PackedVector3Array()
var lados := PackedVector3Array()
var cimas := PackedVector3Array()
var frentes := PackedVector3Array()
var distancias := PackedFloat32Array()
var inclinacoes := PackedFloat32Array()
var comprimento := 0.0

func _ready():
	_calcular()
	_malha_pista()
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

func _calcular():
	var n := AMOSTRAS
	var brutos := PackedVector3Array()
	for i in n:
		brutos.append(_centro(T_LARGADA + TAU * i / n))
	# Inclinação pela curvatura no plano (positiva = curva para a direita)
	var crua := PackedFloat32Array()
	crua.resize(n)
	for i in n:
		var a := brutos[(i - 1 + n) % n]
		var b := brutos[i]
		var c := brutos[(i + 1) % n]
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
				soma += crua[(i + j + n) % n]
			lisa[i] = soma / 25.0
		crua = lisa
	inclinacoes = crua

	pontos.resize(n)
	lados.resize(n)
	cimas.resize(n)
	frentes.resize(n)
	distancias.resize(n + 1)
	for i in n:
		var t := (brutos[(i + 1) % n] - brutos[(i - 1 + n) % n]).normalized()
		var lado := t.cross(Vector3.UP).normalized()
		var cima := lado.cross(t).normalized()
		var ang := inclinacoes[i]
		frentes[i] = t
		lados[i] = lado.rotated(t, ang)
		cimas[i] = cima.rotated(t, ang)
		# Ergue o centro para a borda de baixo da curva ficar no chão
		pontos[i] = brutos[i] + Vector3.UP * (LARGURA * 0.5 * absf(sin(ang)) + 0.08)
	comprimento = 0.0
	for i in n:
		distancias[i] = comprimento
		comprimento += pontos[i].distance_to(pontos[(i + 1) % n])
	distancias[n] = comprimento

## Pista, fundo do viaduto e muros; colisão da pista e da parte de dentro dos muros
func _malha_pista():
	var n := AMOSTRAS
	var meia := LARGURA * 0.5
	var pista := SurfaceTool.new()
	var fundo := SurfaceTool.new()
	var muro := SurfaceTool.new()
	pista.begin(Mesh.PRIMITIVE_TRIANGLES)
	fundo.begin(Mesh.PRIMITIVE_TRIANGLES)
	muro.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colisao := PackedVector3Array()

	for i in n:
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
		var alto := pontos[i].y > 0.9 and pontos[j].y > 0.9
		for lado_sinal: float in [-1.0, 1.0]:
			var fora_i := inclinacoes[i] * lado_sinal < -0.05
			var fora_j := inclinacoes[j] * lado_sinal < -0.05
			if not ((fora_i and fora_j) or alto):
				continue
			var b0 := pontos[i] + lados[i] * meia * lado_sinal
			var b1 := pontos[j] + lados[j] * meia * lado_sinal
			var o0 := Vector3(lados[i].x, 0.0, lados[i].z).normalized() * lado_sinal * MURO_ESPESSURA
			var o1 := Vector3(lados[j].x, 0.0, lados[j].z).normalized() * lado_sinal * MURO_ESPESSURA
			var h := Vector3.UP * MURO_ALTURA
			var chao0 := minf(b0.y - 0.6, -0.3) if pontos[i].y < 0.9 else b0.y - 0.6
			var chao1 := minf(b1.y - 0.6, -0.3) if pontos[j].y < 0.9 else b1.y - 0.6
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
		if p.y < 1.8 or Vector2(p.x, p.z).length() < 13.0:
			continue
		for lado_sinal: float in [-1.0, 1.0]:
			var base := p + lados[i] * (LARGURA * 0.5 - 1.0) * lado_sinal
			var altura := base.y - 0.6
			transformacoes.append(Transform3D(Basis.from_scale(Vector3(1.0, altura, 1.0)), Vector3(base.x, altura * 0.5, base.z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = caixa
	mm.instance_count = transformacoes.size()
	for k in transformacoes.size():
		mm.set_instance_transform(k, transformacoes[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	add_child(no)

## Portões invisíveis de passagem: o 0 é a linha de largada/chegada
func _portoes():
	for k in PORTOES:
		var i := k * AMOSTRAS / PORTOES
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4
		area.monitorable = false
		var forma := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(LARGURA + 2.0, 6.0, 2.0)
		forma.shape = caixa
		area.add_child(forma)
		area.transform = Transform3D(Basis(lados[i], cimas[i], -frentes[i]), pontos[i] + cimas[i] * 2.0)
		area.body_entered.connect(func(_corpo): portao.emit(k))
		add_child(area)

## Pórtico da largada: dois pilares e a viga quadriculada com o nome
func _portico():
	var p := pontos[0]
	var lado := Vector3(lados[0].x, 0.0, lados[0].z).normalized()
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
		m.position = p + lado * (LARGURA * 0.5 + 1.2) * lado_sinal + Vector3.UP * 4.0
		add_child(m)
	var viga := MeshInstance3D.new()
	var caixa := BoxMesh.new()
	caixa.size = Vector3(LARGURA + 3.2, 1.4, 0.5)
	var xadrez := ShaderMaterial.new()
	xadrez.shader = preload("res://xadrez.gdshader")
	caixa.material = xadrez
	viga.mesh = caixa
	viga.transform = Transform3D(base, p + Vector3.UP * 7.5)
	add_child(viga)
	# Um letreiro de cada lado da viga, cada um só visível pela frente
	for virado: bool in [false, true]:
		var nome := Label3D.new()
		nome.text = "SENAI 326 · LARGADA"
		nome.font_size = 96
		nome.pixel_size = 0.012
		nome.outline_size = 16
		nome.double_sided = false
		nome.modulate = Color(1.0, 0.85, 0.2)
		var b := base.rotated(Vector3.UP, PI) if virado else base
		nome.transform = Transform3D(b, p + Vector3.UP * 9.0 + b.z * 0.3)
		add_child(nome)

## Onde o carro começa: alguns metros antes da linha, virado para a frente
func largada() -> Transform3D:
	var i := AMOSTRAS - 10
	return Transform3D(Basis.looking_at(frentes[i], cimas[i]), pontos[i] + cimas[i] * 0.3)
