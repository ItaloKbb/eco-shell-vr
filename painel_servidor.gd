extends Control
## Painel do servidor do evento (só 2D, nada de 3D), em forma de dashboard: cabeçalho
## com IP/porta e o anúncio, faixa de indicadores (óculos, jogando, correndo,
## espectadores, tempo ligado), os óculos em cards (estado, telemetria ao vivo do carro,
## bateria, ping e as ações do operador: liberar com o nome do jogador, encerrar sessão,
## apelido, desconectar), ranking geral com pódio e log de eventos.
## Toda a lógica fica em Rede, Dispositivos e Ranking; aqui só se mostra e se aciona.

const CORES_EVENTO := {
	"conexao": "#5ccfff", "estado": "#9aa0b4", "sessao": "#ffd24a", "tempo": "#4dff7a",
	"dispositivo": "#c58cff", "espectador": "#ffb35c", "erro": "#ff5050", "servidor": "#ffffff",
}
## Quanto tempo o tempo novo fica destacado no ranking (s)
const TEMPO_DESTAQUE := 8.0
const LARGURA_CARTAO := 460.0
const ALTURA_BAIXO := 220.0

var _ip: Label
var _anuncio: PanelContainer
var _contadores: Label
var _indicadores := {}
var _cartoes_box: HFlowContainer
var _vazio: Label
var _cartoes := {}
var _ranking: Tree
var _destaque := ""
var _destaque_ate := 0.0
var _log: RichTextLabel
var _filtro: OptionButton
var _pausar: CheckBox
var _dialogo_apelido: ConfirmationDialog
var _campo_apelido: LineEdit
var _peer_apelido := 0
var _confirma_limpar: ConfirmationDialog
var _tempo_refresco := 0.0

func _ready():
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = TemaEvento.criar()
	var fundo := ColorRect.new()
	fundo.color = TemaEvento.FUNDO
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 18)
	add_child(margem)
	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 14)
	margem.add_child(raiz)

	raiz.add_child(_montar_cabecalho())
	raiz.add_child(_montar_indicadores())
	# Os cards ficam com o que sobra; ranking e log numa faixa de altura fixa embaixo
	var oculos := _secao("ÓCULOS CONECTADOS", _montar_cartoes())
	oculos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(oculos)
	var baixo := HBoxContainer.new()
	baixo.custom_minimum_size.y = ALTURA_BAIXO
	baixo.add_theme_constant_override("separation", 14)
	raiz.add_child(baixo)
	var ranking := _secao("RANKING GERAL · MELHOR TEMPO DE CADA JOGADOR", _montar_ranking())
	ranking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baixo.add_child(ranking)
	var log_eventos := _secao("EVENTOS", _montar_log())
	log_eventos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_eventos.size_flags_stretch_ratio = 1.2
	baixo.add_child(log_eventos)
	_montar_dialogos()

	Dispositivos.mudou.connect(_sincronizar_cartoes)
	Ranking.ranking_mudou.connect(_mostrar_ranking)
	Ranking.novo_tempo.connect(_novo_tempo)
	Rede.evento.connect(_evento)
	_sincronizar_cartoes()
	_mostrar_ranking(Ranking.top)
	_reescrever_log()
	_atualizar_cabecalho()

func _process(delta: float):
	# O selo do anúncio pulsa a cada quadro; o resto refaz a cada 0,5 s
	var ativo := Rede.modo == Rede.Modo.SERVIDOR
	_anuncio.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.003)) if ativo else 1.0
	_tempo_refresco -= delta
	if _tempo_refresco > 0.0:
		return
	_tempo_refresco = 0.5
	_atualizar_cabecalho()
	for cartao in _cartoes.values():
		cartao.atualizar()
	if _destaque != "" and Time.get_ticks_msec() / 1000.0 > _destaque_ate:
		_destaque = ""
		_mostrar_ranking(Ranking.top)

# --- Cabeçalho e indicadores --------------------------------------------------------

