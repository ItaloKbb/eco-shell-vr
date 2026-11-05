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
## carro 30x/s; o servidor repassa cada pacote aos espectadores na hora.
##
## Corrida em grupo: quem entra num portal pede a corrida ao servidor. Com mais de um
## jogador liberado no lobby, o servidor abre uma sala e puxa todos (os que estão na
## esfera também): vagas do grid com a IA na frente e os jogadores atrás, e quem entrou
## no portal é o anfitrião, o único Quest que roda a IA dos adversários (os outros os
## mostram pela telemetria dele). O grid sempre fecha com VAGAS carros: quem entra num
## portal do mesmo destino antes da largada entra na sala no lugar de um adversário, e
## quem sai antes da largada devolve a vaga à IA. Largada quando todos carregaram e
## apertaram PRONTO, ou TEMPO_PRONTO depois. Sozinho (ou sem servidor) a corrida é a de sempre.

const JOGO := "tron_senai"
const VERSAO := "1.8"
const PORTA := 7000
const PORTA_DESCOBERTA := 7001
const MAX_JOGADORES := 32
const INTERVALO_ANUNCIO := 1.0
const INTERVALO_HEARTBEAT := 5.0
const INTERVALO_RECONEXAO := 2.0
## Quanto o cliente espera o servidor tirar o avatar antes de ir para a corrida (s)
const ESPERA_CONFIRMACAO := 2.0
const MAX_EVENTOS := 2000
## Cliente: id sorteado deste aparelho (ver _id_aparelho) e o último servidor em que
## esteve (preferido quando há mais de um na rede)
const ARQUIVO_APARELHO := "user://aparelho.cfg"
## Servidor: o nome que ele anuncia (editável no painel; padrão: nome do PC)
const ARQUIVO_SERVIDOR := "user://servidor.cfg"
## Cliente: junta anúncios por esse tempo antes de escolher o servidor (s), e esquece um
## servidor que parou de anunciar há mais que isso (s)
const JANELA_DESCOBERTA := 2.0
const ESQUECER_SERVIDOR := 5.0
## Servidor: outro servidor relatado por um cliente vale por esse tempo (s)
const VALIDADE_OUTRO_SERVIDOR := 12.0
## Cliente -> servidor: telemetria do carro (s). O servidor repassa cada pacote na hora,
## e quem recebe interpola entre eles (InterpoladorRede): 30 Hz deixa sempre duas
## amostras dentro do atraso de 0,1 s da interpolação
const INTERVALO_TELEMETRIA := 1.0 / 30.0
## Servidor -> espectadores: lista dos jogadores ativos, para tirar quem saiu (s)
const INTERVALO_QUADRO := 0.5
## Corrida em grupo: tempo máximo para todos carregarem o mapa, janela para apertar
## PRONTO depois disso, quanto o Quest espera a resposta do pedido (senão corre sozinho)
## e de quanto em quanto tempo o servidor manda a contagem de prontos (s)
const TEMPO_CARREGAR := 25.0
const TEMPO_PRONTO := 20.0
const ESPERA_RESPOSTA_CORRIDA := 3.0
const INTERVALO_STATUS_SALA := 0.25
## Vagas do grid: os adversários e o jogador da corrida solo
const VAGAS := MapaCorrida.ADVERSARIOS + 1

enum Modo { DESLIGADO, CLIENTE, SERVIDOR, ESPECTADOR }

## Cliente/espectador: conectou/caiu, foi liberado ou teve a sessão encerrada
signal sessao_mudou
## Cliente na espera: mudou o nome sorteado, o "pronto" ou quantos ainda faltam
signal espera_mudou
## Mudou a lista de servidores na rede (cliente: os que ouve; servidor: os relatados)
signal servidores_mudaram
signal apelido_mudou(apelido: String)
## Servidor: uma linha nova no log de eventos
signal evento(registro: Dictionary)
## Espectador: chegou a lista dos jogadores ativos (a última telemetria de cada um)
signal quadro_recebido(jogadores: Array)
## Espectador: chegou um pacote de telemetria de um jogador (com peer, nome e `t`)
signal telemetria_recebida(item: Dictionary)
## Cliente, corrida em grupo: o servidor mandou correr sozinho; puxou para uma sala
## (info: id, destino, anfitriao, rivais, jogadores [{peer, nome, vaga}]); contagem de
## prontos ({prontos, total, restante: s ou -1 carregando}); largada; virou anfitrião;
## e a telemetria dos outros jogadores da sala
signal corrida_solo(destino: String)
signal sala_entrou(info: Dictionary)
## Cliente, corrida em grupo: alguém entrou ou saiu da sala antes da largada (novas
## vagas dos jogadores e quantos adversários da IA completam o grid)
signal sala_atualizada(info: Dictionary)
signal sala_status(status: Dictionary)
signal sala_largada
signal sala_anfitriao
signal telemetria_sala(item: Dictionary)

