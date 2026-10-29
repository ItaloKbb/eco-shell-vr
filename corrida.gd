class_name Corrida
extends Node
## Corrida do circuito: o piloto entra preso na última vaga do grid, vê os controles
## do dispositivo em uso, passa pela contagem (3, 2, 1, VAI! com o semáforo do pórtico)
## e corre as voltas da pista (pista.voltas). A volta só vale passando por todos os
## portões da pista na ordem (sem atalho pelo miolo); a primeira passagem pela linha,
## logo depois do grid, só arma a contagem. Pista aberta (ponta a ponta): uma "volta"
## só, da largada até o último portão, que é a linha de chegada. Ao fechar a última volta mostra o resultado, e o piloto segue
## livre para sair pelo portal. O texto do visor vai em car.gd painel_corrida.
## Os adversários correm por conta própria (TrafegoCorrida + IARival): ficam parados
## no grid até o VAI!, e a posição compara o progresso deles com o do piloto.
## Em grupo (Rede.sala): a contagem só sai quando o servidor dá a largada (todos
## apertaram PRONTO ou a janela fechou), os outros jogadores aparecem como fantasmas
## (CarroFantasma, sem colisão) e entram na posição; no anfitrião eles também entram
## na visão da IA, e nos outros Quests os adversários seguem o que o anfitrião manda.

enum Fase { PARADA, CONTROLES, CONTAGEM, CORRENDO, CHEGADA }
## Voltas dos circuitos fechados (PistaCorrida.voltas)
const VOLTAS := 3
## Quanto tempo os controles ficam na tela antes de a contagem começar sozinha (s)
const TEMPO_CONTROLES := 8.0
const TEMPO_CONTAGEM := 3.0
## Quanto o resultado fica na frente do piloto antes de recolher (s)
const TEMPO_RESULTADO := 7.0
## Jogador da corrida em grupo sem telemetria há mais que isso (s) saiu: o fantasma some
const SUMIR_REMOTO := 2.0

signal fase_mudou(fase: Fase)
signal terminou(total: float, melhor: float)

var pista: PistaCorrida
var carro: RigidBody3D
var rivais: Array[CarroRival] = []
var trafego: TrafegoCorrida

var fase := Fase.PARADA
var volta := 0
var posicao := 0
var _proximo := 0
var _cruzou_largada := false
var _largada := -1.0
var _inicio := -1.0
var _ultima := -1.0
var _melhor := -1.0
var _total := -1.0
var _tempo_fase := 0.0
var _passo_contagem := -1
var _som: AudioStreamPlayer
var _painel: PainelCorrida
var _usando_controle := false
## Tempo de corrida somado na física (não o relógio do computador: engasgos não contam)
var _relogio := 0.0
## Corrida em grupo (a sala de Rede.sala); vazio = sozinho
var grupo := {}
## Outros jogadores do grupo: peer -> {carro: CarroFantasma, nome, progresso, chegou, visto_em}
var remotos := {}
var _pronto_enviado := false
## Contagem de prontos que o servidor manda: {prontos, total, restante (-1 = carregando)}
var _status := {}
## O autoload Rede, buscado na árvore: Corrida é classe global e também é compilada
## em scripts de teste, onde os autoloads ainda não existem na compilação
var _rede: Node

func _ready():
	_rede = get_node("/root/Rede")
	pista.portao.connect(_portao)
	_som = AudioStreamPlayer.new()
	_som.bus = "Carro"
	add_child(_som)
	_rede.sala_largada.connect(_largada_do_grupo)
	_rede.sala_status.connect(func(status: Dictionary): _status = status)
	_rede.telemetria_sala.connect(receber_remoto)
	_rede.sala_anfitriao.connect(func(): if trafego: trafego.assumir_ia())

## Começa do grid: carro preso, controles na tela. Em grupo, avisa o servidor que
## chegou e espera a largada dele
func iniciar(grupo_ := {}):
	grupo = grupo_
	_pronto_enviado = false
	_status = {}
	volta = 0
	posicao = total_carros()
	_proximo = 0
	_cruzou_largada = false
	_largada = -1.0
	_inicio = -1.0
	_ultima = -1.0
	_melhor = -1.0
	_total = -1.0
	_usando_controle = not Input.get_connected_joypads().is_empty()
	trafego.carro = carro
	trafego.preparar()
	carro.segurar()
	pista.semaforo(-1)
	if _painel == null:
		_painel = PainelCorrida.new(_modo_vr())
		_painel.visible = false
		if not carro.mao_direita.button_pressed.is_connected(_botao_vr):
			carro.mao_direita.button_pressed.connect(_botao_vr)
	_ancorar_painel()
	_mudar(Fase.CONTROLES)
	_painel.mostrar_controles(_dispositivo(), TEMPO_CONTROLES)
	_painel.mostrar()
	if not grupo.is_empty():
		_rede.avisar_sala("carregado")

