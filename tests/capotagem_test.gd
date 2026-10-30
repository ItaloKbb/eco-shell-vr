extends SceneTree
## Anti-capotagem: situações que viravam o carro (meio-fio pegando uma roda só em alta
## velocidade, esterço todo com nitro, pouso tombado, quina de parede) agora o deixam de
## pé. Mede com a assistência ligada e desligada; com ela, nenhuma capota.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/capotagem_test.gd

const CAPOTOU := 0.3

var carro: RigidBody3D
var cena: Node
var obstaculos: Array[Node3D] = []

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

func caixa(tamanho: Vector3, t: Transform3D):
	var corpo := StaticBody3D.new()
	var forma := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = tamanho
	forma.shape = b
	corpo.add_child(forma)
	corpo.transform = t
	cena.add_child(corpo)
	obstaculos.append(corpo)

## Roda um cenário e devolve o menor "teto para cima" (global_basis.y.y) depois de
## começar (no pouso: depois de encostar no chão) e o do fim, já assentado
func cenario(nome: String, anti: bool) -> Vector2:
	for o in obstaculos:
		o.queue_free()
	obstaculos.clear()
	await physics_frame
	carro.anti_capotagem = anti
	carro.vida = carro.VIDA_MAX
	carro.teleportar(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)))
	carro.direcao = 0.0
	for i in 30:
		await physics_frame
	var teclas: Array[Key] = []
	match nome:
		"meio-fio":
			# Meio-fio de 15 cm pegando só a roda esquerda, a 20 m/s
			caixa(Vector3(1.0, 0.15, 3.0), Transform3D(Basis.IDENTITY, Vector3(-0.55, 0.075, -30.0)))
			carro.linear_velocity = Vector3.FORWARD * 20.0
			teclas = [KEY_W]
		"rampa":
			# Rampa só embaixo do lado esquerdo (sobe ~0,8 m em 4 m), a 20 m/s
			caixa(Vector3(1.0, 0.2, 4.0), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(12.0)), Vector3(-0.6, 0.3, -30.0)))
			carro.linear_velocity = Vector3.FORWARD * 20.0
			teclas = [KEY_W]
		"esterco":
			# Esterço todo de uma vez a 24 m/s (máxima do nitro), com freio de mão
			carro.linear_velocity = Vector3.FORWARD * 24.0
			teclas = [KEY_A, KEY_SPACE]
		"pouso":
			# Cai de 4 m tombado 75° de lado, andando
			carro.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(75.0)), Vector3(0, 4.0, 0))
			carro.linear_velocity = Vector3.FORWARD * 10.0
		"parede":
			# Muro baixo atravessado a 25°: a frente direita bate nele a 20 m/s
			caixa(Vector3(0.6, 0.9, 20.0), Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(4.0, 0.45, -30.0)))
			carro.linear_velocity = Vector3.FORWARD * 20.0
			teclas = [KEY_W]
	# Sem dash por toque duplo (no teste o relógio de parede anda mais rápido que o jogo)
	carro._ultimo_w = -10.0
	carro.dash_janela = 0.0
	for k in teclas:
		tecla(k, true)
	var menor := 1.0
	var rapida := 0.0
	for i in 60 * 4:
		await physics_frame
		# No pouso o carro já começa tombado: conta a partir do toque no chão
		if nome != "pouso" or carro.rodas_no_chao > 0 or carro.global_position.y < 0.6:
			menor = minf(menor, carro.global_basis.y.y)
		rapida = maxf(rapida, carro.linear_velocity.length())
		if i % 15 == 0 and OS.has_environment("DEBUG_CAPOTAGEM"):
			print("  %s %.2fs v=%.1f pos=%s teto=%.2f rodas=%d" % [nome, i / 60.0, carro.linear_velocity.length(), carro.global_position, carro.global_basis.y.y, carro.rodas_no_chao])
	for k in teclas:
		tecla(k, false)
	return Vector2(menor, carro.global_basis.y.y)

func _testar():
	create_timer(120.0).timeout.connect(func():
		push_error("Timeout no teste de capotagem")
		quit(1))
	cena = load("res://menu.tscn").instantiate()
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
	b.size = Vector3(600, 1, 600)
	forma.shape = b
	solo.add_child(forma)
	solo.position.y = -0.5
	cena.add_child(solo)
	carro = cena.carro
	carro.tempo_lobby = INF
	carro.em_ritual = false
	carro._esperando_chao = false
	carro.freeze = false
	# Mede só o tombo: sem dano nem explosão no meio do cenário
	carro.choque_minimo = 1000.0
	carro.choque_fatal = 1000.0
	carro.pouso_duro = 1000.0
	var sem := 0
	for nome in ["meio-fio", "rampa", "esterco", "pouso", "parede"]:
		var desligada: Vector2 = await cenario(nome, false)
		var ligada: Vector2 = await cenario(nome, true)
		print("%-9s teto.y menor/final: sem assistência %+.2f/%+.2f · com %+.2f/%+.2f" % [nome, desligada.x, desligada.y, ligada.x, ligada.y])
		if desligada.x < CAPOTOU or desligada.y < 0.9:
			sem += 1
		assert(ligada.x > CAPOTOU and ligada.y > 0.9, "%s: capotou com a assistência (%s)" % [nome, ligada])
	print("Capotou em %d de 5 cenários sem a assistência, 0 com ela" % sem)
	print("CAPOTAGEM_OK: meio-fio, rampa de um lado, esterço com nitro, pouso tombado e muro sem capotar")
	cena.queue_free()
	for i in 5:
		await process_frame
	quit()
