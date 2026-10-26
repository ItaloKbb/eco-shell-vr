class_name EstruturasNeon
extends Node3D
## Peças geométricas do mundo neon: um abismo atravessa o mapa de ponta a ponta (de
## leste a oeste) e divide o lado do nascimento do lado norte. Para passar existem três
## pontes curvas (em arco, em S e em curva inclinada) e um salto com turbo; espalhados
## pelos dois lados há loops de 360° (com turbo na entrada) e rampas de salto.
##
## Tudo é gerado por código: fitas (pista com mureta extrudada ao longo de um caminho)
## e prismas (perfil lateral extrudado na largura), com colisão de malha na camada do
## chão, então as rodas do carro sobem nelas como no piso.

const SHADER := preload("res://estrutura_neon.gdshader")
const SHADER_IMPULSO := preload("res://impulso_neon.gdshader")
const SHADER_PISO := preload("res://tron_ground.gdshader")

## Abismo: faixa em z (centro e meia largura) e profundidade visual do fundo
const ABISMO_Z := -260.0
const ABISMO_MEIA := 20.0
const ABISMO_FUNDO := 70.0

## Pista das pontes e loops: largura, espessura e mureta (altura, espessura)
const LARGURA := 5.0
const ESPESSURA := 0.5
const MURETA := 0.4
const MURETA_LARGURA := 0.25
## Topo das pistas no começo e no fim, rente ao piso (evita z-fighting)
const RENTE := 0.03

@export_flags_3d_physics var collision_layer := 1
## Velocidade que o turbo garante na direção da placa (m/s)
@export var turbo_loop := 23.0
@export var turbo_salto := 24.0
## Saída do lançador no topo da rampa do salto: velocidade (m/s) e ângulo
@export var velocidade_salto := 28.0
@export var angulo_salto := deg_to_rad(20.0)
## Rampa de pouso: folga abaixo da parábola na borda norte (tolerância para saltos um
## pouco mais baixos) e em quantos metros ela some (o carro encosta quase tangente)
@export var folga_pouso := 0.5
@export var encaixe_pouso := 4.0

var _material: ShaderMaterial
var _material_parede: ShaderMaterial
## Áreas ocupadas (centro xz, raio), para os portais não nascerem dentro de nada
var _ocupado: Array = []

func _ready():
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material_parede = ShaderMaterial.new()
	_material_parede.shader = SHADER
	_material_parede.set_shader_parameter("edge_color", Color(0.95, 0.2, 0.85))
	_material_parede.set_shader_parameter("emission_energy", 1.2)
	_montar_abismo()
	_montar_pontes()
	_montar_salto(260.0)
	_montar_loop("LoopSul", Vector3(-160.0, 0.0, -60.0), 0.0)
	_montar_loop("LoopNorte", Vector3(80.0, 0.0, -360.0), 0.0)
	for r in [
			[Vector3(0.0, 0.0, -70.0), 0.0], [Vector3(60.0, 0.0, -125.0), 0.6],
			[Vector3(-85.0, 0.0, -150.0), -0.4], [Vector3(150.0, 0.0, -70.0), PI * 0.5],
			[Vector3(-40.0, 0.0, -340.0), PI], [Vector3(200.0, 0.0, -430.0), 0.3]]:
		_montar_rampa(r[0], r[1])

## Ponto dentro do abismo (sem chão)
func no_abismo(x: float, z: float) -> bool:
	return absf(z - ABISMO_Z) < ABISMO_MEIA

## Longe do abismo e das estruturas, com folga `raio`
func area_livre(p: Vector3, raio: float) -> bool:
	if absf(p.z - ABISMO_Z) < ABISMO_MEIA + raio:
		return false
	for o in _ocupado:
		if Vector2(p.x, p.z).distance_to(o[0]) < o[1] + raio:
			return false
	return true

# --- Abismo ------------------------------------------------------------------

