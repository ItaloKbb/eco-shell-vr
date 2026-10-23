class_name PenduloCarga
extends ObstaculoPista
## Pórtico de montagem das turbinas: a nacele de uma turbina pendurada num cabo
## balança de uma borda à outra da pista, como um pêndulo de verdade (mais rápida no
## meio, quase parada nas pontas). Passa quem atravessa pelo lado de onde ela acabou
## de sair.

## Altura do pivô acima da pista e comprimento do cabo (m)
const PIVO := 17.0
const CABO := 16.0
## Tamanho da carga: largura (d), altura e comprimento (ds)
const CARGA := Vector3(2.4, 1.6, 2.6)
## Ângulo máximo do balanço: leva a carga até ~5 m do centro
const AMPLITUDE := 0.33
## Teto do carro: a carga só acerta se passar abaixo disso (m)
const TETO := 1.25

var fase := 0.0
var _braco: Node3D

func _init():
	alcance_s = CARGA.z * 0.5 + MEIO_CARRO
	aviso = "CARGA SUSPENSA"

func _ready():
	var aco := material_metal(Color(0.95, 0.75, 0.1), 0.5, 0.45)
	var cinza := material_metal(Color(0.85, 0.87, 0.9), 0.3, 0.35)
	var cabo := material_metal(Color(0.1, 0.1, 0.12), 0.8, 0.3)
	var faixa := material_metal(COR_PERIGO, 0.1, 0.6)
	var meia := PistaCorrida.LARGURA * 0.5 + 1.5
	for lado: float in [-1.0, 1.0]:
		caixa(Vector3(0.9, PIVO + 1.5, 0.9), aco, Vector3(lado * meia, (PIVO + 1.5) * 0.5 - 1.0, 0.0))
	caixa(Vector3(meia * 2.0 + 0.9, 1.0, 1.2), aco, Vector3(0.0, PIVO + 0.5, 0.0))
	_braco = Node3D.new()
	_braco.position = Vector3.UP * PIVO
	add_child(_braco)
	caixa(Vector3(0.12, CABO - CARGA.y * 0.5, 0.12), cabo, Vector3(0.0, -(CABO - CARGA.y * 0.5) * 0.5, 0.0), _braco)
	# Nacele: corpo, cubo do rotor na frente e faixa de perigo
	var corpo := caixa(CARGA, cinza, Vector3(0.0, -CABO, 0.0), _braco)
	caixa(Vector3(CARGA.x + 0.04, 0.3, CARGA.z + 0.04), faixa, Vector3(0.0, -CARGA.y * 0.5 + 0.15, 0.0), corpo)
	var cubo := cilindro(0.9, 0.8, cinza, Vector3(0.0, 0.0, -CARGA.z * 0.5 - 0.4), corpo)
	cubo.rotation.x = PI * 0.5
	var marca := Label3D.new()
	marca.text = "SENAI"
	marca.font_size = 72
	marca.pixel_size = 0.01
	marca.outline_size = 10
	marca.modulate = Color(0.1, 0.35, 0.85)
	marca.position = Vector3(0.0, 0.2, CARGA.z * 0.5 + 0.02)
	corpo.add_child(marca)
	animar(0.0)

func _angulo(t: float) -> float:
	return AMPLITUDE * sin(sqrt(9.8 / CABO) * t + fase)

## Centro da carga em (d, altura do fundo) no instante t
func carga(t: float) -> Vector2:
	var a := _angulo(t)
	return Vector2(CABO * sin(a), PIVO - CABO * cos(a) - CARGA.y * 0.5)

func bloqueia(ds: float, d: float, t: float) -> bool:
	if absf(ds) > alcance_s:
		return false
	var c := carga(t)
	return c.y < TETO and absf(d - c.x) < CARGA.x * 0.5 + MEIA_LARGURA_CARRO

## Joga para longe da carga
func lado_empurrao(_ds: float, d: float, t: float) -> float:
	var x := carga(t).x
	return signf(d - x) if absf(d - x) > 0.05 else -signf(x)

func animar(t: float):
	if _braco:
		_braco.rotation.z = _angulo(t)
