extends Node
## Troca de mapa pelos portais. O mundo neon e o deserto ficam na mesma cena: o
## deserto é montado longe (ORIGEM_DESERTO) na primeira visita. Atravessar o portal
## âmbar cobre a visão, desliga o mundo neon (chão, névoa, portais, pirâmides),
## troca céu e sol, e leva o carro para a largada do circuito; o portal de volta faz o
## caminho contrário, deixando o carro perto do portal âmbar, de costas para ele.

const ORIGEM_DESERTO := Vector3(4000.0, 0.0, 0.0)

@export var carro: RigidBody3D
@export var hex_world: Node3D
@export var atmosfera: Node3D
@export var portais: Node3D
@export var inimigos: Node3D
@export var ambiente: WorldEnvironment
@export var sol: DirectionalLight3D
@export var musica: Node

var deserto: Deserto
var no_deserto := false

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
	if no_deserto:
		await voltar()

func _portal(portal: Portal):
	if portal.destino_corrida == "Deserto":
		entrar_deserto(portal)
	else:
		# Os outros ainda não levam a lugar nenhum: avisa no visor
		carro._avisar("PORTAL FECHADO", 2.0)
		carro.sem_energia.emit()

func entrar_deserto(portal: Portal):
	if _trocando or no_deserto:
		return
	_trocando = true
	_portal_ida = portal
	# Lado de onde o carro veio: na volta ele reaparece desse lado, de costas para o portal
	_volta_fora = Vector3(carro.global_basis.z.x, 0.0, carro.global_basis.z.z)
	carro.iniciar_transicao()
	await _transicao.cobrir(portal.cor, 0.5, "Corrida / Deserto")

	# Desliga o mundo neon (e tira os inimigos de cena)
	hex_world.desligar()
	atmosfera.visible = false
	for no in [portais, inimigos]:
		no.visible = false
		no.process_mode = Node.PROCESS_MODE_DISABLED
	for grupo in ["piramides", "misseis"]:
		for no in get_tree().get_nodes_in_group(grupo):
			no.queue_free()

	if deserto == null:
		deserto = Deserto.new()
		deserto.construcao_progressiva = true
		deserto.etapa_carregamento.connect(func(etapa: String): _transicao.atualizar_loading("Corrida / Deserto", etapa))
		deserto.position = ORIGEM_DESERTO
		add_child(deserto)
		await deserto.construir()
		deserto.portal_volta.alvo = carro
		deserto.portal_volta.atravessado.connect(voltar)
		deserto.corrida.carro = carro
	_transicao.atualizar_loading("Corrida / Deserto", "Posicionando piloto na largada")
	await get_tree().process_frame
	deserto.visible = true
	deserto.process_mode = Node.PROCESS_MODE_INHERIT

	_ambiente_hex = ambiente.environment
	ambiente.environment = deserto.ambiente
	_sol_hex = {"transform": sol.transform, "cor": sol.light_color, "energia": sol.light_energy, "sombra": sol.shadow_enabled}
	sol.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sol.light_color = Color(1.0, 0.93, 0.82)
	sol.light_energy = 1.5
	sol.shadow_enabled = not OS.has_feature("android")

	carro.hex_world = deserto
	carro.pode_voar = false
	# No grid o carro já fica assentado nas rodas: desconta a folga que teleportar põe
	carro.teleportar(deserto.largada().translated(Vector3.DOWN * 0.3))
	carro.segurar()
	carro.atualizar_ambiente_traseira()
	no_deserto = true
	await get_tree().physics_frame
	await _transicao.descobrir()
	carro.terminar_transicao()
	deserto.corrida.iniciar()
	var yui := get_tree().get_first_node_in_group("yui")
	if yui:
		yui.falar_corrida()
	if musica:
		musica.tocar_corrida()
	_trocando = false

func voltar():
	if _trocando or not no_deserto:
		return
	_trocando = true
	carro.iniciar_transicao()
	await _transicao.cobrir(deserto.portal_volta.cor, 0.5, "Mundo Neon")
	_transicao.atualizar_loading("Mundo Neon", "Restaurando ambiente")
	await get_tree().process_frame

	deserto.visible = false
	deserto.process_mode = Node.PROCESS_MODE_DISABLED
	deserto.corrida.abortar()
	if musica:
		musica.voltar_playlist()
	ambiente.environment = _ambiente_hex
	sol.transform = _sol_hex["transform"]
	sol.light_color = _sol_hex["cor"]
	sol.light_energy = _sol_hex["energia"]
	sol.shadow_enabled = _sol_hex["sombra"]

	hex_world.ligar()
	atmosfera.visible = true
	for no in [portais, inimigos]:
		no.visible = true
		no.process_mode = Node.PROCESS_MODE_INHERIT

	# Perto do portal âmbar, fora do alcance do puxão, de costas para ele
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
	no_deserto = false
	_transicao.atualizar_loading("Mundo Neon", "Estabilizando o piso de energia")
	# Aguarda um frame de física para reativar a colisão antes de revelar o mundo.
	await get_tree().process_frame
	while hex_world.carregando():
		await get_tree().process_frame
	await get_tree().physics_frame
	await _transicao.descobrir()
	carro.terminar_transicao()
	_trocando = false
