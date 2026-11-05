extends SceneTree
var saida := ""
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--saida="):
			saida = arg.trim_prefix("--saida=") + "/"
	_r.call_deferred()
func foto(nome):
	for i in 4: await process_frame
	root.get_texture().get_image().save_png(saida + nome + ".png")
	print("Foto: ", nome)
func _r():
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	var esp = load("res://espectador.tscn").instantiate()
	root.add_child(esp)
	while not esp.pronto: await process_frame
	print("pronto")
	esp._podio_de_ensaio()
	print("podio aberto, estado ", esp.estado)
	for i in 240: await process_frame
	await foto("podio")
	esp._fechar_podio()
	esp._abrir_ranking(["VOLT"])
	for i in 90: await process_frame
	await foto("ranking")
	quit()
