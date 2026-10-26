class_name TemaEvento
extends RefCounted
## Tema das telas 2D do evento no PC (painel do servidor, escolha de modo, HUD do
## espectador): neon ciano sobre azul-noite, como o visor do Eco Shell. Texto em
## Bahnschrift (Windows), números em monoespaçada (PainelHolografico.fonte()).
## Variações de botão: "BotaoPrimario" e "BotaoPerigo" (theme_type_variation).

const FUNDO := Color(0.016, 0.024, 0.06)
const PAINEL := Color(0.03, 0.055, 0.11)
const CARTAO := Color(0.045, 0.08, 0.15)
const CARTAO_CLARO := Color(0.07, 0.115, 0.2)
const CIANO := PainelHolografico.COR_CIANO
const QUENTE := PainelHolografico.COR_QUENTE
const ALERTA := Color(1.0, 0.32, 0.32)
const VERDE := Color(0.3, 1.0, 0.5)
const OURO := Color(1.0, 0.82, 0.3)
const PRATA := Color(0.78, 0.84, 0.92)
const BRONZE := Color(0.9, 0.55, 0.3)
const TEXTO := Color(0.9, 0.94, 1.0)
const TEXTO_SUAVE := Color(0.58, 0.66, 0.8)
const CORES_ESTADO := {
	"idle": Color(0.6, 0.62, 0.7),
	"lobby": CIANO,
	"correndo": VERDE,
	"menu": Color(1.0, 0.85, 0.3),
}

static var _fonte: SystemFont
static var _fonte_forte: SystemFont
static var _tema: Theme

static func fonte(forte := false) -> Font:
	if _fonte == null:
		var nomes := PackedStringArray(["Bahnschrift", "Segoe UI", "DejaVu Sans", "sans-serif"])
		_fonte = SystemFont.new()
		_fonte.font_names = nomes
		_fonte_forte = SystemFont.new()
		_fonte_forte.font_names = nomes
		_fonte_forte.font_weight = 700
	return _fonte_forte if forte else _fonte

static func estilo(fundo: Color, borda := Color.TRANSPARENT, espessura := 0, canto := 6, margem := 8.0) -> StyleBoxFlat:
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = fundo
	caixa.border_color = borda
	caixa.set_border_width_all(espessura)
	caixa.set_corner_radius_all(canto)
	caixa.set_content_margin_all(margem)
	caixa.anti_aliasing = true
	return caixa

## Rótulo no tema; `mono` usa a fonte dos números (tempos, km/h, ping)
static func rotulo(texto: String, tamanho: int, cor := TEXTO, forte := false, mono := false) -> Label:
	var r := Label.new()
	r.text = texto
	r.add_theme_font_override("font", PainelHolografico.fonte(forte) if mono else fonte(forte))
	r.add_theme_font_size_override("font_size", tamanho)
	r.add_theme_color_override("font_color", cor)
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return r

## Pílula colorida (estado, tipo de evento): texto forte na cor, fundo translúcido
static func pilula(texto: String, cor: Color, tamanho := 13) -> PanelContainer:
	var chip := PanelContainer.new()
	var caixa := estilo(Color(cor, 0.16), Color(cor, 0.75), 1, 10, 0.0)
	caixa.content_margin_left = 10
	caixa.content_margin_right = 10
	caixa.content_margin_top = 2
	caixa.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", caixa)
	var r := rotulo(texto, tamanho, cor, true)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(r)
	return chip

static func mudar_pilula(chip: PanelContainer, texto: String, cor: Color):
	var caixa: StyleBoxFlat = chip.get_theme_stylebox("panel")
	caixa.bg_color = Color(cor, 0.16)
	caixa.border_color = Color(cor, 0.75)
	var r: Label = chip.get_child(0)
	r.text = texto
	r.add_theme_color_override("font_color", cor)

