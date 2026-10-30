class_name ObstaculoPista
extends Node3D
## Base dos obstáculos móveis da pista (varredora, comportas, guindaste, minas). Cada um é
## descrito em coordenadas da pista em volta do seu ponto s0: ds ao longo da volta
## (positivo = à frente) e d de lado (positivo = à direita), em função do tempo da
## corrida. A mesma conta anima a malha, acerta o jogador e guia os adversários
## (ObstaculosPista), então o que se vê é exatamente o que bloqueia.
## O nó fica na pose da pista em s0 (local: -Z frente, X direita, Y para cima).

## Meio comprimento do carro e meia largura, para a folga das contas (m)
const MEIO_CARRO := 1.35
const MEIA_LARGURA_CARRO := 0.5

## Distância ao longo da volta do centro do obstáculo (m)
var s0 := 0.0
## Até onde (|ds|) o obstáculo pode bloquear, já com a folga do carro
var alcance_s := 3.0
## Aviso no visor quando o piloto chega perto
var aviso := "OBSTÁCULO"
## Aviso no visor quando o piloto bate nele
var aviso_batida := "BATEU!"
## Sólido: quem bate é jogado para fora dele e fica parado um tempo. Falso (minas): o
## carro passa por cima e o próprio obstáculo decide o efeito em atingido()
var solido := true
## Cor do material "perigo" (listras, luzes)
const COR_PERIGO := Color(1.0, 0.55, 0.05)

## O carro com centro em (ds, d) encosta no obstáculo no instante t?
func bloqueia(_ds: float, _d: float, _t: float) -> bool:
	return false

## Para que lado (+1 direita, -1 esquerda) empurrar quem bateu em (ds, d)
func lado_empurrao(_ds: float, d: float, _t: float) -> float:
	return signf(d) if d != 0.0 else 1.0

## Põe a malha na pose do instante t
func animar(_t: float):
	pass

## Alguém bateu nele em (ds, d) no instante t: o jogador (`carro`) ou um adversário
## (`carro` null). Uma vez por batida, depois do tranco e do dano
func atingido(_ds: float, _d: float, _t: float, _carro: RigidBody3D):
	pass

# --- Peças em comum ----------------------------------------------------------------

static func material_metal(cor: Color, metalico := 0.6, aspereza := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.metallic = metalico
	m.roughness = aspereza
	return m

static func material_luz(cor: Color, energia := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.emission_enabled = true
	m.emission = cor
	m.emission_energy_multiplier = energia
	return m

func caixa(tamanho: Vector3, material: Material, posicao := Vector3.ZERO, pai: Node3D = null) -> MeshInstance3D:
	var malha := BoxMesh.new()
	malha.size = tamanho
	malha.material = material
	var m := MeshInstance3D.new()
	m.mesh = malha
	m.position = posicao
	(pai if pai else self).add_child(m)
	return m

func cilindro(raio: float, altura: float, material: Material, posicao := Vector3.ZERO, pai: Node3D = null) -> MeshInstance3D:
	var malha := CylinderMesh.new()
	malha.top_radius = raio
	malha.bottom_radius = raio
	malha.height = altura
	malha.radial_segments = 16
	malha.material = material
	var m := MeshInstance3D.new()
	m.mesh = malha
	m.position = posicao
	(pai if pai else self).add_child(m)
	return m