var modo := Modo.DESLIGADO
## Cliente
var conectado := false
var liberado := false
var nome_jogador := ""
var apelido := ""
## Cliente na espera (vem do servidor): nome sorteado (só óculos), se já disse que está
## pronto, quantos outros na espera ainda não estão e quantos outros há na espera
var espera_nome := ""
var espera_pronto := false
var espera_faltam := 0
var espera_outros := 0
var estado := "idle"
## Sala da corrida em grupo em que este Quest está (vazio = nenhuma)
var sala := {}
## Servidor
var anuncios_enviados := 0
var pacotes_recebidos := 0
var inicio_servidor := 0.0
var eventos: Array[Dictionary] = []
## peer -> true de cada espectador conectado
var espectadores := {}
## Espectador: o último quadro recebido
var quadro: Array = []
## Servidor: id -> {id, destino, anfitriao, rivais, jogadores, participantes,
## carregados, prontos, criada_em, prontos_desde (-1 = carregando), largou}
var salas := {}
var _proxima_sala := 1
var _tempo_status := 0.0

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
## Servidor: o próprio nome. Cliente: o nome do servidor em que está conectado
var nome_servidor := ""
## Cliente: servidores ouvidos na rede, ip -> {nome, porta, visto_em}
var servidores := {}
## Servidor: outros servidores que os clientes relataram, ip -> {nome, visto_em, por}
var outros_servidores := {}
var _ip_servidor := ""
var _descobrindo_desde := -1.0
var _relatado := ""
## Cliente: servidores que recusaram a conexão há pouco (ip -> quando), pulados se houver outro
var _falhas := {}
var _tempo_relato := 0.0

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
	var config := ConfigFile.new()
	config.load(ARQUIVO_SERVIDOR)
	nome_servidor = str(config.get_value("servidor", "nome", ""))
	if nome_servidor.is_empty():
		nome_servidor = OS.get_environment("COMPUTERNAME") if OS.get_environment("COMPUTERNAME") != "" else "SERVIDOR"
	Ranking.carregar()
	Ranking.ranking_mudou.connect(_ranking_mudou)
	Dispositivos.mudou.connect(_avisar_espera)
	registrar_evento("servidor", "Escutando na porta %d (versão %s) como \"%s\"" % [PORTA, VERSAO, nome_servidor])
	return OK

## Servidor: troca o nome anunciado (e lembra dele)
func definir_nome_servidor(nome: String):
	nome = nome.strip_edges()
	if nome.is_empty() or nome == nome_servidor:
		return
	nome_servidor = nome
	var config := ConfigFile.new()
	config.load(ARQUIVO_SERVIDOR)
	config.set_value("servidor", "nome", nome)
	config.save(ARQUIVO_SERVIDOR)
	registrar_evento("servidor", "Nome do servidor: %s" % nome)

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
	d.erase("espera_enviada")
	# Ao chegar ao lobby, entra num grupo que ainda está no grid (ver mudar_estado)
	d["puxar_sala"] = true
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
	d.erase("espera_enviada")
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

## Na espera para o auto launch: conectado, registrado, respondendo, sem sessão e não
## marcado "Vazio"
static func na_espera(d: Dictionary) -> bool:
	return d.apelido != "" and not Dispositivos.sem_resposta(d) and not d.liberado \
		and d.estado == "idle" and not d.get("sem_jogador", false)

