class_name MapaCorrida
extends Node3D
## Base dos mapas de corrida que os portais abrem (Deserto, ValeTurbinas): o circuito
## com os adversários, o tráfego, a corrida e o portal de volta. Cada mapa diz qual
## pista usar (_nova_pista), onde fica o portal de volta, o céu (ambiente) e o cenário
## (_etapas, montado aos poucos atrás da tela de loading).
## altura(x, z) responde a altura do chão, como o hex_world (o carro usa no visor).

## Vagas do grid: os adversários nas primeiras, o jogador na última
const ADVERSARIOS := 10

var pista: PistaCorrida
var corrida: Corrida
var portal_volta: Portal
var rivais: Array[CarroRival] = []
var trafego: TrafegoCorrida
var ambiente := Environment.new()
var construcao_progressiva := false
## Nome mostrado no loading e no portal ("Deserto", "Vale das Turbinas")
var nome := ""
## Música da largada (musica.gd); vazio usa a faixa padrão de corrida
var faixa_corrida := ""
## Fala da Yui ao chegar, antes do encorajamento (id em voz/yui/falas.json)
var fala_chegada := ""
signal etapa_carregamento(texto: String)

func _ready():
	_montar_ambiente()
	if construcao_progressiva:
		return
	for etapa in _etapas():
		etapa[1].call()

## Distribui a primeira construção entre frames, mantendo o loading visível.
func construir():
	for etapa in _etapas():
		etapa_carregamento.emit(etapa[0])
		await get_tree().process_frame
		etapa[1].call()
	await get_tree().physics_frame

## [texto do loading, o que fazer] na ordem; a última costuma ser _montar_circuito
func _etapas() -> Array:
	return [["Preparando circuito", _montar_circuito]]

func _montar_ambiente():
	pass

func _nova_pista() -> PistaCorrida:
	return PistaCorrida.new()

## Onde fica o portal de volta (local do mapa): longe da pista, para o puxão não alcançar
func _posicao_portal_volta() -> Vector3:
	return Vector3.ZERO

func _montar_circuito():
	pista = _nova_pista()
	add_child(pista)
	# Adversários nas primeiras vagas do grid, cada um com sua personalidade
	CarroRival.preparar(self)
	var elenco := PerfilPiloto.elenco()
	for i in ADVERSARIOS:
		var rival := CarroRival.new(i + 1, elenco[i % elenco.size()])
		rival.pista = pista
		add_child(rival)
		rivais.append(rival)
	trafego = TrafegoCorrida.new()
	trafego.pista = pista
	trafego.rivais = rivais
	add_child(trafego)
	trafego.preparar()
	corrida = Corrida.new()
	corrida.pista = pista
	corrida.rivais = rivais
	corrida.trafego = trafego
	add_child(corrida)
	portal_volta = Portal.new()
	portal_volta.cor = Color(0.1, 0.85, 1.0)
	portal_volta.position = _posicao_portal_volta()
	add_child(portal_volta)

## Altura do chão no ponto do mundo
func altura(_x: float, _z: float) -> float:
	return 0.0

## Ajusta a luz do sol da cena para este mapa (padrão: meio-dia do deserto)
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	luz.light_color = Color(1.0, 0.93, 0.82)
	luz.light_energy = 1.5

## Vaga do grid no mundo, com folga de altura para o carro assentar nas rodas
## (por padrão a última, a do jogador)
func largada(posicao := ADVERSARIOS) -> Transform3D:
	var vaga := pista.grid(posicao)
	vaga.origin += vaga.basis.y * 0.3
	return global_transform * vaga
