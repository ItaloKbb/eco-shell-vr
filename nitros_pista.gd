class_name NitrosPista
extends Node3D
## Turbos de nitro flutuando na pista, estilo Need for Speed: quatro por pista, cada um
## uma cápsula azul acesa girando e balançando acima do asfalto, com um anel no chão.
## O carro do jogador passa por dentro e pega (car.coletar_nitro); o turbo some e volta
## depois de RECARGA s. Os adversários não usam nitro.
## Filho da pista: tudo em coordenadas locais dela.

## Onde ficam ao longo da corrida (fração) e em que faixa (fração da meia largura útil).
## Entre os obstáculos, rampas e campos minados das pistas
const FRACOES := [0.2, 0.38, 0.62, 0.8]
const FAIXAS := [-0.45, 0.45, 0.0, -0.45]
## Altura do centro da cápsula acima da pista (m) e quanto ela sobe e desce
const ALTURA := 1.0
const BALANCO := 0.15
const RECARGA := 8.0
const COR := Color(0.2, 0.6, 1.0)

var pista: PistaCorrida
var turbos: Array[Node3D] = []
var _tempo := 0.0

func _init(pista_: PistaCorrida):
	pista = pista_
	name = "Nitros"

func _ready():
	var casco := StandardMaterial3D.new()
	casco.albedo_color = Color(0.05, 0.12, 0.3)
	casco.metallic = 0.8
	casco.roughness = 0.25
	casco.emission_enabled = true
	casco.emission = COR
	casco.emission_energy_multiplier = 2.5
	var luz := StandardMaterial3D.new()
	luz.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	luz.albedo_color = Color(0.7, 0.9, 1.0)
	luz.emission_enabled = true
	luz.emission = Color(0.7, 0.9, 1.0)
	luz.emission_energy_multiplier = 4.0
	var capsula := CapsuleMesh.new()
	capsula.radius = 0.28
	capsula.height = 1.0
	capsula.radial_segments = 16
	capsula.rings = 4
	capsula.material = casco
	var faixa := CylinderMesh.new()
	faixa.top_radius = 0.3
	faixa.bottom_radius = 0.3
	faixa.height = 0.08
	faixa.radial_segments = 16
	faixa.rings = 1
	faixa.material = luz
	var anel := TorusMesh.new()
	anel.inner_radius = 1.0
	anel.outer_radius = 1.15
	anel.rings = 32
	anel.ring_segments = 4
	anel.material = luz
	for k in FRACOES.size():
		var s := _s(FRACOES[k])
		var q := pista.quadro(s)
		q.origin += q.basis.x * pista.meia_util * float(FAIXAS[k])
		var turbo := Node3D.new()
		turbo.name = "Turbo%d" % k
		turbo.transform = q
		add_child(turbo)
		var corpo := Node3D.new()
		corpo.name = "Corpo"
		corpo.position.y = ALTURA
		# Deitada, atravessada na pista: dá para ver de longe
		corpo.rotation.z = PI * 0.5
		turbo.add_child(corpo)
		for m in [[capsula, 0.0], [faixa, -0.25], [faixa, 0.25]]:
			var peca := MeshInstance3D.new()
			peca.mesh = m[0]
			peca.position.y = m[1]
			peca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			corpo.add_child(peca)
		var chao := MeshInstance3D.new()
		chao.mesh = anel
		chao.scale = Vector3(1.0, 0.1, 1.0)
		chao.position.y = 0.05
		chao.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		turbo.add_child(chao)
		# Detecta o carro do jogador (camada 3, como os portões e as rampas)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 4
		area.monitorable = false
		var forma := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(3.0, 2.6, 2.4)
		forma.shape = caixa
		forma.position.y = 1.3
		area.add_child(forma)
		turbo.add_child(area)
		area.body_entered.connect(_pegou.bind(turbo))
		turbos.append(turbo)

## s da fração da corrida: na pista aberta, entre a largada e a chegada; no laço, da
## linha de largada (s = 0) em diante
func _s(fracao: float) -> float:
	if pista.aberta:
		return pista.s_largada + pista.distancia_corrida() * fracao
	return pista.comprimento * fracao

func _process(delta: float):
	_tempo += delta
	for k in turbos.size():
		var corpo: Node3D = turbos[k].get_node("Corpo")
		corpo.position.y = ALTURA + sin(_tempo * 2.2 + k) * BALANCO
		corpo.rotation.y = _tempo * 1.8

func _pegou(corpo: Node3D, turbo: Node3D):
	if not turbo.visible or not corpo.has_method("coletar_nitro") or not corpo.coletar_nitro():
		return
	pegar(turbo)

## Some até a recarga (também usado pelos testes)
func pegar(turbo: Node3D):
	turbo.visible = false
	get_tree().create_timer(RECARGA, false).timeout.connect(func():
		if is_instance_valid(turbo):
			turbo.visible = true)
