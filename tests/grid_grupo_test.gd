extends SceneTree
## godot --headless --path . --xr-mode off --fixed-fps 60 --script res://tests/grid_grupo_test.gd
## Corrida em grupo: o grid sempre fecha com 11 carros. Cada jogador que entra tira um
## adversário da IA; quem sai antes da largada devolve a vaga à IA

## Vagas do grid (Rede.VAGAS; o autoload não existe na compilação do teste)
const VAGAS := MapaCorrida.ADVERSARIOS + 1
var rede: Node

func _initialize():
	_testar.call_deferred()

## Sala como o servidor manda (Rede._info_sala): este Quest (peer 1) é o anfitrião
func sala(vagas_jogadores: Array) -> Dictionary:
	var jogadores := []
	for k in vagas_jogadores.size():
		jogadores.append({"peer": 1 if k == 0 else 100 + k, "nome": "P%d" % k, "vaga": vagas_jogadores[k]})
	return {"id": 7, "destino": "Deserto", "anfitriao": 1, "rivais": VAGAS - jogadores.size(), "jogadores": jogadores}

## Vagas do grid em que há adversários ativos, conferindo que nenhum cai na de um jogador
func conferir_grid(deserto: Deserto, grupo: Dictionary, ativos: int):
	var corrida: Corrida = deserto.corrida
	var pista: PistaCorrida = deserto.pista
	assert(corrida.rivais.size() == ativos, "Esperava %d adversários, veio %d" % [ativos, corrida.rivais.size()])
	assert(corrida.total_carros() == VAGAS, "O grid deve fechar com %d carros" % VAGAS)
	var usadas := {}
	for jogador in grupo.jogadores:
		usadas[int(jogador.vaga)] = true
	for i in deserto.rivais.size():
		var rival: CarroRival = deserto.rivais[i]
		assert(rival.visible == (i < ativos), "Rival %d deveria estar %s" % [i + 1, "no grid" if i < ativos else "fora"])
		if i >= ativos:
			continue
		var vaga := -1
		for v in VAGAS:
			var sd := pista.grid_sd(v)
			if absf(sd.x - rival.s) < 0.01 and absf(sd.y - rival.d) < 0.01:
				vaga = v
		assert(vaga >= 0, "Rival %d fora de uma vaga do grid" % (i + 1))
		assert(not usadas.has(vaga), "Rival %d na vaga %d, que é de um jogador" % [i + 1, vaga])
		usadas[vaga] = true
	assert(usadas.size() == VAGAS)

func _testar():
	create_timer(60.0).timeout.connect(func():
		push_error("Timeout no teste do grid em grupo")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	mapa.ritual.estado = mapa.ritual.Estado.PARTIDA
	mapa.ritual._painel.hide()
	mapa.carro.em_ritual = false
	var mundos = mapa.get_node("Mundos")
	rede = root.get_node("Rede")

	# Sozinho: 10 adversários e o jogador na última vaga
	await mundos.entrar_deserto(mapa.get_node("Portais")._portais[mapa.get_node("Portais").AMBAR])
	var deserto: Deserto = mundos.deserto
	assert(deserto.corrida.fase == Corrida.Fase.CONTROLES)
	conferir_grid(deserto, {"jogadores": [{"vaga": MapaCorrida.ADVERSARIOS}]}, 10)

	# Grupo de 3: 8 adversários
	var grupo := sala([10, 9, 8])
	assert(deserto.preparar_corrida(grupo) == 10)
	deserto.corrida.grupo = grupo
	deserto.trafego.preparar()
	conferir_grid(deserto, grupo, 8)

	# Entrou mais um ainda no grid: 7 adversários
	grupo = sala([10, 9, 8, 7])
	deserto.atualizar_grupo(grupo)
	conferir_grid(deserto, grupo, 7)

	# O da vaga 9 saiu antes da largada: a IA volta a ocupar a vaga dele
	grupo = sala([10, 8, 7])
	deserto.atualizar_grupo(grupo)
	conferir_grid(deserto, grupo, 8)

	# Servidor: quem entra depois fica com a vaga mais de trás livre e tira uma IA
	var s := {"id": 7, "destino": "Deserto", "anfitriao": 1, "rivais": 8, "largou": false,
		"participantes": [1, 101, 103], "carregados": {}, "prontos": {},
		"jogadores": [{"peer": 1, "nome": "A", "vaga": 10}, {"peer": 101, "nome": "B", "vaga": 8}, {"peer": 103, "nome": "C", "vaga": 7}]}
	rede.salas = {7: s}
	assert(rede._sala_aberta("Deserto") == s)
	assert(rede._sala_aberta("Vale das Turbinas").is_empty())
	rede._entrar_na_sala(s, 104)
	assert(s.rivais == 7 and s.participantes.size() == 4)
	assert(int(s.jogadores[-1].vaga) == 9, "O novo jogador deve ocupar a vaga 9 que estava livre")
	rede._sair_da_sala(101)
	assert(s.rivais == 8 and s.jogadores.size() == 3)
	s.largou = true
	assert(rede._sala_aberta("Deserto").is_empty(), "Depois da largada ninguém entra")
	rede._sair_da_sala(103)
	assert(s.rivais == 8 and s.jogadores.size() == 3, "Depois da largada a IA não volta")
	rede.salas = {}

	print("GRID_GRUPO_OK: o grid fecha com 11 carros quando jogadores entram e saem")
	quit(0)