## Servidor: conta a cada aparelho na espera o nome sorteado (óculos), se ele já está
## pronto e quantos dos outros ainda não estão (o óculos mostra "falta apenas você").
## Só manda quando algo mudou para aquele aparelho
func _avisar_espera():
	if modo != Modo.SERVIDOR:
		return
	var espera := []
	for d in Dispositivos.lista.values():
		if d.apelido != "" and not d.liberado:
			Dispositivos.garantir_nome(d)
		if na_espera(d):
			espera.append(d)
	for d in Dispositivos.lista.values():
		if d.apelido == "" or d.liberado:
			continue
		var outros := 0
		var faltam := 0
		for outro in espera:
			if outro.peer != d.peer:
				outros += 1
				if not outro.nome_confirmado:
					faltam += 1
		var nome: String = d.nome_sugerido if d.tipo == "oculos" else ""
		var info := [nome, bool(d.nome_confirmado), faltam, outros]
		if d.get("espera_enviada", []) != info:
			d["espera_enviada"] = info
			situacao_espera.rpc_id(d.peer, nome, bool(d.nome_confirmado), faltam, outros)

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
	var pacote := JSON.stringify({"jogo": JOGO, "porta": PORTA, "versao": VERSAO, "nome": nome_servidor}).to_utf8_buffer()
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
	_sair_da_sala(peer)
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
		lista.append(_item_quadro(peer, d, dados))
	return lista

## Telemetria com quem é (peer, nome dado pelo operador, apelido do óculos, estado)
func _item_quadro(peer: int, d: Dictionary, dados: Dictionary) -> Dictionary:
	var item := dados.duplicate()
	item.peer = peer
	item.nome = d.jogador
	item.apelido = d.apelido
	item.estado = d.estado
	return item

# --- Corrida em grupo (servidor) -------------------------------------------------------

## Sala em que o peer está, ou vazio
func sala_de(peer: int) -> Dictionary:
	for s in salas.values():
		if peer in s.participantes:
			return s
	return {}

## Quem vai junto: o pedinte primeiro (vira o anfitrião) e os liberados no lobby (na
## esfera também) que não estão em outra sala, até encher o grid
func _elegiveis(pedinte: int) -> Array:
	var lista := [pedinte]
	var peers := Dispositivos.lista.keys()
	peers.sort()
	for peer in peers:
		var d := Dispositivos.obter(peer)
		if peer != pedinte and d.liberado and d.estado == "lobby" and sala_de(peer).is_empty():
			lista.append(peer)
	return lista.slice(0, VAGAS)

func _abrir_sala(destino: String, participantes: Array):
	var id := _proxima_sala
	_proxima_sala += 1
	var jogadores := []
	var nomes := PackedStringArray()
	for k in participantes.size():
		var d := Dispositivos.obter(participantes[k])
		# O anfitrião na última vaga, como na corrida solo; os outros logo à frente dele
		jogadores.append({"peer": participantes[k], "nome": d.jogador, "vaga": VAGAS - 1 - k})
		nomes.append(d.jogador)
	var s := {"id": id, "destino": destino, "anfitriao": participantes[0],
		"rivais": VAGAS - participantes.size(), "jogadores": jogadores,
		"participantes": participantes.duplicate(), "carregados": {}, "prontos": {},
		"criada_em": tempo_ligado(), "prontos_desde": -1.0, "largou": false}
	salas[id] = s
	registrar_evento("corrida", "Grupo #%d em %s: %s (+%d da IA)" % [id, destino, ", ".join(nomes), s.rivais])
	for peer in participantes:
		entrar_sala.rpc_id(peer, _info_sala(s))

## Sala ainda no grid (sem largada) para o destino, com vaga sobrando para um jogador.
## Destino vazio: qualquer uma
func _sala_aberta(destino: String) -> Dictionary:
	for s in salas.values():
		if (destino == "" or s.destino == destino) and not s.largou and s.participantes.size() < VAGAS:
			return s
	return {}

## Auto launch: o peer está numa corrida que já largou (ou sozinho, sem grupo para
## entrar). No lobby ou num grupo ainda no grid não conta: quem for liberado agora
## ainda se junta a eles
func em_corrida_largada(peer: int) -> bool:
	var d := Dispositivos.obter(peer)
	if d.is_empty() or d.estado != "correndo":
		return false
	var s := sala_de(peer)
	return s.is_empty() or s.largou

