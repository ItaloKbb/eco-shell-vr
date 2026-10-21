class_name MissilPonta
extends Node3D
## Ponta da pirâmide lançada como míssil teleguiado. Persegue o carro com curva
## limitada (dá para desviar com curvas fechadas ou dash), tem combustível para
## poucos segundos e explode ao bater no terreno ou numa parede de luz.
## Fica no grupo "misseis": o som do carro lê tempo_para_impacto() para os bipes.

const VELOCIDADE := 20.0
## Quanto o míssil consegue virar por segundo (rad/s)
const CURVA := 1.6
const COMBUSTIVEL := 6.0
const RAIO_ACERTO := 1.3

var alvo: RigidBody3D
var velocidade := Vector3.ZERO
var malha: Mesh
var material: Material

var _vida := COMBUSTIVEL

func _ready():
	add_to_group("misseis")
	var corpo := MeshInstance3D.new()
	corpo.mesh = malha
	corpo.material_override = material
	add_child(corpo)
	# Rastro: brilho vermelho que fica para trás no mundo
	var rastro := Explosao._particulas(40, 0.6, Vector2(0.12, 0.25), false)
	rastro.local_coords = false
	rastro.emitting = true
	var m: ParticleProcessMaterial = rastro.process_material
	m.spread = 10.0
	m.direction = Vector3(0, -1, 0)
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.5
	m.gravity = Vector3.ZERO
	m.scale_curve = Explosao._curva(1.0, 0.1)
	m.color_ramp = Explosao._rampa([Color(1.4, 0.4, 0.5, 0.9), Color(0.6, 0.1, 0.25, 0.5), Color(0.1, 0.05, 0.08, 0.0)])
	add_child(rastro)
	var som := SomGerador.fonte("missil")
	add_child(som)
	if som.stream:
		som.play()

## Segundos até acertar o carro, pela distância e pela velocidade de aproximação
func tempo_para_impacto() -> float:
	if alvo == null:
		return INF
	var para_alvo := _ponto_alvo() - global_position
	var v_alvo: Vector3 = alvo.velocidade_mundo()
	var fechando := (velocidade - v_alvo).dot(para_alvo.normalized())
	return para_alvo.length() / maxf(fechando, 1.0)

func _ponto_alvo() -> Vector3:
	return alvo.global_transform * Vector3(0.0, 0.4, 0.0)

func _physics_process(delta: float):
	_vida -= delta
	if _vida <= 0.0 or alvo == null or alvo.explodindo or alvo.em_ritual:
		_estourar()
		return
	# Mira um pouco à frente do carro, onde ele vai estar
	var alvo_pos := _ponto_alvo()
	var falta := minf(tempo_para_impacto(), 1.5)
	var v_alvo: Vector3 = alvo.velocidade_mundo()
	var mira := alvo_pos + v_alvo * falta * 0.5
	var atual := velocidade.normalized()
	var desejo := (mira - global_position).normalized()
	var angulo := atual.angle_to(desejo)
	if angulo > 0.001:
		var eixo := atual.cross(desejo)
		if eixo.length() < 0.001:
			eixo = Vector3.UP
		atual = atual.rotated(eixo.normalized(), minf(angulo, CURVA * delta))
	# Sai devagar da pirâmide e acelera: dá tempo de reagir
	velocidade = atual * move_toward(velocidade.length(), VELOCIDADE, 10.0 * delta)

	var novo := global_position + velocidade * delta
	# Terreno (camada 1) e paredes de luz (camada 2) explodem o míssil
	var raio := PhysicsRayQueryParameters3D.create(global_position, novo, 3)
	var batida := get_world_3d().direct_space_state.intersect_ray(raio)
	if not batida.is_empty():
		global_position = batida.position
		_estourar()
		return
	global_position = novo
	global_basis = Basis(Quaternion(Vector3.UP, atual))
	if global_position.distance_to(alvo_pos) < RAIO_ACERTO:
		alvo.atingido_por_missil(global_position, velocidade)
		_estourar()

func _estourar():
	var explosao := Explosao.new()
	explosao.escala = 0.35
	explosao.com_pedacos = false
	get_parent().add_child(explosao)
	explosao.global_position = global_position
	queue_free()
