extends Node3D
## Telão do evento (modo espectador, PC sem headset): a propaganda do SENAI com o Eco
## Shell, em tela cheia e no estilo das transmissões de F1. Conecta ao servidor da rede,
## monta o mundo neon e os mapas de corrida só como cenário (MapaCorrida.so_cenario, nas
## mesmas origens de mundos.gd, então a geometria bate com a do Quest) e põe os carros
## pela telemetria (Rede.telemetria_recebida, ~30x/s por jogador), suavizada pelo
## InterpoladorRede de cada carro. A HUD fica em HudTransmissao.
## Diretor (máquina de estados):
## - ESPERA: ninguém correndo. Câmera nos jogadores do lobby (ou órbita lenta no mundo
##   neon) e o "aguardando próximos pilotos" com o top 5 do evento.
## - ABERTURA: jogadores chegaram ao grid. Vinheta "SENAI APRESENTA · ECO SHELL GRAND
##   PRIX", a pista inteira vista do céu, a câmera descendo até o grid e, na contagem,
##   as cinco luzes vermelhas de largada que apagam no VAI!.
## - CORRIDA: troca de jogador (reais primeiro) e de ângulo a cada TEMPO_TOMADA, com a
##   torre de classificação (★ nos jogadores reais) e o minimapa com os carros.
## - PODIO: todos os jogadores reais receberam a bandeirada (ou PODIO_ESPERA_MAX depois
##   do primeiro): pódio 3D ao lado da linha com os três primeiros e confete.
## - RANKING: placar "RANKING DO EVENTO" em tela cheia; depois volta para ESPERA (ou
##   CORRIDA, se outro grupo ainda corre). Um grid novo interrompe o ranking.
## Teclas: ←/→ jogador · espaço pausa a troca · 1 a 5 fixa o ângulo (0 volta ao
## automático) · A pula a abertura · P pódio · R ranking · F11 tela cheia.

const Mundos := preload("res://mundos.gd")

enum Estado { ESPERA, ABERTURA, CORRIDA, PODIO, RANKING }
enum Angulo { TOPO, DIAGONAL, TERCEIRA, TV, TCAM }
const NOMES_ANGULO := ["VISTA DE CIMA", "DIAGONAL ALTA", "TERCEIRA PESSOA", "CÂMERA DE PISTA", "CÂMERA ONBOARD"]
const TEMPO_TOMADA := 6.0
const TEMPO_CORTE := 0.25
const PINTURAS_JOGADOR := CarroFantasma.PINTURAS_JOGADOR

