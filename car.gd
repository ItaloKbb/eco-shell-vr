extends RigidBody3D
## Protótipo Eco Shell (3 rodas, piloto deitado sob a bolha), dirigido em primeira pessoa.
##
## No chão é um corpo rígido simulado pelo Jolt: cada roda é um raio com mola,
## amortecedor e atrito de pneu limitado pela carga, então o carro derrapa, capota e
## cai em buracos.
## W/S acelera/freia/ré, A/D esterça, Espaço é o freio de mão (solta a traseira).
##
## E (ou o botão no painel, apertado com o dedo em VR) liga a energia: o carro vira
## planador, fica cinemático e voa como numa montanha-russa, deixando duas paredes de
## luz sólidas saindo das pontas das asas, como as motos do Tron. Espaço levanta o
## nariz, Shift abaixa (o ângulo fica onde parou), A/D fazem curvas inclinando o carro
## aos poucos. Se o embalo não segurar o carro (lento de cabeça para baixo ou numa
## subida íngreme), ou se ele bater numa parede de luz, ele desgruda e cai.
##
## W duas vezes seguidas: dash. R: desvira/reposiciona. O mouse só move a cabeça.
##
## No Meta Quest (Quest Link / OpenXR) a câmera VR fica nos olhos do piloto e vale:
## gatilho direito acelera, gatilho esquerdo freia/ré, analógico esquerdo esterça,
## analógico direito (cima/baixo) inclina na energia, A liga a energia, B ou dois toques
## no gatilho direito fazem o dash, X é o freio de mão, Y desvira, clique no analógico
## esquerdo recentraliza a visão. Segurando o guidão com o grip (ou fechando a mão, com
## rastreamento de mãos), dá para esterçar girando o guidão com as próprias mãos.
## O teclado continua funcionando junto.

## Para o som (som_carro.gd): o carro tocou o chão pela primeira vez, usou o dash,
## ligou/desligou a energia, ou bateu (roda pousando, degrau, casco contra algo)
signal largou
signal dash_usado
signal energia_mudou(ligada: bool, caiu: bool)
signal impacto(forca: float, ponto: Vector3)
signal botao_apertado(ponto: Vector3)
## Dano: perdeu barrinhas de vida; explodiu (força total ou vida zerada); renasceu
signal dano(barras: int)
signal explodiu
signal retorno_solicitado
signal renasceu
## Energia do voo: encheu mais uma barra derrapando; tentou voar sem energia
signal energia_carregada(barras: int)
signal sem_energia

const VIDA_MAX := 5

const GRAVIDADE := 9.8
const CENTRO_ESFERA := Vector3(0, 1.5, 0)
const FOLGA_RODA := 0.35

@export var hex_world: Node3D
@export var pista: Node3D
@export var sensibilidade := 0.003
## Camadas que as rodas enxergam como chão (só o terreno: as paredes de luz são
## obstáculos, batidas pelo casco)
@export_flags_3d_physics var mascara_chao := 1

@export_group("Chão")
@export var aceleracao := 4.0
@export var frenagem := 10.0
## Baixo de propósito: o carro de eficiência roda solto quando se tira o pé
@export var arrasto := 0.6
@export var velocidade_max := 12.0
@export var velocidade_re := 3.0
@export var direcao_max := 0.42
## Esterço ainda disponível na velocidade máxima; preserva curvas sem dar trancos.
@export_range(0.1, 1.0) var direcao_em_velocidade := 0.5
@export var resposta_direcao := 1.4
@export var raio_roda := 0.245

@export_group("Suspensão e pneus")
@export var curso_suspensao := 0.15
@export var rigidez := 7800.0
@export var amortecimento := 1100.0
## Coeficiente de atrito: força máxima do pneu = atrito × carga na roda
@export var atrito_pneu := 1.1
## Quão rápido o pneu anula o escorregamento lateral (1/s)
@export var aderencia_lateral := 8.0

@export_group("Pista de energia")
@export var aceleracao_energia := 6.0
@export var velocidade_max_energia := 18.0
## Quanto a gravidade freia nas subidas e embala nas descidas (1 = real).
## Em 1, subidas acima de ~38° vencem o motor: é preciso embalo (ou dash) para passar.
@export_range(0.0, 1.0) var efeito_gravidade := 1.0
## Velocidade com que Espaço/Shift mudam a inclinação (rad/s)
@export var taxa_inclinacao := 0.7
@export var raio_curva := 15.0
## Inclinação lateral máxima nas curvas, como numa montanha-russa (rad)
@export var giro_max := 0.7
@export var taxa_giro := 1.5
## Atração magnética da pista, em g; somada à força centrípeta segura o carro invertido
@export var aderencia_energia := 0.35
## Abaixo disso o carro escorrega de subidas íngremes
@export var velocidade_minima := 4.0
## Distância mínima entre o carro e o centro da esfera inicial
@export var raio_esfera := 4.45

@export_group("Dash")
@export var dash_impulso := 8.0
@export var dash_recarga := 1.2
## Tempo máximo entre os dois toques no W (s)
@export var dash_janela := 0.3

@export_group("Energia")
## Barras de energia do voo. Só enchem derrapando no chão (freio de mão de lado)
@export var energia_max := 5
## Escorregamento lateral (m/s) a partir do qual a derrapagem carrega
@export var derrapagem_minima := 1.2
## Barras por segundo para cada m/s de escorregamento acima do mínimo
@export var carga_derrapagem := 0.35
## Barras gastas por segundo de voo
@export var consumo_voo := 0.25

@export_group("Dano")
## Força de um choque = variação brusca de velocidade (m/s). Abaixo disso, só barulho
@export var choque_minimo := 4.0
## Daqui para cima tira 2 barrinhas (abaixo, 1)
@export var choque_medio := 7.0
## Daqui para cima tira 3 barrinhas
@export var choque_forte := 11.0
## Força total: explode na hora
@export var choque_fatal := 15.0
## Roda pousando mais rápido que isso também estraga o carro (m/s)
@export var pouso_duro := 6.0
@export var tempo_renascer := 3.0
## Força de choque de uma ponta de pirâmide acertando o carro (8 = 2 barrinhas)
@export var dano_missil := 8.0

