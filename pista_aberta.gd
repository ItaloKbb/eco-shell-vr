class_name PistaAberta
extends PistaCorrida
## Pista ponta a ponta (Sistema S, Parque Industrial): largada numa ponta, chegada na
## outra, uma "volta" só. Cada pista desenha o traçado no plano em _tracado() (uma
## polilinha densa, começando pela reta do grid e terminando na área de frenagem), que é
## reamostrado por comprimento em AMOSTRAS amostras. Muro dos dois lados em toda a
## pista (ninguém corta caminho e perde os portões) e mureta atravessada nas pontas.

## Reta do grid antes da linha de largada (m): cabem as 11 vagas
var entrada := 80.0
## Área de frenagem depois da chegada, até o fim da pista (m): os adversários
## estacionam nela e o portal de volta fica no fim
var saida := 140.0

func _init():
	aberta = true
	voltas = 1
	muro_dos_dois_lados = true

## Centro da pista no plano (x, z), do começo do grid até o fim, com pontos a cada ~2 m
func _tracado() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(0.0, -entrada - saida - 100.0)])

## O traçado reamostrado por comprimento de arco, com a altura do terreno embaixo
func _amostras_brutas() -> PackedVector3Array:
	var linha := _tracado()
	var acumulado := PackedFloat32Array([0.0])
	for i in range(1, linha.size()):
		acumulado.append(acumulado[i - 1] + linha[i].distance_to(linha[i - 1]))
	var total := acumulado[acumulado.size() - 1]
	var brutos := PackedVector3Array()
	var k := 0
	for i in AMOSTRAS:
		var alvo := total * i / (AMOSTRAS - 1)
		while k < linha.size() - 2 and acumulado[k + 1] < alvo:
			k += 1
		var f := clampf((alvo - acumulado[k]) / maxf(acumulado[k + 1] - acumulado[k], 0.0001), 0.0, 1.0)
		var p := linha[k].lerp(linha[k + 1], f)
		brutos.append(Vector3(p.x, _chao(p.x, p.y), p.y))
	return brutos

func _calcular():
	super()
	s_largada = entrada
	s_chegada = comprimento - saida

## Nenhum trecho passa por cima de outro
func _sob_viaduto(_p: Vector3) -> bool:
	return false

# --- Desenho do traçado -----------------------------------------------------------

## Reta de `metros` a partir do último ponto da linha, na direção dada
static func reta(linha: PackedVector2Array, direcao: Vector2, metros: float):
	var inicio := linha[linha.size() - 1]
	var passos := maxi(ceili(metros / 2.0), 1)
	for i in range(1, passos + 1):
		linha.append(inicio + direcao.normalized() * metros * i / passos)

## Arco de circunferência de `de` a `ate` (rad, no sentido que for) em volta de `centro`
static func arco(linha: PackedVector2Array, centro: Vector2, raio: float, de: float, ate: float):
	var passos := maxi(ceili(absf(ate - de) * raio / 2.0), 1)
	for i in range(1, passos + 1):
		var a := lerpf(de, ate, float(i) / passos)
		linha.append(centro + Vector2(cos(a), sin(a)) * raio)
