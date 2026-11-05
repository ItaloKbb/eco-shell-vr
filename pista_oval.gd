class_name PistaOval
extends PistaCorrida
## Circuito do Deserto: oval de autódromo, plano. Duas retas longas e duas curvas
## de 180° bem abertas, sem viaduto e quase sem inclinação. O infinito antigo era curva o
## tempo todo, com curvas deitadas e o sobe-e-desce do viaduto, e enjoava em VR.
## As retas correm ao longo de X; a largada fica na reta de baixo (+Z), com o grid
## inteiro na reta. ~1,26 km de volta.

## Comprimento de cada reta e raio das curvas (m)
const RETA := 330.0
const RAIO := 95.0
## Meia extensão do oval no plano (centro da pista): o mapa usa para o cenário
const MEIA_X := RETA * 0.5 + RAIO
const MEIA_Z := RAIO
## Inclinação máxima nas curvas (~4,5°): o bastante para o muro de fora, sem girar o horizonte
const INCLINACAO_OVAL := 0.08
## Onde fica a linha de largada, em fração da primeira reta: o grid (atrás dela) cabe na reta
const LINHA_NA_RETA := 0.6

func _init():
	inclinacao_max = INCLINACAO_OVAL

## t de 0 a 2π dá uma volta com passo uniforme no comprimento (as amostras ficam
## igualmente espaçadas). t = 0 é a linha de largada
func _centro(t: float) -> Vector3:
	var total := 2.0 * RETA + TAU * RAIO
	var u := fposmod(t / TAU * total + RETA * LINHA_NA_RETA, total)
	var p: Vector2
	if u < RETA:
		# Reta de baixo, para +X
		p = Vector2(-RETA * 0.5 + u, RAIO)
	elif u < RETA + PI * RAIO:
		# Curva da direita, de +Z para -Z
		var a := PI * 0.5 - (u - RETA) / RAIO
		p = Vector2(RETA * 0.5 + RAIO * cos(a), RAIO * sin(a))
	elif u < 2.0 * RETA + PI * RAIO:
		# Reta de cima, para -X
		p = Vector2(RETA * 0.5 - (u - RETA - PI * RAIO), -RAIO)
	else:
		# Curva da esquerda, de -Z de volta para +Z
		var a := -PI * 0.5 - (u - 2.0 * RETA - PI * RAIO) / RAIO
		p = Vector2(-RETA * 0.5 + RAIO * cos(a), RAIO * sin(a))
	return Vector3(p.x, 0.0, p.y)

func _t_largada() -> float:
	return 0.0

## Plano, sem viaduto: nada passa por baixo
func _sob_viaduto(_p: Vector3) -> bool:
	return false
