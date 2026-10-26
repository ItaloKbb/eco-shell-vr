extends Node
## Rede do evento (autoload). O mesmo executável é servidor (PC sem headset, painel 2D)
## ou cliente (Quest/PC com headset); o Inicializador escolhe e chama iniciar_servidor()
## ou iniciar_cliente(). Sem isso (testes, cena aberta direto) fica desligada e o jogo
## roda sozinho, como antes.
##
## Servidor: anuncia por broadcast UDP a cada 1 s, aceita os Quests por ENet, guarda o
## registro de cada um (Dispositivos), recebe os tempos (Ranking) e cria/remove os
## avatares do lobby compartilhado. Cliente: escuta o anúncio, conecta sozinho
## (ou em --ip=<endereço>), registra o aparelho e manda heartbeat a cada 5 s.
##
## Ciclo do jogador: conectou -> idle (esperando o operador) -> liberar_jogador(nome)
## -> lobby/correndo -> encerrar_sessao() -> idle. O servidor só aceita tempo de quem
## está liberado, e o nome no ranking é sempre o que ELE atribuiu.
##
## LobbyRede/Jogadores existe igual nos dois lados (o Spawner exige a mesma árvore);
## os avatares só ganham malha nos clientes (AvatarRede).
##
## Espectador (PC do telão): descobre e conecta como um cliente, mas se registra como
## espectador (não vira linha de óculos). Cada Quest liberado manda a telemetria do
## carro ~10x/s; o servidor junta tudo num quadro e repassa aos espectadores.

const JOGO := "tron_senai"
const VERSAO := "1.1"
const PORTA := 7000
const PORTA_DESCOBERTA := 7001
const MAX_JOGADORES := 32
const INTERVALO_ANUNCIO := 1.0
const INTERVALO_HEARTBEAT := 5.0
const INTERVALO_RECONEXAO := 2.0
## Quanto o cliente espera o servidor tirar o avatar antes de ir para a corrida (s)
const ESPERA_CONFIRMACAO := 2.0
const MAX_EVENTOS := 2000
## Cliente -> servidor (telemetria do carro) e servidor -> espectadores (quadro), em s
const INTERVALO_TELEMETRIA := 0.1
const INTERVALO_QUADRO := 0.1

enum Modo { DESLIGADO, CLIENTE, SERVIDOR, ESPECTADOR }

## Cliente/espectador: conectou/caiu, foi liberado ou teve a sessão encerrada
signal sessao_mudou
signal apelido_mudou(apelido: String)
## Servidor: uma linha nova no log de eventos
signal evento(registro: Dictionary)
## Espectador: chegou um quadro com os jogadores ativos (lista de telemetrias)
signal quadro_recebido(jogadores: Array)

var modo := Modo.DESLIGADO
## Cliente
var conectado := false
var liberado := false
var nome_jogador := ""
var apelido := ""
var estado := "idle"
## Servidor
var anuncios_enviados := 0
var pacotes_recebidos := 0
var inicio_servidor := 0.0
var eventos: Array[Dictionary] = []
## peer -> true de cada espectador conectado
var espectadores := {}
## Espectador: o último quadro recebido
var quadro: Array = []

var _udp := PacketPeerUDP.new()
var _enet: ENetMultiplayerPeer
var _jogadores: Node
var _spawner: MultiplayerSpawner
var _destinos_anuncio: PackedStringArray = []
var _tempo_anuncio := 0.0
var _tempo_heartbeat := 0.0
var _tempo_reconexao := 0.0
var _tempo_telemetria := 0.0
var _tempo_quadro := 0.0
var _conectando := false
var _confirmado := ""
var _ip_manual := ""

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var lobby := Node.new()
	lobby.name = "LobbyRede"
	add_child(lobby)
	_jogadores = Node.new()
	_jogadores.name = "Jogadores"
	lobby.add_child(_jogadores)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("../Jogadores")
	_spawner.spawn_function = _criar_avatar
	lobby.add_child(_spawner)
	multiplayer.peer_connected.connect(_peer_conectou)
	multiplayer.peer_disconnected.connect(_peer_saiu)
	multiplayer.connected_to_server.connect(_conectou)
	multiplayer.connection_failed.connect(_falhou)
	multiplayer.server_disconnected.connect(_caiu)
	for arg in argumentos():
		if arg.begins_with("--ip="):
			_ip_manual = arg.trim_prefix("--ip=")