enum Abertura { VINHETA, CEU, DESCIDA, GRID }
const NOMES_ABERTURA := ["ECO SHELL GRAND PRIX", "VISTA AÉREA DO CIRCUITO", "DESCENDO NO GRID", "GRID DE LARGADA"]
## Duração de cada etapa da abertura (s); o GRID fica até a largada
const TEMPOS_ABERTURA := [HudTransmissao.DURACAO_VINHETA, 6.0, 4.5, INF]
## Contagem chegou cedo: a descida comprime para isso (s)
const DESCIDA_RAPIDA := 1.5
## Luzes de largada: uma coluna a cada (s), nos 3 s da contagem
const PASSO_LUZES := 0.6
## Câmera de pista: quantos metros à frente do carro ela fica e quando é refeita
const TV_A_FRENTE := 55.0
const TV_PASSOU := 15.0
## Pódio e ranking (s): pódio depois de todos chegarem (ou no máximo PODIO_ESPERA_MAX
## depois do primeiro), quanto dura cada um
const PODIO_ESPERA := 2.5
const PODIO_ESPERA_MAX := 20.0
const TEMPO_PODIO := 12.0
const TEMPO_RANKING := 10.0
## Torre e minimapa: quantas vezes por segundo atualizam
const QUADROS_TORRE := 4.0
const QUADROS_MAPA := 15.0
## Na abertura a câmera sobe muito acima da do Quest: a névoa do mapa recua tanto
const NEVOA_AEREA := 3.0
const ALCANCE_CAMERA := 1500.0
const ALCANCE_AEREO := 6000.0

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
## peer -> CarroFantasma, e a pintura de cada um
var carros := {}
var _pinturas := {}
## Os 10 adversários da corrida do jogador em foco (cada corrida é particular)
var rivais: Array[CarroFantasma] = []
## Último pacote de telemetria, por peer
var dados := {}
var estado := Estado.ESPERA
var foco := 0
var angulo := Angulo.TOPO
## -1 = automático; senão o ângulo fixado pelo operador
var angulo_fixo := -1
var pausado := false
var tempo_tomada := 0.0
var pronto := false
var mundo_atual := "-"
## Mapa cuja abertura está no ar (vazio = sem abertura), a etapa e o tempo nela
var abertura_mapa := ""
var abertura_tomada := Abertura.VINHETA
var abertura_tempo := 0.0
## Contagem: desde quando (relógio do telão) e se as luzes estão no ar
var _contagem_desde := -1.0
## Abertura que o operador pulou (tecla A): só volta num próximo grid desse mapa
var _abertura_pulada := ""
## Por mapa: o ambiente com a névoa recuada; por pista: {centro, raio} do traçado
var _ambientes_aereos := {}
var _formas := {}
## Câmera de pista: onde ela está agora (vazio = refazer)
var _tv := {}
## Resultados por mapa: {mapa, primeiro_em, chegada, reais: {nome: {tempo, pintura}}}
var _resultados := {}
## Mapas cujo pódio já saiu: não abre outro até todos saírem desse mapa
var _podio_feito := {}
var _podio: PodioEspectador
var _tempo_estado := 0.0
var _relogio := 0.0
var _tempo_torre := 0.0
var _tempo_mapa := 0.0
var _pista_minimapa: PistaCorrida
var _elenco: Array = []

var _ambiente_neon: Environment
var _sol_neon: Transform3D
var _frente := Vector3.FORWARD
var _orbita := 0.0
var _hud: HudTransmissao

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

	_hud = HudTransmissao.new()
	add_child(_hud)
	CarroRival.preparar(self)
	_elenco = PerfilPiloto.elenco()
	for i in MapaCorrida.ADVERSARIOS:
		var rival := CarroFantasma.new(CarroRival.PINTURAS[i % CarroRival.PINTURAS.size()], _elenco[i % _elenco.size()].nome, i + 1, false)
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
		var pintura: Array = PINTURAS_JOGADOR[carros.size() % PINTURAS_JOGADOR.size()]
		var carro_novo := CarroFantasma.new(pintura, _nome(item), 0, true)
		add_child(carro_novo)
		carros[peer] = carro_novo
		_pinturas[peer] = pintura
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
	_anotar_resultado(peer, item)
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
			_pinturas.erase(peer)

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

## Guarda o resultado de quem recebeu a bandeirada: o jogador volta para o ovo logo
## depois (e some do mapa), então o pódio sai do que foi anotado aqui
func _anotar_resultado(peer: int, item: Dictionary):
	var nome_mapa := str(item.get("mapa", ""))
	if not item.get("chegou", false) or nome_mapa == "" or _podio_feito.has(nome_mapa):
		return
	if not _resultados.has(nome_mapa):
		_resultados[nome_mapa] = {"mapa": nome_mapa, "primeiro_em": _relogio, "chegada": [], "reais": {}, "peers": {}}
	var res: Dictionary = _resultados[nome_mapa]
	res.peers[peer] = true
	res.reais[_nome(item).to_upper()] = {"tempo": float(item.get("tempo_total", -1.0)), "pintura": _pinturas.get(peer, PINTURAS_JOGADOR[0])}
	var chegada: Array = item.get("chegada", [])
	if chegada.size() >= res.chegada.size():
		res.chegada = chegada.duplicate(true)

# --- Diretor -------------------------------------------------------------------------

