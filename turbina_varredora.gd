class_name TurbinaVarredora
extends ObstaculoPista
## Turbina eólica de eixo vertical plantada na beira da pista: a coluna fica fora do
## muro e, embaixo, três braços laranja longos varrem dois terços da pista girando na
## altura do carro. Do lado oposto sobra uma faixa estreita sempre livre; quem quer a
## linha boa precisa passar entre um braço e outro.

const BRACOS := 3
## Do eixo até a ponta do braço e meia espessura do braço (m)
const COMPRIMENTO := 10.0
const MEIA_ESPESSURA := 0.3
const RAIO_COLUNA := 0.9
const ALTURA := 18.0
## Eixo fora da pista, depois da borda (m a partir do centro)
const EIXO := PistaCorrida.LARGURA * 0.5 + 1.3
## Altura do meio dos braços: pega o casco do carro, passa por cima do muro
const ALTURA_BRACO := 1.0

## De que lado fica a coluna (+1 direita, -1 esquerda)
var lado := 1.0
## Velocidade de giro (rad/s, positiva = anti-horário visto de cima)
var giro := 0.8
var fase := 0.0
var _rotor: Node3D
var _topo: Node3D

func _init():
	alcance_s = COMPRIMENTO + MEIO_CARRO
	aviso = "TURBINA À FRENTE"

func _ready():
	var branco := material_metal(Color(0.9, 0.92, 0.95), 0.3, 0.35)
	var laranja := material_metal(COR_PERIGO, 0.2, 0.5)
	var luz := material_luz(Color(1.0, 0.35, 0.1), 4.0)
	var eixo := Vector3(lado * EIXO, 0.0, 0.0)
	cilindro(RAIO_COLUNA, ALTURA, branco, eixo + Vector3.UP * (ALTURA * 0.5 - 1.0))
	# Pás helicoidais em cima (só cenário) e braços varredores embaixo (o obstáculo)
	_topo = Node3D.new()
	_topo.position = eixo
	add_child(_topo)
	for k in BRACOS:
		var a := TAU * k / BRACOS
		var pa := caixa(Vector3(0.25, 10.0, 1.3), branco, Vector3.ZERO, _topo)
		pa.transform = Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35), Vector3(cos(a) * 2.8, 12.0, -sin(a) * 2.8))
		var haste := caixa(Vector3(2.8, 0.2, 0.2), branco, Vector3.ZERO, _topo)
		haste.transform = Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 1.4, 17.2, -sin(a) * 1.4))
	_rotor = Node3D.new()
	_rotor.position = eixo
	add_child(_rotor)
	cilindro(1.15, 1.4, laranja, Vector3.UP * ALTURA_BRACO, _rotor)
	var comprimento_braco := COMPRIMENTO - RAIO_COLUNA
	for k in BRACOS:
		var braco := Node3D.new()
		braco.rotation.y = -TAU * k / BRACOS
		_rotor.add_child(braco)
		caixa(Vector3(comprimento_braco, 0.55, MEIA_ESPESSURA * 2.0), laranja, Vector3(RAIO_COLUNA + comprimento_braco * 0.5, ALTURA_BRACO, 0.0), braco)
		caixa(Vector3(0.3, 0.6, MEIA_ESPESSURA * 2.0 + 0.04), luz, Vector3(COMPRIMENTO - 0.15, ALTURA_BRACO, 0.0), braco)
	animar(0.0)

func _angulo(t: float) -> float:
	return giro * t + fase

## Braço k aponta para (cos θ, sin θ) no plano (x = d, z = -ds) a partir do eixo
func bloqueia(ds: float, d: float, t: float) -> bool:
	var raio := MEIA_LARGURA_CARRO + 0.15
	var theta := _angulo(t)
	# O carro é comprido: confere a frente, o meio e a traseira
	for desloca: float in [-0.85, 0.0, 0.85]:
		var p := Vector2(d - lado * EIXO, -(ds + desloca))
		if p.length() > COMPRIMENTO + raio:
			continue
		for k in BRACOS:
			var a := theta + TAU * k / BRACOS
			var u := Vector2(cos(a), sin(a))
			var ao_longo := p.dot(u)
			if ao_longo < 0.0:
				continue
			if absf(p.dot(Vector2(-u.y, u.x))) < MEIA_ESPESSURA + raio:
				return true
	return false

## Joga para o lado livre, longe da coluna
func lado_empurrao(_ds: float, _d: float, _t: float) -> float:
	return -lado

func animar(t: float):
	if _rotor == null:
		return
	_rotor.rotation.y = -_angulo(t)
	_topo.rotation.y = -_angulo(t) * 0.5
