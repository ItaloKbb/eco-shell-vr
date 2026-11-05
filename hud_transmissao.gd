class_name HudTransmissao
extends CanvasLayer
## HUD da transmissão do telão (modo espectador), no estilo das transmissões de F1:
## - canto superior esquerdo: a marca (SENAI + ECO SHELL VR), o selo AO VIVO e o ângulo;
## - canto superior direito: a torre de classificação (TorreClassificacao), na corrida;
## - canto inferior esquerdo: o minimapa com os carros (MapaHud), na corrida;
## - embaixo: terço inferior com o piloto em foco e, à direita, a velocidade;
## - abertura: vinheta "SENAI APRESENTA · ECO SHELL GRAND PRIX", faixas de cinema, a
##   cartela do circuito e as luzes de largada (LuzesLargada);
## - fim: título do pódio e o placar "RANKING DO EVENTO" em tela cheia;
## - espera: painel central sem ninguém jogando, faixa no alto com gente no lobby.
## Tudo no TemaEvento. Medidas pensadas para 1920x1080 (o telão abre em tela cheia).

const LARGURA_TERCO := 760.0
const ALTURA_FAIXA := 92.0
const MARGEM := 28.0
const LADO_MAPA := 300.0
## Azul institucional do SENAI (marca em texto)
const AZUL_SENAI := Color("1e6ad2")

var torre: TorreClassificacao
var minimapa: MapaHud
var luzes: LuzesLargada

var _raiz: Control
var _ao_vivo: PanelContainer
var _angulo: Label
var _terco: PanelContainer
var _pos_terco: Label
var _estrela_terco: Label
var _nome: Label
var _local: Label
var _situacao: PanelContainer
var _vida: HBoxContainer
var _vida_texto: Label
var _painel_vel: PanelContainer
var _velocidade: Label
var _progresso: ColorRect
var _painel_mapa: PanelContainer
var _espera: PanelContainer
var _espera_titulo: Label
var _espera_ranking: VBoxContainer
var _faixa_espera: PanelContainer
var _carregando: Label
var _fade: ColorRect
var _varredura: ColorRect
var _corte: Tween
var _vida_max := -1
var _faixa_cima: ColorRect
var _faixa_baixo: ColorRect
var _cartela: PanelContainer
var _cartela_titulo: Label
var _cartela_info: Label
var _cartela_grid: Label
var _cartela_estado: PanelContainer
var _em_abertura := false
var _anima_abertura: Tween
var _vinheta: Control
var _vinheta_pista: Label
var _vinheta_formato: Label
var _anima_vinheta: Tween
var _podio: PanelContainer
var _podio_titulo: Label
var _podio_vencedor: Label
var _placar: Control
var _placar_linhas: VBoxContainer
var _em_corrida := false

func _init():
	layer = 10
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.theme = TemaEvento.criar()
	add_child(_raiz)
	# Faixas de cinema da abertura: por baixo do resto
	_faixa_cima = _faixa(true)
	_faixa_baixo = _faixa(false)
	_montar_marca()
	_montar_torre_e_mapa()
	_montar_terco()
	_montar_cartela()
	_montar_espera()
	_montar_podio()
	_montar_placar()
	luzes = LuzesLargada.new()
	luzes.set_anchors_preset(Control.PRESET_CENTER_TOP)
	luzes.position = Vector2(-LuzesLargada.TAMANHO.x * 0.5, 120.0)
	_raiz.add_child(luzes)
	_montar_vinheta()
	# Corte: tela preta que revela, e uma faixa ciano varrendo por cima (wipe)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_fade)
	_varredura = ColorRect.new()
	_varredura.color = Color(TemaEvento.CIANO, 0.85)
	_varredura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_varredura.size = Vector2(160.0, 3000.0)
	_varredura.rotation = deg_to_rad(12.0)
	_varredura.visible = false
	_raiz.add_child(_varredura)
	_carregando = TemaEvento.rotulo("PREPARANDO TRANSMISSÃO", 22, TemaEvento.CIANO, true)
	_carregando.set_anchors_preset(Control.PRESET_CENTER)
	_carregando.offset_left = -600
	_carregando.offset_right = 600
	_carregando.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_raiz.add_child(_carregando)
	_terco.visible = false
	_painel_vel.visible = false
	_progresso.visible = false
	mostrar_ranking()

