extends Node3D
## Telão do evento (modo espectador, PC sem headset): conecta ao servidor da rede e
## transmite os jogadores ao vivo. Monta o mundo neon e os mapas de corrida só como
## cenário (MapaCorrida.so_cenario, nas mesmas origens de mundos.gd, então a geometria
## bate com a do Quest) e põe os carros pela telemetria (Rede.telemetria_recebida, ~30x/s
## por jogador), suavizada pelo InterpoladorRede de cada carro.
## A cada TEMPO_TOMADA troca de jogador E de ângulo (topo, diagonal alta, terceira
## pessoa); com um jogador só, troca só o ângulo. HUD de transmissão: nome, corrida,
## volta/posição, vida e velocidade.
## Abertura: jogadores que acabaram de chegar ao grid (fase de controles/contagem na
## telemetria) tomam o telão até a largada: a pista vista do céu (panorama, sobrevoo do
## traçado e a grua descendo no grid), com faixas de cinema e a cartela do circuito.
## Teclas: ←/→ jogador · espaço pausa a troca · 1/2/3 fixa o ângulo (0 volta ao
## automático) · A pula a abertura · F11 tela cheia.

const Mundos := preload("res://mundos.gd")

enum Angulo { TOPO, DIAGONAL, TERCEIRA }
const NOMES_ANGULO := ["VISTA DE CIMA", "DIAGONAL ALTA", "TERCEIRA PESSOA"]
const TEMPO_TOMADA := 6.0
const TEMPO_CORTE := 0.25
const PINTURAS_JOGADOR := CarroFantasma.PINTURAS_JOGADOR

enum Abertura { PANORAMA, SOBREVOO, GRID }
const NOMES_ABERTURA := ["VISTA AÉREA", "SOBREVOO DO CIRCUITO", "GRID DE LARGADA"]
## Duração de cada tomada da abertura (s); repete o ciclo enquanto o grid espera
const TEMPOS_ABERTURA := [7.0, 9.0, 6.0]
## Sobrevoo: altura do drone sobre a pista (m) e velocidade máxima (m/s)
const ALTURA_SOBREVOO := 38.0
const VELOCIDADE_SOBREVOO := 110.0
## Na abertura a câmera sobe muito acima da do Quest: a névoa do mapa recua tanto
const NEVOA_AEREA := 3.0
const ALCANCE_CAMERA := 1500.0
const ALCANCE_AEREO := 4000.0

## Os mapas de corrida do jeito que os portais abrem (destino -> [classe, origem])
var _destinos := {
	"Deserto": [Deserto, Mundos.ORIGEM_DESERTO],
	"Vale das Turbinas": [ValeTurbinas, Mundos.ORIGEM_TURBINAS],
	"Sistema S": [SistemaS, Mundos.ORIGEM_SISTEMA_S],
	"Parque Industrial": [ParqueIndustrial, Mundos.ORIGEM_INDUSTRIAL],
	"I de Incrível": [Vulcao, Mundos.ORIGEM_VULCAO],
}
var ambiente: WorldEnvironment
var sol: DirectionalLight3D
var camera: Camera3D
var lobby: Node3D
var mapas := {}
## peer -> CarroFantasma
var carros := {}
## Os 10 adversários da corrida do jogador em foco (cada corrida é particular)
var rivais: Array[CarroFantasma] = []
## Último pacote de telemetria, por peer
var dados := {}
var foco := 0
var angulo := Angulo.TOPO
## -1 = automático; senão o ângulo fixado pelo operador
var angulo_fixo := -1
var pausado := false
var tempo_tomada := 0.0
var pronto := false
var mundo_atual := "-"
## Mapa cuja abertura está no ar (vazio = diretor normal), a tomada e o tempo nela
var abertura_mapa := ""
var abertura_tomada := Abertura.PANORAMA
var abertura_tempo := 0.0
## Abertura que o operador pulou (tecla A): só volta num próximo grid desse mapa
var _abertura_pulada := ""
## Por mapa: o ambiente com a névoa recuada; por pista: {centro, raio} do traçado
var _ambientes_aereos := {}
var _formas := {}

var _ambiente_neon: Environment
var _sol_neon: Transform3D
var _frente := Vector3.FORWARD
var _orbita := 0.0
var _hud: HudEspectador