func _montar_abismo():
	var tamanho: float = get_parent().world_size if "world_size" in get_parent() else 6000.0
	# Paredes de pedra neon descendo das duas bordas
	for lado in [-1.0, 1.0]:
		var z: float = ABISMO_Z + lado * (ABISMO_MEIA + 0.5)
		_corpo("Parede%s" % ("Norte" if lado < 0.0 else "Sul"), _malha_caixa(Vector3(tamanho, ABISMO_FUNDO, 1.0)),
			Transform3D(Basis(), Vector3(0.0, -ABISMO_FUNDO * 0.5, z)), _material_parede, true)
	# Fundo: a mesma grade do piso, bem apagada, sem colisão (quem cai é reposicionado)
	var fundo := MeshInstance3D.new()
	fundo.name = "FundoAbismo"
	var plano := PlaneMesh.new()
	plano.size = Vector2(tamanho, ABISMO_MEIA * 2.0 + 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_PISO
	mat.set_shader_parameter("grid_color", Color(0.25, 0.02, 0.35))
	mat.set_shader_parameter("emission_energy", 0.8)
	plano.material = mat
	fundo.mesh = plano
	fundo.position = Vector3(0.0, -ABISMO_FUNDO, ABISMO_Z)
	fundo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fundo)

# --- Pontes ------------------------------------------------------------------

## Três pontes de borda a borda, cada uma entrando 8 m no chão de cada lado
func _montar_pontes():
	var z0 := ABISMO_Z + ABISMO_MEIA + 8.0
	var z1 := ABISMO_Z - ABISMO_MEIA - 8.0
	var n := 48
	# Arco: reta em planta, corcunda de 6 m no meio
	var arco := PackedVector3Array()
	var cima_arco := PackedVector3Array()
	for i in n + 1:
		var s := float(i) / n
		arco.append(Vector3(-70.0, RENTE + 6.0 * pow(sin(PI * s), 2.0), lerpf(z0, z1, s)))
		cima_arco.append(Vector3.UP)
	_fita("PonteArco", arco, cima_arco)
	# S: desloca 20 m de lado com uma pequena corcunda
	var s_pts := PackedVector3Array()
	var cima_s := PackedVector3Array()
	for i in n + 1:
		var s := float(i) / n
		s_pts.append(Vector3(30.0 + 20.0 * (0.5 - 0.5 * cos(PI * s)), RENTE + 2.0 * pow(sin(PI * s), 2.0), lerpf(z0, z1, s)))
		cima_s.append(Vector3.UP)
	_fita("PonteS", s_pts, cima_s)
	# Curva: barriga de 24 m para leste, inclinada para dentro da curva como num velódromo
	var c_pts := PackedVector3Array()
	var cima_c := PackedVector3Array()
	for i in n + 1:
		var s := float(i) / n
		var barriga := sin(PI * s)
		c_pts.append(Vector3(140.0 + 24.0 * barriga, RENTE + 3.0 * barriga * barriga, lerpf(z0, z1, s)))
		cima_c.append(Vector3.UP.rotated(Vector3.FORWARD, -0.35 * barriga * barriga))
	_fita("PonteCurva", c_pts, cima_c)
	for x in [-70.0, 40.0, 152.0]:
		_ocupado.append([Vector2(x, ABISMO_Z), 45.0])

# --- Salto do abismo ---------------------------------------------------------