@export_group("VR")
@export_range(0.0, 0.5) var zona_morta := 0.15
## Distância da mão até a manopla para conseguir agarrar o guidão (m)
@export var alcance_guidao := 0.2
## Ângulo do guidão (rad) que corresponde ao esterço máximo
@export var giro_guidao_max := 0.6
@export var vibracao := true

## Cores do texto no visor do capacete
const HUD_AZUL := Color(0.3, 0.7, 1.0)
const HUD_ENERGIA := Color(0.6, 0.95, 1.0)
const HUD_ALERTA := Color(1.0, 0.3, 0.25)

@onready var camera: Camera3D = $Cabeca
@onready var camera_xr: XRCamera3D = $OrigemXR/CameraXR
@onready var mao_esquerda: XRController3D = $OrigemXR/MaoEsquerda
@onready var mao_direita: XRController3D = $OrigemXR/MaoDireita
@onready var manoplas: Array[Node3D] = [$Guidao/ManoplaE, $Guidao/ManoplaD]
@onready var rodas: Array[Node3D] = [$RodaFE, $RodaFD, $RodaT]
@onready var giros_rodas: Array[Node3D] = [$RodaFE/Giro, $RodaFD/Giro, $RodaT/Giro]
@onready var guidao: Node3D = $Guidao
@onready var capacete: CapaceteHUD = $Capacete
@onready var casco: CascoEcoShell = $Casco
@onready var pintura: ShaderMaterial = $Casco.material_casco
@onready var horizonte: ShaderMaterial = $Painel/Horizonte.material_override
@onready var asas: Array[Node3D] = [$AsaE, $AsaD]
@onready var pontas_asas: Array[Node3D] = [$AsaE/Malha/Ponta, $AsaD/Malha/Ponta]
@onready var tela_traseira: SubViewport = $TelaTraseira
@onready var botao: Node3D = $Painel/BotaoEnergia
@onready var botao_tampa: Node3D = $Painel/BotaoEnergia/Tampa
@onready var material_botao: StandardMaterial3D = $Painel/BotaoEnergia/Tampa.mesh.material

## Botão da energia no painel: curso da tampa (m) e quanto precisa afundar para acionar
const CURSO_BOTAO := 0.008
const ACIONA_BOTAO := 0.006
@onready var luz_inferior: OmniLight3D = $LuzInferior
@onready var material_roda: ShaderMaterial = $RodaT/Giro/Pneu.mesh.material
@onready var material_asa: ShaderMaterial = $AsaE/Malha.mesh.material

## Modo planador (pista de energia): onde cada roda fica deitada, como disco de levitação
const POSE_VOO: Array[Vector3] = [Vector3(-0.36, 0.22, -0.75), Vector3(0.36, 0.22, -0.75), Vector3(0.0, 0.05, 0.7)]

## Velocidade ao longo da frente do carro
var velocidade := 0.0
var direcao := 0.0
var gerando := false
## Orientação no modo energia, em ângulos de Euler (ordem YXZ do Godot)
var rumo := 0.0
var inclinacao := 0.0
var giro := 0.0
var rodas_no_chao := 0
## 1 = pista segurando com folga, 0 = vai cair
var aderencia := 1.0
## Comando do acelerador (-1 a 1), quanto está freando (0 a 1) e o maior
## escorregamento dos pneus no chão (m/s), lidos pelo som
var comando_acel := 0.0
var freio := 0.0
var derrapagem := 0.0
## Barrinhas de vida (não regeneram: só voltam ao renascer)
var vida := VIDA_MAX
var explodindo := false
var em_ritual := false
var em_transicao := false
var nickname := "PILOTO"
## Nos circuitos não tem voo de energia (só derrapagem e dash)
var pode_voar := true
## Texto da corrida (corrida.gd); quando tem, ocupa o lado esquerdo do visor
var painel_corrida := ""
var _ja_largou := false
## Energia do voo, em barras (fração = barra enchendo). Começa vazia
var energia := 0.0
## Derrapando o bastante para carregar neste passo
var carregando := false
var _deriva_lateral := 0.0
## Puxão de portal acumulado neste passo, e sua intensidade para o visor
var _puxao := Vector3.ZERO
var _puxao_hud := 0.0
var _brilho_carga := 0.0

var _ancoras: Array[Vector3] = []
var _repouso_rodas: Array[Vector3] = []
var _consulta_roda := PhysicsShapeQueryParameters3D.new()
var _distancias: Array[float] = [0.0, 0.0, 0.0]
var _ultimo_seguro: Transform3D
var _capotado := 0.0
var _ultimo_w := -10.0
var _recarga := 0.0
var _aviso := ""
var _aviso_tempo := 0.0
var _fov := 75.0
var _olhar := Vector2.ZERO
var _ultimo_gatilho := -10.0
var _energia_visual := 0.0
var _esperando_chao := false
## Mãos segurando o guidão: [esquerda, direita]
var _segurando := [false, false]
## Pontas dos indicadores das mãos VR: [esqueleto, osso]
var _dedos: Array = []
var _botao_preso := false
## Maior choque de contato do casco no passo de física (m/s) e onde foi
var _choque := 0.0
var _ponto_choque := Vector3.ZERO
var _ultimo_dano := -10.0
var _fumaca: GPUParticles3D
var _faiscas: GPUParticles3D
## Para detectar pousos e pancadas: roda encostada no frame anterior e último impacto
var _tocando := [false, false, false]
var _ultimo_impacto := [0.0, 0.0, 0.0]