# --- Montagem -----------------------------------------------------------------------

func _montar_marca():
	var topo := HBoxContainer.new()
	topo.set_anchors_preset(Control.PRESET_TOP_LEFT)
	topo.position = Vector2(MARGEM, 22.0)
	topo.add_theme_constant_override("separation", 14)
	_raiz.add_child(topo)
	topo.add_child(_marca_senai(26))
	var eco := TemaEvento.rotulo("ECO SHELL VR", 24, Color.WHITE, true)
	topo.add_child(eco)
	_ao_vivo = TemaEvento.pilula("●  AO VIVO", TemaEvento.ALERTA, 16)
	_ao_vivo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	topo.add_child(_ao_vivo)
	_angulo = TemaEvento.rotulo("", 15, TemaEvento.TEXTO_SUAVE, true)
	topo.add_child(_angulo)

## "SENAI" em branco num bloco azul institucional
func _marca_senai(tamanho: int) -> PanelContainer:
	var bloco := PanelContainer.new()
	var caixa := TemaEvento.estilo(AZUL_SENAI, Color.TRANSPARENT, 0, 4, 0.0)
	caixa.content_margin_left = 14
	caixa.content_margin_right = 14
	caixa.content_margin_top = 2
	caixa.content_margin_bottom = 2
	bloco.add_theme_stylebox_override("panel", caixa)
	bloco.add_child(TemaEvento.rotulo("SENAI", tamanho, Color.WHITE, true))
	bloco.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bloco

func _montar_torre_e_mapa():
	torre = TorreClassificacao.new()
	torre.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	torre.position = Vector2(-MARGEM - TorreClassificacao.LARGURA, 22.0)
	torre.visible = false
	_raiz.add_child(torre)
	_painel_mapa = PanelContainer.new()
	_painel_mapa.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO, 10.0))
	_painel_mapa.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_painel_mapa.offset_left = MARGEM
	_painel_mapa.offset_right = MARGEM + LADO_MAPA + 20.0
	_painel_mapa.offset_bottom = -26.0
	_painel_mapa.offset_top = -26.0 - LADO_MAPA - 20.0
	_painel_mapa.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_painel_mapa.visible = false
	_raiz.add_child(_painel_mapa)
	minimapa = MapaHud.new()
	minimapa.custom_minimum_size = Vector2(LADO_MAPA, LADO_MAPA)
	minimapa.escala_traco = 1.5
	minimapa.rumo = Vector2.ZERO
	minimapa.cor = TemaEvento.CIANO
	minimapa.cor_piloto = Color.WHITE
	_painel_mapa.add_child(minimapa)

