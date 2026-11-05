class_name MapaPainel
extends Node2D
## Mapa da telinha do painel do carro, como um GPS: o carro fica no meio, um pouco
## abaixo do centro (vê mais o que vem pela frente), e o mapa gira com ele, a frente
## sempre para cima.
##
## No mundo neon: o abismo com a beirada, as pontes, loops e rampas (planta guardada
## em EstruturasNeon.tracados), os portais de corrida na cor de cada um (os que estão
## longe ficam presos na borda, apontando para onde estão) e os outros jogadores.
## Nos mapas de corrida: a pista com as cores dela, a linha de largada (e a de
## chegada, nas pistas de ponta a ponta), os adversários na cor da lataria, os outros
## jogadores, o portal de volta quando aparece.
##
## Desenhado numa SubViewport do carro (car.gd _montar_mapa), que só é redesenhada
## quando o carro pede (redesenhar), a meia taxa de quadros.

## Raio mostrado em volta do carro (m): o lobby é aberto e os portais ficam longe; na
## pista interessa mais a próxima curva
@export var raio_lobby := 170.0
@export var raio_corrida := 110.0
## Altura do carro na tela (0 = topo, 1 = base)
@export var altura_carro := 0.62

const FUNDO := Color(0.01, 0.02, 0.05)
const AZUL := Color(0.3, 0.7, 1.0)
const ESTRUTURA := Color(0.1, 0.85, 1.0)
const ABISMO := Color(0.12, 0.0, 0.16)
const BEIRADA := Color(1.0, 0.25, 0.85)
const CARRO := Color(1.0, 1.0, 1.0)

var carro: Node3D
var tamanho := 256.0
## Frente do carro no plano (xz), mantida quando ele está de pé no ar ou capotado
var _frente := Vector2(0.0, -1.0)
## Pista em xz global, calculada uma vez por pista: [pista, PackedVector2Array]
var _pista_cache: Array = [null, PackedVector2Array()]
## Planta das estruturas com centro e raio de cada uma (para pular as que estão longe)
var _estruturas_cache: Array = [null, []]

func redesenhar():
	queue_redraw()

func _draw():
	draw_rect(Rect2(0.0, 0.0, tamanho, tamanho), FUNDO)
	if carro == null:
		return
	var mundo: Node3D = carro.get("hex_world")
	var corrida := mundo is MapaCorrida
	var raio := raio_corrida if corrida else raio_lobby
	var frente3 := -carro.global_basis.z
	var frente := Vector2(frente3.x, frente3.z)
	if frente.length() > 0.2:
		_frente = frente.normalized()
	var escala := tamanho * 0.5 / raio
	_aneis(escala)
	if corrida:
		_desenhar_corrida(mundo, escala, raio)
	elif mundo and mundo.get("estruturas") is EstruturasNeon:
		_desenhar_lobby(mundo.estruturas, escala, raio)
	_desenhar_jogadores(escala)
	_seta_carro()
	draw_rect(Rect2(1.0, 1.0, tamanho - 2.0, tamanho - 2.0), AZUL, false, 2.0)

## Mundo (x, z) -> tela, com o carro no ponto de referência e a frente para cima
func _tela(x: float, z: float, escala: float) -> Vector2:
	var rel := Vector2(x - carro.global_position.x, z - carro.global_position.z)
	var direita := Vector2(-_frente.y, _frente.x)
	return _centro() + Vector2(rel.dot(direita), -rel.dot(_frente)) * escala

func _centro() -> Vector2:
	return Vector2(tamanho * 0.5, tamanho * altura_carro)

## Anéis de distância bem apagados: dão a noção de escala sem poluir
func _aneis(escala: float):
	for metros in [50.0, 100.0]:
		draw_arc(_centro(), metros * escala, 0.0, TAU, 48, Color(AZUL, 0.12), 1.0)

func _seta_carro():
	var c := _centro()
	var seta := PackedVector2Array([c + Vector2(0.0, -9.0), c + Vector2(6.0, 7.0), c + Vector2(0.0, 3.5), c + Vector2(-6.0, 7.0)])
	draw_colored_polygon(seta, CARRO)

## Marca de um carro ou portal: bolinha cheia com contorno escuro
func _ponto(p: Vector2, cor: Color, raio_px: float):
	draw_circle(p, raio_px + 1.5, FUNDO)
	draw_circle(p, raio_px, cor)

func _dentro(p: Vector2, folga: float) -> bool:
	return p.x > -folga and p.y > -folga and p.x < tamanho + folga and p.y < tamanho + folga

# --- Lobby ----------------------------------------------------------------------

func _desenhar_lobby(estruturas: EstruturasNeon, escala: float, raio: float):
	var base := estruturas.global_transform
	# Abismo: faixa de borda a borda do mundo, com a beirada acesa
	var longe := raio * 3.0
	var cx := carro.global_position.x
	var z_sul := (base * Vector3(0.0, 0.0, EstruturasNeon.ABISMO_Z + EstruturasNeon.ABISMO_MEIA)).z
	var z_norte := (base * Vector3(0.0, 0.0, EstruturasNeon.ABISMO_Z - EstruturasNeon.ABISMO_MEIA)).z
	draw_colored_polygon(PackedVector2Array([
		_tela(cx - longe, z_sul, escala), _tela(cx + longe, z_sul, escala),
		_tela(cx + longe, z_norte, escala), _tela(cx - longe, z_norte, escala)]), ABISMO)
	for z in [z_sul, z_norte]:
		draw_line(_tela(cx - longe, z, escala), _tela(cx + longe, z, escala), BEIRADA, 2.0)
	# Pontes, loops e rampas
	if _estruturas_cache[0] != estruturas:
		_estruturas_cache = [estruturas, _planta_estruturas(estruturas)]
	var pos := Vector2(carro.global_position.x, carro.global_position.z)
	for peca in _estruturas_cache[1]:
		if pos.distance_to(peca.centro) > raio * 1.5 + peca.raio:
			continue
		var linha := PackedVector2Array()
		for p: Vector2 in peca.pontos:
			linha.append(_tela(p.x, p.y, escala))
		draw_polyline(linha, Color(ESTRUTURA, 0.35), maxf(peca.largura * escala, 3.0))
		draw_polyline(linha, ESTRUTURA, 1.5)
	# Portais de corrida: os de fora da tela ficam presos na borda, apontando para eles
	for portal in get_tree().get_nodes_in_group("portais"):
		if not portal.is_visible_in_tree():
			continue
		_portal(portal, escala)