## Saiu do deserto (portal ou morte): limpa tudo
func abortar():
	if not grupo.is_empty():
		_rede.sair_sala()
		grupo = {}
	for peer in remotos.keys():
		_tirar_remoto(peer)
	_mudar(Fase.PARADA)
	if _painel:
		_painel.hide()
	pista.semaforo(-1)
	if trafego:
		trafego.preparar()
	if carro:
		carro.painel_corrida = ""
		if carro.segurado:
			carro.soltar()

func _mudar(nova: Fase):
	fase = nova
	_tempo_fase = 0.0
	fase_mudou.emit(nova)

func _modo_vr() -> bool:
	return carro.get_viewport().use_xr

func _dispositivo() -> PainelCorrida.Dispositivo:
	if _modo_vr():
		return PainelCorrida.Dispositivo.VR
	return PainelCorrida.Dispositivo.CONTROLE if _usando_controle else PainelCorrida.Dispositivo.TECLADO

## Monitor: preso à câmera. VR: preso ao carro na frente do cockpit (não segue a
## cabeça, mas acompanha o carro quando ele anda)
func _ancorar_painel():
	var pai: Node3D = carro if _modo_vr() else carro.camera
	if _painel.get_parent() == null:
		pai.add_child(_painel)
	elif _painel.get_parent() != pai:
		_painel.reparent(pai, false)
	if _modo_vr():
		var olho: Vector3 = carro.to_local(carro.camera_xr.global_position)
		_painel.position = olho + Vector3(0.0, 0.05, -1.5)
		_painel.look_at(carro.camera_xr.global_position, carro.global_basis.y, true)
	else:
		_painel.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, -1.25))

func _input(event: InputEvent):
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_usando_controle = true
	elif event is InputEventKey or event is InputEventMouseButton:
		_usando_controle = false
	if fase != Fase.CONTROLES or not event.is_pressed() or event.is_echo():
		return
	var pronto := false
	if event is InputEventJoypadButton:
		pronto = event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_START
	elif event is InputEventKey:
		pronto = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	if pronto:
		confirmar_pronto()

func _botao_vr(nome: String):
	if fase == Fase.CONTROLES and nome == "ax_button":
		confirmar_pronto()

## Sozinho: começa a contagem. Em grupo: avisa o servidor e espera os outros
func confirmar_pronto():
	if grupo.is_empty():
		_contar()
		return
	if not _pronto_enviado:
		_pronto_enviado = true
		_rede.avisar_sala("pronto")
		_tocar("clique", 1.3, -6.0)

func _largada_do_grupo():
	if fase == Fase.CONTROLES and not grupo.is_empty():
		_contar()

func _physics_process(delta: float):
	if carro == null or carro.em_transicao or fase == Fase.PARADA:
		return
	_relogio += delta
	_tempo_fase += delta
	match fase:
		Fase.CONTROLES:
			# Em grupo quem dá a largada é o servidor
			if grupo.is_empty() and _tempo_fase >= TEMPO_CONTROLES:
				_contar()
		Fase.CONTAGEM:
			var passo := int(_tempo_fase)
			if passo >= 3:
				_largar()
			elif passo != _passo_contagem:
				_passo_contagem = passo
				pista.semaforo(passo + 1)
				_painel.mostrar_contagem(str(3 - passo), passo / 2.0)
				_tocar("bip", 1.0, -4.0)
		Fase.CORRENDO:
			_atualizar_posicao()
			# O "VAI!" fica um instante e recolhe
			if _painel.visible and _tempo_fase > 0.8:
				_painel.fechar()
		Fase.CHEGADA:
			if _painel.visible and _tempo_fase > TEMPO_RESULTADO:
				_painel.fechar()

func _contar():
	_mudar(Fase.CONTAGEM)
	_passo_contagem = -1
	if not _painel.visible:
		_painel.mostrar()

func _largar():
	_mudar(Fase.CORRENDO)
	pista.semaforo(4)
	_painel.mostrar_contagem("VAI!", 0.0)
	_tocar("bip", 2.0, -2.0)
	carro.soltar()
	trafego.largar()
	volta = 1
	_largada = _relogio
	_inicio = _relogio