func _ready():
	_ambiente_neon = preload("res://ambiente_neon.tres").duplicate()
	# Câmeras altas: a névoa do cockpit (42 m) apagaria o chão inteiro
	_ambiente_neon.fog_depth_end = 160.0
	_ambiente_neon.volumetric_fog_length = 120.0
	ambiente = WorldEnvironment.new()
	ambiente.environment = _ambiente_neon
	add_child(ambiente)
	sol = DirectionalLight3D.new()
	sol.transform = Transform3D(Basis(Vector3(0.8253356, 0, -0.5646425), Vector3(-0.44229966, 0.62161, -0.6465076), Vector3(0.3509874, 0.7833269, 0.51303685)), Vector3.ZERO)
	sol.light_color = Color(0.55, 0.65, 1.0)
	sol.light_energy = 0.5
	sol.shadow_enabled = true
	_sol_neon = sol.transform
	add_child(sol)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = ALCANCE_CAMERA
	add_child(camera)
	camera.make_current()

	lobby = Node3D.new()
	lobby.name = "Lobby"
	add_child(lobby)
	var hex := preload("res://hex_world.gd").new()
	hex.name = "HexWorld"
	lobby.add_child(hex)
	var atmosfera := preload("res://atmosphere.gd").new()
	atmosfera.name = "Atmosfera"
	lobby.add_child(atmosfera)
	lobby.add_child(TelaoRanking.new())

	_hud = HudEspectador.new()
	add_child(_hud)
	CarroRival.preparar(self)
	var elenco := PerfilPiloto.elenco()
	for i in MapaCorrida.ADVERSARIOS:
		var rival := CarroFantasma.new(CarroRival.PINTURAS[i % CarroRival.PINTURAS.size()], elenco[i % elenco.size()].nome, i + 1, false)
		rival.visible = false
		add_child(rival)
		rivais.append(rival)
	Rede.quadro_recebido.connect(receber_quadro)
	Rede.telemetria_recebida.connect(receber_telemetria)
	Ranking.ranking_mudou.connect(func(_top: Array): _hud.mostrar_ranking())
	await _montar_mapas()
	pronto = true
	_hud.carregando("")
	_aplicar_mundo("")
	receber_quadro(Rede.quadro)

## Os mapas de corrida são montados uma vez, atrás da tela de "preparando"
func _montar_mapas():
	for destino in _destinos:
		var mapa: MapaCorrida = _destinos[destino][0].new()
		mapa.so_cenario = true
		mapa.construcao_progressiva = true
		mapa.position = _destinos[destino][1]
		mapa.etapa_carregamento.connect(func(etapa: String): _hud.carregando("%s · %s" % [destino, etapa]))
		add_child(mapa)
		await mapa.construir()
		mapa.visible = false
		mapa.process_mode = Node.PROCESS_MODE_DISABLED
		mapas[destino] = mapa

# --- Telemetria da rede --------------------------------------------------------------

## Um pacote de um jogador: chega ~30x/s, repassado pelo servidor assim que o Quest
## manda, com o carimbo de tempo do Quest (`t`) para o interpolador do carro
func receber_telemetria(item: Dictionary):
	if not item.has("peer"):
		return
	var peer: int = item.peer
	var t := float(item.get("t", InterpoladorRede.agora()))
	dados[peer] = item
	if not carros.has(peer):
		var carro_novo := CarroFantasma.new(PINTURAS_JOGADOR[carros.size() % PINTURAS_JOGADOR.size()], _nome(item), 0, true)
		add_child(carro_novo)
		carros[peer] = carro_novo
	var carro: CarroFantasma = carros[peer]
	carro.rotulo.text = _nome(item)
	var escondido: bool = item.get("explodindo", false) or item.get("na_esfera", false)
	if item.get("explodindo", false) and not carro.explodindo:
		_explodir(carro)
	carro.explodindo = item.get("explodindo", false)
	# Reapareceu (renasceu, saiu da esfera): começa da pose nova, sem deslizar da antiga
	if not escondido and not carro.visible:
		carro.reiniciar()
	carro.visible = not escondido
	carro.receber(t, item.get("pos", Vector3.ZERO), item.get("rot", Quaternion.IDENTITY), float(item.get("vel", 0.0)))
	carro.ver_nitro(int(item.get("nitros", 0)))
	if pronto and peer == foco:
		_atualizar_foco_rivais()

## Lista dos jogadores ativos (o servidor manda a cada 0,5 s): quem saiu dela some
func receber_quadro(lista: Array):
	var vistos := {}
	for item in lista:
		if item is Dictionary and item.has("peer"):
			vistos[item.peer] = true
			receber_telemetria(item)
	for peer in carros.keys():
		if not vistos.has(peer):
			carros[peer].queue_free()
			carros.erase(peer)
			dados.erase(peer)

func _nome(item: Dictionary) -> String:
	var nome := str(item.get("nome", ""))
	return nome if nome != "" else str(item.get("apelido", "PILOTO"))

func _explodir(carro: CarroFantasma):
	var explosao := Explosao.new()
	add_child(explosao)
	explosao.global_position = carro.global_transform * Vector3(0.0, 0.35, 0.0)

## Rivais e relógio dos obstáculos vêm da corrida do jogador em foco (no mesmo pacote,
## com o mesmo carimbo de tempo)
func _atualizar_foco_rivais():
	var item: Dictionary = dados.get(foco, {})
	var t := float(item.get("t", InterpoladorRede.agora()))
	var lista: Array = item.get("rivais", [])
	var usados := {}
	for r in lista:
		var i := int(r[0]) - 1
		if i < 0 or i >= rivais.size():
			continue
		usados[i] = true
		rivais[i].receber(t, r[1], r[2], 0.0)
		rivais[i].visible = true
	for i in rivais.size():
		if not usados.has(i) and rivais[i].visible:
			rivais[i].visible = false
			rivais[i].reiniciar()
	var mapa: MapaCorrida = mapas.get(str(item.get("mapa", "")))
	if mapa is ValeTurbinas and mapa.obstaculos and item.has("relogio"):
		mapa.obstaculos.tempo = float(item.relogio)

# --- Diretor -------------------------------------------------------------------------

## Peers que vale mostrar: quem está dirigindo (na esfera só se não houver outro)
func ativos() -> Array:
	var todos := carros.keys()
	todos.sort()
	var dirigindo := todos.filter(func(p): return not dados[p].get("na_esfera", false))
	return dirigindo if not dirigindo.is_empty() else todos

