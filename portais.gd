extends Node3D
## Mantém sempre os portais de corrida espalhados pelo mapa, um de cada cor, longe uns
## dos outros e fora da praça inicial. Quando o carro se afasta demais de um, ele é
## levado para um lugar novo mais perto (mantendo a cor).

@export var hex_world: Node3D
@export var distancia_min := 100.0
@export var distancia_max := 300.0
## Portal mais longe que isso do carro é levado para perto de novo
@export var distancia_reposiciona := 450.0
@export var separacao := 90.0
@export var raio_praca := 40.0

## Uma cor marcante por portal (sem o vermelho dos inimigos)
const CORES: Array[Color] = [
	Color(0.1, 0.85, 1.0), # ciano
	Color(1.0, 0.2, 0.8), # magenta
	Color(0.45, 1.0, 0.15), # verde-ácido
	Color(1.0, 0.6, 0.08), # âmbar
	Color(0.55, 0.3, 1.0), # violeta
]

## O carro entrou num dos portais (mundos.gd decide para onde ele leva)
signal portal_atravessado(portal: Portal)

## Índice da cor do portal que leva ao deserto (âmbar)
const AMBAR := 3
## O carmesim usa o portal avermelhado/magenta já existente.
const CARMESIM := 1
const CORRIDAS := { CARMESIM: "Deserto", AMBAR: "Deserto" }

var _portais: Array[Portal] = []
var _relogio := 0.0

func _physics_process(delta: float):
	_relogio -= delta
	if _relogio > 0.0:
		return
	_relogio = 1.0
	var carro := get_tree().get_first_node_in_group("carro") as RigidBody3D
	if carro == null:
		return
	if _portais.is_empty():
		for indice in CORES.size():
			var portal := Portal.new()
			portal.cor = CORES[indice]
			portal.destino_corrida = CORRIDAS.get(indice, "")
			portal.alvo = carro
			portal.atravessado.connect(func(): portal_atravessado.emit(portal))
			_portais.append(portal)
			# Posiciona antes de entrar na cena (a posição vale para o _ready)
			portal.position = _lugar_livre(carro.global_position, portal)
			portal.rotation.y = randf() * TAU
			add_child(portal)
		return
	for portal in _portais:
		if portal.global_position.distance_to(carro.global_position) > distancia_reposiciona:
			portal.global_position = _lugar_livre(carro.global_position, portal)
			portal.rotation.y = randf() * TAU

func _lugar_livre(centro: Vector3, quem: Portal) -> Vector3:
	var p := Vector3.ZERO
	for tentativa in 30:
		var a := randf() * TAU
		var d := randf_range(distancia_min, distancia_max)
		p = centro + Vector3(cos(a), 0.0, sin(a)) * d
		if Vector2(p.x, p.z).length() < raio_praca:
			continue
		var longe := true
		for outro in _portais:
			if outro != quem and outro.is_inside_tree() and Vector2(outro.global_position.x - p.x, outro.global_position.z - p.z).length() < separacao:
				longe = false
				break
		if longe:
			break
	p.y = hex_world.altura(p.x, p.z) if hex_world else 0.0
	return p