func _montar_cabecalho() -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 18)
	var marca := VBoxContainer.new()
	marca.add_theme_constant_override("separation", 0)
	marca.add_child(TemaEvento.rotulo("ECO SHELL VR", 28, TemaEvento.CIANO, true))
	marca.add_child(TemaEvento.rotulo("SERVIDOR DO EVENTO", 13, TemaEvento.TEXTO_SUAVE, true))
	caixa.add_child(marca)
	var vao := Control.new()
	vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caixa.add_child(vao)
	var endereco := VBoxContainer.new()
	endereco.alignment = BoxContainer.ALIGNMENT_CENTER
	endereco.add_theme_constant_override("separation", 2)
	_ip = TemaEvento.rotulo("", 17, TemaEvento.TEXTO, true, true)
	_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	endereco.add_child(_ip)
	_contadores = TemaEvento.rotulo("", 12, TemaEvento.TEXTO_SUAVE, false, true)
	_contadores.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	endereco.add_child(_contadores)
	caixa.add_child(endereco)
	_anuncio = TemaEvento.pilula("●  ANUNCIANDO", TemaEvento.QUENTE, 15)
	_anuncio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	caixa.add_child(_anuncio)
	return caixa

func _montar_indicadores() -> Control:
	var faixa := HBoxContainer.new()
	faixa.add_theme_constant_override("separation", 12)
	for chave in [["oculos", "ÓCULOS", TemaEvento.CIANO], ["jogando", "JOGANDO", TemaEvento.CIANO],
			["correndo", "CORRENDO", TemaEvento.VERDE], ["espectadores", "ESPECTADORES", TemaEvento.QUENTE],
			["ligado", "LIGADO HÁ", TemaEvento.TEXTO]]:
		var cartao := PanelContainer.new()
		cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var caixa := TemaEvento.estilo(TemaEvento.PAINEL, Color(chave[2], 0.25), 1, 8, 10.0)
		caixa.content_margin_left = 16
		caixa.border_width_bottom = 3
		caixa.border_color = Color(chave[2], 0.6)
		cartao.add_theme_stylebox_override("panel", caixa)
		# Número e legenda lado a lado: faixa baixa, sobra altura para os cards
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 12)
		cartao.add_child(linha)
		var valor := TemaEvento.rotulo("0", 28, chave[2], true, true)
		linha.add_child(valor)
		linha.add_child(TemaEvento.rotulo(chave[1], 13, TemaEvento.TEXTO_SUAVE, true))
		_indicadores[chave[0]] = valor
		faixa.add_child(cartao)
	return faixa

func _atualizar_cabecalho():
	var ips := Rede.ips_locais()
	var ligado := int(Rede.tempo_ligado())
	var jogando := 0
	var correndo := 0
	for d in Dispositivos.lista.values():
		if d.liberado:
			jogando += 1
		if d.estado == "correndo":
			correndo += 1
	_ip.text = "%s : %d" % [", ".join(ips) if not ips.is_empty() else "sem rede local", Rede.PORTA]
	_contadores.text = "UDP enviados %d · pacotes recebidos %d · versão %s" % [Rede.anuncios_enviados, Rede.pacotes_recebidos, Rede.VERSAO]
	_indicadores.oculos.text = str(Dispositivos.lista.size())
	_indicadores.jogando.text = str(jogando)
	_indicadores.correndo.text = str(correndo)
	_indicadores.espectadores.text = str(Rede.espectadores.size())
	_indicadores.ligado.text = "%02d:%02d:%02d" % [ligado / 3600, (ligado / 60) % 60, ligado % 60]
	var ativo := Rede.modo == Rede.Modo.SERVIDOR
	TemaEvento.mudar_pilula(_anuncio, "●  ANUNCIANDO" if ativo else "●  PARADO", TemaEvento.QUENTE if ativo else TemaEvento.ALERTA)

# --- Óculos -------------------------------------------------------------------------

func _montar_cartoes() -> Control:
	var coluna := VBoxContainer.new()
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(TemaEvento.rotulo("Liberar coloca o jogador no lobby (e no telão). Voltar para idle encerra a sessão; correndo e menu vêm do Quest.", 13, TemaEvento.TEXTO_SUAVE))
	var rolagem := ScrollContainer.new()
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	coluna.add_child(rolagem)
	var conteudo := VBoxContainer.new()
	conteudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(conteudo)
	_vazio = TemaEvento.rotulo("Nenhum óculos conectado ainda. Ligue os Quests na mesma rede: eles acham o servidor sozinhos.", 15, Color(TemaEvento.TEXTO_SUAVE, 0.8))
	_vazio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vazio.custom_minimum_size.y = 120
	conteudo.add_child(_vazio)
	_cartoes_box = HFlowContainer.new()
	_cartoes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cartoes_box.add_theme_constant_override("h_separation", 12)
	_cartoes_box.add_theme_constant_override("v_separation", 12)
	conteudo.add_child(_cartoes_box)
	return coluna

