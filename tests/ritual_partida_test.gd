extends SceneTree
## Executar: godot --headless --path . --xr-mode off --script res://tests/ritual_partida_test.gd


func _initialize():
	_testar.call_deferred()

func _testar():
	create_timer(30.0).timeout.connect(func():
		push_error("Timeout: teste do ritual não terminou")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var ritual = mapa.ritual
	var carro = mapa.carro
	ritual.arquivo_perfil = "res://.godot/test_piloto.cfg"
	assert(carro.em_ritual and carro.freeze)
	carro._dash()
	carro._alternar_energia()
	carro._registrar_choque(100.0, carro.global_position)
	assert(carro.vida == carro.VIDA_MAX and not carro.gerando)
	assert(carro.global_position.distance_to(mapa.get_node("EsferaInicial").global_position) < 0.01)
	assert(ritual._sanitizar("  ab!c123456789  ") == "ABC12345")
	ritual.nick = "   "
	ritual._confirmar()
	assert(ritual.estado == ritual.Estado.ESCOLHA)
	ritual.nick = " TESTE1 "
	ritual._confirmar()
	assert(ritual.estado == ritual.Estado.CARGA and ritual.nick == "TESTE1")
	var perfil := ConfigFile.new()
	assert(perfil.load(ritual.arquivo_perfil) == OK)
	assert(perfil.get_value("piloto", "nick") == "TESTE1")
	Input.action_release("ui_accept")
	var acelerador := InputEventKey.new()
	acelerador.keycode = KEY_W
	acelerador.physical_keycode = KEY_W
	acelerador.pressed = true
	Input.parse_input_event(acelerador)
	Input.flush_buffered_events()
	for i in 10:
		await physics_frame
	assert(ritual.carga == 0.0, "Acelerar antes de soltar não deve carregar")
	acelerador.pressed = false
	Input.parse_input_event(acelerador)
	Input.flush_buffered_events()
	for i in 3:
		await physics_frame
	assert(ritual._soltou)
	acelerador.pressed = true
	Input.parse_input_event(acelerador)
	Input.flush_buffered_events()
	for i in 150:
		await physics_frame
	assert(ritual.estado == ritual.Estado.PARTIDA, "Deve carregar e lançar")
	# O carro atravessa a casca estilhaçada antes de a física assumir
	for i in 60:
		if not carro.em_ritual:
			break
		await physics_frame
	assert(not carro.em_ritual and not carro.freeze)
	assert(carro.global_position.z < -6.0)
	acelerador.pressed = false
	Input.parse_input_event(acelerador)
	Input.flush_buffered_events()
	# Cria rastro real, incluindo a colisão, e morre duas vezes.
	for vida in 2:
		if vida == 1:
			carro.energia = 3.0
			carro._alternar_energia()
			assert(carro.gerando)
		carro.pista.comecar(carro.global_transform, carro._pontas())
		var pontas: Array[Vector3] = [carro._pontas()[0] + Vector3.FORWARD, carro._pontas()[1] + Vector3.FORWARD]
		carro.pista.adicionar(Transform3D(carro.global_basis, carro.global_position + Vector3.FORWARD), pontas)
		assert(not carro.pista._trechos.is_empty())
		carro.tempo_renascer = 0.05
		carro._explodir()
		assert(ritual.estado == ritual.Estado.MORTE)
		for i in 20:
			await physics_frame
		assert(ritual.estado == ritual.Estado.ESCOLHA)
		assert(carro.pista._trechos.is_empty())
		assert(carro.vida == carro.VIDA_MAX and carro.energia == 0.0)
		assert(carro.em_ritual and carro.freeze and not carro.explodindo)
		assert(ritual.nick == "TESTE1")
		assert(carro.global_position.distance_to(mapa.get_node("EsferaInicial").global_position) < 0.01)
		if vida == 0:
			ritual._confirmar()
			ritual.carga = 1.0
			await physics_frame
			ritual._tentar_partida()
			assert(ritual.estado == ritual.Estado.PARTIDA)
			while carro.em_ritual:
				await physics_frame
	ritual._confirmar()
	ritual.carga = 1.0
	await physics_frame
	ritual._tentar_partida()
	while carro.em_ritual:
		await physics_frame
	await mapa.get_node("Mundos").entrar_deserto(mapa.get_node("Portais")._portais[3])
	assert(mapa.get_node("Mundos").no_deserto)
	carro._explodir()
	for i in 150:
		await physics_frame
	assert(not mapa.get_node("Mundos").no_deserto)
	assert(ritual.estado == ritual.Estado.ESCOLHA)
	assert(carro.hex_world == mapa.get_node("HexWorld"))
	assert(carro.em_ritual and carro.freeze)
	assert(carro.global_position.distance_to(mapa.get_node("EsferaInicial").global_position) < 0.01)
	print("RITUAL_OK: nick, persistência, carga, lançamento, duas mortes, limpeza e retorno do deserto")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
