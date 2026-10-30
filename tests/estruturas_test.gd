extends SceneTree
## Dirige o carro de verdade pelas estruturas do mundo neon: loop com turbo, salto do
## abismo e ponte em arco. godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/estruturas_test.gd

var mapa
var carro

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

func _largar(pos: Vector3, velocidade: float):
	carro.teleportar(Transform3D(Basis.IDENTITY, pos))
	carro.em_ritual = false
	carro._esperando_chao = false
	carro.freeze = false
	carro.vida = carro.VIDA_MAX
	carro.linear_velocity = Vector3.FORWARD * velocidade
	carro.direcao = 0.0

func _testar():
	create_timer(90.0).timeout.connect(func():
		push_error("Timeout: teste das estruturas não terminou")
		quit(1))
	mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 10:
		await physics_frame
	mapa.get_node("Portais").process_mode = Node.PROCESS_MODE_DISABLED
	# Testa a pilotagem por muito tempo no mundo neon: sem a sobrecarga do lobby
	mapa.carro.tempo_lobby = INF
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	carro = mapa.carro
	var hex = mapa.get_node("HexWorld")
	var estruturas: EstruturasNeon = hex.estruturas
	assert(estruturas.get_child_count() >= 12, "Abismo, pontes, salto, loops e rampas")
	for corpo in estruturas.get_children():
		if corpo is StaticBody3D:
			var vista: MeshInstance3D = corpo.get_child(0)
			assert(vista.mesh.get_faces().size() > 0, "%s sem geometria" % corpo.name)
	assert(not hex.area_livre(Vector3(0, 0, EstruturasNeon.ABISMO_Z), 1.0))
	assert(hex.area_livre(Vector3(400, 0, 200), 30.0))

	# Loop sul: começa em (-160, 0, -60) rumo -Z; o turbo fica 6 m antes
	tecla(KEY_W, true)
	_largar(Vector3(-160, 0.3, -40), 12.0)
	var mais_alto := 0.0
	var menor_cima := 1.0
	for i in 420:
		await physics_frame
		mais_alto = maxf(mais_alto, carro.global_position.y)
		menor_cima = minf(menor_cima, carro.global_basis.y.y)
	print("LOOP alto=%.1f menor_cima=%.2f pos=%s vida=%d" % [mais_alto, menor_cima, carro.global_position, carro.vida])
	assert(mais_alto > 9.0, "Deve subir até o topo do loop")
	assert(menor_cima < -0.8, "Deve passar de cabeça para baixo")
	assert(carro.global_position.z < -110.0 and carro.global_position.y < 2.0, "Deve sair do loop pelo outro lado")
	assert(carro.global_position.x > -157.0, "A saída fica deslocada de lado")
	assert(carro.global_basis.y.y > 0.8, "Deve sair de pé")
	assert(carro.vida >= carro.VIDA_MAX - 1, "Loop não deve destruir o carro")

	# Salto do abismo: turbo antes da rampa da borda sul, pouso na rampa da borda norte
	var borda_sul := EstruturasNeon.ABISMO_Z + EstruturasNeon.ABISMO_MEIA
	_largar(Vector3(260, 0.3, borda_sul + 45.0), 12.0)
	var menor_y := 0.0
	for i in 300:
		await physics_frame
		menor_y = minf(menor_y, carro.global_position.y)
	print("SALTO menor_y=%.1f pos=%s vida=%d cima=%.2f" % [menor_y, carro.global_position, carro.vida, carro.global_basis.y.y])
	assert(menor_y > -1.0, "Não pode cair no abismo")
	assert(carro.global_position.z < EstruturasNeon.ABISMO_Z - EstruturasNeon.ABISMO_MEIA - 5.0, "Deve atravessar o abismo")
	assert(carro.vida >= carro.VIDA_MAX - 1, "O pouso na rampa não deve destruir o carro")

	# Ponte em arco: reta, atravessa de pé sem cair
	_largar(Vector3(-70, 0.3, borda_sul + 15.0), 8.0)
	menor_y = 0.0
	mais_alto = 0.0
	for i in 600:
		await physics_frame
		menor_y = minf(menor_y, carro.global_position.y)
		mais_alto = maxf(mais_alto, carro.global_position.y)
		if carro.global_position.z < EstruturasNeon.ABISMO_Z - EstruturasNeon.ABISMO_MEIA - 12.0:
			break
	print("PONTE alto=%.1f menor_y=%.1f pos=%s" % [mais_alto, menor_y, carro.global_position])
	assert(mais_alto > 5.0 and menor_y > -1.0, "Deve subir o arco e não cair")
	assert(carro.global_position.z < EstruturasNeon.ABISMO_Z - EstruturasNeon.ABISMO_MEIA - 12.0, "Deve chegar ao lado norte")

	# Fora do mapa: além da borda do piso conta como fora, mesmo no alto
	var meio: float = hex.world_size * 0.5
	carro.global_position = Vector3(meio + 1.0, 20.0, 0.0)
	assert(carro._fora_do_lobby(), "Passar da borda do piso é sair do mapa")
	carro.global_position = Vector3(meio - 1.0, 20.0, 0.0)
	assert(not carro._fora_do_lobby())

	# Abismo de verdade: sem ponte, cai e explode (renasce na esfera)
	_largar(Vector3(-20, 0.3, borda_sul + 4.0), 10.0)
	var caiu := false
	for i in 400:
		await physics_frame
		if carro.global_position.y < -5.0:
			caiu = true
		if carro.explodindo:
			break
	assert(caiu, "Sem ponte, o carro cai no abismo")
	assert(carro.explodindo and mapa.ritual.estado == mapa.ritual.Estado.MORTE, "Cair no abismo explode o carro")
	tecla(KEY_W, false)
	print("ESTRUTURAS_OK: loop, salto do abismo, ponte em arco, borda do mapa e queda no abismo")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
