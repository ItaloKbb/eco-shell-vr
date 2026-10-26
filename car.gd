extends RigidBody3D
## Protótipo Eco Shell (3 rodas, piloto deitado sob a bolha), dirigido em primeira pessoa.
##
## No chão é um corpo rígido simulado pelo Jolt: cada roda é um raio com mola,
## amortecedor e atrito de pneu limitado pela carga, então o carro derrapa, capota e
## cai em buracos.
## W/S acelera/freia/ré, A/D esterça, Espaço é o freio de mão (solta a traseira).
## Acelerar e frear ao mesmo tempo (W+S, ou os dois gatilhos) faz drift: a traseira
## solta mas continua tracionando.
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
## esquerdo recentraliza a visão; clique no direito alterna o conforto VR. As mãos aparecem como os controles do Quest (ou a malha
## da própria mão, com rastreamento de mãos); o guidão só acompanha o esterço.
## O teclado continua funcionando junto.
##
## Gamepad (Xbox, ROG Ally, Steam Deck...) segue o mesmo esquema do Quest: RT acelera,
## LT freia/ré, analógico esquerdo esterça, analógico direito inclina na energia (cima/
## baixo) e olha para os lados, A liga a energia, B ou dois toques no RT fazem o dash,
## X é o freio de mão, Y desvira; clique em qualquer analógico recentraliza os olhos
## exatamente na âncora do cockpit, inclusive no menu de nascimento.

## Para o som (som_carro.gd): o carro tocou o chão pela primeira vez, usou o dash,
## ligou/desligou a energia, ou bateu (roda pousando, degrau, casco contra algo)
signal largou
signal dash_usado
signal energia_mudou(ligada: bool, caiu: bool)
## `material`: o que foi atingido (chao, estrutura, luz, rival), para o som
signal impacto(forca: float, ponto: Vector3, material: StringName)
signal botao_apertado(ponto: Vector3)
## Dano: perdeu barrinhas de vida; explodiu (força total ou vida zerada); renasceu
signal dano(barras: int)
signal explodiu
signal retorno_solicitado
signal renasceu
signal visao_recentralizada
## Energia do voo: encheu mais uma barra derrapando; tentou voar sem energia
signal energia_carregada(barras: int)
signal sem_energia

const VIDA_MAX := 8
const CONFORTO_VR := preload("res://conforto_vr.gd")

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
@export var velocidade_re := 5.0
## Força do motor em marcha à ré como fração da aceleração para a frente.
@export_range(0.0, 1.0) var forca_re := 0.9
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
## Barras de energia do voo. Só enchem derrapando no chão (freio de mão de lado ou
## drift). A primeira vida da sessão já começa com a energia cheia
@export var energia_max := 5
## Escorregamento lateral (m/s) a partir do qual a derrapagem carrega
@export var derrapagem_minima := 0.6
## Barras por segundo para cada m/s de escorregamento acima do mínimo
@export var carga_derrapagem := 0.8
## Barras gastas por segundo de voo
@export var consumo_voo := 0.25
## Fração da aderência lateral que a traseira mantém no drift (acelerando e freando juntos)
@export_range(0.05, 1.0) var aderencia_drift := 0.3

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
## Lobby (mundo neon): segundos livres depois de sair da esfera; passado isso o casco
## entra em sobrecarga e perde a vida aos poucos, explodindo em `tempo_sobrecarga`.
## Empurra o piloto para uma corrida. Zera a cada vida e ao entrar num mapa de corrida
@export var tempo_lobby := 35.0
@export var tempo_sobrecarga := 15.0

@export_group("VR")
@export_range(0.0, 0.5) var zona_morta := 0.15
@export var vibracao := true

## Posição local dos olhos no cockpit. Ao recentralizar, a origem OpenXR compensa
## integralmente a pose física atual para colocar a câmera exatamente aqui.
const ANCORA_CABECA_LOCAL := Vector3(0.0, 0.8, 0.05)

@export_group("Gamepad")
## Velocidade de giro da cabeça com o analógico direito (rad/s)
@export var giro_olhar_controle := 2.5

## Cores do texto no visor do capacete
const HUD_AZUL := Color(0.3, 0.7, 1.0)
const HUD_ENERGIA := Color(0.6, 0.95, 1.0)
const HUD_ALERTA := Color(1.0, 0.3, 0.25)

