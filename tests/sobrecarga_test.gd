extends SceneTree
## Lobby sem inimigos e a sobrecarga: 35 s livres, depois 15 s perdendo vida até explodir;
## a corrida suspende a contagem e a volta recomeça do zero.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/sobrecarga_test.gd

func _initialize():
	_testar.call_deferred()

func _quadros(n: int):
	for i in n:
		await physics_frame

func _testar():
	create_timer(60.0).timeout.connect(func():
		push_error("Timeout no teste da sobrecarga")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	await _quadros(30)
	var carro = mapa.carro
	var ritual = mapa.ritual
	assert(not mapa.has_node("Inimigos"), "Lobby sem o gerador de inimigos")
	ritual.estado = ritual.Estado.PARTIDA
	ritual._painel.hide()
	carro.em_ritual = false
	carro.freeze = false
	carro.teleportar(Transform3D(Basis.IDENTITY, Vector3(30.0, 0.3, 30.0)))
	carro.tempo_no_lobby = 0.0
	carro.tempo_renascer = 0.05
	var danos := []
	carro.dano.connect(func(barras: int): danos.append(barras))

	# Conta em tempo real; nada de pirâmides aparecendo
	await _quadros(120)
	assert(is_equal_approx(carro.tempo_lobby, 35.0) and is_equal_approx(carro.tempo_sobrecarga, 15.0))
	assert(carro.tempo_no_lobby > 1.9 and carro.tempo_no_lobby < 2.1, "%.2f" % carro.tempo_no_lobby)
	assert(absf(carro.segundos_para_explodir() - 48.0) < 0.2)
	assert(get_nodes_in_group("piramides").is_empty() and carro.vida == carro.VIDA_MAX)

	# Até 35 s: vida cheia, sem sobrecarga na telemetria
	carro.tempo_no_lobby = carro.tempo_lobby - 0.5
	await _quadros(2)
	assert(carro.vida == carro.VIDA_MAX and danos.is_empty() and not carro.telemetria().has("sobrecarga"))

	# Corrida suspende a contagem; voltar ao lobby recomeça do zero
	carro.tempo_no_lobby = carro.tempo_lobby + 5.0
	var mundos = mapa.get_node("Mundos")
	await mundos.entrar_deserto(mapa.get_node("Portais")._portais[3])
	await _quadros(5)
	assert(carro.tempo_no_lobby == 0.0 and carro.segundos_para_explodir() == INF, "Na corrida não conta")
	await mundos.voltar()
	await _quadros(5)
	assert(carro.tempo_no_lobby < 0.5, "De volta ao lobby, recomeça: %.2f" % carro.tempo_no_lobby)
	var vida_inicio: int = carro.vida
	danos.clear()

	# Sobrecarga: a vida cai em passos até a metade no meio dos 15 s
	carro.tempo_no_lobby = carro.tempo_lobby - 0.01
	await _quadros(2)
	carro.tempo_no_lobby = carro.tempo_lobby + carro.tempo_sobrecarga * 0.5
	await _quadros(2)
	# Pouco depois da metade dos 15 s: metade da vida (arredondada para cima)
	assert(carro.vida == ceili(vida_inicio * 0.5), "vida %d de %d" % [carro.vida, vida_inicio])
	assert(not danos.is_empty() and not carro.explodindo)
	var t: Dictionary = carro.telemetria()
	assert(t.has("sobrecarga") and t.sobrecarga > 6.0 and t.sobrecarga < 8.0)

	# Fim dos 15 s: explode e renasce na esfera com a contagem zerada
	carro.tempo_no_lobby = carro.tempo_lobby + carro.tempo_sobrecarga - 0.01
	await _quadros(3)
	assert(carro.explodindo and ritual.estado == ritual.Estado.MORTE, "Explode ao fim da sobrecarga")
	await _quadros(30)
	assert(ritual.estado != ritual.Estado.MORTE and carro.em_ritual and not carro.explodindo)
	assert(carro.tempo_no_lobby == 0.0 and carro.vida == carro.VIDA_MAX)
	assert(carro.segundos_para_explodir() == INF, "Na esfera não conta")
	print("SOBRECARGA_OK: lobby sem inimigos, 35 s livres, vida caindo nos 15 s, explosão, renascer e pausa na corrida")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
