extends SceneTree
## Fotos do telão (modo espectador) para revisar o visual: corrida simulada no Deserto
## com 2 jogadores reais e os 10 adversários, nas resoluções de TV mais comuns.
## Precisa de janela (não headless):
## godot --path . --xr-mode off --rendering-driver vulkan --script res://tests/telao_fotos.gd -- --saida=<pasta>

var esp
var saida := "user://telao_fotos/"

func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--saida="):
			saida = arg.trim_prefix("--saida=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(saida)
	_rodar.call_deferred()

func foto(nome: String):
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(saida + nome + ".png")
	print("Foto: ", saida + nome + ".png")

func _pacote(peer: int, nome: String, s: float, d: float, deserto: MapaCorrida, rivais: Array, extra := {}) -> Dictionary:
	var pista: PistaCorrida = deserto.pista
	var q := deserto.global_transform * pista.quadro(s)
	q.origin += q.basis.x * d
	var item := {"peer": peer, "nome": nome, "apelido": "Óculos %d" % peer, "estado": "correndo",
		"pos": q.origin, "rot": q.basis.get_rotation_quaternion(), "vel": 132.0, "vida": 6, "vida_max": 8,
		"explodindo": false, "na_esfera": false, "nitro": false, "mapa": "Deserto",
		"volta": 2, "voltas": 3, "posicao": 3, "total": 12, "progresso": pista.comprimento + s,
		"fase": Corrida.Fase.CORRENDO, "rivais": rivais, "t": InterpoladorRede.agora()}
	item.merge(extra, true)
	return item

func _rodar():
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	esp = load("res://espectador.tscn").instantiate()
	root.add_child(esp)
	current_scene = esp
	while not esp.pronto:
		await process_frame
	var deserto: MapaCorrida = esp.mapas["Deserto"]
	var pista: PistaCorrida = deserto.pista
	# Pelotão espalhado na reta da largada
	var rivais := []
	for i in MapaCorrida.ADVERSARIOS:
		var s := 260.0 - i * 9.0
		var q := deserto.global_transform * pista.quadro(s)
		q.origin += q.basis.x * (2.5 if i % 2 == 0 else -2.5)
		rivais.append([i + 1, q.origin, q.basis.get_rotation_quaternion(), pista.comprimento + s, 22.0])
	for resolucao in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(resolucao)
		root.size = resolucao
		for quadro in 30:
			var ana: Dictionary = _pacote(5, "Ana", 238.0, 1.0, deserto, rivais, {"posicao": 3})
			var beto: Dictionary = _pacote(9, "Bruno", 205.0, -1.5, deserto, rivais, {"posicao": 7})
			for r in rivais:
				pass
			esp.receber_quadro([ana, beto])
			await process_frame
		esp.angulo_fixo = esp.Angulo.DIAGONAL
		esp._cortar(5, esp.Angulo.DIAGONAL)
		for i in 60:
			await process_frame
		await foto("corrida_%dx%d" % [resolucao.x, resolucao.y])
	# Abertura (céu) e luzes, e o pódio e o ranking, em 1920x1080
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var grid: Dictionary = _pacote(5, "Ana", 0.0, 0.0, deserto, rivais, {"fase": Corrida.Fase.CONTROLES, "volta": 0})
	grid.pos = deserto.largada(MapaCorrida.ADVERSARIOS).origin
	esp.receber_quadro([grid])
	for i in 60:
		await process_frame
	await foto("abertura_vinheta")
	for i in 240:
		await process_frame
	await foto("abertura_ceu")
	grid.fase = Corrida.Fase.CONTAGEM
	esp.receber_quadro([grid])
	for i in 150:
		await process_frame
	await foto("abertura_luzes")
	esp.receber_quadro([])
	for i in 10:
		await process_frame
	esp._podio_de_ensaio()
	for i in 240:
		await process_frame
	await foto("podio")
	esp._fechar_podio()
	esp._abrir_ranking(["ANA"])
	for i in 90:
		await process_frame
	await foto("ranking")
	quit()
