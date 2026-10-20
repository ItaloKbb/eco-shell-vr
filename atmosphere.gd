extends Node3D
## Névoa de tempestade de luz volumétrica que acompanha a câmera em X/Z.
## O ruído do shader é ancorado no mundo, então a névoa não "anda junto" com o jogador.

const STORM_SHADER := preload("res://storm_fog.gdshader")

## Cobre do chão até acima da camada de nuvens (cloud_top no shader)
@export var size := Vector3(110.0, 26.0, 110.0)

func _ready():
	var mat := ShaderMaterial.new()
	mat.shader = STORM_SHADER

	var fog := FogVolume.new()
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = size
	fog.material = mat
	fog.position.y = size.y * 0.5 - 1.0
	add_child(fog)

func _process(_delta):
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = Vector3(cam.global_position.x, 0.0, cam.global_position.z)