func _sincronizar_cartoes():
	for peer in _cartoes.keys():
		if not Dispositivos.lista.has(peer):
			_cartoes[peer].queue_free()
			_cartoes.erase(peer)
	for peer in Dispositivos.lista:
		if not _cartoes.has(peer):
			var cartao := CartaoDispositivo.new(peer)
			cartao.custom_minimum_size.x = LARGURA_CARTAO
			cartao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cartao.pediu_apelido.connect(_pedir_apelido)
			_cartoes_box.add_child(cartao)
			_cartoes[peer] = cartao
		_cartoes[peer].atualizar()
	_vazio.visible = _cartoes.is_empty()

func _pedir_apelido(peer: int):
	_peer_apelido = peer
	_campo_apelido.text = Dispositivos.obter(peer).get("apelido", "")
	_dialogo_apelido.popup_centered(Vector2i(380, 130))
	_campo_apelido.grab_focus()
	_campo_apelido.select_all()

# --- Ranking ------------------------------------------------------------------------

func _montar_ranking() -> Control:
	var coluna := VBoxContainer.new()
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_theme_constant_override("separation", 8)
	_ranking = Tree.new()
	_ranking.columns = 6
	_ranking.hide_root = true
	_ranking.column_titles_visible = true
	_ranking.select_mode = Tree.SELECT_ROW
	_ranking.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titulos := ["#", "JOGADOR", "TEMPO", "PISTA", "DATA", "ÓCULOS"]
	for i in titulos.size():
		_ranking.set_column_title(i, titulos[i])
		_ranking.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
		_ranking.set_column_expand(i, i in [1, 3, 4])
	_ranking.set_column_custom_minimum_width(0, 52)
	_ranking.set_column_custom_minimum_width(2, 110)
	coluna.add_child(_ranking)
	var botoes := HBoxContainer.new()
	botoes.add_theme_constant_override("separation", 8)
	var exportar := Button.new()
	exportar.text = "Exportar CSV (todas as tentativas)"
	exportar.pressed.connect(_exportar)
	botoes.add_child(exportar)
	var limpar := Button.new()
	limpar.text = "Limpar ranking"
	limpar.theme_type_variation = "BotaoPerigo"
	limpar.pressed.connect(func(): _confirma_limpar.popup_centered())
	botoes.add_child(limpar)
	coluna.add_child(botoes)
	return coluna

func _mostrar_ranking(top: Array):
	_ranking.clear()
	var raiz := _ranking.create_item()
	var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
	var numeros := PainelHolografico.fonte(true)
	for i in top.size():
		var r: Dictionary = top[i]
		var item := _ranking.create_item(raiz)
		var valores := ["%dº" % (i + 1), str(r.nome), Ranking.formatar_tempo(float(r.tempo)), str(r.get("pista", "")),
			_data_curta(str(r.get("data", ""))), str(r.get("oculos", ""))]
		for c in valores.size():
			item.set_text(c, valores[c])
			item.set_custom_color(c, TemaEvento.TEXTO_SUAVE if c >= 3 else TemaEvento.TEXTO)
			if i % 2 == 1:
				item.set_custom_bg_color(c, Color(1, 1, 1, 0.025))
		item.set_custom_font(0, numeros)
		item.set_custom_font(2, numeros)
		item.set_custom_color(2, TemaEvento.CIANO)
		if i < 3:
			item.set_custom_color(0, medalhas[i])
			item.set_custom_color(1, medalhas[i])
		if _chave(r) == _destaque:
			for c in valores.size():
				item.set_custom_bg_color(c, Color(TemaEvento.QUENTE, 0.3))

## "2026-10-26T10:21:00" -> "26/10 10:21"
static func _data_curta(data: String) -> String:
	var partes := data.split("T")
	var dia := partes[0].split("-")
	if dia.size() != 3:
		return data
	return "%s/%s %s" % [dia[2], dia[1], partes[1].left(5) if partes.size() > 1 else ""]

func _novo_tempo(registro: Dictionary):
	_destaque = _chave(registro)
	_destaque_ate = Time.get_ticks_msec() / 1000.0 + TEMPO_DESTAQUE

func _chave(r: Dictionary) -> String:
	return "%s|%s|%s" % [r.get("nome", ""), r.get("tempo", ""), r.get("data", "")]