static func argumentos() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()

## IPv4 da rede local (192.168.x, 10.x, 172.16-31.x): o cabeçalho do painel mostra
## para conexão manual de emergência
static func ips_locais() -> PackedStringArray:
	var lista: PackedStringArray = []
	for ip in IP.get_local_addresses():
		var partes := ip.split(".")
		if partes.size() != 4:
			continue
		var privado := ip.begins_with("192.168.") or ip.begins_with("10.") \
			or (partes[0] == "172" and int(partes[1]) >= 16 and int(partes[1]) <= 31)
		if privado:
			lista.append(ip)
	return lista

# --- Servidor -----------------------------------------------------------------------

func iniciar_servidor() -> Error:
	_enet = ENetMultiplayerPeer.new()
	var erro := _enet.create_server(PORTA, MAX_JOGADORES)
	if erro != OK:
		registrar_evento("erro", "Não abriu a porta %d: %s" % [PORTA, error_string(erro)])
		return erro
	multiplayer.multiplayer_peer = _enet
	modo = Modo.SERVIDOR
	inicio_servidor = Time.get_ticks_msec() / 1000.0
	_udp.set_broadcast_enabled(true)
	# Broadcast geral e o da sub-rede de cada placa (o geral às vezes só sai por uma)
	_destinos_anuncio = ["255.255.255.255"]
	for ip in ips_locais():
		var partes := ip.split(".")
		_destinos_anuncio.append("%s.%s.%s.255" % [partes[0], partes[1], partes[2]])
	Ranking.carregar()
	Ranking.ranking_mudou.connect(_ranking_mudou)
	registrar_evento("servidor", "Escutando na porta %d (versão %s)" % [PORTA, VERSAO])
	return OK

func tempo_ligado() -> float:
	return Time.get_ticks_msec() / 1000.0 - inicio_servidor

func ping(peer: int) -> int:
	if _enet == null:
		return -1
	var p := _enet.get_peer(peer)
	if p == null:
		return -1
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

## Operador: associa o nome ao óculos e solta o Quest da espera (também renomeia)
func liberar(peer: int, nome: String):
	nome = nome.strip_edges()
	var d := Dispositivos.obter(peer)
	if d.is_empty() or nome.is_empty():
		return
	Dispositivos.liberar(peer, nome)
	liberar_jogador.rpc_id(peer, nome)
	_atualizar_avatar(peer, true)
	registrar_evento("sessao", "%s liberado para %s" % [d.apelido, nome])

## Operador: devolve o Quest para a espera e limpa o nome
func encerrar(peer: int):
	var d := Dispositivos.obter(peer)
	if d.is_empty() or (not d.liberado and d.estado == "idle"):
		return
	var jogador: String = d.jogador
	var estado_anterior: String = d.estado
	Dispositivos.encerrar(peer)
	_atualizar_avatar(peer)
	encerrar_sessao.rpc_id(peer)
	if jogador.is_empty():
		registrar_evento("sessao", "%s: %s -> idle" % [d.apelido, estado_anterior])
	else:
		registrar_evento("sessao", "%s: sessão de %s encerrada (%s -> idle)" % [d.apelido, jogador, estado_anterior])

func renomear_oculos(peer: int, novo: String):
	novo = novo.strip_edges()
	if novo.is_empty() or Dispositivos.obter(peer).is_empty():
		return
	Dispositivos.definir_apelido(peer, novo)
	definir_apelido.rpc_id(peer, novo)
	registrar_evento("dispositivo", "Peer %d agora é %s" % [peer, novo])

func desconectar(peer: int):
	if _enet == null:
		return
	registrar_evento("conexao", "%s desconectado pelo operador" % Dispositivos.obter(peer).get("apelido", str(peer)))
	_enet.disconnect_peer(peer)

func registrar_evento(tipo: String, texto: String):
	var registro := {"data": Time.get_date_string_from_system(), "hora": Time.get_time_string_from_system(),
		"tipo": tipo, "texto": texto}
	eventos.append(registro)
	if eventos.size() > MAX_EVENTOS:
		eventos.pop_front()
	_gravar_log(registro)
	print("[%s] %s: %s" % [registro.hora, tipo, texto])
	evento.emit(registro)

