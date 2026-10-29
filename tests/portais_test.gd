extends SceneTree
## godot --headless --path . --xr-mode off --script res://tests/portais_test.gd

func _initialize():
	_testar.call_deferred()

func _testar():
	create_timer(30.0).timeout.connect(func():
		push_error("Timeout no teste de entrada dos portais")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var carro = mapa.carro
	var portais = mapa.get_node("Portais")
	var mundos = mapa.get_node("Mundos")
	for indice in portais._portais.size():
		var portal: Portal = portais._portais[indice]
		assert(portal.has_node("Aura") and portal.has_node("Nucleo"))
		assert(portal.find_children("*", "GPUParticles3D", true, false).is_empty())
		assert(portal.find_children("*", "MultiMeshInstance3D", true, false).is_empty())
		assert(portal.has_node("MarcadorCorrida") == portais.CORRIDAS.has(indice))
		if portais.CORRIDAS.has(indice):
			assert(portal.get_node("MarcadorCorrida").position.y > Portal.ALTURA + Portal.RAIO)
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	carro.em_ritual = false
	# Entrar dirigindo ao nível do chão deve disparar a transição, sem chamar Mundos diretamente.
	for indice in [portais.CARMESIM, portais.AMBAR]:
		var portal: Portal = portais._portais[indice]
		carro.teleportar(Transform3D(Basis.IDENTITY, portal.global_position))
		carro.freeze = true
		portal._physics_process(0.0)
		assert(not portal._pronto)
		assert(mundos._trocando)
		assert(carro.em_transicao and carro.freeze)
		assert(mundos._transicao.visible and mundos._transicao._carregando)
		assert(mundos._transicao._destino == "Corrida / Deserto")
		var vida: int = carro.vida
		carro._registrar_choque(100.0, carro.global_position)
		carro._dash()
		assert(carro.vida == vida and carro.freeze)
		while mundos._trocando:
			await physics_frame
		assert(mundos.no_deserto and carro.hex_world == mundos.deserto)
		assert(not carro.em_transicao)
		assert(not mundos._transicao.visible and not mundos._transicao._carregando)
		await mundos.voltar()
		assert(not mundos.no_deserto)
		assert(not carro.em_transicao and not mundos._transicao.visible)
		assert(mundos._transicao._destino == "Mundo Neon")
		assert(not mapa.get_node("HexWorld").carregando())
	# Todo portal leva a uma corrida (ciano: Sistema S, violeta: Parque Industrial)
	assert(portais.CORRIDAS.size() == portais.CORES.size())
	assert(portais.CORRIDAS[portais.CIANO] == "Sistema S" and portais.CORRIDAS[portais.VIOLETA] == "Parque Industrial")
	print("PORTAIS_OK: entrada real no carmesim e âmbar; marcador em todos os portais de corrida")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