func _exportar():
	var caminho := Ranking.exportar_csv()
	if caminho.is_empty():
		Rede.registrar_evento("erro", "Falha ao exportar o ranking")
	else:
		Rede.registrar_evento("servidor", "Ranking exportado: %s" % caminho)

func _limpar_ranking():
	var backup := Ranking.limpar()
	Rede.registrar_evento("servidor", "Ranking limpo (backup em %s)" % ProjectSettings.globalize_path(backup))

# --- Log ----------------------------------------------------------------------------

func _montar_log() -> Control:
	var coluna := VBoxContainer.new()
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_theme_constant_override("separation", 8)
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 10)
	_filtro = OptionButton.new()
	_filtro.add_item("todos")
	for tipo in CORES_EVENTO:
		_filtro.add_item(tipo)
	_filtro.item_selected.connect(func(_i: int): _reescrever_log())
	barra.add_child(_filtro)
	_pausar = CheckBox.new()
	_pausar.text = "Pausar rolagem"
	_pausar.toggled.connect(func(pausado: bool): _log.scroll_following = not pausado)
	barra.add_child(_pausar)
	coluna.add_child(barra)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(_log)
	return coluna

func _evento(registro: Dictionary):
	if _passa_filtro(registro):
		_escrever(registro)

func _passa_filtro(registro: Dictionary) -> bool:
	return _filtro.selected <= 0 or registro.tipo == _filtro.get_item_text(_filtro.selected)

func _reescrever_log():
	_log.clear()
	for registro in Rede.eventos:
		if _passa_filtro(registro):
			_escrever(registro)

## Hora apagada, tipo como etiqueta colorida e o texto
func _escrever(registro: Dictionary):
	var cor: String = CORES_EVENTO.get(registro.tipo, "#ffffff")
	_log.append_text("[color=#5d6884]%s[/color]  [bgcolor=%s26][color=%s] %-11s [/color][/bgcolor]  %s\n" % [
		registro.hora, cor, cor, registro.tipo, str(registro.texto).replace("[", "[lb]")])

# --- Diálogos -----------------------------------------------------------------------

func _montar_dialogos():
	_dialogo_apelido = ConfirmationDialog.new()
	_dialogo_apelido.title = "Apelido do óculos"
	_campo_apelido = LineEdit.new()
	_campo_apelido.placeholder_text = "Óculos 1"
	_dialogo_apelido.add_child(_campo_apelido)
	_dialogo_apelido.register_text_enter(_campo_apelido)
	_dialogo_apelido.confirmed.connect(func(): Rede.renomear_oculos(_peer_apelido, _campo_apelido.text))
	add_child(_dialogo_apelido)
	_confirma_limpar = ConfirmationDialog.new()
	_confirma_limpar.title = "Limpar ranking"
	_confirma_limpar.dialog_text = "Apagar TODAS as tentativas do ranking?\nUma cópia de segurança é salva antes."
	_confirma_limpar.confirmed.connect(_limpar_ranking)
	add_child(_confirma_limpar)

func _secao(titulo: String, conteudo: Control) -> PanelContainer:
	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", TemaEvento.estilo(TemaEvento.PAINEL, Color(TemaEvento.CIANO, 0.18), 1, 10, 14.0))
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 10)
	var marca := ColorRect.new()
	marca.color = TemaEvento.CIANO
	marca.custom_minimum_size = Vector2(4, 18)
	topo.add_child(marca)
	topo.add_child(TemaEvento.rotulo(titulo, 15, TemaEvento.CIANO, true))
	coluna.add_child(topo)
	conteudo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(conteudo)
	painel.add_child(coluna)
	return painel