@onready var camera: Camera3D = $Cabeca
@onready var camera_xr: XRCamera3D = $OrigemXR/CameraXR
@onready var mao_esquerda: XRController3D = $OrigemXR/MaoEsquerda
@onready var mao_direita: XRController3D = $OrigemXR/MaoDireita
## Modelos dos controles do Quest e malhas das mãos rastreadas: [esquerda, direita]
@onready var controles: Array[Node3D] = [$OrigemXR/MaoEsquerda/Controle, $OrigemXR/MaoDireita/Controle]
@onready var maos_rastreadas: Array[Node3D] = [$OrigemXR/MaoRastreadaE, $OrigemXR/MaoRastreadaD]
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
## Velocidade tangencial do casco encostando no cenário (alimenta som e faíscas)
var raspagem := 0.0
## Barrinhas de vida (não regeneram: só voltam ao renascer)
var vida := VIDA_MAX
var explodindo := false
var em_ritual := false
var em_transicao := false
## Parado no grid esperando a largada (corrida.gd): comandos lidos, carro preso
var segurado := false
var nickname := "PILOTO"
## Nos circuitos não tem voo de energia (só derrapagem e dash)
var pode_voar := true
## Texto da corrida (corrida.gd); quando tem, ocupa o lado esquerdo do visor
var painel_corrida := ""
var _ja_largou := false
## Energia do voo, em barras (fração = barra enchendo). Cheia na primeira vida
var energia := 0.0
var _primeira_vida := true
## Acelerando e freando juntos: traseira solta para derrapar
var drift := false
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
## Segundos no lobby nesta vida (ver tempo_lobby) e a vida ao entrar na sobrecarga
var tempo_no_lobby := 0.0
var _vida_na_sobrecarga := VIDA_MAX
var _fov := 75.0
var _olhar := Vector2.ZERO
var _olhar_repouso := Vector2.ZERO
var _ultimo_gatilho := -10.0
var _ultimo_rt := -10.0
var _rt_apertado := false
var _energia_visual := 0.0
var _esperando_chao := false
var _botao_preso := false
## Maior choque de contato do casco no passo de física (m/s) e onde foi
var _choque := 0.0
var _ponto_choque := Vector3.ZERO
var _material_choque := &"chao"
## Tremor da câmera depois de um choque (só no monitor: na VR enjoa; lá vibra o controle)
var _tremor := 0.0
var _conforto_vr
var _ultimo_dano := -10.0
var _fumaca: GPUParticles3D
var _faiscas: GPUParticles3D
var _faiscas_atrito: GPUParticles3D
var _ponto_raspagem := Vector3.ZERO
var _ultimo_efeito_impacto := -10.0
## Para detectar pousos e pancadas: roda encostada no frame anterior e último impacto
var _tocando := [false, false, false]
var _ultimo_impacto := [0.0, 0.0, 0.0]
## Trilho de um loop (EstruturasNeon): pontos, cimas e distâncias acumuladas; vazio = fora
var _trilho := {}
var _trilho_s := 0.0
var _trilho_i := 0
## Desvio lateral de quando entrou fora do centro, desfeito aos poucos
var _trilho_desvio := 0.0
## Tempo com as três rodas no ar (s)
var _no_ar := 0.0

func _ready():
	# A rede (telemetria, avatar do lobby) procura o carro por este grupo
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
	# Segura o carro até existir colisão de chão embaixo dele.
	freeze = true
	_esperando_chao = true
	_fov = camera.fov
	_olhar = Vector2(camera.rotation.x, camera.rotation.y)
	_olhar_repouso = _olhar
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
	_faiscas_atrito = Explosao.faiscas_atrito()
	add_child(_faiscas_atrito)
	# Só depois do menu escolher entre VR e monitor dá para saber qual câmera usar
	_vestir_capacete.call_deferred()
	_montar_conforto_vr.call_deferred()
	_montar_camera_traseira()

func _montar_conforto_vr():
	if not get_viewport().use_xr:
		return
	_conforto_vr = CONFORTO_VR.new(self)
	camera_xr.add_child(_conforto_vr)

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

func _process(delta):
	_tremer(delta)
	# Inclusive no nascimento: sem isso mãos e controles ficam visíveis na origem XR,
	# que fica na altura dos olhos, e grudam no rosto até o rastreamento começar
	if get_viewport().use_xr:
		_trocar_maos()
	if em_ritual or em_transicao:
		tela_traseira.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Câmera de ré a meia taxa de quadros: metade do custo, e ainda fluida no painel
	if Engine.get_process_frames() % 2 == 0:
		tela_traseira.render_target_update_mode = SubViewport.UPDATE_ONCE
	if get_viewport().use_xr:
		_apertar_botao()

## Rastreador da mão (esqueleto de juntas) de cada lado, ou null sem rastreamento de mãos
func _rastreador_mao(i: int) -> XRHandTracker:
	return XRServer.get_tracker("/user/hand_tracker/left" if i == 0 else "/user/hand_tracker/right") as XRHandTracker

## Mão rastreada de verdade (sem controle na mão): mostra a malha da mão do Quest;
## senão, o modelo do controle. Sem rastreamento nenhum, esconde os dois
func _mao_livre(i: int) -> bool:
	var rastreador := _rastreador_mao(i)
	return rastreador != null and rastreador.has_tracking_data \
		and rastreador.hand_tracking_source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER

