extends Node
## Troca de mapa pelos portais. O mundo neon e os mapas de corrida (MapaCorrida: o
## Deserto e o Vale das Turbinas) ficam na mesma cena: cada mapa é montado longe, na
## sua ORIGEM, na primeira visita. Atravessar um portal de corrida cobre a visão,
## desliga o mundo neon (chão, névoa, portais), troca céu e sol, e leva o
## carro para a largada do circuito; o portal de volta faz o caminho contrário,
## deixando o carro perto do portal de onde veio, de costas para ele.

const ORIGEM_DESERTO := Vector3(4000.0, 0.0, 0.0)
const ORIGEM_TURBINAS := Vector3(-4000.0, 0.0, 0.0)
## Destino do portal (Portal.destino_corrida) -> [classe do mapa, onde fica]
var _destinos := {
	"Deserto": [Deserto, ORIGEM_DESERTO],
	"Vale das Turbinas": [ValeTurbinas, ORIGEM_TURBINAS],
}

@export var carro: RigidBody3D
@export var hex_world: Node3D
@export var atmosfera: Node3D
@export var portais: Node3D
@export var ambiente: WorldEnvironment
@export var sol: DirectionalLight3D
@export var musica: Node

## Mapas já montados, pelo destino
var mapas := {}
## Mapa de corrida onde o piloto está (null no mundo neon)
var mapa_atual: MapaCorrida
var deserto: Deserto:
	get: return mapas.get("Deserto")
var turbinas: ValeTurbinas:
	get: return mapas.get("Vale das Turbinas")
var no_deserto: bool:
	get: return mapa_atual != null and mapa_atual == deserto
var no_mapa_corrida: bool:
	get: return mapa_atual != null

var _trocando := false
var _portal_ida: Portal
var _transicao := Transicao.new()
var _ambiente_hex: Environment
var _sol_hex := {}
var _volta_fora := Vector3.BACK

func _ready():
	portais.portal_atravessado.connect(_portal)
	add_child(_transicao)

## A morte sempre devolve o piloto à esfera do mundo inicial.
func restaurar_inicio():
	while _trocando:
		await get_tree().process_frame
	if mapa_atual:
		await voltar()

func _portal(portal: Portal):
	if _destinos.has(portal.destino_corrida):
		entrar_mapa(portal, portal.destino_corrida)
	else:
		# Os outros ainda não levam a lugar nenhum: avisa no visor
		carro._avisar("PORTAL FECHADO", 2.0)
		carro.sem_energia.emit()

func entrar_deserto(portal: Portal):
	await entrar_mapa(portal, "Deserto")

func entrar_mapa(portal: Portal, destino: String):
	if _trocando or mapa_atual:
		return
	_trocando = true
	_portal_ida = portal
	# Evento: o servidor tira o avatar do lobby antes de o piloto sair
	await Rede.informar_estado("correndo")
	var titulo := "Corrida / " + destino
	# Lado de onde o carro veio: na volta ele reaparece desse lado, de costas para o portal
	_volta_fora = Vector3(carro.global_basis.z.x, 0.0, carro.global_basis.z.z)
	carro.iniciar_transicao()
	await _transicao.cobrir(portal.cor, 0.5, titulo)

	# Desliga o mundo neon
	hex_world.desligar()
	atmosfera.visible = false
	portais.visible = false
	portais.process_mode = Node.PROCESS_MODE_DISABLED

	var mapa: MapaCorrida = mapas.get(destino)
	if mapa == null:
		mapa = _destinos[destino][0].new()
		mapa.construcao_progressiva = true
		mapa.etapa_carregamento.connect(func(etapa: String): _transicao.atualizar_loading(titulo, etapa))
		mapa.position = _destinos[destino][1]
		add_child(mapa)
		await mapa.construir()
		mapa.portal_volta.alvo = carro
		mapa.portal_volta.atravessado.connect(voltar)
		mapa.corrida.carro = carro
		mapa.corrida.terminou.connect(func(total: float, _melhor: float): Rede.registrar_tempo(total, destino))
		mapas[destino] = mapa
	_transicao.atualizar_loading(titulo, "Posicionando piloto na largada")
	await get_tree().process_frame
	mapa.visible = true
	mapa.process_mode = Node.PROCESS_MODE_INHERIT

	_ambiente_hex = ambiente.environment
	ambiente.environment = mapa.ambiente
	_sol_hex = {"transform": sol.transform, "cor": sol.light_color, "energia": sol.light_energy, "sombra": sol.shadow_enabled}
	mapa.sol(sol)
	sol.shadow_enabled = not OS.has_feature("android")

	carro.hex_world = mapa
	carro.pode_voar = false
	# No grid o carro já fica assentado nas rodas: desconta a folga que teleportar põe
	carro.teleportar(mapa.largada().translated(Vector3.DOWN * 0.3))
	carro.segurar()
	carro.atualizar_ambiente_traseira()
	mapa_atual = mapa
	await get_tree().physics_frame
	await _transicao.descobrir()
	carro.terminar_transicao()
	mapa.corrida.iniciar()
	var yui := get_tree().get_first_node_in_group("yui")
	if yui:
		yui.falar_corrida(mapa.fala_chegada)
	if musica:
		musica.tocar_corrida(mapa.faixa_corrida)
	_trocando = false

func voltar():
	if _trocando or mapa_atual == null:
		return
	_trocando = true
	var mapa := mapa_atual
	carro.iniciar_transicao()
	await _transicao.cobrir(mapa.portal_volta.cor, 0.5, "Mundo Neon")
	_transicao.atualizar_loading("Mundo Neon", "Restaurando ambiente")
	await get_tree().process_frame

	mapa.visible = false
	mapa.process_mode = Node.PROCESS_MODE_DISABLED
	mapa.corrida.abortar()
	if musica:
		musica.voltar_playlist()
	ambiente.environment = _ambiente_hex
	sol.transform = _sol_hex["transform"]
	sol.light_color = _sol_hex["cor"]
	sol.light_energy = _sol_hex["energia"]
	sol.shadow_enabled = _sol_hex["sombra"]

	hex_world.ligar()
	atmosfera.visible = true
	portais.visible = true
	portais.process_mode = Node.PROCESS_MODE_INHERIT

	# Perto do portal de ida, fora do alcance do puxão, de costas para ele
	var centro := _portal_ida.global_position
	var fora := _volta_fora
	if fora.length() < 0.1:
		fora = Vector3.BACK
	var pos := centro + fora.normalized() * (Portal.ALCANCE_PUXAO + 6.0)
	pos.y = hex_world.altura(pos.x, pos.z) + 0.5
	carro.hex_world = hex_world
	carro.pode_voar = true
	carro.teleportar(Transform3D(Basis.looking_at(fora.normalized(), Vector3.UP), pos), true)
	carro.atualizar_ambiente_traseira()
	mapa_atual = null
	_transicao.atualizar_loading("Mundo Neon", "Estabilizando o piso de energia")
	# Aguarda um frame de física para reativar a colisão antes de revelar o mundo.
	await get_tree().process_frame
	while hex_world.carregando():
		await get_tree().process_frame
	await get_tree().physics_frame
	await _transicao.descobrir()
	carro.terminar_transicao()
	if Rede.liberado:
		Rede.informar_estado("lobby")
	_trocando = false