## Peers que vale mostrar: quem está dirigindo (na esfera só se não houver outro)
func ativos() -> Array:
	var todos := carros.keys()
	todos.sort()
	var dirigindo := todos.filter(func(p): return not dados[p].get("na_esfera", false))
	return dirigindo if not dirigindo.is_empty() else todos

## Peers correndo (num mapa de corrida), os reais primeiro na fila do diretor
func _correndo(lista: Array) -> Array:
	return lista.filter(func(p): return mapas.has(str(dados[p].get("mapa", ""))))

func _process(delta: float):
	if not pronto:
		return
	_relogio += delta
	_tempo_estado += delta
	# Pódio feito: libera o mapa quando ninguém mais está nele (a próxima corrida terá o dela)
	for nome_mapa in _podio_feito.keys():
		if not dados.values().any(func(d): return str(d.get("mapa", "")) == nome_mapa):
			_podio_feito.erase(nome_mapa)
	var lista := ativos()
	var correndo := _correndo(lista)
	var grid := _mapa_em_abertura(lista)
	match estado:
		Estado.PODIO:
			_rodar_podio(delta, grid, lista)
		Estado.RANKING:
			_rodar_ranking(grid, lista)
		_:
			if grid != "":
				estado = Estado.ABERTURA
				_rodar_abertura(grid, lista, delta)
			else:
				if abertura_mapa != "":
					_fechar_abertura(lista)
				var resultado := _resultado_pronto()
				if not resultado.is_empty():
					_abrir_podio(resultado)
				else:
					estado = Estado.CORRIDA if not correndo.is_empty() else Estado.ESPERA
					_dirigir(delta, lista, correndo)
	_hud.atualizar_estado(Rede.conectado, lista.is_empty() and estado == Estado.ESPERA, correndo.is_empty())

## ESPERA e CORRIDA: troca de jogador e de ângulo; na corrida, torre e minimapa
func _dirigir(delta: float, lista: Array, correndo: Array):
	if lista.is_empty():
		foco = 0
		_hud.modo_corrida(false)
		_aplicar_mundo("")
		_orbitar(delta)
		return
	# Na corrida o diretor só olha quem está correndo
	var fila := correndo if not correndo.is_empty() else lista
	if foco not in fila:
		_cortar(fila[0], angulo)
	elif not pausado:
		tempo_tomada += delta
		if tempo_tomada >= TEMPO_TOMADA:
			proxima_tomada()
	var item: Dictionary = dados[foco]
	var nome_mapa := str(item.get("mapa", ""))
	_aplicar_mundo(nome_mapa)
	_seguir(delta, false)
	var em_corrida := mapas.has(nome_mapa)
	_hud.modo_corrida(em_corrida)
	if em_corrida:
		_atualizar_torre(nome_mapa, item, delta)
		_atualizar_minimapa(nome_mapa, delta)
	_hud.mostrar_jogador(item, _nome(item), NOMES_ANGULO[angulo], lista, foco, pausado, tempo_tomada / TEMPO_TOMADA, carros)

## Próximo jogador (se houver outro) e próximo ângulo
func proxima_tomada(passo := 1):
	var lista := ativos()
	if lista.is_empty():
		return
	var correndo := _correndo(lista)
	var fila := correndo if not correndo.is_empty() else lista
	var i := fila.find(foco)
	var proximo: int = fila[posmod(i + passo, fila.size())] if i >= 0 else fila[0]
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
	_tv = {}
	_atualizar_foco_rivais()
	var item: Dictionary = dados.get(foco, {})
	_aplicar_mundo(str(item.get("mapa", "")))
	_hud.corte(TEMPO_CORTE)
	_seguir(0.0, true)