## Barra horizontal fina (bateria, vida): fundo apagado e preenchimento colorido
static func barra(largura: float, altura: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(largura, altura)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", estilo(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 3, 0.0))
	b.add_theme_stylebox_override("fill", estilo(CIANO, Color.TRANSPARENT, 0, 3, 0.0))
	return b

static func pintar_barra(b: ProgressBar, cor: Color):
	var fill: StyleBoxFlat = b.get_theme_stylebox("fill")
	fill.bg_color = cor

## Verde -> âmbar -> vermelho conforme a fração cai (vida, bateria)
static func cor_nivel(fracao: float) -> Color:
	if fracao > 0.5:
		return VERDE.lerp(CIANO, 0.35)
	if fracao > 0.25:
		return QUENTE
	return ALERTA

static func criar() -> Theme:
	if _tema:
		return _tema
	var t := Theme.new()
	t.default_font = fonte()
	t.default_font_size = 15

	t.set_color("font_color", "Label", TEXTO)

	# Botões: vidro escuro com borda ciano; primário cheio de ciano; perigo em vermelho
	for tipo in ["Button", "OptionButton", "MenuButton"]:
		_botao(t, tipo, CIANO, false)
	t.add_type("BotaoPrimario")
	t.set_type_variation("BotaoPrimario", "Button")
	_botao(t, "BotaoPrimario", CIANO, true)
	t.add_type("BotaoPerigo")
	t.set_type_variation("BotaoPerigo", "Button")
	_botao(t, "BotaoPerigo", ALERTA, false)

	t.set_stylebox("normal", "LineEdit", estilo(Color(0.0, 0.0, 0.0, 0.35), Color(CIANO, 0.3), 1, 5, 7.0))
	t.set_stylebox("focus", "LineEdit", estilo(Color.TRANSPARENT, CIANO, 2, 5, 7.0))
	t.set_stylebox("read_only", "LineEdit", estilo(Color(0.0, 0.0, 0.0, 0.2), Color(CIANO, 0.15), 1, 5, 7.0))
	t.set_color("font_color", "LineEdit", TEXTO)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXTO_SUAVE, 0.7))
	t.set_color("caret_color", "LineEdit", CIANO)
	t.set_color("selection_color", "LineEdit", Color(CIANO, 0.35))

	t.set_color("font_color", "CheckBox", TEXTO_SUAVE)
	t.set_color("font_hover_color", "CheckBox", TEXTO)
	t.set_color("font_pressed_color", "CheckBox", CIANO)
	for estado in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(estado, "CheckBox", estilo(Color.TRANSPARENT, Color.TRANSPARENT, 0, 4, 4.0))

	t.set_stylebox("panel", "Tree", estilo(Color(0.0, 0.0, 0.0, 0.25), Color.TRANSPARENT, 0, 6, 4.0))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", estilo(Color(CIANO, 0.18), Color.TRANSPARENT, 0, 3, 0.0))
	t.set_stylebox("selected_focus", "Tree", estilo(Color(CIANO, 0.25), Color.TRANSPARENT, 0, 3, 0.0))
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("title_button_normal", "Tree", estilo(Color(CIANO, 0.08), Color.TRANSPARENT, 0, 0, 6.0))
	t.set_stylebox("title_button_hover", "Tree", estilo(Color(CIANO, 0.14), Color.TRANSPARENT, 0, 0, 6.0))
	t.set_stylebox("title_button_pressed", "Tree", estilo(Color(CIANO, 0.2), Color.TRANSPARENT, 0, 0, 6.0))
	t.set_color("font_color", "Tree", TEXTO)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("title_button_color", "Tree", CIANO)
	t.set_font("title_button_font", "Tree", fonte(true))
	t.set_font_size("title_button_font_size", "Tree", 12)
	t.set_constant("v_separation", "Tree", 6)
	t.set_constant("draw_relationship_lines", "Tree", 0)
	t.set_constant("draw_guides", "Tree", 0)

	for barra_tipo in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", barra_tipo, estilo(Color(1, 1, 1, 0.03), Color.TRANSPARENT, 0, 4, 3.0))
		t.set_stylebox("grabber", barra_tipo, estilo(Color(CIANO, 0.3), Color.TRANSPARENT, 0, 4, 3.0))
		t.set_stylebox("grabber_highlight", barra_tipo, estilo(Color(CIANO, 0.55), Color.TRANSPARENT, 0, 4, 3.0))
		t.set_stylebox("grabber_pressed", barra_tipo, estilo(CIANO, Color.TRANSPARENT, 0, 4, 3.0))

	t.set_stylebox("panel", "PopupMenu", estilo(CARTAO, Color(CIANO, 0.5), 1, 6, 6.0))
	t.set_stylebox("hover", "PopupMenu", estilo(Color(CIANO, 0.2), Color.TRANSPARENT, 0, 4, 4.0))
	t.set_color("font_color", "PopupMenu", TEXTO)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "AcceptDialog", estilo(PAINEL, Color.TRANSPARENT, 0, 0, 14.0))
	t.set_stylebox("embedded_border", "Window", estilo(PAINEL, Color(CIANO, 0.6), 2, 8, 8.0))
	t.set_color("title_color", "Window", CIANO)
	t.set_font("title_font", "Window", fonte(true))
	t.set_stylebox("panel", "TooltipPanel", estilo(CARTAO, Color(CIANO, 0.5), 1, 5, 8.0))
	t.set_color("font_color", "TooltipLabel", TEXTO)

	t.set_color("default_color", "RichTextLabel", TEXTO)
	t.set_font("normal_font", "RichTextLabel", PainelHolografico.fonte())
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_stylebox("normal", "RichTextLabel", estilo(Color(0.0, 0.0, 0.0, 0.25), Color.TRANSPARENT, 0, 6, 8.0))
	_tema = t
	return t

static func _botao(t: Theme, tipo: String, cor: Color, cheio: bool):
	var fundo := Color(cor, 0.85) if cheio else Color(cor, 0.07)
	t.set_stylebox("normal", tipo, estilo(fundo, Color(cor, 0.55), 1, 6, 8.0))
	t.set_stylebox("hover", tipo, estilo(Color(cor, 1.0) if cheio else Color(cor, 0.16), cor, 1, 6, 8.0))
	t.set_stylebox("pressed", tipo, estilo(Color(cor, 0.65) if cheio else Color(cor, 0.28), cor, 2, 6, 8.0))
	t.set_stylebox("disabled", tipo, estilo(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.08), 1, 6, 8.0))
	t.set_stylebox("focus", tipo, estilo(Color.TRANSPARENT, Color(cor, 0.9), 1, 6, 8.0))
	var texto := Color(0.02, 0.05, 0.1) if cheio else cor.lerp(Color.WHITE, 0.35)
	t.set_color("font_color", tipo, texto)
	t.set_color("font_hover_color", tipo, Color(0.0, 0.02, 0.05) if cheio else Color.WHITE)
	t.set_color("font_pressed_color", tipo, Color(0.0, 0.02, 0.05) if cheio else Color.WHITE)
	t.set_color("font_focus_color", tipo, texto)
	t.set_color("font_disabled_color", tipo, Color(TEXTO_SUAVE, 0.45))
	t.set_font("font", tipo, fonte(true))
	t.set_font_size("font_size", tipo, 14)
