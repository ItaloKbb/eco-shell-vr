extends Control
## Painel do servidor do evento (só 2D, nada de 3D): cabeçalho com IP/porta/tempo
## ligado/anúncio, tabela dos óculos com as ações do operador (liberar com o nome do
## jogador, encerrar sessão, apelido, desconectar), ranking geral e log de eventos.
## Toda a lógica fica em Rede, Dispositivos e Ranking; aqui só se mostra e se aciona.

const COR_CIANO := Color(0.35, 0.8, 1.0)
const COR_QUENTE := Color(1.0, 0.62, 0.25)
const COR_ALERTA := Color(1.0, 0.3, 0.3)
const CORES_ESTADO := {
	"idle": Color(0.6, 0.6, 0.65),
	"lobby": Color(0.35, 0.8, 1.0),
	"correndo": Color(0.3, 1.0, 0.45),
	"menu": Color(1.0, 0.85, 0.3),
}
const CORES_EVENTO := {
	"conexao": "#5ccfff", "estado": "#9aa0b4", "sessao": "#ffd24a", "tempo": "#4dff7a",
	"dispositivo": "#c58cff", "erro": "#ff5050", "servidor": "#ffffff",
}
## Quanto tempo o tempo novo fica destacado no ranking (s)
const TEMPO_DESTAQUE := 8.0

var _info: Label
var _anuncio: Label
var _contadores: Label
var _linhas_box: VBoxContainer
var _linhas := {}
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
	var fundo := ColorRect.new()
	fundo.color = Color(0.02, 0.03, 0.07)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 14)
	add_child(margem)
	var raiz := VBoxContainer.new()
	raiz.add_theme_constant_override("separation", 10)
	margem.add_child(raiz)

	raiz.add_child(_montar_cabecalho())
	var dispositivos := _secao("ÓCULOS CONECTADOS", _montar_dispositivos())
	dispositivos.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(dispositivos)
	var baixo := HBoxContainer.new()
	baixo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	baixo.add_theme_constant_override("separation", 10)
	raiz.add_child(baixo)
	var ranking := _secao("RANKING GERAL · MELHOR TEMPO DE CADA JOGADOR", _montar_ranking())
	ranking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	baixo.add_child(ranking)
	var log_eventos := _secao("EVENTOS", _montar_log())
	log_eventos.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_eventos.size_flags_stretch_ratio = 1.3
	baixo.add_child(log_eventos)
	_montar_dialogos()

	Dispositivos.mudou.connect(_sincronizar_linhas)
	Ranking.ranking_mudou.connect(_mostrar_ranking)
	Ranking.novo_tempo.connect(_novo_tempo)
	Rede.evento.connect(_evento)
	_sincronizar_linhas()
	_mostrar_ranking(Ranking.top)
	_reescrever_log()
	_atualizar_cabecalho()

func _process(delta: float):
	_tempo_refresco -= delta
	if _tempo_refresco > 0.0:
		return
	_tempo_refresco = 0.5
	_atualizar_cabecalho()
	for linha in _linhas.values():
		linha.atualizar()
	if _destaque != "" and Time.get_ticks_msec() / 1000.0 > _destaque_ate:
		_destaque = ""
		_mostrar_ranking(Ranking.top)

# --- Cabeçalho ----------------------------------------------------------------------

func _montar_cabecalho() -> Control:
	var caixa := HBoxContainer.new()
	caixa.add_theme_constant_override("separation", 28)
	caixa.add_child(_rotulo("ECO SHELL VR · SERVIDOR", 22, COR_CIANO))
	_info = _rotulo("", 16, Color.WHITE)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caixa.add_child(_info)
	_contadores = _rotulo("", 14, Color(0.7, 0.75, 0.85))
	caixa.add_child(_contadores)
	_anuncio = _rotulo("● ANUNCIANDO", 16, COR_QUENTE)
	caixa.add_child(_anuncio)
	return caixa

