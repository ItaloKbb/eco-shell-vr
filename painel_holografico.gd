class_name PainelHolografico
extends MeshInstance3D
## Painel holográfico do Eco Shell (nascimento e corrida): uma SubViewport com moldura
## de vidro escuro, borda ciano e cabeçalho (marca à esquerda, etapa à direita),
## projetada num quad. No monitor usa o shader do visor (LEDs, varredura, aditivo);
## na VR usa um material simples, sem cintilação nem halos.
## O conteúdo vai em `coluna`, entre o cabeçalho e o fim da moldura.

const COR_CIANO := Color(0.35, 0.8, 1.0)
const COR_QUENTE := Color(1.0, 0.62, 0.25)

static var _fonte: FontVariation
static var _fonte_forte: FontVariation

var tela: SubViewport
var coluna: VBoxContainer
var etapa: Label
var modo_vr := false
## Vidro escuro de verdade em vez do brilho aditivo: legível contra céu claro (dia)
var opaco := false
var _fundo: StyleBoxFlat
var _cabecalho: Array[Control] = []
var _abertura: Tween
var _assinatura := ""

func _init(resolucao: Vector2i, tamanho: Vector2, vr: bool, titulo := "ECO SHELL"):
	modo_vr = vr
	tela = SubViewport.new()
	tela.size = resolucao
	tela.transparent_bg = true
	tela.disable_3d = true
	tela.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(tela)

	# Moldura: vidro escuro com borda ciano e cantos cortados
	var moldura := PanelContainer.new()
	moldura.size = Vector2(resolucao)
	# Transparência sobre uma cena estereoscópica movimentada reduz muito o
	# contraste aparente. No VR o painel é quase opaco e a borda é mais forte.
	var alfa_fundo := 0.97 if modo_vr else 0.85
	var alfa_borda := 1.0 if modo_vr else 0.85
	_fundo = estilo(Color(0.012, 0.035, 0.075, alfa_fundo), Color(COR_CIANO, alfa_borda), 3 if modo_vr else 2, 14)
	moldura.add_theme_stylebox_override("panel", _fundo)
	tela.add_child(moldura)
	var margem := MarginContainer.new()
	for lado in ["left", "right"]:
		margem.add_theme_constant_override("margin_" + lado, 30)
	for lado in ["top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 20)
	moldura.add_child(margem)
	coluna = VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 12)
	margem.add_child(coluna)

	# Cabeçalho: marca à esquerda, etapa à direita, filete embaixo
	var topo := HBoxContainer.new()
	coluna.add_child(topo)
	topo.add_child(rotulo(titulo, 22, COR_CIANO, true, 6))
	var vao := Control.new()
	vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topo.add_child(vao)
	etapa = rotulo("", 18, Color(COR_CIANO, 0.6))
	topo.add_child(etapa)
	var filete := ColorRect.new()
	filete.color = Color(COR_CIANO, 0.35)
	filete.custom_minimum_size.y = 2
	coluna.add_child(filete)
	_cabecalho = [topo, filete]

	var quad := QuadMesh.new()
	quad.size = tamanho
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready():
	# A textura da SubViewport só é válida com o painel na árvore
	if modo_vr or opaco:
		# Texto sem grade de LEDs, varredura, cintilação ou halos aditivos no Link.
		var simples := StandardMaterial3D.new()
		simples.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		simples.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		simples.albedo_texture = tela.get_texture()
		# Sem mipmaps: a UI já está na resolução adequada e o nível menor deixava
		# letras finas borradas no headset.
		simples.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		if opaco:
			_fundo.bg_color.a = 1.0
			# Preso ao carro: nunca fica escondido atrás do bico ou do vidro
			simples.no_depth_test = true
			simples.render_priority = 127
		material_override = simples
	else:
		var material := ShaderMaterial.new()
		material.shader = preload("res://visor_holografico.gdshader")
		material.set_shader_parameter("tela", tela.get_texture())
		material.set_shader_parameter("resolucao", Vector2(tela.size))
		material.set_shader_parameter("intensidade", 1.6)
		material.render_priority = 127
		material_override = material

