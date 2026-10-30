extends SceneTree
## Vão embaixo da pista: no Vale das Turbinas a pista corre num aterro 1,5 a 6 m acima do
## terreno, e a saia de concreto é só visual. Quem saía pelo lado sem muro passava por
## baixo da pista. Agora o acostamento (rampa com colisão) fecha o vão, quem sai da pista
## consegue voltar subindo por ele e, se ainda assim o carro parar embaixo do asfalto,
## a rede de segurança o põe de volta em cima. No Deserto, quem passa embaixo do viaduto
## não é puxado para cima dele.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/vao_pista_test.gd

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
	create_timer(180.0).timeout.connect(func():
		push_error("Timeout no teste do vão da pista")
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

	await mundos.entrar_mapa(portais._portais[portais.VERDE], "Vale das Turbinas")
	var vale: ValeTurbinas = mundos.turbinas
	var pista: PistaCorrida = vale.pista
	vale.corrida.abortar()
	carro.soltar()
	var espaco: PhysicsDirectSpaceState3D = vale.get_world_3d().direct_space_state

	# 1. Vão fechado: 1,2 m para fora da borda (dos dois lados, a volta toda) o chão
	# fica logo abaixo do asfalto, não 1,5 a 6 m
	var maior := 0.0
	for i in range(0, PistaCorrida.AMOSTRAS, 3):
		for lado: float in [-1.0, 1.0]:
			var borda: Vector3 = vale.global_transform * (pista.pontos[i] + pista.lados[i] * pista.largura * 0.5 * lado)
			var fora: Vector3 = (vale.global_basis * Vector3(pista.lados[i].x, 0.0, pista.lados[i].z)).normalized() * lado
			var p: Vector3 = borda + fora * 1.2
			var achou := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 20.0, 1))
			assert(not achou.is_empty())
			maior = maxf(maior, borda.y - achou.position.y)
	print("Maior desnível 1,2 m fora da borda: %.2f m" % maior)
	assert(maior < 0.8, "Ainda tem vão na borda da pista: %.2f m" % maior)

	# 2. Saiu da pista pelo lado sem muro: volta subindo pelo acostamento
	var s := 0.0
	var lado := 0.0
	for i in range(0, PistaCorrida.AMOSTRAS, 4):
		for l: float in [-1.0, 1.0]:
			# Sem muro (dentro da curva) e com bastante aterro
			if pista.inclinacoes[i] * l >= -0.05 and pista.pontos[i].y - vale.altura(pista.pontos[i].x + vale.global_position.x, pista.pontos[i].z + vale.global_position.z) + vale.global_position.y > 2.0:
				s = pista.distancias[i]
				lado = l
	assert(lado != 0.0, "Achar um trecho sem muro com aterro alto")
	var q := pista.quadro(s)
	var fora_l: Vector3 = Vector3(q.basis.x.x, 0.0, q.basis.x.z).normalized() * lado
	var ponto: Vector3 = q.origin + fora_l * (pista.largura * 0.5 + 7.0)
	ponto.y = vale.altura(ponto.x + vale.global_position.x, ponto.z + vale.global_position.z) - vale.global_position.y + 3.0
	# Olhando para a pista
	carro.teleportar(vale.global_transform * Transform3D(Basis.looking_at(-fora_l, Vector3.UP), ponto))
	for i in 60:
		await physics_frame
	tecla(KEY_W, true)
	var subiu := false
	for i in 60 * 5:
		await physics_frame
		var proj := pista.projetar(pista.to_local(carro.global_position))
		var acima: float = (pista.to_local(carro.global_position) - pista.quadro(proj.x).origin).dot(pista.quadro(proj.x).basis.y)
		if absf(proj.y) < pista.largura * 0.5 - 1.0 and acima > -0.3:
			subiu = true
			break
	tecla(KEY_W, false)
	assert(subiu, "O carro deve voltar para a pista subindo pelo acostamento")

	# 3. Rede de segurança: carro largado embaixo do asfalto volta para cima dele
	q = pista.quadro(s)
	var embaixo: Transform3D = vale.global_transform * Transform3D(q.basis, q.origin - q.basis.y * 1.6)
	carro.global_transform = embaixo
	carro.linear_velocity = Vector3.ZERO
	carro.angular_velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	var local: Vector3 = pista.to_local(carro.global_position)
	var acima: float = (local - pista.quadro(s).origin).dot(pista.quadro(s).basis.y)
	print("Depois da rede de segurança: %.2f m acima do asfalto" % acima)
	assert(acima > -0.3, "O carro ficou embaixo da pista")

	await mundos.voltar()
	for i in 10:
		await physics_frame

	# 4. Deserto: andar embaixo do viaduto não teleporta para cima dele
	await mundos.entrar_mapa(portais._portais[portais.AMBAR], "Deserto")
	var deserto: Deserto = mundos.deserto
	deserto.corrida.abortar()
	carro.soltar()
	var circuito: PistaCorrida = deserto.pista
	var baixo := -1
	for i in PistaCorrida.AMOSTRAS:
		if Vector2(circuito.pontos[i].x, circuito.pontos[i].z).length() < 3.0 and circuito.pontos[i].y < 0.5:
			baixo = i
	assert(baixo >= 0, "Achar a pista de baixo no cruzamento")
	var antes := circuito.quadro(circuito.distancias[baixo] - 30.0)
	carro.teleportar(deserto.global_transform * Transform3D(antes.basis, antes.origin + antes.basis.y * 0.3))
	for i in 20:
		await physics_frame
	carro.linear_velocity = -carro.global_basis.z * 10.0
	tecla(KEY_W, true)
	var mais_alto := 0.0
	for i in 60 * 3:
		await physics_frame
		mais_alto = maxf(mais_alto, carro.global_position.y - deserto.global_position.y)
	tecla(KEY_W, false)
	print("Pista de baixo do Deserto: maior altura %.2f m (viaduto a %.1f m)" % [mais_alto, PistaCorrida.ALTURA_VIADUTO])
	assert(mais_alto < 2.0, "Passou embaixo do viaduto e foi parar em cima dele")

	print("VAO_PISTA_OK: acostamento fecha o vão, dá para voltar à pista, rede de segurança e viaduto do Deserto")
	await mundos.voltar()
	cena.queue_free()
	for i in 5:
		await process_frame
	quit()