func _gravar_log(registro: Dictionary):
	if modo != Modo.SERVIDOR:
		return
	DirAccess.make_dir_recursive_absolute("user://logs")
	var caminho := "user://logs/eventos_%s.csv" % registro.data
	var arquivo: FileAccess
	if FileAccess.file_exists(caminho):
		arquivo = FileAccess.open(caminho, FileAccess.READ_WRITE)
		if arquivo:
			arquivo.seek_end()
	else:
		arquivo = FileAccess.open(caminho, FileAccess.WRITE)
		if arquivo:
			arquivo.store_csv_line(PackedStringArray(["data", "hora", "tipo", "texto"]))
	if arquivo:
		arquivo.store_csv_line(PackedStringArray([registro.data, registro.hora, registro.tipo, registro.texto]))

func _anunciar(delta: float):
	_tempo_anuncio -= delta
	if _tempo_anuncio > 0.0:
		return
	_tempo_anuncio = INTERVALO_ANUNCIO
	var pacote := JSON.stringify({"jogo": JOGO, "porta": PORTA, "versao": VERSAO}).to_utf8_buffer()
	for destino in _destinos_anuncio:
		_udp.set_dest_address(destino, PORTA_DESCOBERTA)
		_udp.put_packet(pacote)
	anuncios_enviados += 1

func _peer_conectou(peer: int):
	if modo != Modo.SERVIDOR:
		return
	var ip := ""
	var p := _enet.get_peer(peer)
	if p:
		ip = p.get_remote_address()
	Dispositivos.adicionar(peer, ip)
	registrar_evento("conexao", "Peer %d conectou de %s" % [peer, ip])

func _peer_saiu(peer: int):
	if modo != Modo.SERVIDOR:
		return
	if espectadores.has(peer):
		espectadores.erase(peer)
		registrar_evento("espectador", "Espectador #%d saiu" % peer)
		return
	var d := Dispositivos.obter(peer)
	_remover_avatar(peer)
	Dispositivos.remover(peer)
	registrar_evento("conexao", "%s saiu" % d.get("apelido", "Peer %d" % peer))

## Avatar só existe para quem está liberado e no lobby; recriar = trocou o nome
func _atualizar_avatar(peer: int, recriar := false):
	var d := Dispositivos.obter(peer)
	var deve: bool = not d.is_empty() and d.liberado and d.estado == "lobby"
	var atual := _jogadores.get_node_or_null(str(peer))
	if atual and (recriar or not deve):
		_remover_avatar(peer)
		atual = null
	if deve and atual == null:
		_spawner.spawn([peer, d.jogador])

func _remover_avatar(peer: int):
	var atual := _jogadores.get_node_or_null(str(peer))
	if atual:
		# Sai da árvore já: o Spawner despawna nos clientes e o nome fica livre
		_jogadores.remove_child(atual)
		atual.queue_free()

func _criar_avatar(dados: Variant) -> Node:
	var peer: int = dados[0]
	var com_visual := modo == Modo.CLIENTE and peer != multiplayer.get_unique_id()
	return AvatarRede.new(peer, str(dados[1]), com_visual)

func _ranking_mudou(top: Array):
	if modo == Modo.SERVIDOR:
		atualizar_ranking.rpc(top)

## Jogadores liberados com telemetria recente, com nome e estado do servidor
func montar_quadro() -> Array:
	var lista := []
	var peers := Dispositivos.lista.keys()
	peers.sort()
	for peer in peers:
		var d := Dispositivos.obter(peer)
		var dados := Dispositivos.telemetria(d)
		if not d.liberado or dados.is_empty():
			continue
		var item := dados.duplicate()
		item.peer = peer
		item.nome = d.jogador
		item.apelido = d.apelido
		item.estado = d.estado
		lista.append(item)
	return lista

func _enviar_quadros(delta: float):
	_tempo_quadro -= delta
	if _tempo_quadro > 0.0 or espectadores.is_empty():
		return
	_tempo_quadro = INTERVALO_QUADRO
	var lista := montar_quadro()
	for peer in espectadores:
		quadro_espectador.rpc_id(peer, lista)

# --- Cliente ------------------------------------------------------------------------

func iniciar_cliente():
	modo = Modo.CLIENTE
	_escutar_anuncios()

## Telão: acha o servidor como um cliente, mas só assiste
func iniciar_espectador():
	modo = Modo.ESPECTADOR
	_escutar_anuncios()