## Salto do abismo: turbo, rampa de 20° na borda sul (curva suave embaixo, reta em cima)
## com um lançador no topo, e rampa de pouso na borda norte. O lançador fixa velocidade
## e direção de saída (a suspensão e a borda da rampa sozinhas fariam cada salto sair
## diferente), então a rampa de pouso é calculada pela própria parábola do salto: começa
## um pouco abaixo dela, encosta aos poucos (pouso quase tangente) e depois achata até o chão
func _montar_salto(x: float):
	var borda_sul := ABISMO_Z + ABISMO_MEIA
	var borda_norte := ABISMO_Z - ABISMO_MEIA
	var comprimento := 14.0
	var transicao := 6.0
	var inclinacao := tan(angulo_salto)
	var perfil := PackedVector2Array([Vector2(0.0, 0.0)])
	for i in range(1, 15):
		var d := comprimento * i / 14.0
		var y := inclinacao * d * d / (2.0 * transicao) if d < transicao else inclinacao * (d - transicao * 0.5)
		perfil.append(Vector2(d, y))
	var altura := perfil[perfil.size() - 1].y
	perfil.append(Vector2(comprimento, 0.0))
	_prisma("RampaSalto", perfil, 6.0, Transform3D(Basis(), Vector3(x, 0.0, borda_sul + comprimento)), [0, 13])
	var saida := Vector3(0.0, sin(angulo_salto), -cos(angulo_salto))
	var lancador := _area("Lancador", Transform3D(Basis(), Vector3(x, altura - 1.2, borda_sul + 1.5)), Vector3(6.0, 3.0, 3.0))
	lancador.body_entered.connect(func(corpo: Node3D):
		if corpo.has_method("impulsionar"):
			corpo.impulsionar(saida, velocidade_salto, true))
	_prisma("RampaPouso", _perfil_pouso(altura), 8.0, Transform3D(Basis(), Vector3(x, 0.0, borda_norte)), [1, 24])
	_turbo(Vector3(x, 0.0, borda_sul + comprimento + 10.0), 0.0, turbo_salto)
	_ocupado.append([Vector2(x, ABISMO_Z), 70.0])

## Perfil (distância depois da borda norte, altura) da rampa de pouso. Simula o voo do
## carro saindo do lançador, com a gravidade e o amortecimento linear padrão do projeto
## (o carro sai ~1,6 m antes da borda, com a origem ~0,6 m abaixo do topo da rampa)
func _perfil_pouso(altura_lancamento: float) -> PackedVector2Array:
	var largura := ABISMO_MEIA * 2.0
	var amortecimento: float = ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var p := Vector2(-1.6, altura_lancamento - 0.6)
	var v := Vector2(cos(angulo_salto), sin(angulo_salto)) * velocidade_salto
	var dt := 1.0 / 240.0
	var voo: Array[Vector2] = []
	while p.x < largura + encaixe_pouso + 1.0 and p.y > -5.0:
		v.y -= g * dt
		v *= 1.0 - amortecimento * dt
		p += v * dt
		voo.append(p)
	var altura_em := func(d: float) -> Vector2:
		for i in range(1, voo.size()):
			if voo[i].x >= d + largura:
				var a: Vector2 = voo[i - 1]
				var b: Vector2 = voo[i]
				var y := lerpf(a.y, b.y, (d + largura - a.x) / (b.x - a.x))
				return Vector2(y, (b.y - a.y) / (b.x - a.x))
		return Vector2(0.0, 0.0)
	var pontos := PackedVector2Array([Vector2(0.0, 0.0)])
	# Encaixe: a folga diminui até zero em `encaixe_pouso` metros
	for i in 13:
		var d := encaixe_pouso * i / 12.0
		pontos.append(Vector2(d, altura_em.call(d).x - folga_pouso * (1.0 - d / encaixe_pouso)))
	# Achatamento: a inclinação da parábola diminui linearmente até zero no chão
	var fim: Vector2 = altura_em.call(encaixe_pouso)
	var h := fim.x
	var s := minf(fim.y, -0.05)
	var resto := 2.0 * h / -s
	for i in range(1, 13):
		var t := resto * i / 12.0
		pontos.append(Vector2(encaixe_pouso + t, maxf(h + s * t * (1.0 - t / (2.0 * resto)), 0.0)))
	return pontos

# --- Loops 360° --------------------------------------------------------------