## Jogador chegando a uma sala aberta: fica com a vaga mais de trás que nenhum jogador
## ocupa e um adversário da IA sai do grid para manter VAGAS carros
func _entrar_na_sala(s: Dictionary, peer: int):
	var ocupadas := []
	for jogador in s.jogadores:
		ocupadas.append(int(jogador.vaga))
	var vaga := VAGAS - 1
	while vaga in ocupadas:
		vaga -= 1
	var nome: String = Dispositivos.obter(peer).get("jogador", "Peer %d" % peer)
	s.participantes.append(peer)
	s.jogadores.append({"peer": peer, "nome": nome, "vaga": vaga})
	s.rivais = VAGAS - s.participantes.size()
	registrar_evento("corrida", "%s entrou no grupo #%d (+%d da IA)" % [nome, s.id, s.rivais])
	entrar_sala.rpc_id(peer, _info_sala(s))
	_avisar_sala_mudou(s, peer)

## Manda a sala nova a quem já está nela (menos `exceto`, que acabou de receber)
func _avisar_sala_mudou(s: Dictionary, exceto := 0):
	var info := _info_sala(s)
	for outro in s.participantes:
		if outro != exceto:
			atualizar_sala.rpc_id(outro, info)

## O que cada Quest precisa saber da sala
func _info_sala(s: Dictionary) -> Dictionary:
	return {"id": s.id, "destino": s.destino, "anfitriao": s.anfitriao, "rivais": s.rivais, "jogadores": s.jogadores}

## Saiu da corrida (portal, morte, sessão encerrada, caiu da rede). Sala vazia fecha;
## se era o anfitrião, o próximo assume a IA dos adversários. Antes da largada a vaga
## dele volta para a IA (depois da largada o grid já correu como estava)
func _sair_da_sala(peer: int):
	var s := sala_de(peer)
	if s.is_empty():
		return
	s.participantes.erase(peer)
	s.carregados.erase(peer)
	s.prontos.erase(peer)
	var nome: String = Dispositivos.obter(peer).get("jogador", "Peer %d" % peer)
	if s.participantes.is_empty():
		salas.erase(s.id)
		registrar_evento("corrida", "Grupo #%d encerrado" % s.id)
		return
	registrar_evento("corrida", "%s saiu do grupo #%d" % [nome, s.id])
	if s.anfitriao == peer:
		s.anfitriao = s.participantes[0]
		virou_anfitriao.rpc_id(s.anfitriao, s.id)
		registrar_evento("corrida", "%s assume a IA do grupo #%d" % [Dispositivos.obter(s.anfitriao).get("jogador", "?"), s.id])
	if not s.largou:
		s.jogadores = s.jogadores.filter(func(jogador): return int(jogador.peer) != peer)
		s.rivais = VAGAS - s.participantes.size()
		_avisar_sala_mudou(s)

## Espera todos carregarem (até TEMPO_CARREGAR), abre a janela de PRONTO e larga
## quando todos confirmam ou a janela fecha. Manda a contagem de prontos aos Quests
func _cuidar_salas(delta: float):
	_tempo_status -= delta
	var mandar_status := _tempo_status <= 0.0
	if mandar_status:
		_tempo_status = INTERVALO_STATUS_SALA
	var agora := tempo_ligado()
	for s in salas.values():
		if s.largou:
			continue
		if s.prontos_desde < 0.0 and (s.carregados.size() >= s.participantes.size() or agora - s.criada_em > TEMPO_CARREGAR):
			s.prontos_desde = agora
		var restante: float = -1.0 if s.prontos_desde < 0.0 else maxf(TEMPO_PRONTO - (agora - s.prontos_desde), 0.0)
		if s.prontos_desde >= 0.0 and (s.prontos.size() >= s.participantes.size() or restante <= 0.0):
			_largar_sala(s)
			continue
		if mandar_status:
			var status := {"prontos": s.prontos.size(), "total": s.participantes.size(), "restante": restante}
			for peer in s.participantes:
				status_sala.rpc_id(peer, s.id, status)