static func estilo(fundo: Color, borda: Color, espessura: int, canto: int) -> StyleBoxFlat:
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = fundo
	caixa.border_color = borda
	caixa.set_border_width_all(espessura)
	caixa.set_corner_radius_all(canto)
	caixa.corner_detail = 1
	return caixa

static func fonte(forte := false, espaco := -1) -> FontVariation:
	if _fonte == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
		_fonte = FontVariation.new()
		_fonte.base_font = base
		_fonte.spacing_glyph = 2
		var negrito := SystemFont.new()
		negrito.font_names = base.font_names
		negrito.font_weight = 700
		_fonte_forte = FontVariation.new()
		_fonte_forte.base_font = negrito
		_fonte_forte.spacing_glyph = 2
	var escolhida := _fonte_forte if forte else _fonte
	if espaco < 0 or espaco == escolhida.spacing_glyph:
		return escolhida
	var variante := FontVariation.new()
	variante.base_font = escolhida.base_font
	variante.spacing_glyph = espaco
	return variante

static func rotulo(texto: String, tamanho: int, cor: Color, forte := false, espaco := -1) -> Label:
	var r := Label.new()
	r.text = texto
	r.add_theme_font_override("font", fonte(forte, espaco))
	r.add_theme_font_size_override("font_size", tamanho)
	r.add_theme_color_override("font_color", cor)
	# Contorno mínimo evita que hastes finas desapareçam após a projeção no quad.
	r.add_theme_constant_override("outline_size", 2 if tamanho >= 20 else 1)
	r.add_theme_color_override("font_outline_color", Color(0.0, 0.01, 0.025, 0.9))
	return r

## Tecla desenhada como um "chip" (borda ciano, fundo translúcido)
static func tecla(texto: String, tamanho := 20) -> PanelContainer:
	var chip := PanelContainer.new()
	var caixa := estilo(Color(COR_CIANO, 0.18), Color(COR_CIANO, 0.9), 2, 5)
	caixa.content_margin_left = 8
	caixa.content_margin_right = 8
	chip.add_theme_stylebox_override("panel", caixa)
	var r := rotulo(texto, tamanho, Color.WHITE, true)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(r)
	return chip

static func caixa_dicas() -> HBoxContainer:
	var caixa := HBoxContainer.new()
	caixa.alignment = BoxContainer.ALIGNMENT_CENTER
	caixa.add_theme_constant_override("separation", 26)
	return caixa

## Dicas de rodapé: [[tecla, texto], ...]; só remonta quando mudam
func definir_dicas(caixa: HBoxContainer, dicas: Array):
	if dicas == caixa.get_meta("dicas", []):
		return
	caixa.set_meta("dicas", dicas)
	for filho in caixa.get_children():
		caixa.remove_child(filho)
		filho.queue_free()
	for dica in dicas:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)
		item.add_child(tecla(dica[0]))
		var texto := rotulo(dica[1], 20, Color(COR_CIANO, 0.9))
		texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		item.add_child(texto)
		caixa.add_child(item)

## Liga como um tubo de imagem: abre de uma linha fina até o tamanho cheio
func mostrar():
	if _abertura and _abertura.is_valid():
		_abertura.kill()
	visible = true
	scale = Vector3(1.0, 0.04, 1.0)
	_abertura = create_tween()
	_abertura.tween_property(self, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	redesenhar()

## Desliga fechando para uma linha
func fechar():
	if not visible:
		return
	if _abertura and _abertura.is_valid():
		_abertura.kill()
	_abertura = create_tween()
	_abertura.tween_property(self, "scale", Vector3(1.0, 0.04, 1.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_abertura.tween_callback(hide)

## Monitor: redesenha sempre (pisca/pulsa); VR: só quando a assinatura do conteúdo muda
func redesenhar(assinatura := ""):
	if modo_vr and assinatura != "" and assinatura == _assinatura:
		return
	_assinatura = assinatura
	tela.render_target_update_mode = SubViewport.UPDATE_ONCE

## Sem vidro nem cabeçalho: só o conteúdo flutuando (ex.: o número da contagem,
## para o semáforo do pórtico continuar à vista)
func moldura_visivel(sim: bool):
	_fundo.bg_color.a = (1.0 if opaco else 0.85) if sim else 0.0
	_fundo.border_color.a = 0.85 if sim else 0.0
	for parte in _cabecalho:
		parte.visible = sim
