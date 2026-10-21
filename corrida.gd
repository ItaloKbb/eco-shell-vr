class_name Corrida
extends Node
## Voltas e cronômetro do circuito. A volta só vale passando por todos os portões da
## pista na ordem (sem atalho pelo miolo). A primeira passagem pela linha de largada
## dispara o cronômetro; cada passagem seguinte fecha a volta, guarda a última e a
## melhor. O texto vai para o lado esquerdo do visor do capacete (car.gd painel_corrida).

var pista: PistaCorrida
var carro: RigidBody3D

var volta := 0
var _proximo := 0
var _inicio := -1.0
var _ultima := -1.0
var _melhor := -1.0
var _som: AudioStreamPlayer
## Tempo de corrida somado na física (não o relógio do computador: engasgos não contam)
var _relogio := 0.0

func _physics_process(delta: float):
	if carro != null and carro.em_transicao:
		return
	_relogio += delta

func _ready():
	pista.portao.connect(_portao)
	_som = AudioStreamPlayer.new()
	_som.bus = "Carro"
	add_child(_som)

func reiniciar():
	volta = 0
	_proximo = 0
	_inicio = -1.0
	_ultima = -1.0

func _portao(k: int):
	if carro == null or carro.em_transicao or k != _proximo:
		return
	_proximo = (k + 1) % PistaCorrida.PORTOES
	var agora := _relogio
	if k != 0:
		_tocar("clique", 1.5, -8.0)
		return
	if _inicio >= 0.0:
		_ultima = agora - _inicio
		var recorde := _melhor < 0.0 or _ultima < _melhor
		if recorde:
			_melhor = _ultima
		_tocar("volta", 1.25 if recorde else 1.0, -4.0)
	else:
		_tocar("volta", 0.8, -6.0)
	volta += 1
	_inicio = agora

func _tocar(nome: String, pitch: float, volume: float):
	var som: AudioStream = SomGerador.biblioteca.get(nome)
	if som:
		_som.stream = som
		_som.pitch_scale = pitch
		_som.volume_db = volume
		_som.play()

func _process(_delta):
	if carro == null:
		return
	var agora := _relogio
	var atual := agora - _inicio if _inicio >= 0.0 else 0.0
	carro.painel_corrida = "VOLTA %3d\nT  %s\nULT %s\nMEL %s" % [volta, _tempo(atual), _tempo(_ultima), _tempo(_melhor)]

func _tempo(s: float) -> String:
	if s < 0.0:
		return "-:--.-"
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]