## Loop com entrada e saída em clotoide (a curvatura cresce aos poucos), deslocado de
## lado para a saída não bater na entrada. Turbo antes. A suspensão de raio não aguenta
## os ~7 g da curva, então o carro anda nele como num trilho (car.gd: entrar_trilho),
## com a gravidade freando na subida; lento demais, desgruda e cai.
func _montar_loop(nome: String, inicio: Vector3, rumo: float):
	var raio_min := 5.5
	var rampa := 8.0
	var k := 1.0 / raio_min
	var meio := (TAU - k * rampa) / k
	var total := rampa * 2.0 + meio
	var reta := 12.0
	var deslocamento := 6.5
	var passo := 0.5
	var pontos := PackedVector3Array()
	var cimas := PackedVector3Array()
	var frente := 0.0
	var alto := RENTE
	var theta := 0.0
	var s := -reta
	while s <= total + reta + 0.001:
		var no_loop := clampf(s, 0.0, total)
		var lado := deslocamento * smoothstep(0.0, 1.0, theta / TAU)
		pontos.append(Vector3(lado, alto, -frente))
		cimas.append(Vector3(0.0, cos(theta), sin(theta)))
		# Integra o ângulo de arfagem pela curvatura (Euler semi-implícito, passo curto)
		var curv := 0.0
		if s >= 0.0 and s < total:
			if no_loop < rampa: curv = k * no_loop / rampa
			elif no_loop > total - rampa: curv = k * (total - no_loop) / rampa
			else: curv = k
		theta = minf(theta + curv * passo, TAU)
		frente += cos(theta) * passo
		alto += sin(theta) * passo
		s += passo
	# O erro da integração deixa a saída um tico fora do chão: nivela de volta
	var erro := alto - RENTE
	var n := pontos.size()
	for i in n:
		pontos[i].y -= erro * smoothstep(0.5, 1.0, float(i) / (n - 1))
	var base := Transform3D(Basis(Vector3.UP, rumo), inicio)
	for i in n:
		pontos[i] = base * pontos[i]
		cimas[i] = base.basis * cimas[i]
	_fita(nome, pontos, cimas)
	_turbo(base * Vector3(0.0, 0.0, 6.0), rumo, turbo_loop)
	var dist := PackedFloat32Array([0.0])
	for i in range(1, n):
		dist.append(dist[i - 1] + pontos[i].distance_to(pontos[i - 1]))
	var trilho := {"pontos": pontos, "cimas": cimas, "dist": dist}
	var entrada := _area("Entrada" + nome, Transform3D(base.basis, base * Vector3(0.0, 0.0, -1.5)), Vector3(LARGURA, 2.0, 3.0))
	entrada.body_entered.connect(func(corpo: Node3D):
		if corpo.has_method("entrar_trilho"):
			corpo.entrar_trilho(trilho))
	_ocupado.append([Vector2(inicio.x, inicio.z) + Vector2(0.0, -12.0).rotated(-rumo), 30.0])

# --- Rampas soltas -------------------------------------------------------------

func _montar_rampa(pos: Vector3, rumo: float):
	var comprimento := 9.0
	var altura := 1.3
	var perfil := PackedVector2Array([Vector2(0.0, 0.0)])
	for i in range(1, 11):
		var d := comprimento * i / 10.0
		perfil.append(Vector2(d, altura * pow(d / comprimento, 2.0)))
	perfil.append(Vector2(comprimento, 0.0))
	_prisma("Rampa", perfil, 5.0, Transform3D(Basis(Vector3.UP, rumo), pos), [0, 9])
	_ocupado.append([Vector2(pos.x, pos.z), 12.0])

## Placa de turbo no chão; o impulso aponta para a frente da placa (-Z local)
func _turbo(pos: Vector3, rumo: float, alvo: float):
	var area := _area("Turbo", Transform3D(Basis(Vector3.UP, rumo), pos), Vector3(LARGURA, 2.0, 6.0))
	var placa := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(LARGURA - 0.6, 6.0)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_IMPULSO
	plano.material = mat
	placa.mesh = plano
	placa.position.y = RENTE + 0.02
	placa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(placa)
	var direcao := -area.global_basis.z
	area.body_entered.connect(func(corpo: Node3D):
		if corpo.has_method("impulsionar"):
			corpo.impulsionar(direcao, alvo))

