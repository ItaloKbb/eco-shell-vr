class_name TorreClassificacao
extends Control
## Torre de classificação do telão, no estilo das transmissões de F1: cabeçalho com a
## pista e a volta, e uma linha por carro com a posição, a barra na cor da pintura, o
## nome, ★ dourada em quem é jogador real e o intervalo para o carro da frente. A linha
## do carro em foco acende. Quando a ordem muda as linhas deslizam para o lugar novo
## (cada linha é guardada pelo nome), então a ultrapassagem aparece na torre.
## atualizar() recebe as linhas já ordenadas: [{nome, real, cor, intervalo, foco}].

const LARGURA := 290.0
const ALTURA_CABECA := 58.0
const ALTURA_LINHA := 27.0
const MAX_LINHAS := 12
const DESLIZE := 0.35

var _cabeca_titulo: Label
var _cabeca_volta: Label
var _corpo: Control
var _fundo_corpo: Panel
## nome -> {raiz, pos, barra, nome, estrela, intervalo, fundo, alvo}
var _linhas := {}

func _init():
	custom_minimum_size = Vector2(LARGURA, ALTURA_CABECA)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Cabeçalho: marca da transmissão em cima, pista e volta embaixo
	var cabeca := Panel.new()
	cabeca.add_theme_stylebox_override("panel", _caixa(Color(0.01, 0.02, 0.05, 0.92), TemaEvento.CIANO, 3))
	cabeca.size = Vector2(LARGURA, ALTURA_CABECA - 6.0)
	add_child(cabeca)
	_cabeca_titulo = TemaEvento.rotulo("", 11, TemaEvento.CIANO, true)
	_cabeca_titulo.position = Vector2(12.0, 6.0)
	_cabeca_titulo.size = Vector2(LARGURA - 24.0, 16.0)
	_cabeca_titulo.clip_text = true
	cabeca.add_child(_cabeca_titulo)
	_cabeca_volta = TemaEvento.rotulo("", 20, Color.WHITE, true, true)
	_cabeca_volta.position = Vector2(12.0, 22.0)
	_cabeca_volta.size = Vector2(LARGURA - 24.0, 26.0)
	cabeca.add_child(_cabeca_volta)
	_fundo_corpo = Panel.new()
	_fundo_corpo.add_theme_stylebox_override("panel", _caixa(Color(0.01, 0.02, 0.05, 0.8), Color.TRANSPARENT, 0))
	_fundo_corpo.position = Vector2(0.0, ALTURA_CABECA)
	_fundo_corpo.size = Vector2(LARGURA, 0.0)
	add_child(_fundo_corpo)
	_corpo = Control.new()
	_corpo.position = Vector2(0.0, ALTURA_CABECA)
	_corpo.clip_contents = true
	add_child(_corpo)

## `titulo`: a pista ("DESERTO"); `volta`: "VOLTA 2/3", "SPRINT" ou "RESULTADO"
func atualizar(titulo: String, volta: String, linhas: Array):
	_cabeca_titulo.text = titulo.to_upper()
	_cabeca_volta.text = volta
	var vistos := {}
	var n := mini(linhas.size(), MAX_LINHAS)
	for i in n:
		var dado: Dictionary = linhas[i]
		var nome := str(dado.nome)
		vistos[nome] = true
		var linha: Dictionary = _linhas.get(nome, {})
		var alvo := i * ALTURA_LINHA
		if linha.is_empty():
			linha = _nova_linha()
			_linhas[nome] = linha
			linha.raiz.position = Vector2(0.0, alvo)
			linha.alvo = alvo
			linha.raiz.modulate.a = 0.0
			create_tween().tween_property(linha.raiz, "modulate:a", 1.0, 0.3)
		elif not is_equal_approx(linha.alvo, alvo):
			linha.alvo = alvo
			create_tween().tween_property(linha.raiz, "position:y", alvo, DESLIZE) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_preencher(linha, i + 1, dado)
	for nome in _linhas.keys():
		if not vistos.has(nome):
			_linhas[nome].raiz.queue_free()
			_linhas.erase(nome)
	_corpo.size = Vector2(LARGURA, n * ALTURA_LINHA)
	_fundo_corpo.size = _corpo.size
	custom_minimum_size = Vector2(LARGURA, ALTURA_CABECA + n * ALTURA_LINHA)
	size = custom_minimum_size

func _preencher(linha: Dictionary, posicao: int, dado: Dictionary):
	var foco: bool = dado.get("foco", false)
	var real: bool = dado.get("real", false)
	linha.pos.text = str(posicao)
	linha.barra.color = dado.get("cor", TemaEvento.CIANO)
	linha.nome.text = _curto(str(dado.nome))
	linha.nome.add_theme_color_override("font_color", Color.WHITE if foco or real else TemaEvento.TEXTO)
	linha.estrela.visible = real
	linha.intervalo.text = str(dado.get("intervalo", ""))
	var fundo: StyleBoxFlat = linha.fundo
	fundo.bg_color = Color(TemaEvento.CIANO, 0.32) if foco else (Color(1, 1, 1, 0.06) if posicao % 2 == 0 else Color(0, 0, 0, 0))
	# Pódio em ouro, prata e bronze no número
	var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
	linha.pos.add_theme_color_override("font_color", medalhas[posicao - 1] if posicao <= 3 else Color.WHITE)

func _nova_linha() -> Dictionary:
	var raiz := Panel.new()
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0, 0, 0, 0)
	raiz.add_theme_stylebox_override("panel", fundo)
	raiz.size = Vector2(LARGURA, ALTURA_LINHA)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corpo.add_child(raiz)
	var pos := TemaEvento.rotulo("", 15, Color.WHITE, true, true)
	pos.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pos.position = Vector2(2.0, 0.0)
	pos.size = Vector2(28.0, ALTURA_LINHA)
	raiz.add_child(pos)
	var barra := ColorRect.new()
	barra.position = Vector2(34.0, 6.0)
	barra.size = Vector2(4.0, ALTURA_LINHA - 12.0)
	raiz.add_child(barra)
	var nome := TemaEvento.rotulo("", 14, Color.WHITE, true)
	nome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nome.position = Vector2(46.0, 0.0)
	nome.size = Vector2(140.0, ALTURA_LINHA)
	nome.clip_text = true
	raiz.add_child(nome)
	var estrela := TemaEvento.rotulo("★", 13, TemaEvento.OURO, true)
	estrela.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	estrela.position = Vector2(188.0, 0.0)
	estrela.size = Vector2(16.0, ALTURA_LINHA)
	raiz.add_child(estrela)
	var intervalo := TemaEvento.rotulo("", 12, TemaEvento.TEXTO_SUAVE, false, true)
	intervalo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intervalo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intervalo.position = Vector2(204.0, 0.0)
	intervalo.size = Vector2(LARGURA - 214.0, ALTURA_LINHA)
	raiz.add_child(intervalo)
	return {"raiz": raiz, "pos": pos, "barra": barra, "nome": nome, "estrela": estrela,
		"intervalo": intervalo, "fundo": fundo, "alvo": 0.0}

## Nome da torre: até 12 letras, em caixa alta
func _curto(nome: String) -> String:
	var limpo := nome.strip_edges().to_upper()
	return limpo if limpo.length() <= 12 else limpo.left(11) + "."

func _caixa(fundo: Color, borda: Color, espessura: int) -> StyleBoxFlat:
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = fundo
	caixa.border_color = borda
	caixa.border_width_top = espessura
	caixa.corner_radius_top_left = 6
	caixa.corner_radius_top_right = 6
	return caixa
