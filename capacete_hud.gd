class_name CapaceteHUD
extends Node3D
## Visor do capacete, holográfico azul, preso à cabeça. Só o essencial, sem texto
## explicando nada: à esquerda a posição na corrida, grande; à direita a barra do nitro,
## mais cheia quanto mais nitro, acesa quando ligado. Avisos curtos (MINA!, SOBRECARGA)
## aparecem embaixo da posição só enquanto duram. A velocidade fica no painel do carro.
## Cada bloco é uma SubViewport de alta densidade projetada num quad que se desenha por
## cima de tudo, em modo aditivo. Fica filho da câmera ativa (o carro cuida disso).

## Distância dos blocos até o olho (m)
@export var distancia := 1.0
## Quanto os blocos ficam para os lados e para baixo do centro da visão (graus)
@export var abertura := 24.0
@export var descida := 17.0

const SHADER := preload("res://visor_holografico.gdshader")
const RESOLUCAO := Vector2i(320, 128)
## Tamanho de cada pixel do visor a 1 m (m)
const TEXEL := 0.001
const AZUL := Color(0.3, 0.7, 1.0)
const ACESO := Color(0.75, 0.97, 1.0)
## Barra do nitro (px na tela da direita)
const BARRA := Vector2(300.0, 30.0)

var _fonte := SystemFont.new()
var _telas: Array[SubViewport] = []
var _posicao: Label
var _total: Label
var _aviso: Label
var _moldura: Panel
var _estilo_moldura := StyleBoxFlat.new()
var _enchimento: ColorRect
## Último estado desenhado (só redesenha a tela quando muda)
var _desenhado := {}

func _ready():
	# Grayscale preserva bordas suaves na textura sem o fringing colorido do LCD.
	_fonte.font_names = PackedStringArray(["Consolas", "Lucida Console", "DejaVu Sans Mono", "Droid Sans Mono", "monospace"])
	_fonte.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_fonte.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	var caixa_e := _bloco(-1.0)
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 2)
	caixa_e.add_child(linha)
	_posicao = _rotulo(linha, 76, HORIZONTAL_ALIGNMENT_LEFT)
	_total = _rotulo(linha, 26, HORIZONTAL_ALIGNMENT_LEFT)
	_total.size_flags_vertical = Control.SIZE_SHRINK_END
	_aviso = _rotulo(caixa_e, 19, HORIZONTAL_ALIGNMENT_LEFT)

	var caixa_d := _bloco(1.0)
	_moldura = Panel.new()
	_moldura.custom_minimum_size = BARRA
	_moldura.size_flags_horizontal = Control.SIZE_SHRINK_END
	_estilo_moldura.bg_color = Color(AZUL, 0.12)
	_estilo_moldura.border_color = AZUL
	_estilo_moldura.set_border_width_all(2)
	_estilo_moldura.set_corner_radius_all(4)
	_moldura.add_theme_stylebox_override("panel", _estilo_moldura)
	caixa_d.add_child(_moldura)
	_enchimento = ColorRect.new()
	_enchimento.position = Vector2(4.0, 4.0)
	_enchimento.size = Vector2(0.0, BARRA.y - 8.0)
	_moldura.add_child(_enchimento)
	# Marcas de cada barra do tanque, por cima do enchimento
	for k in range(1, 5):
		var marca := ColorRect.new()
		marca.color = Color(0.0, 0.0, 0.0, 0.55)
		marca.position = Vector2(4.0 + (BARRA.x - 8.0) * k / 5.0 - 1.0, 4.0)
		marca.size = Vector2(2.0, BARRA.y - 8.0)
		_moldura.add_child(marca)

## `posicao` 0 = fora de corrida (sem número). `nitro` de 0 a 1. `aviso` vazio some
func mostrar(posicao: int, total: int, nitro: float, ligado: bool, aviso: String, cor_aviso: Color):
	nitro = snappedf(clampf(nitro, 0.0, 1.0), 0.01)
	# Ligado: a barra acende e pulsa; cheia (pronto para usar): brilho firme
	var pulso := 0.0
	if ligado:
		pulso = snappedf(0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 14.0), 0.1)
	var esquerda := [posicao, total, aviso, cor_aviso]
	if esquerda != _desenhado.get("esquerda"):
		_desenhado["esquerda"] = esquerda
		_posicao.visible = posicao > 0
		_total.visible = posicao > 0
		_posicao.text = "%dº" % posicao
		_total.text = "/%d" % total
		_aviso.text = aviso
		_aviso.label_settings.font_color = cor_aviso
		_telas[0].render_target_update_mode = SubViewport.UPDATE_ONCE
	var direita := [nitro, ligado, pulso]
	if direita != _desenhado.get("direita"):
		_desenhado["direita"] = direita
		var cheia := nitro >= 0.999
		var cor := AZUL.lerp(ACESO, pulso) if ligado else (ACESO if cheia else AZUL)
		_enchimento.size.x = (BARRA.x - 8.0) * nitro
		_enchimento.color = Color(cor, 0.95 if ligado or cheia else 0.75)
		_estilo_moldura.border_color = cor
		_telas[1].render_target_update_mode = SubViewport.UPDATE_ONCE

## Cria a tela de um lado (-1 esquerda, 1 direita) e devolve a caixa onde vão os itens
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
	caixa.offset_bottom = -6
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
	rotulo.label_settings.font_color = AZUL
	rotulo.label_settings.line_spacing = -2.0
	rotulo.horizontal_alignment = alinhamento
	pai.add_child(rotulo)
	return rotulo