func _escutar_anuncios():
	var erro := _udp.bind(PORTA_DESCOBERTA)
	if erro != OK:
		push_warning("Descoberta UDP indisponível na porta %d: %s" % [PORTA_DESCOBERTA, error_string(erro)])

## Avisa o servidor da troca de cena. Indo para a corrida, espera o servidor tirar o
## avatar do lobby (ou o tempo esgotar) antes de seguir.
func informar_estado(novo: String):
	estado = novo
	if not conectado:
		return
	_confirmado = ""
	mudar_estado.rpc_id(1, novo)
	if novo != "correndo":
		return
	var limite := Time.get_ticks_msec() + int(ESPERA_CONFIRMACAO * 1000.0)
	while conectado and _confirmado != novo and Time.get_ticks_msec() < limite:
		await get_tree().process_frame

## Fim da corrida: só conta para o ranking com o Quest liberado pelo operador
func registrar_tempo(tempo: float, pista: String):
	if conectado and liberado:
		enviar_tempo.rpc_id(1, nome_jogador, tempo, pista)

func _cliente(delta: float):
	if conectado:
		if modo == Modo.CLIENTE:
			_tempo_heartbeat -= delta
			if _tempo_heartbeat <= 0.0:
				_tempo_heartbeat = INTERVALO_HEARTBEAT
				heartbeat.rpc_id(1, _bateria(), int(Engine.get_frames_per_second()))
			_enviar_telemetria(delta)
		return
	if _conectando:
		return
	if _ip_manual != "":
		_tempo_reconexao -= delta
		if _tempo_reconexao <= 0.0:
			_tempo_reconexao = INTERVALO_RECONEXAO
			_conectar(_ip_manual, PORTA)
		return
	while _udp.is_bound() and _udp.get_available_packet_count() > 0:
		var pacote := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var dados: Variant = JSON.parse_string(pacote.get_string_from_utf8())
		# A versão no anúncio deixa de fora um Quest com build antiga
		if dados is Dictionary and dados.get("jogo") == JOGO and dados.get("versao") == VERSAO:
			_conectar(ip, int(dados.get("porta", PORTA)))
			return

## Só com o Quest liberado (quem está em espera não aparece no telão)
func _enviar_telemetria(delta: float):
	_tempo_telemetria -= delta
	if _tempo_telemetria > 0.0 or not liberado:
		return
	_tempo_telemetria = INTERVALO_TELEMETRIA
	var carro := get_tree().get_first_node_in_group("carro")
	if carro and carro.has_method("telemetria"):
		telemetria.rpc_id(1, carro.telemetria())

func _conectar(ip: String, porta: int):
	_enet = ENetMultiplayerPeer.new()
	if _enet.create_client(ip, porta) != OK:
		return
	multiplayer.multiplayer_peer = _enet
	_conectando = true
	print("Conectando ao servidor %s:%d" % [ip, porta])

func _conectou():
	_conectando = false
	conectado = true
	liberado = false
	nome_jogador = ""
	estado = "idle"
	_tempo_heartbeat = INTERVALO_HEARTBEAT
	if modo == Modo.ESPECTADOR:
		registrar_espectador.rpc_id(1, VERSAO)
		print("Conectado ao servidor do evento como espectador")
		sessao_mudou.emit()
		return
	registrar_dispositivo.rpc_id(1, {
		"unique_id": OS.get_unique_id(),
		"modelo": OS.get_model_name(),
		"aparelho": "%s (%s)" % [OS.get_model_name(), OS.get_name()],
		"versao": VERSAO,
		"bateria": _bateria(),
	})
	print("Conectado ao servidor do evento")
	sessao_mudou.emit()

func _falhou():
	_conectando = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _caiu():
	_conectando = false
	conectado = false
	liberado = false
	nome_jogador = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for avatar in _jogadores.get_children():
		avatar.queue_free()
	print("Servidor do evento caiu: voltando a procurar")
	sessao_mudou.emit()
	if modo == Modo.ESPECTADOR:
		quadro = []
		quadro_recebido.emit(quadro)

## Godot 4 não expõe a bateria em todas as plataformas: -1 quando não dá para ler
func _bateria() -> int:
	if OS.has_method("get_power_percent_left"):
		return int(OS.call("get_power_percent_left"))
	return -1