## Área que detecta o carro do jogador (camada 3, a mesma que os portões da corrida
## enxergam), com a base da caixa no chão
func _area(nome: String, t: Transform3D, tamanho: Vector3) -> Area3D:
	var area := Area3D.new()
	area.name = nome
	area.collision_layer = 0
	area.collision_mask = 4
	area.monitorable = false
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = tamanho
	forma.shape = caixa
	forma.position.y = tamanho.y * 0.5
	area.add_child(forma)
	area.transform = t
	add_child(area, true)
	return area

# --- Geometria -----------------------------------------------------------------

## Pista com mureta extrudada ao longo de `pontos` (topo da pista), virada para `cimas`
func _fita(nome: String, pontos: PackedVector3Array, cimas: PackedVector3Array):
	var meia := LARGURA * 0.5
	var perfil := PackedVector2Array([
		Vector2(-meia, MURETA), Vector2(-meia + MURETA_LARGURA, MURETA),
		Vector2(-meia + MURETA_LARGURA, 0.0), Vector2(meia - MURETA_LARGURA, 0.0),
		Vector2(meia - MURETA_LARGURA, MURETA), Vector2(meia, MURETA),
		Vector2(meia, -ESPESSURA), Vector2(-meia, -ESPESSURA)])
	var n := pontos.size()
	var m := perfil.size()
	var anel: Array[PackedVector3Array] = []
	var dist := PackedFloat32Array()
	var acumulado := 0.0
	for i in n:
		var t := (pontos[mini(i + 1, n - 1)] - pontos[maxi(i - 1, 0)]).normalized()
		var lado := t.cross(cimas[i]).normalized()
		var cima := lado.cross(t)
		var a := PackedVector3Array()
		for p in perfil:
			a.append(pontos[i] + lado * p.x + cima * p.y)
		anel.append(a)
		if i > 0:
			acumulado += pontos[i].distance_to(pontos[i - 1])
		dist.append(acumulado)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in m:
		var j2 := (j + 1) % m
		var largura_face := perfil[j].distance_to(perfil[j2])
		var tamanho := Vector2(largura_face, acumulado)
		var rodagem := 1.0 if j == 2 else 0.0
		for i in n - 1:
			_quad(st, [anel[i][j], anel[i][j2], anel[i + 1][j2], anel[i + 1][j]],
				[Vector2(0.0, dist[i]), Vector2(largura_face, dist[i]), Vector2(largura_face, dist[i + 1]), Vector2(0.0, dist[i + 1])],
				tamanho, rodagem)
	# Tampas nas duas pontas
	var tris := Geometry2D.triangulate_polygon(perfil)
	var caixa_tampa := Vector2(LARGURA, MURETA + ESPESSURA)
	for ponta in [0, n - 1]:
		for idx in tris:
			var p := perfil[idx]
			st.set_color(Color.BLACK)
			st.set_uv(Vector2(p.x + meia, p.y + ESPESSURA))
			st.set_uv2(caixa_tampa)
			st.add_vertex(anel[ponta][idx])
	_corpo(nome, st.commit(), Transform3D.IDENTITY, _material, true)

