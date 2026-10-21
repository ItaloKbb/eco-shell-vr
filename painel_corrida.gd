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
var _resultado: Array[Label] = []
var _dicas_chegada: HBoxContainer
var _dispositivo := -1

func _init(vr: bool):
	super(Vector2i(820, 400), Vector2(1.5, 0.732), vr)
	opaco = true
	var miolo := MarginContainer.new()
	miolo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	coluna.add_child(miolo)

	# Controles: duas colunas de [tecla] ação
	var controles := VBoxContainer.new()
	controles.add_theme_constant_override("separation", 14)
	_subtitulo = rotulo("", 28, Color.WHITE, true, 6)
	_subtitulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controles.add_child(_subtitulo)
	var centro := CenterContainer.new()
	centro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	controles.add_child(centro)
	_grade = GridContainer.new()
	_grade.columns = 4
	_grade.add_theme_constant_override("h_separation", 14)
	_grade.add_theme_constant_override("v_separation", 10)
	centro.add_child(_grade)
	_dicas = caixa_dicas()
	controles.add_child(_dicas)
	miolo.add_child(controles)

	# Contagem: só o número, enorme
	var contagem := CenterContainer.new()
	_numero = rotulo("", 210, Color.WHITE, true)
	_numero.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numero.add_theme_constant_override("outline_size", 24)
	_numero.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.08, 0.9))
	contagem.add_child(_numero)
	miolo.add_child(contagem)

	# Chegada: posição grande e os tempos
	var chegada := VBoxContainer.new()
	chegada.add_theme_constant_override("separation", 10)
	var titulo := rotulo("BANDEIRADA!", 40, COR_QUENTE, true, 8)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chegada.add_child(titulo)
	var linhas := CenterContainer.new()
	linhas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chegada.add_child(linhas)
	var tabela := GridContainer.new()
	tabela.columns = 2
	tabela.add_theme_constant_override("h_separation", 40)
	tabela.add_theme_constant_override("v_separation", 6)
	linhas.add_child(tabela)
	for nome in ["POSIÇÃO", "TEMPO TOTAL", "MELHOR VOLTA", "VENCEDOR"]:
		tabela.add_child(rotulo(nome, 28, Color(COR_CIANO, 0.85)))
		var valor := rotulo("", 34, Color.WHITE, true)
		valor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tabela.add_child(valor)
		_resultado.append(valor)
	_dicas_chegada = caixa_dicas()
	chegada.add_child(_dicas_chegada)
	miolo.add_child(chegada)

	_paginas.assign([controles, contagem, chegada])

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
		_subtitulo.text = "CONTROLES · %s" % NOMES[dispositivo]
		for filho in _grade.get_children():
			filho.queue_free()
		for linha in CONTROLES[dispositivo]:
			_grade.add_child(tecla(linha[0], 24))
			var acao := rotulo(linha[1], 24, Color(COR_CIANO, 0.95))
			acao.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			acao.custom_minimum_size.x = 200
			_grade.add_child(acao)
		var pronto := "ENTER" if dispositivo == Dispositivo.TECLADO else "A"
		definir_dicas(_dicas, [[pronto, "ESTOU PRONTO"]])
	redesenhar("c|%d|%d" % [dispositivo, ceili(restante)])

## "3", "2", "1" em ciano esquentando; "VAI!" em verde
func mostrar_contagem(texto: String, calor: float):
	_pagina(Pagina.CONTAGEM)
	etapa.text = "LARGADA"
	_numero.text = texto
	var cor := Color(0.3, 1.0, 0.45) if texto == "VAI!" else COR_CIANO.lerp(COR_QUENTE, calor)
	_numero.add_theme_color_override("font_color", cor)
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
