extends Node
## Óculos conectados ao servidor (autoload; só usado no modo servidor): estado, nome do
## jogador liberado, ping, bateria e último heartbeat de cada peer. O apelido ("Óculos 3")
## fica preso ao OS.get_unique_id() do aparelho em user://dispositivos.json, e por isso
## sobrevive a reinicializações e a outros dias de evento.

const ARQUIVO := "user://dispositivos.json"
const ESTADOS := ["idle", "lobby", "correndo", "menu"]
## Sem heartbeat há mais que isso (s): a linha do painel fica em alerta
const LIMITE_HEARTBEAT := 10.0
## Telemetria mais velha que isso (s) não vai para o espectador nem para o painel
const LIMITE_TELEMETRIA := 2.0

signal mudou

## peer -> {peer, ip, unique_id, modelo, aparelho, versao, apelido, jogador, liberado,
## estado, bateria, fps, conectado_em, ultimo_heartbeat, telemetria, telemetria_em}
## (telemetria: car.gd telemetria(), a ~10 Hz enquanto liberado)
var lista := {}
## unique_id -> apelido
var _apelidos := {}

func _ready():
	if FileAccess.file_exists(ARQUIVO):
		var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
		if dados is Dictionary:
			_apelidos = dados

func adicionar(peer: int, ip: String):
	var agora := _agora()
	lista[peer] = {
		"peer": peer, "ip": ip, "unique_id": "", "modelo": "", "aparelho": "", "versao": "",
		"apelido": "", "jogador": "", "liberado": false, "estado": "idle",
		"bateria": -1, "fps": 0, "conectado_em": agora, "ultimo_heartbeat": agora,
		"telemetria": {}, "telemetria_em": 0.0,
	}
	mudou.emit()

func remover(peer: int):
	lista.erase(peer)
	mudou.emit()

func obter(peer: int) -> Dictionary:
	return lista.get(peer, {})

## Devolve o apelido do aparelho (cria "Óculos N" na primeira vez que ele aparece)
func registrar(peer: int, info: Dictionary) -> String:
	var d := obter(peer)
	if d.is_empty():
		return ""
	var unico := str(info.get("unique_id", ""))
	d.unique_id = unico
	d.modelo = str(info.get("modelo", ""))
	d.aparelho = str(info.get("aparelho", ""))
	d.versao = str(info.get("versao", ""))
	d.bateria = int(info.get("bateria", -1))
	if unico != "" and _apelidos.has(unico):
		d.apelido = _apelidos[unico]
	else:
		d.apelido = _proximo_apelido()
		if unico != "":
			_apelidos[unico] = d.apelido
			_salvar()
	d.ultimo_heartbeat = _agora()
	mudou.emit()
	return d.apelido

func definir_apelido(peer: int, apelido: String):
	var d := obter(peer)
	if d.is_empty() or apelido.strip_edges().is_empty():
		return
	d.apelido = apelido.strip_edges()
	if d.unique_id != "":
		_apelidos[d.unique_id] = d.apelido
		_salvar()
	mudou.emit()

func heartbeat(peer: int, bateria: int, fps: int):
	var d := obter(peer)
	if d.is_empty():
		return
	d.bateria = bateria
	d.fps = fps
	d.ultimo_heartbeat = _agora()
	mudou.emit()

## Chega 10x/s: não emite `mudou` (o painel já refaz os cards a cada 0,5 s)
func definir_telemetria(peer: int, dados: Dictionary):
	var d := obter(peer)
	if d.is_empty():
		return
	d.telemetria = dados
	d.telemetria_em = _agora()

## Telemetria recente do peer, ou vazio
func telemetria(d: Dictionary) -> Dictionary:
	if d.is_empty() or _agora() - float(d.telemetria_em) > LIMITE_TELEMETRIA:
		return {}
	return d.telemetria

func definir_estado(peer: int, estado: String):
	var d := obter(peer)
	if d.is_empty() or estado not in ESTADOS:
		return
	d.estado = estado
	mudou.emit()

func liberar(peer: int, jogador: String):
	var d := obter(peer)
	if d.is_empty():
		return
	d.jogador = jogador
	d.liberado = true
	mudou.emit()

func encerrar(peer: int):
	var d := obter(peer)
	if d.is_empty():
		return
	d.jogador = ""
	d.liberado = false
	d.estado = "idle"
	d.telemetria = {}
	mudou.emit()

func sem_resposta(d: Dictionary) -> bool:
	return _agora() - float(d.ultimo_heartbeat) > LIMITE_HEARTBEAT

func _proximo_apelido() -> String:
	var usados := {}
	for apelido in _apelidos.values():
		usados[apelido] = true
	for d in lista.values():
		usados[d.apelido] = true
	var n := 1
	while usados.has("Óculos %d" % n):
		n += 1
	return "Óculos %d" % n

func _salvar():
	var arquivo := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if arquivo:
		arquivo.store_string(JSON.stringify(_apelidos, "\t"))

func _agora() -> float:
	return Time.get_ticks_msec() / 1000.0
