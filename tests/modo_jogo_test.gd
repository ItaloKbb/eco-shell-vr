extends SceneTree
## Modo GAME (notebook jogando no teclado): a tela de escolha do PC tem o terceiro
## cartão e o servidor chama o aparelho de "Notebook N" (e o Quest continua "Óculos N").
## godot --headless --path . --xr-mode off --script res://tests/modo_jogo_test.gd

func _initialize():
	_testar.call_deferred()

func _testar():
	var falhas := 0

	var escolha = load("res://escolha_modo.tscn").instantiate()
	root.add_child(escolha)
	await process_frame
	var titulos := []
	for b in escolha.find_children("*", "Button", true, false):
		for r in b.find_children("*", "Label", true, false):
			titulos.append(r.text)
	if "GAME" not in titulos:
		push_error("Tela de escolha sem o cartão GAME: %s" % [titulos])
		falhas += 1
	escolha.queue_free()

	# Sem unique_id não grava user://dispositivos.json
	var dispositivos = root.get_node("Dispositivos")
	dispositivos.adicionar(9001, "10.0.0.1")
	dispositivos.adicionar(9002, "10.0.0.2")
	dispositivos.adicionar(9003, "10.0.0.3")
	var notebook: String = dispositivos.registrar(9001, {"tipo": "notebook"})
	var quest: String = dispositivos.registrar(9002, {"tipo": "oculos"})
	var antigo: String = dispositivos.registrar(9003, {})
	if not notebook.begins_with("Notebook "):
		push_error("Notebook registrado como '%s'" % notebook)
		falhas += 1
	if not quest.begins_with("Óculos ") or not antigo.begins_with("Óculos "):
		push_error("Quest registrado como '%s' / '%s'" % [quest, antigo])
		falhas += 1
	for peer in [9001, 9002, 9003]:
		dispositivos.remover(peer)

	print("modo_jogo_test: %s" % ("OK" if falhas == 0 else "%d falha(s)" % falhas))
	quit(falhas)
