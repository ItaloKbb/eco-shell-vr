extends Node
## Trilha sonora: toca as músicas da pasta em ordem embaralhada, sem repetir nenhuma
## até tocar todas, com transição cruzada suave (uma vai sumindo enquanto a próxima
## entra). Dois players se revezam; tudo passa pelo barramento "Musica".

const BARRAMENTO := "Musica"

@export_dir var pasta := "res://musicas"
@export var volume_db := -9.0
## Duração da transição entre uma música e outra (s)
@export var transicao := 5.0
## Quanto a música abaixa durante o alarme de míssil, para os bipes aparecerem (dB)
@export var abaixa_alarme := 6.0

var _faixas: Array[AudioStream] = []
var _fila: Array[AudioStream] = []
var _players: Array[AudioStreamPlayer] = []
var _atual := 0
var _trocando := false
var _ultima: AudioStream

func _ready():
	if AudioServer.get_bus_index(BARRAMENTO) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, BARRAMENTO)
		AudioServer.set_bus_send(i, "Master")
	# list_directory enxerga os arquivos importados também no jogo exportado
	for nome in ResourceLoader.list_directory(pasta):
		if nome.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			_faixas.append(load(pasta.path_join(nome)))
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BARRAMENTO
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	if not _faixas.is_empty():
		_tocar_proxima(2.0)

func _process(delta):
	# Abaixa um pouco enquanto há míssil no ar
	var alarme := not get_tree().get_nodes_in_group("misseis").is_empty()
	var alvo := -abaixa_alarme if alarme else 0.0
	var bus := AudioServer.get_bus_index(BARRAMENTO)
	AudioServer.set_bus_volume_db(bus, move_toward(AudioServer.get_bus_volume_db(bus), alvo, 12.0 * delta))

	var p := _players[_atual]
	if _trocando or p.stream == null:
		return
	# Acabou sem dar tempo de cruzar (um travamento, por exemplo): segue a fila
	if not p.playing:
		_tocar_proxima(1.0)
		return
	var falta := p.stream.get_length() - p.get_playback_position()
	if falta <= transicao:
		_tocar_proxima(transicao)

## Embaralha de novo quando a fila acaba, sem deixar a mesma música tocar duas seguidas
func _proxima() -> AudioStream:
	if _fila.is_empty():
		_fila = _faixas.duplicate()
		_fila.shuffle()
		if _fila.size() > 1 and _fila[0] == _ultima:
			_fila.push_back(_fila.pop_front())
	_ultima = _fila.pop_front()
	return _ultima

func _tocar_proxima(duracao: float):
	_trocando = true
	var sai := _players[_atual]
	_atual = 1 - _atual
	var entra := _players[_atual]
	entra.stream = _proxima()
	entra.volume_db = -80.0
	entra.play()
	# Curva de volume em escala linear (soa uniforme); quem sai some no mesmo tempo
	var tw := create_tween().set_parallel()
	tw.tween_method(func(v: float): entra.volume_db = linear_to_db(v) + volume_db, 0.0001, 1.0, duracao)
	if sai.playing:
		var inicio := db_to_linear(sai.volume_db - volume_db)
		tw.tween_method(func(v: float): sai.volume_db = linear_to_db(v) + volume_db, inicio, 0.0001, duracao)
	tw.chain().tween_callback(func():
		sai.stop()
		_trocando = false)