func _trocar_maos():
	for i in 2:
		var livre := _mao_livre(i)
		var mao: XRController3D = mao_esquerda if i == 0 else mao_direita
		maos_rastreadas[i].visible = livre
		controles[i].visible = not livre and mao.get_has_tracking_data()

## Ponta que aperta o botão do painel: o indicador da mão rastreada, ou a frente do controle
func _ponta_dedo(i: int) -> Vector3:
	if _mao_livre(i):
		var junta := _rastreador_mao(i).get_hand_joint_transform(XRHandTracker.HAND_JOINT_INDEX_FINGER_TIP)
		return ($OrigemXR as XROrigin3D).global_transform * junta.origin
	var mao: XRController3D = mao_esquerda if i == 0 else mao_direita
	return mao.global_transform * Vector3(0.0, 0.0, -0.07)

## Botão físico do painel: a ponta do indicador (ou do controle) empurra a tampa;
## afundando o bastante, liga/desliga a energia (uma vez por toque, solta quando sai)
func _apertar_botao():
	var afunda := 0.0
	var quem := -1
	for i in 2:
		var mao: XRController3D = mao_esquerda if i == 0 else mao_direita
		if not mao.get_has_tracking_data() and not _mao_livre(i):
			continue
		var p := botao.to_local(_ponta_dedo(i))
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
		_vibrar(mao_esquerda if quem == 0 else mao_direita, 0.5, 0.05)
	elif afunda < 0.002:
		_botao_preso = false

## Tremor da câmera do monitor: deslocamento da lente (h/v_offset), sem girar a visão
func _tremer(delta: float):
	if _tremor <= 0.0:
		return
	_tremor = maxf(_tremor - 3.5 * delta, 0.0)
	var t := Time.get_ticks_msec() / 1000.0
	var amplitude := 0.05 * _tremor * _tremor
	camera.h_offset = sin(t * 61.0) * amplitude
	camera.v_offset = sin(t * 47.0 + 1.3) * amplitude

## O visor do capacete vai junto com a câmera ativa (a cabeça do piloto)
func _vestir_capacete():
	capacete.reparent(camera_xr if get_viewport().use_xr else camera, false)
	capacete.transform = Transform3D.IDENTITY

## O carro recebe comandos quando a câmera dele está ativa ou quando está em VR
func _ativo() -> bool:
	return camera.current or get_viewport().use_xr

func recentralizar():
	if get_viewport().use_xr:
		# No APK o jogo começa a desenhar antes do Quest rastrear a cabeça: centralizar
		# com a pose ainda vazia deixa os olhos fora da âncora (dentro da casca do ovo).
		# Espera a pose valer, com limite para não travar sem headset.
		var cabeca := XRServer.get_tracker(&"head") as XRPositionalTracker
		var espera := 0
		while cabeca and espera < 300 and not _cabeca_rastreada(cabeca):
			espera += 1
			await get_tree().process_frame
		# Zera posição e rotação para que a frente física passe a coincidir com a
		# frente do carro. No frame seguinte a nova pose do runtime já está válida.
		XRServer.center_on_hmd(XRServer.RESET_FULL_ROTATION, false)
		await get_tree().process_frame
		_alinhar_origem_xr()
	else:
		_olhar = _olhar_repouso
		camera.rotation = Vector3(_olhar.x, _olhar.y, 0.0)
		visao_recentralizada.emit()

func _cabeca_rastreada(cabeca: XRPositionalTracker) -> bool:
	var pose := cabeca.get_pose(&"default")
	return pose != null and pose.has_tracking_data

func _alinhar_origem_xr():
	var origem := $OrigemXR as XROrigin3D
	origem.basis = Basis.IDENTITY
	# A posição rastreada da câmera é relativa à origem. Deslocar a origem pelo
	# inverso dessa pose coloca os olhos na âncora sem limitar movimentos futuros.
	origem.position = ANCORA_CABECA_LOCAL - camera_xr.position
	visao_recentralizada.emit()