func _process(delta: float):
	if not pronto:
		return
	var lista := ativos()
	_hud.atualizar_estado(Rede.conectado, lista.is_empty())
	var grid := _mapa_em_abertura(lista)
	if grid != "":
		_rodar_abertura(grid, lista, delta)
		return
	if abertura_mapa != "":
		_fechar_abertura(lista)
	if lista.is_empty():
		foco = 0
		_aplicar_mundo("")
		_orbitar(delta)
		return
	if foco not in lista:
		_cortar(lista[0], angulo)
	elif not pausado:
		tempo_tomada += delta
		if tempo_tomada >= TEMPO_TOMADA:
			proxima_tomada()
	var item: Dictionary = dados[foco]
	_aplicar_mundo(str(item.get("mapa", "")))
	_seguir(delta, false)
	_hud.mostrar_jogador(item, _nome(item), NOMES_ANGULO[angulo], lista, foco, pausado, tempo_tomada / TEMPO_TOMADA, carros)

## Próximo jogador (se houver outro) e próximo ângulo
func proxima_tomada(passo := 1):
	var lista := ativos()
	if lista.is_empty():
		return
	var i := lista.find(foco)
	var proximo: int = lista[posmod(i + passo, lista.size())] if i >= 0 else lista[0]
	var novo := angulo_fixo if angulo_fixo >= 0 else (angulo + 1) % Angulo.size()
	_cortar(proximo, novo)

func _cortar(peer: int, novo_angulo: int):
	# Outro jogador, outra corrida: os rivais recomeçam pelas poses da corrida dele
	if peer != foco:
		for rival in rivais:
			rival.reiniciar()
	foco = peer
	angulo = novo_angulo as Angulo
	tempo_tomada = 0.0
	_atualizar_foco_rivais()
	var item: Dictionary = dados.get(foco, {})
	_aplicar_mundo(str(item.get("mapa", "")))
	_hud.corte(TEMPO_CORTE)
	_seguir(0.0, true)

## Câmera atrás do carro em foco, no ângulo atual; `cortar` posiciona sem suavizar
func _seguir(delta: float, cortar: bool):
	var carro: CarroFantasma = carros.get(foco)
	if carro == null:
		return
	var alvo := carro.global_position
	var frente := -carro.global_basis.z
	frente.y = 0.0
	if frente.length_squared() > 0.01:
		frente = frente.normalized()
		_frente = frente if cortar else _frente.slerp(frente, 1.0 - exp(-3.0 * delta)).normalized()
	var lado := _frente.cross(Vector3.UP)
	var posicao: Vector3
	var mira: Vector3
	var cima := Vector3.UP
	match angulo:
		Angulo.TOPO:
			posicao = alvo + Vector3.UP * 28.0 + _frente * 2.0
			mira = alvo + _frente * 2.0
			cima = _frente
		Angulo.DIAGONAL:
			posicao = alvo - _frente * 14.0 + lado * 8.0 + Vector3.UP * 12.0
			mira = alvo + _frente * 3.0
		_:
			posicao = alvo - _frente * 6.5 + Vector3.UP * 2.4
			mira = alvo + _frente * 4.0 + Vector3.UP * 0.6
	var desejada := Transform3D(Basis.looking_at(mira - posicao, cima), posicao)
	if cortar:
		camera.global_transform = desejada
	else:
		camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-5.0 * delta))

## Sem ninguém dirigindo: sobrevoo lento do mundo neon
func _orbitar(delta: float):
	_orbita += delta * 0.04
	var posicao := Vector3(sin(_orbita) * 70.0, 32.0, cos(_orbita) * 70.0 - 20.0)
	camera.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, 8.0, -30.0) - posicao), posicao)

# --- Abertura da corrida ---------------------------------------------------------------

## Na telemetria: no grid, esperando a largada (controles ou contagem)
func _no_grid(item: Dictionary) -> bool:
	var fase := int(item.get("fase", -1))
	return mapas.has(str(item.get("mapa", ""))) and (fase == Corrida.Fase.CONTROLES or fase == Corrida.Fase.CONTAGEM)

## Mapa com jogadores no grid (o que já está no ar tem preferência); vazio = nenhum
func _mapa_em_abertura(lista: Array) -> String:
	var candidatos := []
	for peer in lista:
		var item: Dictionary = dados[peer]
		if _no_grid(item) and str(item.mapa) not in candidatos:
			candidatos.append(str(item.mapa))
	if _abertura_pulada not in candidatos:
		_abertura_pulada = ""
	candidatos.erase(_abertura_pulada)
	if abertura_mapa in candidatos:
		return abertura_mapa
	return candidatos[0] if not candidatos.is_empty() else ""

## Jogadores no mapa (correndo ou no grid), em ordem de peer
func _no_mapa(lista: Array, nome_mapa: String) -> Array:
	return lista.filter(func(p): return str(dados[p].get("mapa", "")) == nome_mapa)

