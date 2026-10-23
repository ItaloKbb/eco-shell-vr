class_name AvatarRede
extends Node3D
## Avatar de um jogador no lobby compartilhado. A raiz é só rede: um
## MultiplayerSynchronizer com a pose do carro, cuja autoridade é o próprio dono.
## O servidor cria e remove (Rede._criar_avatar, pelo MultiplayerSpawner); o visual
## (casco neon e o nome por cima) só existe nos clientes, e nunca no do próprio dono,
## que já tem o carro de verdade.

## Pose enviada 20 vezes por segundo; o visual suaviza entre uma e outra
const INTERVALO_SYNC := 0.05
const COR := Color(1.0, 0.45, 0.15)

var peer := 0
var nome := ""
var _visual: Node3D
var _carro: Node3D

func _init(peer_: int, nome_: String, com_visual: bool):
	peer = peer_
	nome = nome_
	name = str(peer_)
	var config := SceneReplicationConfig.new()
	for propriedade in [NodePath(".:position"), NodePath(".:rotation")]:
		config.add_property(propriedade)
		config.property_set_spawn(propriedade, false)
		config.property_set_replication_mode(propriedade, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.replication_interval = INTERVALO_SYNC
	add_child(sync)
	set_multiplayer_authority(peer_)
	if com_visual:
		_visual = _montar_visual()
		add_child(_visual)

func _ready():
	if _visual:
		_visual.global_transform = global_transform

func _process(delta: float):
	if peer == multiplayer.get_unique_id():
		# Dono: a pose do avatar é a do carro local
		if not is_instance_valid(_carro):
			_carro = get_tree().get_first_node_in_group("carro") as Node3D
		if _carro:
			global_transform = _carro.global_transform
	elif _visual:
		var peso := 1.0 - exp(-12.0 * delta)
		_visual.global_transform = _visual.global_transform.interpolate_with(global_transform, peso)

func _montar_visual() -> Node3D:
	var raiz := Node3D.new()
	raiz.name = "Visual"
	raiz.top_level = true
	var casco := MeshInstance3D.new()
	var caixa := BoxMesh.new()
	caixa.size = Vector3(1.0, 0.45, 2.1)
	casco.mesh = caixa
	casco.position.y = 0.45
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.03, 0.03, 0.08)
	material.metallic = 0.8
	material.roughness = 0.3
	material.emission_enabled = true
	material.emission = COR
	material.emission_energy_multiplier = 0.6
	casco.material_override = material
	raiz.add_child(casco)
	# Filete neon na base, como os carros do mundo
	var filete := MeshInstance3D.new()
	var barra := BoxMesh.new()
	barra.size = Vector3(1.08, 0.06, 2.18)
	filete.mesh = barra
	filete.position.y = 0.25
	var neon := StandardMaterial3D.new()
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.albedo_color = COR
	neon.emission_enabled = true
	neon.emission = COR
	neon.emission_energy_multiplier = 3.0
	filete.material_override = neon
	raiz.add_child(filete)
	var rotulo := Label3D.new()
	rotulo.text = nome
	rotulo.position.y = 1.6
	rotulo.pixel_size = 0.006
	rotulo.font_size = 64
	rotulo.outline_size = 12
	rotulo.modulate = COR
	rotulo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rotulo.no_depth_test = true
	raiz.add_child(rotulo)
	return raiz
