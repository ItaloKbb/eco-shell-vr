class_name TelaoRanking
extends Node3D
## Telão do ranking geral flutuando alto no céu do mundo neon (só no cliente): uma
## SubViewport com a UI 2D, projetada num quad sem névoa e com moldura neon. Só
## redesenha quando chega ranking_mudou (UPDATE_ONCE), então custa quase nada por
## quadro. Gira devagar para ficar de frente para o piloto, levemente inclinado para
## baixo; tempo novo no top 10 pisca a linha, e 1º lugar novo mostra "NOVO RECORDE".

const RESOLUCAO := Vector2i(1024, 760)
const TAMANHO := Vector2(26.0, 19.3)
const ALTURA := 34.0
## Rotação em X (rad): a face aponta um pouco para baixo, para quem está no chão
const INCLINACAO := 0.3
const TEMPO_ANUNCIO := 6.0
const COR_CIANO := PainelHolografico.COR_CIANO
const COR_QUENTE := PainelHolografico.COR_QUENTE

var _tela: SubViewport
var _linhas: Array[Array] = []
var _recorde: Label
var _aviso: Label
var _top_anterior: Array = []
var _novo := -1
var _anuncio := 0.0

func _ready():
	position = Vector3(0.0, ALTURA, -60.0)
	_tela = SubViewport.new()
	_tela.size = RESOLUCAO
	_tela.disable_3d = true
	_tela.transparent_bg = false
	_tela.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_tela)
	_montar_ui()

	var quad := MeshInstance3D.new()
	var malha := QuadMesh.new()
	malha.size = TAMANHO
	quad.mesh = malha
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _tela.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	# Alto e longe: a névoa do chão apagaria o telão
	material.disable_fog = true
	quad.material_override = material
	add_child(quad)

	# Moldura neon atrás do quad, sobrando nas bordas
	var moldura := MeshInstance3D.new()
	var caixa := BoxMesh.new()
	caixa.size = Vector3(TAMANHO.x + 0.8, TAMANHO.y + 0.8, 0.3)
	moldura.mesh = caixa
	moldura.position.z = -0.2
	moldura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var neon := StandardMaterial3D.new()
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.albedo_color = COR_CIANO
	neon.disable_fog = true
	moldura.material_override = neon
	add_child(moldura)

	Ranking.ranking_mudou.connect(_ranking_mudou)
	Rede.sessao_mudou.connect(_redesenhar)
	_preencher(Ranking.top)

func _montar_ui():
	var fundo := PanelContainer.new()
	fundo.size = Vector2(RESOLUCAO)
	fundo.add_theme_stylebox_override("panel", PainelHolografico.estilo(Color(0.01, 0.03, 0.07), COR_CIANO, 4, 0))
	_tela.add_child(fundo)
	var margem := MarginContainer.new()
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 36)
	fundo.add_child(margem)
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 10)
	margem.add_child(coluna)
	var titulo := PainelHolografico.rotulo("RANKING GERAL", 54, COR_CIANO, true, 8)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(titulo)
	_recorde = PainelHolografico.rotulo("★ NOVO RECORDE ★", 40, COR_QUENTE, true, 6)
	_recorde.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recorde.visible = false
	coluna.add_child(_recorde)
	for i in Ranking.TOP:
		var linha := HBoxContainer.new()
		linha.add_theme_constant_override("separation", 18)
		var posicao := PainelHolografico.rotulo("%2dº" % (i + 1), 38, COR_CIANO, true)
		posicao.custom_minimum_size.x = 90
		var nome := PainelHolografico.rotulo("", 38, Color.WHITE, true)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nome.clip_text = true
		var pista := PainelHolografico.rotulo("", 24, Color(COR_CIANO, 0.7))
		pista.custom_minimum_size.x = 230
		pista.clip_text = true
		var tempo := PainelHolografico.rotulo("", 38, COR_QUENTE, true)
		tempo.custom_minimum_size.x = 200
		tempo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for parte in [posicao, nome, pista, tempo]:
			parte.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			linha.add_child(parte)
		coluna.add_child(linha)
		_linhas.append([linha, nome, pista, tempo])
	_aviso = PainelHolografico.rotulo("", 26, Color(COR_CIANO, 0.7))
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(_aviso)

func _ranking_mudou(top: Array):
	_novo = -1
	var chaves := {}
	for r in _top_anterior:
		chaves[_chave(r)] = true
	for i in top.size():
		if not chaves.has(_chave(top[i])):
			_novo = i
			break
	# 1º lugar mudou (e já havia um antes): recorde novo
	var recorde := not top.is_empty() and not _top_anterior.is_empty() and _chave(top[0]) != _chave(_top_anterior[0])
	if _novo >= 0 and not _top_anterior.is_empty():
		_anuncio = TEMPO_ANUNCIO
		_recorde.visible = recorde
	_preencher(top)

func _preencher(top: Array):
	_top_anterior = top.duplicate()
	for i in _linhas.size():
		var partes: Array = _linhas[i]
		if i < top.size():
			var r: Dictionary = top[i]
			partes[1].text = str(r.nome)
			partes[2].text = str(r.get("pista", ""))
			partes[3].text = Ranking.formatar_tempo(float(r.tempo))
		else:
			partes[1].text = "—"
			partes[2].text = ""
			partes[3].text = ""
		partes[0].modulate = Color.WHITE
	_redesenhar()

func _redesenhar():
	if Rede.conectado:
		_aviso.text = "" if not _top_anterior.is_empty() else "Ainda sem tempos. Seja o primeiro!"
	else:
		_aviso.text = "Procurando o servidor do evento..."
	_tela.render_target_update_mode = SubViewport.UPDATE_ONCE

func _chave(r: Dictionary) -> String:
	return "%s|%s|%s" % [r.get("nome", ""), r.get("tempo", ""), r.get("data", "")]

func _process(delta: float):
	var camera := get_viewport().get_camera_3d()
	if camera:
		var alvo := camera.global_position - global_position
		var rumo := atan2(alvo.x, alvo.z)
		rotation = Vector3(INCLINACAO, lerp_angle(rotation.y, rumo, 1.0 - exp(-0.8 * delta)), 0.0)
	if _anuncio <= 0.0:
		return
	# Enquanto pisca, redesenha todo quadro; depois volta ao UPDATE_ONCE
	_anuncio -= delta
	var pulso := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
	if _novo >= 0 and _novo < _linhas.size():
		_linhas[_novo][0].modulate = Color.WHITE.lerp(COR_QUENTE, pulso) if _anuncio > 0.0 else Color.WHITE
	_recorde.modulate.a = pulso
	if _anuncio <= 0.0:
		_recorde.visible = false
	_tela.render_target_update_mode = SubViewport.UPDATE_ONCE
