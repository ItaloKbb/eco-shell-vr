extends Node
## Uma vida começa na esfera, com identificação e lançamento, no PC e no XR.
## No evento (conectado ao servidor) a esfera fica em AGUARDANDO, mostrando o apelido
## do óculos, até o operador liberar; o nick vem do painel e pula a identificação.
## No notebook (fora da VR) o jogador já digita o próprio nome na espera, e ele aparece
## no painel do operador como sugestão para a liberação.
## Encerrar a sessão devolve o piloto à esfera, em espera para a próxima pessoa.
enum Estado { ESCOLHA, CARGA, PARTIDA, MORTE, AGUARDANDO }
const ARQUIVO := "user://piloto.cfg"
const LETRAS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
const RESOLUCAO := Vector2i(800, 320)
## No headset o painel precisa ocupar uma parte maior do campo de visão. A
## resolução continua igual para não aumentar o custo da SubViewport no Quest.
## Fica além do bico do carro (1,35 m à frente da cabeça) e dentro da esfera (raio 3 m);
## o tamanho cresce junto com a distância para manter o mesmo ângulo de visão.
const TAMANHO_PAINEL_MONITOR := Vector2(1.0, 0.4)
const TAMANHO_PAINEL_VR := Vector2(2.0, 0.8)
const DISTANCIA_PAINEL_VR := 2.1
## Paleta do painel e da esfera: ciano do jogador, âmbar da energia no limite
const COR_CIANO := PainelHolografico.COR_CIANO
const COR_QUENTE := PainelHolografico.COR_QUENTE
const COR_LUZ := Color(0.3, 0.6, 1.0)
const SEGMENTOS := 20
## Lançamento no PC: a casca estilhaça e o carro atravessa o buraco
const TEMPO_RUPTURA := 0.9
const ATRASO_VOO := 0.3
const TEMPO_VOO := 0.35

var arquivo_perfil := ARQUIVO
var estado := Estado.ESCOLHA
var nick := "PILOTO"
var cursor := 0
var carga := 0.0
var _soltou := false
var _repeticao := 0.0
var _eixo_anterior := Vector2i.ZERO
var _fase := 0.0
var _tom: AudioStreamGeneratorPlayback
var _som: AudioStreamPlayer
var _tela: SubViewport
var _painel: PainelHolografico
var _material: ShaderMaterial
var _ruptura: Tween
var _voo: Tween
## Controles do painel (desenhados na SubViewport)
var _etapa: Label
var _caixa_nick: HBoxContainer
var _caixa_espera: VBoxContainer
var _rotulo_oculos: Label
var _slots: Array[Label] = []
var _estilos_slot: Array[StyleBoxFlat] = []
var _caixa_carga: VBoxContainer
var _legenda_carga: Label
var _segmentos: Array[ColorRect] = []
var _porcento: Label
var _dicas: HBoxContainer
var _pronto := false
var _reiniciando := false
## Corrida em grupo tirou o piloto da esfera: o lançamento em andamento não solta o carro
var _puxado := false
var _modo_vr := false
## Fora da VR: o último comando veio de um gamepad (muda a edição do nick e os textos)
var _usando_controle := false
## O nick atual foi digitado na espera (sobrevive a uma queda do servidor)
var _nome_da_espera := false
var _fade_spawn: Transicao
@onready var mapa = get_parent()
@onready var carro = mapa.get_node("Carro")
@onready var esfera: MeshInstance3D = mapa.get_node("EsferaInicial")