## Câmera no carro em foco, no ângulo atual; `cortar` posiciona sem suavizar
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
	var suavidade := 5.0
	var tomada := angulo
	var pista := _pista_do_foco()
	if tomada == Angulo.TV and pista == null:
		tomada = Angulo.DIAGONAL
	match tomada:
		Angulo.TOPO:
			posicao = alvo + Vector3.UP * 28.0 + _frente * 2.0
			mira = alvo + _frente * 2.0
			cima = _frente
		Angulo.DIAGONAL:
			posicao = alvo - _frente * 14.0 + lado * 8.0 + Vector3.UP * 12.0
			mira = alvo + _frente * 3.0
		Angulo.TV:
			# Câmera fixa na beira da pista, à frente: o carro vem, passa e ela é refeita
			posicao = _camera_de_pista(pista, alvo)
			mira = alvo + Vector3.UP * 0.6
			suavidade = 30.0
		Angulo.TCAM:
			# Em cima e logo atrás do cockpit, olhando a pista à frente
			posicao = alvo - _frente * 1.4 + Vector3.UP * 1.75
			mira = alvo + _frente * 14.0 + Vector3.UP * 0.7
			suavidade = 12.0
		_:
			posicao = alvo - _frente * 6.5 + Vector3.UP * 2.4
			mira = alvo + _frente * 4.0 + Vector3.UP * 0.6
	var desejada := Transform3D(Basis.looking_at(mira - posicao, cima), posicao)
	if cortar:
		camera.global_transform = desejada
	else:
		camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-suavidade * delta))

## Pista do mapa do jogador em foco (ou null no lobby)
func _pista_do_foco() -> PistaCorrida:
	var mapa: MapaCorrida = mapas.get(str(dados.get(foco, {}).get("mapa", "")))
	return mapa.pista if mapa else null

## Onde fica a câmera de pista: TV_A_FRENTE m à frente do carro, fora do asfalto e um
## pouco alta. Refeita quando o carro passa dela
func _camera_de_pista(pista: PistaCorrida, alvo: Vector3) -> Vector3:
	var local := pista.to_local(alvo)
	var s := pista.projetar(local).x
	if _tv.is_empty() or _tv.pista != pista or pista.delta(_tv.s, s) > TV_PASSOU:
		var s_cam := s + TV_A_FRENTE
		var q := pista.quadro(s_cam)
		var lado := 1.0 if randf() < 0.5 else -1.0
		var ponto := q.origin + q.basis.x * lado * (pista.largura * 0.5 + 9.0) + q.basis.y * 3.2
		_tv = {"pista": pista, "s": s_cam, "posicao": pista.global_transform * ponto}
	return _tv.posicao

## Sem ninguém dirigindo: sobrevoo lento do mundo neon
func _orbitar(delta: float):
	_orbita += delta * 0.04
	var posicao := Vector3(sin(_orbita) * 70.0, 32.0, cos(_orbita) * 70.0 - 20.0)
	camera.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, 8.0, -30.0) - posicao), posicao)

# --- Torre e minimapa ----------------------------------------------------------------

## Cor da barra / do marcador de cada carro: jogador real pela cor do filete, adversário
## pela pintura (a preta usa a cor de detalhe)
func _cor_jogador(peer: int) -> Color:
	var pintura: Array = _pinturas.get(peer, PINTURAS_JOGADOR[0])
	return pintura[1]

func _cor_rival(i: int) -> Color:
	var pintura: Array = CarroRival.PINTURAS[i % CarroRival.PINTURAS.size()]
	var base: Color = pintura[0]
	return pintura[1] if base.get_luminance() < 0.2 else base