func _largar_sala(s: Dictionary):
	s.largou = true
	registrar_evento("corrida", "Grupo #%d: largada (%d de %d prontos)" % [s.id, s.prontos.size(), s.participantes.size()])
	for peer in s.participantes:
		# Quem ainda carrega larga ao avisar que chegou ao grid
		if s.carregados.has(peer):
			largar_sala.rpc_id(peer, s.id)

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

## Fim da vida do piloto (explodiu ou terminou a corrida): a sessão acaba aqui mesmo
## (sem esperar o servidor, a esfera já fica em espera) e o servidor põe o Quest em idle
func terminar_sessao():
	if not conectado or not liberado:
		return
	liberado = false
	nome_jogador = ""
	pedir_encerramento.rpc_id(1)

## Espera (notebook): o nome que o jogador digitou aparece no painel do operador.
## `confirmado`: o jogador apertou Enter (só então o auto launch usa o nome)
func enviar_nome_sugerido(nome: String, confirmado := false):
	if conectado and not liberado and modo == Modo.CLIENTE:
		sugerir_nome.rpc_id(1, nome, confirmado)

## Óculos na espera: o jogador apertou A (está pronto com o nome sorteado)
func confirmar_pronto():
	if not conectado or liberado or modo != Modo.CLIENTE or espera_nome.is_empty() or espera_pronto:
		return
	espera_pronto = true
	sugerir_nome.rpc_id(1, espera_nome, true)
	espera_mudou.emit()

## Fim da corrida: só conta para o ranking com o Quest liberado pelo operador
func registrar_tempo(tempo: float, pista: String):
	if conectado and liberado:
		enviar_tempo.rpc_id(1, nome_jogador, tempo, pista)

func _cliente(delta: float):
	if conectado:
		_relatar_servidores(delta)
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
	_ouvir_anuncios()
	if servidores.is_empty():
		_descobrindo_desde = -1.0
		return
	var agora := Time.get_ticks_msec() / 1000.0
	if _descobrindo_desde < 0.0:
		_descobrindo_desde = agora
	# Espera um pouco para saber se há mais de um servidor antes de escolher
	if agora - _descobrindo_desde < JANELA_DESCOBERTA:
		return
	var ip := _escolher_servidor()
	_descobrindo_desde = -1.0
	_conectar(ip, int(servidores[ip].porta))

## Anúncios recebidos: atualiza a lista de servidores (e esquece os que sumiram)
func _ouvir_anuncios():
	var agora := Time.get_ticks_msec() / 1000.0
	var mudou := false
	while _udp.is_bound() and _udp.get_available_packet_count() > 0:
		var pacote := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var dados: Variant = JSON.parse_string(pacote.get_string_from_utf8())
		# A versão no anúncio deixa de fora um Quest com build antiga
		if dados is Dictionary and dados.get("jogo") == JOGO and dados.get("versao") == VERSAO:
			if not servidores.has(ip):
				mudou = true
			servidores[ip] = {"nome": str(dados.get("nome", ip)), "porta": int(dados.get("porta", PORTA)), "visto_em": agora}
	for ip in servidores.keys():
		if agora - float(servidores[ip].visto_em) > ESQUECER_SERVIDOR and ip != _ip_servidor:
			servidores.erase(ip)
			mudou = true
	if mudou:
		if servidores.size() > 1:
			print("Servidores na rede: %s" % ", ".join(servidores.keys().map(func(i): return "%s (%s)" % [servidores[i].nome, i])))
		servidores_mudaram.emit()

## Mais de um servidor: o último em que este aparelho esteve; senão o de menor IP (todos
## os aparelhos sem preferência vão para o mesmo)
func _escolher_servidor() -> String:
	var config := ConfigFile.new()
	config.load(ARQUIVO_APARELHO)
	var preferido := str(config.get_value("aparelho", "servidor", ""))
	var ips := servidores.keys()
	ips.sort_custom(func(a, b): return _ip_numero(a) < _ip_numero(b))
	var agora := Time.get_ticks_msec() / 1000.0
	var acessiveis := ips.filter(func(ip): return agora - float(_falhas.get(ip, -100.0)) > 15.0)
	if not acessiveis.is_empty():
		ips = acessiveis
	for ip in ips:
		if preferido != "" and servidores[ip].nome == preferido:
			return ip
	return ips[0]