func _montar_terco():
	# Terço inferior: posição grande, nome, ★, onde está e a vida. Fica à direita do
	# minimapa; a velocidade num quadro no canto direito
	_terco = PanelContainer.new()
	_terco.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
	_terco.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_terco.offset_left = MARGEM + LADO_MAPA + 40.0
	_terco.offset_right = _terco.offset_left + LARGURA_TERCO
	_terco.offset_bottom = -26
	_terco.offset_top = -168
	_terco.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_raiz.add_child(_terco)
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 18)
	_terco.add_child(linha)
	_pos_terco = TemaEvento.rotulo("", 64, Color.WHITE, true, true)
	_pos_terco.custom_minimum_size.x = 96
	_pos_terco.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	linha.add_child(_pos_terco)
	var esquerda := VBoxContainer.new()
	esquerda.add_theme_constant_override("separation", 6)
	esquerda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	linha.add_child(esquerda)
	var cabeca := HBoxContainer.new()
	cabeca.add_theme_constant_override("separation", 12)
	esquerda.add_child(cabeca)
	_nome = TemaEvento.rotulo("", 44, Color.WHITE, true)
	cabeca.add_child(_nome)
	_estrela_terco = TemaEvento.rotulo("★", 34, TemaEvento.OURO, true)
	cabeca.add_child(_estrela_terco)
	_situacao = TemaEvento.pilula("", TemaEvento.CIANO, 15)
	_situacao.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cabeca.add_child(_situacao)
	_local = TemaEvento.rotulo("", 21, TemaEvento.CIANO, true)
	esquerda.add_child(_local)
	var linha_vida := HBoxContainer.new()
	linha_vida.add_theme_constant_override("separation", 12)
	esquerda.add_child(linha_vida)
	linha_vida.add_child(TemaEvento.rotulo("VIDA", 14, TemaEvento.TEXTO_SUAVE, true))
	_vida = HBoxContainer.new()
	_vida.add_theme_constant_override("separation", 4)
	linha_vida.add_child(_vida)
	_vida_texto = TemaEvento.rotulo("", 14, TemaEvento.TEXTO_SUAVE, false, true)
	linha_vida.add_child(_vida_texto)
	_painel_vel = PanelContainer.new()
	_painel_vel.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
	_painel_vel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_painel_vel.offset_left = -MARGEM - 270
	_painel_vel.offset_right = -MARGEM
	_painel_vel.offset_bottom = -26
	_painel_vel.offset_top = -168
	_painel_vel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_painel_vel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_raiz.add_child(_painel_vel)
	var direita := VBoxContainer.new()
	direita.alignment = BoxContainer.ALIGNMENT_CENTER
	_painel_vel.add_child(direita)
	_velocidade = TemaEvento.rotulo("0", 76, Color.WHITE, true, true)
	_velocidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	direita.add_child(_velocidade)
	var unidade := TemaEvento.rotulo("KM/H", 16, TemaEvento.CIANO, true)
	unidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	direita.add_child(unidade)
	# Tempo da tomada: filete embaixo do terço que enche até a próxima troca
	_progresso = ColorRect.new()
	_progresso.color = Color(TemaEvento.CIANO, 0.8)
	_progresso.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_progresso.offset_left = _terco.offset_left
	_progresso.offset_top = -27
	_progresso.offset_bottom = -24
	_raiz.add_child(_progresso)

func _montar_cartela():
	# Cartela da abertura: o circuito, o formato e quem está no grid, acima da faixa de baixo
	_cartela = PanelContainer.new()
	_cartela.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.QUENTE, 24.0))
	_cartela.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_cartela.offset_left = MARGEM
	_cartela.offset_bottom = -ALTURA_FAIXA - 24
	_cartela.offset_top = _cartela.offset_bottom - 200
	_cartela.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_raiz.add_child(_cartela)
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 4)
	_cartela.add_child(coluna)
	var cabeca := HBoxContainer.new()
	cabeca.add_theme_constant_override("separation", 14)
	coluna.add_child(cabeca)
	cabeca.add_child(TemaEvento.rotulo("ECO SHELL GRAND PRIX  ·  A CORRIDA VAI COMEÇAR", 16, TemaEvento.QUENTE, true))
	_cartela_estado = TemaEvento.pilula("", TemaEvento.QUENTE, 13)
	_cartela_estado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cabeca.add_child(_cartela_estado)
	_cartela_titulo = TemaEvento.rotulo("", 64, Color.WHITE, true)
	coluna.add_child(_cartela_titulo)
	_cartela_info = TemaEvento.rotulo("", 22, TemaEvento.CIANO, true)
	coluna.add_child(_cartela_info)
	_cartela_grid = TemaEvento.rotulo("", 16, TemaEvento.TEXTO_SUAVE, true)
	coluna.add_child(_cartela_grid)
	_cartela.visible = false