func _rodar_abertura(nome_mapa: String, lista: Array, delta: float):
	var aqui := _no_mapa(lista, nome_mapa)
	var contagem := aqui.any(func(p): return int(dados[p].get("fase", -1)) == Corrida.Fase.CONTAGEM)
	var cortar := false
	if abertura_mapa != nome_mapa:
		abertura_mapa = nome_mapa
		abertura_tomada = Abertura.GRID if contagem else Abertura.PANORAMA
		abertura_tempo = 0.0
		_aplicar_mundo(nome_mapa)
		ambiente.environment = _ambiente_aereo(nome_mapa)
		camera.far = ALCANCE_AEREO
		_hud.abertura(true)
		_hud.corte(0.8)
		cortar = true
	# Os rivais vêm da telemetria de quem está nesse grid
	if foco not in aqui:
		for rival in rivais:
			rival.reiniciar()
		foco = aqui[0]
		_atualizar_foco_rivais()
	abertura_tempo += delta
	if contagem and abertura_tomada != Abertura.GRID:
		# Vai largar: fica no grid até o VAI!
		abertura_tomada = Abertura.GRID
		abertura_tempo = 0.0
		_hud.corte(TEMPO_CORTE)
		cortar = true
	elif not contagem and abertura_tempo >= TEMPOS_ABERTURA[abertura_tomada]:
		abertura_tomada = ((abertura_tomada + 1) % Abertura.size()) as Abertura
		abertura_tempo = 0.0
		_hud.corte(TEMPO_CORTE * 2.0)
		cortar = true
	var mapa: MapaCorrida = mapas[nome_mapa]
	var desejada := _pose_abertura(mapa, abertura_tomada, minf(abertura_tempo / TEMPOS_ABERTURA[abertura_tomada], 1.0))
	if cortar:
		camera.global_transform = desejada
	else:
		camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-6.0 * delta))
	var item: Dictionary = dados[foco]
	var nomes := PackedStringArray()
	for peer in aqui:
		nomes.append(_nome(dados[peer]).to_upper())
	var ia: int = item.get("rivais", []).size()
	var total := int(item.get("total", aqui.size() + ia))
	var grid_texto := "%d CARROS NO GRID  ·  %s" % [total, ", ".join(nomes)]
	if ia > 0:
		grid_texto += " + %d DA IA" % ia
	_hud.mostrar_abertura(nome_mapa, _formato_pista(mapa.pista), grid_texto, NOMES_ABERTURA[abertura_tomada], contagem, lista, foco, carros)

## A largada saiu (ou o grid esvaziou): volta ao diretor de sempre, com corte
func _fechar_abertura(lista: Array):
	abertura_mapa = ""
	camera.far = ALCANCE_CAMERA
	# Força o céu normal do mapa de novo
	mundo_atual = "-"
	_hud.abertura(false)
	if not lista.is_empty():
		_cortar(foco if foco in lista else lista[0], angulo)

## "3 VOLTAS · 604 M POR VOLTA" ou "SPRINT · 1614 M PONTA A PONTA"
func _formato_pista(pista: PistaCorrida) -> String:
	if pista.aberta:
		return "SPRINT  ·  %d M PONTA A PONTA" % roundi(pista.distancia_corrida())
	return "%d VOLTAS  ·  %d M POR VOLTA  ·  %.1f KM" % [pista.voltas, roundi(pista.comprimento), pista.distancia_corrida() / 1000.0]

## O céu do mapa com a névoa recuada para as tomadas do alto
func _ambiente_aereo(nome_mapa: String) -> Environment:
	if not _ambientes_aereos.has(nome_mapa):
		var aereo: Environment = mapas[nome_mapa].ambiente.duplicate()
		aereo.fog_depth_begin *= NEVOA_AEREA
		aereo.fog_depth_end *= NEVOA_AEREA
		_ambientes_aereos[nome_mapa] = aereo
	return _ambientes_aereos[nome_mapa]

## Centro e raio (meia maior largura) do traçado no mundo
func _forma(pista: PistaCorrida) -> Dictionary:
	if not _formas.has(pista):
		var caixa := AABB(pista.global_transform * pista.pontos[0], Vector3.ZERO)
		for ponto in pista.pontos:
			caixa = caixa.expand(pista.global_transform * ponto)
		_formas[pista] = {"centro": caixa.get_center(), "raio": maxf(caixa.size.x, caixa.size.z) * 0.5}
	return _formas[pista]

func _na_pista(pista: PistaCorrida, s: float) -> Transform3D:
	return pista.global_transform * pista.quadro(s)

