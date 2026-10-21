extends Node
## Adesivos do Eco Shell 326: desenha uma única vez um atlas com "SENAI",
## "Sistema Fiep | SENAI" e a placa 326 num SubViewport, guarda como textura e
## passa para o shader do casco (filho de eco_shell_casco.gd), que projeta cada
## adesivo nas laterais ou no bico.

const TAMANHO := Vector2i(1024, 512)
const SENAI := Rect2i(0, 0, 512, 128)
const FIEP := Rect2i(0, 128, 640, 128)
const PLACA := Rect2i(0, 256, 224, 256)

const LATERAL := 0
const BICO := 1
## [onde, região do atlas, centro (Z,Y nas laterais; X,Y visto de frente no bico), largura (m), giro (graus)]
const ADESIVOS := [
	[LATERAL, FIEP, Vector2(0.02, 0.6), 0.45, 0.0],
	[LATERAL, SENAI, Vector2(0.64, 0.4), 0.3, -90.0],
	[LATERAL, PLACA, Vector2(0.92, 0.4), 0.16, 0.0],
	[BICO, PLACA, Vector2(0.0, 0.36), 0.12, 0.0],
	[BICO, SENAI, Vector2(-0.15, 0.37), 0.2, -50.0],
	[BICO, SENAI, Vector2(0.15, 0.37), 0.2, 50.0],
]

func _ready():
	var tela := SubViewport.new()
	tela.size = TAMANHO
	tela.transparent_bg = true
	tela.disable_3d = true
	tela.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(tela)
	_desenhar(tela)
	await RenderingServer.frame_post_draw
	var imagem := tela.get_texture().get_image()
	imagem.generate_mipmaps()
	tela.queue_free()

	var rects := PackedVector4Array()
	var posicoes := PackedVector4Array()
	var giros := PackedFloat32Array()
	var tipos := PackedFloat32Array()
	for a in ADESIVOS:
		var r: Rect2i = a[1]
		var largura: float = a[3]
		rects.append(Vector4(float(r.position.x) / TAMANHO.x, float(r.position.y) / TAMANHO.y,
			float(r.end.x) / TAMANHO.x, float(r.end.y) / TAMANHO.y))
		posicoes.append(Vector4(a[2].x, a[2].y, largura, largura * r.size.y / r.size.x))
		giros.append(deg_to_rad(a[4]))
		tipos.append(a[0])
	var material: ShaderMaterial = get_parent().material_casco
	material.set_shader_parameter("adesivos", ImageTexture.create_from_image(imagem))
	material.set_shader_parameter("adesivo_rect", rects)
	material.set_shader_parameter("adesivo_pos", posicoes)
	material.set_shader_parameter("adesivo_giro", giros)
	material.set_shader_parameter("adesivo_tipo", tipos)
	material.set_shader_parameter("qtd_adesivos", ADESIVOS.size())

func _desenhar(tela: SubViewport):
	var grossa := SystemFont.new()
	grossa.font_names = PackedStringArray(["Arial Black", "Segoe UI Black", "Roboto", "sans-serif"])
	grossa.font_weight = 900
	var media := SystemFont.new()
	media.font_names = PackedStringArray(["Arial", "Roboto", "sans-serif"])
	media.font_weight = 700
	var estreita := SystemFont.new()
	estreita.font_names = PackedStringArray(["Arial Narrow", "Roboto Condensed", "Arial", "sans-serif"])
	estreita.font_weight = 700

	_texto(tela, SENAI, "SENAI", grossa, 88, Color.WHITE)

	# "Sistema Fiep" empilhado, divisória tracejada e "SENAI" grande
	var linha := HBoxContainer.new()
	linha.position = FIEP.position
	linha.size = FIEP.size
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 18)
	tela.add_child(linha)
	var nome := _texto(linha, Rect2i(), "Sistema\nFiep", media, 40, Color.WHITE)
	nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nome.label_settings.line_spacing = -8.0
	var divisoria := VBoxContainer.new()
	divisoria.alignment = BoxContainer.ALIGNMENT_CENTER
	divisoria.add_theme_constant_override("separation", 6)
	for i in 5:
		var traco := ColorRect.new()
		traco.custom_minimum_size = Vector2(6, 12)
		divisoria.add_child(traco)
	linha.add_child(divisoria)
	_texto(linha, Rect2i(), "SENAI", grossa, 88, Color.WHITE)

	# Placa de competição: fundo branco, moldura preta arredondada, número preto
	var placa := Panel.new()
	placa.position = PLACA.position + Vector2i(6, 6)
	placa.size = PLACA.size - Vector2i(12, 12)
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color.WHITE
	fundo.set_corner_radius_all(14)
	placa.add_theme_stylebox_override("panel", fundo)
	tela.add_child(placa)
	var moldura := Panel.new()
	moldura.position = Vector2(14, 14)
	moldura.size = placa.size - Vector2(28, 28)
	var borda := StyleBoxFlat.new()
	borda.draw_center = false
	borda.border_color = Color.BLACK
	borda.set_border_width_all(6)
	borda.set_corner_radius_all(16)
	moldura.add_theme_stylebox_override("panel", borda)
	placa.add_child(moldura)
	_texto(placa, Rect2i(Vector2i.ZERO, Vector2i(placa.size)), "326", estreita, 100, Color.BLACK)

## Label centralizado; com região vazia, deixa o container pai posicionar
func _texto(pai: Node, regiao: Rect2i, texto: String, fonte: Font, tamanho: int, cor: Color) -> Label:
	var rotulo := Label.new()
	rotulo.text = texto
	rotulo.label_settings = LabelSettings.new()
	rotulo.label_settings.font = fonte
	rotulo.label_settings.font_size = tamanho
	rotulo.label_settings.font_color = cor
	rotulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if regiao.has_area():
		rotulo.position = regiao.position
		rotulo.size = regiao.size
	pai.add_child(rotulo)
	return rotulo
