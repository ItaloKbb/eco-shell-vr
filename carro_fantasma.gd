class_name CarroFantasma
extends Node3D
## Carro vindo da rede (telão do espectador e os outros jogadores numa corrida em
## grupo): o visual do rival (CarroRival.montar_visual: casco pintado, rodas, nome),
## sem física, seguindo a pose recebida pelo InterpoladorRede. Rodas giram pela
## velocidade. `translucido`: os outros jogadores na corrida, que a gente atravessa.
## Precisa de CarroRival.preparar() antes.

## [lataria, filete] dos jogadores (os rivais usam CarroRival.PINTURAS)
const PINTURAS_JOGADOR := [
	[Color(0.03, 0.2, 0.34), Color(0.45, 0.9, 1.0)],
	[Color(0.3, 0.04, 0.3), Color(1.0, 0.5, 0.95)],
	[Color(0.34, 0.2, 0.02), Color(1.0, 0.8, 0.3)],
	[Color(0.04, 0.28, 0.12), Color(0.5, 1.0, 0.6)],
]

var giros: Array[Node3D] = []
var rotulo: Label3D
var interpolador := InterpoladorRede.new()
## m/s, para girar as rodas
var vel := 0.0
var explodindo := false
## Quantas vezes o dono ligou o nitro (telemetria "nitros"); -1 = ainda não visto
var _nitros := -1

func _init(pintura: Array, nome: String, numero: int, jogador: bool, translucido := false):
	var visual := CarroRival.montar_visual(self, pintura, nome, numero)
	giros = visual.giros
	rotulo = visual.nome
	if jogador:
		# Jogador: nome do mesmo tamanho na tela em qualquer distância, branco com
		# contorno, sempre por cima do cenário
		rotulo.fixed_size = true
		rotulo.font_size = 64
		rotulo.pixel_size = 0.0009
		rotulo.outline_size = 18
		rotulo.position.y = 1.8
		rotulo.modulate = Color(1.0, 1.0, 1.0)
		rotulo.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		rotulo.visibility_range_end = 0.0
		rotulo.no_depth_test = true
		_anel(pintura[1])
	if translucido:
		for filho in get_children():
			if filho is GeometryInstance3D and not filho is Label3D:
				filho.transparency = 0.45
			for neto in filho.get_children():
				if neto is GeometryInstance3D:
					neto.transparency = 0.45

## Anel neon no chão, na cor do filete: destaca o jogador no piso escuro do lobby e o
## separa dos adversários na corrida (o glow do ambiente faz o halo)
func _anel(cor: Color):
	var anel := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = 1.55
	toro.outer_radius = 1.75
	toro.rings = 48
	toro.ring_segments = 6
	anel.mesh = toro
	anel.scale = Vector3(1.0, 0.15, 1.0)
	anel.position.y = 0.06
	var neon := StandardMaterial3D.new()
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon.albedo_color = cor
	neon.emission_enabled = true
	neon.emission = cor
	neon.emission_energy_multiplier = 3.0
	anel.material_override = neon
	anel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(anel)

## `t` no relógio de quem mediu a pose (o Quest dono do carro)
func receber(t: float, pos: Vector3, rot: Quaternion, vel_kmh: float):
	interpolador.adicionar(t, pos, rot)
	vel = vel_kmh / 3.6

## Contador de nitros do dono (telemetria): subiu, ele acabou de ligar e o ronco toca
## aqui, no carro dele. O primeiro valor visto só marca o ponto de partida
func ver_nitro(contador: int):
	if _nitros >= 0 and contador > _nitros and visible:
		CarroFantasma.roncar(self)
	_nitros = contador

## Ronco do nitro (som_gerador.gd "nitro") preso ao carro, alto o bastante para ouvir
## de longe; some quando acaba
static func roncar(pai: Node3D, volume_db := 0.0):
	var som := SomGerador.fonte("nitro")
	if som.stream == null:
		som.free()
		return
	som.volume_db = volume_db
	som.unit_size = 12.0
	som.position = Vector3(0.0, 0.35, 1.2)
	pai.add_child(som)
	som.play()
	som.finished.connect(som.queue_free)

## Some e volta a aparecer depois (renascer, outra corrida): começa da próxima pose
func reiniciar():
	interpolador.limpar()

func _process(delta: float):
	if interpolador.vazio():
		return
	transform = interpolador.pose()
	for giro in giros:
		giro.rotation.x -= vel * delta / CarroRival.RAIO_RODA
