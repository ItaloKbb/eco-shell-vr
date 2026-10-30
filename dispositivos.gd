extends Node
## Óculos e notebooks conectados ao servidor (autoload; só usado no modo servidor):
## estado, nome do jogador liberado, ping, bateria e último heartbeat de cada peer. O
## apelido ("Óculos 3", ou "Notebook 2" para PC jogando no teclado) fica preso ao
## OS.get_unique_id() do aparelho em user://dispositivos.json, e por isso sobrevive a
## reinicializações e a outros dias de evento. Dois aparelhos conectados nunca dividem o
## mesmo apelido: se o id coincidir (notebooks clonados da mesma imagem), o segundo
## ganha um número livre só nesta sessão.

const ARQUIVO := "user://dispositivos.json"
const ESTADOS := ["idle", "lobby", "correndo", "menu"]
## Sem heartbeat há mais que isso (s): a linha do painel fica em alerta
const LIMITE_HEARTBEAT := 10.0
## Telemetria mais velha que isso (s) não vai para o espectador nem para o painel
const LIMITE_TELEMETRIA := 2.0
## tipo do aparelho (enviado no registro) -> prefixo do apelido
const PREFIXOS := {"oculos": "Óculos", "notebook": "Notebook"}

signal mudou

## peer -> {peer, ip, unique_id, tipo, modelo, aparelho, versao, apelido, jogador, liberado,
## nome_sugerido (o que o jogador digitou no notebook enquanto espera), estado, bateria, fps, conectado_em, ultimo_heartbeat, telemetria, telemetria_em}
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
		"peer": peer, "ip": ip, "unique_id": "", "tipo": "oculos", "modelo": "", "aparelho": "", "versao": "",
		"apelido": "", "jogador": "", "nome_sugerido": "", "liberado": false, "estado": "idle",
		"bateria": -1, "fps": 0, "conectado_em": agora, "ultimo_heartbeat": agora,
		"telemetria": {}, "telemetria_em": 0.0,
	}
	mudou.emit()

func remover(peer: int):
	lista.erase(peer)
	mudou.emit()

func obter(peer: int) -> Dictionary:
	return lista.get(peer, {})

## Devolve o apelido do aparelho (cria "Óculos N"/"Notebook N" na primeira vez que ele aparece)
func registrar(peer: int, info: Dictionary) -> String:
	var d := obter(peer)
	if d.is_empty():
		return ""
	var unico := str(info.get("unique_id", ""))
	d.unique_id = unico
	d.tipo = str(info.get("tipo", "oculos"))
	if d.tipo not in PREFIXOS:
		d.tipo = "oculos"
	d.modelo = str(info.get("modelo", ""))
	d.aparelho = str(info.get("aparelho", ""))
	d.versao = str(info.get("versao", ""))
	d.bateria = int(info.get("bateria", -1))
	if unico != "" and _apelidos.has(unico) and not _em_uso(_apelidos[unico], peer):
		d.apelido = _apelidos[unico]
	elif unico != "" and _apelidos.has(unico):
		# Outro aparelho conectado com o mesmo id já usa esse apelido
		d.apelido = _proximo_apelido(PREFIXOS[d.tipo])
	else:
		d.apelido = _proximo_apelido(PREFIXOS[d.tipo])
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

## Nome que o jogador digitou na espera (notebook); o operador ainda confirma ao liberar
func sugerir_nome(peer: int, nome: String):
	var d := obter(peer)
	if d.is_empty() or d.liberado:
		return
	d.nome_sugerido = nome.strip_edges()
	mudou.emit()

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
	d.nome_sugerido = ""
	d.liberado = true
	mudou.emit()

func encerrar(peer: int):
	var d := obter(peer)
	if d.is_empty():
		return
	d.jogador = ""
	d.nome_sugerido = ""
	d.liberado = false
	d.estado = "idle"
	d.telemetria = {}
	mudou.emit()

func sem_resposta(d: Dictionary) -> bool:
	return _agora() - float(d.ultimo_heartbeat) > LIMITE_HEARTBEAT

func _em_uso(apelido: String, exceto: int) -> bool:
	for outro in lista:
		if outro != exceto and lista[outro].apelido == apelido:
			return true
	return false

func _proximo_apelido(prefixo: String) -> String:
	var usados := {}
	for apelido in _apelidos.values():
		usados[apelido] = true
	for d in lista.values():
		usados[d.apelido] = true
	var n := 1
	while usados.has("%s %d" % [prefixo, n]):
		n += 1
	return "%s %d" % [prefixo, n]

func _salvar():
	var arquivo := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if arquivo:
		arquivo.store_string(JSON.stringify(_apelidos, "\t"))

func _agora() -> float:
	return Time.get_ticks_msec() / 1000.0
