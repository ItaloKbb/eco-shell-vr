extends SceneTree
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/corrida_test.gd

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

func _testar():
	create_timer(60.0).timeout.connect(func():
		push_error("Timeout no teste da corrida")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var carro = mapa.carro
	var mundos = mapa.get_node("Mundos")
	var musica = mapa.get_node("Musica")
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	carro.em_ritual = false

	await mundos.entrar_deserto(mapa.get_node("Portais")._portais[mapa.get_node("Portais").AMBAR])
	var deserto: Deserto = mundos.deserto
	var corrida: Corrida = deserto.corrida
	var pista: PistaCorrida = deserto.pista
	var resultado := []
	corrida.terminou.connect(func(total: float, _melhor: float): resultado.append(total))

	# Enter pula os controles; a contagem solta o carro sozinha
	tecla(KEY_ENTER, true)
	tecla(KEY_ENTER, false)
	assert(corrida.fase == Corrida.Fase.CONTAGEM)
	for i in 240:
		if corrida.fase == Corrida.Fase.CORRENDO:
			break
		await physics_frame
	for n in 180:
		await physics_frame
		if n % 20 == 0:
			print(n, " vis=", corrida._painel.visible, " esc=", corrida._painel.scale, " fase=", corrida.fase, " t=", corrida._tempo_fase)
	quit()
