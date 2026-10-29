class_name PistaIndustrial
extends PistaAberta
## Pista do Parque Industrial: o "i". A haste é uma reta de ~1,8 km (com curvas de raio
## enorme só para não ficar monótona) e quatro rampas de salto com turbo no pouso
## (RampasPista), alternando esquerda, centro e direita. O pingo é uma praça redonda
## depois da área de frenagem, aberta para a pista, com o portal de volta no meio.

const LARGURA_I := 18.0
## Metros de corrida (da largada à chegada)
const CORRIDA := 1800.0
## Ondulação suave da reta: amplitude e comprimento de onda (m)
const ONDA := 22.0
const COMPRIMENTO_ONDA := 950.0
## Retas sem ondulação depois da largada e antes da chegada (m)
const RETA_PONTAS := 200.0
## [fração da corrida, faixa em fração da meia largura útil] de cada rampa
const RAMPAS := [[0.25, -0.55], [0.45, 0.0], [0.65, 0.55], [0.85, 0.0]]
const LARGURA_RAMPA := 8.0
## Praça do pingo (m)
const RAIO_PINGO := 32.0

func _init():
	super()
	largura = LARGURA_I
	letreiro = "SENAI 326 · PARQUE INDUSTRIAL"
	raio_pingo = RAIO_PINGO

func _ready():
	super()
	var lista: Array[Dictionary] = []
	for r in RAMPAS:
		lista.append({"s": s_largada + CORRIDA * float(r[0]), "d": meia_util * float(r[1]), "largura": LARGURA_RAMPA})
	rampas = RampasPista.new(self, lista)
	add_child(rampas)

## Haste do i ao longo de X, centrada na origem
func _tracado() -> PackedVector2Array:
	var total := entrada + CORRIDA + saida
	var linha := PackedVector2Array()
	var x := 0.0
	while x <= total:
		var corrida := x - entrada
		var suave := smoothstep(0.0, RETA_PONTAS, corrida) * (1.0 - smoothstep(CORRIDA - RETA_PONTAS, CORRIDA, corrida))
		linha.append(Vector2(x - total * 0.5, ONDA * sin(TAU * corrida / COMPRIMENTO_ONDA) * suave))
		x += 2.0
	return linha