func _ready():
	_modo_vr = get_viewport().use_xr
	_usando_controle = not Input.get_connected_joypads().is_empty()
	carro.em_ritual = true
	carro.explodiu.connect(_morreu)
	carro.retorno_solicitado.connect(voltar_ao_ovo)
	carro.visao_recentralizada.connect(_visao_recentralizada)
	carro.mao_direita.button_pressed.connect(_botao_vr)
	Rede.sessao_mudou.connect(_sessao_mudou)
	Rede.apelido_mudou.connect(func(_apelido: String): _atualizar_texto())
	var config := ConfigFile.new()
	if config.load(arquivo_perfil) == OK:
		nick = _sanitizar(str(config.get_value("piloto", "nick", "PILOTO")))
	if nick.is_empty():
		nick = "PILOTO"
	_material = ShaderMaterial.new()
	_material.shader = preload("res://esfera_nascimento.gdshader")
	if _modo_vr:
		_material.set_shader_parameter("intensidade", 0.6)
		_material.set_shader_parameter("cintilar", 0.0)
		_material.set_shader_parameter("simplificar_vr", 1.0)
		_fade_spawn = Transicao.new()
		add_child(_fade_spawn)
	esfera.set_surface_override_material(0, _material)
	# Luz fria por dentro: a laranja antiga deixava o cockpit cor de barro
	esfera.get_node("LuzEsfera").light_color = COR_LUZ
	esfera.get_node("Colisao").collision_layer = 0
	_montar_painel()
	_montar_som()
	# O pai escolhe a câmera XR depois de adicionar este controlador.
	_nova_vida.call_deferred()

func _sanitizar(valor: String) -> String:
	var resultado := ""
	for letra in valor.strip_edges().to_upper():
		if letra in LETRAS and resultado.length() < 8:
			resultado += letra
	return resultado.strip_edges()

## Explodiu ou terminou a corrida: a vida acaba, o piloto volta para o ovo e, no
## evento, a sessão encerra (servidor em idle, esfera esperando o operador)
func voltar_ao_ovo():
	Rede.terminar_sessao()
	_nova_vida()

func _nova_vida():
	if _reiniciando:
		return
	_reiniciando = true
	_pronto = false
	_puxado = false
	carro.em_ritual = true
	carro.freeze = true
	var mundos = mapa.get_node_or_null("Mundos")
	if mundos:
		await mundos.restaurar_inicio()
	if _modo_vr:
		await _fade_spawn.cobrir(Color(0.05, 0.1, 0.2), 0.15, "Nascimento")
	carro.pista.limpar()
	if _modo_vr:
		mapa.ajustar_spawn_vr(true)
	for tween in [_ruptura, _voo]:
		if tween and tween.is_valid():
			tween.kill()
	esfera.scale = Vector3.ONE
	esfera.visible = true
	_material.set_shader_parameter("ruptura", 0.0)
	_material.set_shader_parameter("carga", 0.0)
	carro.camera.fov = carro._fov
	estado = _estado_na_esfera()
	if estado == Estado.CARGA:
		_usar_nome_do_operador()
	elif estado == Estado.AGUARDANDO:
		_limpar_nome_da_espera()
	carga = 0.0
	_resetar_carga()
	cursor = 0
	carro.preparar_vida(Transform3D(Basis.IDENTITY, esfera.global_position - Vector3.UP * 0.3))
	if get_viewport().use_xr:
		carro.camera_xr.make_current()
	else:
		carro.camera.make_current()
	if _modo_vr:
		if get_viewport().use_xr:
			await carro.recentralizar()
		await get_tree().process_frame
		await get_tree().process_frame
		# Painel ancorado no mundo e alinhado ao carro, não ao olhar momentâneo.
		_painel.reparent(mapa, false)
		_posicionar_painel_vr()
	else:
		_painel.reparent(carro.camera, false)
		_painel.position = Vector3(0.0, 0.08, -1.2)
	_atualizar_texto()
	_painel.mostrar()
	if _modo_vr:
		await _fade_spawn.descobrir(0.25)
	_pronto = true
	_reiniciando = false
	_informar_sessao()

## Evento: com servidor a esfera espera o operador e o nick vem do painel; sem
## servidor o piloto escolhe o nick como sempre
func _estado_na_esfera() -> Estado:
	if Rede.conectado:
		return Estado.CARGA if Rede.liberado else Estado.AGUARDANDO
	return Estado.ESCOLHA

func _usar_nome_do_operador():
	var limpo := _sanitizar(Rede.nome_jogador)
	nick = limpo if not limpo.is_empty() else "PILOTO"
	_nome_da_espera = false
	carro.nickname = nick