static func _ip_numero(ip: String) -> int:
	var n := 0
	for parte in ip.split("."):
		n = n * 256 + int(parte)
	return n

## Conectado: conta ao servidor quais outros servidores este aparelho ouve (o painel
## do operador avisa que há mais de um servidor na rede)
func _relatar_servidores(delta: float):
	_ouvir_anuncios()
	_tempo_relato -= delta
	if _tempo_relato > 0.0:
		return
	_tempo_relato = 2.0
	var outros := []
	for ip in servidores:
		if ip != _ip_servidor:
			outros.append([ip, servidores[ip].nome])
	var assinatura := str(outros)
	if assinatura != _relatado or not outros.is_empty():
		_relatado = assinatura
		relatar_servidores.rpc_id(1, outros)

func outros_servidores_vistos() -> int:
	return servidores.keys().filter(func(ip): return ip != _ip_servidor).size()

# --- Corrida em grupo (cliente) --------------------------------------------------------

func eh_anfitriao() -> bool:
	return not sala.is_empty() and int(sala.anfitriao) == multiplayer.get_unique_id()

## Entrou num portal de corrida: o servidor responde com corrida_solo ou sala_entrou
## (mundos.gd espera ESPERA_RESPOSTA_CORRIDA e corre sozinho se nada chegar)
func pedir_corrida(destino: String):
	if conectado:
		pedido_corrida.rpc_id(1, destino)

## "carregado" (chegou ao grid) ou "pronto" (apertou o botão)
func avisar_sala(novo: String):
	if conectado and not sala.is_empty():
		estado_sala.rpc_id(1, int(sala.id), novo)

func sair_sala():
	if sala.is_empty():
		return
	if conectado:
		estado_sala.rpc_id(1, int(sala.id), "saiu")
	sala = {}

## Só com o Quest liberado (quem está em espera não aparece no telão)
func _enviar_telemetria(delta: float):
	_tempo_telemetria -= delta
	if _tempo_telemetria > 0.0 or not liberado:
		return
	_tempo_telemetria = INTERVALO_TELEMETRIA
	var carro := get_tree().get_first_node_in_group("carro")
	if carro and carro.has_method("telemetria"):
		var dados: Dictionary = carro.telemetria()
		# Relógio deste Quest na hora da medida: quem recebe interpola no tempo certo
		dados.t = InterpoladorRede.agora()
		telemetria.rpc_id(1, dados)

func _conectar(ip: String, porta: int):
	_ip_servidor = ip
	_enet = ENetMultiplayerPeer.new()
	if _enet.create_client(ip, porta) != OK:
		return
	multiplayer.multiplayer_peer = _enet
	_conectando = true
	print("Conectando ao servidor %s:%d" % [ip, porta])

func _conectou():
	_conectando = false
	conectado = true
	# Lembra o servidor (preferido da próxima vez, se houver mais de um na rede)
	nome_servidor = str(servidores.get(_ip_servidor, {}).get("nome", _ip_servidor))
	var lembrar := ConfigFile.new()
	lembrar.load(ARQUIVO_APARELHO)
	lembrar.set_value("aparelho", "servidor", nome_servidor)
	lembrar.save(ARQUIVO_APARELHO)
	_relatado = ""
	_tempo_relato = 0.0
	liberado = false
	nome_jogador = ""
	_limpar_espera()
	estado = "idle"
	_tempo_heartbeat = INTERVALO_HEARTBEAT
	if modo == Modo.ESPECTADOR:
		registrar_espectador.rpc_id(1, VERSAO)
		print("Conectado ao servidor do evento como espectador")
		sessao_mudou.emit()
		return
	var xr := XRServer.find_interface("OpenXR")
	# Sem XR é um PC jogando no teclado (modo jogo): vira "Notebook N" no painel
	var notebook := xr == null or not xr.is_initialized()
	registrar_dispositivo.rpc_id(1, {
		"unique_id": _id_aparelho(notebook),
		"tipo": "notebook" if notebook else "oculos",
		"modelo": OS.get_model_name(),
		"aparelho": "%s (%s)" % [OS.get_model_name(), OS.get_name()],
		"versao": VERSAO,
		"bateria": _bateria(),
	})
	print("Conectado ao servidor do evento")
	sessao_mudou.emit()

