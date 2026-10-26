class_name CapaceteHUD
extends Node3D
## Visor do capacete: status do carro em texto holográfico azul, preso à cabeça.
## Cada bloco é uma SubViewport de alta densidade projetada num quad que se
## desenha por cima de tudo, em modo aditivo.
## Fica filho da câmera ativa (o carro cuida disso).

## Distância dos blocos até o olho (m)
@export var distancia := 1.0
## Quanto os blocos ficam para os lados e para baixo do centro da visão (graus)
@export var abertura := 24.0
@export var descida := 17.0

const SHADER := preload("res://visor_holografico.gdshader")
const RESOLUCAO := Vector2i(320, 128)
## Tamanho de cada pixel do visor a 1 m (m)
const TEXEL := 0.001

var _fonte := SystemFont.new()
var _telas: Array[SubViewport] = []
var _esquerda: Label
var _velocidade: Label
var _unidade: Label
var _direita: Label

func _ready():
	# Grayscale preserva bordas suaves na textura sem o fringing colorido do LCD.
	_fonte.font_names = PackedStringArray(["Consolas", "Lucida Console", "DejaVu Sans Mono", "Droid Sans Mono", "monospace"])
	_fonte.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_fonte.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	var caixa_e := _bloco(-1.0)
	_esquerda = _rotulo(caixa_e, 19, HORIZONTAL_ALIGNMENT_LEFT)

	var caixa_d := _bloco(1.0)
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_END
	linha.add_theme_constant_override("separation", 4)
	caixa_d.add_child(linha)
	_velocidade = _rotulo(linha, 39, HORIZONTAL_ALIGNMENT_RIGHT)
	_unidade = _rotulo(linha, 18, HORIZONTAL_ALIGNMENT_RIGHT)
	_unidade.text = "KM/H"
	_unidade.size_flags_vertical = Control.SIZE_SHRINK_END
	_direita = _rotulo(caixa_d, 19, HORIZONTAL_ALIGNMENT_RIGHT)

## Atualiza os textos; só redesenha as telas quando algo mudou
func escrever(esquerda: String, cor_esquerda: Color, km_h: int, direita: String, cor_direita: Color):
	if _trocar(_esquerda, esquerda, cor_esquerda):
		_telas[0].render_target_update_mode = SubViewport.UPDATE_ONCE
	var mudou := _trocar(_velocidade, "%03d" % km_h, cor_direita)
	mudou = _trocar(_unidade, _unidade.text, cor_direita) or mudou
	mudou = _trocar(_direita, direita, cor_direita) or mudou
	if mudou:
		_telas[1].render_target_update_mode = SubViewport.UPDATE_ONCE

func _trocar(rotulo: Label, texto: String, cor: Color) -> bool:
	if rotulo.text == texto and rotulo.label_settings.font_color == cor:
		return false
	rotulo.text = texto
	rotulo.label_settings.font_color = cor
	return true

## Cria a tela de um lado (-1 esquerda, 1 direita) e devolve a caixa onde vão os textos
func _bloco(lado: float) -> VBoxContainer:
	var tela := SubViewport.new()
	tela.size = RESOLUCAO
	tela.transparent_bg = true
	tela.disable_3d = true
	tela.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	tela.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(tela)
	_telas.append(tela)

	var caixa := VBoxContainer.new()
	caixa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caixa.offset_left = 4
	caixa.offset_right = -4
	caixa.alignment = BoxContainer.ALIGNMENT_END
	caixa.add_theme_constant_override("separation", 0)
	tela.add_child(caixa)

	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material.set_shader_parameter("tela", tela.get_texture())
	material.set_shader_parameter("resolucao", Vector2(RESOLUCAO))
	material.set_shader_parameter("grade_pixels", 0.18)
	material.set_shader_parameter("forca_halo", 0.16)
	material.set_shader_parameter("forca_cintilacao", 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(RESOLUCAO) * TEXEL * distancia
	var visor := MeshInstance3D.new()
	visor.mesh = quad
	visor.material_override = material
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gira para o lado e para baixo, sempre de frente para o olho
	var b := Basis(Vector3.UP, -lado * deg_to_rad(abertura)) * Basis(Vector3.RIGHT, -deg_to_rad(descida))
	visor.transform = Transform3D(b, b * Vector3(0.0, 0.0, -distancia))
	add_child(visor)
	return caixa

func _rotulo(pai: Control, tamanho: int, alinhamento: HorizontalAlignment) -> Label:
	var rotulo := Label.new()
	rotulo.label_settings = LabelSettings.new()
	rotulo.label_settings.font = _fonte
	rotulo.label_settings.font_size = tamanho
	rotulo.label_settings.line_spacing = -2.0
	rotulo.horizontal_alignment = alinhamento
	pai.add_child(rotulo)
	return rotulo