func _atualizar_cabecalho():
	var ips := Rede.ips_locais()
	var ligado := int(Rede.tempo_ligado())
	var jogadores := 0
	for d in Dispositivos.lista.values():
		if d.liberado:
			jogadores += 1
	_info.text = "IP %s   ·   Porta %d   ·   Ligado %02d:%02d:%02d   ·   %d óculos, %d jogando" % [
		", ".join(ips) if not ips.is_empty() else "sem rede local", Rede.PORTA,
		ligado / 3600, (ligado / 60) % 60, ligado % 60, Dispositivos.lista.size(), jogadores]
	_contadores.text = "UDP enviados %d · pacotes recebidos %d" % [Rede.anuncios_enviados, Rede.pacotes_recebidos]
	var ativo := Rede.modo == Rede.Modo.SERVIDOR
	_anuncio.text = "● ANUNCIANDO" if ativo else "● PARADO"
	_anuncio.modulate.a = (0.4 + 0.6 * float(Rede.anuncios_enviados % 2)) if ativo else 1.0
	_anuncio.add_theme_color_override("font_color", COR_QUENTE if ativo else COR_ALERTA)

# --- Dispositivos -------------------------------------------------------------------

func _montar_dispositivos() -> Control:
	var coluna := VBoxContainer.new()
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titulo := HBoxContainer.new()
	for c in LinhaDispositivo.COLUNAS:
		var r := _rotulo(c[0], 13, COR_CIANO)
		r.custom_minimum_size.x = c[1]
		titulo.add_child(r)
	var acoes := _rotulo("NOME DO JOGADOR / AÇÕES", 13, COR_CIANO)
	titulo.add_child(acoes)
	coluna.add_child(titulo)
	var rolagem := ScrollContainer.new()
	rolagem.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(rolagem)
	_linhas_box = VBoxContainer.new()
	_linhas_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rolagem.add_child(_linhas_box)
	return coluna

func _sincronizar_linhas():
	for peer in _linhas.keys():
		if not Dispositivos.lista.has(peer):
			_linhas[peer].queue_free()
			_linhas.erase(peer)
	for peer in Dispositivos.lista:
		if not _linhas.has(peer):
			var linha := LinhaDispositivo.new(peer)
			linha.pediu_apelido.connect(_pedir_apelido)
			_linhas_box.add_child(linha)
			_linhas[peer] = linha
		_linhas[peer].atualizar()

func _pedir_apelido(peer: int):
	_peer_apelido = peer
	_campo_apelido.text = Dispositivos.obter(peer).get("apelido", "")
	_dialogo_apelido.popup_centered(Vector2i(360, 120))
	_campo_apelido.grab_focus()
	_campo_apelido.select_all()

# --- Ranking ------------------------------------------------------------------------

func _montar_ranking() -> Control:
	var coluna := VBoxContainer.new()
	coluna.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ranking = Tree.new()
	_ranking.columns = 6
	_ranking.hide_root = true
	_ranking.column_titles_visible = true
	_ranking.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var titulos := ["#", "JOGADOR", "TEMPO", "PISTA", "DATA", "ÓCULOS"]
	for i in titulos.size():
		_ranking.set_column_title(i, titulos[i])
		_ranking.set_column_expand(i, i in [1, 3, 4])
	_ranking.set_column_custom_minimum_width(0, 40)
	coluna.add_child(_ranking)
	var botoes := HBoxContainer.new()
	var exportar := Button.new()
	exportar.text = "Exportar CSV (todas as tentativas)"
	exportar.pressed.connect(_exportar)
	botoes.add_child(exportar)
	var limpar := Button.new()
	limpar.text = "Limpar ranking"
	limpar.pressed.connect(func(): _confirma_limpar.popup_centered())
	botoes.add_child(limpar)
	coluna.add_child(botoes)
	return coluna

func _mostrar_ranking(top: Array):
	_ranking.clear()
	var raiz := _ranking.create_item()
	for i in top.size():
		var r: Dictionary = top[i]
		var item := _ranking.create_item(raiz)
		var data := str(r.get("data", "")).replace("T", " ")
		var valores := ["%dº" % (i + 1), str(r.nome), Ranking.formatar_tempo(float(r.tempo)), str(r.get("pista", "")),
			data.left(16), str(r.get("oculos", ""))]
		for c in valores.size():
			item.set_text(c, valores[c])
		if _chave(r) == _destaque:
			for c in valores.size():
				item.set_custom_bg_color(c, Color(COR_QUENTE, 0.35))

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
	var barra := HBoxContainer.new()
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

