class_name Piramide
extends Node3D
## Primeiro inimigo: uma pirâmide desmontada. O núcleo é uma esfera de energia e as
## cinco pontas (topo + quatro da base) flutuam em volta dela, girando devagar.
##
## Parada, só flutua. Quando o carro chega perto, ela acorda e persegue, mantendo
## distância e altura. De tempos em tempos trava a mira (a ponta sai da formação e
## aponta para o carro, enquanto o painel faz "pi... pi...") e lança a ponta como
## míssil teleguiado (missil_ponta.gd). A ponta lançada volta a crescer no lugar
## depois de um tempo. Longe demais, ela desiste e volta para casa.
## É invencível: o jogo é fugir e desviar.

enum { OCIOSA, PERSEGUINDO }

@export var raio_alerta := 40.0
@export var raio_ataque := 35.0
@export var raio_desiste := 110.0
@export var velocidade_max := 15.0
## Distância e altura que ela tenta manter do carro na perseguição
@export var distancia_caca := 12.0
@export var altura_caca := 3.5
@export var intervalo_tiro := 5.0
## Tempo de aviso (TRAVANDO no HUD) antes de lançar: janela para reagir
@export var tempo_mira := 1.5
@export var recarga_ponta := 6.0

const RAIO_FORMACAO := 1.6
const NUCLEO := 0.55

var alvo: RigidBody3D
var hex_world: Node3D
## Mirando agora (para os bipes e o aviso do visor)
var travando := false
var estado := OCIOSA

var _casa := Vector3.ZERO
var _vel := Vector3.ZERO
var _giro := 0.0
var _furia := 0.0
var _pontas: Array[MeshInstance3D] = []
var _direcoes: Array[Vector3] = []
## Segundos até cada ponta lançada voltar (0 = está na formação)
var _faltando: Array[float] = []
var _mirando := -1
var _mira := 0.0
var _tiro := 1.0
var _malha_ponta := CylinderMesh.new()
var _material_ponta := ShaderMaterial.new()
var _material_mira := ShaderMaterial.new()
var _material_nucleo := ShaderMaterial.new()
var _luz: OmniLight3D
## Só um míssil desta pirâmide no ar de cada vez
var _missil: MissilPonta
var _zumbido: AudioStreamPlayer3D
## Som da mira travando (sai da própria pirâmide: dá para ouvir de onde vem)
var _carga: AudioStreamPlayer3D
## Pulso de luz ao acordar e ao disparar (decai sozinho)
var _pulso := 0.0

func _ready():
	add_to_group("piramides")
	_casa = global_position
	var nucleo := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = NUCLEO
	esfera.height = NUCLEO * 2.0
	nucleo.mesh = esfera
	_material_nucleo.shader = preload("res://esfera_energia.gdshader")
	nucleo.material_override = _material_nucleo
	add_child(nucleo)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.2, 0.35)
	_luz.light_energy = 1.5
	_luz.omni_range = 7.0
	add_child(_luz)

	# Ponta: pirâmide de base quadrada (cilindro de 4 lados com topo zero)
	_malha_ponta.top_radius = 0.0
	_malha_ponta.bottom_radius = 0.32
	_malha_ponta.height = 0.8
	_malha_ponta.radial_segments = 4
	_malha_ponta.rings = 0
	_material_ponta.shader = preload("res://ponta.gdshader")
	_material_mira.shader = _material_ponta.shader
	_material_mira.set_shader_parameter("alerta", 1.0)
	# Formação de pirâmide: topo para cima e quatro cantos da base para baixo e para fora
	_direcoes = [Vector3.UP]
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		_direcoes.append(Vector3(cos(a), -0.55, sin(a)).normalized())
	for d in _direcoes:
		var ponta := MeshInstance3D.new()
		ponta.mesh = _malha_ponta
		ponta.material_override = _material_ponta
		add_child(ponta)
		_pontas.append(ponta)
		_faltando.append(0.0)

	_zumbido = SomGerador.fonte("zumbido_inimigo")
	_zumbido.unit_size = 5.0
	add_child(_zumbido)
	if _zumbido.stream:
		_zumbido.play()

func _physics_process(delta: float):
	var perto: bool = alvo != null and not alvo.explodindo and not alvo.em_ritual
	var distancia := global_position.distance_to(alvo.global_position) if perto else INF
	match estado:
		OCIOSA:
			if distancia < raio_alerta:
				estado = PERSEGUINDO
				_tiro = 1.0
				_acordar()
			_mover_para(_casa + Vector3.UP * sin(Time.get_ticks_msec() / 1000.0) * 0.4, 4.0, delta)
		PERSEGUINDO:
			if distancia > raio_desiste:
				estado = OCIOSA
				_cancelar_mira()
			else:
				_cacar(delta, distancia)
	_furia = move_toward(_furia, 1.0 if estado == PERSEGUINDO else 0.0, delta)
	_material_nucleo.set_shader_parameter("furia", _furia)
	_pulso = maxf(_pulso - 2.5 * delta, 0.0)
	_luz.light_energy = 1.5 + 2.0 * _furia + 6.0 * _pulso
	# Zumbido: mais alto e mais agudo com a fúria; a biblioteca pode chegar depois
	if _zumbido.stream == null and SomGerador.biblioteca.has("zumbido_inimigo"):
		_zumbido.stream = SomGerador.biblioteca["zumbido_inimigo"]
		_zumbido.play()
	_zumbido.pitch_scale = 1.0 + 0.3 * _furia + 0.15 * (1.0 - _mira / tempo_mira if _mirando >= 0 else 0.0)
	_zumbido.volume_db = lerpf(-6.0, 0.0, _furia)
	_animar_pontas(delta)

