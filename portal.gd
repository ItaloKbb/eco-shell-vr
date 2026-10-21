class_name Portal
extends Node3D
## Portal de corrida: uma esfera de vórtice flutuando acima do chão, na cor do portal,
## sugando tudo em volta. Por enquanto não leva a lugar nenhum; é a estética e o puxão.
##
## - Casca esférica (portal_esfera.gdshader): borda brilhante e faixas em espiral
## - Dentro, o vórtice (portal.gdshader): túnel com profundidade, espiral e borda em
##   chamas, sempre virado para a câmera, então é redondo de qualquer ângulo
## - Faíscas e fiapos de névoa vindo de todas as direções em espiral, poeira do chão
## - Hexágonos arrancados do chão orbitando em órbitas inclinadas e caindo no vórtice
## - Luz na cor do portal no chão, feixe até o céu para achar de longe, ronco de vento
## - Perto, puxa o carro de leve (car.gd puxar())
## Longe do carro, partículas, detritos e luz desligam (o vórtice e o feixe ficam).

## Raio do vórtice e altura do centro acima do chão (m)
const RAIO := 4.5
## (a esfera encosta no chão: dá para entrar dirigindo)
const ALTURA := 4.2
## Tamanho do carro para o toque: encostar a lataria na esfera já conta como entrar
const ENTRADA := 1.4

## O carro entrou no portal
signal atravessado
const ALCANCE_PUXAO := 20.0
## Aceleração máxima do puxão, bem perto (m/s²): ~0,45 g, dá para vencer acelerando
const PUXAO_MAX := 4.5
## Distância até onde as partículas e detritos ficam ligados
const PERTO := 120.0
const DETRITOS := 16
const RAIO_DETRITOS := 9.0

var cor := Color(0.1, 0.85, 1.0)
## O destino também determina se este portal recebe o marcador de corrida.
var destino_corrida := ""
var alvo: RigidBody3D

var _vortice := Node3D.new()
## O disco do vórtice, que vira para a câmera a cada quadro
var _disco := MeshInstance3D.new()
var _particulas: Array[GPUParticles3D] = []
var _detritos := MultiMesh.new()
var _detritos_no: MultiMeshInstance3D
## Cada detrito: [ângulo, avanço até o centro (0 a 1), velocidade, plano da órbita, eixo de giro]
var _estado_detritos: Array = []
var _luz := OmniLight3D.new()
var _perto := true
var _pronto := true

func _ready():
	add_to_group("portais")
	if not destino_corrida.is_empty():
		var marcador := Label3D.new()
		marcador.name = "MarcadorCorrida"
		marcador.text = "CORRIDA\n%s\n▼" % destino_corrida.to_upper()
		marcador.position = Vector3.UP * (ALTURA + RAIO + 2.5)
		marcador.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marcador.font_size = 48
		marcador.pixel_size = 0.012
		marcador.modulate = Color(1.0, 0.95, 0.75)
		marcador.outline_modulate = Color(0.02, 0.02, 0.06)
		marcador.outline_size = 12
		marcador.shaded = false
		add_child(marcador)
	_vortice.position = Vector3.UP * ALTURA
	add_child(_vortice)

	var quad := QuadMesh.new()
	quad.size = Vector2(12.0, 12.0)
	_disco.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = preload("res://portal.gdshader")
	material.set_shader_parameter("cor", cor)
	material.set_shader_parameter("tamanho", 6.0)
	material.set_shader_parameter("raio", RAIO / 6.0)
	# Transparentes com o mesmo centro trocariam de ordem conforme o ângulo (pisca):
	# ordem fixa: feixe, vórtice, casca da esfera e por fim as partículas
	material.render_priority = -2
	_disco.material_override = material
	_disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortice.add_child(_disco)

	var bola := SphereMesh.new()
	bola.radius = RAIO
	bola.height = RAIO * 2.0
	bola.radial_segments = 48
	bola.rings = 24
	var casca := MeshInstance3D.new()
	casca.mesh = bola
	var material_casca := ShaderMaterial.new()
	material_casca.shader = preload("res://portal_esfera.gdshader")
	material_casca.set_shader_parameter("cor", cor)
	material_casca.render_priority = -1
	casca.material_override = material_casca
	casca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortice.add_child(casca)

	_vortice.add_child(_faiscas())
	_vortice.add_child(_nevoa())
	_vortice.add_child(_poeira())
	_montar_detritos()

	_luz.light_color = cor
	_luz.light_energy = 3.0
	_luz.omni_range = 16.0
	_vortice.add_child(_luz)

	var feixe := MeshInstance3D.new()
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = 0.35
	cilindro.bottom_radius = 0.35
	cilindro.height = 80.0
	cilindro.radial_segments = 12
	cilindro.rings = 0
	feixe.mesh = cilindro
	var material_feixe := ShaderMaterial.new()
	material_feixe.shader = preload("res://feixe_portal.gdshader")
	material_feixe.set_shader_parameter("cor", cor)
	material_feixe.set_shader_parameter("altura", 80.0)
	material_feixe.render_priority = -3
	feixe.material_override = material_feixe
	feixe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	feixe.position = Vector3.UP * (ALTURA + RAIO + 40.0)
	add_child(feixe)

	var som := SomGerador.fonte("portal")
	som.unit_size = 8.0
	som.max_distance = 90.0
	_vortice.add_child(som)
	if som.stream:
		som.play()