func _ready():
	# Os inimigos procuram o carro por este grupo
	add_to_group("carro")
	# Colisão com o mesmo formato do casco (envoltória convexa da malha gerada)
	$Forma.shape = $Casco.mesh.create_convex_shape(true, true)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	for r in rodas:
		_ancoras.append(r.position + Vector3.UP * 0.1)
		_repouso_rodas.append(r.position)
	_distancias.fill(curso_suspensao + raio_roda)
	var esfera := SphereShape3D.new()
	esfera.radius = raio_roda
	_consulta_roda.shape = esfera
	_consulta_roda.collision_mask = mascara_chao
	_consulta_roda.exclude = [get_rid()]
	_ultimo_seguro = global_transform
	# O terreno é gerado aos poucos: segura o carro até existir chão embaixo dele
	freeze = true
	_esperando_chao = true
	_fov = camera.fov
	_olhar = Vector2(camera.rotation.x, camera.rotation.y)
	mao_esquerda.button_pressed.connect(_botao_esquerdo)
	mao_direita.button_pressed.connect(_botao_direito)
	# Choques do casco: lidos em _integrate_forces pelo impulso de cada contato
	contact_monitor = true
	max_contacts_reported = 4
	# Avarias: fumaça na traseira com vida baixa, faíscas quando está quase explodindo
	_fumaca = Explosao.fumaca()
	_fumaca.position = Vector3(0.0, 0.55, 1.0)
	add_child(_fumaca)
	_faiscas = Explosao.faiscas()
	_faiscas.position = Vector3(0.0, 0.4, 0.6)
	add_child(_faiscas)
	# Só depois do menu escolher entre VR e monitor dá para saber qual câmera usar
	_vestir_capacete.call_deferred()
	_montar_camera_traseira()
	for mao in [mao_esquerda, mao_direita]:
		for esqueleto: Skeleton3D in mao.find_children("*", "Skeleton3D", true, false):
			for nome in ["Index_Tip_L", "Index_Tip_R"]:
				var osso := esqueleto.find_bone(nome)
				if osso >= 0:
					_dedos.append([esqueleto, osso])

## Câmera de ré: olha para trás, um pouco para baixo, da cauda; imagem pequena num
## SubViewport mostrada no painel. Ambiente sem névoa volumétrica nem glow (é barata)
func _montar_camera_traseira():
	$MiraTraseira.basis = Basis.looking_at(Vector3(0.0, -0.14, 1.0))
	if OS.has_feature("android"):
		tela_traseira.size = Vector2i(256, 144)
	($Painel/Retrovisor.material_override as ShaderMaterial).set_shader_parameter("tela", tela_traseira.get_texture())
	_ambiente_traseira.call_deferred()

func _ambiente_traseira():
	var mundo := get_world_3d().environment
	if mundo == null:
		return
	var env: Environment = mundo.duplicate()
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	env.ssr_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	$TelaTraseira/CameraTraseira.environment = env

func _process(_delta):
	if em_ritual or em_transicao:
		tela_traseira.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Câmera de ré a meia taxa de quadros: metade do custo, e ainda fluida no painel
	if Engine.get_process_frames() % 2 == 0:
		tela_traseira.render_target_update_mode = SubViewport.UPDATE_ONCE
	if get_viewport().use_xr and not em_ritual and not em_transicao:
		_apertar_botao()

## Botão físico do painel: a ponta do indicador empurra a tampa; afundando o bastante,
## liga/desliga a energia (uma vez por toque, solta quando o dedo sai)
func _apertar_botao():
	var afunda := 0.0
	var quem := -1
	for i in _dedos.size():
		var esqueleto: Skeleton3D = _dedos[i][0]
		if not esqueleto.is_visible_in_tree():
			continue
		var ponta := esqueleto.global_transform * esqueleto.get_bone_global_pose(_dedos[i][1]).origin
		var p := botao.to_local(ponta)
		# Topo da tampa em z = 0,014; aceita o dedo dentro do raio e pouco à frente
		if Vector2(p.x, p.y).length() < 0.028 and p.z > -0.02 and p.z < 0.03:
			var d := 0.014 - p.z
			if d > afunda:
				afunda = d
				quem = i
	afunda = clampf(afunda, 0.0, CURSO_BOTAO)
	botao_tampa.position.z = 0.008 - afunda
	if afunda >= ACIONA_BOTAO and not _botao_preso:
		_botao_preso = true
		_alternar_energia()
		botao_apertado.emit(botao.global_position)
		var esqueleto: Skeleton3D = _dedos[quem][0]
		_vibrar(mao_esquerda if mao_esquerda.is_ancestor_of(esqueleto) else mao_direita, 0.5, 0.05)
	elif afunda < 0.002:
		_botao_preso = false

## O visor do capacete vai junto com a câmera ativa (a cabeça do piloto)
func _vestir_capacete():
	capacete.reparent(camera_xr if get_viewport().use_xr else camera, false)
	capacete.transform = Transform3D.IDENTITY

## O carro recebe comandos quando a câmera dele está ativa ou quando está em VR
func _ativo() -> bool:
	return camera.current or get_viewport().use_xr

func recentralizar():
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

func _input(event):
	if not _ativo():
		return
	if not em_ritual and not em_transicao and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _alternar_energia()
			KEY_R: _desvirar()
			KEY_W: _ultimo_w = _toque_duplo(_ultimo_w)
	if get_viewport().use_xr:
		return
	# Esc libera o cursor; um clique volta a capturá-lo.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_olhar.y = clamp(_olhar.y - event.relative.x * sensibilidade, -1.9, 1.9)
		_olhar.x = clamp(_olhar.x - event.relative.y * sensibilidade, -1.0, 0.8)
		camera.rotation = Vector3(_olhar.x, _olhar.y, 0.0)

## Segundo toque dentro da janela dispara o dash; devolve o novo "último toque"
func _toque_duplo(ultimo: float) -> float:
	var agora := Time.get_ticks_msec() / 1000.0
	if agora - ultimo <= dash_janela:
		_dash()
		return -10.0
	return agora

func _botao_esquerdo(nome: String):
	if em_ritual or em_transicao:
		return
	match nome:
		"by_button": _desvirar()
		"primary_click", "menu_button": recentralizar()