func _input(event):
	if not _ativo():
		return
	# A centralização precisa funcionar inclusive dentro do menu de nascimento.
	if get_viewport().use_xr and event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_RIGHT_STICK:
			if _conforto_vr:
				_avisar("CONFORTO VR: " + _conforto_vr.ciclar(), 2.0)
			get_viewport().set_input_as_handled()
			return
		if event.button_index in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_BACK]:
			recentralizar()
			get_viewport().set_input_as_handled()
			return
	if not em_ritual and not em_transicao and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E: _alternar_energia()
			KEY_R: _desvirar()
			KEY_W: _ultimo_w = _toque_duplo(_ultimo_w)
	if not em_ritual and not em_transicao and event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _alternar_energia()
			JOY_BUTTON_B: _dash()
			JOY_BUTTON_Y: _desvirar()
			JOY_BUTTON_LEFT_STICK, JOY_BUTTON_BACK:
				if get_viewport().use_xr:
					recentralizar()
			JOY_BUTTON_RIGHT_STICK:
				_olhar = _olhar_repouso
				camera.rotation = Vector3(_olhar.x, _olhar.y, 0.0)
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
	if nome in ["primary_click", "menu_button"]:
		recentralizar()
		return
	if em_ritual or em_transicao:
		return
	match nome:
		"by_button": _desvirar()

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
	# Acelerador e freio separados: os dois juntos viram drift em vez de se anularem
	var pedal := 0.0
	var pedal_freio := 0.0
	if _ativo():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): pedal += 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): pedal_freio += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): vira += 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): vira -= 1.0
		if Input.is_key_pressed(KEY_SPACE):
			sobe += 1.0
			freio_mao = true
		if Input.is_key_pressed(KEY_SHIFT): sobe -= 1.0
		var rt := eixo_controle(JOY_AXIS_TRIGGER_RIGHT)
		pedal += _analogico(rt)
		pedal_freio += _analogico(eixo_controle(JOY_AXIS_TRIGGER_LEFT))
		vira -= _analogico(eixo_controle(JOY_AXIS_LEFT_X))
		# No Godot o eixo Y dos analógicos é positivo para baixo
		sobe -= _analogico(eixo_controle(JOY_AXIS_RIGHT_Y))
		freio_mao = freio_mao or botao_controle(JOY_BUTTON_X)
		# Dois toques no RT: dash (com histerese para não contar tremidas do gatilho)
		if not _rt_apertado and rt > 0.6:
			_rt_apertado = true
			_ultimo_rt = _toque_duplo(_ultimo_rt)
		elif _rt_apertado and rt < 0.3:
			_rt_apertado = false
		var olhar_x := _analogico(eixo_controle(JOY_AXIS_RIGHT_X))
		if olhar_x != 0.0 and not get_viewport().use_xr:
			_olhar.y = clamp(_olhar.y - olhar_x * giro_olhar_controle * delta, -1.9, 1.9)
			camera.rotation = Vector3(_olhar.x, _olhar.y, 0.0)
	if get_viewport().use_xr:
		pedal += _analogico(mao_direita.get_float("trigger"))
		pedal_freio += _analogico(mao_esquerda.get_float("trigger"))
		vira -= _analogico(mao_esquerda.get_vector2("primary").x)
		sobe += _analogico(mao_direita.get_vector2("primary").y)
		freio_mao = freio_mao or mao_esquerda.is_button_pressed("ax_button")
	pedal = minf(pedal, 1.0)
	pedal_freio = minf(pedal_freio, 1.0)
	drift = pedal > 0.5 and pedal_freio > 0.5 and not gerando
	acel += pedal if drift else pedal - pedal_freio
	acel = clamp(acel, -1.0, 1.0)
	vira = clamp(vira, -1.0, 1.0)
	sobe = clamp(sobe, -1.0, 1.0)
	comando_acel = acel
	_recarga = max(_recarga - delta, 0.0)
	_aviso_tempo -= delta

	# Na largada: lê os comandos (o motor ronca) e mantém o visor, mas não anda
	if segurado:
		_animar(delta)
		_atualizar_painel()
		return
	if gerando:
		_andar_na_energia(delta, acel, vira, sobe)
	elif not _trilho.is_empty():
		_andar_no_trilho(delta, acel)
	else:
		_andar_com_fisica(delta, acel, vira, freio_mao)
	if _choque > 0.0:
		var forca := _choque
		_choque = 0.0
		if forca > 1.5:
			_registrar_choque(forca, _ponto_choque, 0.0, _material_choque)
	_atualizar_atrito()
	if explodindo or em_ritual or em_transicao:
		return
	# Fora do lobby (abismo, borda do piso ou voando além dela): explode e renasce na
	# esfera. Nos mapas de corrida, caiu no vazio volta ao último lugar seguro
	if _fora_do_lobby():
		_explodir()
		return
	_sobrecarga_lobby(delta)
	if explodindo:
		return
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
		# sem perder contato em altas velocidades ou depois de um pouso forte.
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
			f_long = aceleracao * forca_re * mass * acel
		elif acel == 0.0:
			f_long = -signf(v_long) * min(arrasto * parte, parar)
		if freio_mao and traseira:
			f_long = -signf(v_long) * min(frenagem * 1.5 * parte, parar)

		# Freio de mão solta a traseira para derrapar; no drift ela solta mas segue tracionando
		var grip := aderencia_lateral
		if traseira and freio_mao:
			grip *= 0.25
		elif traseira and drift:
			grip *= aderencia_drift
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

	# Salto rápido (rampas, lançador do abismo): no ar o nariz acompanha a trajetória
	# aos poucos, só na arfagem, para pousar com as rodas e não com a cauda
	_no_ar = _no_ar + delta if rodas_no_chao == 0 else 0.0
	if _no_ar > 0.15 and linear_velocity.length() > 8.0:
		var direita := global_basis.x
		var rumo_voo := linear_velocity.slide(direita)
		if rumo_voo.length() > 1.0:
			var erro := frente.signed_angle_to(rumo_voo, direita)
			var alvo := direita * clampf(erro * 3.0, -2.0, 2.0)
			angular_velocity += (alvo - angular_velocity.project(direita)) * minf(1.0, 4.0 * delta)

	if rodas_no_chao == 3 and cima.y > 0.8:
		_ultimo_seguro = global_transform
	# Capotou e parou: desvira sozinho depois de um tempo
	if cima.y < 0.3 and linear_velocity.length() < 1.0:
		_capotado += delta
		if _capotado > 2.0:
			_desvirar()
	else:
		_capotado = 0.0

