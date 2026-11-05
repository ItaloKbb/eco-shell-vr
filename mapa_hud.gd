class_name MapaHud
extends Control
## Mapa da pista em 2D, usado no visor do capacete (CapaceteHUD) e no minimapa do telão
## (HudTransmissao). Desenha o traçado com um brilho largo e apagado por baixo de uma
## linha fina acesa, o tracinho da largada e, por cima:
## - no capacete: os adversários em pontos, os outros jogadores em anéis e o piloto numa
##   seta para onde o bico vai (vermelha na contramão);
## - no telão: um marcador por carro (`carros`), na cor da pintura, jogador real maior e
##   com anel, o carro em foco pulsando.
## Norte (-Z) sempre para cima. definir_pista enquadra o traçado inteiro mantendo a
## proporção; no_mapa converte um ponto local da pista em pixels deste controle.

var cor := Color(0.3, 0.7, 1.0)
var cor_piloto := Color(0.75, 0.97, 1.0)
var cor_contramao := Color(1.0, 0.32, 0.25)
## Espessura dos traços e tamanho dos marcadores (o telão desenha maior)
var escala_traco := 1.0
var trilha := PackedVector2Array()
var largada := PackedVector2Array()
var rivais := PackedVector2Array()
var outros := PackedVector2Array()
var jogador := Vector2.ZERO
## Para onde o bico aponta, na tela (unitário; y para baixo = sul). Sem seta: Vector2.ZERO
var rumo := Vector2.UP
var contramao := false
## Telão: [{pos: Vector2, cor: Color, real: bool, foco: bool}]
var carros: Array = []
## Fase do pulso do carro em foco (0 a 1), avançada por quem desenha
var pulso := 0.0

var _centro := Vector2.ZERO
var _escala := 1.0
var _tamanho := Vector2(200.0, 200.0)

## Enquadra o traçado inteiro em `tamanho` px, com a fração `margem` útil
func definir_pista(pista: PistaCorrida, tamanho: Vector2, margem := 0.86):
	_tamanho = tamanho
	var caixa := Rect2(Vector2(pista.pontos[0].x, pista.pontos[0].z), Vector2.ZERO)
	for p in pista.pontos:
		caixa = caixa.expand(Vector2(p.x, p.z))
	_centro = caixa.get_center()
	var util := tamanho * margem
	_escala = minf(util.x / maxf(caixa.size.x, 1.0), util.y / maxf(caixa.size.y, 1.0))
	var nova := PackedVector2Array()
	for i in range(0, PistaCorrida.AMOSTRAS, 6):
		nova.append(no_mapa(pista.pontos[i]))
	if pista.aberta:
		nova.append(no_mapa(pista.pontos[PistaCorrida.AMOSTRAS - 1]))
	else:
		nova.append(nova[0])
	trilha = nova
	# Linha de largada: um tracinho atravessado na pista
	var q := pista.quadro(pista.s_largada)
	var meio := no_mapa(q.origin)
	var lado := Vector2(q.basis.x.x, q.basis.x.z).normalized() * 7.0 * escala_traco
	largada = PackedVector2Array([meio - lado, meio + lado])
	queue_redraw()

## Ponto local da pista (x, z) em pixels do mapa (norte, -Z, para cima)
func no_mapa(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _centro) * _escala + _tamanho * 0.5

func _draw():
	if trilha.size() < 2:
		return
	var e := escala_traco
	# Pista: brilho largo e apagado, linha fina acesa por cima
	draw_polyline(trilha, Color(cor, 0.22), 8.0 * e, true)
	draw_polyline(trilha, Color(cor, 0.9), 2.0 * e, true)
	if largada.size() == 2:
		draw_line(largada[0], largada[1], cor_piloto, 3.0 * e, true)
	for p in rivais:
		draw_circle(p, 3.2 * e, Color(cor, 0.95))
	for p in outros:
		draw_arc(p, 4.5 * e, 0.0, TAU, 16, cor_piloto, 2.0 * e, true)
	# Telão: os carros comuns primeiro, os reais e o em foco por cima
	for camada in 2:
		for c: Dictionary in carros:
			var destaque: bool = c.real or c.foco
			if destaque != (camada == 1):
				continue
			var raio := (5.5 if c.real else 3.6) * e
			draw_circle(c.pos, raio + 1.2 * e, Color(0.0, 0.0, 0.0, 0.7))
			draw_circle(c.pos, raio, c.cor)
			if c.real:
				draw_arc(c.pos, raio + 3.0 * e, 0.0, TAU, 20, Color.WHITE, 1.6 * e, true)
			if c.foco:
				var onda := fposmod(pulso, 1.0)
				draw_arc(c.pos, raio + (4.0 + 10.0 * onda) * e, 0.0, TAU, 24, Color(Color.WHITE, 0.8 * (1.0 - onda)), 2.0 * e, true)
	if rumo == Vector2.ZERO:
		return
	# Piloto (capacete): seta com entalhe atrás e um anel em volta
	var tom := cor_contramao if contramao else cor_piloto
	var lado := Vector2(-rumo.y, rumo.x)
	var seta := PackedVector2Array([
		jogador + rumo * 9.0 * e,
		jogador - rumo * 6.0 * e + lado * 6.0 * e,
		jogador - rumo * 2.5 * e,
		jogador - rumo * 6.0 * e - lado * 6.0 * e,
	])
	draw_colored_polygon(seta, tom)
	draw_arc(jogador, 12.0 * e, 0.0, TAU, 24, Color(tom, 0.45), 1.5 * e, true)