func _montar_espera():
	# Sem ninguém jogando: painel central com a chamada e o top 5 do evento
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(centro)
	_espera = PanelContainer.new()
	_espera.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO, 34.0))
	_espera.custom_minimum_size.x = 720
	centro.add_child(_espera)
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 14)
	_espera.add_child(coluna)
	var marca := HBoxContainer.new()
	marca.alignment = BoxContainer.ALIGNMENT_CENTER
	marca.add_theme_constant_override("separation", 12)
	marca.add_child(_marca_senai(22))
	marca.add_child(TemaEvento.rotulo("ECO SHELL GRAND PRIX", 22, TemaEvento.QUENTE, true))
	coluna.add_child(marca)
	_espera_titulo = TemaEvento.rotulo("", 34, Color.WHITE, true)
	_espera_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_espera_titulo)
	var chamada := TemaEvento.rotulo("COLOQUE O ÓCULOS E VENHA CORRER!", 18, TemaEvento.CIANO, true)
	chamada.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(chamada)
	_espera_ranking = VBoxContainer.new()
	_espera_ranking.add_theme_constant_override("separation", 6)
	coluna.add_child(_espera_ranking)
	# Com gente andando no lobby: só uma faixa no alto, centrada
	_faixa_espera = PanelContainer.new()
	_faixa_espera.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.QUENTE, 14.0))
	_faixa_espera.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_faixa_espera.offset_top = 86
	_faixa_espera.offset_left = -330
	_faixa_espera.offset_right = 330
	_faixa_espera.add_child(TemaEvento.rotulo("AGUARDANDO A PRÓXIMA CORRIDA  ·  ENTRE NUM PORTAL!", 18, Color.WHITE, true))
	(_faixa_espera.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_faixa_espera.visible = false
	_raiz.add_child(_faixa_espera)

func _montar_podio():
	_podio = PanelContainer.new()
	_podio.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.OURO, 22.0))
	_podio.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_podio.offset_top = 90
	_podio.offset_left = -420
	_podio.offset_right = 420
	_raiz.add_child(_podio)
	var coluna := VBoxContainer.new()
	coluna.alignment = BoxContainer.ALIGNMENT_CENTER
	_podio.add_child(coluna)
	_podio_titulo = TemaEvento.rotulo("", 46, Color.WHITE, true)
	_podio_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_podio_titulo)
	_podio_vencedor = TemaEvento.rotulo("", 24, TemaEvento.OURO, true)
	_podio_vencedor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_podio_vencedor)
	_podio.visible = false

func _montar_placar():
	# Ranking final do evento em tela cheia: fundo escurecido e o placar no meio
	_placar = Control.new()
	_placar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_placar)
	var fundo := ColorRect.new()
	fundo.color = Color(0.0, 0.01, 0.04, 0.82)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placar.add_child(fundo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_placar.add_child(centro)
	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO, 36.0))
	painel.custom_minimum_size.x = 980
	centro.add_child(painel)
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	painel.add_child(coluna)
	var marca := HBoxContainer.new()
	marca.add_theme_constant_override("separation", 12)
	marca.add_child(_marca_senai(24))
	marca.add_child(TemaEvento.rotulo("ECO SHELL GRAND PRIX", 24, TemaEvento.QUENTE, true))
	coluna.add_child(marca)
	coluna.add_child(TemaEvento.rotulo("RANKING DO EVENTO", 54, Color.WHITE, true))
	coluna.add_child(TemaEvento.rotulo("MELHORES TEMPOS DE CADA PILOTO", 18, TemaEvento.CIANO, true))
	_placar_linhas = VBoxContainer.new()
	_placar_linhas.add_theme_constant_override("separation", 4)
	coluna.add_child(_placar_linhas)
	_placar.visible = false

