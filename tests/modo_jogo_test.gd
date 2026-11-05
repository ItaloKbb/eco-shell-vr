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

	# Notebooks clonados (mesmo id) conectados juntos não dividem o apelido
	var guardados: Dictionary = dispositivos._apelidos.duplicate()
	dispositivos._apelidos["clone-teste"] = "Notebook 1"
	dispositivos.adicionar(9004, "10.0.0.4")
	dispositivos.adicionar(9005, "10.0.0.5")
	var primeiro: String = dispositivos.registrar(9004, {"tipo": "notebook", "unique_id": "clone-teste"})
	var segundo: String = dispositivos.registrar(9005, {"tipo": "notebook", "unique_id": "clone-teste"})
	if primeiro == segundo:
		push_error("Dois aparelhos conectados com o mesmo apelido '%s'" % primeiro)
		falhas += 1
	for peer in [9004, 9005]:
		dispositivos.remover(peer)
	dispositivos._apelidos = guardados

	# Nome digitado na espera: guardado como sugestão e apagado ao liberar
	dispositivos.adicionar(9006, "10.0.0.6")
	dispositivos.sugerir_nome(9006, " ANA ")
	var sugerido: String = dispositivos.obter(9006).nome_sugerido
	dispositivos.liberar(9006, "ANA")
	if sugerido != "ANA" or dispositivos.obter(9006).nome_sugerido != "":
		push_error("Sugestão de nome: '%s' / '%s'" % [sugerido, dispositivos.obter(9006).nome_sugerido])
		falhas += 1
	dispositivos.remover(9006)

	print("modo_jogo_test: %s" % ("OK" if falhas == 0 else "%d falha(s)" % falhas))
	quit(falhas)
