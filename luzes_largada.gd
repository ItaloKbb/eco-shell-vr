class_name LuzesLargada
extends Control
## Pórtico de largada do telão, como na F1: cinco colunas com duas lâmpadas cada, num
## painel escuro no alto da tela. Na contagem acendem em vermelho uma coluna por vez;
## no "VAI!" apagam todas juntas e aparece o VAI! em verde, que some sozinho.
## O espectador chama acender(n) com 0 a 5 conforme o tempo da fase de contagem.

const COLUNAS := 5
const TAMANHO := Vector2(520.0, 150.0)
const RAIO := 22.0
const VERMELHO := Color(1.0, 0.12, 0.08)
const APAGADA := Color(0.12, 0.03, 0.03)

var acesas := 0
var _vai: Label
var _anima: Tween

func _init():
	custom_minimum_size = TAMANHO
	size = TAMANHO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vai = TemaEvento.rotulo("VAI!", 96, TemaEvento.VERDE, true)
	_vai.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vai.position = Vector2(0.0, TAMANHO.y + 6.0)
	_vai.size = Vector2(TAMANHO.x, 110.0)
	_vai.visible = false
	add_child(_vai)
	visible = false

## Liga o pórtico com as lâmpadas apagadas
func mostrar():
	if visible:
		return
	acesas = 0
	_vai.visible = false
	visible = true
	modulate.a = 0.0
	_animar().tween_property(self, "modulate:a", 1.0, 0.25)
	queue_redraw()

## Quantas colunas acesas (0 a 5)
func acender(n: int):
	n = clampi(n, 0, COLUNAS)
	if n != acesas:
		acesas = n
		queue_redraw()

## Largada: apaga tudo, mostra o VAI! e some
func vai():
	if not visible or _vai.visible:
		return
	acesas = 0
	queue_redraw()
	_vai.visible = true
	_vai.scale = Vector2(0.6, 0.6)
	_vai.pivot_offset = _vai.size * 0.5
	var t := _animar()
	t.tween_property(_vai, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(1.0)
	t.tween_property(self, "modulate:a", 0.0, 0.4)
	t.tween_callback(func(): visible = false)

## Esconde na hora (abertura pulada, corte para outra corrida)
func esconder():
	if _anima and _anima.is_valid():
		_anima.kill()
	visible = false

func _animar() -> Tween:
	if _anima and _anima.is_valid():
		_anima.kill()
	_anima = create_tween()
	return _anima

func _draw():
	var fundo := TemaEvento.estilo(Color(0.02, 0.02, 0.03, 0.92), Color(0.25, 0.25, 0.3, 0.9), 2, 12, 0.0)
	draw_style_box(fundo, Rect2(Vector2.ZERO, TAMANHO))
	var passo := TAMANHO.x / COLUNAS
	for c in COLUNAS:
		var x := passo * (c + 0.5)
		# Coluna de suporte escura atrás das lâmpadas
		draw_rect(Rect2(x - RAIO - 6.0, 12.0, (RAIO + 6.0) * 2.0, TAMANHO.y - 24.0), Color(0.06, 0.06, 0.08), true)
		for linha in 2:
			var centro := Vector2(x, 44.0 + linha * 62.0)
			var acesa := c < acesas
			if acesa:
				# Halo largo e apagado em volta da lâmpada acesa
				draw_circle(centro, RAIO * 1.7, Color(VERMELHO, 0.18))
				draw_circle(centro, RAIO * 1.3, Color(VERMELHO, 0.3))
			draw_circle(centro, RAIO, VERMELHO if acesa else APAGADA)
			if acesa:
				draw_circle(centro - Vector2(RAIO * 0.3, RAIO * 0.3), RAIO * 0.3, Color(1.0, 0.75, 0.7, 0.8))