## Card de cada Quest: apelido e estado no topo, o jogador e a telemetria ao vivo do
## carro (mapa, volta, posição, velocidade, vida), bateria/ping/conexão, e as ações
## sempre visíveis embaixo. A borda esquerda tem a cor do estado.
class CartaoDispositivo extends PanelContainer:

	signal pediu_apelido(peer: int)

	var peer := 0
	var _caixa: StyleBoxFlat
	var _titulo: Label
	var _peer: Label
	var _estado: PanelContainer
	var _jogador: Label
	var _aparelho: Label
	var _ao_vivo: HBoxContainer
	var _corrida: Label
	var _vida: HBoxContainer
	var _bateria: ProgressBar
	var _bateria_texto: Label
	var _ping: Label
	var _conexao: Label
	var _nome: LineEdit
	var _liberar: Button
	var _encerrar: Button
	var _liberado_antes := false

	func _init(peer_: int):
		peer = peer_
		_caixa = TemaEvento.estilo(TemaEvento.CARTAO, TemaEvento.CIANO, 0, 8, 14.0)
		_caixa.border_width_left = 4
		add_theme_stylebox_override("panel", _caixa)
		var coluna := VBoxContainer.new()
		coluna.add_theme_constant_override("separation", 8)
		add_child(coluna)

		var topo := HBoxContainer.new()
		topo.add_theme_constant_override("separation", 10)
		coluna.add_child(topo)
		_titulo = TemaEvento.rotulo("", 19, Color.WHITE, true)
		topo.add_child(_titulo)
		_peer = TemaEvento.rotulo("", 13, TemaEvento.TEXTO_SUAVE, false, true)
		topo.add_child(_peer)
		var vao := Control.new()
		vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		topo.add_child(vao)
		_estado = TemaEvento.pilula("", TemaEvento.CIANO)
		_estado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		topo.add_child(_estado)

		var quem := HBoxContainer.new()
		quem.add_theme_constant_override("separation", 10)
		coluna.add_child(quem)
		_jogador = TemaEvento.rotulo("", 16, TemaEvento.TEXTO, true)
		_jogador.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quem.add_child(_jogador)
		_aparelho = TemaEvento.rotulo("", 12, TemaEvento.TEXTO_SUAVE)
		_aparelho.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_aparelho.custom_minimum_size.x = 150
		_aparelho.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		quem.add_child(_aparelho)

		# Ao vivo (só com telemetria recente): onde está, volta/posição, km/h e vida
		_ao_vivo = HBoxContainer.new()
		_ao_vivo.add_theme_constant_override("separation", 12)
		coluna.add_child(_ao_vivo)
		_corrida = TemaEvento.rotulo("", 14, TemaEvento.CIANO, true, true)
		_corrida.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_ao_vivo.add_child(_corrida)
		_vida = HBoxContainer.new()
		_vida.add_theme_constant_override("separation", 3)
		_ao_vivo.add_child(_vida)

		var metricas := HBoxContainer.new()
		metricas.add_theme_constant_override("separation", 16)
		coluna.add_child(metricas)
		var bateria := HBoxContainer.new()
		bateria.add_theme_constant_override("separation", 6)
		bateria.add_child(TemaEvento.rotulo("BAT", 12, TemaEvento.TEXTO_SUAVE, true))
		_bateria = TemaEvento.barra(70, 8)
		bateria.add_child(_bateria)
		_bateria_texto = TemaEvento.rotulo("", 13, TemaEvento.TEXTO, false, true)
		bateria.add_child(_bateria_texto)
		metricas.add_child(bateria)
		_ping = TemaEvento.rotulo("", 13, TemaEvento.TEXTO, false, true)
		metricas.add_child(_ping)
		_conexao = TemaEvento.rotulo("", 13, TemaEvento.TEXTO_SUAVE, false, true)
		metricas.add_child(_conexao)

		var acoes := HBoxContainer.new()
		acoes.add_theme_constant_override("separation", 6)
		coluna.add_child(acoes)
		_nome = LineEdit.new()
		_nome.placeholder_text = "Nome do jogador"
		_nome.custom_minimum_size.x = 140
		_nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_nome.text_submitted.connect(func(_t: String): _liberar_jogador())
		acoes.add_child(_nome)
		_liberar = _botao(acoes, "Liberar", _liberar_jogador)
		_liberar.theme_type_variation = "BotaoPrimario"
		_encerrar = _botao(acoes, "Idle", func(): Rede.encerrar(peer))
		_encerrar.tooltip_text = "Encerra a sessão e devolve o jogador à espera no Quest"
		var apelido := _botao(acoes, "Apelido", func(): pediu_apelido.emit(peer))
		apelido.tooltip_text = "Renomear este óculos"
		var desconectar := _botao(acoes, "✕", func(): Rede.desconectar(peer))
		desconectar.theme_type_variation = "BotaoPerigo"
		desconectar.tooltip_text = "Desconectar este óculos"

	func _botao(pai: Control, texto: String, acao: Callable) -> Button:
		var b := Button.new()
		b.text = texto
		b.pressed.connect(acao)
		pai.add_child(b)
		return b

	func _liberar_jogador():
		if _nome.text.strip_edges().is_empty():
			_nome.grab_focus()
			return
		Rede.liberar(peer, _nome.text)
		_nome.release_focus()

	func atualizar():
		var d := Dispositivos.obter(peer)
		if d.is_empty():
			return
		var agora := Time.get_ticks_msec() / 1000.0
		var conectado := int(agora - float(d.conectado_em))
		var silencio := agora - float(d.ultimo_heartbeat)
		var ping := Rede.ping(peer)
		var cor_estado: Color = TemaEvento.CORES_ESTADO.get(d.estado, Color.WHITE)
		_caixa.border_color = cor_estado
		_titulo.text = d.apelido if d.apelido != "" else "Registrando…"
		_peer.text = "#%d" % peer
		TemaEvento.mudar_pilula(_estado, d.estado.to_upper(), cor_estado)
		_jogador.text = d.jogador if d.liberado else "Aguardando liberação"
		_jogador.add_theme_color_override("font_color", Color.WHITE if d.liberado else TemaEvento.TEXTO_SUAVE)
		_aparelho.text = "%s · %s" % [d.ip, d.aparelho if d.aparelho != "" else "registrando"]
		_mostrar_telemetria(Dispositivos.telemetria(d))

		var bateria := int(d.bateria)
		_bateria.value = maxi(bateria, 0)
		TemaEvento.pintar_barra(_bateria, TemaEvento.cor_nivel(bateria / 100.0))
		_bateria_texto.text = "%d%%" % bateria if bateria >= 0 else "—"
		_ping.text = "PING %s" % ("%d ms" % ping if ping >= 0 else "—")
		_ping.add_theme_color_override("font_color", TemaEvento.TEXTO_SUAVE if ping < 0 else (TemaEvento.VERDE if ping < 60 else (TemaEvento.QUENTE if ping < 150 else TemaEvento.ALERTA)))
		_conexao.text = "ON %02d:%02d · HB %.0f s" % [conectado / 60, conectado % 60, silencio]
		var alerta := Dispositivos.sem_resposta(d)
		_conexao.add_theme_color_override("font_color", TemaEvento.ALERTA if alerta else TemaEvento.TEXTO_SUAVE)
		_caixa.bg_color = Color(0.16, 0.05, 0.07) if alerta else TemaEvento.CARTAO

		_liberar.text = "Renomear" if d.liberado else "Liberar"
		_encerrar.disabled = not d.liberado and d.estado == "idle"
		# Liberado: o campo mostra o nome atual, a não ser que o operador esteja editando
		if d.liberado and not _nome.has_focus() and _nome.text != d.jogador:
			_nome.text = d.jogador
		elif _liberado_antes and not d.liberado:
			# Sessão encerrada: campo limpo para a próxima pessoa
			_nome.text = ""
		_liberado_antes = d.liberado

	func _mostrar_telemetria(t: Dictionary):
		_ao_vivo.visible = not t.is_empty()
		if t.is_empty():
			return
		var partes: Array[String] = []
		if t.get("explodindo", false):
			partes.append("EXPLODIU")
		elif t.get("na_esfera", false):
			partes.append("NA ESFERA")
		elif t.has("sobrecarga"):
			partes.append("SOBRECARGA %ds" % ceili(float(t.sobrecarga)))
		var mapa := str(t.get("mapa", ""))
		if mapa != "":
			partes.append(mapa.to_upper())
			if int(t.get("volta", 0)) > 0:
				partes.append("V%d/%d · %dº/%d" % [mini(int(t.volta), int(t.get("voltas", 3))), int(t.get("voltas", 3)), int(t.get("posicao", 0)), int(t.get("total", 0))])
		else:
			partes.append("MUNDO NEON")
		partes.append("%d km/h" % roundi(float(t.get("vel", 0.0))))
		_corrida.text = "  ·  ".join(partes)
		var vida := int(t.get("vida", 0))
		var vida_max := int(t.get("vida_max", 8))
		if _vida.get_child_count() != vida_max:
			for filho in _vida.get_children():
				_vida.remove_child(filho)
				filho.queue_free()
			for i in vida_max:
				var segmento := ColorRect.new()
				segmento.custom_minimum_size = Vector2(9, 12)
				_vida.add_child(segmento)
		var cor := TemaEvento.cor_nivel(float(vida) / maxf(vida_max, 1))
		for i in _vida.get_child_count():
			(_vida.get_child(i) as ColorRect).color = cor if i < vida else Color(1, 1, 1, 0.1)