## Planta global de cada peça, com centro e raio para o corte por distância
func _planta_estruturas(estruturas: EstruturasNeon) -> Array:
	var pecas := []
	var base := estruturas.global_transform
	for tracado in estruturas.tracados:
		var pontos := PackedVector2Array()
		var caixa := Rect2()
		for i in tracado.pontos.size():
			var p: Vector2 = tracado.pontos[i]
			var g := base * Vector3(p.x, 0.0, p.y)
			pontos.append(Vector2(g.x, g.z))
			caixa = Rect2(pontos[0], Vector2.ZERO) if i == 0 else caixa.expand(pontos[i])
		pecas.append({"pontos": pontos, "largura": tracado.largura,
			"centro": caixa.get_center(), "raio": caixa.size.length() * 0.5})
	return pecas

func _portal(portal: Portal, escala: float):
	var p := _tela(portal.global_position.x, portal.global_position.z, escala)
	var margem := 10.0
	if _dentro(p, -margem):
		draw_arc(p, 7.0, 0.0, TAU, 20, portal.cor, 2.5)
		_ponto(p, portal.cor, 3.5)
		return
	# Fora: na borda, no rumo dele, com um triângulo apontando para fora
	var c := _centro()
	var rumo := (p - c).normalized()
	var limite := Rect2(margem, margem, tamanho - margem * 2.0, tamanho - margem * 2.0)
	var t := INF
	for eixo in 2:
		if absf(rumo[eixo]) > 0.0001:
			var alvo: float = limite.end[eixo] if rumo[eixo] > 0.0 else limite.position[eixo]
			t = minf(t, (alvo - c[eixo]) / rumo[eixo])
	var borda := c + rumo * t
	var lado := Vector2(-rumo.y, rumo.x)
	draw_colored_polygon(PackedVector2Array([borda + rumo * 7.0, borda - rumo * 4.0 + lado * 6.0, borda - rumo * 4.0 - lado * 6.0]), portal.cor)

# --- Corrida --------------------------------------------------------------------

func _desenhar_corrida(mapa: MapaCorrida, escala: float, raio: float):
	var pista := mapa.pista
	if pista == null:
		return
	if _pista_cache[0] != pista:
		var pontos := PackedVector2Array()
		for p in pista.pontos:
			var g := pista.global_transform * p
			pontos.append(Vector2(g.x, g.z))
		if not pista.aberta and pontos.size() > 1:
			pontos.append(pontos[0])
		_pista_cache = [pista, pontos]
	var linha := PackedVector2Array()
	for p: Vector2 in _pista_cache[1]:
		linha.append(_tela(p.x, p.y, escala))
	var neon: Color = pista.paleta.get("neon", ESTRUTURA)
	var asfalto: Color = pista.paleta.get("asfalto", Color(0.25, 0.22, 0.28))
	var largura := maxf(pista.largura * escala, 4.0)
	draw_polyline(linha, neon, largura + 3.0)
	draw_polyline(linha, asfalto.lightened(0.25), largura)
	_linha_pista(pista, pista.s_largada, escala, pista.paleta.get("linha", Color.WHITE))
	if pista.aberta:
		_linha_pista(pista, pista.s_chegada, escala, Color.WHITE)
	if mapa.portal_volta and mapa.portal_volta.is_visible_in_tree():
		_portal(mapa.portal_volta, escala)
	var pos := carro.global_position
	for rival in mapa.rivais:
		if not is_instance_valid(rival) or not rival.is_visible_in_tree() or rival.global_position.distance_to(pos) > raio * 1.6:
			continue
		var pintura: Array = CarroRival.PINTURAS[(rival.numero - 1) % CarroRival.PINTURAS.size()]
		_ponto(_tela(rival.global_position.x, rival.global_position.z, escala), pintura[0], 3.5)

## Linha atravessada na pista em `s` (largada, chegada)
func _linha_pista(pista: PistaCorrida, s: float, escala: float, cor: Color):
	var quadro := pista.global_transform * pista.quadro(s)
	var meia := quadro.basis.x.normalized() * pista.largura * 0.5
	var a := quadro.origin - meia
	var b := quadro.origin + meia
	draw_line(_tela(a.x, a.z, escala), _tela(b.x, b.z, escala), cor, 3.0)

# --- Jogadores ------------------------------------------------------------------

## Os outros jogadores da sala (CarroFantasma de jogador: no lobby e na corrida)
func _desenhar_jogadores(escala: float):
	for outro in get_tree().get_nodes_in_group("jogador_mapa"):
		if not outro.is_visible_in_tree():
			continue
		var p := _tela(outro.global_position.x, outro.global_position.z, escala)
		if _dentro(p, 0.0):
			draw_arc(p, 6.0, 0.0, TAU, 16, Color.WHITE, 1.5)
			_ponto(p, outro.cor_mapa, 4.0)
