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

	# Grid: preso na última vaga, com os 10 adversários à frente, em vagas separadas
	assert(corrida.fase == Corrida.Fase.CONTROLES)
	assert(carro.segurado and carro.freeze)
	assert(corrida._painel.visible)
	assert(corrida._painel.tela.size == Vector2i(1024, 512), "O painel da corrida deve ter alta densidade no VR")
	assert(corrida._painel._grade.get_child_count() == 8, "Cada comando deve ocupar um cartão")
	assert(deserto.rivais.size() == 10)
	var frente: Vector3 = -carro.global_basis.z
	for i in deserto.rivais.size():
		var rival: CarroRival = deserto.rivais[i]
		assert((rival.global_position - carro.global_position).dot(frente) > 3.0, "Rival %d deve largar à frente" % i)
		for j in i:
			assert(rival.global_position.distance_to(deserto.rivais[j].global_position) > 2.5)
	assert(corrida.posicao == 11)

	# A música da corrida começa do início
	assert(musica.em_corrida)
	var tocando: AudioStreamPlayer = musica._players[musica._atual]
	assert(tocando.playing and tocando.stream.resource_path == musica.faixa_corrida)
	assert(tocando.get_playback_position() < 2.0)

	# Segurado: acelerar ronca o motor, mas o carro não sai do lugar
	var parado: Vector3 = carro.global_position
	tecla(KEY_W, true)
	for i in 30:
		await physics_frame
	assert(carro.comando_acel > 0.5)
	assert(carro.global_position.distance_to(parado) < 0.01)
	tecla(KEY_W, false)

	# Enter pula os controles; a contagem solta o carro sozinha
	tecla(KEY_ENTER, true)
	tecla(KEY_ENTER, false)
	assert(corrida.fase == Corrida.Fase.CONTAGEM)
	for i in 240:
		if corrida.fase == Corrida.Fase.CORRENDO:
			break
		await physics_frame
	assert(corrida.fase == Corrida.Fase.CORRENDO)
	assert(not carro.segurado and not carro.freeze)
	assert(corrida.volta == 1)
	# O freio deve engatar a ré depois de parar e mover o carro para trás.
	tecla(KEY_S, true)
	for i in 120:
		await physics_frame
	tecla(KEY_S, false)
	assert(carro.linear_velocity.dot(-carro.global_basis.z) < -1.0, "A ré não acelerou o carro")

	# Saindo do grid: a primeira passagem pela linha só arma os portões
	pista.portao.emit(0)
	assert(corrida.volta == 1 and corrida._cruzou_largada)
	# Passou todos os adversários: lidera
	carro.teleportar(deserto.global_transform * Transform3D(Basis.IDENTITY, pista.pontos[30]))
	carro.freeze = true
	for i in 3:
		await physics_frame
	assert(corrida.posicao == 1, "Na frente de todos deveria ser 1º, foi %d" % corrida.posicao)

	# Atalho não vale: pular portões não fecha volta
	pista.portao.emit(0)
	assert(corrida.volta == 1)
	for volta in 3:
		for k in range(1, PistaCorrida.PORTOES):
			pista.portao.emit(k)
		await physics_frame
		pista.portao.emit(0)
		if volta < 2:
			assert(corrida.volta == volta + 2)
	assert(corrida.fase == Corrida.Fase.CHEGADA)
	assert(resultado.size() == 1 and resultado[0] > 0.0)
	assert(corrida._melhor > 0.0)
	for i in 2:
		await process_frame
	assert(carro.painel_corrida.begins_with("CHEGOU 1º/11"), carro.painel_corrida)
	# Depois da chegada, portões não contam mais
	var proximo: int = corrida._proximo
	pista.portao.emit(proximo)
	assert(corrida._proximo == proximo and corrida.volta == Corrida.VOLTAS)

	await mundos.voltar()
	assert(corrida.fase == Corrida.Fase.PARADA)
	assert(carro.painel_corrida == "" and not carro.segurado)
	assert(not musica.em_corrida)
	print("CORRIDA_OK: grid com 10 rivais, música do início, controles, contagem, 3 voltas, posição e chegada")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
