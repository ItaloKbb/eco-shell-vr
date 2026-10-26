extends Node3D
## Piso contínuo do mundo inicial, partido em dois pelo abismo das estruturas neon
## (EstruturasNeon): uma malha e uma colisão de cada lado evitam o serrilhado, os
## degraus e o ruído visual dos antigos milhares de hexágonos.

const FLOOR_SHADER := preload("res://tron_ground.gdshader")

## Mantidos por compatibilidade com o perfil VR e cenas antigas. O piso contínuo
## nasce inteiro no primeiro frame, portanto não possui fila de chunks.
@export var view_distance := 45.0
@export var chunks_per_frame := 1
@export var world_size := 6000.0
@export_flags_3d_physics var collision_layer := 1

var _corpo: StaticBody3D
var estruturas: EstruturasNeon

func _ready():
	_criar_piso()
	estruturas = EstruturasNeon.new()
	estruturas.name = "Estruturas"
	estruturas.collision_layer = collision_layer
	add_child(estruturas)

## Dois retângulos de piso, um de cada lado do abismo (faixa em z, de borda a borda)
func _criar_piso():
	var meio := world_size * 0.5
	var sul := EstruturasNeon.ABISMO_Z + EstruturasNeon.ABISMO_MEIA
	var norte := EstruturasNeon.ABISMO_Z - EstruturasNeon.ABISMO_MEIA
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	_corpo = StaticBody3D.new()
	_corpo.name = "ColisaoPiso"
	_corpo.collision_layer = collision_layer
	_corpo.collision_mask = 0
	add_child(_corpo)
	# [nome, z inicial, z final]
	for faixa in [["PisoSul", sul, meio], ["PisoNorte", -meio, norte]]:
		var profundidade: float = faixa[2] - faixa[1]
		var centro_z: float = (faixa[1] + faixa[2]) * 0.5
		var malha := PlaneMesh.new()
		malha.size = Vector2(world_size, profundidade)
		malha.material = material
		var piso := MeshInstance3D.new()
		piso.name = faixa[0]
		piso.mesh = malha
		piso.position.z = centro_z
		# O piso é plano e não precisa projetar nem receber sombras. O shader já contém
		# a iluminação estilizada; isto também reduz trabalho extra por olho no VR.
		piso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piso.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(piso)
		var forma := CollisionShape3D.new()
		forma.name = "Forma" + faixa[0].substr(4)
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(world_size, 1.0, profundidade)
		forma.shape = caixa
		forma.position = Vector3(0.0, -0.5, centro_z)
		_corpo.add_child(forma)

## Usado pela troca de mundos: oculta o piso e remove sua colisão.
func desligar():
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	if _corpo:
		_corpo.process_mode = Node.PROCESS_MODE_DISABLED

## Restaura imediatamente o piso completo; não há geração progressiva.
func ligar():
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if _corpo:
		_corpo.process_mode = Node.PROCESS_MODE_INHERIT

func carregando() -> bool:
	return false

## O piso é plano. Sobre o abismo também responde 0: é o "piso de energia" do voo
## (o planador não mergulha no abismo); quem cai de carro explode e renasce na esfera.
func altura(_x: float, _z: float) -> float:
	return 0.0

## Fora do abismo e das estruturas, com folga `raio` (portais e retorno do deserto)
func area_livre(p: Vector3, raio: float) -> bool:
	return estruturas == null or estruturas.area_livre(p, raio)
