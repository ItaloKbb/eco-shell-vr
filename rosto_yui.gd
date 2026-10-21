class_name RostoYui
extends Control
## Rosto holográfico da Yui, desenhado em código (o projeto não tem imagens): moldura
## circular, cabelo verde-água com duas mechas longas presas no alto (estilo idol
## virtual), franja, olhos grandes que piscam e a boca que abre com a voz.

const CIANO := Color(0.35, 0.95, 0.9)
const CABELO := Color(0.12, 0.72, 0.7)
const CABELO_ESCURO := Color(0.05, 0.42, 0.45)
const PELE := Color(0.86, 0.97, 1.0)
const OLHO := Color(0.1, 0.55, 0.62)
const BOCA := Color(0.95, 0.4, 0.55)

## 0 = fechada, 1 = toda aberta (suavizado)
var boca := 0.0
var _proxima_piscada := 2.5
var _fim_piscada := -1.0

## Chamado a cada quadro pela assistente com o volume atual da voz (0 a 1)
func atualizar(nivel: float):
	var agora := Time.get_ticks_msec() / 1000.0
	boca = move_toward(boca, nivel, 0.25)
	if agora >= _proxima_piscada:
		_fim_piscada = agora + 0.12
		_proxima_piscada = agora + randf_range(2.5, 5.0)
	queue_redraw()

func piscando() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _fim_piscada

## Abertura da boca em degraus (o painel na VR só redesenha quando algo muda)
func passo_boca() -> int:
	return clampi(roundi(boca * 3.0), 0, 3)

func _draw():
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# Moldura: disco escuro com anel ciano
	draw_circle(c, r - 2.0, Color(0.02, 0.08, 0.12, 0.95))
	draw_arc(c, r - 3.0, 0.0, TAU, 64, CIANO, 3.0, true)
	var u := r / 70.0
	# Mechas longas (atrás da cabeça), presas no alto dos dois lados
	for lado in [-1.0, 1.0]:
		var base := c + Vector2(lado * 30.0, -22.0) * u
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-lado * 4.0, -6.0) * u, base + Vector2(lado * 14.0, -4.0) * u,
			base + Vector2(lado * 24.0, 30.0) * u, base + Vector2(lado * 20.0, 62.0) * u,
			base + Vector2(lado * 8.0, 66.0) * u, base + Vector2(lado * 10.0, 30.0) * u]), CABELO)
		# Prendedor
		draw_rect(Rect2(base + Vector2(lado * 6.0 - 4.0, -9.0) * u, Vector2(8.0, 7.0) * u), Color(0.95, 0.35, 0.6))
	# Cabelo atrás do rosto e o rosto
	draw_circle(c + Vector2(0.0, -4.0) * u, 34.0 * u, CABELO_ESCURO)
	_elipse(c + Vector2(0.0, 4.0) * u, Vector2(26.0, 30.0) * u, PELE)
	# Franja: três pontas sobre a testa
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-30.0, -6.0) * u, c + Vector2(-28.0, -28.0) * u, c + Vector2(0.0, -40.0) * u,
		c + Vector2(28.0, -28.0) * u, c + Vector2(30.0, -6.0) * u, c + Vector2(20.0, -12.0) * u,
		c + Vector2(12.0, -4.0) * u, c + Vector2(4.0, -14.0) * u, c + Vector2(-6.0, -4.0) * u,
		c + Vector2(-14.0, -14.0) * u, c + Vector2(-22.0, -4.0) * u]), CABELO)
	# Olhos: grandes, com brilho; piscando viram um traço
	for lado in [-1.0, 1.0]:
		var o := c + Vector2(lado * 11.0, 6.0) * u
		if piscando():
			draw_line(o + Vector2(-6.0, 0.0) * u, o + Vector2(6.0, 0.0) * u, OLHO, 2.5 * u, true)
		else:
			_elipse(o, Vector2(6.0, 8.0) * u, OLHO)
			draw_circle(o + Vector2(-2.0, -3.0) * u, 2.2 * u, Color.WHITE)
	# Boca: sorriso fechado, ou abrindo com a voz
	var m := c + Vector2(0.0, 22.0) * u
	if boca < 0.08:
		draw_arc(m + Vector2(0.0, -3.0) * u, 5.0 * u, deg_to_rad(30.0), deg_to_rad(150.0), 12, BOCA, 2.0 * u, true)
	else:
		_elipse(m, Vector2(4.0 + 2.0 * boca, 1.5 + 5.0 * boca) * u, BOCA)
	# Bochechas
	for lado in [-1.0, 1.0]:
		_elipse(c + Vector2(lado * 17.0, 16.0) * u, Vector2(4.0, 2.0) * u, Color(1.0, 0.55, 0.65, 0.5))

func _elipse(centro: Vector2, raios: Vector2, cor: Color):
	var pontos := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pontos.append(centro + Vector2(cos(a) * raios.x, sin(a) * raios.y))
	draw_colored_polygon(pontos, cor)