## Espera em que o jogador digita o nome no teclado (notebook; na VR só o operador)
func _digitando_na_espera() -> bool:
	return estado == Estado.AGUARDANDO and not _modo_vr

## Próxima pessoa na espera: começa sem nome (nem o do jogador anterior)
func _limpar_nome_da_espera():
	nick = ""
	cursor = 0
	_nome_da_espera = false
	if not _modo_vr:
		Rede.enviar_nome_sugerido("")

func _informar_sessao():
	Rede.informar_estado("lobby" if Rede.liberado else "idle")

## Conectou/caiu, liberado ou sessão encerrada pelo operador
func _sessao_mudou():
	if Rede.liberado:
		_usar_nome_do_operador()
	if estado in [Estado.ESCOLHA, Estado.CARGA, Estado.AGUARDANDO]:
		var novo := _estado_na_esfera()
		if novo != estado:
			estado = novo
			if estado == Estado.AGUARDANDO and not _nome_da_espera:
				_limpar_nome_da_espera()
			carga = 0.0
			carro.comando_acel = 0.0
			_resetar_carga()
		_informar_sessao()
		# Reconectou com um nome já digitado: o servidor novo ainda não o conhece
		if _digitando_na_espera() and not nick.is_empty():
			Rede.enviar_nome_sugerido(nick)
	elif Rede.conectado and not Rede.liberado:
		# Fora da esfera sem liberação (sessão encerrada): volta para a espera
		_nova_vida()
	_atualizar_texto()

func _resetar_carga():
	_soltou = false
	_repeticao = 0.0
	_eixo_anterior = Vector2i.ZERO

func _morreu():
	estado = Estado.MORTE
	carga = 0.0
	_painel.visible = false

func _input(event: InputEvent):
	var era_controle := _usando_controle
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_usando_controle = true
	elif event is InputEventKey:
		_usando_controle = false
	if _usando_controle != era_controle:
		_atualizar_texto()
	if _pronto and _digitando_na_espera():
		_digitar_na_espera(event)
		return
	if not _pronto or estado != Estado.ESCOLHA:
		return
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_START:
			_confirmar()
			get_viewport().set_input_as_handled()
		elif event.button_index == JOY_BUTTON_B:
			nick = nick.left(cursor) + nick.substr(cursor + 1)
			cursor = mini(cursor, nick.length())
			_atualizar_texto()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirmar()
		elif event.keycode == KEY_BACKSPACE:
			nick = nick.left(maxi(0, nick.length() - 1))
			cursor = mini(cursor, nick.length())
		elif event.unicode >= 32 and event.unicode < 127 and nick.length() < 8:
			var letra := String.chr(event.unicode).to_upper()
			if letra in LETRAS:
				nick += letra
				cursor = mini(nick.length(), 7)
		_atualizar_texto()
		get_viewport().set_input_as_handled()

## Teclado na espera: letras e ⌫ editam o nome, que vai para o painel a cada mudança
func _digitar_na_espera(event: InputEvent):
	if not (event is InputEventKey and event.pressed):
		return
	var antes := nick
	if event.keycode == KEY_BACKSPACE:
		nick = nick.left(maxi(0, nick.length() - 1))
	elif event.unicode >= 32 and event.unicode < 127 and nick.length() < 8:
		var letra := String.chr(event.unicode).to_upper()
		if letra in LETRAS and not (letra == " " and nick.is_empty()):
			nick += letra
	else:
		return
	get_viewport().set_input_as_handled()
	if nick != antes:
		_nome_da_espera = true
		Rede.enviar_nome_sugerido(nick.strip_edges())
		_atualizar_texto()

func _botao_vr(nome: String):
	if nome in ["primary_click", "menu_button"]:
		carro.recentralizar()
		return
	if _pronto and estado == Estado.ESCOLHA and nome == "ax_button":
		_confirmar()

func _visao_recentralizada():
	if _modo_vr and is_instance_valid(_painel) and _painel.is_inside_tree():
		_posicionar_painel_vr()

