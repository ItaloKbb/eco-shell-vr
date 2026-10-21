class_name Explosao
extends Node3D
## Explosão: bola de fogo, fumaça grossa, faíscas, clarão, estrondo e (a do carro)
## pedaços do casco voando e quicando no chão. Tudo criado em código; o nó se apaga
## sozinho. `escala` < 1 faz a explosão menor dos mísseis.
## As funções estáticas também fazem a fumaça e as faíscas de carro avariado.

const COR_LATARIA := Color(0.09, 0.42, 0.82)

## Velocidade do carro na hora: os pedaços herdam parte dela
var velocidade := Vector3.ZERO
var escala := 1.0
var com_pedacos := true

func _ready():
	add_child(_fogo())
	add_child(_fumaca_grossa())
	var faiscas := Explosao.faiscas(true)
	add_child(faiscas)
	faiscas.emitting = true
	_clarao()
	if com_pedacos:
		_pedacos()
	var som := SomGerador.fonte("explosao")
	som.unit_size = 10.0 * escala
	som.pitch_scale = 1.0 / sqrt(escala)
	som.volume_db = linear_to_db(clampf(escala, 0.3, 1.0))
	add_child(som)
	if som.stream:
		som.play()
	get_tree().create_timer(6.0).timeout.connect(queue_free)

func _fogo() -> GPUParticles3D:
	var p := Explosao._particulas(maxi(int(70 * escala), 14), 1.3, Vector2(0.5, 1.3) * escala, true)
	var m: ParticleProcessMaterial = p.process_material
	m.spread = 180.0
	m.initial_velocity_min = 2.0 * escala
	m.initial_velocity_max = 7.0 * escala
	m.gravity = Vector3(0, 1.5, 0)
	m.damping_min = 3.0
	m.damping_max = 5.0
	m.scale_curve = Explosao._curva(0.4, 1.6)
	# Um pouco acima de 1 para o glow acender, sem estourar para branco
	m.color_ramp = Explosao._rampa([Color(1.3, 0.75, 0.25, 1.0), Color(1.1, 0.35, 0.06, 0.9), Color(0.5, 0.1, 0.03, 0.6), Color(0.06, 0.05, 0.05, 0.0)])
	return p

func _fumaca_grossa() -> GPUParticles3D:
	var p := Explosao._particulas(maxi(int(55 * escala), 10), 4.5 * sqrt(escala), Vector2(1.0, 2.4) * escala, true)
	var m: ParticleProcessMaterial = p.process_material
	m.spread = 180.0
	m.initial_velocity_min = 1.0 * escala
	m.initial_velocity_max = 3.0 * escala
	m.gravity = Vector3(0, 0.7, 0)
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_curve = Explosao._curva(0.5, 2.0)
	m.color_ramp = Explosao._rampa([Color(0.12, 0.1, 0.09, 0.0), Color(0.07, 0.065, 0.065, 0.85), Color(0.05, 0.05, 0.055, 0.0)])
	return p

func _clarao():
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.6, 0.25)
	luz.light_energy = 10.0 * escala
	luz.omni_range = 14.0 * escala
	add_child(luz)
	create_tween().tween_property(luz, "light_energy", 0.0, 0.6).set_ease(Tween.EASE_OUT)

## Pedaços do casco azul (e alguns pretos, da fibra) voando para todo lado
func _pedacos():
	var azul := StandardMaterial3D.new()
	azul.albedo_color = COR_LATARIA
	azul.roughness = 0.35
	var preto := StandardMaterial3D.new()
	preto.albedo_color = Color(0.03, 0.03, 0.04)
	preto.emission_enabled = true
	preto.emission = Color(1.0, 0.35, 0.05)
	preto.emission_energy_multiplier = 1.5
	for i in 9:
		var corpo := RigidBody3D.new()
		corpo.collision_layer = 0
		corpo.collision_mask = 1
		corpo.mass = 3.0
		var tamanho := Vector3(randf_range(0.12, 0.4), randf_range(0.02, 0.05), randf_range(0.1, 0.3))
		var malha := MeshInstance3D.new()
		var caixa := BoxMesh.new()
		caixa.size = tamanho
		caixa.material = preto if i % 3 == 0 else azul
		malha.mesh = caixa
		corpo.add_child(malha)
		var forma := CollisionShape3D.new()
		forma.shape = BoxShape3D.new()
		forma.shape.size = tamanho
		corpo.add_child(forma)
		add_child(corpo)
		var rumo := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		corpo.linear_velocity = velocidade * 0.5 + rumo * randf_range(4.0, 9.0)
		corpo.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		# Somem aos poucos antes do nó inteiro ser apagado
		var tw := corpo.create_tween()
		tw.tween_interval(4.0)
		tw.tween_property(corpo, "scale", Vector3.ONE * 0.01, 0.8)