## Todos da corrida do mapa: jogadores reais nele (progresso da telemetria) e os
## adversários do pacote do jogador em foco. Ordem: quem já recebeu a bandeirada, na
## ordem dela; depois o progresso
func _classificacao(nome_mapa: String, item_foco: Dictionary) -> Array:
	var linhas := []
	for peer in carros:
		var d: Dictionary = dados[peer]
		if str(d.get("mapa", "")) != nome_mapa:
			continue
		linhas.append({"nome": _nome(d), "real": true, "cor": _cor_jogador(peer), "foco": peer == foco,
			"progresso": float(d.get("progresso", 0.0)), "v": float(d.get("vel", 0.0)) / 3.6, "peer": peer})
	for r in item_foco.get("rivais", []):
		var i := int(r[0]) - 1
		if i < 0:
			continue
		linhas.append({"nome": _elenco[i % _elenco.size()].nome, "real": false, "cor": _cor_rival(i), "foco": false,
			"progresso": float(r[3]), "v": float(r[4]) if r.size() > 4 else 0.0, "rival": i})
	var ordem := {}
	var chegada: Array = item_foco.get("chegada", [])
	for k in chegada.size():
		ordem[str(chegada[k][0]).to_upper()] = k
	linhas.sort_custom(func(a, b):
		var oa: int = ordem.get(str(a.nome).to_upper(), -1)
		var ob: int = ordem.get(str(b.nome).to_upper(), -1)
		if oa >= 0 or ob >= 0:
			if oa < 0:
				return false
			if ob < 0:
				return true
			return oa < ob
		return a.progresso > b.progresso)
	for k in linhas.size():
		var linha: Dictionary = linhas[k]
		if ordem.has(str(linha.nome).to_upper()):
			linha.intervalo = "CHEGOU" if k > 0 else "VENCEDOR"
		elif k == 0:
			linha.intervalo = "LÍDER"
		else:
			var frente: Dictionary = linhas[k - 1]
			var segundos: float = maxf(frente.progresso - linha.progresso, 0.0) / maxf(linha.v, 10.0)
			linha.intervalo = "+%.1f" % segundos
	return linhas

func _atualizar_torre(nome_mapa: String, item: Dictionary, delta: float):
	_tempo_torre -= delta
	if _tempo_torre > 0.0:
		return
	_tempo_torre = 1.0 / QUADROS_TORRE
	var volta := int(item.get("volta", 0))
	var voltas := int(item.get("voltas", 3))
	var cabeca := "SPRINT" if voltas <= 1 else "VOLTA %d/%d" % [clampi(volta, 1, voltas), voltas]
	if item.get("chegou", false):
		cabeca = "RESULTADO"
	_hud.torre.atualizar("ECO SHELL GP  ·  " + nome_mapa, cabeca, _classificacao(nome_mapa, item))

func _atualizar_minimapa(nome_mapa: String, delta: float):
	var pista: PistaCorrida = mapas[nome_mapa].pista
	if pista != _pista_minimapa:
		_pista_minimapa = pista
		_hud.minimapa.definir_pista(pista, Vector2(HudTransmissao.LADO_MAPA, HudTransmissao.LADO_MAPA))
	_hud.minimapa.pulso = _relogio * 1.2
	_tempo_mapa -= delta
	if _tempo_mapa > 0.0:
		return
	_tempo_mapa = 1.0 / QUADROS_MAPA
	var marcas := []
	for i in rivais.size():
		if rivais[i].visible:
			marcas.append({"pos": _hud.minimapa.no_mapa(pista.to_local(rivais[i].global_position)), "cor": _cor_rival(i), "real": false, "foco": false})
	for peer in carros:
		if str(dados[peer].get("mapa", "")) == nome_mapa and carros[peer].visible:
			marcas.append({"pos": _hud.minimapa.no_mapa(pista.to_local(carros[peer].global_position)), "cor": _cor_jogador(peer), "real": true, "foco": peer == foco})
	_hud.minimapa.carros = marcas
	_hud.minimapa.queue_redraw()

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

