extends Node3D
## Telão do evento (modo espectador, PC sem headset): conecta ao servidor da rede e
## transmite os jogadores ao vivo. Monta o mundo neon e os mapas de corrida só como
## cenário (MapaCorrida.so_cenario, nas mesmas origens de mundos.gd, então a geometria
## bate com a do Quest) e põe os carros pela telemetria (Rede.telemetria_recebida, ~30x/s
## por jogador), suavizada pelo InterpoladorRede de cada carro.
## A cada TEMPO_TOMADA troca de jogador E de ângulo (topo, diagonal alta, terceira
## pessoa); com um jogador só, troca só o ângulo. HUD de transmissão: nome, corrida,
## volta/posição, vida e velocidade.
## Teclas: ←/→ jogador · espaço pausa a troca · 1/2/3 fixa o ângulo (0 volta ao
## automático) · F11 tela cheia.

const Mundos := preload("res://mundos.gd")

enum Angulo { TOPO, DIAGONAL, TERCEIRA }
const NOMES_ANGULO := ["VISTA DE CIMA", "DIAGONAL ALTA", "TERCEIRA PESSOA"]
const TEMPO_TOMADA := 6.0
const TEMPO_CORTE := 0.25
const PINTURAS_JOGADOR := CarroFantasma.PINTURAS_JOGADOR

## Os mapas de corrida do jeito que os portais abrem (destino -> [classe, origem])
var _destinos := {
	"Deserto": [Deserto, Mundos.ORIGEM_DESERTO],
	"Vale das Turbinas": [ValeTurbinas, Mundos.ORIGEM_TURBINAS],
	"Sistema S": [SistemaS, Mundos.ORIGEM_SISTEMA_S],
	"Parque Industrial": [ParqueIndustrial, Mundos.ORIGEM_INDUSTRIAL],
	"I de Incrível": [Vulcao, Mundos.ORIGEM_VULCAO],
}
var ambiente: WorldEnvironment
var sol: DirectionalLight3D
var camera: Camera3D
var lobby: Node3D
var mapas := {}
## peer -> CarroFantasma
var carros := {}
## Os 10 adversários da corrida do jogador em foco (cada corrida é particular)
var rivais: Array[CarroFantasma] = []
## Último pacote de telemetria, por peer
var dados := {}
var foco := 0
var angulo := Angulo.TOPO
## -1 = automático; senão o ângulo fixado pelo operador
var angulo_fixo := -1
var pausado := false
var tempo_tomada := 0.0
var pronto := false
var mundo_atual := "-"

var _ambiente_neon: Environment
var _sol_neon: Transform3D
var _frente := Vector3.FORWARD
var _orbita := 0.0
var _hud: HudEspectador

func _ready():
	_ambiente_neon = preload("res://ambiente_neon.tres").duplicate()
	# Câmeras altas: a névoa do cockpit (42 m) apagaria o chão inteiro
	_ambiente_neon.fog_depth_end = 160.0
	_ambiente_neon.volumetric_fog_length = 120.0
	ambiente = WorldEnvironment.new()
	ambiente.environment = _ambiente_neon
	add_child(ambiente)
	sol = DirectionalLight3D.new()
	sol.transform = Transform3D(Basis(Vector3(0.8253356, 0, -0.5646425), Vector3(-0.44229966, 0.62161, -0.6465076), Vector3(0.3509874, 0.7833269, 0.51303685)), Vector3.ZERO)
	sol.light_color = Color(0.55, 0.65, 1.0)
	sol.light_energy = 0.5
	sol.shadow_enabled = true
	_sol_neon = sol.transform
	add_child(sol)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.1
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()

	lobby = Node3D.new()
	lobby.name = "Lobby"
	add_child(lobby)
	var hex := preload("res://hex_world.gd").new()
	hex.name = "HexWorld"
	lobby.add_child(hex)
	var atmosfera := preload("res://atmosphere.gd").new()
	atmosfera.name = "Atmosfera"
	lobby.add_child(atmosfera)
	lobby.add_child(TelaoRanking.new())

	_hud = HudEspectador.new()
	add_child(_hud)
	CarroRival.preparar(self)
	var elenco := PerfilPiloto.elenco()
	for i in MapaCorrida.ADVERSARIOS:
		var rival := CarroFantasma.new(CarroRival.PINTURAS[i % CarroRival.PINTURAS.size()], elenco[i % elenco.size()].nome, i + 1, false)
		rival.visible = false
		add_child(rival)
		rivais.append(rival)
	Rede.quadro_recebido.connect(receber_quadro)
	Rede.telemetria_recebida.connect(receber_telemetria)
	Ranking.ranking_mudou.connect(func(_top: Array): _hud.mostrar_ranking())
	await _montar_mapas()
	pronto = true
	_hud.carregando("")
	_aplicar_mundo("")
	receber_quadro(Rede.quadro)

