extends SceneTree
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/manejo_test.gd
var menor_cima := 1.0
## Maior rolagem lateral da carroceria na curva (graus): a câmera VR herda tudo
var rolagem_max := 0.0
var giro_total := 0.0
var anterior := Vector3.FORWARD

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
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 10:
		await physics_frame
	mapa.get_node("HexWorld").desligar()
	mapa.get_node("Portais").process_mode = Node.PROCESS_MODE_DISABLED
	# Testa a pilotagem por muito tempo no mundo neon: sem a sobrecarga do lobby
	mapa.carro.tempo_lobby = INF
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	mapa.get_node("EsferaInicial").hide()
	var solo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(400, 1, 400)
	forma.shape = caixa
	solo.add_child(forma)
	mapa.add_child(solo)
	solo.position.y = -0.5
	var carro = mapa.carro
	for sentido in [KEY_A, KEY_D]:
		carro.teleportar(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)))
		carro.em_ritual = false
		carro._esperando_chao = false
		carro.freeze = false
		menor_cima = 1.0
		rolagem_max = 0.0
		giro_total = 0.0
		anterior = Vector3.FORWARD
		carro.direcao = 0.0
		# Evita que o cenário de teste seja interrompido por dano de pouso.
		carro.choque_fatal = 1000.0
		carro.choque_minimo = 1000.0
		for i in 120:
			await physics_frame
		tecla(KEY_W, true)
		for i in 300:
			await physics_frame
		print("RETA velocidade=", carro.linear_velocity.length(), " cima=", carro.global_basis.y.y)
		tecla(sentido, true)
		for i in 240:
			await physics_frame
			menor_cima = minf(menor_cima, carro.global_basis.y.y)
			rolagem_max = maxf(rolagem_max, rad_to_deg(absf(asin(carro.global_basis.x.y))))
			var frente: Vector3 = -carro.global_basis.z
			giro_total += anterior.signed_angle_to(frente, Vector3.UP)
			anterior = frente
		print("MANEJO min_cima=", menor_cima, " rolagem_max=", rolagem_max, " curva_graus=", rad_to_deg(giro_total), " velocidade_final=", carro.linear_velocity.length())
		assert(menor_cima > 0.85, "O carro não deve tombar em curva contínua no plano")
		assert(rolagem_max < 8.0, "A carroceria não deve rolar muito na curva (vertigem na VR)")
		assert(absf(rad_to_deg(giro_total)) > 120.0, "A direção deve responder em velocidade")
		assert(carro.linear_velocity.length() > 5.5, "Deve manter movimento durante a curva")
		tecla(KEY_W, false)
		tecla(sentido, false)
	print("MANEJO_OK: curvas nos dois sentidos sem capotar, com resposta e velocidade")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