func _montar_vinheta():
	# Abertura: fundo escuro, duas faixas diagonais (ciano e âmbar) varrendo a tela e o
	# título no meio
	_vinheta = Control.new()
	_vinheta.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vinheta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_vinheta)
	var fundo := ColorRect.new()
	fundo.name = "Fundo"
	fundo.color = Color(0.0, 0.01, 0.04, 0.9)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vinheta.add_child(fundo)
	for i in 2:
		var faixa := ColorRect.new()
		faixa.name = "Faixa%d" % i
		faixa.color = Color(TemaEvento.CIANO if i == 0 else TemaEvento.QUENTE, 0.9)
		faixa.size = Vector2(5200.0, 120.0 if i == 0 else 60.0)
		faixa.rotation = deg_to_rad(-10.0)
		_vinheta.add_child(faixa)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vinheta.add_child(centro)
	var coluna := VBoxContainer.new()
	coluna.name = "Titulo"
	coluna.alignment = BoxContainer.ALIGNMENT_CENTER
	coluna.add_theme_constant_override("separation", 6)
	centro.add_child(coluna)
	var apresenta := HBoxContainer.new()
	apresenta.alignment = BoxContainer.ALIGNMENT_CENTER
	apresenta.add_theme_constant_override("separation", 12)
	apresenta.add_child(_marca_senai(28))
	apresenta.add_child(TemaEvento.rotulo("APRESENTA", 28, Color.WHITE, true))
	coluna.add_child(apresenta)
	var titulo := TemaEvento.rotulo("ECO SHELL GRAND PRIX", 96, Color.WHITE, true)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(titulo)
	_vinheta_pista = TemaEvento.rotulo("", 52, TemaEvento.QUENTE, true)
	_vinheta_pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_vinheta_pista)
	_vinheta_formato = TemaEvento.rotulo("", 22, TemaEvento.CIANO, true)
	_vinheta_formato.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_vinheta_formato)
	_vinheta.visible = false

func _faixa(cima: bool) -> ColorRect:
	var faixa := ColorRect.new()
	faixa.color = Color.BLACK
	faixa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	faixa.set_anchors_preset(Control.PRESET_TOP_WIDE if cima else Control.PRESET_BOTTOM_WIDE)
	faixa.offset_top = 0.0
	faixa.offset_bottom = 0.0
	faixa.visible = false
	_raiz.add_child(faixa)
	return faixa

func _caixa_vidro(cor: Color, margem := 20.0) -> StyleBoxFlat:
	var caixa := TemaEvento.estilo(Color(0.01, 0.025, 0.06, 0.84), Color(cor, 0.6), 0, 10, margem)
	caixa.border_width_left = 5
	return caixa

# --- Estado geral ---------------------------------------------------------------------

func carregando(texto: String):
	_carregando.visible = texto != ""
	_carregando.text = "PREPARANDO TRANSMISSÃO  ·  " + texto.to_upper()
	if texto == "":
		corte(0.6)

## Troca de tomada: escurece, revela e uma faixa ciano varre a tela (esconde o salto da câmera)
func corte(tempo: float):
	if _corte and _corte.is_valid():
		_corte.kill()
	_fade.color.a = 1.0
	var largura := _raiz.get_viewport_rect().size.x
	_varredura.visible = true
	_varredura.position = Vector2(-400.0, -600.0)
	_corte = create_tween().set_parallel()
	_corte.tween_property(_fade, "color:a", 0.0, tempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_corte.tween_property(_varredura, "position:x", largura + 400.0, maxf(tempo, 0.3)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_corte.chain().tween_callback(func(): _varredura.visible = false)

## `vazio`: ninguém para mostrar (painel central); `no_lobby`: só gente no mundo neon
## (faixa "aguardando a próxima corrida")
func atualizar_estado(conectado: bool, vazio: bool, no_lobby := false):
	var pulso := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.003))
	_ao_vivo.modulate.a = pulso if conectado else 0.35
	var tela_cheia := _placar.visible or _vinheta.visible
	_espera.visible = vazio and not _carregando.visible and not tela_cheia
	_faixa_espera.visible = no_lobby and not vazio and not _em_abertura and not tela_cheia and not _podio.visible
	var terco := not vazio and not _em_abertura and not _podio.visible and not tela_cheia
	_terco.visible = terco
	_painel_vel.visible = terco
	_progresso.visible = terco
	var corrida := _em_corrida and not _em_abertura and not tela_cheia and not _podio.visible
	torre.visible = corrida or (_podio.visible and torre.visible)
	_painel_mapa.visible = corrida
	if vazio:
		_espera_titulo.text = "AGUARDANDO PRÓXIMOS PILOTOS" if conectado else "PROCURANDO SERVIDOR DO EVENTO…"
		_angulo.text = ""