## Vinheta → céu → descida → grid; na contagem as luzes acendem e a descida comprime
func _rodar_abertura(nome_mapa: String, lista: Array, delta: float):
	var aqui := _no_mapa(lista, nome_mapa)
	var contagem := aqui.any(func(p): return int(dados[p].get("fase", -1)) == Corrida.Fase.CONTAGEM)
	var mapa: MapaCorrida = mapas[nome_mapa]
	var cortar := false
	if abertura_mapa != nome_mapa:
		abertura_mapa = nome_mapa
		abertura_tomada = Abertura.VINHETA
		abertura_tempo = 0.0
		_contagem_desde = -1.0
		_aplicar_mundo(nome_mapa)
		ambiente.environment = _ambiente_aereo(nome_mapa)
		camera.far = ALCANCE_AEREO
		_hud.modo_corrida(false)
		_hud.abertura(true)
		_hud.vinheta(nome_mapa, _formato_pista(mapa.pista))
		cortar = true
	# Os rivais vêm da telemetria de quem está nesse grid
	if foco not in aqui:
		for rival in rivais:
			rival.reiniciar()
		foco = aqui[0]
		_atualizar_foco_rivais()
	abertura_tempo += delta
	if contagem:
		if _contagem_desde < 0.0:
			_contagem_desde = _relogio
			_hud.luzes.mostrar()
			# Chegou cedo: a câmera desce depressa até o grid
			if abertura_tomada < Abertura.DESCIDA:
				abertura_tomada = Abertura.DESCIDA
				abertura_tempo = TEMPOS_ABERTURA[Abertura.DESCIDA] - DESCIDA_RAPIDA
		_hud.luzes.acender(int((_relogio - _contagem_desde) / PASSO_LUZES) + 1)
	if abertura_tempo >= TEMPOS_ABERTURA[abertura_tomada]:
		abertura_tomada = mini(abertura_tomada + 1, Abertura.GRID) as Abertura
		abertura_tempo = 0.0
	var duracao: float = TEMPOS_ABERTURA[abertura_tomada]
	var u := 1.0 if is_inf(duracao) else minf(abertura_tempo / duracao, 1.0)
	var desejada := _pose_abertura(mapa, abertura_tomada, u)
	if cortar:
		camera.global_transform = desejada
	else:
		camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-6.0 * delta))
	var item: Dictionary = dados[foco]
	var nomes := PackedStringArray()
	for peer in aqui:
		nomes.append("★ " + _nome(dados[peer]).to_upper())
	var ia: int = item.get("rivais", []).size()
	var total := int(item.get("total", aqui.size() + ia))
	var grid_texto := "%d CARROS NO GRID  ·  %s" % [total, ", ".join(nomes)]
	if ia > 0:
		grid_texto += " + %d DA IA" % ia
	_hud.mostrar_abertura(nome_mapa, _formato_pista(mapa.pista), grid_texto, NOMES_ABERTURA[abertura_tomada], contagem, lista, foco, carros)

## A largada saiu (ou o grid esvaziou): apaga as luzes (VAI!) e volta ao diretor, com corte
func _fechar_abertura(lista: Array):
	abertura_mapa = ""
	camera.far = ALCANCE_CAMERA
	# Força o céu normal do mapa de novo
	mundo_atual = "-"
	_hud.abertura(false)
	if _contagem_desde >= 0.0:
		_hud.luzes.vai()
	else:
		_hud.luzes.esconder()
	_contagem_desde = -1.0
	if not lista.is_empty():
		_cortar(foco if foco in lista else lista[0], Angulo.TERCEIRA if angulo_fixo < 0 else angulo_fixo)

## "3 VOLTAS · 1257 M POR VOLTA" ou "SPRINT · 3229 M PONTA A PONTA"
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

## Céu: a pista inteira no quadro. Circuito: órbita lenta bem alta; sprint: do alto,
## atrás da largada, olhando a reta toda sumir no horizonte. [posição, mira]
func _ceu(pista: PistaCorrida, u: float) -> Array:
	if pista.aberta:
		var largada := _na_pista(pista, pista.s_largada)
		var frente := _plano(-largada.basis.z)
		return [largada.origin - frente * (90.0 - 60.0 * u) + Vector3.UP * (150.0 - 20.0 * u),
			_na_pista(pista, pista.s_largada + pista.distancia_corrida() * 0.45).origin]
	var forma := _forma(pista)
	var giro := u * 0.5
	return [forma.centro + Vector3(sin(giro), 0.0, cos(giro)) * (forma.raio * 1.3 + 60.0) + Vector3.UP * (forma.raio * 0.85 + 60.0),
		forma.centro]