## Faíscas nascendo numa casca em volta da esfera e entrando em espiral, encolhendo
func _faiscas() -> GPUParticles3D:
	var p := Explosao._particulas(220, 1.1, Vector2(0.05, 0.14), false)
	var m: ParticleProcessMaterial = p.process_material
	_casca(m, RAIO + 1.4, -9.0, 5.0)
	m.scale_curve = Explosao._curva(1.0, 0.15)
	var c := cor
	# Some antes de chegar ao centro: o núcleo tem que continuar escuro
	m.color_ramp = Explosao._rampa([Color(c.r, c.g, c.b, 0.0), Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 1.0), Color(c.r * 1.3 + 0.2, c.g * 1.3 + 0.2, c.b * 1.3 + 0.2, 0.7), Color(c.r, c.g, c.b, 0.0), Color(c.r, c.g, c.b, 0.0)])
	p.local_coords = true
	p.emitting = true
	_particulas.append(p)
	return p

## Fiapos grandes e suaves de névoa girando para dentro
func _nevoa() -> GPUParticles3D:
	var p := Explosao._particulas(30, 3.0, Vector2(1.5, 3.0), false)
	var m: ParticleProcessMaterial = p.process_material
	_casca(m, RAIO + 2.2, -1.2, 1.6)
	m.scale_curve = Explosao._curva(1.0, 0.3)
	var c := cor
	m.color_ramp = Explosao._rampa([Color(c.r, c.g, c.b, 0.0), Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.2), Color(c.r * 0.3, c.g * 0.3, c.b * 0.3, 0.0), Color(c.r, c.g, c.b, 0.0)])
	p.local_coords = true
	p.emitting = true
	_particulas.append(p)
	return p

## Poeira que nasce no chão em volta e é puxada para dentro do vórtice
func _poeira() -> GPUParticles3D:
	var p := Explosao._particulas(90, 3.0, Vector2(0.05, 0.14), false)
	var m: ParticleProcessMaterial = p.process_material
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(10.0, 0.2, 10.0)
	m.emission_shape_offset = Vector3(0.0, -ALTURA + 0.3, 0.0)
	m.radial_accel_min = -4.0
	m.radial_accel_max = -2.5
	m.tangential_accel_min = 1.0
	m.tangential_accel_max = 2.0
	m.gravity = Vector3.ZERO
	m.damping_min = 0.3
	m.damping_max = 0.6
	var c := cor
	m.color_ramp = Explosao._rampa([Color(c.r, c.g, c.b, 0.0), Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.7), Color(c.r, c.g, c.b, 0.0)])
	p.local_coords = true
	p.emitting = true
	_particulas.append(p)
	return p