func _posicionar_painel_vr():
	var frente: Vector3 = -carro.global_basis.z
	frente.y = 0.0
	if frente.length_squared() < 0.01:
		frente = Vector3.FORWARD
	frente = frente.normalized()
	var ancora: Vector3 = carro.global_transform * carro.ANCORA_CABECA_LOCAL
	_painel.global_position = ancora + frente * DISTANCIA_PAINEL_VR
	_painel.look_at(ancora, Vector3.UP, true)

func _confirmar():
	var limpo := _sanitizar(nick)
	if limpo.is_empty():
		return
	nick = limpo
	carro.nickname = nick
	var config := ConfigFile.new()
	config.set_value("piloto", "nick", nick)
	var erro := config.save(arquivo_perfil)
	if erro != OK:
		push_warning("Não foi possível salvar o nickname: %s" % error_string(erro))
	estado = Estado.CARGA
	_resetar_carga()
	_atualizar_texto()

func _physics_process(delta: float):
	if not _pronto or estado == Estado.MORTE or estado == Estado.PARTIDA:
		return
	if estado == Estado.ESCOLHA:
		# VR: analógico esquerdo do Quest; gamepad: analógico esquerdo ou direcional
		var analogico := Vector2.ZERO
		if get_viewport().use_xr:
			analogico = carro.mao_esquerda.get_vector2("primary")
		var pad := Vector2(carro.eixo_controle(JOY_AXIS_LEFT_X), -carro.eixo_controle(JOY_AXIS_LEFT_Y))
		pad.x += float(carro.botao_controle(JOY_BUTTON_DPAD_RIGHT)) - float(carro.botao_controle(JOY_BUTTON_DPAD_LEFT))
		pad.y += float(carro.botao_controle(JOY_BUTTON_DPAD_UP)) - float(carro.botao_controle(JOY_BUTTON_DPAD_DOWN))
		if pad.length() > analogico.length():
			analogico = pad
		_editar_nick(delta, analogico)
	if estado == Estado.CARGA:
		var acel := 1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0
		acel = maxf(acel, carro.eixo_controle(JOY_AXIS_TRIGGER_RIGHT))
		if get_viewport().use_xr:
			acel = maxf(acel, carro.mao_direita.get_float("trigger"))
		if acel < 0.15:
			_soltou = true
		if _soltou:
			carga = move_toward(carga, 1.0 if acel > 0.5 else 0.0, delta * 0.5)
		carro.comando_acel = carga
		if carga >= 1.0:
			_tentar_partida()
	var pulso := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (3.0 + carga * 14.0))
	_material.set_shader_parameter("carga", carga)
	var luz: OmniLight3D = esfera.get_node("LuzEsfera")
	luz.light_color = COR_LUZ.lerp(COR_QUENTE, smoothstep(0.4, 1.0, carga))
	luz.light_energy = 0.0 if _modo_vr else 0.6 + carga * (1.8 + pulso * 0.6)
	_atualizar_texto()

## Analógico/direcional: ← → move o cursor, ↑ ↓ troca a letra (com repetição ao segurar)
func _editar_nick(delta: float, analogico: Vector2):
	var eixo := Vector2i(int(signf(analogico.x)) if absf(analogico.x) > 0.6 else 0,
		int(signf(analogico.y)) if absf(analogico.y) > 0.6 else 0)
	_repeticao -= delta
	if eixo == Vector2i.ZERO:
		_repeticao = 0.0
	elif eixo != _eixo_anterior or _repeticao <= 0.0:
		_repeticao = 0.25 if eixo == _eixo_anterior else 0.4
		if eixo.x != 0:
			cursor = clampi(cursor + eixo.x, 0, mini(nick.length(), 7))
		elif eixo.y != 0:
			while nick.length() <= cursor:
				nick += " "
			var indice := LETRAS.find(nick[cursor])
			nick = nick.left(cursor) + LETRAS[posmod(indice + eixo.y, LETRAS.length())] + nick.substr(cursor + 1)
	_eixo_anterior = eixo

