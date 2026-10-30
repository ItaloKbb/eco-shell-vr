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
## Turbos de nitro flutuando na pista
var nitros: NitrosPista
var rivais: Array[CarroRival] = []
var trafego: TrafegoCorrida
var ambiente := Environment.new()
var construcao_progressiva := false
## Só o cenário (pista, terreno, portal): sem adversários, tráfego nem corrida. O
## espectador usa assim e põe os carros pela telemetria dos Quests
var so_cenario := false
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
	nitros = NitrosPista.new(pista)
	pista.add_child(nitros)
	if not so_cenario:
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

## Antes de cada corrida. Solo (`grupo` vazio): os 10 adversários com IA, o jogador na
## última vaga. Em grupo (Rede.sala): só os `rivais` da sala, com IA só no anfitrião
## (nos outros Quests seguem a rede). Devolve a vaga deste jogador
func preparar_corrida(grupo: Dictionary) -> int:
	trafego.limpar_remotos()
	return distribuir_grid(grupo)

## Jogadores nas vagas da sala e os adversários 1..`rivais` nas que sobram, da frente
## para trás: o grid sempre fecha com ADVERSARIOS + 1 carros. Também quando a sala muda
## antes da largada (entrou ou saiu alguém). Devolve a vaga deste jogador
func distribuir_grid(grupo: Dictionary) -> int:
	var remoto := not grupo.is_empty() and int(grupo.anfitriao) != multiplayer.get_unique_id()
	var vaga := ADVERSARIOS
	var dos_jogadores := []
	for jogador in grupo.get("jogadores", []):
		dos_jogadores.append(int(jogador.vaga))
		if int(jogador.peer) == multiplayer.get_unique_id():
			vaga = int(jogador.vaga)
	var livres: Array[int] = []
	for v in ADVERSARIOS + 1:
		if v not in dos_jogadores and v != vaga and livres.size() < ADVERSARIOS:
			livres.append(v)
	var quantos := mini(ADVERSARIOS if grupo.is_empty() else int(grupo.rivais), livres.size())
	var ativos: Array[CarroRival] = []
	for i in rivais.size():
		var rival := rivais[i]
		rival.ativar(i < quantos)
		rival.remoto = remoto
		if i < quantos:
			ativos.append(rival)
	corrida.rivais = ativos
	trafego.remoto = remoto
	trafego.vagas_rivais = livres.slice(0, quantos)
	trafego.definir_rivais(ativos)
	return vaga

## A sala mudou ainda no grid: refaz as vagas e estaciona a IA de novo
func atualizar_grupo(grupo: Dictionary):
	distribuir_grid(grupo)
	corrida.grupo = grupo
	trafego.preparar()

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

# --- Ajudantes de cenário ---------------------------------------------------------

## Chão plano (mapas ponta a ponta): piso grande em manchas largas de dois tons
## chapados (chao_campo.gdshader, sem textura: não cintila no headset) e um plano de
## colisão infinito na altura 0, embaixo da pista. Sem `cor_b`, o segundo tom é o
## primeiro um pouco mais claro
func _chao_plano(cor: Color, tamanho := 3200.0, cor_b := Color(0, 0, 0, 0)):
	var piso := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(tamanho, tamanho)
	var material := ShaderMaterial.new()
	material.shader = preload("res://chao_campo.gdshader")
	material.set_shader_parameter("cor_a", cor)
	material.set_shader_parameter("cor_b", cor_b if cor_b.a > 0.0 else cor.lightened(0.12))
	plano.material = material
	piso.mesh = plano
	add_child(piso)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	forma.shape = WorldBoundaryShape3D.new()
	corpo.add_child(forma)
	add_child(corpo)

## Distância no plano do ponto (local do mapa) até o centro da pista
func distancia_pista(x: float, z: float) -> float:
	var i := pista.amostra_perto(Vector3(x, 0.0, z))
	return Vector2(x - pista.pontos[i].x, z - pista.pontos[i].z).length()

## Várias cópias de uma malha numa MultiMesh (uma chamada de desenho só, leve no Quest),
## com cor por cópia se `cores` vier preenchida. `material`: no lugar do da malha
## (malhas de LowPoly.facetar vêm sem material)
func _instancias(malha: Mesh, pecas: Array[Transform3D], cores: Array[Color] = [], material: Material = null):
	if pecas.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cores.is_empty()
	mm.mesh = malha
	mm.instance_count = pecas.size()
	for k in pecas.size():
		mm.set_instance_transform(k, pecas[k])
		if mm.use_colors:
			mm.set_instance_color(k, cores[k])
	var no := MultiMeshInstance3D.new()
	no.multimesh = mm
	no.material_override = material
	add_child(no)