## Os mapas de corrida são montados uma vez, atrás da tela de "preparando"
func _montar_mapas():
	for destino in _destinos:
		var mapa: MapaCorrida = _destinos[destino][0].new()
		mapa.so_cenario = true
		mapa.construcao_progressiva = true
		mapa.position = _destinos[destino][1]
		mapa.etapa_carregamento.connect(func(etapa: String): _hud.carregando("%s · %s" % [destino, etapa]))
		add_child(mapa)
		await mapa.construir()
		mapa.visible = false
		mapa.process_mode = Node.PROCESS_MODE_DISABLED
		mapas[destino] = mapa

# --- Telemetria da rede --------------------------------------------------------------

## Um pacote de um jogador: chega ~30x/s, repassado pelo servidor assim que o Quest
## manda, com o carimbo de tempo do Quest (`t`) para o interpolador do carro
func receber_telemetria(item: Dictionary):
	if not item.has("peer"):
		return
	var peer: int = item.peer
	var t := float(item.get("t", InterpoladorRede.agora()))
	dados[peer] = item
	if not carros.has(peer):
		var carro_novo := CarroFantasma.new(PINTURAS_JOGADOR[carros.size() % PINTURAS_JOGADOR.size()], _nome(item), 0, true)
		add_child(carro_novo)
		carros[peer] = carro_novo
	var carro: CarroFantasma = carros[peer]
	carro.rotulo.text = _nome(item)
	var escondido: bool = item.get("explodindo", false) or item.get("na_esfera", false)
	if item.get("explodindo", false) and not carro.explodindo:
		_explodir(carro)
	carro.explodindo = item.get("explodindo", false)
	# Reapareceu (renasceu, saiu da esfera): começa da pose nova, sem deslizar da antiga
	if not escondido and not carro.visible:
		carro.reiniciar()
	carro.visible = not escondido
	carro.receber(t, item.get("pos", Vector3.ZERO), item.get("rot", Quaternion.IDENTITY), float(item.get("vel", 0.0)))
	carro.ver_nitro(int(item.get("nitros", 0)))
	if pronto and peer == foco:
		_atualizar_foco_rivais()

## Lista dos jogadores ativos (o servidor manda a cada 0,5 s): quem saiu dela some
func receber_quadro(lista: Array):
	var vistos := {}
	for item in lista:
		if item is Dictionary and item.has("peer"):
			vistos[item.peer] = true
			receber_telemetria(item)
	for peer in carros.keys():
		if not vistos.has(peer):
			carros[peer].queue_free()
			carros.erase(peer)
			dados.erase(peer)

func _nome(item: Dictionary) -> String:
	var nome := str(item.get("nome", ""))
	return nome if nome != "" else str(item.get("apelido", "PILOTO"))

func _explodir(carro: CarroFantasma):
	var explosao := Explosao.new()
	add_child(explosao)
	explosao.global_position = carro.global_transform * Vector3(0.0, 0.35, 0.0)