func _botao_direito(nome: String):
	if em_ritual or em_transicao:
		return
	match nome:
		"ax_button": _alternar_energia()
		"by_button": _dash()
		"trigger_click": _ultimo_gatilho = _toque_duplo(_ultimo_gatilho)

func _physics_process(delta):
	if em_ritual or em_transicao:
		capacete.visible = false
		return
	if _esperando_chao:
		var consulta := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 5.0, mascara_chao, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(consulta):
			return
		_esperando_chao = false
		freeze = false
		# O motor só dá a partida na primeira vez (ao voltar de um portal ele já está ligado)
		if not _ja_largou:
			_ja_largou = true
			largou.emit()
	if explodindo:
		_atualizar_painel()
		return
	# Comandos analógicos (-1 a 1) somando teclado e controles do Quest
	var acel := 0.0
	var vira := 0.0
	var sobe := 0.0
	var freio_mao := false
	if _ativo():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): acel += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): acel -= 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): vira += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): vira -= 1.0
		if Input.is_key_pressed(KEY_SPACE):
			sobe += 1.0
			freio_mao = true
		if Input.is_key_pressed(KEY_SHIFT): sobe -= 1.0
	if get_viewport().use_xr:
		acel += _analogico(mao_direita.get_float("trigger")) - _analogico(mao_esquerda.get_float("trigger"))
		vira -= _analogico(mao_esquerda.get_vector2("primary").x)
		sobe += _analogico(mao_direita.get_vector2("primary").y)
		freio_mao = freio_mao or mao_esquerda.is_button_pressed("ax_button")
		var manual = _esterco_manual()
		if manual != null:
			vira = manual
	acel = clamp(acel, -1.0, 1.0)
	vira = clamp(vira, -1.0, 1.0)
	sobe = clamp(sobe, -1.0, 1.0)
	comando_acel = acel
	_recarga = max(_recarga - delta, 0.0)
	_aviso_tempo -= delta

	if gerando:
		_andar_na_energia(delta, acel, vira, sobe)
	else:
		_andar_com_fisica(delta, acel, vira, freio_mao)
	if _choque > 0.0:
		var forca := _choque
		_choque = 0.0
		if forca > 1.5:
			_registrar_choque(forca, _ponto_choque)
	if explodindo or em_ritual or em_transicao:
		return
	# Caiu no vazio (buraco ou fora do mapa): volta ao último lugar seguro
	if global_position.y < -30.0:
		_reposicionar(_ultimo_seguro)
		_avisar("REPOSICIONADO", 1.5)
	_aplicar_puxao()
	_animar(delta)
	_atualizar_painel()

# --- Chão: corpo rígido com suspensão por raio ------------------------------

func _andar_com_fisica(delta: float, acel: float, vira: float, freio_mao: bool):
	var cima := global_basis.y
	var frente := -global_basis.z
	velocidade = linear_velocity.dot(frente)
	var rapidez: float = clamp(abs(velocidade) / velocidade_max, 0.0, 1.0)
	direcao = move_toward(direcao, vira * direcao_max * lerp(1.0, direcao_em_velocidade, rapidez), resposta_direcao * delta)

	var espaco_fisico := get_world_3d().direct_space_state
	var alcance := curso_suspensao + raio_roda
	var parte := mass / 3.0
	rodas_no_chao = 0
	freio = 1.0 if freio_mao else 0.0
	derrapagem = 0.0
	_deriva_lateral = 0.0
	var agora := Time.get_ticks_msec() / 1000.0
	for i in 3:
		# Esfera do tamanho da roda descendo pelo curso da suspensão: passa liso
		# pelos degraus entre hexágonos, onde um raio fino "cairia" em cada borda
		# Começa acima da âncora: o Jolt ignora formas que já partem encostadas no chão,
		# então uma roda afundada (pouso forte) nunca mais acharia o chão
		var ancora: Vector3 = global_transform * _ancoras[i]
		_consulta_roda.transform = Transform3D(Basis(), ancora + cima * FOLGA_RODA)
		_consulta_roda.motion = -cima * (curso_suspensao + FOLGA_RODA)
		var fracao := espaco_fisico.cast_motion(_consulta_roda)
		_distancias[i] = alcance
		if fracao[0] >= 1.0:
			_tocando[i] = false
			continue
		rodas_no_chao += 1
		_distancias[i] = max((curso_suspensao + FOLGA_RODA) * fracao[0] - FOLGA_RODA, 0.0) + raio_roda
		var ponto := ancora - cima * _distancias[i]
		var braco := ponto - global_position
		# linear_velocity é medida no centro de massa, não na origem do casco.
		var vel_ponto := linear_velocity + angular_velocity.cross(braco - global_basis * center_of_mass)

		# Mola + amortecedor ao longo do eixo do carro
		var carga: float = max(0.0, rigidez * (alcance - _distancias[i]) - amortecimento * vel_ponto.dot(cima))

		# Pneu: direção da roda (as dianteiras esterçam) e escorregamentos
		var frente_roda := frente.rotated(cima, direcao) if i < 2 else frente
		var lado_roda := frente_roda.cross(cima)
		var v_long := vel_ponto.dot(frente_roda)
		var v_lat := vel_ponto.dot(lado_roda)
		var traseira := i == 2

		# Pouso (a roda volta a encostar) ou pancada num degrau: velocidade de compressão
		var fechamento := -vel_ponto.dot(cima)
		if (not _tocando[i] and fechamento > 0.8) or (fechamento > 1.4 and agora - _ultimo_impacto[i] > 0.12):
			# Só pouso bem duro estraga: a suspensão absorve o resto
			_registrar_choque(fechamento, ponto, pouso_duro - choque_minimo)
			_ultimo_impacto[i] = agora
		_tocando[i] = true
		derrapagem = max(derrapagem, absf(v_lat))
		_deriva_lateral = max(_deriva_lateral, absf(v_lat))
		if (acel > 0.0 and v_long < -0.3) or (acel < 0.0 and v_long > 0.3):
			freio = max(freio, absf(acel))
		if freio_mao and traseira:
			derrapagem = max(derrapagem, absf(v_long))

		var f_long := 0.0
		var parar := absf(v_long) * parte / delta
		if (acel > 0.0 and v_long < -0.3) or (acel < 0.0 and v_long > 0.3):
			f_long = -signf(v_long) * min(frenagem * parte * absf(acel), parar)
		elif traseira and acel > 0.0 and v_long < velocidade_max:
			f_long = aceleracao * mass * acel
		elif traseira and acel < 0.0 and v_long > -velocidade_re:
			f_long = aceleracao * 0.6 * mass * acel
		elif acel == 0.0:
			f_long = -signf(v_long) * min(arrasto * parte, parar)
		if freio_mao and traseira:
			f_long = -signf(v_long) * min(frenagem * 1.5 * parte, parar)

		# Freio de mão solta a traseira para derrapar
		var grip := aderencia_lateral * (0.25 if freio_mao and traseira else 1.0)
		var atrito := Vector2(f_long, -v_lat * parte * grip).limit_length(atrito_pneu * carga)
		apply_force(cima * carga + frente_roda * atrito.x + lado_roda * atrito.y, braco)

	# Derrapagem de lado (não vale travar a roda indo reto) carrega a energia do voo
	carregando = rodas_no_chao >= 2 and _deriva_lateral > derrapagem_minima and energia < energia_max
	if carregando:
		var antes := floori(energia)
		energia = minf(energia + (_deriva_lateral - derrapagem_minima) * carga_derrapagem * delta, energia_max)
		if floori(energia) > antes:
			energia_carregada.emit(floori(energia))
			_vibrar_ambas(0.4, 0.06)

	if rodas_no_chao == 3 and cima.y > 0.8:
		_ultimo_seguro = global_transform
	# Capotou e parou: desvira sozinho depois de um tempo
	if cima.y < 0.3 and linear_velocity.length() < 1.0:
		_capotado += delta
		if _capotado > 2.0:
			_desvirar()
	else:
		_capotado = 0.0