func _process(delta: float):
	match modo:
		Modo.SERVIDOR:
			_anunciar(delta)
			_enviar_quadros(delta)
		Modo.CLIENTE, Modo.ESPECTADOR:
			_cliente(delta)

# --- Mensagens (mesmo script nos dois lados) ------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func registrar_dispositivo(info: Dictionary):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	if str(info.get("versao", "")) != VERSAO:
		registrar_evento("erro", "Peer %d recusado: versão %s" % [peer, info.get("versao", "?")])
		_enet.disconnect_peer(peer)
		return
	var novo := Dispositivos.registrar(peer, info)
	definir_apelido.rpc_id(peer, novo)
	atualizar_ranking.rpc_id(peer, Ranking.top)
	registrar_evento("dispositivo", "%s registrado: %s" % [novo, info.get("aparelho", "?")])

## O peer é um telão: sai da lista de óculos e passa a receber os quadros
@rpc("any_peer", "call_remote", "reliable")
func registrar_espectador(versao: String):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	if versao != VERSAO:
		registrar_evento("erro", "Espectador %d recusado: versão %s" % [peer, versao])
		_enet.disconnect_peer(peer)
		return
	Dispositivos.remover(peer)
	espectadores[peer] = true
	atualizar_ranking.rpc_id(peer, Ranking.top)
	var p := _enet.get_peer(peer)
	registrar_evento("espectador", "Espectador #%d conectou de %s" % [peer, p.get_remote_address() if p else "?"])

@rpc("any_peer", "call_remote", "unreliable_ordered")
func telemetria(dados: Dictionary):
	if modo != Modo.SERVIDOR:
		return
	var peer := multiplayer.get_remote_sender_id()
	if Dispositivos.obter(peer).get("liberado", false):
		Dispositivos.definir_telemetria(peer, dados)

@rpc("authority", "call_remote", "unreliable_ordered")
func quadro_espectador(lista: Array):
	quadro = lista
	quadro_recebido.emit(lista)

@rpc("any_peer", "call_remote", "reliable")
func mudar_estado(novo: String):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	var d := Dispositivos.obter(peer)
	if d.is_empty() or novo not in Dispositivos.ESTADOS:
		return
	# Sem liberação o Quest só pode ficar em espera
	if not d.liberado:
		novo = "idle"
	if d.estado != novo:
		registrar_evento("estado", "%s: %s -> %s" % [d.apelido, d.estado, novo])
	Dispositivos.definir_estado(peer, novo)
	_atualizar_avatar(peer)
	# Um frame para o despawn sair antes da confirmação
	await get_tree().process_frame
	if not Dispositivos.obter(peer).is_empty():
		confirmar_estado.rpc_id(peer, novo)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func heartbeat(bateria: int, fps: int):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	Dispositivos.heartbeat(multiplayer.get_remote_sender_id(), bateria, fps)

## O nome enviado pelo cliente é ignorado: vale o que o operador atribuiu
@rpc("any_peer", "call_remote", "reliable")
func enviar_tempo(_nome: String, tempo: float, pista: String):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	var d := Dispositivos.obter(peer)
	if d.is_empty() or not d.liberado:
		registrar_evento("erro", "Tempo recusado do peer %d (não liberado)" % peer)
		return
	if not is_finite(tempo) or tempo <= 0.0:
		registrar_evento("erro", "Tempo inválido de %s" % d.apelido)
		return
	Ranking.adicionar(d.jogador, tempo, pista, d.apelido)
	registrar_evento("tempo", "%s: %s em %s (%s)" % [d.jogador, Ranking.formatar_tempo(tempo), pista, d.apelido])

@rpc("authority", "call_remote", "reliable")
func atualizar_ranking(lista: Array):
	Ranking.receber_top(lista)

@rpc("authority", "call_remote", "reliable")
func liberar_jogador(nome: String):
	liberado = true
	nome_jogador = nome
	sessao_mudou.emit()

@rpc("authority", "call_remote", "reliable")
func encerrar_sessao():
	liberado = false
	nome_jogador = ""
	sessao_mudou.emit()

@rpc("authority", "call_remote", "reliable")
func definir_apelido(novo: String):
	apelido = novo
	apelido_mudou.emit(novo)

@rpc("authority", "call_remote", "reliable")
func confirmar_estado(novo: String):
	_confirmado = novo
