extends SceneTree
## Encalhe no meio da corrida (Inventum): o carro tombado encostado na barreira, de
## cabeça para baixo sendo empurrado ou com a barriga apoiada em algo e as rodas no ar
## ficava parado para sempre. O vigia de encalhe (car.gd) põe de volta no asfalto, e
## quem anda normal (raspando o muro, parado de propósito) não é reposicionado.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/encalhe_test.gd

var carro
var deserto: Deserto
var pista: PistaCorrida
## Instante (s) em que a condição esperada aconteceu; -1 = ainda não (lambdas do
## GDScript capturam locais por valor, então o registro fica num membro)
var marca := -1.0

func _initialize():
	_testar.call_deferred()

func tecla(codigo: Key, pressionada: bool):
	var evento := InputEventKey.new()
	evento.keycode = codigo
	evento.physical_keycode = codigo
	evento.pressed = pressionada
	Input.parse_input_event(evento)
	Input.flush_buffered_events()

## Pose no mundo em (s, d) da pista, girada `rolagem` graus em volta da frente
## (positivo: o teto pende para a direita) e `altura` m acima do asfalto
func pose(s: float, d: float, rolagem: float, altura: float) -> Transform3D:
	var q := pista.quadro(s)
	var frente := -q.basis.z
	var base := Basis(frente.normalized(), deg_to_rad(rolagem)) * q.basis
	return deserto.global_transform * Transform3D(base, q.origin + q.basis.x * d + q.basis.y * altura)

## Lado (d) do carro na pista e se está em pé
func estado() -> Vector2:
	var proj := pista.projetar(pista.to_local(carro.global_position))
	return Vector2(proj.y, carro.global_basis.y.y)

func esperar(segundos: float, por_quadro := Callable()):
	for i in int(segundos * 60.0):
		if por_quadro.is_valid():
			por_quadro.call(i)
		await physics_frame