## Grid: a grua parada baixa atrás dos carros, olhando a linha. [posição, mira]
func _grid(mapa: MapaCorrida, u: float) -> Array:
	var primeira := mapa.largada(0)
	var ultima := mapa.largada(MapaCorrida.ADVERSARIOS)
	var frente := _plano(-primeira.basis.z)
	var lado := frente.cross(Vector3.UP)
	var posicao := ultima.origin - frente * (13.0 - 3.0 * u) + lado * 3.0 + Vector3.UP * 4.5
	return [posicao, primeira.origin + frente * 12.0 + Vector3.UP]

## Pose da câmera na etapa `tomada` da abertura, com `u` de 0 a 1 ao longo dela
func _pose_abertura(mapa: MapaCorrida, tomada: Abertura, u: float) -> Transform3D:
	var pista := mapa.pista
	var suave := smoothstep(0.0, 1.0, u)
	var pose: Array
	match tomada:
		Abertura.VINHETA:
			pose = _ceu(pista, 0.0)
		Abertura.CEU:
			pose = _ceu(pista, suave)
		Abertura.DESCIDA:
			# Do céu até o grid: a posição desce em curva e a mira passa do centro da
			# pista para a linha de largada
			var de := _ceu(pista, 1.0)
			var ate := _grid(mapa, 0.0)
			var meio: Vector3 = (de[0] as Vector3).lerp(ate[0], 0.5) + Vector3.UP * 20.0
			var a: Vector3 = (de[0] as Vector3).lerp(meio, suave)
			var b: Vector3 = meio.lerp(ate[0], suave)
			pose = [a.lerp(b, suave), (de[1] as Vector3).lerp(ate[1], suave)]
		_:
			pose = _grid(mapa, smoothstep(0.0, 1.0, minf(abertura_tempo / 8.0, 1.0)))
	return Transform3D(Basis.looking_at(pose[1] - pose[0], Vector3.UP), pose[0])

## Direção no plano do chão (sem subir/descer)
func _plano(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD

# --- Pódio e ranking ------------------------------------------------------------------

## Resultado pronto para o pódio: todos os jogadores reais do mapa receberam a
## bandeirada (ou já saíram dele) há PODIO_ESPERA s, ou PODIO_ESPERA_MAX desde o primeiro
func _resultado_pronto() -> Dictionary:
	for nome_mapa in _resultados:
		var res: Dictionary = _resultados[nome_mapa]
		var espera := _relogio - float(res.primeiro_em)
		var faltando := false
		for peer in carros:
			var d: Dictionary = dados[peer]
			if str(d.get("mapa", "")) == nome_mapa and not d.get("chegou", false):
				faltando = true
		if (not faltando and espera >= PODIO_ESPERA) or espera >= PODIO_ESPERA_MAX:
			return res
	return {}

## Os três primeiros: pela ordem da bandeirada; reais com a pintura e o tempo deles, a
## IA com a pintura do número dela
func _lugares(res: Dictionary) -> Array:
	var lugares := []
	for linha in res.chegada:
		if lugares.size() >= 3:
			break
		var nome := str(linha[0])
		var real: bool = linha[1]
		if real:
			var info: Dictionary = res.reais.get(nome.to_upper(), {})
			lugares.append({"nome": nome, "real": true, "pintura": info.get("pintura", PINTURAS_JOGADOR[0]), "numero": 0, "tempo": float(info.get("tempo", -1.0))})
		else:
			var i := 0
			for k in _elenco.size():
				if _elenco[k].nome == nome:
					i = k
			lugares.append({"nome": nome, "real": false, "pintura": CarroRival.PINTURAS[i % CarroRival.PINTURAS.size()], "numero": i + 1, "tempo": -1.0})
	# Sem a ordem (telemetria antiga): os reais anotados
	if lugares.is_empty():
		for nome in res.reais:
			lugares.append({"nome": nome, "real": true, "pintura": res.reais[nome].pintura, "numero": 0, "tempo": float(res.reais[nome].tempo)})
	return lugares

func _abrir_podio(res: Dictionary):
	var nome_mapa: String = res.mapa
	_resultados.erase(nome_mapa)
	_podio_feito[nome_mapa] = true
	var mapa: MapaCorrida = mapas.get(nome_mapa)
	if mapa == null:
		return
	estado = Estado.PODIO
	_tempo_estado = 0.0
	if abertura_mapa != "":
		_fechar_abertura([])
	_aplicar_mundo(nome_mapa)
	ambiente.environment = _ambiente_aereo(nome_mapa)
	_hud.modo_corrida(false)
	var lugares := _lugares(res)
	_podio = PodioEspectador.new()
	add_child(_podio)
	_podio.montar(mapa.pista, lugares)
	camera.global_transform = _podio.pose_camera(0.0)
	_hud.corte(0.8)
	var vencedor: Dictionary = lugares[0] if not lugares.is_empty() else {"nome": "-", "real": false}
	_hud.mostrar_podio(nome_mapa, str(vencedor.nome), vencedor.real)
	_podio_destaques = res.reais.keys()

var _podio_destaques: Array = []

func _rodar_podio(delta: float, grid: String, lista: Array):
	if _podio == null:
		estado = Estado.ESPERA
		return
	var desejada := _podio.pose_camera(_tempo_estado / TEMPO_PODIO)
	camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-4.0 * delta))
	# Uma largada já contando não espera o pódio acabar
	var contando := grid != "" and _no_mapa(lista, grid).any(func(p): return int(dados[p].get("fase", -1)) == Corrida.Fase.CONTAGEM)
	if _tempo_estado >= TEMPO_PODIO or contando:
		_fechar_podio()
		if contando:
			estado = Estado.ESPERA
		else:
			_abrir_ranking(_podio_destaques)

