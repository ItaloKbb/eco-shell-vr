extends SceneTree
## Vale das Turbinas: portal verde abre o mapa, pista com relevo sem afundar no terreno,
## obstáculos móveis (lógica, batida do jogador e adversários desviando) e volta.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/turbinas_test.gd

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
	create_timer(240.0).timeout.connect(func():
		push_error("Timeout no teste do Vale das Turbinas")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var carro = mapa.carro
	var mundos = mapa.get_node("Mundos")
	var musica = mapa.get_node("Musica")
	var portais = mapa.get_node("Portais")
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	carro.em_ritual = false

	# Portal verde: marcador e destino
	var verde: Portal = portais._portais[portais.VERDE]
	assert(verde.destino_corrida == "Vale das Turbinas")
	assert(verde.has_node("MarcadorCorrida"))
	await mundos.entrar_mapa(verde, "Vale das Turbinas")
	var vale: ValeTurbinas = mundos.turbinas
	assert(vale != null and mundos.mapa_atual == vale and not mundos.no_deserto)
	assert(carro.hex_world == vale and not carro.pode_voar)
	var corrida: Corrida = vale.corrida
	var pista: PistaCorrida = vale.pista
	var obstaculos: ObstaculosPista = vale.obstaculos
	assert(pista is PistaTurbinas)
	assert(corrida.fase == Corrida.Fase.CONTROLES and carro.segurado)
	assert(vale.rivais.size() == 10)
	assert(obstaculos.obstaculos.size() == 6, "Seis obstáculos na volta")
	assert(vale.trafego.obstaculos == obstaculos)
	var tocando: AudioStreamPlayer = musica._players[musica._atual]
	assert(tocando.stream.resource_path == "res://musicas/musica_2.mp3", "Música própria do vale")
	var yui: AssistenteYui = root.get_tree().get_first_node_in_group("yui")
	assert(yui._player.stream.resource_path.ends_with("turbinas.wav"), "A Yui apresenta o vale primeiro")
	assert(yui._fila.size() == 1 and yui._fila[0].begins_with("corrida_"))

	# Pista: curvas abertas o bastante, relevo de verdade, sem afundar no terreno
	var menor_raio := INF
	var mais_alto := -INF
	var mais_baixo := INF
	for i in PistaCorrida.AMOSTRAS:
		var k := absf(pista.curvaturas[i])
		if k > 0.0001:
			menor_raio = minf(menor_raio, 1.0 / k)
		var p: Vector3 = pista.pontos[i]
		mais_alto = maxf(mais_alto, p.y)
		mais_baixo = minf(mais_baixo, p.y)
		for lado: float in [-1.0, 0.0, 1.0]:
			var borda: Vector3 = vale.global_transform * (p + pista.lados[i] * PistaCorrida.LARGURA * 0.5 * lado)
			assert(borda.y - vale.altura(borda.x, borda.z) > 0.05, "Terreno atravessa a pista na amostra %d" % i)
	assert(menor_raio > 18.0, "Curva fechada demais: raio %.1f m" % menor_raio)
	assert(mais_alto - mais_baixo > 6.0, "A pista deve subir e descer (desnível %.1f m)" % (mais_alto - mais_baixo))
	assert(pista.comprimento > 650.0 and pista.comprimento < 850.0, "Volta de %.0f m" % pista.comprimento)
	# Grid num trecho quase plano e reto
	for posicao in MapaCorrida.ADVERSARIOS + 1:
		var vaga: Vector2 = pista.grid_sd(posicao)
		assert(absf(pista.curvatura(vaga.x)) < 0.012, "Vaga %d numa curva" % posicao)
	# O portal de volta fica longe da pista (o puxão não alcança)
	var portal_local: Vector3 = vale.portal_volta.position
	var proj := pista.projetar(portal_local)
	assert(absf(proj.y) > Portal.ALCANCE_PUXAO + 10.0)

	# Lógica dos obstáculos
	var comportas: Comportas
	var varredoras: Array[TurbinaVarredora] = []
	var pendulos: Array[PenduloCarga] = []
	for o in obstaculos.obstaculos:
		if o is Comportas:
			comportas = o
		elif o is TurbinaVarredora:
			varredoras.append(o)
		elif o is PenduloCarga:
			pendulos.append(o)
	assert(comportas != null and varredoras.size() == 2 and pendulos.size() == 3)
	# Comportas: nunca as três abertas, quase sempre alguma aberta, todas abrem
	var abriu := [false, false, false]
	var com_saida := 0
	var amostras := 0
	var t := 0.0
	while t < 30.0:
		var abertas := 0
		for i in Comportas.FAIXAS:
			if comportas.abertura(i, t) >= Comportas.LIVRE:
				abertas += 1
				abriu[i] = true
		assert(abertas <= 2)
		if abertas > 0:
			com_saida += 1
		amostras += 1
		t += 0.05
	assert(abriu == [true, true, true])
	assert(float(com_saida) / amostras > 0.9, "As comportas deixam passagem quase sempre")
	# Pilar entre as faixas sempre bloqueia
	assert(comportas.bloqueia(0.0, Comportas.LARGURA_FAIXA * 0.5, 1.0))
	# Varredoras em lados opostos; cada uma deixa uma faixa estreita sempre livre do
	# outro lado, e as faixas que ela varre abrem e fecham
	assert(varredoras[0].lado == -varredoras[1].lado)
	for v in varredoras:
		var faixa_livre := -v.lado * 4.4
		t = 0.0
		while t < 10.0:
			var ds := -v.alcance_s
			while ds <= v.alcance_s:
				assert(not v.bloqueia(ds, faixa_livre, t), "A faixa de escape da varredora deve ficar livre")
				ds += 0.5
			t += 0.1
		for d: float in [0.0, v.lado * 2.5]:
			var livre := false
			var varrida := false
			t = 0.0
			while t < 10.0:
				if v.bloqueia(0.0, d, t):
					varrida = true
				else:
					livre = true
				t += 0.05
			assert(livre and varrida, "A faixa %.1f deve abrir e fechar" % d)
	# Pêndulo: a carga passa pelo meio e vai até perto das bordas
	var maior_x := 0.0
	t = 0.0
	while t < 9.0:
		maior_x = maxf(maior_x, absf(pendulos[0].carga(t).x))
		t += 0.05
	assert(maior_x > 4.5 and maior_x < PistaCorrida.LARGURA * 0.5)

	# Largada
	tecla(KEY_ENTER, true)
	tecla(KEY_ENTER, false)
	for i in 240:
		if corrida.fase == Corrida.Fase.CORRENDO:
			break
		await physics_frame
	assert(corrida.fase == Corrida.Fase.CORRENDO and not carro.segurado)

	# Jogador batendo numa comporta fechada: volta para trás, perde 1 barra, não atravessa
	var agora := obstaculos.tempo
	var faixa := -1
	for i in Comportas.FAIXAS:
		var fechada := true
		var x := 0.0
		while x < 2.0:
			if comportas.abertura(i, agora + x) >= Comportas.LIVRE * 0.5:
				fechada = false
			x += 0.1
		if fechada:
			faixa = i
	assert(faixa >= 0, "Deve haver uma comporta fechada pelos próximos 2 s")
	var d_faixa: float = (faixa - 1) * Comportas.LARGURA_FAIXA
	var antes: Transform3D = pista.quadro(comportas.s0 - 6.0)
	antes.origin += antes.basis.x * d_faixa + antes.basis.y * 0.3
	carro.teleportar(vale.global_transform * antes)
	for i in 3:
		await physics_frame
	var vida_antes: int = carro.vida
	var batidas: int = obstaculos.batidas_jogador
	var frente: Vector3 = -(vale.global_transform * antes).basis.z
	for i in 90:
		carro.linear_velocity = frente * 9.0 if obstaculos.batidas_jogador == batidas else carro.linear_velocity
		await physics_frame
		if obstaculos.batidas_jogador > batidas and i > 10:
			break
	assert(obstaculos.batidas_jogador == batidas + 1, "O carro deveria bater na comporta")
	assert(carro.vida == vida_antes - 1, "Uma barra de dano por batida (vida %d -> %d)" % [vida_antes, carro.vida])
	assert(carro.linear_velocity.dot(frente) < 0.0, "A batida joga o carro para trás")
	var ds_carro: float = wrapf(vale.trafego.jogador.s - comportas.s0, -pista.comprimento * 0.5, pista.comprimento * 0.5)
	assert(ds_carro < 0.0, "O carro não atravessa a comporta fechada")

	# Adversários: correm uma volta e meia desviando; quase ninguém bate
	carro.teleportar(vale.global_transform * pista.quadro(5.0).translated(Vector3.UP * 0.3))
	carro.freeze = true
	var inicio := obstaculos.tempo
	var quadros := 0
	while obstaculos.tempo - inicio < 100.0:
		await physics_frame
		quadros += 1
		if OS.has_environment("DEBUG_OBSTACULOS") and quadros % 120 == 0:
			var lento: CarroRival = vale.rivais[0]
			for rival in vale.rivais:
				if rival.progresso < lento.progresso:
					lento = rival
			var perto: ObstaculoPista = obstaculos._proximo(lento.s)
			print("t=%.0f lento %s prog=%.0f s=%.0f d=%.1f v=%.1f valvo=%.1f estado=%s obst=%s falta=%.1f plano=%s" % [obstaculos.tempo - inicio, lento.perfil.nome, lento.progresso, lento.s, lento.d, lento.v, lento.v_alvo, IARival.Estado.keys()[lento.ia.estado], perto.get_script().get_global_name() if perto else "-", -obstaculos._ds(perto, lento.s) if perto else 0.0, obstaculos._plano.get(lento, []).slice(2)])
	var menor_progresso := INF
	var progressos := []
	for rival in vale.rivais:
		menor_progresso = minf(menor_progresso, rival.progresso)
		progressos.append("%s %.0f" % [rival.perfil.nome, rival.progresso])
	print(", ".join(progressos))
	print("Turbinas: menor progresso %.0f m de %.0f, batidas dos rivais %d" % [menor_progresso, pista.comprimento, obstaculos.batidas_rivais])
	# Esperar a vez nas comportas faz parte: só não pode ninguém travar
	assert(menor_progresso > pista.comprimento, "Algum adversário travou nos obstáculos")
	assert(obstaculos.batidas_rivais < 25, "Adversários batendo demais: %d" % obstaculos.batidas_rivais)
	assert(obstaculos.batidas_rivais > 0, "Os distraídos deveriam bater de vez em quando")

	await mundos.voltar()
	assert(mundos.mapa_atual == null and carro.hex_world == mapa.get_node("HexWorld"))
	assert(corrida.fase == Corrida.Fase.PARADA and not musica.em_corrida)
	print("TURBINAS_OK: portal verde, pista com relevo, comportas, varredoras, guindastes, batida e rivais desviando")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
