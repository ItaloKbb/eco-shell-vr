class_name RampasPista
extends Node3D
## Rampas de salto de uma pista de corrida (Parque Industrial). Cada rampa ocupa uma
## faixa da pista ({s: onde fica a borda de cima, d: centro da faixa, largura}), então dá
## para escolher passar por ela ou não. No topo um lançador fixa a velocidade e a direção
## de saída (o salto é sempre igual, como o do abismo no mundo neon) e, onde o carro
## pousa, uma placa de turbo dá o boost. Salto curto e baixo de propósito: queda alta na
## VR dá vertigem.
## Os adversários não colidem com a rampa (andam presos à pista): ao cruzar a borda na
## faixa da rampa eles ganham a mesma velocidade, fazem o mesmo arco (altura()) e pegam
## o turbo do pouso.

const SHADER_IMPULSO := preload("res://impulso_neon.gdshader")
## Rampa: comprimento e altura da borda (m), em perfil quadrático (começa rente)
const COMPRIMENTO := 9.0
const ALTURA := 0.9
## Velocidade de saída do lançador (m/s): sobe ~0,3 m acima da borda e voa ~10 m. O
## pouso fica abaixo de 5 m/s na vertical, sem dano (car.gd pouso_duro é 6)
const LANCAMENTO := 13.0
## Velocidade que a placa do pouso garante (m/s; o carro anda a ~12 no chão)
const TURBO := 20.0
const PLACA := 6.0
const GRAVIDADE := 9.8

var pista: PistaCorrida
## [{s, d, largura}] de cada rampa
var lista: Array[Dictionary] = []
## Ângulo da borda e quanto o salto voa até voltar ao nível da pista (m)
var angulo := atan(2.0 * ALTURA / COMPRIMENTO)
var voo := 0.0

func _init(pista_: PistaCorrida, lista_: Array[Dictionary]):
	pista = pista_
	lista = lista_
	name = "Rampas"
	# Parábola saindo da borda: ALTURA + tan(a)·x - g·x²/(2·v²·cos²a) = 0
	var a := GRAVIDADE / (2.0 * LANCAMENTO * LANCAMENTO * cos(angulo) * cos(angulo))
	var b := tan(angulo)
	voo = (b + sqrt(b * b + 4.0 * a * ALTURA)) / (2.0 * a)

func _ready():
	var concreto := StandardMaterial3D.new()
	concreto.albedo_color = Color(0.95, 0.62, 0.1)
	concreto.roughness = 0.7
	concreto.emission_enabled = true
	concreto.emission = Color(1.0, 0.55, 0.05)
	concreto.emission_energy_multiplier = 0.25
	concreto.cull_mode = BaseMaterial3D.CULL_DISABLED
	for rampa in lista:
		_montar(rampa, concreto)

## Altura do arco de um adversário (m acima da pista): subindo a rampa na faixa dela ou
## no ar depois de ter saído do lançador
func altura(rival: CarroRival) -> float:
	if rival.salto_s > -INF:
		var x := rival.s - rival.salto_s
		if x >= 0.0 and x < voo:
			var v := LANCAMENTO * cos(angulo)
			return maxf(ALTURA + tan(angulo) * x - GRAVIDADE * x * x / (2.0 * v * v), 0.0)
	for rampa in lista:
		var u: float = rival.s - (rampa.s - COMPRIMENTO)
		if u >= 0.0 and u <= COMPRIMENTO and _na_faixa(rampa, rival.d):
			return ALTURA * pow(u / COMPRIMENTO, 2.0)
	return 0.0

## O adversário andou de `antes` até rival.s: salta ao cruzar a borda na faixa da rampa
## e pega o turbo ao pousar
func passar(rival: CarroRival, antes: float):
	for rampa in lista:
		var s: float = rampa.s
		if antes < s and rival.s >= s and _na_faixa(rampa, rival.d):
			rival.salto_s = s
			rival.v = maxf(rival.v, LANCAMENTO)
		var pouso := s + voo
		if rival.salto_s == s and antes < pouso and rival.s >= pouso:
			rival.salto_s = -INF
			rival.turbo(TURBO)