## Rivais e relógio dos obstáculos vêm da corrida do jogador em foco (no mesmo pacote,
## com o mesmo carimbo de tempo)
func _atualizar_foco_rivais():
	var item: Dictionary = dados.get(foco, {})
	var t := float(item.get("t", InterpoladorRede.agora()))
	var lista: Array = item.get("rivais", [])
	var usados := {}
	for r in lista:
		var i := int(r[0]) - 1
		if i < 0 or i >= rivais.size():
			continue
		usados[i] = true
		rivais[i].receber(t, r[1], r[2], 0.0)
		rivais[i].visible = true
	for i in rivais.size():
		if not usados.has(i) and rivais[i].visible:
			rivais[i].visible = false
			rivais[i].reiniciar()
	var mapa: MapaCorrida = mapas.get(str(item.get("mapa", "")))
	if mapa is ValeTurbinas and mapa.obstaculos and item.has("relogio"):
		mapa.obstaculos.tempo = float(item.relogio)

# --- Diretor -------------------------------------------------------------------------

## Peers que vale mostrar: quem está dirigindo (na esfera só se não houver outro)
func ativos() -> Array:
	var todos := carros.keys()
	todos.sort()
	var dirigindo := todos.filter(func(p): return not dados[p].get("na_esfera", false))
	return dirigindo if not dirigindo.is_empty() else todos

func _process(delta: float):
	if not pronto:
		return
	var lista := ativos()
	_hud.atualizar_estado(Rede.conectado, lista.is_empty())
	if lista.is_empty():
		foco = 0
		_aplicar_mundo("")
		_orbitar(delta)
		return
	if foco not in lista:
		_cortar(lista[0], angulo)
	elif not pausado:
		tempo_tomada += delta
		if tempo_tomada >= TEMPO_TOMADA:
			proxima_tomada()
	var item: Dictionary = dados[foco]
	_aplicar_mundo(str(item.get("mapa", "")))
	_seguir(delta, false)
	_hud.mostrar_jogador(item, _nome(item), NOMES_ANGULO[angulo], lista, foco, pausado, tempo_tomada / TEMPO_TOMADA, carros)

## Próximo jogador (se houver outro) e próximo ângulo
func proxima_tomada(passo := 1):
	var lista := ativos()
	if lista.is_empty():
		return
	var i := lista.find(foco)
	var proximo: int = lista[posmod(i + passo, lista.size())] if i >= 0 else lista[0]
	var novo := angulo_fixo if angulo_fixo >= 0 else (angulo + 1) % Angulo.size()
	_cortar(proximo, novo)

func _cortar(peer: int, novo_angulo: int):
	# Outro jogador, outra corrida: os rivais recomeçam pelas poses da corrida dele
	if peer != foco:
		for rival in rivais:
			rival.reiniciar()
	foco = peer
	angulo = novo_angulo as Angulo
	tempo_tomada = 0.0
	_atualizar_foco_rivais()
	var item: Dictionary = dados.get(foco, {})
	_aplicar_mundo(str(item.get("mapa", "")))
	_hud.corte(TEMPO_CORTE)
	_seguir(0.0, true)

## Câmera atrás do carro em foco, no ângulo atual; `cortar` posiciona sem suavizar
func _seguir(delta: float, cortar: bool):
	var carro: CarroFantasma = carros.get(foco)
	if carro == null:
		return
	var alvo := carro.global_position
	var frente := -carro.global_basis.z
	frente.y = 0.0
	if frente.length_squared() > 0.01:
		frente = frente.normalized()
		_frente = frente if cortar else _frente.slerp(frente, 1.0 - exp(-3.0 * delta)).normalized()
	var lado := _frente.cross(Vector3.UP)
	var posicao: Vector3
	var mira: Vector3
	var cima := Vector3.UP
	match angulo:
		Angulo.TOPO:
			posicao = alvo + Vector3.UP * 28.0 + _frente * 2.0
			mira = alvo + _frente * 2.0
			cima = _frente
		Angulo.DIAGONAL:
			posicao = alvo - _frente * 14.0 + lado * 8.0 + Vector3.UP * 12.0
			mira = alvo + _frente * 3.0
		_:
			posicao = alvo - _frente * 6.5 + Vector3.UP * 2.4
			mira = alvo + _frente * 4.0 + Vector3.UP * 0.6
	var desejada := Transform3D(Basis.looking_at(mira - posicao, cima), posicao)
	if cortar:
		camera.global_transform = desejada
	else:
		camera.global_transform = camera.global_transform.interpolate_with(desejada, 1.0 - exp(-5.0 * delta))