func _fechar_podio():
	if _podio:
		_podio.queue_free()
		_podio = null
	_hud.esconder_podio()
	mundo_atual = "-"

func _abrir_ranking(destaques: Array):
	estado = Estado.RANKING
	_tempo_estado = 0.0
	_aplicar_mundo("")
	_hud.corte(0.5)
	_hud.mostrar_ranking_final(destaques)

func _rodar_ranking(grid: String, _lista: Array):
	_orbitar(get_process_delta_time())
	# Um grid novo interrompe o ranking (a abertura não pode ser perdida)
	if _tempo_estado >= TEMPO_RANKING or grid != "":
		_hud.esconder_ranking_final()
		_hud.corte(0.5)
		estado = Estado.ESPERA

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

## Ensaio no evento: pódio com o que a torre mostra agora (P)
func _podio_de_ensaio():
	var item: Dictionary = dados.get(foco, {})
	var nome_mapa := str(item.get("mapa", ""))
	if not mapas.has(nome_mapa):
		nome_mapa = "Deserto"
	var chegada := []
	for linha in _classificacao(nome_mapa, item):
		chegada.append([linha.nome, linha.real])
	var reais := {}
	for peer in carros:
		reais[_nome(dados[peer]).to_upper()] = {"tempo": float(dados[peer].get("tempo_total", -1.0)), "pintura": _pinturas.get(peer, PINTURAS_JOGADOR[0])}
	if chegada.is_empty():
		chegada = [[_elenco[0].nome, false], [_elenco[1].nome, false], [_elenco[2].nome, false]]
	_abrir_podio({"mapa": nome_mapa, "primeiro_em": _relogio, "chegada": chegada, "reais": reais, "peers": {}})

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
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			angulo_fixo = event.keycode - KEY_1
			_cortar(foco, angulo_fixo)
		KEY_0:
			angulo_fixo = -1
		KEY_A:
			if abertura_mapa != "":
				_abertura_pulada = abertura_mapa
		KEY_P:
			if estado != Estado.PODIO:
				_podio_de_ensaio()
		KEY_R:
			if estado == Estado.PODIO:
				_fechar_podio()
			_abrir_ranking([])
		KEY_F11:
			var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia else DisplayServer.WINDOW_MODE_FULLSCREEN)