# --- Pista de energia: trilho cinemático ------------------------------------

func _alternar_energia():
	if pista == null or explodindo or em_ritual or em_transicao:
		return
	if not gerando and not pode_voar:
		_avisar("SEM VOO AQUI", 1.5)
		sem_energia.emit()
		return
	if gerando:
		_sair_da_energia(false)
	elif energia < 1.0:
		# Para decolar precisa de pelo menos uma barra cheia
		_avisar("DERRAPE!", 1.5)
		sem_energia.emit()
	else:
		_entrar_na_energia()

func _entrar_na_energia():
	var e := global_basis.get_euler()
	# No chão o carro sempre tem um pouco de nariz para cima ou para baixo (suspensão,
	# degraus). No voo isso vira subida contínua e o carro passa por cima das próprias
	# paredes de luz: inclinações pequenas começam niveladas
	inclinacao = e.x if absf(e.x) > deg_to_rad(8.0) else 0.0
	rumo = e.y
	giro = e.z if absf(e.z) > deg_to_rad(8.0) else 0.0
	velocidade = max(linear_velocity.dot(-global_basis.z), 0.0)
	freeze = true
	gerando = true
	freio = 0.0
	derrapagem = 0.0
	pista.comecar(global_transform, _pontas())
	_vibrar_ambas(0.3, 0.1)
	energia_mudou.emit(true, false)

func _sair_da_energia(caiu: bool):
	gerando = false
	pista.terminar(global_transform, _pontas())
	freeze = false
	linear_velocity = -global_basis.z * velocidade
	angular_velocity = Vector3.ZERO
	energia_mudou.emit(false, caiu)
	if caiu:
		# Desgrudou: sai rodopiando um pouco
		angular_velocity = global_basis.z * randf_range(-1.5, 1.5) + global_basis.x * randf_range(-0.6, 0.6)
		_avisar("SEM ADERÊNCIA!", 2.0)
		_vibrar_ambas(1.0, 0.4)

func _andar_na_energia(delta: float, acel: float, vira: float, sobe: float):
	# O voo gasta energia; acabou, o planador desliga e o carro cai
	energia = maxf(energia - consumo_voo * delta, 0.0)
	if energia <= 0.0:
		_sair_da_energia(false)
		_avisar("SEM ENERGIA", 2.0)
		return
	if acel > 0.0: velocidade = max(velocidade, min(velocidade + aceleracao_energia * acel * delta, velocidade_max_energia))
	elif acel < 0.0: velocidade = move_toward(velocidade, 0.0, frenagem * -acel * delta)
	else: velocidade = move_toward(velocidade, 0.0, arrasto * delta)
	# Embalo do dash acima da máxima vai se dissipando
	if velocidade > velocidade_max_energia:
		velocidade = move_toward(velocidade, velocidade_max_energia, 4.0 * delta)
	velocidade = max(velocidade - GRAVIDADE * efeito_gravidade * sin(inclinacao) * delta, 0.0)

	inclinacao = wrapf(inclinacao + sobe * taxa_inclinacao * delta, -PI, PI)
	# De cabeça para baixo o rumo gira ao contrário, então A continua sendo "esquerda do piloto"
	var invertido := cos(inclinacao) < 0.0
	rumo += vira * max(velocidade, 3.0) / raio_curva * delta * (-1.0 if invertido else 1.0)
	giro = lerp_angle(giro, vira * giro_max, taxa_giro * delta)
	direcao = move_toward(direcao, vira * 0.15, 2.5 * delta)

	var b := Basis.from_euler(Vector3(inclinacao, rumo, giro))
	var pos := global_position - b.z * velocidade * delta
	# Puxão de portal: no trilho cinemático vira um desvio suave do caminho
	pos += _puxao * 0.6 * delta
	# A pista não atravessa o chão: encosta e vai nivelando o nariz
	var h := _altura_terreno(pos)
	if pos.y < h:
		pos.y = h
		if inclinacao < 0.0 and not invertido:
			inclinacao = lerp(inclinacao, 0.0, min(1.0, 8.0 * delta))
	var batida := _parede_no_caminho(Transform3D(b, pos))
	if not batida.is_empty():
		_bater_na_parede(batida)
		return
	global_transform = Transform3D(b, pos)
	pista.adicionar(global_transform, _pontas())

	# Aderência: a pista segura com força centrípeta (curvando o nariz) + atração magnética.
	# A parte da gravidade que puxa o carro para fora da pista só existe de lado/invertido.
	var puxao := -b.y.y * GRAVIDADE
	var segura := velocidade * absf(sobe) * taxa_inclinacao + aderencia_energia * GRAVIDADE
	aderencia = clamp(1.0 - puxao / segura, 0.0, 1.0) if puxao > 0.0 else 1.0
	var subida := -b.z.y
	if subida > 0.42: # mais de ~25° subindo: precisa de embalo
		aderencia = min(aderencia, clamp((velocidade - velocidade_minima) / velocidade_minima, 0.0, 1.0))
	if puxao > segura or (subida > 0.42 and velocidade < velocidade_minima):
		_sair_da_energia(true)
	elif (pos + b.y * 0.3 - CENTRO_ESFERA).length() < raio_esfera:
		_sair_da_energia(true)

