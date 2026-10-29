extends SceneTree
## Telemetria do carro (lobby e corrida), quadro do servidor e o telão do espectador:
## mapas só cenário, carros pela telemetria, troca de jogador e ângulo, céu do mapa e HUD.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/espectador_test.gd

func _initialize():
	_testar.call_deferred()

func _esperar(quadros: int):
	for i in quadros:
		await process_frame

func _testar():
	create_timer(120.0).timeout.connect(func():
		push_error("Timeout no teste do espectador")
		quit(1))

	# --- Quest: telemetria do carro no lobby e na corrida ---
	var jogo = load("res://menu.tscn").instantiate()
	root.add_child(jogo)
	current_scene = jogo
	for i in 30:
		await physics_frame
	var carro = jogo.carro
	jogo.ritual.estado = jogo.ritual.Estado.PARTIDA
	carro.em_ritual = false
	var t: Dictionary = carro.telemetria()
	for chave in ["pos", "rot", "vel", "vida", "vida_max", "explodindo", "na_esfera", "nitro", "nitros", "mapa"]:
		assert(t.has(chave), "Telemetria sem %s" % chave)
	assert(t.mapa == "" and t.pos is Vector3 and t.rot is Quaternion and not t.has("rivais"))
	var mundos = jogo.get_node("Mundos")
	await mundos.entrar_deserto(jogo.get_node("Portais")._portais[3])
	t = carro.telemetria()
	assert(t.mapa == "Deserto" and t.voltas == Corrida.VOLTAS and t.total == MapaCorrida.ADVERSARIOS + 1)
	assert(t.rivais.size() == MapaCorrida.ADVERSARIOS and t.rivais[0][0] == 1 and t.rivais[0][1] is Vector3)
	var rivais_quest: Array = t.rivais

	# --- Servidor: só liberados com telemetria recente entram no quadro ---
	var dispositivos = root.get_node("/root/Dispositivos")
	var rede = root.get_node("/root/Rede")
	dispositivos.adicionar(7, "10.0.0.7")
	dispositivos.adicionar(8, "10.0.0.8")
	dispositivos.liberar(7, "CARLA")
	dispositivos.definir_telemetria(7, t)
	dispositivos.definir_telemetria(8, t)
	var quadro_servidor: Array = rede.montar_quadro()
	assert(quadro_servidor.size() == 1 and quadro_servidor[0].peer == 7 and quadro_servidor[0].nome == "CARLA")
	dispositivos.remover(7)
	dispositivos.remover(8)
	jogo.queue_free()
	await _esperar(5)

	# --- Espectador ---
	var esp = load("res://espectador.tscn").instantiate()
	root.add_child(esp)
	current_scene = esp
	while not esp.pronto:
		await process_frame
	for nome in esp.mapas:
		var m: MapaCorrida = esp.mapas[nome]
		assert(m.so_cenario and m.rivais.is_empty() and m.corrida == null and m.trafego == null and m.pista != null, "%s só cenário" % nome)
	assert(esp.mapas["Vale das Turbinas"].obstaculos != null, "Vale monta os obstáculos sem tráfego")
	await _esperar(2)
	assert(esp._hud._espera.visible and esp.lobby.visible, "Sem jogadores: tela de espera no mundo neon")

	var deserto: MapaCorrida = esp.mapas["Deserto"]
	var largada: Transform3D = deserto.largada()
	# O cenário do espectador fica onde o Quest monta: a pose recebida cai na pista
	var rival_quest: Vector3 = rivais_quest[0][1]
	assert(rival_quest.distance_to(deserto.largada(0).origin) < 1.0, "Mesmo mapa no Quest e no telão")
	var ana := {"peer": 5, "nome": "Ana", "apelido": "Óculos 1", "estado": "lobby",
		"pos": Vector3(10, 0.3, 20), "rot": Quaternion.IDENTITY, "vel": 88.4, "vida": 6, "vida_max": 8,
		"explodindo": false, "na_esfera": false, "nitro": false, "mapa": ""}
	var beto := {"peer": 9, "nome": "", "apelido": "Óculos 2", "estado": "correndo",
		"pos": largada.origin, "rot": largada.basis.get_rotation_quaternion(), "vel": 142.0, "vida": 8, "vida_max": 8,
		"explodindo": false, "na_esfera": false, "nitro": false, "mapa": "Deserto",
		"volta": 2, "voltas": 3, "posicao": 3, "total": 11, "rivais": rivais_quest}
	rede.quadro_recebido.emit([ana, beto])
	await _esperar(3)
	assert(esp.carros.size() == 2 and esp.foco == 5)
	assert(esp.mundo_atual == "" and esp.lobby.visible and not deserto.visible)
	assert(esp._hud._nome.text == "ANA" and "MUNDO NEON" in esp._hud._local.text)
	assert(esp._hud._velocidade.text == "88" and esp._hud._vida_texto.text == "6/8")
	assert(not esp._hud._espera.visible and esp._hud._terco.visible)
	assert(esp.carros[9].rotulo.text == "Óculos 2", "Sem nome do operador usa o apelido")
	var angulo_antes: int = esp.angulo

	# Fim da tomada: outro jogador e outro ângulo, com o céu e o sol do mapa dele
	esp.tempo_tomada = esp.TEMPO_TOMADA - 0.001
	await _esperar(3)
	assert(esp.foco == 9 and esp.angulo == (angulo_antes + 1) % 3)
	assert(esp.mundo_atual == "Deserto" and deserto.visible and not esp.lobby.visible)
	assert(esp.ambiente.environment == deserto.ambiente)
	var local: String = esp._hud._local.text
	assert("DESERTO" in local and "VOLTA 2/3" in local and "3º DE 11" in local, local)
	var visiveis: Array = esp.rivais.filter(func(r): return r.visible)
	assert(visiveis.size() == MapaCorrida.ADVERSARIOS, "Rivais da corrida de quem está em foco")
	for i in 40:
		await process_frame
	assert(esp.carros[9].global_position.distance_to(largada.origin) < 0.2)
	assert(esp.camera.global_position.distance_to(largada.origin) < 35.0, "Câmera seguindo o carro em foco")

	# Os três ângulos pelo teclado, e a volta para o lobby segue o foco
	for tecla in [KEY_1, KEY_2, KEY_3]:
		var evento := InputEventKey.new()
		evento.keycode = tecla
		evento.pressed = true
		esp._unhandled_input(evento)
		assert(esp.angulo == tecla - KEY_1 and esp.foco == 9)
		await _esperar(2)
	esp.angulo_fixo = -1

	# Explodiu: carro some e o HUD avisa; quem sai do quadro some do telão
	beto.explodindo = true
	esp.receber_quadro([ana, beto])
	await _esperar(2)
	assert(not esp.carros[9].visible)
	esp.receber_quadro([ana])
	await _esperar(3)
	assert(esp.carros.size() == 1 and esp.foco == 5 and esp.mundo_atual == "" and esp.lobby.visible)
	assert(esp.rivais.all(func(r): return not r.visible))
	esp.receber_quadro([])
	await _esperar(2)
	assert(esp.carros.is_empty() and esp._hud._espera.visible)
	print("ESPECTADOR_OK: telemetria do Quest, quadro do servidor, mapas só cenário, tomadas de 6 s, ângulos, céu do mapa e HUD")
	esp.queue_free()
	await _esperar(5)
	quit()