func _portao(k: int):
	if fase != Fase.CORRENDO or carro == null or carro.em_transicao or k != _proximo:
		return
	_proximo = (k + 1) % pista.total_portoes()
	if pista.aberta:
		_portao_sprint(k)
		return
	if k != 0:
		_tocar("clique", 1.5, -8.0)
		return
	# Saindo do grid: a linha fica logo à frente, a primeira passagem só arma os portões
	if not _cruzou_largada:
		_cruzou_largada = true
		return
	var agora := _relogio
	_ultima = agora - _inicio
	var recorde := _melhor < 0.0 or _ultima < _melhor
	if recorde:
		_melhor = _ultima
	_inicio = agora
	if volta >= pista.voltas:
		_chegar()
		return
	volta += 1
	_tocar("volta", 1.25 if recorde else 1.0, -4.0)
	carro._avisar("ÚLTIMA VOLTA!" if volta == pista.voltas else "VOLTA %d/%d" % [volta, pista.voltas], 2.0)

## Ponta a ponta: o 0 é a largada (só arma os portões), o último é a bandeirada
func _portao_sprint(k: int):
	if k == 0:
		_cruzou_largada = true
		return
	if k < pista.total_portoes() - 1:
		_tocar("clique", 1.5, -8.0)
		return
	_ultima = _relogio - _inicio
	_melhor = _ultima
	_chegar()

func _chegar():
	_total = _relogio - _largada
	# Quem já recebeu a bandeirada chegou antes (adversários e outros jogadores)
	var jogadores_antes := remotos.values().filter(func(r): return r.chegou)
	posicao = trafego.chegada.size() + jogadores_antes.size() + 1
	_mudar(Fase.CHEGADA)
	_tocar("volta", 1.5, -2.0)
	carro._avisar("BANDEIRADA!", 2.5)
	var vencedor := "VOCÊ"
	if not trafego.chegada.is_empty():
		vencedor = trafego.chegada[0].nome()
	elif not jogadores_antes.is_empty():
		vencedor = jogadores_antes[0].nome
	_painel.mostrar_chegada(posicao, total_carros(), _tempo(_total), _tempo(_melhor), vencedor, pista.aberta)
	_painel.mostrar()
	terminou.emit(_total, _melhor)

## Posição: 1 + adversários com mais progresso. O do piloto soma as voltas fechadas
## à distância desde a linha (antes de cruzá-la pela primeira vez, ele fica negativo;
## na pista aberta é só a distância desde a largada).
## O tráfego usa esse progresso para o "elástico" dos adversários
func _atualizar_posicao():
	var d := trafego.jogador.s
	var meu: float
	if pista.aberta:
		meu = d - pista.s_largada
	elif not _cruzou_largada:
		meu = d - pista.comprimento if d > pista.comprimento * 0.5 else d
	else:
		# Logo antes de fechar a volta já é o fim da pista: não dá volta a mais
		meu = (volta - 1) * pista.comprimento + d
	trafego.jogador.progresso = meu
	var frente := 0
	for rival in rivais:
		if rival.progresso > meu:
			frente += 1
	for remoto in remotos.values():
		if remoto.progresso > meu:
			frente += 1
	posicao = frente + 1

## Carros no grid: adversários, este jogador e os outros do grupo
func total_carros() -> int:
	var jogadores: int = grupo.get("jogadores", []).size()
	return rivais.size() + maxi(jogadores, remotos.size() + 1)

# --- Outros jogadores (corrida em grupo) ------------------------------------------------

