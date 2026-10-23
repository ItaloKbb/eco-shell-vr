extends MeshInstance3D
## Vinheta periférica presa à câmera XR. A intensidade acompanha movimento do carro,
## sem filtrar a pose da cabeça nem alterar os comandos de direção.

const ARQUIVO := "user://conforto_vr.cfg"
const NOMES := ["DESLIGADO", "MODERADO", "FORTE"]

var carro
var nivel := 1
var _material: ShaderMaterial
var _intensidade := 0.0
var _velocidade_anterior := 0.0
var _orientacao_anterior := Quaternion.IDENTITY

func _init(carro_):
	carro = carro_

func _ready():
	var config := ConfigFile.new()
	if config.load(ARQUIVO) == OK:
		nivel = clampi(int(config.get_value("vr", "conforto", nivel)), 0, 2)
	var esfera := SphereMesh.new()
	esfera.radius = 1.0
	esfera.height = 2.0
	esfera.radial_segments = 32
	esfera.rings = 16
	esfera.flip_faces = true
	mesh = esfera
	_material = ShaderMaterial.new()
	_material.shader = preload("res://vinheta_conforto.gdshader")
	_material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_orientacao_anterior = carro.global_basis.get_rotation_quaternion()
	visible = false

func ciclar() -> String:
	nivel = (nivel + 1) % NOMES.size()
	var config := ConfigFile.new()
	config.set_value("vr", "conforto", nivel)
	config.save(ARQUIVO)
	return NOMES[nivel]

func _process(delta: float):
	if delta <= 0.0:
		return
	var orientacao: Quaternion = carro.global_basis.get_rotation_quaternion()
	var giro := _orientacao_anterior.angle_to(orientacao) / delta
	_orientacao_anterior = orientacao
	var velocidade: float = carro.velocidade_mundo().length()
	var aceleracao := absf(velocidade - _velocidade_anterior) / delta
	_velocidade_anterior = velocidade
	var alvo := 0.0
	if nivel > 0 and not carro.em_ritual and not carro.em_transicao and not carro.segurado:
		var movimento := smoothstep(2.0, 13.0, velocidade) * 0.35
		var rotacao := smoothstep(0.12, 1.2, giro)
		var impulso := smoothstep(1.0, 7.0, aceleracao) * 0.7
		alvo = maxf(movimento, maxf(rotacao, impulso)) * (0.55 if nivel == 1 else 1.0)
	var resposta := 9.0 if alvo > _intensidade else 3.5
	_intensidade = lerpf(_intensidade, alvo, 1.0 - exp(-resposta * delta))
	_material.set_shader_parameter("intensidade", _intensidade)
	visible = _intensidade > 0.005