## Sem ninguém dirigindo: sobrevoo lento do mundo neon
func _orbitar(delta: float):
	_orbita += delta * 0.04
	var posicao := Vector3(sin(_orbita) * 70.0, 32.0, cos(_orbita) * 70.0 - 20.0)
	camera.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, 8.0, -30.0) - posicao), posicao)

## Mostra o mundo neon ("") ou o mapa de corrida, com o céu e o sol de cada um
func _aplicar_mundo(nome_mapa: String):
	if not mapas.has(nome_mapa):
		nome_mapa = ""
	if nome_mapa == mundo_atual:
		return
	mundo_atual = nome_mapa
	for destino in mapas:
		var mapa: MapaCorrida = mapas[destino]
		mapa.visible = destino == nome_mapa
		mapa.process_mode = Node.PROCESS_MODE_INHERIT if mapa.visible else Node.PROCESS_MODE_DISABLED
	lobby.visible = nome_mapa == ""
	lobby.process_mode = Node.PROCESS_MODE_INHERIT if lobby.visible else Node.PROCESS_MODE_DISABLED
	if nome_mapa == "":
		ambiente.environment = _ambiente_neon
		sol.transform = _sol_neon
		sol.light_color = Color(0.55, 0.65, 1.0)
		sol.light_energy = 0.5
	else:
		ambiente.environment = mapas[nome_mapa].ambiente
		mapas[nome_mapa].sol(sol)

func _unhandled_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_RIGHT:
			proxima_tomada(1)
		KEY_LEFT:
			proxima_tomada(-1)
		KEY_SPACE:
			pausado = not pausado
		KEY_1, KEY_2, KEY_3:
			angulo_fixo = event.keycode - KEY_1
			_cortar(foco, angulo_fixo)
		KEY_0:
			angulo_fixo = -1
		KEY_F11:
			var cheia := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if cheia else DisplayServer.WINDOW_MODE_FULLSCREEN)