# --- Loops: trilho cinemático ----------------------------------------------

## Entrada de um loop: o carro passa a seguir o caminho com a velocidade que trouxe
func entrar_trilho(trilho: Dictionary):
	if gerando or explodindo or em_ritual or em_transicao or segurado or not _trilho.is_empty():
		return
	var pontos: PackedVector3Array = trilho.pontos
	var tangente := (pontos[1] - pontos[0]).normalized()
	var v := linear_velocity.dot(tangente)
	if v < 3.0:
		return
	_trilho = trilho
	var lado := tangente.cross(trilho.cimas[0]).normalized()
	var rel := global_position - pontos[0]
	_trilho_s = clampf(rel.dot(tangente), 0.0, trilho.dist[trilho.dist.size() - 1])
	_trilho_i = 0
	_trilho_desvio = clampf(rel.dot(lado), -1.5, 1.5)
	velocidade = v
	freeze = true

## Anda pelo trilho: a gravidade freia na subida e embala na descida, o acelerador
## ajuda pouco. Se o embalo não segura o carro de cabeça para baixo (v² · curvatura menor
## que a gravidade puxando para fora) ou ele para, desgruda e volta para a física
func _andar_no_trilho(delta: float, acel: float):
	var pontos: PackedVector3Array = _trilho.pontos
	var cimas: PackedVector3Array = _trilho.cimas
	var dist: PackedFloat32Array = _trilho.dist
	var ultimo := pontos.size() - 1
	while _trilho_i < ultimo - 1 and dist[_trilho_i + 1] <= _trilho_s:
		_trilho_i += 1
	var i := _trilho_i
	var f := clampf((_trilho_s - dist[i]) / maxf(dist[i + 1] - dist[i], 0.001), 0.0, 1.0)
	var tangente := (pontos[i + 1] - pontos[i]).normalized()
	var cima := cimas[i].lerp(cimas[i + 1], f).normalized()
	var lado := tangente.cross(cima).normalized()
	cima = lado.cross(tangente)
	# Curvatura local: quanto a tangente gira por metro
	var seguinte := (pontos[mini(i + 2, ultimo)] - pontos[i + 1]).normalized()
	var curvatura := tangente.angle_to(seguinte) / maxf(dist[i + 1] - dist[i], 0.001)

	velocidade -= GRAVIDADE * tangente.y * delta
	if acel > 0.0 and velocidade < velocidade_max:
		velocidade += aceleracao * acel * delta
	elif acel < 0.0:
		velocidade = move_toward(velocidade, 0.0, frenagem * -acel * delta)
	velocidade -= arrasto * 0.5 * delta
	aderencia = 1.0
	if cima.y < 0.0:
		aderencia = clampf(velocidade * velocidade * curvatura / (-cima.y * GRAVIDADE) - 1.0, 0.0, 1.0)
	if velocidade <= 0.5 or (cima.y < -0.1 and velocidade * velocidade * curvatura < -cima.y * GRAVIDADE):
		_sair_do_trilho()
		_avisar("SEM EMBALO!", 1.5)
		return
	_trilho_s += velocidade * delta
	if _trilho_s >= dist[ultimo]:
		_sair_do_trilho()
		return
	_trilho_desvio = move_toward(_trilho_desvio, 0.0, 1.5 * delta)
	var alvo := Basis.looking_at(tangente, cima)
	global_transform = Transform3D(global_basis.slerp(alvo, minf(1.0, 12.0 * delta)).orthonormalized(),
		pontos[i].lerp(pontos[i + 1], f) + lado * _trilho_desvio)
	rodas_no_chao = 3
	direcao = move_toward(direcao, 0.0, resposta_direcao * delta)
	_distancias.fill(curso_suspensao * 0.5 + raio_roda)
	_ultimo_seguro = Transform3D(Basis.looking_at(Vector3(tangente.x, 0.0, tangente.z).normalized() if absf(tangente.y) < 0.9 else Vector3.FORWARD, Vector3.UP), pontos[0])

## Volta para a física com a velocidade do trilho, na direção em que o carro aponta
func _sair_do_trilho():
	if _trilho.is_empty():
		return
	_trilho = {}
	freeze = false
	linear_velocity = -global_basis.z * velocidade
	angular_velocity = Vector3.ZERO

