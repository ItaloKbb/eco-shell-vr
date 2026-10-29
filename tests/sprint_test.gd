extends SceneTree
## Pistas ponta a ponta: o portal ciano abre o Sistema S (S largo) e o violeta o Parque
## Industrial (reta com rampas). Traçado sem se cruzar, grid atrás da largada, portões até
## a bandeirada, adversários chegando e estacionando antes do fim, salto da rampa (jogador
## e adversários) e o portal de volta no fim.
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/sprint_test.gd

## Passos extras da IA por quadro (a corrida inteira dos adversários sem esperar o relógio)
const ACELERA_IA := 9
const PASSOS_MAX := 60 * 260

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
	create_timer(280.0).timeout.connect(func():
		push_error("Timeout no teste das sprints")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var carro = mapa.carro
	var mundos = mapa.get_node("Mundos")
	var portais = mapa.get_node("Portais")
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	carro.em_ritual = false

	for caso in [[portais.CIANO, "Sistema S", PistaSistemaS.LARGURA_S, 1500.0, 1750.0],
			[portais.VIOLETA, "Parque Industrial", PistaIndustrial.LARGURA_I, 1790.0, 1830.0]]:
		var portal: Portal = portais._portais[caso[0]]
		assert(portal.destino_corrida == caso[1])
		assert(portal.has_node("MarcadorCorrida"))
		await mundos.entrar_mapa(portal, caso[1])
		var sprint: MapaCorrida = mundos.mapa_atual
		assert(sprint != null and sprint.nome == caso[1])
		var pista: PistaCorrida = sprint.pista
		var corrida: Corrida = sprint.corrida
		var trafego: TrafegoCorrida = sprint.trafego

		# Ponta a ponta, uma "volta" e a largura da pista
		assert(pista.aberta and pista.voltas == 1 and pista.total_portoes() == PistaCorrida.PORTOES + 1)
		assert(is_equal_approx(pista.largura, caso[2]) and is_equal_approx(pista.meia_util, caso[2] * 0.5 - 0.9))
		var distancia := pista.distancia_corrida()
		assert(distancia > caso[3] and distancia < caso[4], "%s: corrida de %.0f m" % [caso[1], distancia])
		print("%s: %.0f m de corrida, %.0f m de pista" % [caso[1], distancia, pista.comprimento])
		# O traçado não passa perto dele mesmo (muros não se encostam)
		var n := PistaCorrida.AMOSTRAS
		for i in range(0, n, 3):
			for j in range(i + 1, n, 3):
				if pista.distancias[j] - pista.distancias[i] > pista.largura * 3.0:
					assert(pista.pontos[i].distance_to(pista.pontos[j]) > pista.largura + 4.0,
						"%s: amostras %d e %d se encostam" % [caso[1], i, j])
		# Grid inteiro atrás da linha, dentro da pista, sem vagas sobrepostas
		for vaga in MapaCorrida.ADVERSARIOS + 1:
			var sd := pista.grid_sd(vaga)
			assert(sd.x < pista.s_largada and sd.x > 0.0 and absf(sd.y) < pista.meia_util)
		var frente: Vector3 = -carro.global_basis.z
		for i in sprint.rivais.size():
			var rival: CarroRival = sprint.rivais[i]
			assert((rival.global_position - carro.global_position).dot(frente) > 3.0)
			assert(rival.progresso < 0.0, "No grid o progresso é negativo")
		# Portal de volta depois da chegada, longe do puxão de quem ainda corre
		var chegada_mundo: Vector3 = sprint.global_transform * pista.pontos[pista.amostra_em(pista.s_chegada)]
		assert(sprint.portal_volta.global_position.distance_to(chegada_mundo) > Portal.ALCANCE_PUXAO + 30.0)

		# Largada
		tecla(KEY_ENTER, true)
		tecla(KEY_ENTER, false)
		for i in 240:
			if corrida.fase == Corrida.Fase.CORRENDO:
				break
			await physics_frame
		assert(corrida.fase == Corrida.Fase.CORRENDO)
		for i in 2:
			await process_frame
		assert(carro.painel_corrida.begins_with("SPRINT POS"), carro.painel_corrida)

		# Adversários correndo até o fim (com a IA acelerada) e o jogador parado no grid
		carro.freeze = true
		var saltaram := {}
		var tetos := {}
		for passo in PASSOS_MAX:
			await physics_frame
			for k in ACELERA_IA:
				trafego._physics_process(1.0 / 60.0)
			for rival in sprint.rivais:
				if pista.rampas and pista.rampas.altura(rival) > RampasPista.ALTURA + 0.1:
					saltaram[rival.numero] = true
				tetos[rival.numero] = maxf(tetos.get(rival.numero, 0.0), rival.s)
			if trafego.chegada.size() == sprint.rivais.size():
				break
		assert(trafego.chegada.size() == sprint.rivais.size(), "%s: só %d adversários chegaram" % [caso[1], trafego.chegada.size()])
		# Estacionam depois da chegada, encostados nos muros, antes do fim
		for i in 60 * 6:
			await physics_frame
			for k in ACELERA_IA:
				trafego._physics_process(1.0 / 60.0)
		for rival in sprint.rivais:
			assert(rival.s > pista.s_chegada and rival.s < pista.comprimento - PistaCorrida.FOLGA_FIM)
			assert(rival.v < 0.5, "%s: adversário %d não parou (%.1f m/s)" % [caso[1], rival.numero, rival.v])
			assert(absf(rival.d) > pista.meia_util * 0.6, "Estaciona no canto, deixando o meio livre")
		if pista.rampas:
			assert(saltaram.size() >= 4, "Os adversários devem saltar nas rampas (%d saltaram)" % saltaram.size())
			print("%d adversários saltaram nas rampas" % saltaram.size())

		# Jogador: portões em ordem até a bandeirada
		carro.freeze = false
		var resultado := []
		corrida.terminou.connect(func(total: float, _melhor: float): resultado.append(total), CONNECT_ONE_SHOT)
		pista.portao.emit(0)
		assert(corrida._cruzou_largada)
		pista.portao.emit(PistaCorrida.PORTOES)
		assert(corrida.fase == Corrida.Fase.CORRENDO, "Pular portões não chega")
		for k in range(1, PistaCorrida.PORTOES + 1):
			pista.portao.emit(k)
		assert(corrida.fase == Corrida.Fase.CHEGADA and resultado.size() == 1)
		assert(corrida.posicao == sprint.rivais.size() + 1, "Chegou depois de todos")
		for i in 2:
			await process_frame
		assert(carro.painel_corrida.begins_with("CHEGOU"), carro.painel_corrida)

		# Salto da rampa com o carro do jogador: sai do chão, pousa sem dano e com turbo
		if pista.rampas:
			var rampa: Dictionary = pista.rampas.lista[0]
			var antes := pista.quadro(float(rampa.s) - 35.0)
			antes.origin += antes.basis.x * float(rampa.d) + antes.basis.y * 0.3
			carro.teleportar(sprint.global_transform * antes)
			for i in 20:
				await physics_frame
			var vida: int = carro.vida
			carro.linear_velocity = -carro.global_basis.z * 11.0
			tecla(KEY_W, true)
			var mais_alto := 0.0
			var mais_rapido := 0.0
			var aterrissou := false
			var no_ar := false
			for i in 60 * 6:
				await physics_frame
				var proj := pista.projetar(sprint.to_local(carro.global_position))
				var acima: float = sprint.to_local(carro.global_position).y - pista.quadro(proj.x).origin.y
				mais_alto = maxf(mais_alto, acima)
				if carro.rodas_no_chao == 0 and proj.x > float(rampa.s):
					no_ar = true
				elif no_ar and carro.rodas_no_chao > 0:
					aterrissou = true
				mais_rapido = maxf(mais_rapido, carro.linear_velocity.length())
				if proj.x > float(rampa.s) + pista.rampas.voo + RampasPista.PLACA + 15.0:
					break
			tecla(KEY_W, false)
			print("Salto: %.2f m acima da pista, %.1f m/s no máximo, vida %d -> %d" % [mais_alto, mais_rapido, vida, carro.vida])
			assert(no_ar and aterrissou, "O carro deve sair do chão na rampa e pousar")
			assert(mais_alto > RampasPista.ALTURA + 0.1 and mais_alto < 3.0, "Salto baixo: %.2f m" % mais_alto)
			assert(carro.vida == vida, "Pouso sem dano")
			assert(mais_rapido > RampasPista.TURBO - 1.5, "Turbo no pouso: %.1f m/s" % mais_rapido)

		await mundos.voltar()
		assert(mundos.mapa_atual == null and corrida.fase == Corrida.Fase.PARADA)
		for i in 10:
			await physics_frame

	print("SPRINT_OK: Sistema S e Parque Industrial, ponta a ponta, rampas, chegada e volta")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