## Fumaça contínua de carro avariado (saindo da traseira, rastro no mundo)
static func fumaca() -> GPUParticles3D:
	var p := Explosao._particulas(28, 2.5, Vector2(0.25, 0.55), false)
	p.local_coords = false
	var m: ParticleProcessMaterial = p.process_material
	m.direction = Vector3(0, 1, 0.3)
	m.spread = 25.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 0.9
	m.gravity = Vector3(0, 0.8, 0)
	m.scale_curve = Explosao._curva(0.4, 2.2)
	m.color_ramp = Explosao._rampa([Color(0.3, 0.3, 0.32, 0.0), Color(0.18, 0.18, 0.2, 0.45), Color(0.1, 0.1, 0.11, 0.0)])
	return p

## Faíscas: pontos quentes voando e caindo (na explosão, um estouro só)
static func faiscas(explosao := false) -> GPUParticles3D:
	var p := Explosao._particulas(90 if explosao else 14, 1.0 if explosao else 0.5, Vector2(0.015, 0.035), explosao)
	p.local_coords = false
	var m: ParticleProcessMaterial = p.process_material
	m.spread = 180.0 if explosao else 70.0
	m.direction = Vector3(0, 1, 0)
	m.initial_velocity_min = 6.0 if explosao else 1.0
	m.initial_velocity_max = 14.0 if explosao else 3.5
	m.gravity = Vector3(0, -9.8, 0)
	m.color_ramp = Explosao._rampa([Color(1.6, 1.1, 0.5, 1.0), Color(1.3, 0.5, 0.1, 1.0), Color(0.6, 0.1, 0.02, 0.0)])
	return p

## Rajada curta usada no ponto de uma batida. Menor que a explosão e rápida o
## bastante para comunicar o contato sem encher a visão no headset.
static func faiscas_impacto(forca: float) -> GPUParticles3D:
	var quantidade := clampi(roundi(forca * 3.0), 10, 42)
	var p := Explosao._particulas(quantidade, 0.6, Vector2(0.012, 0.03), true)
	p.local_coords = false
	p.emitting = false
	var m: ParticleProcessMaterial = p.process_material
	m.direction = Vector3.UP
	m.spread = 150.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = clampf(forca * 0.75, 4.0, 10.0)
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 1.0
	m.damping_max = 2.5
	m.color_ramp = Explosao._rampa([Color(2.0, 1.4, 0.65, 1.0), Color(1.4, 0.45, 0.08, 1.0), Color(0.5, 0.05, 0.01, 0.0)])
	return p

## Faíscas contínuas de atrito; local_coords=false deixa um rastro no mundo.
static func faiscas_atrito() -> GPUParticles3D:
	var p := Explosao._particulas(24, 0.38, Vector2(0.009, 0.024), false)
	p.local_coords = false
	p.emitting = false
	var m: ParticleProcessMaterial = p.process_material
	m.direction = Vector3.UP
	m.spread = 105.0
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 4.5
	m.gravity = Vector3(0, -9.8, 0)
	m.color_ramp = Explosao._rampa([Color(1.8, 1.2, 0.45, 1.0), Color(1.1, 0.3, 0.04, 0.9), Color(0.4, 0.03, 0.01, 0.0)])
	return p

