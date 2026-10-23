class_name PainelCorrida
extends PainelHolografico
## Painel da corrida, em três páginas: os controles do dispositivo em uso (antes da
## largada), o número grande da contagem e o resultado na chegada.

enum Pagina { CONTROLES, CONTAGEM, CHEGADA }
enum Dispositivo { VR, CONTROLE, TECLADO }

## [tecla, ação] de cada dispositivo (no circuito não tem voo de energia)
const CONTROLES := {
	Dispositivo.VR: [
		["GATILHO D", "ACELERAR"], ["GATILHO E", "FREIO / RÉ"],
		["ANALÓG. E", "ESTERÇAR"], ["GRIP", "PEGAR GUIDÃO"],
		["B", "DASH"], ["X", "FREIO DE MÃO"],
		["Y", "DESVIRAR"], ["CLIQUE E", "RECENTRAR"],
	],
	Dispositivo.CONTROLE: [
		["RT", "ACELERAR"], ["LT", "FREIO / RÉ"],
		["ANALÓG. E", "ESTERÇAR"], ["ANALÓG. D", "OLHAR"],
		["B", "DASH / RT 2X"], ["X", "FREIO DE MÃO"],
		["Y", "DESVIRAR"], ["R3", "CENTRAR VISÃO"],
	],
	Dispositivo.TECLADO: [
		["W / ↑", "ACELERAR"], ["S / ↓", "FREIO / RÉ"],
		["A D", "ESTERÇAR"], ["MOUSE", "OLHAR"],
		["W W", "DASH"], ["ESPAÇO", "FREIO DE MÃO"],
		["R", "DESVIRAR"], ["ESC", "SOLTAR MOUSE"],
	],
}
const NOMES := {Dispositivo.VR: "META QUEST", Dispositivo.CONTROLE: "GAMEPAD", Dispositivo.TECLADO: "TECLADO"}

var _paginas: Array[Control] = []
var _grade: GridContainer
var _subtitulo: Label
var _dicas: HBoxContainer
var _numero: Label
var _legenda_contagem: Label
var _resultado: Array[Label] = []
var _dicas_chegada: HBoxContainer
var _dispositivo := -1

func _init(vr: bool):
	# Mais texels por grau que o painel antigo: os caracteres permanecem definidos
	# mesmo com o painel ocupando boa parte do campo de visão no headset.
	super(Vector2i(1024, 512), Vector2(1.5, 0.75), vr, "ECO SHELL // CORRIDA")
	opaco = true
	var miolo := MarginContainer.new()
	miolo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(miolo)

	# Controles: duas colunas de [tecla] ação
	var controles := VBoxContainer.new()
	controles.add_theme_constant_override("separation", 16)
	_subtitulo = rotulo("", 32, Color.WHITE, true, 5)
	_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controles.add_child(_subtitulo)
	var centro := CenterContainer.new()
	centro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controles.add_child(centro)
	_grade = GridContainer.new()
	_grade.columns = 2
	_grade.add_theme_constant_override("h_separation", 16)
	_grade.add_theme_constant_override("v_separation", 12)
	centro.add_child(_grade)
	_dicas = caixa_dicas()
	controles.add_child(_dicas)
	miolo.add_child(controles)

	# Contagem: número e instrução curta, sem a moldura para não cobrir a pista
	var contagem := CenterContainer.new()
	var coluna_contagem := VBoxContainer.new()
	coluna_contagem.alignment = BoxContainer.ALIGNMENT_CENTER
	coluna_contagem.add_theme_constant_override("separation", -24)
	_numero = rotulo("", 240, Color.WHITE, true)
	_numero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numero.add_theme_constant_override("outline_size", 30)
	_numero.add_theme_color_override("font_outline_color", Color(0.005, 0.015, 0.04, 0.98))
	coluna_contagem.add_child(_numero)
	_legenda_contagem = rotulo("PREPARE-SE", 28, Color.WHITE, true, 7)
	_legenda_contagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legenda_contagem.add_theme_constant_override("outline_size", 10)
	_legenda_contagem.add_theme_color_override("font_outline_color", Color(0.005, 0.015, 0.04, 1.0))
	coluna_contagem.add_child(_legenda_contagem)
	contagem.add_child(coluna_contagem)
	miolo.add_child(contagem)

	# Chegada: posição em destaque e métricas em cartões separados
	var chegada := VBoxContainer.new()
	chegada.add_theme_constant_override("separation", 14)
	var titulo := rotulo("BANDEIRADA", 44, COR_QUENTE, true, 8)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chegada.add_child(titulo)
	var resumo := HBoxContainer.new()
	resumo.alignment = BoxContainer.ALIGNMENT_CENTER
	resumo.add_theme_constant_override("separation", 18)
	resumo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chegada.add_child(resumo)

	var cartao_posicao := PanelContainer.new()
	cartao_posicao.custom_minimum_size = Vector2(280, 190)
	cartao_posicao.add_theme_stylebox_override("panel", _estilo_cartao(COR_QUENTE, 0.14, 2))
	var coluna_posicao := VBoxContainer.new()
	coluna_posicao.alignment = BoxContainer.ALIGNMENT_CENTER
	coluna_posicao.add_theme_constant_override("separation", -8)
	coluna_posicao.add_child(_rotulo_central("POSIÇÃO FINAL", 22, Color(COR_QUENTE, 0.9), true))
	var valor_posicao := _rotulo_central("", 76, Color.WHITE, true)
	coluna_posicao.add_child(valor_posicao)
	cartao_posicao.add_child(coluna_posicao)
	resumo.add_child(cartao_posicao)
	_resultado.append(valor_posicao)

	var metricas := VBoxContainer.new()
	metricas.add_theme_constant_override("separation", 10)
	resumo.add_child(metricas)
	for nome in ["TEMPO TOTAL", "MELHOR VOLTA", "VENCEDOR"]:
		var linha := PanelContainer.new()
		linha.custom_minimum_size = Vector2(550, 56)
		linha.add_theme_stylebox_override("panel", _estilo_cartao(COR_CIANO, 0.07, 1))
		var conteudo := HBoxContainer.new()
		conteudo.add_child(rotulo(nome, 21, Color(COR_CIANO, 0.82), false, 2))
		var vao := Control.new()
		vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		conteudo.add_child(vao)
		var valor := rotulo("", 28, Color.WHITE, true)
		valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		conteudo.add_child(valor)
		linha.add_child(conteudo)
		metricas.add_child(linha)
		_resultado.append(valor)
	_dicas_chegada = caixa_dicas()
	chegada.add_child(_dicas_chegada)
	miolo.add_child(chegada)

	_paginas.assign([controles, contagem, chegada])

