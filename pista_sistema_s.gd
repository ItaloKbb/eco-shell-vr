class_name PistaSistemaS
extends PistaAberta
## Pista do Sistema S: um S enorme e bem largo, ponta a ponta. Reta do grid, a curva de
## cima (250° em volta de um círculo), o meio do S e a curva de baixo no sentido contrário
## (mais 250°), terminando na reta de frenagem. ~1,6 km de corrida no chão plano.

const LARGURA_S := 24.0
## Raios das duas barrigas do S (m): a de baixo um pouco mais aberta
const RAIO_CIMA := 170.0
const RAIO_BAIXO := 200.0
## Onde a curva de cima começa (rad, no círculo de cima) e onde a de baixo termina
const INICIO_CIMA := deg_to_rad(20.0)
const FIM_BAIXO := deg_to_rad(-160.0)

func _init():
	super()
	largura = LARGURA_S
	letreiro = "SENAI 326 · SISTEMA S"
	# Paleta da pista: azul SENAI com neon âmbar
	paleta = {
		"asfalto": Color("283247"), "faixa": Color("1e6ad2"), "linha": Color("e8f0ff"),
		"neon": Color("ffb52e"), "muro": Color("eef2f8"),
	}

func _tracado() -> PackedVector2Array:
	var centro_cima := Vector2(0.0, RAIO_CIMA)
	var centro_baixo := Vector2(0.0, -RAIO_BAIXO)
	# Começo da curva de cima e a direção em que se anda nela (ângulo crescendo)
	var p0 := centro_cima + Vector2(cos(INICIO_CIMA), sin(INICIO_CIMA)) * RAIO_CIMA
	var t0 := Vector2(-sin(INICIO_CIMA), cos(INICIO_CIMA))
	var linha := PackedVector2Array([p0 - t0 * entrada])
	reta(linha, t0, entrada)
	# Curva de cima até o meio do S (a origem), e a de baixo no sentido contrário
	arco(linha, centro_cima, RAIO_CIMA, INICIO_CIMA, PI * 1.5)
	arco(linha, centro_baixo, RAIO_BAIXO, PI * 0.5, FIM_BAIXO)
	reta(linha, Vector2(sin(FIM_BAIXO), -cos(FIM_BAIXO)), saida)
	# Espelha em X: visto de cima com o norte (-Z) para cima, como no telão, lê como S
	for i in linha.size():
		linha[i] = Vector2(-linha[i].x, linha[i].y)
	return linha