## Emissão numa casca esférica em volta do vórtice, puxando (radial negativo) e
## girando (tangencial)
func _casca(m: ParticleProcessMaterial, raio: float, puxa: float, gira: float):
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	m.emission_sphere_radius = raio
	m.radial_accel_min = puxa * 1.2
	m.radial_accel_max = puxa * 0.8
	m.tangential_accel_min = gira * 0.8
	m.tangential_accel_max = gira * 1.2
	m.gravity = Vector3.ZERO
	m.damping_min = 0.5
	m.damping_max = 1.0

## Pedaços de chão hexagonal, escuros com brilho na cor do portal
func _montar_detritos():
	var prisma := CylinderMesh.new()
	prisma.top_radius = 0.4
	prisma.bottom_radius = 0.4
	prisma.height = 0.28
	prisma.radial_segments = 6
	prisma.rings = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.05, 0.06, 0.13)
	material.metallic = 0.6
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = cor
	material.emission_energy_multiplier = 0.5
	prisma.material = material
	_detritos.transform_format = MultiMesh.TRANSFORM_3D
	_detritos.mesh = prisma
	_detritos.instance_count = DETRITOS
	for i in DETRITOS:
		# Cada um numa órbita inclinada diferente em volta da esfera
		var orbita := Basis(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(), randf() * TAU)
		_estado_detritos.append([randf() * TAU, randf(), randf_range(0.07, 0.14), orbita,
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()])
	_detritos_no = MultiMeshInstance3D.new()
	_detritos_no.multimesh = _detritos
	_vortice.add_child(_detritos_no)

func _process(delta: float):
	var cam := get_viewport().get_camera_3d()
	if cam:
		# O disco do vórtice sempre de frente para a câmera (+Z do quad para ela)
		var para_fora := _disco.global_position - cam.global_position
		if para_fora.length() > 0.1:
			var cima := Vector3.UP if absf(para_fora.normalized().y) < 0.98 else Vector3.FORWARD
			_disco.global_basis = Basis.looking_at(para_fora, cima)
	var perto := cam != null and cam.global_position.distance_to(global_position) < PERTO
	if perto != _perto:
		_perto = perto
		for p in _particulas:
			p.emitting = perto
		_detritos_no.visible = perto
		_luz.visible = perto
	if not perto:
		return
	_luz.light_energy = 3.0 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 3.1)
	var t := Time.get_ticks_msec() / 1000.0
	for i in DETRITOS:
		var d: Array = _estado_detritos[i]
		d[1] += d[2] * delta
		if d[1] >= 1.0:
			d[1] = 0.0
			d[0] = randf() * TAU
		var raio := lerpf(RAIO_DETRITOS, 0.4, d[1] * d[1])
		# Gira mais rápido quanto mais perto do centro, como água no ralo
		d[0] += delta * 1.6 / maxf(raio, 0.6)
		var orbita: Basis = d[3]
		var pos := orbita * Vector3(cos(d[0]) * raio, sin(d[0]) * raio, 0.0)
		var tamanho := clampf(raio / 2.5, 0.05, 1.0)
		var b := Basis(d[4], t * (1.0 + 3.0 * d[1])).scaled(Vector3.ONE * tamanho)
		_detritos.set_instance_transform(i, Transform3D(b, pos))

func _physics_process(_delta: float):
	if alvo == null or alvo.explodindo or alvo.em_ritual or alvo.em_transicao:
		return
	var centro := _vortice.global_position
	var para := centro - alvo.global_transform * Vector3(0.0, 0.4, 0.0)
	# A força cai com a distância no chão (o centro está no alto)
	var d := Vector2(para.x, para.z).length()
	if d < ALCANCE_PUXAO and para.length() > 0.5:
		var forca := PUXAO_MAX * pow(1.0 - d / ALCANCE_PUXAO, 1.5)
		alvo.puxar(para.normalized() * forca)
	# Entrou: avisa uma vez (de novo só depois de um tempo)
	if para.length() < RAIO + ENTRADA and _pronto:
		_pronto = false
		atravessado.emit()
		get_tree().create_timer(5.0).timeout.connect(func(): _pronto = true)