func _estilo_cartao(cor: Color, alfa: float, borda: int) -> StyleBoxFlat:
	var caixa := estilo(Color(cor, alfa), Color(cor, 0.55), borda, 8)
	caixa.content_margin_left = 16
	caixa.content_margin_right = 16
	caixa.content_margin_top = 8
	caixa.content_margin_bottom = 8
	return caixa

func _rotulo_central(texto: String, tamanho: int, cor: Color, forte := false) -> Label:
	var label := rotulo(texto, tamanho, cor, forte)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _cartao_controle(atalho: String, acao: String) -> PanelContainer:
	var cartao := PanelContainer.new()
	cartao.custom_minimum_size = Vector2(450, 58)
	cartao.add_theme_stylebox_override("panel", _estilo_cartao(COR_CIANO, 0.055, 1))
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 14)
	var chip := tecla(atalho, 22)
	chip.custom_minimum_size.x = 142
	linha.add_child(chip)
	var texto := rotulo(acao, 22, Color.WHITE, true)
	texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(texto)
	cartao.add_child(linha)
	return cartao

func _pagina(qual: Pagina):
	for i in _paginas.size():
		_paginas[i].visible = i == qual
	moldura_visivel(qual != Pagina.CONTAGEM)

## `restante`: segundos até a largada começar sozinha
func mostrar_controles(dispositivo: Dispositivo, restante: float):
	_pagina(Pagina.CONTROLES)
	etapa.text = "LARGADA EM %ds" % ceili(restante)
	if dispositivo != _dispositivo:
		_dispositivo = dispositivo
		_subtitulo.text = "COMANDOS  ·  %s" % NOMES[dispositivo]
		for filho in _grade.get_children():
			_grade.remove_child(filho)
			filho.queue_free()
		for linha in CONTROLES[dispositivo]:
			_grade.add_child(_cartao_controle(linha[0], linha[1]))
		var pronto := "ENTER" if dispositivo == Dispositivo.TECLADO else "A"
		var dicas := [[pronto, "ESTOU PRONTO"]]
		if dispositivo == Dispositivo.VR:
			dicas.append(["CLIQUE D", "CONFORTO VR"])
		definir_dicas(_dicas, dicas)
	redesenhar("c|%d|%d" % [dispositivo, ceili(restante)])

## "3", "2", "1" em ciano esquentando; "VAI!" em verde
func mostrar_contagem(texto: String, calor: float):
	_pagina(Pagina.CONTAGEM)
	etapa.text = "LARGADA"
	_numero.text = texto
	var cor := Color(0.3, 1.0, 0.45) if texto == "VAI!" else COR_CIANO.lerp(COR_QUENTE, calor)
	_numero.add_theme_color_override("font_color", cor)
	_legenda_contagem.text = "ACELERE" if texto == "VAI!" else "PREPARE-SE"
	_legenda_contagem.add_theme_color_override("font_color", cor.lightened(0.2))
	redesenhar("n|" + texto)

func mostrar_chegada(posicao: int, total_carros: int, total: String, melhor: String, vencedor: String):
	_pagina(Pagina.CHEGADA)
	etapa.text = "RESULTADO"
	_resultado[0].text = "%dº / %d" % [posicao, total_carros]
	_resultado[1].text = total
	_resultado[2].text = melhor
	_resultado[3].text = vencedor
	_resultado[3].add_theme_color_override("font_color", COR_QUENTE if vencedor == "VOCÊ" else Color.WHITE)
	definir_dicas(_dicas_chegada, [["PORTAL", "VOLTE PELO PORTAL AZUL NO MIOLO"]])
	redesenhar("r|%d|%s|%s|%s" % [posicao, total, melhor, vencedor])