# --- Pista de energia: trilho cinemático ------------------------------------

func _alternar_energia():
	if pista == null or explodindo or em_ritual or em_transicao or segurado or not _trilho.is_empty():
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

## Placa de turbo (loops e salto do abismo): garante `alvo` m/s na direção da placa,
## só para quem passa por ela no sentido certo e rodando no chão. Com `lancar` (topo da
## rampa do salto) a saída é exatamente `alvo` nessa direção, sem giro: o salto é sempre igual
func impulsionar(direcao: Vector3, alvo: float, lancar := false):
	if gerando or explodindo or em_ritual or em_transicao or segurado:
		return
	var atual := linear_velocity.dot(direcao)
	if atual < 2.0:
		return
	if lancar:
		var lado := direcao.cross(Vector3.UP).normalized()
		linear_velocity = direcao * alvo + lado * linear_velocity.dot(lado)
		angular_velocity = Vector3.ZERO
		_avisar("SALTO!", 1.2)
		_vibrar_ambas(0.8, 0.2)
		return
	if atual >= alvo:
		return
	linear_velocity += direcao * (alvo - atual)
	var tw := create_tween()
	tw.tween_property(camera, "fov", _fov + 22.0, 0.1)
	tw.tween_property(camera, "fov", _fov, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_avisar("TURBO!", 0.8)
	_vibrar_ambas(0.6, 0.25)
	dash_usado.emit()

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
	return -global_basis.z * velocidade if gerando or not _trilho.is_empty() else linear_velocity

## Conta o tempo no lobby; na sobrecarga tira barrinhas em passos iguais, da vida que
## o carro tinha ao entrar nela até zero no fim de `tempo_sobrecarga`, e explode
func _sobrecarga_lobby(delta: float):
	if hex_world == null or hex_world is MapaCorrida:
		tempo_no_lobby = 0.0
		return
	tempo_no_lobby += delta
	var t := tempo_no_lobby - tempo_lobby
	if t < 0.0:
		_vida_na_sobrecarga = vida
		return
	if t >= tempo_sobrecarga:
		_explodir()
		return
	var restante := ceili(_vida_na_sobrecarga * (1.0 - t / tempo_sobrecarga))
	if restante < vida:
		var barras := vida - restante
		vida = restante
		dano.emit(barras)
		_avisar("SOBRECARGA!", 0.8)
		_vibrar_ambas(0.6, 0.15)

## Segundos até a sobrecarga explodir o carro (INF fora do lobby ou sem estar dirigindo)
func segundos_para_explodir() -> float:
	if hex_world == null or hex_world is MapaCorrida or explodindo or em_ritual or em_transicao:
		return INF
	return tempo_lobby + tempo_sobrecarga - tempo_no_lobby

func _bater_na_parede(batida: Dictionary):
	var forca := maxf(velocidade, choque_minimo)
	_sair_da_energia(true)
	_avisar("PAREDE DE LUZ!", 2.0)
	_registrar_choque(forca, batida.position, 0.0, &"luz")

# --- VR -----------------------------------------------------------------------

## Remove a zona morta e reescala o resto para continuar indo de 0 a 1
func _analogico(v: float) -> float:
	if absf(v) < zona_morta:
		return 0.0
	return signf(v) * (absf(v) - zona_morta) / (1.0 - zona_morta)

func _vibrar(mao: XRController3D, forca: float, tempo: float):
	if not vibracao:
		return
	if get_viewport().use_xr:
		mao.trigger_haptic_pulse("haptic", 0.0, forca, tempo, 0.0)
	for pad in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, forca, forca, tempo)

# --- Gamepad ------------------------------------------------------------------

## Eixo de maior amplitude entre todos os gamepads conectados (sem zona morta)
func eixo_controle(eixo: JoyAxis) -> float:
	var maior := 0.0
	for pad in Input.get_connected_joypads():
		var v := Input.get_joy_axis(pad, eixo)
		if absf(v) > absf(maior):
			maior = v
	return maior

## Botão apertado em qualquer gamepad conectado
func botao_controle(botao_pad: JoyButton) -> bool:
	for pad in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(pad, botao_pad):
			return true
	return false

func _vibrar_ambas(forca: float, tempo: float):
	_vibrar(mao_esquerda, forca, tempo)
	_vibrar(mao_direita, forca, tempo)

# --- Habilidades e utilidades -----------------------------------------------

func _dash():
	if _recarga > 0.0 or explodindo or em_ritual or em_transicao or segurado:
		return
	_recarga = dash_recarga
	if gerando or not _trilho.is_empty():
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
	raspagem = 0.0
	if em_ritual or em_transicao:
		return
	for i in state.get_contact_count():
		var forca := state.get_contact_impulse(i).length() / mass
		if forca > _choque:
			_choque = forca
			_ponto_choque = state.get_contact_collider_position(i)
			_material_choque = _material_de(state.get_contact_collider_object(i))
		var relativa := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
		var tangencial := relativa.slide(state.get_contact_local_normal(i).normalized()).length()
		if tangencial > raspagem:
			raspagem = tangencial
			_ponto_raspagem = state.get_contact_collider_position(i)

