class_name PistaVulcao
extends PistaAberta
## Pista do I de Incrível: um "i" comprido cortando o campo de lava. A haste é uma reta
## de ~2 km que serpenteia de leve (duas ondas sobrepostas, nada que exija frear), com
## campos de minas terrestres (CampoMinado, postos pelo mapa) e o pingo no fim: a praça
## de basalto com o portal de volta. Muro dos dois lados o tempo todo: a lava fica do
## lado de fora, um pouco abaixo do asfalto.

const LARGURA_V := 20.0
## Metros de corrida (da largada à chegada)
const CORRIDA := 2000.0
## Ondulação: duas ondas de amplitude e comprimento diferentes (m)
const ONDA := 14.0
const COMPRIMENTO_ONDA := 760.0
const ONDA_CURTA := 5.0
const COMPRIMENTO_CURTA := 290.0
## Retas sem ondulação depois da largada e antes da chegada (m)
const RETA_PONTAS := 180.0
const RAIO_PINGO := 34.0

func _init():
	super()
	largura = LARGURA_V
	letreiro = "SENAI 326 · I DE INCRÍVEL"
	# Paleta da pista: basalto com neon de lava
	paleta = {
		"asfalto": Color("221d20"), "faixa": Color("b8321e"), "linha": Color("ffd2a8"),
		"neon": Color("ff6a1a"), "muro": Color("5a4a48"),
	}
	raio_pingo = RAIO_PINGO
	cor_piso_pingo = Color(0.1, 0.09, 0.09)
	cor_anel_pingo = Color(1.0, 0.25, 0.05)
	# A lava fica abaixo do asfalto: a saia fecha a borda até lá
	saia = 0.7

## Haste do i ao longo de X (a corrida vai para +X), centrada na origem
func _tracado() -> PackedVector2Array:
	var total := entrada + CORRIDA + saida
	var linha := PackedVector2Array()
	var x := 0.0
	while x <= total:
		var corrida := x - entrada
		var suave := smoothstep(0.0, RETA_PONTAS, corrida) * (1.0 - smoothstep(CORRIDA - RETA_PONTAS, CORRIDA, corrida))
		var z := ONDA * sin(TAU * corrida / COMPRIMENTO_ONDA) + ONDA_CURTA * sin(TAU * corrida / COMPRIMENTO_CURTA + 1.0)
		linha.append(Vector2(x - total * 0.5, z * suave))
		x += 2.0
	return linha