## Pose da câmera na tomada `tomada` da abertura, com `u` de 0 a 1 ao longo dela
func _pose_abertura(mapa: MapaCorrida, tomada: Abertura, u: float) -> Transform3D:
	var pista := mapa.pista
	var suave := smoothstep(0.0, 1.0, u)
	var posicao: Vector3
	var mira: Vector3
	match tomada:
		Abertura.PANORAMA:
			if pista.aberta:
				# Ponta a ponta: do alto, atrás da largada, olhando a reta toda sumir no horizonte
				var largada := _na_pista(pista, pista.s_largada)
				var frente := _plano(-largada.basis.z)
				posicao = largada.origin - frente * (90.0 - 140.0 * suave) + Vector3.UP * (120.0 + 30.0 * suave)
				mira = _na_pista(pista, pista.s_largada + pista.distancia_corrida() * 0.45).origin
			else:
				# Circuito: órbita lenta com o traçado inteiro no quadro
				var forma := _forma(pista)
				var giro := u * 0.6
				posicao = forma.centro + Vector3(sin(giro), 0.0, cos(giro)) * (forma.raio * 1.35 + 60.0) + Vector3.UP * (forma.raio * 0.8 + 50.0)
				mira = forma.centro
		Abertura.SOBREVOO:
			# Drone pelo traçado: no circuito chega ao grid no fim; na sprint sai da largada
			var tempo: float = TEMPOS_ABERTURA[Abertura.SOBREVOO]
			var s: float
			if pista.aberta:
				s = pista.s_largada + minf(VELOCIDADE_SOBREVOO, pista.distancia_corrida() / tempo) * tempo * u
			else:
				s = pista.grid_sd(0).x - minf(VELOCIDADE_SOBREVOO, pista.comprimento * 0.85 / tempo) * tempo * (1.0 - u)
			var aqui := _na_pista(pista, s)
			posicao = aqui.origin - _plano(-aqui.basis.z) * 30.0 + Vector3.UP * ALTURA_SOBREVOO
			mira = _na_pista(pista, s + 70.0).origin
		_:
			# Grua: começa alta atrás do grid e desce até a altura dos carros
			var primeira := mapa.largada(0)
			var ultima := mapa.largada(MapaCorrida.ADVERSARIOS)
			var frente := _plano(-primeira.basis.z)
			var lado := frente.cross(Vector3.UP)
			var alto := ultima.origin - frente * 22.0 + lado * 12.0 + Vector3.UP * 60.0
			var baixo := ultima.origin - frente * 13.0 + lado * 3.0 + Vector3.UP * 4.5
			posicao = alto.lerp(baixo, suave)
			mira = ((primeira.origin + ultima.origin) * 0.5).lerp(primeira.origin + frente * 12.0 + Vector3.UP, suave)
	return Transform3D(Basis.looking_at(mira - posicao, Vector3.UP), posicao)

## Direção no plano do chão (sem subir/descer)
func _plano(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD

## Mostra o mundo neon ("") ou o mapa de corrida, com o céu e o sol de cada um
func _aplicar_mundo(nome_mapa: String):
	if not mapas.has(nome_mapa):
		nome_mapa = ""
	if nome_mapa == mundo_atual:
		return
	mundo_atual = nome_mapa
	for destino in mapas:
		var mapa: MapaCorrida = mapas[destino]
		mapa.visible = destino == nome_mapa
		mapa.process_mode = Node.PROCESS_MODE_INHERIT if mapa.visible else Node.PROCESS_MODE_DISABLED
	lobby.visible = nome_mapa == ""
	lobby.process_mode = Node.PROCESS_MODE_INHERIT if lobby.visible else Node.PROCESS_MODE_DISABLED
	if nome_mapa == "":
		ambiente.environment = _ambiente_neon
		sol.transform = _sol_neon
		sol.light_color = Color(0.55, 0.65, 1.0)
		sol.light_energy = 0.5
	else:
		ambiente.environment = mapas[nome_mapa].ambiente
		mapas[nome_mapa].sol(sol)

func _unhandled_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_RIGHT:
			proxima_tomada(1)
		KEY_LEFT:
			proxima_tomada(-1)
		KEY_SPACE:
			pausado = not pausado
		KEY_1, KEY_2, KEY_3:
			angulo_fixo = event.keycode - KEY_1
			_cortar(foco, angulo_fixo)
		KEY_0:
			angulo_fixo = -1
		KEY_A:
			if abertura_mapa != "":
				_abertura_pulada = abertura_mapa
		KEY_F11:
			var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia else DisplayServer.WINDOW_MODE_FULLSCREEN)