func _escrever(registro: Dictionary):
	var cor: String = CORES_EVENTO.get(registro.tipo, "#ffffff")
	_log.append_text("[color=#6c7590]%s[/color] [color=%s]%-11s[/color] %s\n" % [registro.hora, cor, registro.tipo,
		str(registro.texto).replace("[", "[lb]")])

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
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = Color(0.03, 0.06, 0.12)
	caixa.border_color = Color(COR_CIANO, 0.5)
	caixa.set_border_width_all(1)
	caixa.set_corner_radius_all(6)
	caixa.set_content_margin_all(10)
	painel.add_theme_stylebox_override("panel", caixa)
	var coluna := VBoxContainer.new()
	coluna.add_child(_rotulo(titulo, 15, COR_CIANO))
	conteudo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(conteudo)
	painel.add_child(coluna)
	return painel

static func _rotulo(texto: String, tamanho: int, cor: Color) -> Label:
	var r := Label.new()
	r.text = texto
	r.add_theme_font_size_override("font_size", tamanho)
	r.add_theme_color_override("font_color", cor)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return r


## Uma linha da tabela de óculos: dados do peer e as ações do operador
class LinhaDispositivo extends HBoxContainer:
	## [título, largura]; a ordem é a dos rótulos em atualizar()
	const COLUNAS := [["ÓCULOS", 110], ["PEER", 90], ["IP", 120], ["APARELHO", 170], ["JOGADOR", 130],
		["ESTADO", 85], ["PING", 60], ["BATERIA", 70], ["CONECTADO", 85], ["HEARTBEAT", 85]]

	signal pediu_apelido(peer: int)

	var peer := 0
	var _rotulos: Array[Label] = []
	var _nome: LineEdit
	var _liberar: Button
	var _encerrar: Button
	var _liberado_antes := false

	func _init(peer_: int):
		peer = peer_
		for c in COLUNAS:
			var r := Label.new()
			r.custom_minimum_size.x = c[1]
			r.clip_text = true
			r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			add_child(r)
			_rotulos.append(r)
		_nome = LineEdit.new()
		_nome.placeholder_text = "nome do jogador"
		_nome.custom_minimum_size.x = 150
		_nome.text_submitted.connect(func(_t: String): _liberar_jogador())
		add_child(_nome)
		_liberar = _botao("Liberar", _liberar_jogador)
		_encerrar = _botao("Encerrar sessão", func(): Rede.encerrar(peer))
		_botao("Apelido", func(): pediu_apelido.emit(peer))
		_botao("Desconectar", func(): Rede.desconectar(peer))

	func _botao(texto: String, acao: Callable) -> Button:
		var b := Button.new()
		b.text = texto
		b.pressed.connect(acao)
		add_child(b)
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
		var valores := [
			d.apelido, str(peer), d.ip, d.aparelho if d.aparelho != "" else "(registrando)",
			d.jogador if d.liberado else "—", d.estado,
			"%d ms" % ping if ping >= 0 else "—",
			"%d%%" % d.bateria if int(d.bateria) >= 0 else "—",
			"%02d:%02d" % [conectado / 60, conectado % 60],
			"%.0f s" % silencio,
		]
		for i in valores.size():
			_rotulos[i].text = str(valores[i])
		_rotulos[5].add_theme_color_override("font_color", CORES_ESTADO.get(d.estado, Color.WHITE))
		var alerta := Dispositivos.sem_resposta(d)
		_rotulos[9].add_theme_color_override("font_color", COR_ALERTA if alerta else Color.WHITE)
		modulate = Color(1.0, 0.75, 0.75) if alerta else Color.WHITE
		_liberar.text = "Renomear" if d.liberado else "Liberar"
		_encerrar.disabled = not d.liberado
		# Liberado: o campo mostra o nome atual, a não ser que o operador esteja editando
		if d.liberado and not _nome.has_focus() and _nome.text != d.jogador:
			_nome.text = d.jogador
		elif _liberado_antes and not d.liberado:
			# Sessão encerrada: campo limpo para a próxima pessoa
			_nome.text = ""
		_liberado_antes = d.liberado