## Rampa mais próxima à frente de s, até `alcance` m (vazio se não tiver)
func proxima(s: float, alcance: float) -> Dictionary:
	for rampa in lista:
		var falta: float = rampa.s - s
		if falta > 0.0 and falta < alcance:
			return rampa
	return {}

func _na_faixa(rampa: Dictionary, d: float) -> bool:
	return absf(d - float(rampa.d)) < float(rampa.largura) * 0.5

func _montar(rampa: Dictionary, material: Material):
	var q := pista.quadro(rampa.s)
	var w: float = rampa.largura
	var base := Transform3D(q.basis, q.origin + q.basis.x * float(rampa.d))
	# Perfil: u da frente da rampa (rente) até a borda; -Z local é a frente da pista
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var passos := 12
	var ponto := func(u: float, x: float) -> Vector3:
		return Vector3(x, ALTURA * pow(u / COMPRIMENTO, 2.0), COMPRIMENTO - u)
	for j in passos:
		var u0 := COMPRIMENTO * j / passos
		var u1 := COMPRIMENTO * (j + 1) / passos
		var a: Vector3 = ponto.call(u0, -w * 0.5)
		var b: Vector3 = ponto.call(u0, w * 0.5)
		var c: Vector3 = ponto.call(u1, w * 0.5)
		var d: Vector3 = ponto.call(u1, -w * 0.5)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
		# Laterais: o vão embaixo da curva, de cada lado
		for x in [-w * 0.5, w * 0.5]:
			for v in [Vector3(x, 0.0, COMPRIMENTO - u0), ponto.call(u0, x), ponto.call(u1, x),
					Vector3(x, 0.0, COMPRIMENTO - u0), ponto.call(u1, x), Vector3(x, 0.0, COMPRIMENTO - u1)]:
				st.add_vertex(v)
	# Parede da borda (de onde o carro salta)
	for v in [Vector3(-w * 0.5, 0.0, 0.0), Vector3(w * 0.5, 0.0, 0.0), Vector3(w * 0.5, ALTURA, 0.0),
			Vector3(-w * 0.5, 0.0, 0.0), Vector3(w * 0.5, ALTURA, 0.0), Vector3(-w * 0.5, ALTURA, 0.0)]:
		st.add_vertex(v)
	st.generate_normals()
	var malha := st.commit()
	var corpo := StaticBody3D.new()
	corpo.name = "Rampa"
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.transform = base
	var vista := MeshInstance3D.new()
	vista.mesh = malha
	vista.material_override = material
	corpo.add_child(vista)
	var forma := CollisionShape3D.new()
	var concava := malha.create_trimesh_shape()
	concava.backface_collision = true
	forma.shape = concava
	corpo.add_child(forma)
	add_child(corpo)

	# Lançador no topo: sai sempre na mesma direção e velocidade
	var lancador := _area("Lancador", Transform3D(base.basis, base * Vector3(0.0, ALTURA - 1.2, 1.4)), Vector3(w, 3.0, 2.4))
	lancador.body_entered.connect(func(corpo_: Node3D):
		if corpo_.has_method("impulsionar"):
			var b: Basis = lancador.global_basis
			corpo_.impulsionar((-b.z * cos(angulo) + b.y * sin(angulo)).normalized(), LANCAMENTO, true))
	# Placa de turbo onde o carro pousa
	var meio := voo + PLACA * 0.5
	var placa := _area("TurboPouso", Transform3D(base.basis, base * Vector3(0.0, 0.0, -meio)), Vector3(w, 2.0, PLACA))
	var plano := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w - 0.6, PLACA)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_IMPULSO
	pm.material = mat
	plano.mesh = pm
	plano.position.y = 0.03
	plano.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	placa.add_child(plano)
	placa.body_entered.connect(func(corpo_: Node3D):
		if corpo_.has_method("impulsionar"):
			corpo_.impulsionar(-placa.global_basis.z, TURBO))

## Área que detecta o carro do jogador (camada 3, como os portões), base no chão
func _area(nome: String, t: Transform3D, tamanho: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = nome
	area.collision_layer = 0
	area.collision_mask = 4
	area.monitorable = false
	area.transform = t
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = tamanho
	forma.shape = caixa
	forma.position.y = tamanho.y * 0.5
	area.add_child(forma)
	add_child(area)
	return area
