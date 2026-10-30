extends SceneTree
## Velocidade e manejo no dobro da velocidade, num piso plano enorme (sem muro nem
## curva da pista no caminho): arrancada controlável (~5 s até a máxima, tração nas três rodas), máxima do chão
## (24 m/s), nitro 3,5x no chão, e curva com o volante todo a 24 m/s sem o carro
## deslizar de lado ("roda de sabão").
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/velocidade_test.gd

var carro: RigidBody3D

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

## Escorregamento lateral (m/s) de um ponto do carro (z local: -0,75 frente, 0,7 traseira)
func lateral(z: float) -> float:
	var p: Vector3 = carro.global_transform * Vector3(0.0, 0.0, z)
	var v: Vector3 = carro.linear_velocity + carro.angular_velocity.cross(p - carro.global_position)
	return absf(v.dot(carro.global_basis.x))

func parar_em(pos: Vector3):
	carro.teleportar(Transform3D(Basis.IDENTITY, pos))
	for i in 30:
		await physics_frame

func _testar():
	create_timer(120.0).timeout.connect(func():
		push_error("Timeout no teste de velocidade")
		quit(1))
	var cena = load("res://menu.tscn").instantiate()
	root.add_child(cena)
	current_scene = cena
	for i in 10:
		await physics_frame
	cena.get_node("HexWorld").desligar()
	cena.get_node("Portais").process_mode = Node.PROCESS_MODE_DISABLED
	cena.ritual.estado = cena.ritual.Estado.PARTIDA
	cena.ritual._painel.hide()
	cena.get_node("EsferaInicial").hide()
	var solo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(800, 1, 2400)
	forma.shape = b
	solo.add_child(forma)
	solo.position = Vector3(0.0, -0.5, -900.0)
	cena.add_child(solo)
	carro = cena.carro
	carro.tempo_lobby = INF
	carro.em_ritual = false
	carro._esperando_chao = false
	carro.freeze = false
	carro.choque_minimo = 1000.0

	# Arrancada e máxima do chão
	await parar_em(Vector3(0.0, 0.2, 250.0))
	var chegou := -1
	var normal := 0.0
	tecla(KEY_W, true)
	for i in 60 * 9:
		await physics_frame
		normal = maxf(normal, carro.linear_velocity.length())
		if chegou < 0 and normal > 22.0:
			chegou = i
	print("0 a 22 m/s em %.1f s; máxima %.1f m/s" % [chegou / 60.0, normal])
	# Nem fraca (ficar preso) nem disparando de uma vez: ~5 s até perto da máxima
	assert(chegou > 60 * 3 and chegou < 60 * 7, "Arrancada fora do ritmo: %.1f s" % (chegou / 60.0))
	assert(normal > carro.velocidade_max - 0.8 and normal < carro.velocidade_max + 0.6)

	# Nitro: 3,5x, sem sair do chão
	carro.nitro = float(carro.nitro_max)
	tecla(KEY_E, true)
	tecla(KEY_E, false)
	var maior := 0.0
	var no_chao := true
	for i in 60 * 8:
		await physics_frame
		maior = maxf(maior, carro.linear_velocity.length())
		if carro.nitro_ativo and i > 30 and carro.rodas_no_chao < 2:
			no_chao = false
	tecla(KEY_W, false)
	print("Nitro: %.1f m/s (%.2fx)" % [maior, maior / normal])
	assert(maior > normal * 3.3 and maior < normal * 3.6, "Nitro deve dar ~3,5x")
	assert(no_chao, "Com nitro o carro segue no chão")

	# Curva com o volante todo a 24 m/s, acelerando: faz a curva sem deslizar de lado
	for sentido in [KEY_A, KEY_D]:
		await parar_em(Vector3(0.0, 0.2, 0.0))
		carro.linear_velocity = Vector3.FORWARD * carro.velocidade_max
		for i in 10:
			await physics_frame
		var rumo0: Vector3 = -carro.global_basis.z
		var desliza := 0.0
		var menor_v := INF
		tecla(KEY_W, true)
		tecla(sentido, true)
		for i in 60 * 3:
			await physics_frame
			if i > 20:
				desliza = maxf(desliza, maxf(lateral(-0.75), lateral(0.7)))
				menor_v = minf(menor_v, carro.linear_velocity.length())
		tecla(KEY_W, false)
		tecla(sentido, false)
		var virou := rad_to_deg(absf(rumo0.signed_angle_to(-carro.global_basis.z, Vector3.UP)))
		print("Curva a 24 m/s (%s): virou %.0f° em 3 s, escorregamento máx %.2f m/s, menor velocidade %.1f m/s" % [
			"esquerda" if sentido == KEY_A else "direita", virou, desliza, menor_v])
		assert(desliza < 2.0, "O carro desliza de lado na curva: %.2f m/s" % desliza)
		assert(virou > 90.0, "Curva aberta demais: %.0f°" % virou)
		assert(menor_v > 18.0, "Perdeu velocidade demais na curva: %.1f" % menor_v)
		assert(carro.global_basis.y.y > 0.9)

	print("VELOCIDADE_OK: arrancada, 24 m/s no chão, nitro 3,5x e curva firme a 24 m/s")
	cena.queue_free()
	for i in 5:
		await process_frame
	quit()
