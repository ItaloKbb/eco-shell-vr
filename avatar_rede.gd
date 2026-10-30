class_name AvatarRede
extends Node3D
## Avatar de um jogador no lobby compartilhado. A raiz é só rede: um
## MultiplayerSynchronizer com a pose do carro e o contador de nitros (o ronco toca no
## avatar quando o dono liga o nitro), cuja autoridade é o próprio dono.
## O servidor cria e remove (Rede._criar_avatar, pelo MultiplayerSpawner); o visual
## (o mesmo carro dos jogadores na corrida e no telão: CarroFantasma, com casco
## pintado, rodas, nome e anel neon) só existe nos clientes, e nunca no do próprio
## dono, que já tem o carro de verdade.

## Pose enviada 30 vezes por segundo junto com o relógio do dono (`t`); o visual
## interpola entre as poses no tempo em que foram medidas (InterpoladorRede)
const INTERVALO_SYNC := 1.0 / 30.0

var peer := 0
var nome := ""
## Relógio do dono quando a pose foi tirada (sincronizado junto com ela)
var t := 0.0
## Quantas vezes o dono ligou o nitro (sincronizado); -1 visto = ainda não recebido
var nitros := 0
var _nitros_visto := -1
var _com_visual := false
var _visual: CarroFantasma
var _carro: Node3D
var _interpolador := InterpoladorRede.new()
var _ultimo_t := -1.0

func _init(peer_: int, nome_: String, com_visual: bool):
	peer = peer_
	nome = nome_
	name = str(peer_)
	var config := SceneReplicationConfig.new()
	for propriedade in [NodePath(".:position"), NodePath(".:quaternion"), NodePath(".:t"), NodePath(".:nitros")]:
		config.add_property(propriedade)
		config.property_set_spawn(propriedade, false)
		config.property_set_replication_mode(propriedade, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.replication_interval = INTERVALO_SYNC
	add_child(sync)
	set_multiplayer_authority(peer_)
	_com_visual = com_visual

## O casco dos carros só é gerado com um nó na árvore (CarroRival.preparar)
func _ready():
	if _com_visual:
		CarroRival.preparar(self)
		var pintura: Array = CarroFantasma.PINTURAS_JOGADOR[peer % CarroFantasma.PINTURAS_JOGADOR.size()]
		_visual = CarroFantasma.new(pintura, nome, 0, true)
		_visual.name = "Visual"
		_visual.top_level = true
		add_child(_visual)
		_visual.global_transform = global_transform

func _process(delta: float):
	if peer == multiplayer.get_unique_id():
		# Dono: a pose do avatar é a do carro local
		if not is_instance_valid(_carro):
			_carro = get_tree().get_first_node_in_group("carro") as Node3D
		if _carro:
			global_transform = _carro.global_transform
			t = InterpoladorRede.agora()
			nitros = int(_carro.get("nitros_ligados"))
	elif _visual:
		# Pose nova chegou (o `t` muda junto): entra no interpolador
		if t != _ultimo_t:
			_ultimo_t = t
			_interpolador.adicionar(t, position, quaternion)
		if not _interpolador.vazio():
			var antes := _visual.global_position
			_visual.global_transform = _interpolador.pose()
			# Rodas pela velocidade da pose interpolada (a pose não traz velocidade)
			if delta > 0.0:
				_visual.vel = lerpf(_visual.vel, (_visual.global_position - antes).length() / delta, 0.3)
		# Só depois da primeira pose: o contador chega no mesmo pacote dela
		if t > 0.0:
			if _nitros_visto >= 0 and nitros > _nitros_visto:
				CarroFantasma.roncar(_visual)
			_nitros_visto = nitros