## No Windows o OS.get_unique_id() se repete em notebooks clonados da mesma imagem:
## no notebook o id leva junto um sorteio guardado em user:// na primeira execução
func _id_aparelho(notebook: bool) -> String:
	var id := OS.get_unique_id()
	if not notebook:
		return id
	var config := ConfigFile.new()
	config.load(ARQUIVO_APARELHO)
	var sorteio := str(config.get_value("aparelho", "id", ""))
	if sorteio.is_empty():
		sorteio = Crypto.new().generate_random_bytes(8).hex_encode()
		config.set_value("aparelho", "id", sorteio)
		config.save(ARQUIVO_APARELHO)
	return "%s/%s" % [id, sorteio]

func _falhou():
	_conectando = false
	_falhas[_ip_servidor] = Time.get_ticks_msec() / 1000.0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _caiu():
	_conectando = false
	conectado = false
	liberado = false
	nome_jogador = ""
	_limpar_espera()
	sala = {}
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
			_cuidar_salas(delta)
		Modo.CLIENTE, Modo.ESPECTADOR:
			_cliente(delta)

# --- Mensagens (mesmo script nos dois lados) ------------------------------------------

## Cliente -> servidor: outros servidores que ele ouve na rede ([ip, nome])
@rpc("any_peer", "call_remote", "reliable")
func relatar_servidores(lista: Array):
	if modo != Modo.SERVIDOR:
		return
	var peer := multiplayer.get_remote_sender_id()
	var quem: String = Dispositivos.obter(peer).get("apelido", "telão" if espectadores.has(peer) else "#%d" % peer)
	var agora := Time.get_ticks_msec() / 1000.0
	for par in lista:
		var ip := str(par[0])
		if not outros_servidores.has(ip):
			registrar_evento("erro", "Outro servidor na rede: %s (%s), visto por %s" % [str(par[1]), ip, quem])
		outros_servidores[ip] = {"nome": str(par[1]), "visto_em": agora, "por": quem}
	servidores_mudaram.emit()

## Servidor: outros servidores relatados há pouco (some o que não é mais visto)
func outros_servidores_ativos() -> Array:
	var agora := Time.get_ticks_msec() / 1000.0
	for ip in outros_servidores.keys():
		if agora - float(outros_servidores[ip].visto_em) > VALIDADE_OUTRO_SERVIDOR:
			outros_servidores.erase(ip)
	var lista := []
	for ip in outros_servidores:
		lista.append({"ip": ip, "nome": outros_servidores[ip].nome, "por": outros_servidores[ip].por})
	return lista

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

@rpc("any_peer", "call_remote", "reliable")
func sugerir_nome(nome: String, confirmado: bool):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	Dispositivos.sugerir_nome(multiplayer.get_remote_sender_id(), nome.left(32), confirmado)

## O Quest acabou a vida do piloto (explodiu ou terminou a corrida): encerra como o
## operador faria, voltando para idle
@rpc("any_peer", "call_remote", "reliable")
func pedir_encerramento():
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	encerrar(multiplayer.get_remote_sender_id())

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
	var d := Dispositivos.obter(peer)
	if not d.get("liberado", false):
		return
	Dispositivos.definir_telemetria(peer, dados)
	# Repassa na hora: esperar um relógio próprio do servidor juntaria ou pularia
	# pacotes, e é isso que aparece como tranco no telão
	if not espectadores.is_empty():
		var item := _item_quadro(peer, d, dados)
		for espectador in espectadores:
			telemetria_espectador.rpc_id(espectador, item)
	# Corrida em grupo: para os outros da sala (os adversários só valem os do anfitrião)
	var s := sala_de(peer)
	if s.size() > 0 and s.participantes.size() > 1:
		var item := dados.duplicate()
		item.peer = peer
		item.nome = d.jogador
		if peer != s.anfitriao:
			item.erase("rivais")
		for outro in s.participantes:
			if outro != peer:
				repassar_sala.rpc_id(outro, item)

@rpc("authority", "call_remote", "unreliable_ordered")
func quadro_espectador(lista: Array):
	quadro = lista
	quadro_recebido.emit(lista)

