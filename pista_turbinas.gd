class_name PistaTurbinas
extends PistaCorrida
## Circuito do Vale das Turbinas: um laço fechado de ~720 m com curvas para os dois
## lados (um círculo deformado por duas ondas) que sobe e desce acompanhando o relevo
## do vale. Corre num aterro de concreto um pouco acima do terreno, então a pista
## nunca afunda no morro. Os obstáculos móveis ficam em ObstaculosPista.

## Raio médio do laço e as duas ondas que o deformam (m)
const RAIO := 112.0
const ONDA_2 := 22.0
const ONDA_3 := 13.0
## Quanto o terreno fica abaixo da pista em volta dela (o aterro)
const ATERRO := 1.4

func _init():
	letreiro = "SENAI 326 · VALE DAS TURBINAS"
	# Paleta da pista: pôr do sol: laranja com neon rosa
	paleta = {
		"asfalto": Color("3a3346"), "faixa": Color("f28a2e"), "linha": Color("ffe2b8"),
		"neon": Color("ff5fa2"), "muro": Color("f4e4d2"),
	}
	saia = ATERRO + 0.4

## Relevo do vale (local): morros largos e suaves, o bastante para a pista subir e
## descer sem degraus
static func relevo(x: float, z: float) -> float:
	return 6.0 * sin(x * 0.011 + 0.7) * cos(z * 0.009 - 0.4) + 3.0 * sin((x + z) * 0.016 + 1.9)

static func raio(t: float) -> float:
	return RAIO + ONDA_2 * cos(2.0 * t) + ONDA_3 * sin(3.0 * t + 0.6)

func _centro(t: float) -> Vector3:
	var r := raio(t)
	var x := r * cos(t)
	var z := r * sin(t)
	return Vector3(x, relevo(x, z), z)

func _chao(x: float, z: float) -> float:
	return relevo(x, z)

## Não há viaduto: nenhum ponto do laço passa por cima de outro
func _sob_viaduto(_p: Vector3) -> bool:
	return false

## Largada no trecho mais reto do laço (menor curvatura média em ~±50 m)
func _t_largada() -> float:
	var n := 360
	var curva := PackedFloat32Array()
	curva.resize(n)
	for i in n:
		var a := _plano(TAU * (i - 1) / n)
		var b := _plano(TAU * i / n)
		var c := _plano(TAU * (i + 1) / n)
		var f1 := b - a
		var f2 := c - b
		curva[i] = absf(f1.angle_to(f2)) / maxf(f1.length(), 0.001)
	var melhor := 0
	var menor := INF
	for i in n:
		var soma := 0.0
		for j in range(-25, 26):
			soma += curva[(i + j + n) % n]
		if soma < menor:
			menor = soma
			melhor = i
	# A linha fica um pouco depois do começo do trecho reto: o grid inteiro fica nele
	return TAU * (melhor + 12) / n

func _plano(t: float) -> Vector2:
	var r := raio(t)
	return Vector2(r * cos(t), r * sin(t))
