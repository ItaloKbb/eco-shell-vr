extends Node3D
## Espalha pirâmides pelo mapa em volta do carro: no máximo algumas por perto, longe
## da praça inicial, flutuando paradas até o jogador chegar perto. As que ficaram para
## trás (e não estão perseguindo) somem, e outras aparecem mais à frente.

@export var hex_world: Node3D
@export var maximo := 3
@export var distancia_min := 60.0
@export var distancia_max := 120.0
## Pirâmides além disso, ociosas, são removidas
@export var distancia_some := 220.0
## Nada nasce perto do ponto de partida
@export var raio_praca := 25.0
@export var altura := 4.0

var _relogio := 0.0

func _physics_process(delta: float):
	_relogio -= delta
	if _relogio > 0.0:
		return
	_relogio = 2.0
	var carro := get_tree().get_first_node_in_group("carro") as RigidBody3D
	if carro == null or carro.em_ritual or carro.explodindo:
		return
	var vivas := 0
	for piramide: Piramide in get_tree().get_nodes_in_group("piramides"):
		if piramide.estado == Piramide.OCIOSA and piramide.global_position.distance_to(carro.global_position) > distancia_some:
			piramide.queue_free()
		else:
			vivas += 1
	if vivas < maximo:
		_nascer(carro)

func _nascer(carro: RigidBody3D):
	for tentativa in 8:
		var a := randf() * TAU
		var d := randf_range(distancia_min, distancia_max)
		var p := carro.global_position + Vector3(cos(a), 0.0, sin(a)) * d
		if Vector2(p.x, p.z).length() < raio_praca:
			continue
		p.y = (hex_world.altura(p.x, p.z) if hex_world else 0.0) + altura
		var piramide := Piramide.new()
		piramide.alvo = carro
		piramide.hex_world = hex_world
		add_child(piramide)
		piramide.global_position = p
		return