func _atualizar_atrito():
	var ativo := raspagem > 1.8 and not explodindo and not em_ritual and not em_transicao
	_faiscas_atrito.emitting = ativo
	if ativo:
		_faiscas_atrito.global_position = _ponto_raspagem

## Todo choque passa por aqui: toca o som e, se for forte, tira vida e marca o casco.
## `folga` é descontada só do dano (pouso de roda, que a suspensão amortece)
func _registrar_choque(forca: float, ponto: Vector3, folga := 0.0, material := &"chao"):
	impacto.emit(forca, ponto, material)
	var agora := Time.get_ticks_msec() / 1000.0
	if forca >= 3.0 and agora - _ultimo_efeito_impacto >= 0.08 and not explodindo and not em_ritual and not em_transicao:
		_ultimo_efeito_impacto = agora
		_soltar_faiscas_impacto(ponto, forca)
		_efeitos_choque(forca, ponto, material, folga > 0.0)
	var f := forca - folga
	if explodindo or em_ritual or em_transicao or f < choque_minimo:
		return
	# Um choque dura alguns passos de física: conta uma vez só
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

## No mundo neon (não nos mapas de corrida): caiu abaixo do piso ou passou da borda dele
func _fora_do_lobby() -> bool:
	if hex_world == null or hex_world is MapaCorrida:
		return false
	var meio: float = hex_world.world_size * 0.5
	return global_position.y < -12.0 or absf(global_position.x) > meio or absf(global_position.z) > meio

func _soltar_faiscas_impacto(ponto: Vector3, forca: float):
	var rajada := Explosao.faiscas_impacto(forca)
	get_parent().add_child(rajada)
	rajada.global_position = ponto
	rajada.emitting = true
	get_tree().create_timer(1.0).timeout.connect(rajada.queue_free)

## O que o casco atingiu, pelo corpo do contato
func _material_de(corpo: Object) -> StringName:
	if corpo is CarroRival:
		return &"rival"
	if corpo is CollisionObject3D and pista and corpo.collision_layer & pista.camada_colisao:
		return &"luz"
	if corpo is Node and corpo.get_parent() is EstruturasNeon:
		return &"estrutura"
	return &"chao"

## Efeitos de um choque forte além das faíscas: clarão no ponto, tremor da câmera
## (monitor) e, nos pousos, um anel de energia no piso neon ou poeira nos mapas de corrida
func _efeitos_choque(forca: float, ponto: Vector3, material: StringName, pouso: bool):
	if not get_viewport().use_xr:
		_tremor = maxf(_tremor, clampf((forca - 2.0) / 13.0, 0.0, 1.0))
	if forca >= 6.0:
		var cor := Color(0.5, 0.9, 1.0) if material == &"luz" else Color(1.0, 0.7, 0.35)
		Explosao.clarao_impacto(get_parent(), ponto, cor, clampf(forca / 10.0, 0.5, 1.6))
	if pouso and forca >= 3.5:
		if hex_world is MapaCorrida:
			Explosao.poeira(get_parent(), ponto, clampf(forca / 8.0, 0.4, 1.5))
		else:
			Explosao.anel_choque(get_parent(), ponto, Color(0.3, 0.9, 1.0), clampf(forca / 5.0, 0.6, 2.2))

func _explodir():
	if explodindo or em_ritual or em_transicao:
		return
	explodindo = true
	vida = 0
	if gerando:
		_sair_da_energia(false)
	_sair_do_trilho()
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
	_faiscas_atrito.emitting = false

func _desvirar():
	if gerando or explodindo or em_ritual or em_transicao or segurado:
		return
	var f := -global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = global_basis.y.slide(Vector3.UP)
	_reposicionar(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP))

## Leva o carro para outro lugar (troca de mapa): parado, e ali passa a ser o lugar seguro.
## Com `esperar_chao`, fica congelado até existir colisão de chão após a transição.
func teleportar(t: Transform3D, esperar_chao := false):
	_reposicionar(t)
	_ultimo_seguro = t
	if esperar_chao:
		freeze = true
		_esperando_chao = true