func _cacar(delta: float, distancia: float):
	# Fica a uma distância do carro, um pouco acima, do lado em que já está
	var carro := alvo.global_position
	var lado := (global_position - carro)
	lado.y = 0.0
	if lado.length() < 0.1:
		lado = Vector3.BACK
	var destino := carro + lado.normalized() * distancia_caca + Vector3.UP * altura_caca
	_mover_para(destino, velocidade_max, delta)

	_tiro -= delta
	if _mirando < 0 and _tiro <= 0.0 and distancia < raio_ataque and not is_instance_valid(_missil):
		var livre := _faltando.find(0.0)
		if livre >= 0:
			_mirando = livre
			_mira = tempo_mira
			travando = true
			_tocar_carga()
			_pontas[livre].material_override = _material_mira
	if _mirando >= 0:
		_mira -= delta
		if _mira <= 0.0:
			_lancar(_mirando)

func _mover_para(destino: Vector3, maxima: float, delta: float):
	var desejo := ((destino - global_position) * 1.2).limit_length(maxima)
	_vel = _vel.lerp(desejo, minf(2.0 * delta, 1.0))
	var pos := global_position + _vel * delta
	# Nunca rasante: sempre acima do terreno
	var chao: float = hex_world.altura(pos.x, pos.z) if hex_world else 0.0
	pos.y = maxf(pos.y, chao + 2.5)
	global_position = pos

func _lancar(i: int):
	var ponta := _pontas[i]
	var missil := MissilPonta.new()
	missil.alvo = alvo
	missil.malha = _malha_ponta
	missil.material = _material_mira
	var para_carro := (alvo.global_position - ponta.global_position).normalized()
	missil.velocidade = _vel + para_carro * 4.0
	get_parent().add_child(missil)
	missil.global_transform = ponta.global_transform
	_missil = missil
	_parar_carga()
	_pulso = 1.0
	var som := SomGerador.fonte("lancamento")
	add_child(som)
	if som.stream:
		som.play()
		som.finished.connect(som.queue_free)
	ponta.visible = false
	ponta.material_override = _material_ponta
	_faltando[i] = recarga_ponta
	_mirando = -1
	travando = false
	_tiro = intervalo_tiro

func _cancelar_mira():
	_parar_carga()
	if _mirando >= 0:
		_pontas[_mirando].material_override = _material_ponta
	_mirando = -1
	travando = false

## Acordou: rosnado subindo e um pulso de luz no núcleo
func _acordar():
	_pulso = 1.0
	SomGerador.tocar_em(self, global_position, "acordar", 0.0, randf_range(0.92, 1.05), 8.0)

## Carga da mira: o tom sobe junto com o tempo de mira (o som dura exatamente isso)
func _tocar_carga():
	_parar_carga()
	_carga = SomGerador.tocar_em(self, global_position, "carga_mira", -3.0, 1.1 / tempo_mira, 7.0)

func _parar_carga():
	if is_instance_valid(_carga):
		_carga.queue_free()
	_carga = null

## Formação girando e balançando; a ponta que mira sai para fora e aponta para o
## carro; as lançadas voltam crescendo no lugar
func _animar_pontas(delta: float):
	_giro += delta * (0.4 + 1.2 * _furia)
	var t := Time.get_ticks_msec() / 1000.0
	var roda := Basis(Vector3.UP, _giro)
	for i in _pontas.size():
		var ponta := _pontas[i]
		if _faltando[i] > 0.0:
			_faltando[i] = maxf(_faltando[i] - delta, 0.0)
			ponta.visible = _faltando[i] < 1.0
			ponta.scale = Vector3.ONE * clampf(1.0 - _faltando[i], 0.01, 1.0)
		var d: Vector3 = roda * _direcoes[i]
		var pos := d * (RAIO_FORMACAO + 0.12 * sin(t * 2.0 + i))
		var aponta := d
		if i == _mirando:
			var k := 1.0 - _mira / tempo_mira
			pos = d * (RAIO_FORMACAO + 0.9 * k)
			var para_carro := to_local(alvo.global_position) - pos
			aponta = d.slerp(para_carro.normalized(), k)
		ponta.position = pos
		ponta.basis = Basis(Quaternion(Vector3.UP, aponta.normalized())).scaled(ponta.scale)