## HUD de transmissão (CanvasLayer): selo AO VIVO, ângulo e chips dos jogadores no
## topo; terço inferior com nome, corrida, vida e velocidade; telas de espera.
class HudEspectador extends CanvasLayer:
	const LARGURA_TERCO := 780.0
	## Faixas de cinema da abertura (px)
	const ALTURA_FAIXA := 92.0

	var _ao_vivo: PanelContainer
	var _painel_vel: PanelContainer
	var _angulo: Label
	var _chips: HBoxContainer
	var _terco: PanelContainer
	var _nome: Label
	var _local: Label
	var _situacao: PanelContainer
	var _vida: HBoxContainer
	var _vida_texto: Label
	var _velocidade: Label
	var _progresso: ColorRect
	var _espera: PanelContainer
	var _espera_titulo: Label
	var _espera_ranking: VBoxContainer
	var _carregando: Label
	var _fade: ColorRect
	var _corte: Tween
	var _assinatura_chips := ""
	var _vida_max := -1
	var _faixa_cima: ColorRect
	var _faixa_baixo: ColorRect
	var _cartela: PanelContainer
	var _cartela_titulo: Label
	var _cartela_info: Label
	var _cartela_grid: Label
	var _cartela_estado: PanelContainer
	var _em_abertura := false
	var _anima_abertura: Tween

	func _init():
		layer = 10
		var raiz := Control.new()
		raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
		raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.theme = TemaEvento.criar()
		add_child(raiz)

		# Faixas de cinema da abertura: por baixo do resto do HUD
		_faixa_cima = _faixa(raiz, true)
		_faixa_baixo = _faixa(raiz, false)

		# Topo: AO VIVO + marca + ângulo à esquerda, jogadores à direita
		var topo := HBoxContainer.new()
		topo.set_anchors_preset(Control.PRESET_TOP_WIDE)
		topo.offset_left = 28
		topo.offset_right = -28
		topo.offset_top = 22
		topo.add_theme_constant_override("separation", 14)
		raiz.add_child(topo)
		_ao_vivo = TemaEvento.pilula("●  AO VIVO", TemaEvento.ALERTA, 16)
		topo.add_child(_ao_vivo)
		topo.add_child(TemaEvento.rotulo("ECO SHELL VR", 20, TemaEvento.CIANO, true))
		_angulo = TemaEvento.rotulo("", 15, TemaEvento.TEXTO_SUAVE, true)
		topo.add_child(_angulo)
		var vao := Control.new()
		vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		topo.add_child(vao)
		_chips = HBoxContainer.new()
		_chips.add_theme_constant_override("separation", 8)
		topo.add_child(_chips)

		# Terço inferior à esquerda (quem, onde, vida); velocidade num quadro à direita:
		# o meio da tela fica livre para a pista
		_terco = PanelContainer.new()
		_terco.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
		_terco.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_terco.offset_left = 28
		_terco.offset_right = 28 + LARGURA_TERCO
		_terco.offset_bottom = -26
		_terco.offset_top = -168
		_terco.grow_vertical = Control.GROW_DIRECTION_BEGIN
		raiz.add_child(_terco)
		var esquerda := VBoxContainer.new()
		esquerda.add_theme_constant_override("separation", 6)
		_terco.add_child(esquerda)
		var cabeca := HBoxContainer.new()
		cabeca.add_theme_constant_override("separation", 16)
		esquerda.add_child(cabeca)
		_nome = TemaEvento.rotulo("", 46, Color.WHITE, true)
		cabeca.add_child(_nome)
		_situacao = TemaEvento.pilula("", TemaEvento.CIANO, 15)
		_situacao.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cabeca.add_child(_situacao)
		_local = TemaEvento.rotulo("", 22, TemaEvento.CIANO, true)
		esquerda.add_child(_local)
		var linha_vida := HBoxContainer.new()
		linha_vida.add_theme_constant_override("separation", 12)
		esquerda.add_child(linha_vida)
		linha_vida.add_child(TemaEvento.rotulo("VIDA", 14, TemaEvento.TEXTO_SUAVE, true))
		_vida = HBoxContainer.new()
		_vida.add_theme_constant_override("separation", 4)
		linha_vida.add_child(_vida)
		_vida_texto = TemaEvento.rotulo("", 14, TemaEvento.TEXTO_SUAVE, false, true)
		linha_vida.add_child(_vida_texto)
		# Velocidade grande, no canto direito
		_painel_vel = PanelContainer.new()
		_painel_vel.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
		_painel_vel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_painel_vel.offset_left = -28 - 270
		_painel_vel.offset_right = -28
		_painel_vel.offset_bottom = -26
		_painel_vel.offset_top = -168
		_painel_vel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_painel_vel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		raiz.add_child(_painel_vel)
		var direita := VBoxContainer.new()
		direita.alignment = BoxContainer.ALIGNMENT_CENTER
		_painel_vel.add_child(direita)
		_velocidade = TemaEvento.rotulo("0", 76, Color.WHITE, true, true)
		_velocidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		direita.add_child(_velocidade)
		var unidade := TemaEvento.rotulo("KM/H", 16, TemaEvento.CIANO, true)
		unidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		direita.add_child(unidade)
		# Tempo da tomada: filete que enche até a próxima troca
		_progresso = ColorRect.new()
		_progresso.color = Color(TemaEvento.CIANO, 0.8)
		_progresso.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_progresso.offset_left = 28
		_progresso.offset_top = -27
		_progresso.offset_bottom = -24
		raiz.add_child(_progresso)

		# Cartela da abertura: o circuito, o formato e quem está no grid, logo acima da
		# faixa de baixo
		_cartela = PanelContainer.new()
		_cartela.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.QUENTE, 24.0))
		_cartela.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_cartela.offset_left = 28
		_cartela.offset_bottom = -ALTURA_FAIXA - 24
		_cartela.offset_top = _cartela.offset_bottom - 200
		_cartela.grow_vertical = Control.GROW_DIRECTION_BEGIN
		raiz.add_child(_cartela)
		var coluna_cartela := VBoxContainer.new()
		coluna_cartela.add_theme_constant_override("separation", 4)
		_cartela.add_child(coluna_cartela)
		var cabeca_cartela := HBoxContainer.new()
		cabeca_cartela.add_theme_constant_override("separation", 14)
		coluna_cartela.add_child(cabeca_cartela)
		cabeca_cartela.add_child(TemaEvento.rotulo("A CORRIDA VAI COMEÇAR", 16, TemaEvento.QUENTE, true))
		_cartela_estado = TemaEvento.pilula("", TemaEvento.QUENTE, 13)
		_cartela_estado.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cabeca_cartela.add_child(_cartela_estado)
		_cartela_titulo = TemaEvento.rotulo("", 64, Color.WHITE, true)
		coluna_cartela.add_child(_cartela_titulo)
		_cartela_info = TemaEvento.rotulo("", 22, TemaEvento.CIANO, true)
		coluna_cartela.add_child(_cartela_info)
		_cartela_grid = TemaEvento.rotulo("", 16, TemaEvento.TEXTO_SUAVE, true)
		coluna_cartela.add_child(_cartela_grid)
		_cartela.visible = false

		# Espera: sem servidor ou sem ninguém jogando (com o top 5)
		var centro := CenterContainer.new()
		centro.set_anchors_preset(Control.PRESET_FULL_RECT)
		centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(centro)
		_espera = PanelContainer.new()
		_espera.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO, 30.0))
		_espera.custom_minimum_size.x = 620
		centro.add_child(_espera)
		var coluna := VBoxContainer.new()
		coluna.add_theme_constant_override("separation", 14)
		_espera.add_child(coluna)
		_espera_titulo = TemaEvento.rotulo("", 30, Color.WHITE, true)
		_espera_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coluna.add_child(_espera_titulo)
		_espera_ranking = VBoxContainer.new()
		_espera_ranking.add_theme_constant_override("separation", 6)
		coluna.add_child(_espera_ranking)

		_fade = ColorRect.new()
		_fade.color = Color(0.0, 0.0, 0.0, 1.0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(_fade)
		# Por cima do fade: aparece na tela preta enquanto os mapas são montados
		_carregando = TemaEvento.rotulo("PREPARANDO TRANSMISSÃO", 20, TemaEvento.CIANO, true)
		_carregando.set_anchors_preset(Control.PRESET_CENTER)
		_carregando.offset_left = -450
		_carregando.offset_right = 450
		_carregando.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		raiz.add_child(_carregando)
		_terco.visible = false
		_painel_vel.visible = false
		_progresso.visible = false
		mostrar_ranking()

	func _faixa(raiz: Control, cima: bool) -> ColorRect:
		var faixa := ColorRect.new()
		faixa.color = Color.BLACK
		faixa.mouse_filter = Control.MOUSE_FILTER_IGNORE
		faixa.set_anchors_preset(Control.PRESET_TOP_WIDE if cima else Control.PRESET_BOTTOM_WIDE)
		faixa.offset_top = 0.0
		faixa.offset_bottom = 0.0
		faixa.visible = false
		raiz.add_child(faixa)
		return faixa

	func _caixa_vidro(cor: Color, margem := 20.0) -> StyleBoxFlat:
		var caixa := TemaEvento.estilo(Color(0.01, 0.025, 0.06, 0.82), Color(cor, 0.6), 0, 10, margem)
		caixa.border_width_left = 5
		return caixa

	func carregando(texto: String):
		_carregando.visible = texto != ""
		_carregando.text = "PREPARANDO TRANSMISSÃO  ·  " + texto.to_upper()
		if texto == "":
			corte(0.6)

	## Escurece e revela: esconde o salto da câmera numa troca de tomada
	func corte(tempo: float):
		if _corte and _corte.is_valid():
			_corte.kill()
		_fade.color.a = 1.0
		_corte = create_tween()
		_corte.tween_property(_fade, "color:a", 0.0, tempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	func atualizar_estado(conectado: bool, vazio: bool):
		var pulso := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.003))
		_ao_vivo.modulate.a = pulso if conectado else 0.35
		_espera.visible = vazio and not _carregando.visible
		_terco.visible = not vazio and not _em_abertura
		_painel_vel.visible = not vazio and not _em_abertura
		_progresso.visible = not vazio and not _em_abertura
		if vazio:
			_espera_titulo.text = "AGUARDANDO JOGADORES" if conectado else "PROCURANDO SERVIDOR DO EVENTO…"
			_angulo.text = ""
			_atualizar_chips([], 0, {})

	## Liga/desliga a abertura: faixas de cinema entram e a cartela desliza da esquerda
	func abertura(ligada: bool):
		if ligada == _em_abertura:
			return
		_em_abertura = ligada
		if _anima_abertura and _anima_abertura.is_valid():
			_anima_abertura.kill()
		_anima_abertura = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var altura := ALTURA_FAIXA if ligada else 0.0
		var tempo := 0.7 if ligada else 0.35
		if ligada:
			for faixa in [_faixa_cima, _faixa_baixo]:
				faixa.visible = true
			_cartela.visible = true
			_cartela.modulate.a = 0.0
			_cartela.offset_left = -120.0
			_anima_abertura.tween_property(_cartela, "offset_left", 28.0, 0.8).set_delay(0.3)
		_anima_abertura.tween_property(_faixa_cima, "offset_bottom", altura, tempo)
		_anima_abertura.tween_property(_faixa_baixo, "offset_top", -altura, tempo)
		_anima_abertura.tween_property(_cartela, "modulate:a", 1.0 if ligada else 0.0, 0.6 if ligada else 0.25).set_delay(0.3 if ligada else 0.0)
		if not ligada:
			_anima_abertura.chain().tween_callback(func():
				_faixa_cima.visible = false
				_faixa_baixo.visible = false
				_cartela.visible = false)

	func mostrar_abertura(mapa: String, formato: String, grid: String, tomada: String, contagem: bool, ativos: Array, foco: int, carros: Dictionary):
		_cartela_titulo.text = mapa.to_upper()
		_cartela_info.text = formato
		_cartela_grid.text = grid
		_angulo.text = "·  %s" % tomada
		if contagem:
			TemaEvento.mudar_pilula(_cartela_estado, "LARGADA!", TemaEvento.VERDE)
			_cartela_estado.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.008))
		else:
			TemaEvento.mudar_pilula(_cartela_estado, "NO GRID", TemaEvento.QUENTE)
			_cartela_estado.modulate.a = 1.0
		_atualizar_chips(ativos, foco, carros)

	func mostrar_ranking():
		for filho in _espera_ranking.get_children():
			filho.queue_free()
		if Ranking.top.is_empty():
			return
		var titulo := TemaEvento.rotulo("RANKING · MELHORES TEMPOS", 15, TemaEvento.CIANO, true)
		titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_espera_ranking.add_child(titulo)
		var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
		for i in mini(5, Ranking.top.size()):
			var r: Dictionary = Ranking.top[i]
			var linha := HBoxContainer.new()
			linha.add_theme_constant_override("separation", 16)
			var cor: Color = medalhas[i] if i < 3 else TemaEvento.TEXTO_SUAVE
			var pos := TemaEvento.rotulo("%dº" % (i + 1), 20, cor, true, true)
			pos.custom_minimum_size.x = 50
			linha.add_child(pos)
			var nome := TemaEvento.rotulo(str(r.get("nome", "")), 20, Color.WHITE, true)
			nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			linha.add_child(nome)
			linha.add_child(TemaEvento.rotulo(str(r.get("pista", "")), 15, TemaEvento.TEXTO_SUAVE))
			linha.add_child(TemaEvento.rotulo(Ranking.formatar_tempo(float(r.get("tempo", 0.0))), 20, cor, true, true))
			_espera_ranking.add_child(linha)

	func mostrar_jogador(item: Dictionary, nome: String, angulo: String, ativos: Array, foco: int, pausado: bool, fracao: float, carros: Dictionary):
		_nome.text = nome.to_upper()
		_angulo.text = "·  %s%s" % [angulo, "  ·  PAUSADO" if pausado else ""]
		var mapa := str(item.get("mapa", ""))
		if mapa != "":
			var texto := mapa.to_upper()
			var volta := int(item.get("volta", 0))
			var voltas := int(item.get("voltas", 3))
			if volta > 0 and voltas <= 1:
				# Ponta a ponta: não tem volta para contar
				texto += "  ·  SPRINT  ·  %dº DE %d" % [int(item.get("posicao", 0)), int(item.get("total", 0))]
			elif volta > 0:
				texto += "  ·  VOLTA %d/%d  ·  %dº DE %d" % [mini(volta, voltas), voltas, int(item.get("posicao", 0)), int(item.get("total", 0))]
			else:
				texto += "  ·  NO GRID"
			_local.text = texto
		else:
			_local.text = "MUNDO NEON" + ("  ·  NITRO" if item.get("nitro", false) else "")
		if item.get("explodindo", false):
			TemaEvento.mudar_pilula(_situacao, "EXPLODIU", TemaEvento.ALERTA)
		elif item.get("na_esfera", false):
			TemaEvento.mudar_pilula(_situacao, "NA ESFERA", TemaEvento.QUENTE)
		elif item.has("sobrecarga"):
			TemaEvento.mudar_pilula(_situacao, "SOBRECARGA %ds" % ceili(float(item.sobrecarga)), TemaEvento.ALERTA)
		elif mapa != "":
			TemaEvento.mudar_pilula(_situacao, "CORRIDA", TemaEvento.VERDE)
		else:
			TemaEvento.mudar_pilula(_situacao, "LOBBY", TemaEvento.CIANO)
		_mostrar_vida(int(item.get("vida", 0)), int(item.get("vida_max", 8)))
		_velocidade.text = "%d" % roundi(float(item.get("vel", 0.0)))
		_progresso.offset_right = _progresso.offset_left + LARGURA_TERCO * clampf(fracao, 0.0, 1.0)
		_atualizar_chips(ativos, foco, carros)

	func _mostrar_vida(vida: int, vida_max: int):
		if vida_max != _vida_max:
			_vida_max = vida_max
			for filho in _vida.get_children():
				_vida.remove_child(filho)
				filho.queue_free()
			for i in vida_max:
				var segmento := ColorRect.new()
				segmento.custom_minimum_size = Vector2(26, 14)
				_vida.add_child(segmento)
		var cor := TemaEvento.cor_nivel(float(vida) / maxf(vida_max, 1))
		for i in _vida.get_child_count():
			(_vida.get_child(i) as ColorRect).color = cor if i < vida else Color(1, 1, 1, 0.1)
		_vida_texto.text = "%d/%d" % [vida, vida_max]

	func _atualizar_chips(ativos: Array, foco: int, carros: Dictionary):
		var nomes := []
		for peer in ativos:
			nomes.append("%d:%s" % [peer, carros[peer].rotulo.text])
		var assinatura := "%s|%d" % [",".join(nomes), foco]
		if assinatura == _assinatura_chips:
			return
		_assinatura_chips = assinatura
		for filho in _chips.get_children():
			filho.queue_free()
		for peer in ativos:
			var cor := Color.WHITE if peer == foco else TemaEvento.TEXTO_SUAVE
			var chip := TemaEvento.pilula(carros[peer].rotulo.text.to_upper(), cor, 13)
			if peer != foco:
				chip.modulate.a = 0.7
			_chips.add_child(chip)