@rpc("authority", "call_remote", "unreliable_ordered")
func telemetria_espectador(item: Dictionary):
	telemetria_recebida.emit(item)

## Corrida em grupo: um Quest entrou num portal
@rpc("any_peer", "call_remote", "reliable")
func pedido_corrida(destino: String):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	var atual := sala_de(peer)
	if not atual.is_empty():
		entrar_sala.rpc_id(peer, _info_sala(atual))
		return
	var liberado: bool = Dispositivos.obter(peer).get("liberado", false)
	# Grupo deste destino ainda no grid: entra nele no lugar de um adversário da IA
	var aberta := _sala_aberta(destino) if liberado else {}
	if not aberta.is_empty():
		_entrar_na_sala(aberta, peer)
		return
	var participantes := _elegiveis(peer) if liberado else [peer]
	if participantes.size() <= 1:
		resposta_solo.rpc_id(peer, destino)
		return
	_abrir_sala(destino, participantes)

## Corrida em grupo: "carregado", "pronto" ou "saiu"
@rpc("any_peer", "call_remote", "reliable")
func estado_sala(id: int, novo: String):
	if modo != Modo.SERVIDOR:
		return
	pacotes_recebidos += 1
	var peer := multiplayer.get_remote_sender_id()
	var s: Dictionary = salas.get(id, {})
	if s.is_empty() or peer not in s.participantes:
		return
	match novo:
		"carregado":
			s.carregados[peer] = true
			if s.largou:
				largar_sala.rpc_id(peer, id)
		"pronto":
			s.carregados[peer] = true
			s.prontos[peer] = true
		"saiu":
			_sair_da_sala(peer)

@rpc("authority", "call_remote", "reliable")
func resposta_solo(destino: String):
	corrida_solo.emit(destino)

@rpc("authority", "call_remote", "reliable")
func entrar_sala(info: Dictionary):
	sala = info
	sala_entrou.emit(info)

@rpc("authority", "call_remote", "reliable")
func atualizar_sala(info: Dictionary):
	if not sala.is_empty() and int(sala.id) == int(info.id):
		sala = info
		sala_atualizada.emit(info)

@rpc("authority", "call_remote", "unreliable_ordered")
func status_sala(id: int, status: Dictionary):
	if not sala.is_empty() and int(sala.id) == id:
		sala_status.emit(status)

@rpc("authority", "call_remote", "reliable")
func largar_sala(id: int):
	if not sala.is_empty() and int(sala.id) == id:
		sala_largada.emit()

@rpc("authority", "call_remote", "reliable")
func virou_anfitriao(id: int):
	if not sala.is_empty() and int(sala.id) == id:
		sala.anfitriao = multiplayer.get_unique_id()
		sala_anfitriao.emit()

@rpc("authority", "call_remote", "unreliable_ordered")
func repassar_sala(item: Dictionary):
	telemetria_sala.emit(item)

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
	# Saiu da corrida (voltou ao lobby, morreu, sessão encerrada): sai da sala junto
	if novo != "correndo":
		_sair_da_sala(peer)
	Dispositivos.definir_estado(peer, novo)
	# Acabou de ser liberado e chegou ao lobby (ainda na esfera): se um grupo está no
	# grid esperando a largada, entra nele no lugar de um adversário da IA
	var puxar: bool = d.get("puxar_sala", false)
	if novo != "idle":
		d.erase("puxar_sala")
	if puxar and novo == "lobby" and sala_de(peer).is_empty():
		var aberta := _sala_aberta("")
		if not aberta.is_empty():
			_entrar_na_sala(aberta, peer)
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
	_limpar_espera()
	sessao_mudou.emit()

## Servidor -> aparelho na espera (ver _avisar_espera)
@rpc("authority", "call_remote", "reliable")
func situacao_espera(nome: String, pronto: bool, faltam: int, outros: int):
	espera_nome = nome
	espera_pronto = pronto
	espera_faltam = faltam
	espera_outros = outros
	espera_mudou.emit()

func _limpar_espera():
	espera_nome = ""
	espera_pronto = false
	espera_faltam = 0
	espera_outros = 0

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