## Perfil lateral (distância para a frente, altura) extrudado na largura. A frente é -Z
## local; `rodagem` lista as arestas do perfil por onde o carro anda (ganham faixas)
func _prisma(nome: String, perfil: PackedVector2Array, largura: float, t: Transform3D, rodagem: Array):
	var meia := largura * 0.5
	var m := perfil.size()
	var p3 := func(p: Vector2, x: float) -> Vector3: return Vector3(x, p.y, -p.x)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Superfície de rodagem: um contorno só (sem linhas a cada segmento da curva)
	var corrido := 0.0
	var total := 0.0
	for j in m:
		total += perfil[j].distance_to(perfil[(j + 1) % m])
	for j in m:
		var j2 := (j + 1) % m
		var comp := perfil[j].distance_to(perfil[j2])
		var anda: bool = j >= rodagem[0] and j <= rodagem[rodagem.size() - 1]
		var y0 := corrido if anda else 0.0
		var tamanho := Vector2(largura, _comprimento_rodagem(perfil, rodagem) if anda else comp)
		if anda:
			corrido += comp
		_quad(st, [p3.call(perfil[j], -meia), p3.call(perfil[j], meia), p3.call(perfil[j2], meia), p3.call(perfil[j2], -meia)],
			[Vector2(0.0, y0), Vector2(largura, y0), Vector2(largura, y0 + comp), Vector2(0.0, y0 + comp)],
			tamanho, 1.0 if anda else 0.0)
	var minimo := Vector2(INF, INF)
	var maximo := -minimo
	for p in perfil:
		minimo = minimo.min(p)
		maximo = maximo.max(p)
	var tris := Geometry2D.triangulate_polygon(perfil)
	for x in [-meia, meia]:
		for idx in tris:
			st.set_color(Color.BLACK)
			st.set_uv(perfil[idx] - minimo)
			st.set_uv2(maximo - minimo)
			st.add_vertex(p3.call(perfil[idx], x))
	_corpo(nome, st.commit(), t, _material, true)

func _comprimento_rodagem(perfil: PackedVector2Array, rodagem: Array) -> float:
	var total := 0.0
	var m := perfil.size()
	for j in range(rodagem[0], rodagem[rodagem.size() - 1] + 1):
		total += perfil[j].distance_to(perfil[(j + 1) % m])
	return total

## Caixa com UV por face em metros (o contorno neon acompanha as arestas)
func _malha_caixa(tamanho: Vector3) -> ArrayMesh:
	var h := tamanho * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := func(x: float, y: float, z: float) -> Vector3: return Vector3(x * h.x, y * h.y, z * h.z)
	# Cada face: quatro cantos e seu tamanho (largura, altura) em metros
	var faces := [
		[[c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1)], Vector2(tamanho.x, tamanho.y)],
		[[c.call(1, -1, -1), c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(1, 1, -1)], Vector2(tamanho.x, tamanho.y)],
		[[c.call(-1, 1, 1), c.call(1, 1, 1), c.call(1, 1, -1), c.call(-1, 1, -1)], Vector2(tamanho.x, tamanho.z)],
		[[c.call(-1, -1, -1), c.call(-1, -1, 1), c.call(-1, 1, 1), c.call(-1, 1, -1)], Vector2(tamanho.z, tamanho.y)],
		[[c.call(1, -1, 1), c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1)], Vector2(tamanho.z, tamanho.y)]]
	for f in faces:
		var s: Vector2 = f[1]
		_quad(st, f[0], [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)], s, 0.0)
	return st.commit()

func _quad(st: SurfaceTool, v: Array, uv: Array, tamanho: Vector2, rodagem: float):
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(rodagem, 0.0, 0.0))
		st.set_uv(uv[idx])
		st.set_uv2(tamanho)
		st.add_vertex(v[idx])

## Malha + corpo estático (colisão de malha dos dois lados, na camada do chão)
func _corpo(nome: String, malha: ArrayMesh, t: Transform3D, material: Material, colide: bool) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.name = nome
	corpo.collision_layer = collision_layer if colide else 0
	corpo.collision_mask = 0
	corpo.transform = t
	var vista := MeshInstance3D.new()
	vista.mesh = malha
	vista.material_override = material
	vista.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vista.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	corpo.add_child(vista)
	if colide:
		var forma := CollisionShape3D.new()
		var concava := malha.create_trimesh_shape()
		concava.backface_collision = true
		forma.shape = concava
		corpo.add_child(forma)
	add_child(corpo, true)
	return corpo