## Estado para o telão e a corrida em grupo (Rede manda ao servidor 30x/s): pose,
## velocidade, vida e, na corrida, volta, posição, progresso, os adversários e o
## relógio dos obstáculos
func telemetria() -> Dictionary:
	var dados := {
		"pos": global_position, "rot": global_basis.get_rotation_quaternion(),
		"vel": absf(velocidade) * 3.6, "vida": vida, "vida_max": VIDA_MAX,
		"explodindo": explodindo, "na_esfera": em_ritual, "energia": gerando, "mapa": "",
	}
	var falta := segundos_para_explodir()
	if falta <= tempo_sobrecarga:
		dados.sobrecarga = falta
	if hex_world is MapaCorrida and hex_world.corrida:
		var mapa: MapaCorrida = hex_world
		dados.mapa = mapa.nome
		dados.volta = mapa.corrida.volta
		dados.voltas = Corrida.VOLTAS
		dados.posicao = mapa.corrida.posicao
		dados.total = mapa.corrida.total_carros()
		dados.progresso = mapa.trafego.jogador.progresso
		dados.chegou = mapa.corrida.fase == Corrida.Fase.CHEGADA
		# [número, posição, rotação, progresso, velocidade] dos adversários da corrida: o
		# telão mostra; numa corrida em grupo, os outros Quests seguem os do anfitrião
		var rivais := []
		for rival in mapa.corrida.rivais:
			rivais.append([rival.numero, rival.global_position, rival.global_basis.get_rotation_quaternion(), rival.progresso, rival.v])
		dados.rivais = rivais
		if mapa is ValeTurbinas and mapa.obstaculos:
			dados.relogio = mapa.obstaculos.tempo
	return dados

func atualizar_ambiente_traseira():
	_ambiente_traseira()

func _reposicionar(t: Transform3D):
	if gerando:
		_sair_da_energia(false)
	_sair_do_trilho()
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

	var km_h := 0 if explodindo else roundi((velocidade if gerando or not _trilho.is_empty() else linear_velocity.length()) * 3.6)
	# Barras de energia: cheias, a que está enchendo/acabando (▒ a partir de 1/3) e vazias
	var cheias := floori(energia)
	var meia := 1 if energia - cheias >= 0.34 and cheias < energia_max else 0
	var estado := "%s %s" % ["VOO " if gerando else "ENER", "█".repeat(cheias) + "▒".repeat(meia) + "·".repeat(energia_max - cheias - meia)]
	# Ameaça: lobby acabando (10 s antes da sobrecarga) e a sobrecarga em si
	var ameaca := ""
	var falta := segundos_para_explodir()
	if falta <= tempo_sobrecarga:
		ameaca = "SOBRECARGA %ds" % ceili(falta)
	elif falta <= tempo_sobrecarga + 10.0:
		ameaca = "PORTAL EM %ds" % ceili(falta - tempo_sobrecarga)
	if _aviso_tempo > 0.0:
		estado = _aviso
	elif ameaca != "":
		estado = ameaca
	elif _puxao_hud > 0.8:
		estado = "PORTAL"
	if explodindo:
		estado = "DESTRUÍDO"
	var linha_dash := "DASH OK" if _recarga <= 0.0 else "DASH %.1fs" % _recarga
	# FPS real (média do último segundo): no Quest deve ficar colado na taxa da tela
	linha_dash += "  %3d FPS" % roundi(Engine.get_frames_per_second())
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
	segurado = false
	if gerando:
		_sair_da_energia(false)
	freeze = true
	_esperando_chao = false
	_reposicionar(t)
	vida = VIDA_MAX
	# Primeira vida da sessão: energia cheia para já experimentar o voo
	energia = float(energia_max) if _primeira_vida else 0.0
	_primeira_vida = false
	velocidade = 0.0
	direcao = 0.0
	comando_acel = 0.0
	freio = 0.0
	derrapagem = 0.0
	raspagem = 0.0
	carregando = false
	drift = false
	_puxao = Vector3.ZERO
	_puxao_hud = 0.0
	_choque = 0.0
	_ultimo_dano = -10.0
	_ultimo_efeito_impacto = -10.0
	_ultimo_w = -10.0
	_ultimo_gatilho = -10.0
	_recarga = 0.0
	_energia_visual = 0.0
	_brilho_carga = 0.0
	_aviso_tempo = 0.0
	tempo_no_lobby = 0.0
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
## Toda troca de mapa (ida para a corrida ou volta) zera a contagem do lobby.
func iniciar_transicao():
	if gerando:
		_sair_da_energia(false)
	_sair_do_trilho()
	tempo_no_lobby = 0.0
	em_transicao = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	comando_acel = 0.0
	_puxao = Vector3.ZERO
	_choque = 0.0
	raspagem = 0.0
	_faiscas_atrito.emitting = false

func terminar_transicao():
	em_transicao = false
	freeze = em_ritual or explodindo or _esperando_chao or segurado

## Prende o carro no grid até a largada (a física para, o motor e o visor não)
func segurar():
	if gerando:
		_sair_da_energia(false)
	_sair_do_trilho()
	segurado = true
	raspagem = 0.0
	_faiscas_atrito.emitting = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	velocidade = 0.0

## Solta na largada, sem impulso: quem acelerar sai
func soltar():
	segurado = false
	freeze = em_ritual or em_transicao or explodindo or _esperando_chao
	sleeping = false