## Pontas das asas, de onde saem as paredes de luz
func _pontas() -> Array[Vector3]:
	return [pontas_asas[0].global_position, pontas_asas[1].global_position]

## Colisão com uma parede de luz no passo de voo: o casco indo da posição atual até a
## nova, e a envergadura (de ponta a ponta) já na posição nova. As asas encostam nas
## próprias paredes recém-criadas, então essa parte ignora os trechos mais novos.
func _parede_no_caminho(novo: Transform3D) -> Dictionary:
	var espaco := get_world_3d().direct_space_state
	# Casco: um raio rente ao fundo e outro na altura da bolha
	for altura in [0.12, 0.7]:
		var raio := PhysicsRayQueryParameters3D.create(
			global_transform * Vector3(0, altura, 0), novo * Vector3(0, altura, -1.3), pista.camada_colisao, [get_rid()])
		var achou := espaco.intersect_ray(raio)
		if not achou.is_empty():
			return achou
	var desloca := novo * global_transform.affine_inverse()
	var p := _pontas()
	var excluir: Array[RID] = pista.recentes()
	excluir.append(get_rid())
	var asas_ray := PhysicsRayQueryParameters3D.create(desloca * p[0], desloca * p[1], pista.camada_colisao, excluir)
	return espaco.intersect_ray(asas_ray)

## Puxão de portal (aceleração em m/s², somada de todos os portais por perto)
func puxar(aceleracao: Vector3):
	if not explodindo and not em_ritual and not em_transicao:
		_puxao += aceleracao

## No chão vira força; no voo já desviou o caminho em _andar_na_energia. Vibra as mãos
## e mostra o aviso enquanto puxa
func _aplicar_puxao():
	_puxao_hud = _puxao.length()
	if _puxao_hud > 0.0:
		if not gerando:
			apply_central_force(_puxao * mass)
		if Engine.get_physics_frames() % 6 == 0:
			_vibrar_ambas(clampf(_puxao_hud / Portal.PUXAO_MAX, 0.0, 1.0) * 0.3, 0.06)
	_puxao = Vector3.ZERO

## Velocidade real do carro no mundo (no voo ele é cinemático e linear_velocity é zero)
func velocidade_mundo() -> Vector3:
	return -global_basis.z * velocidade if gerando else linear_velocity

## Ponta de pirâmide acertou: derruba do voo ou empurra no chão, e estraga o carro
func atingido_por_missil(ponto: Vector3, direcao_missil: Vector3):
	if explodindo or em_ritual or em_transicao:
		return
	if gerando:
		_sair_da_energia(true)
	else:
		apply_central_impulse((direcao_missil.normalized() * 3.0 + Vector3.UP * 2.0) * mass)
	_avisar("ATINGIDO!", 1.5)
	_registrar_choque(dano_missil, ponto)

func _bater_na_parede(batida: Dictionary):
	var forca := maxf(velocidade, choque_minimo)
	_sair_da_energia(true)
	_avisar("PAREDE DE LUZ!", 2.0)
	_registrar_choque(forca, batida.position)

# --- VR -----------------------------------------------------------------------

## Remove a zona morta e reescala o resto para continuar indo de 0 a 1
func _analogico(v: float) -> float:
	if absf(v) < zona_morta:
		return 0.0
	return signf(v) * (absf(v) - zona_morta) / (1.0 - zona_morta)

## Esterço vindo das mãos no guidão, ou null se nenhuma mão está segurando.
## Agarra com o grip perto da manopla; o ângulo da linha entre as mãos (ou da mão
## em volta do centro do guidão) em torno do eixo do carro vira o esterço.
func _esterco_manual():
	var maos: Array[XRController3D] = [mao_esquerda, mao_direita]
	var locais: Array[Vector3] = []
	for i in 2:
		var grip := maos[i].get_float("grip")
		var local := to_local(maos[i].global_position)
		locais.append(local)
		if not _segurando[i] and grip > 0.6 and maos[i].global_position.distance_to(manoplas[i].global_position) < alcance_guidao:
			_segurando[i] = true
			_vibrar(maos[i], 0.3, 0.05)
		elif _segurando[i] and grip < 0.4:
			_segurando[i] = false

	var angulo := 0.0
	if _segurando[0] and _segurando[1]:
		var d := locais[1] - locais[0]
		angulo = atan2(d.y, d.x)
	elif _segurando[0] or _segurando[1]:
		var i := 0 if _segurando[0] else 1
		var d := locais[i] - guidao.position
		var repouso := manoplas[i].position
		angulo = wrapf(atan2(d.y, d.x) - atan2(repouso.y, repouso.x), -PI, PI)
	else:
		return null
	return clamp(angulo / giro_guidao_max, -1.0, 1.0)

func _vibrar(mao: XRController3D, forca: float, tempo: float):
	if vibracao and get_viewport().use_xr:
		mao.trigger_haptic_pulse("haptic", 0.0, forca, tempo, 0.0)

