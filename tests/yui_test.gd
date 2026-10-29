extends SceneTree
## Assistente Yui: apresentação ao abrir, fala do lugar na primeira largada, encorajamento
## na corrida (cortando o que estava falando), barramento da voz e música abaixando.
## godot --headless --path . --xr-mode off --script res://tests/yui_test.gd

func _initialize():
	_testar.call_deferred()

func _testar():
	create_timer(40.0).timeout.connect(func():
		push_error("Timeout: teste da Yui não terminou")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	var yui: AssistenteYui = get_first_node_in_group("yui")
	assert(yui != null, "A Yui nasce junto com o mapa")
	assert(yui._textos.size() == 10, "Dez falas com legenda")
	for id in yui._textos:
		assert(ResourceLoader.exists(AssistenteYui.PASTA.path_join(id + ".wav")), "Falta a voz de " + id)
	var bus := AudioServer.get_bus_index(AssistenteYui.BARRAMENTO)
	assert(bus >= 0 and AudioServer.get_bus_effect_count(bus) == 6)
	assert(AudioServer.get_bus_effect(bus, 1) is AudioEffectPitchShift)
	assert(AudioServer.get_bus_effect(bus, 2) is AudioEffectCompressor)

	# Apresentação: dentro da esfera, depois do atraso
	await create_timer(yui.atraso_inicio + 0.5).timeout
	assert(yui.falando and yui._player.playing, "Deve se apresentar ao abrir o jogo")
	assert(yui._player.stream.resource_path.ends_with("boas_vindas.wav"))
	assert(yui._painel.visible and yui._legenda.text.begins_with("Oi, piloto!"))
	await process_frame
	assert(mapa.get_node("Musica").voz_falando, "A música abaixa enquanto ela fala")

	# Primeira largada: troca a apresentação pela fala do lugar, uma vez só
	mapa.carro.largou.emit()
	assert(yui._player.stream.resource_path.ends_with("lugar_1.wav"))
	assert(yui._fila == ["lugar_2", "lugar_3"])
	mapa.carro.largou.emit()
	assert(yui._fila == ["lugar_2", "lugar_3"], "A fala do lugar não repete")

	# Corrida: corta o resto e encoraja, sem repetir a mesma fala duas vezes seguidas
	yui.falar_corrida()
	var primeira := yui._ultima_corrida
	assert(yui._fila.is_empty() and yui._player.stream.resource_path.ends_with(primeira + ".wav"))
	assert(yui._legenda.text == yui._textos[primeira])
	yui.falar_corrida()
	assert(yui._ultima_corrida != primeira)

	# Acabou: fecha o painel depois da permanência e a música volta
	yui._player.stop()
	yui._terminou_fala()
	await process_frame
	assert(not yui.falando and not mapa.get_node("Musica").voz_falando)
	await create_timer(yui.permanencia + 0.6).timeout
	assert(not yui._painel.visible, "O painel recolhe depois da última fala")
	print("YUI_OK: apresentação, lugar na largada, encorajamento na corrida, voz e música")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