## Torre e minimapa ligados (a câmera está num mapa de corrida com corrida rolando)
func modo_corrida(ligado: bool):
	_em_corrida = ligado

# --- Abertura -------------------------------------------------------------------------

## Liga/desliga a abertura: faixas de cinema entram e a cartela desliza da esquerda
func abertura(ligada: bool):
	if ligada == _em_abertura:
		return
	_em_abertura = ligada
	if _anima_abertura and _anima_abertura.is_valid():
		_anima_abertura.kill()
	_anima_abertura = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var altura := ALTURA_FAIXA if ligada else 0.0
	var tempo := 0.7 if ligada else 0.35
	if ligada:
		for faixa in [_faixa_cima, _faixa_baixo]:
			faixa.visible = true
		_cartela.visible = true
		_cartela.modulate.a = 0.0
		_cartela.offset_left = -120.0
		_anima_abertura.tween_property(_cartela, "offset_left", MARGEM, 0.8).set_delay(0.3)
	_anima_abertura.tween_property(_faixa_cima, "offset_bottom", altura, tempo)
	_anima_abertura.tween_property(_faixa_baixo, "offset_top", -altura, tempo)
	_anima_abertura.tween_property(_cartela, "modulate:a", 1.0 if ligada else 0.0, 0.6 if ligada else 0.25).set_delay(0.3 if ligada else 0.0)
	if not ligada:
		_anima_abertura.chain().tween_callback(func():
			_faixa_cima.visible = false
			_faixa_baixo.visible = false
			_cartela.visible = false)

## Vinheta de abertura (~DURACAO_VINHETA s): faixas varrendo, "SENAI APRESENTA ·
## ECO SHELL GRAND PRIX", a pista e o formato; some sozinha
const DURACAO_VINHETA := 2.8
func vinheta(pista: String, formato: String):
	if _anima_vinheta and _anima_vinheta.is_valid():
		_anima_vinheta.kill()
	_vinheta_pista.text = pista.to_upper()
	_vinheta_formato.text = formato
	var tela := _raiz.get_viewport_rect().size
	_vinheta.visible = true
	_vinheta.modulate.a = 1.0
	var fundo: ColorRect = _vinheta.get_node("Fundo")
	fundo.color.a = 0.0
	var titulo: Control = _vinheta.find_child("Titulo", true, false)
	titulo.modulate.a = 0.0
	titulo.scale = Vector2(1.15, 1.15)
	titulo.pivot_offset = titulo.size * 0.5
	var t := create_tween().set_parallel()
	_anima_vinheta = t
	t.tween_property(fundo, "color:a", 0.9, 0.35)
	for i in 2:
		var faixa: ColorRect = _vinheta.get_node("Faixa%d" % i)
		faixa.position = Vector2(-5400.0, tela.y * (0.35 + 0.25 * i))
		t.tween_property(faixa, "position:x", tela.x + 200.0, 1.1).set_delay(0.1 + 0.12 * i) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(titulo, "modulate:a", 1.0, 0.4).set_delay(0.5)
	t.tween_property(titulo, "scale", Vector2.ONE, 0.6).set_delay(0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_interval(DURACAO_VINHETA - 1.5)
	t.chain().tween_property(_vinheta, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(func(): _vinheta.visible = false)

func mostrar_abertura(mapa: String, formato: String, grid: String, tomada: String, contagem: bool, _ativos: Array, _foco: int, _carros: Dictionary):
	_cartela_titulo.text = mapa.to_upper()
	_cartela_info.text = formato
	_cartela_grid.text = grid
	_angulo.text = "·  %s" % tomada
	if contagem:
		TemaEvento.mudar_pilula(_cartela_estado, "LARGADA!", TemaEvento.VERDE)
		_cartela_estado.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.008))
	else:
		TemaEvento.mudar_pilula(_cartela_estado, "NO GRID", TemaEvento.QUENTE)
		_cartela_estado.modulate.a = 1.0

# --- Corrida --------------------------------------------------------------------------