## Telemetria de outro jogador da sala (~30x/s): o fantasma dele, a posição na
## corrida e, no anfitrião, o retrato para a IA; o pacote do anfitrião traz também os
## adversários e o relógio dos obstáculos para os bonecos daqui
func receber_remoto(item: Dictionary):
	var peer := int(item.get("peer", 0))
	if grupo.is_empty() or fase == Fase.PARADA or peer == multiplayer.get_unique_id():
		return
	var t := float(item.get("t", InterpoladorRede.agora()))
	if not remotos.has(peer):
		var vaga := 0
		for jogador in grupo.get("jogadores", []):
			if int(jogador.peer) == peer:
				vaga = int(jogador.vaga)
		var pintura: Array = CarroFantasma.PINTURAS_JOGADOR[vaga % CarroFantasma.PINTURAS_JOGADOR.size()]
		var fantasma := CarroFantasma.new(pintura, str(item.get("nome", "")), 0, true, true)
		pista.get_parent().add_child(fantasma)
		remotos[peer] = {"carro": fantasma, "nome": str(item.get("nome", "")), "progresso": -INF, "chegou": false, "visto_em": 0.0}
	var remoto: Dictionary = remotos[peer]
	var pos: Vector3 = item.get("pos", Vector3.ZERO)
	remoto.carro.visible = not item.get("explodindo", false) and str(item.get("mapa", "")) == pista.get_parent().nome
	remoto.carro.receber(t, pos, item.get("rot", Quaternion.IDENTITY), float(item.get("vel", 0.0)))
	remoto.carro.ver_nitro(int(item.get("nitros", 0)))
	remoto.progresso = float(item.get("progresso", -INF))
	remoto.chegou = item.get("chegou", false)
	remoto.visto_em = InterpoladorRede.agora()
	if not trafego.remoto:
		# Anfitrião: a IA desvia e disputa posição com ele
		var info := trafego.jogador_remoto(peer)
		var proj := pista.projetar(pista.to_local(pos))
		info.s = proj.x
		info.d = proj.y
		info.v = float(item.get("vel", 0.0)) / 3.6
		info.progresso = remoto.progresso
		info.nome_remoto = remoto.nome
		info.presente = remoto.carro.visible and absf(proj.y) < pista.largura
	elif item.has("rivais"):
		for r in item.rivais:
			var i := int(r[0]) - 1
			if i >= 0 and i < rivais.size():
				rivais[i].receber_rede(t, r[1], r[2], float(r[3]), float(r[4]))
		if trafego.obstaculos and item.has("relogio"):
			trafego.obstaculos.tempo = float(item.relogio)

func _tirar_remoto(peer: int):
	var remoto: Dictionary = remotos.get(peer, {})
	if remoto.is_empty():
		return
	remoto.carro.queue_free()
	remotos.erase(peer)
	if trafego:
		trafego.tirar_remoto(peer)

func _tocar(nome: String, pitch: float, volume: float):
	var som: AudioStream = SomGerador.biblioteca.get(nome)
	if som:
		_som.stream = som
		_som.pitch_scale = pitch
		_som.volume_db = volume
		_som.play()

func _process(_delta):
	if carro == null or fase == Fase.PARADA:
		return
	# Jogador do grupo que parou de mandar telemetria saiu da corrida
	for peer in remotos.keys():
		if InterpoladorRede.agora() - remotos[peer].visto_em > SUMIR_REMOTO:
			_tirar_remoto(peer)
	var total := total_carros()
	match fase:
		Fase.CONTROLES:
			if grupo.is_empty():
				_painel.mostrar_controles(_dispositivo(), TEMPO_CONTROLES - _tempo_fase)
				carro.painel_corrida = "GRID %d/%d\n%s\nAGUARDE" % [total, total, _formato()]
			else:
				var restante := float(_status.get("restante", -1.0))
				var prontos := "PRONTOS %d/%d" % [int(_status.get("prontos", 0)), int(_status.get("total", grupo.jogadores.size()))]
				var espera := "AGUARDANDO JOGADORES" if restante < 0.0 else "%s · %ds" % [prontos, ceili(restante)]
				_painel.mostrar_controles(_dispositivo(), maxf(restante, 0.0), espera, _pronto_enviado)
				carro.painel_corrida = "GRID %d/%d\n%s\n%s" % [total, total, prontos, "AGUARDE" if _pronto_enviado else "APERTE A"]
		Fase.CONTAGEM:
			carro.painel_corrida = "GRID %d/%d\n%s\nLARGADA %d" % [total, total, _formato(), 3 - maxi(_passo_contagem, 0)]
		Fase.CORRENDO:
			var atual := _relogio - _inicio
			if pista.aberta:
				var falta := maxf(pista.distancia_corrida() - trafego.jogador.progresso, 0.0)
				carro.painel_corrida = "SPRINT POS %d/%d\nT   %s\nFALTAM %d m" % [posicao, total, _tempo(atual), roundi(falta)]
			else:
				carro.painel_corrida = "VOLTA %d/%d POS %d/%d\nT   %s\nULT %s\nMEL %s" % [volta, pista.voltas, posicao, total, _tempo(atual), _tempo(_ultima), _tempo(_melhor)]
		Fase.CHEGADA:
			carro.painel_corrida = "CHEGOU %dº/%d\nTOT %s\nMEL %s\nSAIA: PORTAL" % [posicao, total, _tempo(_total), _tempo(_melhor)]

## "3 VOLTAS" ou, ponta a ponta, "SPRINT 1600 m"
func _formato() -> String:
	if pista.aberta:
		return "SPRINT %d m" % roundi(pista.distancia_corrida())
	return "%d VOLTAS" % pista.voltas

func _tempo(s: float) -> String:
	if s < 0.0:
		return "-:--.-"
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]
