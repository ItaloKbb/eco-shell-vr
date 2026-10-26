extends Control
## PC sem headset: pergunta se este computador é o servidor do evento (painel do
## operador) ou um espectador (telão com a transmissão dos jogadores). Teclas 1 e 2
## escolhem direto. Pular a pergunta: --servidor ou --espectador.

func _ready():
	theme = TemaEvento.criar()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fundo := ColorRect.new()
	fundo.color = TemaEvento.FUNDO
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centro)
	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 28)
	centro.add_child(coluna)

	var marca := TemaEvento.rotulo("ECO SHELL VR", 40, TemaEvento.CIANO, true)
	marca.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(marca)
	var pergunta := TemaEvento.rotulo("Como este computador vai ser usado no evento?", 18, TemaEvento.TEXTO_SUAVE)
	pergunta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(pergunta)

	var cartoes := HBoxContainer.new()
	cartoes.add_theme_constant_override("separation", 28)
	coluna.add_child(cartoes)
	var servidor := _cartao("1", "SERVIDOR", "Painel do operador: libera os óculos,\nacompanha a telemetria e o ranking.", TemaEvento.CIANO)
	servidor.pressed.connect(Inicializador.iniciar.bind("servidor"))
	cartoes.add_child(servidor)
	var espectador := _cartao("2", "ESPECTADOR", "Transmissão ao vivo para o telão:\ncâmeras alternando entre os jogadores.", TemaEvento.QUENTE)
	espectador.pressed.connect(Inicializador.iniciar.bind("espectador"))
	cartoes.add_child(espectador)
	servidor.grab_focus()

	var dica := TemaEvento.rotulo("Atalhos: 1 servidor · 2 espectador   ·   Pular esta tela: --servidor ou --espectador", 13, Color(TemaEvento.TEXTO_SUAVE, 0.7))
	dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coluna.add_child(dica)

func _cartao(tecla: String, titulo: String, texto: String, cor: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(400, 230)
	b.add_theme_stylebox_override("normal", TemaEvento.estilo(TemaEvento.CARTAO, Color(cor, 0.45), 2, 12, 24.0))
	b.add_theme_stylebox_override("hover", TemaEvento.estilo(TemaEvento.CARTAO_CLARO, cor, 2, 12, 24.0))
	b.add_theme_stylebox_override("focus", TemaEvento.estilo(Color.TRANSPARENT, cor, 3, 12, 24.0))
	b.add_theme_stylebox_override("pressed", TemaEvento.estilo(Color(cor, 0.2), cor, 3, 12, 24.0))
	var margem := MarginContainer.new()
	margem.set_anchors_preset(Control.PRESET_FULL_RECT)
	margem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for lado in ["left", "right", "top", "bottom"]:
		margem.add_theme_constant_override("margin_" + lado, 26)
	b.add_child(margem)
	var coluna := VBoxContainer.new()
	coluna.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coluna.add_theme_constant_override("separation", 12)
	margem.add_child(coluna)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 14)
	topo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coluna.add_child(topo)
	var chip := PainelHolografico.tecla(tecla, 22)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topo.add_child(chip)
	topo.add_child(TemaEvento.rotulo(titulo, 30, cor, true))
	var filete := ColorRect.new()
	filete.color = Color(cor, 0.4)
	filete.custom_minimum_size.y = 2
	filete.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coluna.add_child(filete)
	var descricao := TemaEvento.rotulo(texto, 16, TemaEvento.TEXTO)
	descricao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coluna.add_child(descricao)
	return b

func _unhandled_key_input(event: InputEvent):
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_KP_1:
			Inicializador.iniciar("servidor")
		KEY_2, KEY_KP_2:
			Inicializador.iniciar("espectador")