func mostrar_jogador(item: Dictionary, nome: String, angulo: String, _ativos: Array, _foco: int, pausado: bool, fracao: float, _carros: Dictionary):
	_nome.text = nome.to_upper()
	_estrela_terco.visible = true
	_angulo.text = "·  %s%s" % [angulo, "  ·  PAUSADO" if pausado else ""]
	var mapa := str(item.get("mapa", ""))
	var posicao := int(item.get("posicao", 0))
	_pos_terco.visible = mapa != "" and posicao > 0
	_pos_terco.text = "%dº" % posicao
	var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
	_pos_terco.add_theme_color_override("font_color", medalhas[posicao - 1] if posicao >= 1 and posicao <= 3 else Color.WHITE)
	if mapa != "":
		var texto := mapa.to_upper()
		var volta := int(item.get("volta", 0))
		var voltas := int(item.get("voltas", 3))
		if item.get("chegou", false):
			texto += "  ·  BANDEIRADA  ·  %dº DE %d" % [posicao, int(item.get("total", 0))]
		elif volta > 0 and voltas <= 1:
			# Ponta a ponta: não tem volta para contar
			texto += "  ·  SPRINT  ·  %dº DE %d" % [posicao, int(item.get("total", 0))]
		elif volta > 0:
			texto += "  ·  VOLTA %d/%d  ·  %dº DE %d" % [mini(volta, voltas), voltas, posicao, int(item.get("total", 0))]
		else:
			texto += "  ·  NO GRID"
		_local.text = texto
	else:
		_local.text = "MUNDO NEON" + ("  ·  NITRO" if item.get("nitro", false) else "")
	if item.get("explodindo", false):
		TemaEvento.mudar_pilula(_situacao, "EXPLODIU", TemaEvento.ALERTA)
	elif item.get("na_esfera", false):
		TemaEvento.mudar_pilula(_situacao, "NA ESFERA", TemaEvento.QUENTE)
	elif item.has("sobrecarga"):
		TemaEvento.mudar_pilula(_situacao, "SOBRECARGA %ds" % ceili(float(item.sobrecarga)), TemaEvento.ALERTA)
	elif item.get("chegou", false):
		TemaEvento.mudar_pilula(_situacao, "BANDEIRADA", TemaEvento.OURO)
	elif mapa != "":
		TemaEvento.mudar_pilula(_situacao, "CORRIDA", TemaEvento.VERDE)
	else:
		TemaEvento.mudar_pilula(_situacao, "LOBBY", TemaEvento.CIANO)
	_mostrar_vida(int(item.get("vida", 0)), int(item.get("vida_max", 8)))
	_velocidade.text = "%d" % roundi(float(item.get("vel", 0.0)))
	_progresso.offset_right = _progresso.offset_left + LARGURA_TERCO * clampf(fracao, 0.0, 1.0)

func _mostrar_vida(vida: int, vida_max: int):
	if vida_max != _vida_max:
		_vida_max = vida_max
		for filho in _vida.get_children():
			_vida.remove_child(filho)
			filho.queue_free()
		for i in vida_max:
			var segmento := ColorRect.new()
			segmento.custom_minimum_size = Vector2(26, 14)
			_vida.add_child(segmento)
	var cor := TemaEvento.cor_nivel(float(vida) / maxf(vida_max, 1))
	for i in _vida.get_child_count():
		(_vida.get_child(i) as ColorRect).color = cor if i < vida else Color(1, 1, 1, 0.1)
	_vida_texto.text = "%d/%d" % [vida, vida_max]

# --- Pódio e ranking --------------------------------------------------------------------

