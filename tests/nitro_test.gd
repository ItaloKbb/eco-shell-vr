extends SceneTree
## Nitro e manejo: sem voo (o nitro fica no chão e deixa 2x mais rápido), turbos da
## pista enchendo o tanque, a traseira segurando ao acelerar na curva, bater na
## traseira de um adversário sem levar dano, limites de dano mais altos, controle no
## ar estilo GTA e o ronco do nitro no carro de outro jogador.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/nitro_test.gd

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

## Põe o carro parado num ponto da pista, olhando para a frente dela
func na_pista(mapa: MapaCorrida, carro: RigidBody3D, s: float, d := 0.0):
	var q := mapa.pista.quadro(s)
	q.origin += q.basis.x * d + q.basis.y * 0.3
	carro.teleportar(mapa.global_transform * q)
	for i in 20:
		await physics_frame

## Velocidade máxima acelerando reto por `segundos`
func arrancar(carro: RigidBody3D, segundos: float) -> float:
	var maior := 0.0
	tecla(KEY_W, true)
	for i in int(60 * segundos):
		await physics_frame
		maior = maxf(maior, carro.linear_velocity.length())
	tecla(KEY_W, false)
	return maior

func _testar():
	create_timer(240.0).timeout.connect(func():
		push_error("Timeout no teste do nitro")
		quit(1))
	var cena = load("res://menu.tscn").instantiate()
	root.add_child(cena)
	current_scene = cena
	for i in 30:
		await physics_frame
	var carro = cena.carro
	var mundos = cena.get_node("Mundos")
	var portais = cena.get_node("Portais")
	cena.ritual.estado = cena.ritual.Estado.PARTIDA
	cena.ritual._painel.hide()
	carro.em_ritual = false
	carro.freeze = false

	# Sem voo: o modo planador e as paredes sólidas não existem mais
	for antigo in ["gerando", "pode_voar", "energia", "inclinacao", "aderencia"]:
		assert(not antigo in carro, "Sobrou %s do voo" % antigo)

	await mundos.entrar_mapa(portais._portais[portais.VIOLETA], "Parque Industrial")
	var mapa: MapaCorrida = mundos.mapa_atual
	var pista: PistaCorrida = mapa.pista
	mapa.corrida.abortar()
	carro.soltar()
	assert(mapa.nitros and mapa.nitros.turbos.size() == 4)
	for turbo in mapa.nitros.turbos:
		var proj := pista.projetar(pista.to_local(turbo.global_position))
		assert(absf(proj.y) < pista.meia_util and proj.x > pista.s_largada and proj.x < pista.s_chegada)

	# Tanque vazio: o nitro não liga e avisa para pegar na pista
	carro.nitro = 0.0
	carro._alternar_nitro()
	assert(not carro.nitro_ativo)

	# Turbo da pista: passar por dentro enche o tanque e ele some até a recarga
	var turbo: Node3D = mapa.nitros.turbos[0]
	carro.teleportar(Transform3D(turbo.global_basis, turbo.global_position + turbo.global_basis.z * 4.0))
	for i in 10:
		await physics_frame
	carro.linear_velocity = -turbo.global_basis.z * 8.0
	for i in 60:
		await physics_frame
		if not turbo.visible:
			break
	assert(not turbo.visible, "Passou pelo turbo e ele não sumiu")
	assert(is_equal_approx(carro.nitro, carro.nitro_por_turbo), "Nitro: %.2f" % carro.nitro)

	# Sem nitro, a máxima do chão; com nitro, 2x e no chão o tempo todo
	await na_pista(mapa, carro, pista.s_largada + 300.0)
	var normal := await arrancar(carro, 9.0)
	await na_pista(mapa, carro, pista.s_largada + 300.0)
	carro.nitro = float(carro.nitro_max)
	tecla(KEY_E, true)
	tecla(KEY_E, false)
	assert(carro.nitro_ativo)
	assert(not carro.freeze, "O nitro não deixa o carro cinemático")
	var no_chao := true
	var maior := 0.0
	tecla(KEY_W, true)
	for i in 60 * 6:
		await physics_frame
		maior = maxf(maior, carro.linear_velocity.length())
		if i > 30 and carro.nitro_ativo and carro.rodas_no_chao < 2:
			no_chao = false
	tecla(KEY_W, false)
	print("Máxima: %.1f m/s sem nitro, %.1f m/s com nitro" % [normal, maior])
	assert(normal < carro.velocidade_max + 0.6)
	assert(maior > normal * 1.9 and maior < normal * 2.1, "Nitro deve dar ~2x")
	assert(no_chao, "Com nitro o carro segue no chão")
	assert(not carro.pista._trechos.is_empty(), "Linha de luz da traseira")
	# O tanque acaba e o nitro desliga sozinho
	assert(not carro.nitro_ativo and carro.nitro == 0.0)

	# Curva acelerando: a traseira segura (lateral primeiro no pneu)
	# (começa à direita: o círculo de esterço todo cabe na pista)
	await na_pista(mapa, carro, pista.s_largada + 600.0, 6.0)
	carro.linear_velocity = -carro.global_basis.z * 7.0
	var escorregou := 0.0
	tecla(KEY_W, true)
	tecla(KEY_A, true)
	for i in 60 * 2:
		await physics_frame
		var traseira: Vector3 = carro.global_transform * Vector3(0.0, 0.0, 0.7)
		var vel_traseira: Vector3 = carro.linear_velocity + carro.angular_velocity.cross(traseira - carro.global_position)
		escorregou = maxf(escorregou, absf(vel_traseira.dot(carro.global_basis.x)))
	tecla(KEY_W, false)
	tecla(KEY_A, false)
	print("Escorregamento lateral da traseira acelerando na curva: %.2f m/s" % escorregou)
	assert(escorregou < 1.5, "A traseira escapou acelerando: %.2f m/s" % escorregou)

	# Limites de dano: encostar não estraga; batida média tira 1 barra; nada explode na
	# velocidade normal
	await na_pista(mapa, carro, pista.s_largada + 800.0)
	carro.vida = carro.VIDA_MAX
	carro._ultimo_dano = -10.0
	carro._registrar_choque(5.0, carro.global_position)
	assert(carro.vida == carro.VIDA_MAX)
	carro._registrar_choque(8.0, carro.global_position)
	assert(carro.vida == carro.VIDA_MAX - 1)
	carro._ultimo_dano = -10.0
	carro._registrar_choque(carro.velocidade_max, carro.global_position)
	assert(carro.vida == carro.VIDA_MAX - 3 and not carro.explodindo)
	# Ataque: bater com o bico num adversário não tira vida
	carro._ultimo_dano = -10.0
	carro._registrar_choque(12.0, carro.global_position, 0.0, &"ataque")
	assert(carro.vida == carro.VIDA_MAX - 3, "Bater na traseira do rival não é dano")

	# Na física: um adversário parado à frente, o jogador acerta a traseira dele
	var rival: CarroRival = mapa.rivais[0]
	rival.ativar(true)
	var s_rival := pista.s_largada + 1000.0
	rival.estacionar(s_rival, 0.0)
	await na_pista(mapa, carro, s_rival - 25.0)
	carro.vida = carro.VIDA_MAX
	carro._ultimo_dano = -10.0
	var materiais := []
	carro.impacto.connect(func(f: float, _p: Vector3, m: StringName):
		if f > 1.5:
			materiais.append(m))
	carro.linear_velocity = -carro.global_basis.z * 12.0
	tecla(KEY_W, true)
	for i in 60 * 3:
		await physics_frame
		if materiais.has(&"rival"):
			break
	tecla(KEY_W, false)
	assert(materiais.has(&"rival"), "Não encostou no adversário")
	assert(carro.vida == carro.VIDA_MAX, "Levou dano batendo na traseira: vida %d" % carro.vida)

	# No ar, estilo GTA: analógico (aqui Shift = puxar) levanta o nariz e o carro gira de lado
	await na_pista(mapa, carro, pista.s_largada + 1200.0)
	carro.global_position += Vector3.UP * 25.0
	carro.linear_velocity = -carro.global_basis.z * 3.0
	carro.angular_velocity = Vector3.ZERO
	for i in 15:
		await physics_frame
	tecla(KEY_SHIFT, true)
	for i in 20:
		await physics_frame
	var arfagem: float = carro.angular_velocity.dot(carro.global_basis.x)
	tecla(KEY_SHIFT, false)
	assert(carro.rodas_no_chao == 0)
	assert(arfagem > 0.8, "Puxar levanta o nariz no ar: %.2f rad/s" % arfagem)
	carro.angular_velocity = Vector3.ZERO
	tecla(KEY_A, true)
	for i in 20:
		await physics_frame
	var rolagem: float = carro.angular_velocity.dot(-carro.global_basis.z)
	tecla(KEY_A, false)
	assert(rolagem < -0.8, "Esquerda gira o carro para a esquerda no ar: %.2f rad/s" % rolagem)
	print("No ar: arfagem %.2f rad/s, rolagem %.2f rad/s" % [arfagem, rolagem])

	# Horizonte travado: carro tombado 25° de lado e subindo 10°, a câmera não tomba
	# (lado na horizontal) mas acompanha a subida
	await na_pista(mapa, carro, pista.s_largada + 1400.0)
	carro.freeze = true
	var reto: Basis = carro.global_basis
	carro.global_basis = reto * Basis(Vector3.RIGHT, deg_to_rad(10.0)) * Basis(Vector3.BACK, deg_to_rad(25.0))
	carro._nivelar_visao()
	var cam: Basis = carro.camera.global_basis
	assert(absf(cam.x.y) < 0.01, "A câmera tombou junto: lado.y = %.3f" % cam.x.y)
	assert(-carro.global_basis.z.dot(-cam.z) > 0.95, "A câmera olha para onde o carro aponta")
	# (a câmera do cockpit já olha ~9° para baixo da frente do carro)
	assert((-cam.z).y > 0.0, "A câmera acompanha a subida")
	carro.global_basis = reto
	carro.freeze = false

	# Outro jogador ligou o nitro: o ronco toca no carro dele
	for i in 120:
		if SomGerador.biblioteca.has("nitro"):
			break
		await process_frame
	assert(SomGerador.biblioteca.has("nitro"), "Ronco do nitro gerado")
	var ronco: AudioStreamWAV = SomGerador.biblioteca["nitro"]
	assert(ronco.get_length() > 2.0)
	var outro := CarroFantasma.new(CarroFantasma.PINTURAS_JOGADOR[0], "OUTRO", 0, true, true)
	mapa.add_child(outro)
	outro.ver_nitro(3)
	assert(outro.find_children("*", "AudioStreamPlayer3D", false, false).is_empty(), "O primeiro valor só marca")
	outro.ver_nitro(4)
	assert(outro.find_children("*", "AudioStreamPlayer3D", false, false).size() == 1, "Ronco no carro do outro")
	assert(carro.telemetria().has("nitros"))

	print("NITRO_OK: sem voo, turbos na pista, 2x no chão, traseira firme, ataque sem dano, controle no ar e ronco em rede")
	await mundos.voltar()
	cena.queue_free()
	for i in 5:
		await process_frame
	quit()