## Clarão rápido no ponto de uma batida forte (luz que some em ~0,25 s)
static func clarao_impacto(pai: Node, ponto: Vector3, cor: Color, forca := 1.0):
	if pai == null or not pai.is_inside_tree():
		return
	var luz := OmniLight3D.new()
	luz.light_color = cor
	luz.light_energy = 4.0 * forca
	luz.omni_range = 4.0 + 2.0 * forca
	luz.shadow_enabled = false
	pai.add_child(luz)
	luz.global_position = ponto
	var tw := luz.create_tween()
	tw.tween_property(luz, "light_energy", 0.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(luz.queue_free)

## Pouso forte no piso neon: um anel de energia se abre no chão e apaga
static func anel_choque(pai: Node, ponto: Vector3, cor: Color, tamanho := 1.0):
	if pai == null or not pai.is_inside_tree():
		return
	var anel := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = 0.92
	toro.outer_radius = 1.0
	toro.rings = 32
	toro.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(cor.r * 2.0, cor.g * 2.0, cor.b * 2.0, 1.0)
	toro.material = mat
	anel.mesh = toro
	anel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(anel)
	anel.global_position = Vector3(ponto.x, ponto.y + 0.04, ponto.z)
	anel.scale = Vector3(0.3, 0.05, 0.3)
	var tw := anel.create_tween().set_parallel(true)
	tw.tween_property(anel, "scale", Vector3(2.4, 0.05, 2.4) * tamanho, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(anel.queue_free)

## Pouso forte na areia: nuvem de poeira baixa se espalhando
static func poeira(pai: Node, ponto: Vector3, forca := 1.0):
	var p := Explosao._particulas(clampi(roundi(18 * forca), 8, 30), 1.4, Vector2(0.4, 0.9) * forca, true)
	var m: ParticleProcessMaterial = p.process_material
	m.direction = Vector3.UP
	m.spread = 80.0
	m.flatness = 0.6
	m.initial_velocity_min = 1.0
	m.initial_velocity_max = 3.0 * forca
	m.gravity = Vector3(0, 0.3, 0)
	m.damping_min = 2.0
	m.damping_max = 3.0
	m.scale_curve = Explosao._curva(0.5, 1.8)
	m.color_ramp = Explosao._rampa([Color(0.75, 0.62, 0.45, 0.0), Color(0.72, 0.6, 0.44, 0.55), Color(0.6, 0.5, 0.38, 0.0)])
	Explosao._soltar(pai, p, ponto, 1.6)

## Ponta de pirâmide estourando: cacos de cristal rosados voando e caindo
static func estilhacos(pai: Node, ponto: Vector3, cor: Color):
	var p := Explosao._particulas(36, 0.9, Vector2(0.03, 0.08), true)
	var m: ParticleProcessMaterial = p.process_material
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, -9.8, 0)
	m.angular_velocity_min = -720.0
	m.angular_velocity_max = 720.0
	m.color_ramp = Explosao._rampa([Color(cor.r * 2.5, cor.g * 2.5, cor.b * 2.5, 1.0), Color(cor, 0.9), Color(cor * 0.4, 0.0)])
	Explosao._soltar(pai, p, ponto, 1.2)

## Põe um efeito de uma vez só no mundo e apaga depois de `vida` segundos
static func _soltar(pai: Node, p: GPUParticles3D, ponto: Vector3, vida: float):
	if pai == null or not pai.is_inside_tree():
		p.free()
		return
	p.local_coords = false
	p.emitting = false
	pai.add_child(p)
	p.global_position = ponto
	p.emitting = true
	p.get_tree().create_timer(vida).timeout.connect(p.queue_free)

static func _particulas(quantidade: int, vida: float, tamanho: Vector2, uma_vez: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = quantidade
	p.lifetime = vida
	p.one_shot = uma_vez
	p.explosiveness = 0.92 if uma_vez else 0.0
	p.randomness = 0.5
	p.emitting = uma_vez
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ParticleProcessMaterial.new()
	m.scale_min = tamanho.x
	m.scale_max = tamanho.y
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	var quad := QuadMesh.new()
	var visual := StandardMaterial3D.new()
	visual.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	visual.vertex_color_use_as_albedo = true
	visual.albedo_texture = Explosao._bolinha()
	quad.material = visual
	p.draw_pass_1 = quad
	return p

## Mancha redonda de borda suave, para fogo e fumaça não parecerem quadrados
static func _bolinha() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

static func _rampa(cores: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var lista := PackedColorArray()
	for i in cores.size():
		offsets.append(float(i) / (cores.size() - 1))
		lista.append(cores[i])
	g.offsets = offsets
	g.colors = lista
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t

static func _curva(inicio: float, fim: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = maxf(inicio, fim)
	c.add_point(Vector2(0.0, inicio))
	c.add_point(Vector2(1.0, fim))
	var t := CurveTexture.new()
	t.curve = c
	return t