func mostrar_podio(pista: String, vencedor: String, real: bool):
	_podio_titulo.text = "PÓDIO  ·  %s" % pista.to_upper()
	_podio_vencedor.text = "VENCEDOR:  %s%s" % ["★ " if real else "", vencedor.to_upper()]
	_podio.visible = true
	_podio.modulate.a = 0.0
	_podio.offset_top = 40
	var t := create_tween().set_parallel()
	t.tween_property(_podio, "modulate:a", 1.0, 0.5).set_delay(0.6)
	t.tween_property(_podio, "offset_top", 90.0, 0.6).set_delay(0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func esconder_podio():
	_podio.visible = false

## Placar "RANKING DO EVENTO" (top 10 do Ranking), com NOVO em quem acabou de correr;
## as linhas entram uma a uma
func mostrar_ranking_final(destaques: Array):
	for filho in _placar_linhas.get_children():
		filho.queue_free()
	var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
	var nomes := destaques.map(func(n): return str(n).to_upper())
	var t := create_tween().set_parallel()
	for i in mini(10, Ranking.top.size()):
		var r: Dictionary = Ranking.top[i]
		var linha := PanelContainer.new()
		var novo := str(r.get("nome", "")).to_upper() in nomes
		var caixa := TemaEvento.estilo(Color(TemaEvento.CIANO, 0.22) if novo else Color(1, 1, 1, 0.04 if i % 2 else 0.0), Color.TRANSPARENT, 0, 6, 8.0)
		caixa.content_margin_left = 16
		caixa.content_margin_right = 16
		linha.add_theme_stylebox_override("panel", caixa)
		var conteudo := HBoxContainer.new()
		conteudo.add_theme_constant_override("separation", 18)
		linha.add_child(conteudo)
		var cor: Color = medalhas[i] if i < 3 else Color.WHITE
		var pos := TemaEvento.rotulo("%d" % (i + 1), 30, cor, true, true)
		pos.custom_minimum_size.x = 56
		pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		conteudo.add_child(pos)
		var nome := TemaEvento.rotulo("★ " + str(r.get("nome", "")).to_upper(), 28, Color.WHITE, true)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		conteudo.add_child(nome)
		if novo:
			conteudo.add_child(TemaEvento.pilula("NOVO", TemaEvento.VERDE, 14))
		conteudo.add_child(TemaEvento.rotulo(str(r.get("pista", "")).to_upper(), 18, TemaEvento.TEXTO_SUAVE, true))
		var tempo := TemaEvento.rotulo(Ranking.formatar_tempo(float(r.get("tempo", 0.0))), 30, cor, true, true)
		tempo.custom_minimum_size.x = 170
		tempo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		conteudo.add_child(tempo)
		_placar_linhas.add_child(linha)
		linha.modulate.a = 0.0
		t.tween_property(linha, "modulate:a", 1.0, 0.35).set_delay(0.3 + 0.08 * i)
	if Ranking.top.is_empty():
		_placar_linhas.add_child(TemaEvento.rotulo("NENHUM TEMPO AINDA: SEJA O PRIMEIRO!", 26, TemaEvento.CIANO, true))
	_placar.visible = true
	_placar.modulate.a = 0.0
	t.tween_property(_placar, "modulate:a", 1.0, 0.4)

func esconder_ranking_final():
	_placar.visible = false

## Top 5 do evento no painel de espera
func mostrar_ranking():
	for filho in _espera_ranking.get_children():
		filho.queue_free()
	if Ranking.top.is_empty():
		return
	var titulo := TemaEvento.rotulo("RANKING · MELHORES TEMPOS", 15, TemaEvento.CIANO, true)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_espera_ranking.add_child(titulo)
	var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
	for i in mini(5, Ranking.top.size()):
		var r: Dictionary = Ranking.top[i]
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 16)
		var cor: Color = medalhas[i] if i < 3 else TemaEvento.TEXTO_SUAVE
		var pos := TemaEvento.rotulo("%dº" % (i + 1), 20, cor, true, true)
		pos.custom_minimum_size.x = 50
		linha.add_child(pos)
		var nome := TemaEvento.rotulo(str(r.get("nome", "")), 20, Color.WHITE, true)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		linha.add_child(nome)
		linha.add_child(TemaEvento.rotulo(str(r.get("pista", "")), 15, TemaEvento.TEXTO_SUAVE))
		linha.add_child(TemaEvento.rotulo(Ranking.formatar_tempo(float(r.get("tempo", 0.0))), 20, cor, true, true))
		_espera_ranking.add_child(linha)