func _vibrar_ambas(forca: float, tempo: float):
	_vibrar(mao_esquerda, forca, tempo)
	_vibrar(mao_direita, forca, tempo)

# --- Habilidades e utilidades -----------------------------------------------

func _dash():
	if _recarga > 0.0 or explodindo or em_ritual or em_transicao:
		return
	_recarga = dash_recarga
	if gerando:
		velocidade += dash_impulso
	else:
		apply_central_impulse(-global_basis.z * dash_impulso * mass)
	var tw := create_tween()
	tw.tween_property(camera, "fov", _fov + 18.0, 0.08)
	tw.tween_property(camera, "fov", _fov, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_avisar("DASH!", 0.6)
	_vibrar_ambas(0.6, 0.15)
	dash_usado.emit()

# --- Dano e explosão -----------------------------------------------------------

## Impulso de cada contato do casco dividido pela massa = variação brusca de velocidade
func _integrate_forces(state: PhysicsDirectBodyState3D):
	if em_ritual or em_transicao:
		return
	for i in state.get_contact_count():
		var forca := state.get_contact_impulse(i).length() / mass
		if forca > _choque:
			_choque = forca
			_ponto_choque = state.get_contact_collider_position(i)

## Todo choque passa por aqui: toca o som e, se for forte, tira vida e marca o casco.
## `folga` é descontada só do dano (pouso de roda, que a suspensão amortece)
func _registrar_choque(forca: float, ponto: Vector3, folga := 0.0):
	impacto.emit(forca, ponto)
	var f := forca - folga
	if explodindo or em_ritual or em_transicao or f < choque_minimo:
		return
	# Um choque dura alguns passos de física: conta uma vez só
	var agora := Time.get_ticks_msec() / 1000.0
	if agora - _ultimo_dano < 0.4:
		return
	_ultimo_dano = agora
	if f >= choque_fatal:
		_explodir()
		return
	var barras := 1 if f < choque_medio else (2 if f < choque_forte else 3)
	vida = maxi(vida - barras, 0)
	casco.marcar(casco.to_local(ponto), clampf(f / choque_fatal * 1.4, 0.4, 1.0))
	dano.emit(barras)
	_avisar("DANO!", 1.2)
	_vibrar_ambas(0.9, 0.25)
	if vida == 0:
		_explodir()

func _explodir():
	if explodindo or em_ritual or em_transicao:
		return
	explodindo = true
	vida = 0
	if gerando:
		_sair_da_energia(false)
	var explosao := Explosao.new()
	explosao.velocidade = linear_velocity
	get_parent().add_child(explosao)
	explosao.global_position = global_transform * Vector3(0.0, 0.35, 0.0)
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_mostrar_carro(false)
	_vibrar_ambas(1.0, 0.6)
	explodiu.emit()
	await get_tree().create_timer(tempo_renascer).timeout
	retorno_solicitado.emit()

## Some com o carro na explosão (as câmeras ficam: o piloto vê tudo de dentro do fogo)
func _mostrar_carro(sim: bool):
	for parte in [casco, $Painel, $Guidao, $FarolE, $FarolD, $LuzTraseira, luz_inferior] + rodas + asas:
		parte.visible = sim
	_fumaca.emitting = false
	_faiscas.emitting = false

func _desvirar():
	if gerando or explodindo or em_ritual or em_transicao:
		return
	var f := -global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = global_basis.y.slide(Vector3.UP)
	_reposicionar(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP))

## Leva o carro para outro lugar (troca de mapa): parado, e ali passa a ser o lugar seguro.
## Com `esperar_chao`, fica congelado até existir chão embaixo (o mapa hexagonal é
## gerado aos poucos)
func teleportar(t: Transform3D, esperar_chao := false):
	_reposicionar(t)
	_ultimo_seguro = t
	if esperar_chao:
		freeze = true
		_esperando_chao = true

func atualizar_ambiente_traseira():
	_ambiente_traseira()

func _reposicionar(t: Transform3D):
	if gerando:
		_sair_da_energia(false)
	global_transform = Transform3D(t.basis, t.origin + Vector3.UP * 0.3)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_capotado = 0.0

func _avisar(texto: String, tempo: float):
	_aviso = texto
	_aviso_tempo = tempo

func _altura_terreno(p: Vector3) -> float:
	return hex_world.altura(p.x, p.z) if hex_world else 0.0

func _animar(delta: float):
	# Modo planador: ao gerar a pista o carro se transforma aos poucos (~0,6 s). As rodas
	# deitam e viram discos de levitação girando com LED, depois as asas abrem; o filete
	# neon do casco e a luz por baixo acendem junto
	_energia_visual = move_toward(_energia_visual, 1.0 if gerando else 0.0, 1.6 * delta)
	var deita := smoothstep(0.0, 0.7, _energia_visual)
	var abre := smoothstep(0.3, 1.0, _energia_visual)
	for i in 3:
		giros_rodas[i].rotation.x -= (velocidade / raio_roda + 14.0 * deita) * delta
		# Roda acompanha a suspensão (no trilho fica na posição de repouso)
		var descida := 0.1 if gerando else _distancias[i] - raio_roda
		var no_chao := Vector3(_repouso_rodas[i].x, _ancoras[i].y - descida, _repouso_rodas[i].z)
		rodas[i].position = no_chao.lerp(POSE_VOO[i], deita)
		var lado := -1.0 if i == 0 else 1.0
		var esterco := direcao if i < 2 else 0.0
		rodas[i].rotation = Vector3(0.0, esterco * (1.0 - deita), PI * 0.5 * lado * deita)
	for k in 2:
		var lado := -1.0 if k == 0 else 1.0
		asas[k].visible = abre > 0.01
		# Saem dobradas para trás, junto ao casco, e abrem com leve diedro
		asas[k].scale = Vector3(maxf(abre, 0.01), 1.0, 1.0)
		asas[k].rotation = Vector3(0.0, -lado * lerpf(1.3, 0.12, abre), lado * 0.08 * abre)
	# Carregando na derrapagem: o filete neon pisca
	_brilho_carga = move_toward(_brilho_carga, 0.7 if carregando else 0.0, 4.0 * delta)
	var pisca := _brilho_carga * (0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 30.0))
	pintura.set_shader_parameter("energia", maxf(_energia_visual, pisca))
	material_roda.set_shader_parameter("led", deita)
	material_asa.set_shader_parameter("energia", abre)
	luz_inferior.light_energy = 1.5 * deita
	# Botão da energia: aceso fraco desligado, pulsando forte ligado
	var pulso := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
	# Botão quase apagado enquanto não há energia para decolar
	var desligado := 0.6 if energia >= 1.0 else 0.12
	material_botao.emission_energy_multiplier = lerpf(desligado, 2.0 + 1.5 * pulso, _energia_visual)
	_fumaca.emitting = vida <= 2
	_faiscas.emitting = vida <= 1
	guidao.rotation.z = direcao * 2.0

