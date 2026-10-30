extends SceneTree
## Corrida inteira dos adversários, com o jogador parado na pista (obstáculo e alvo).
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/ia_rivais_test.gd

const PASSOS_MAX := 60 * 260

func _initialize():
	_testar.call_deferred()

func _testar():
	create_timer(240.0).timeout.connect(func():
		push_error("Timeout no teste da IA")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var carro = mapa.carro
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	carro.em_ritual = false
	var mundos = mapa.get_node("Mundos")
	await mundos.entrar_deserto(mapa.get_node("Portais")._portais[mapa.get_node("Portais").AMBAR])
	var deserto: Deserto = mundos.deserto
	var corrida: Corrida = deserto.corrida
	var trafego: TrafegoCorrida = deserto.trafego
	var pista: PistaCorrida = deserto.pista

	# Personalidades distintas e todos os estilos presentes
	var estilos := {}
	for rival in deserto.rivais:
		estilos[rival.perfil.estilo] = true
	assert(estilos.size() == PerfilPiloto.Estilo.size())

	# Parados até o VAI!
	corrida._contar()
	for i in 60:
		await physics_frame
	for rival in deserto.rivais:
		assert(rival.v == 0.0 and rival.ia.estado == IARival.Estado.PARADO)
	while corrida.fase != Corrida.Fase.CORRENDO:
		await physics_frame

	# Jogador estacionado no meio da pista, no laço da esquerda (longe do portal de volta)
	var parada := pista.quadro(pista.comprimento * 0.65)
	# Congela antes: encaixar o carro direto na curva inclinada contaria como batida
	carro.freeze = true
	carro.teleportar(deserto.global_transform * parada)

	var ataques := []
	trafego.jogador_atacado.connect(func(rival: CarroRival): ataques.append(rival.perfil.nome))
	var vistos := {}
	var sobreposicoes := 0
	var fora := 0
	var tempo_chegada := {}
	var maior_turbo := 0
	for passo in PASSOS_MAX:
		await physics_frame
		for rival in deserto.rivais:
			vistos[rival.ia.estado] = true
			maior_turbo = maxi(maior_turbo, rival.turbos_usados)
			if absf(rival.d) > PistaCorrida.MEIA_UTIL + 0.01:
				fora += 1
			if rival.terminou and not tempo_chegada.has(rival.perfil.nome):
				tempo_chegada[rival.perfil.nome] = trafego.tempo_corrida
		# Contato fundo entre adversários (mais que um raspão) não pode persistir
		for i in deserto.rivais.size():
			for j in range(i + 1, deserto.rivais.size()):
				var a: CarroRival = deserto.rivais[i]
				var b: CarroRival = deserto.rivais[j]
				if absf(trafego.delta_s(a.info, b.info)) < 1.5 and absf(a.d - b.d) < 0.4:
					sobreposicoes += 1
		if trafego.chegada.size() == deserto.rivais.size():
			break
		if passo == 60 * 30:
			for rival in deserto.rivais:
				assert(rival.progresso > 150.0, "%s andou só %.0f m em 30 s" % [rival.perfil.nome, rival.progresso])

	var nomes := []
	for estado in vistos:
		nomes.append(IARival.Estado.keys()[estado])
	print("Estados vistos: ", nomes)
	print("Ataques no jogador: ", ataques.size(), " ", ataques)
	print("Chegada: ")
	for info in trafego.chegada:
		print("  %-8s %6.1f s  (%s)" % [info.nome(), tempo_chegada[info.nome()], PerfilPiloto.Estilo.keys()[info.rival.perfil.estilo]])
	print("Sobreposições: ", sobreposicoes, "  fora da pista: ", fora)

	assert(trafego.chegada.size() == 10, "Só %d chegaram" % trafego.chegada.size())
	for estado in [IARival.Estado.CORRER, IARival.Estado.ULTRAPASSAR, IARival.Estado.ATACAR, IARival.Estado.VOLTA_LENTA]:
		assert(vistos.has(estado), "Nunca entrou em %s" % IARival.Estado.keys()[estado])
	assert(not ataques.is_empty(), "Nenhum brigão acertou o jogador")
	var usuarios_turbo := 0
	var total_turbo := 0
	for rival in deserto.rivais:
		total_turbo += rival.turbos_usados
		if rival.turbos_usados > 0:
			usuarios_turbo += 1
	assert(usuarios_turbo >= 7, "Só %d rivais usaram turbo" % usuarios_turbo)
	assert(total_turbo >= 12 and maior_turbo >= 2, "Turbos insuficientes: %d" % total_turbo)
	for nome in ataques:
		var perfil: PerfilPiloto = deserto.rivais.filter(func(r): return r.perfil.nome == nome)[0].perfil
		assert(perfil.estilo == PerfilPiloto.Estilo.BRIGAO, "%s atacou sem ser brigão" % nome)
	assert(fora == 0)
	assert(sobreposicoes < 60, "Carros atravessando uns aos outros: %d" % sobreposicoes)
	# 3 voltas de ~630 m, reta a ~24 m/s e curvas no ritmo de antes: ~1 a 2 minutos
	var primeiro: float = tempo_chegada[trafego.chegada[0].nome()]
	assert(primeiro > 50.0 and primeiro < 130.0, "Tempo do vencedor fora do esperado: %.1f" % primeiro)
	print("IA_OK: 10 adversários, ultrapassagens, ataques e %d turbos táticos" % total_turbo)
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
