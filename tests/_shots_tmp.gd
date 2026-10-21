extends SceneTree
const DIR := "C:/Users/italo/AppData/Local/Temp/eco_shots/"
func foto(nome: String):
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(DIR + "ia_" + nome + ".png")
func _initialize():
	_t.call_deferred()
func _t():
	root.size = Vector2i(1280, 720)
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa); current_scene = mapa
	for i in 60: await physics_frame
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	mapa.get_node("EsferaInicial").hide()
	var carro = mapa.carro
	carro.em_ritual = false
	var mundos = mapa.get_node("Mundos")
	await mundos.entrar_deserto(mapa.get_node("Portais")._portais[mapa.get_node("Portais").AMBAR])
	var d = mundos.deserto
	d.corrida._contar()
	while d.corrida.fase != Corrida.Fase.CORRENDO: await physics_frame
	for i in 90: await physics_frame
	await foto("1_largada")
	# Jogador parado no laço da esquerda, olhando para trás para ver o pelotão chegar
	carro.freeze = true
	carro.teleportar(d.global_transform * d.pista.quadro(d.pista.comprimento * 0.3))
	carro._olhar.y = 2.6
	carro.camera.rotation = Vector3(-0.05, 2.6, 0)
	var feitas := 0
	var ataque := false
	d.trafego.jogador_atacado.connect(func(_r): ataque = true)
	for i in 60 * 40:
		await physics_frame
		var perto := 0
		for r in d.rivais:
			var ds = d.trafego.delta_s(d.trafego.jogador, r.info)
			if ds < -4.0 and ds > -25.0:
				perto += 1
		if perto >= 3 and feitas == 0:
			await foto("2_pelotao")
			feitas = 1
		if ataque and feitas == 1:
			await foto("3_ataque")
			feitas = 2
			break
	quit()