func _atualizar_painel():
	var incl := inclinacao
	var gir := giro
	var rum := rumo
	if not gerando:
		var e := global_basis.get_euler()
		incl = e.x
		gir = e.z
		rum = e.y
	var linha_ader := "ADER  %3d%%" % roundi(aderencia * 100.0) if gerando else "RODAS  %d/3" % rodas_no_chao
	var barras := "█".repeat(vida) + "·".repeat(VIDA_MAX - vida)
	var esquerda := "INCL %+4d°\nGIRO %+4d°\nRUMO  %03d°\n%s\nVIDA %s" % [
		roundi(rad_to_deg(incl)), roundi(rad_to_deg(gir)), roundi(fposmod(-rad_to_deg(rum), 360.0)), linha_ader, barras]
	if painel_corrida != "":
		esquerda = painel_corrida + "\nVIDA " + barras
	var cor_esquerda := HUD_ALERTA if (gerando and aderencia < 0.25) or vida <= 2 else HUD_AZUL
	# Última barrinha: pisca
	if vida == 1 and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.3:
		cor_esquerda = HUD_ALERTA * 0.45

	var km_h := 0 if explodindo else roundi((velocidade if gerando else linear_velocity.length()) * 3.6)
	# Barras de energia: cheias, a que está enchendo/acabando (▒ a partir de 1/3) e vazias
	var cheias := floori(energia)
	var meia := 1 if energia - cheias >= 0.34 and cheias < energia_max else 0
	var estado := "%s %s" % ["VOO " if gerando else "ENER", "█".repeat(cheias) + "▒".repeat(meia) + "·".repeat(energia_max - cheias - meia)]
	# Ameaça: míssil no ar ou pirâmide travando a mira
	var ameaca := ""
	if not get_tree().get_nodes_in_group("misseis").is_empty():
		ameaca = "MÍSSIL!"
	else:
		for piramide in get_tree().get_nodes_in_group("piramides"):
			if piramide.travando and piramide.alvo == self:
				ameaca = "TRAVANDO"
	if _aviso_tempo > 0.0:
		estado = _aviso
	elif ameaca != "":
		estado = ameaca
	elif _puxao_hud > 0.8:
		estado = "PORTAL"
	if explodindo:
		estado = "DESTRUÍDO"
	var linha_dash := "DASH OK" if _recarga <= 0.0 else "DASH %.1fs" % _recarga
	var direita := "ALT %.1f m\n%s\n%s" % [global_position.y - _altura_terreno(global_position), estado, linha_dash]
	var cor_direita := HUD_ALERTA if _aviso_tempo > 0.0 or explodindo or ameaca != "" else (HUD_ENERGIA if gerando else HUD_AZUL)
	# Na câmera livre de debug o visor não faz sentido
	capacete.visible = _ativo() and not em_transicao
	capacete.escrever(esquerda, cor_esquerda, km_h, direita, cor_direita)

	# Horizonte artificial: de cabeça para baixo mostra a mesma atitude sem passar de ±90°
	if cos(incl) < 0.0:
		incl = wrapf(PI - incl, -PI, PI)
		gir += PI
	horizonte.set_shader_parameter("inclinacao", incl)
	horizonte.set_shader_parameter("giro", gir)

## Preparação de cada vida, controlada pelo ritual de partida.
func preparar_vida(t: Transform3D):
	em_ritual = true
	if gerando:
		_sair_da_energia(false)
	freeze = true
	_esperando_chao = false
	_reposicionar(t)
	vida = VIDA_MAX
	energia = 0.0
	velocidade = 0.0
	direcao = 0.0
	comando_acel = 0.0
	freio = 0.0
	derrapagem = 0.0
	carregando = false
	_puxao = Vector3.ZERO
	_puxao_hud = 0.0
	_choque = 0.0
	_ultimo_dano = -10.0
	_ultimo_w = -10.0
	_ultimo_gatilho = -10.0
	_recarga = 0.0
	_energia_visual = 0.0
	_brilho_carga = 0.0
	_aviso_tempo = 0.0
	_tocando.fill(false)
	_distancias.fill(curso_suspensao + raio_roda)
	casco.consertar()
	_mostrar_carro(true)
	explodindo = false
	_animar(0.0)
	renasceu.emit()

func liberar_partida(t: Transform3D):
	teleportar(t)
	_esperando_chao = false
	_ultimo_seguro = global_transform
	_choque = 0.0
	_ultimo_dano = Time.get_ticks_msec() / 1000.0
	linear_velocity = -global_basis.z * 12.0
	velocidade = 12.0
	_ja_largou = true
	em_ritual = false
	freeze = false
	sleeping = false
	largou.emit()
## Congela a física durante o loading sem bloquear o rastreamento da cabeça.
func iniciar_transicao():
	if gerando:
		_sair_da_energia(false)
	em_transicao = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	comando_acel = 0.0
	_puxao = Vector3.ZERO
	_choque = 0.0

func terminar_transicao():
	em_transicao = false
	freeze = em_ritual or explodindo or _esperando_chao