func _tentar_partida():
	# Só sai quando a colisão real do terreno estiver disponível sob as três rodas.
	var saida := Vector3(0.0, 0.0, -7.0)
	var altura := -INF
	for deslocamento in [Vector3(-0.36, 0, -0.75), Vector3(0.36, 0, -0.75), Vector3(0, 0, 0.7)]:
		var p: Vector3 = saida + deslocamento
		var consulta := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0, carro.mascara_chao, [carro.get_rid()])
		var chao: Dictionary = carro.get_world_3d().direct_space_state.intersect_ray(consulta)
		if chao.is_empty():
			return
		altura = maxf(altura, chao.position.y)
	estado = Estado.PARTIDA
	_painel.visible = false
	var destino := Transform3D(Basis.IDENTITY, Vector3(saida.x, altura + 0.15, saida.z))
	if _modo_vr:
		_sair_vr(destino)
		return
	_lancar(destino)

## PC: a casca estilhaça a partir da saída e o carro atravessa o buraco, com um
## puxão no campo de visão; só no fim a física assume com a velocidade de largada.
func _lancar(destino: Transform3D):
	# _reposicionar soma 0,3 m na altura: desconta para o começo bater com a pose atual
	var inicio := Transform3D(carro.global_basis, carro.global_position - Vector3.UP * 0.3)
	_ruptura = create_tween().set_parallel(true)
	_ruptura.tween_method(func(v: float): _material.set_shader_parameter("ruptura", v), 0.0, 1.0, TEMPO_RUPTURA) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ruptura.tween_property(esfera.get_node("LuzEsfera"), "light_energy", 0.0, TEMPO_RUPTURA)
	_ruptura.chain().tween_callback(esfera.hide)
	var fov: float = carro.camera.fov
	_voo = create_tween()
	_voo.tween_interval(ATRASO_VOO)
	_voo.tween_method(func(f: float): carro.teleportar(inicio.interpolate_with(destino, f)), 0.0, 1.0, TEMPO_VOO) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_voo.parallel().tween_property(carro.camera, "fov", fov + 22.0, TEMPO_VOO).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_voo.tween_callback(carro.liberar_partida.bind(destino))
	_voo.tween_property(carro.camera, "fov", fov, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _sair_vr(destino: Transform3D):
	await _fade_spawn.cobrir(Color(0.05, 0.1, 0.2), 0.15, "Saída da esfera", false)
	if _puxado:
		# A transição dos mundos assume a tela
		_fade_spawn.descobrir(0.3)
		return
	# Evita transparência de tela inteira, expansão sobre os olhos e salto visível.
	esfera.hide()
	carro.teleportar(destino)
	mapa.ajustar_spawn_vr(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_spawn.descobrir(0.3)
	if not _puxado:
		carro.liberar_partida(destino)

## Corrida em grupo puxou este jogador ainda na esfera (ou saindo dela): sai direto, já
## parado para a transição dos mundos levar ao grid. Cancela um lançamento em andamento
func sair_para_corrida():
	if estado == Estado.MORTE:
		return
	_puxado = true
	estado = Estado.PARTIDA
	carga = 0.0
	carro.comando_acel = 0.0
	_painel.visible = false
	for tween in [_ruptura, _voo]:
		if tween and tween.is_valid():
			tween.kill()
	carro.camera.fov = carro._fov
	esfera.hide()
	if _modo_vr:
		mapa.ajustar_spawn_vr(false)
		_fade_spawn.descobrir(0.3)
	carro.liberar_partida(carro.global_transform)
	carro.iniciar_transicao()

func _montar_painel():
	_slots.clear()
	_estilos_slot.clear()
	_segmentos.clear()
	var tamanho_painel := TAMANHO_PAINEL_VR if _modo_vr else TAMANHO_PAINEL_MONITOR
	_painel = PainelHolografico.new(RESOLUCAO, tamanho_painel, _modo_vr)
	_tela = _painel.tela
	_etapa = _painel.etapa
	var coluna := _painel.coluna

	# Miolo: um dos dois blocos aparece por vez
	var miolo := CenterContainer.new()
	miolo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(miolo)
	_caixa_nick = HBoxContainer.new()
	_caixa_nick.add_theme_constant_override("separation", 10)
	miolo.add_child(_caixa_nick)
	for i in 8:
		var estilo := PainelHolografico.estilo(Color.TRANSPARENT, Color.TRANSPARENT, 2, 6)
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(62, 84)
		slot.add_theme_stylebox_override("panel", estilo)
		var letra := PainelHolografico.rotulo("", 46, Color.WHITE, true)
		letra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letra.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(letra)
		_caixa_nick.add_child(slot)
		_slots.append(letra)
		_estilos_slot.append(estilo)

	# Espera do evento: o apelido do óculos em destaque para o operador achar qual é
	_caixa_espera = VBoxContainer.new()
	_caixa_espera.add_theme_constant_override("separation", 10)
	miolo.add_child(_caixa_espera)
	_rotulo_oculos = PainelHolografico.rotulo("", 64, Color.WHITE, true, 6)
	_rotulo_oculos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caixa_espera.add_child(_rotulo_oculos)
	var aguarde := PainelHolografico.rotulo("AGUARDE A LIBERAÇÃO", 26, COR_CIANO, true, 6)
	aguarde.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caixa_espera.add_child(aguarde)

	_caixa_carga = VBoxContainer.new()
	_caixa_carga.add_theme_constant_override("separation", 12)
	miolo.add_child(_caixa_carga)
	_legenda_carga = PainelHolografico.rotulo("", 26, Color.WHITE, true, 6)
	_legenda_carga.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caixa_carga.add_child(_legenda_carga)
	var linha_barra := HBoxContainer.new()
	linha_barra.add_theme_constant_override("separation", 16)
	_caixa_carga.add_child(linha_barra)
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 4)
	linha_barra.add_child(barra)
	for i in SEGMENTOS:
		var segmento := ColorRect.new()
		segmento.custom_minimum_size = Vector2(22, 40)
		barra.add_child(segmento)
		_segmentos.append(segmento)
	_porcento = PainelHolografico.rotulo("", 36, Color.WHITE, true)
	_porcento.custom_minimum_size.x = 110
	_porcento.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	linha_barra.add_child(_porcento)

	# Rodapé: dicas com o botão desenhado como uma tecla
	_dicas = PainelHolografico.caixa_dicas()
	coluna.add_child(_dicas)
	add_child(_painel)

func _atualizar_texto():
	var agora := Time.get_ticks_msec() * 0.001
	var digitando := _digitando_na_espera()
	var escolha := estado == Estado.ESCOLHA or digitando
	var espera := estado == Estado.AGUARDANDO and not digitando
	_caixa_nick.visible = escolha
	_caixa_espera.visible = espera
	_caixa_carga.visible = not escolha and not espera
	if espera:
		_etapa.text = "EM ESPERA"
		_rotulo_oculos.text = Rede.apelido.to_upper() if Rede.apelido != "" else "CONECTADO"
		_painel.definir_dicas(_dicas, [["L3/R3", "CENTRALIZAR"]] if _modo_vr else [])
	elif escolha:
		_etapa.text = "IDENTIFICAÇÃO"
		if digitando:
			var aparelho := Rede.apelido.to_upper() if Rede.apelido != "" else "CONECTADO"
			_etapa.text = "%s · AGUARDE A LIBERAÇÃO" % aparelho
		# Teclado: destaca onde a próxima letra entra; controle/VR: a letra em edição
		var ativo := cursor if (_modo_vr or _usando_controle) and not digitando else mini(nick.length(), 7)
		# Piscar só no monitor: na VR o painel só redesenha quando algo muda
		var brilho := 1.0 if _modo_vr else 0.75 + 0.25 * sin(agora * 6.0)
		for i in 8:
			var letra := nick[i] if i < nick.length() and nick[i] != " " else ""
			_slots[i].text = letra if letra else "·"
			_slots[i].modulate = Color.WHITE if letra else Color(COR_CIANO, 0.45)
			var estilo := _estilos_slot[i]
			if i == ativo:
				estilo.bg_color = Color(COR_CIANO, 0.2 * brilho)
				estilo.border_color = Color(COR_CIANO, brilho)
				estilo.set_border_width_all(3)
			else:
				estilo.bg_color = Color(COR_CIANO, 0.06)
				estilo.border_color = Color(COR_CIANO, 0.3)
				estilo.set_border_width_all(2)
		if digitando:
			_painel.definir_dicas(_dicas, [["A-Z", "DIGITE SEU NOME"], ["⌫", "APAGAR"]])
		elif _modo_vr:
			_painel.definir_dicas(_dicas, [["← →", "POSIÇÃO"], ["↑ ↓", "LETRA"], ["A", "CONFIRMAR"], ["L3/R3", "CENTRALIZAR"]])
		elif _usando_controle:
			_painel.definir_dicas(_dicas, [["← →", "POSIÇÃO"], ["↑ ↓", "LETRA"], ["B", "APAGAR"], ["A", "CONFIRMAR"]])
		else:
			_painel.definir_dicas(_dicas, [["A-Z", "DIGITE SEU NICK"], ["⌫", "APAGAR"], ["ENTER", "CONFIRMAR"]])
	else:
		_etapa.text = "LANÇAMENTO"
		_legenda_carga.text = "%s  ·  PRONTO PARA NASCER" % nick
		# VR avança de 5 em 5% para redesenhar o painel menos vezes
		var exibida := floorf(carga * SEGMENTOS) / SEGMENTOS if _modo_vr else carga
		_porcento.text = "%d%%" % int(exibida * 100.0)
		var cor_carga := COR_CIANO.lerp(COR_QUENTE, smoothstep(0.5, 1.0, carga))
		_porcento.add_theme_color_override("font_color", cor_carga)
		var pulso := 1.0 if _modo_vr else 0.8 + 0.2 * sin(agora * (6.0 + carga * 16.0))
		for i in SEGMENTOS:
			var preenchido := clampf(exibida * SEGMENTOS - i, 0.0, 1.0)
			var cor := COR_CIANO.lerp(COR_QUENTE, float(i) / (SEGMENTOS - 1))
			_segmentos[i].color = Color(COR_CIANO, 0.12).lerp(Color(cor, pulso), preenchido)
		var tecla := "GATILHO" if _modo_vr else ("RT" if _usando_controle else "W")
		var dicas_carga: Array = [[tecla, "SOLTE PARA ARMAR" if not _soltou else "SEGURE PARA ROMPER A CASCA"]]
		if _modo_vr:
			dicas_carga.append(["L3/R3", "CENTRALIZAR"])
		_painel.definir_dicas(_dicas, dicas_carga)
	_painel.redesenhar("%d|%s|%d|%s|%d|%d|%s" % [estado, nick, cursor, _porcento.text, int(_soltou), int(_usando_controle), Rede.apelido])

func _montar_som():
	_som = AudioStreamPlayer.new()
	var gerador := AudioStreamGenerator.new()
	gerador.mix_rate = 16000.0
	gerador.buffer_length = 0.08
	_som.stream = gerador
	_som.volume_db = -18.0
	add_child(_som)

func _process(_delta: float):
	if estado != Estado.CARGA or carga <= 0.0:
		if _som.playing:
			_som.stop()
		return
	if not _som.playing:
		_som.play()
		_tom = _som.get_stream_playback()
	for i in _tom.get_frames_available():
		_fase = fmod(_fase + TAU * (100.0 + carga * 650.0) / 16000.0, TAU)
		var amplitude := carga * 0.35 if estado == Estado.CARGA else 0.0
		var valor := (sin(_fase) + 0.25 * sin(_fase * 2.0)) * amplitude
		_tom.push_frame(Vector2.ONE * valor)

func _exit_tree():
	# O painel foi movido para a câmera; sua vida continua pertencendo ao controlador.
	if is_instance_valid(_painel):
		_painel.queue_free()
