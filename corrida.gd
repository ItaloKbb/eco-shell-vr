class_name Corrida
extends Node
## Corrida do circuito: o piloto entra preso na última vaga do grid, vê os controles
## do dispositivo em uso, passa pela contagem (3, 2, 1, VAI! com o semáforo do pórtico)
## e corre VOLTAS voltas. A volta só vale passando por todos os portões da pista na
## ordem (sem atalho pelo miolo); a primeira passagem pela linha, logo depois do grid,
## só arma a contagem. Ao fechar a última volta mostra o resultado, e o piloto segue
## livre para sair pelo portal. O texto do visor vai em car.gd painel_corrida.
## Os adversários correm por conta própria (TrafegoCorrida + IARival): ficam parados
## no grid até o VAI!, e a posição compara o progresso deles com o do piloto.

enum Fase { PARADA, CONTROLES, CONTAGEM, CORRENDO, CHEGADA }
const VOLTAS := 3
## Quanto tempo os controles ficam na tela antes de a contagem começar sozinha (s)
const TEMPO_CONTROLES := 8.0
const TEMPO_CONTAGEM := 3.0
## Quanto o resultado fica na frente do piloto antes de recolher (s)
const TEMPO_RESULTADO := 7.0

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

func _ready():
	pista.portao.connect(_portao)
	_som = AudioStreamPlayer.new()
	_som.bus = "Carro"
	add_child(_som)

## Começa do grid: carro preso, controles na tela
func iniciar():
	volta = 0
	posicao = rivais.size() + 1
	_proximo = 0
	_cruzou_largada = false
	_largada = -1.0
	_inicio = -1.0
	_ultima = -1.0
	_melhor = -1.0
	_total = -1.0
	_usando_controle = not Input.get_connected_joypads().is_empty()
	trafego.carro = carro
	trafego.voltas = VOLTAS
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

## Saiu do deserto (portal ou morte): limpa tudo
func abortar():
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
		_contar()

func _botao_vr(nome: String):
	if fase == Fase.CONTROLES and nome == "ax_button":
		_contar()

func _physics_process(delta: float):
	if carro == null or carro.em_transicao or fase == Fase.PARADA:
		return
	_relogio += delta
	_tempo_fase += delta
	match fase:
		Fase.CONTROLES:
			if _tempo_fase >= TEMPO_CONTROLES:
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
	_proximo = (k + 1) % PistaCorrida.PORTOES
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
	if volta >= VOLTAS:
		_chegar()
		return
	volta += 1
	_tocar("volta", 1.25 if recorde else 1.0, -4.0)
	carro._avisar("ÚLTIMA VOLTA!" if volta == VOLTAS else "VOLTA %d/%d" % [volta, VOLTAS], 2.0)

func _chegar():
	_total = _relogio - _largada
	# Quem já recebeu a bandeirada chegou antes; os outros ficaram para trás
	posicao = trafego.chegada.size() + 1
	_mudar(Fase.CHEGADA)
	_tocar("volta", 1.5, -2.0)
	carro._avisar("BANDEIRADA!", 2.5)
	var vencedor := "VOCÊ" if trafego.chegada.is_empty() else trafego.chegada[0].nome()
	_painel.mostrar_chegada(posicao, rivais.size() + 1, _tempo(_total), _tempo(_melhor), vencedor)
	_painel.mostrar()
	terminou.emit(_total, _melhor)

## Posição: 1 + adversários com mais progresso. O do piloto soma as voltas fechadas
## à distância desde a linha (antes de cruzá-la pela primeira vez, ele fica negativo).
## O tráfego usa esse progresso para o "elástico" dos adversários
func _atualizar_posicao():
	var d := trafego.jogador.s
	var meu: float
	if not _cruzou_largada:
		meu = d - pista.comprimento if d > pista.comprimento * 0.5 else d
	else:
		# Logo antes de fechar a volta já é o fim da pista: não dá volta a mais
		meu = (volta - 1) * pista.comprimento + d
	trafego.jogador.progresso = meu
	var frente := 0
	for rival in rivais:
		if rival.progresso > meu:
			frente += 1
	posicao = frente + 1

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
	var total := rivais.size() + 1
	match fase:
		Fase.CONTROLES:
			_painel.mostrar_controles(_dispositivo(), TEMPO_CONTROLES - _tempo_fase)
			carro.painel_corrida = "GRID %d/%d\n%d VOLTAS\nAGUARDE" % [total, total, VOLTAS]
		Fase.CONTAGEM:
			carro.painel_corrida = "GRID %d/%d\n%d VOLTAS\nLARGADA %d" % [total, total, VOLTAS, 3 - maxi(_passo_contagem, 0)]
		Fase.CORRENDO:
			var atual := _relogio - _inicio
			carro.painel_corrida = "VOLTA %d/%d POS %d/%d\nT   %s\nULT %s\nMEL %s" % [volta, VOLTAS, posicao, total, _tempo(atual), _tempo(_ultima), _tempo(_melhor)]
		Fase.CHEGADA:
			carro.painel_corrida = "CHEGOU %dº/%d\nTOT %s\nMEL %s\nSAIA: PORTAL" % [posicao, total, _tempo(_total), _tempo(_melhor)]

func _tempo(s: float) -> String:
	if s < 0.0:
		return "-:--.-"
	return "%d:%04.1f" % [int(s / 60.0), fmod(s, 60.0)]
