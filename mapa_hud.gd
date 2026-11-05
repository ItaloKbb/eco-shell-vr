class_name MapaHud
extends Control
## Desenho do mapa holográfico do visor (CapaceteHUD): traçado da pista com um brilho
## largo e apagado por baixo de uma linha fina acesa, o tracinho da largada, os
## adversários em pontos, os outros jogadores do grupo em anéis e o piloto numa seta
## apontando para onde o bico vai. Na contramão a seta e o anel em volta dela ficam
## vermelhos. Tudo em pixels da tela do mapa (CapaceteHUD._no_mapa); o fundo é
## transparente e o visor é aditivo, então o preto some e só a luz aparece.

var cor := Color(0.3, 0.7, 1.0)
var cor_piloto := Color(0.75, 0.97, 1.0)
var cor_contramao := Color(1.0, 0.32, 0.25)
var trilha := PackedVector2Array()
var largada := PackedVector2Array()
var rivais := PackedVector2Array()
var outros := PackedVector2Array()
var jogador := Vector2.ZERO
## Para onde o bico aponta, na tela (unitário; y para baixo = sul)
var rumo := Vector2.UP
var contramao := false

func _draw():
	if trilha.size() < 2:
		return
	# Pista: brilho largo e apagado, linha fina acesa por cima
	draw_polyline(trilha, Color(cor, 0.22), 8.0, true)
	draw_polyline(trilha, Color(cor, 0.9), 2.0, true)
	if largada.size() == 2:
		draw_line(largada[0], largada[1], cor_piloto, 3.0, true)
	for p in rivais:
		draw_circle(p, 3.2, Color(cor, 0.95))
	for p in outros:
		draw_arc(p, 4.5, 0.0, TAU, 16, cor_piloto, 2.0, true)
	# Piloto: seta (bico, duas pontas de trás e o entalhe no meio) com um anel em volta
	var tom := cor_contramao if contramao else cor_piloto
	var lado := Vector2(-rumo.y, rumo.x)
	var seta := PackedVector2Array([
		jogador + rumo * 9.0,
		jogador - rumo * 6.0 + lado * 6.0,
		jogador - rumo * 2.5,
		jogador - rumo * 6.0 - lado * 6.0,
	])
	draw_colored_polygon(seta, tom)
	draw_arc(jogador, 12.0, 0.0, TAU, 24, Color(tom, 0.45), 1.5, true)
