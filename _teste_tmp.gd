extends SceneTree
func tecla(k: Key, apertada: bool):
	var e := InputEventKey.new(); e.keycode = k; e.physical_keycode = k; e.pressed = apertada
	Input.parse_input_event(e)
func dirigir_ate(carro, mundos, portal: Portal, lateral: float, segundos: float) -> String:
	var hw = carro.hex_world
	var c := portal.global_position
	var dir := Vector3(1, 0, 0)
	var inicio := c - dir * 30.0 + Vector3(0, 0, lateral)
	inicio.y = hw.altura(inicio.x, inicio.z) + 0.3
	carro.teleportar(Transform3D(Basis.looking_at(dir, Vector3.UP), inicio), true)
	for i in 30: await physics_frame
	tecla(KEY_W, true)
	var resultado := "nada"
	var menor := INF
	for i in int(segundos * 60):
		await physics_frame
		var pc: Vector3 = portal.global_position + Vector3.UP * Portal.ALTURA
		menor = minf(menor, (carro.global_transform * Vector3(0, 0.4, 0)).distance_to(pc))
		if mundos._trocando or mundos.no_deserto:
			resultado = "ENTROU no deserto"
			break
		if carro._aviso == "PORTAL FECHADO" and carro._aviso_tempo > 0.0:
			resultado = "aviso PORTAL FECHADO"
			break
	tecla(KEY_W, false)
	return resultado + " (menor distancia ao centro %.1f m)" % menor
func _initialize():
	var cena: Node = load("res://menu.tscn").instantiate()
	root.add_child(cena)
	var carro = cena.get_node("Carro")
	for i in 200: await process_frame
	var mundos = cena.get_node("Mundos")
	var portais = cena.get_node("Portais")
	var ambar: Portal
	var outro: Portal
	for p in get_nodes_in_group("portais"):
		if p.cor == portais.CORES[3]: ambar = p
		elif p.cor == portais.CORES[0]: outro = p
	print("outra cor, de frente: ", await dirigir_ate(carro, mundos, outro, 0.0, 8.0))
	print("ambar, de raspão (4 m ao lado): ", await dirigir_ate(carro, mundos, ambar, 4.0, 8.0))
	quit()
