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