## HUD de transmissão (CanvasLayer): selo AO VIVO, ângulo e chips dos jogadores no
## topo; terço inferior com nome, corrida, vida e velocidade; telas de espera.
class HudEspectador extends CanvasLayer:
	const LARGURA_TERCO := 780.0

	var _ao_vivo: PanelContainer
	var _painel_vel: PanelContainer
	var _angulo: Label
	var _chips: HBoxContainer
	var _terco: PanelContainer
	var _nome: Label
	var _local: Label
	var _situacao: PanelContainer
	var _vida: HBoxContainer
	var _vida_texto: Label
	var _velocidade: Label
	var _progresso: ColorRect
	var _espera: PanelContainer
	var _espera_titulo: Label
	var _espera_ranking: VBoxContainer
	var _carregando: Label
	var _fade: ColorRect
	var _corte: Tween
	var _assinatura_chips := ""
	var _vida_max := -1

	func _init():
		layer = 10
		var raiz := Control.new()
		raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
		raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.theme = TemaEvento.criar()
		add_child(raiz)

		# Topo: AO VIVO + marca + ângulo à esquerda, jogadores à direita
		var topo := HBoxContainer.new()
		topo.set_anchors_preset(Control.PRESET_TOP_WIDE)
		topo.offset_left = 28
		topo.offset_right = -28
		topo.offset_top = 22
		topo.add_theme_constant_override("separation", 14)
		raiz.add_child(topo)
		_ao_vivo = TemaEvento.pilula("●  AO VIVO", TemaEvento.ALERTA, 16)
		topo.add_child(_ao_vivo)
		topo.add_child(TemaEvento.rotulo("ECO SHELL VR", 20, TemaEvento.CIANO, true))
		_angulo = TemaEvento.rotulo("", 15, TemaEvento.TEXTO_SUAVE, true)
		topo.add_child(_angulo)
		var vao := Control.new()
		vao.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		topo.add_child(vao)
		_chips = HBoxContainer.new()
		_chips.add_theme_constant_override("separation", 8)
		topo.add_child(_chips)

		# Terço inferior à esquerda (quem, onde, vida); velocidade num quadro à direita:
		# o meio da tela fica livre para a pista
		_terco = PanelContainer.new()
		_terco.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
		_terco.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_terco.offset_left = 28
		_terco.offset_right = 28 + LARGURA_TERCO
		_terco.offset_bottom = -26
		_terco.offset_top = -168
		_terco.grow_vertical = Control.GROW_DIRECTION_BEGIN
		raiz.add_child(_terco)
		var esquerda := VBoxContainer.new()
		esquerda.add_theme_constant_override("separation", 6)
		_terco.add_child(esquerda)
		var cabeca := HBoxContainer.new()
		cabeca.add_theme_constant_override("separation", 16)
		esquerda.add_child(cabeca)
		_nome = TemaEvento.rotulo("", 46, Color.WHITE, true)
		cabeca.add_child(_nome)
		_situacao = TemaEvento.pilula("", TemaEvento.CIANO, 15)
		_situacao.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cabeca.add_child(_situacao)
		_local = TemaEvento.rotulo("", 22, TemaEvento.CIANO, true)
		esquerda.add_child(_local)
		var linha_vida := HBoxContainer.new()
		linha_vida.add_theme_constant_override("separation", 12)
		esquerda.add_child(linha_vida)
		linha_vida.add_child(TemaEvento.rotulo("VIDA", 14, TemaEvento.TEXTO_SUAVE, true))
		_vida = HBoxContainer.new()
		_vida.add_theme_constant_override("separation", 4)
		linha_vida.add_child(_vida)
		_vida_texto = TemaEvento.rotulo("", 14, TemaEvento.TEXTO_SUAVE, false, true)
		linha_vida.add_child(_vida_texto)
		# Velocidade grande, no canto direito
		_painel_vel = PanelContainer.new()
		_painel_vel.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO))
		_painel_vel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_painel_vel.offset_left = -28 - 270
		_painel_vel.offset_right = -28
		_painel_vel.offset_bottom = -26
		_painel_vel.offset_top = -168
		_painel_vel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_painel_vel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		raiz.add_child(_painel_vel)
		var direita := VBoxContainer.new()
		direita.alignment = BoxContainer.ALIGNMENT_CENTER
		_painel_vel.add_child(direita)
		_velocidade = TemaEvento.rotulo("0", 76, Color.WHITE, true, true)
		_velocidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		direita.add_child(_velocidade)
		var unidade := TemaEvento.rotulo("KM/H", 16, TemaEvento.CIANO, true)
		unidade.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		direita.add_child(unidade)
		# Tempo da tomada: filete que enche até a próxima troca
		_progresso = ColorRect.new()
		_progresso.color = Color(TemaEvento.CIANO, 0.8)
		_progresso.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_progresso.offset_left = 28
		_progresso.offset_top = -27
		_progresso.offset_bottom = -24
		raiz.add_child(_progresso)

		# Espera: sem servidor ou sem ninguém jogando (com o top 5)
		var centro := CenterContainer.new()
		centro.set_anchors_preset(Control.PRESET_FULL_RECT)
		centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(centro)
		_espera = PanelContainer.new()
		_espera.add_theme_stylebox_override("panel", _caixa_vidro(TemaEvento.CIANO, 30.0))
		_espera.custom_minimum_size.x = 620
		centro.add_child(_espera)
		var coluna := VBoxContainer.new()
		coluna.add_theme_constant_override("separation", 14)
		_espera.add_child(coluna)
		_espera_titulo = TemaEvento.rotulo("", 30, Color.WHITE, true)
		_espera_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coluna.add_child(_espera_titulo)
		_espera_ranking = VBoxContainer.new()
		_espera_ranking.add_theme_constant_override("separation", 6)
		coluna.add_child(_espera_ranking)

		_fade = ColorRect.new()
		_fade.color = Color(0.0, 0.0, 0.0, 1.0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(_fade)
		# Por cima do fade: aparece na tela preta enquanto os mapas são montados
		_carregando = TemaEvento.rotulo("PREPARANDO TRANSMISSÃO", 20, TemaEvento.CIANO, true)
		_carregando.set_anchors_preset(Control.PRESET_CENTER)
		_carregando.offset_left = -450
		_carregando.offset_right = 450
		_carregando.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		raiz.add_child(_carregando)
		_terco.visible = false
		_painel_vel.visible = false
		_progresso.visible = false
		mostrar_ranking()

	func _caixa_vidro(cor: Color, margem := 20.0) -> StyleBoxFlat:
		var caixa := TemaEvento.estilo(Color(0.01, 0.025, 0.06, 0.82), Color(cor, 0.6), 0, 10, margem)
		caixa.border_width_left = 5
		return caixa

	func carregando(texto: String):
		_carregando.visible = texto != ""
		_carregando.text = "PREPARANDO TRANSMISSÃO  ·  " + texto.to_upper()
		if texto == "":
			corte(0.6)

	## Escurece e revela: esconde o salto da câmera numa troca de tomada
	func corte(tempo: float):
		if _corte and _corte.is_valid():
			_corte.kill()
		_fade.color.a = 1.0
		_corte = create_tween()
		_corte.tween_property(_fade, "color:a", 0.0, tempo).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	func atualizar_estado(conectado: bool, vazio: bool):
		var pulso := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.003))
		_ao_vivo.modulate.a = pulso if conectado else 0.35
		_espera.visible = vazio and not _carregando.visible
		_terco.visible = not vazio
		_painel_vel.visible = not vazio
		_progresso.visible = not vazio
		if vazio:
			_espera_titulo.text = "AGUARDANDO JOGADORES" if conectado else "PROCURANDO SERVIDOR DO EVENTO…"
			_angulo.text = ""
			_atualizar_chips([], 0, {})

	func mostrar_ranking():
		for filho in _espera_ranking.get_children():
			filho.queue_free()
		if Ranking.top.is_empty():
			return
		var titulo := TemaEvento.rotulo("RANKING · MELHORES TEMPOS", 15, TemaEvento.CIANO, true)
		titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_espera_ranking.add_child(titulo)
		var medalhas := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
		for i in mini(5, Ranking.top.size()):
			var r: Dictionary = Ranking.top[i]
			var linha := HBoxContainer.new()
			linha.add_theme_constant_override("separation", 16)
			var cor: Color = medalhas[i] if i < 3 else TemaEvento.TEXTO_SUAVE
			var pos := TemaEvento.rotulo("%dº" % (i + 1), 20, cor, true, true)
			pos.custom_minimum_size.x = 50
			linha.add_child(pos)
			var nome := TemaEvento.rotulo(str(r.get("nome", "")), 20, Color.WHITE, true)
			nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			linha.add_child(nome)
			linha.add_child(TemaEvento.rotulo(str(r.get("pista", "")), 15, TemaEvento.TEXTO_SUAVE))
			linha.add_child(TemaEvento.rotulo(Ranking.formatar_tempo(float(r.get("tempo", 0.0))), 20, cor, true, true))
			_espera_ranking.add_child(linha)

	func mostrar_jogador(item: Dictionary, nome: String, angulo: String, ativos: Array, foco: int, pausado: bool, fracao: float, carros: Dictionary):
		_nome.text = nome.to_upper()
		_angulo.text = "·  %s%s" % [angulo, "  ·  PAUSADO" if pausado else ""]
		var mapa := str(item.get("mapa", ""))
		if mapa != "":
			var texto := mapa.to_upper()
			var volta := int(item.get("volta", 0))
			var voltas := int(item.get("voltas", 3))
			if volta > 0 and voltas <= 1:
				# Ponta a ponta: não tem volta para contar
				texto += "  ·  SPRINT  ·  %dº DE %d" % [int(item.get("posicao", 0)), int(item.get("total", 0))]
			elif volta > 0:
				texto += "  ·  VOLTA %d/%d  ·  %dº DE %d" % [mini(volta, voltas), voltas, int(item.get("posicao", 0)), int(item.get("total", 0))]
			else:
				texto += "  ·  NO GRID"
			_local.text = texto
		else:
			_local.text = "MUNDO NEON" + ("  ·  NITRO" if item.get("nitro", false) else "")
		if item.get("explodindo", false):
			TemaEvento.mudar_pilula(_situacao, "EXPLODIU", TemaEvento.ALERTA)
		elif item.get("na_esfera", false):
			TemaEvento.mudar_pilula(_situacao, "NA ESFERA", TemaEvento.QUENTE)
		elif item.has("sobrecarga"):
			TemaEvento.mudar_pilula(_situacao, "SOBRECARGA %ds" % ceili(float(item.sobrecarga)), TemaEvento.ALERTA)
		elif mapa != "":
			TemaEvento.mudar_pilula(_situacao, "CORRIDA", TemaEvento.VERDE)
		else:
			TemaEvento.mudar_pilula(_situacao, "LOBBY", TemaEvento.CIANO)
		_mostrar_vida(int(item.get("vida", 0)), int(item.get("vida_max", 8)))
		_velocidade.text = "%d" % roundi(float(item.get("vel", 0.0)))
		_progresso.offset_right = _progresso.offset_left + LARGURA_TERCO * clampf(fracao, 0.0, 1.0)
		_atualizar_chips(ativos, foco, carros)

	func _mostrar_vida(vida: int, vida_max: int):
		if vida_max != _vida_max:
			_vida_max = vida_max
			for filho in _vida.get_children():
				_vida.remove_child(filho)
				filho.queue_free()
			for i in vida_max:
				var segmento := ColorRect.new()
				segmento.custom_minimum_size = Vector2(26, 14)
				_vida.add_child(segmento)
		var cor := TemaEvento.cor_nivel(float(vida) / maxf(vida_max, 1))
		for i in _vida.get_child_count():
			(_vida.get_child(i) as ColorRect).color = cor if i < vida else Color(1, 1, 1, 0.1)
		_vida_texto.text = "%d/%d" % [vida, vida_max]

	func _atualizar_chips(ativos: Array, foco: int, carros: Dictionary):
		var nomes := []
		for peer in ativos:
			nomes.append("%d:%s" % [peer, carros[peer].rotulo.text])
		var assinatura := "%s|%d" % [",".join(nomes), foco]
		if assinatura == _assinatura_chips:
			return
		_assinatura_chips = assinatura
		for filho in _chips.get_children():
			filho.queue_free()
		for peer in ativos:
			var cor := Color.WHITE if peer == foco else TemaEvento.TEXTO_SUAVE
			var chip := TemaEvento.pilula(carros[peer].rotulo.text.to_upper(), cor, 13)
			if peer != foco:
				chip.modulate.a = 0.7
			_chips.add_child(chip)