func _testar():
	create_timer(240.0).timeout.connect(func():
		push_error("Timeout no teste de encalhe")
		quit(1))
	var cena = load("res://menu.tscn").instantiate()
	root.add_child(cena)
	current_scene = cena
	for i in 30:
		await physics_frame
	carro = cena.carro
	var mundos = cena.get_node("Mundos")
	var portais = cena.get_node("Portais")
	cena.ritual.estado = cena.ritual.Estado.PARTIDA
	cena.ritual._painel.hide()
	carro.em_ritual = false

	await mundos.entrar_mapa(portais._portais[portais.AMBAR], "Deserto")
	deserto = mundos.deserto
	pista = deserto.pista
	deserto.corrida.abortar()
	carro.soltar()
	# Como na corrida: barreira invisível ligada nas bordas
	pista.barreira_ligada(true)
	for rival in deserto.rivais:
		rival.ativar(false)
	# Trecho reto, longe do viaduto: logo depois da largada
	var s := 60.0
	var borda := pista.largura * 0.5 - 0.7

	# 1. Tombado a 55° encostado na barreira, acelerando: volta de pé para o asfalto e anda
	carro.teleportar(pose(s, borda, 55.0, 0.9))
	tecla(KEY_W, true)
	marca = -1.0
	await esperar(6.0, func(i: int):
		if marca < 0.0 and estado().y > 0.9 and absf(estado().x) < pista.largura * 0.5:
			marca = i / 60.0)
	var desvirou := marca
	var antes: Vector3 = carro.global_position
	await esperar(3.0)
	tecla(KEY_W, false)
	var andou: float = carro.global_position.distance_to(antes)
	print("Tombado na barreira: de pé em %.1f s, depois andou %.0f m em 3 s" % [desvirou, andou])
	assert(desvirou >= 0.0, "Tombado na barreira e não saiu (cima.y %.2f, d %.1f)" % [estado().y, estado().x])
	assert(andou > 5.0, "Desvirou mas não anda: %.1f m" % andou)

	# 2. De cabeça para baixo no meio da pista, sendo sacudido (como um adversário
	# raspando): a velocidade passa de 1 m/s, mas o carro não sai do lugar
	carro.teleportar(pose(s + 80.0, 0.0, 180.0, 1.0))
	marca = -1.0
	await esperar(4.0, func(i: int):
		if i > 30 and i % 8 == 0:
			carro.linear_velocity += carro.global_basis.x * (1.6 if (i / 8) % 2 == 0 else -1.6)
		if marca < 0.0 and estado().y > 0.9:
			marca = i / 60.0)
	var em_pe := marca
	print("De cabeça para baixo e sacudido: de pé em %.1f s" % em_pe)
	assert(em_pe >= 0.0, "Capotado e sacudido não desvirou")

	# 3. Barriga apoiada num bloco, rodas no ar, sem pedal: reposicionado fora dele
	var q := pista.quadro(s + 160.0)
	var bloco := StaticBody3D.new()
	bloco.collision_layer = 1
	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(0.5, 1.1, 0.5)
	forma.shape = caixa
	bloco.add_child(forma)
	deserto.add_child(bloco)
	bloco.global_transform = deserto.global_transform * Transform3D(q.basis, q.origin + q.basis.y * 0.55)
	carro.teleportar(pose(s + 160.0, 0.0, 0.0, 1.35))
	await esperar(0.5)
	var rodas_no_ar: int = carro.rodas_no_chao
	marca = -1.0
	await esperar(5.0, func(i: int):
		if marca < 0.0 and carro.rodas_no_chao == 3 and carro.global_position.distance_to(bloco.global_position) > 1.5:
			marca = i / 60.0)
	var solto := marca
	print("Barriga no bloco (%d rodas no chão): solto em %.1f s, a %.1f m do bloco" % [rodas_no_ar, solto, carro.global_position.distance_to(bloco.global_position)])
	assert(rodas_no_ar == 0, "O cenário devia deixar as rodas no ar")
	assert(solto >= 0.0, "Encalhado no bloco não foi solto")
	bloco.queue_free()

	# 4. Sem falso positivo: raspando o muro numa curva acelerando, e parado sem pedal
	var curva := 0.0
	var maior := 0.0
	for i in PistaCorrida.AMOSTRAS:
		if absf(pista.curvaturas[i]) > maior:
			maior = absf(pista.curvaturas[i])
			curva = pista.distancias[i]
	var lado_fora := -signf(pista.curvaturas[pista.amostra_perto(pista.quadro(curva).origin)])
	carro.teleportar(pose(curva - 40.0, lado_fora * (pista.meia_util - 0.3), 0.0, 0.3))
	await esperar(0.3)
	var destravou: float = carro._ultimo_destravar
	carro.linear_velocity = -carro.global_basis.z * 14.0
	tecla(KEY_W, true)
	await esperar(5.0)
	tecla(KEY_W, false)
	tecla(KEY_S, true)
	await esperar(2.0)
	tecla(KEY_S, false)
	await esperar(5.0)
	print("Andando na curva e parado: destravou %s" % ("não" if carro._ultimo_destravar == destravou else "SIM"))
	assert(carro._ultimo_destravar == destravou, "Reposicionou quem estava andando ou parado de propósito")

	# 5. Barreira fora do raio das rodas: o chão da suspensão não enxerga a parede
	var espaco: PhysicsDirectSpaceState3D = deserto.get_world_3d().direct_space_state
	var qb := pista.quadro(s)
	var dentro: Vector3 = deserto.global_transform * (qb.origin + qb.basis.x * (pista.largura * 0.5 - 1.0) + qb.basis.y * 1.5)
	var fora: Vector3 = deserto.global_transform * (qb.origin + qb.basis.x * (pista.largura * 0.5 + 1.0) + qb.basis.y * 1.5)
	var chao := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(dentro, fora, carro.mascara_chao, [carro.get_rid()]))
	var casco := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(dentro, fora, carro.collision_mask, [carro.get_rid()]))
	assert(chao.is_empty(), "As rodas ainda enxergam a barreira como chão")
	assert(not casco.is_empty(), "O casco tem que bater na barreira")

	print("ENCALHE_OK: tombado na barreira, capotado sacudido, barriga num bloco e sem falso positivo")
	await mundos.voltar()
	cena.queue_free()
	for i in 5:
		await process_frame
	quit()
