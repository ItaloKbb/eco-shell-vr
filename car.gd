extends RigidBody3D
## Protótipo Eco Shell (3 rodas, piloto deitado sob a bolha), dirigido em primeira pessoa.
##
## No chão é um corpo rígido simulado pelo Jolt: cada roda é um raio com mola,
## amortecedor e atrito de pneu limitado pela carga, então o carro derrapa, capota,
## cai em buracos e roda sobre as pistas de energia já criadas.
## W/S acelera/freia/ré, A/D esterça, Espaço é o freio de mão (solta a traseira).
##
## E liga a pista de energia: o carro vira cinemático e anda "no trilho" que ele mesmo
## gera, como numa montanha-russa. Espaço levanta o nariz, Shift abaixa (o ângulo fica
## onde parou), A/D fazem curvas inclinando o carro aos poucos. Se o embalo não segurar
## o carro (lento de cabeça para baixo ou numa subida íngreme), ele desgruda e cai.
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

const GRAVIDADE := 9.8
const CENTRO_ESFERA := Vector3(0, 1.5, 0)
const FOLGA_RODA := 0.35

@export var hex_world: Node3D
@export var pista: Node3D
@export var sensibilidade := 0.003
## Camadas que as rodas enxergam como chão (terreno + pistas)
@export_flags_3d_physics var mascara_chao := 3

@export_group("Chão")
@export var aceleracao := 4.0
@export var frenagem := 10.0
## Baixo de propósito: o carro de eficiência roda solto quando se tira o pé
@export var arrasto := 0.6
@export var velocidade_max := 12.0
@export var velocidade_re := 3.0
@export var direcao_max := 0.3
@export var raio_roda := 0.245

@export_group("Suspensão e pneus")
@export var curso_suspensao := 0.15
@export var rigidez := 7800.0
@export var amortecimento := 900.0
## Coeficiente de atrito: força máxima do pneu = atrito × carga na roda
@export var atrito_pneu := 1.1
## Quão rápido o pneu anula o escorregamento lateral (1/s)
@export var aderencia_lateral := 10.0

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

@export_group("VR")
@export_range(0.0, 0.5) var zona_morta := 0.15
## Distância da mão até a manopla para conseguir agarrar o guidão (m)
@export var alcance_guidao := 0.2
## Ângulo do guidão (rad) que corresponde ao esterço máximo
@export var giro_guidao_max := 0.6
@export var vibracao := true

@onready var camera: Camera3D = $Cabeca
@onready var camera_xr: XRCamera3D = $OrigemXR/CameraXR
@onready var mao_esquerda: XRController3D = $OrigemXR/MaoEsquerda
@onready var mao_direita: XRController3D = $OrigemXR/MaoDireita
@onready var manoplas: Array[Node3D] = [$Guidao/ManoplaE, $Guidao/ManoplaD]
@onready var rodas: Array[Node3D] = [$RodaFE, $RodaFD, $RodaT]
@onready var giros_rodas: Array[Node3D] = [$RodaFE/Giro, $RodaFD/Giro, $RodaT/Giro]
@onready var guidao: Node3D = $Guidao
@onready var info_esquerda: Label3D = $Painel/InfoE
@onready var info_direita: Label3D = $Painel/InfoD
@onready var horizonte: ShaderMaterial = $Painel/Horizonte.material_override

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

var _ancoras: Array[Vector3] = []
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
var _esperando_chao := false
## Mãos segurando o guidão: [esquerda, direita]
var _segurando := [false, false]

func _ready():
	# Colisão com o mesmo formato do casco (envoltória convexa da malha gerada)
	$Forma.shape = $Casco.mesh.create_convex_shape(true, true)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	for r in rodas:
		_ancoras.append(r.position + Vector3.UP * 0.1)
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

## O carro recebe comandos quando a câmera dele está ativa ou quando está em VR
func _ativo() -> bool:
	return camera.current or get_viewport().use_xr

func recentralizar():
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)

func _input(event):
	if not _ativo():
		return
	if event is InputEventKey and event.pressed and not event.echo:
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
	match nome:
		"by_button": _desvirar()
		"primary_click", "menu_button": recentralizar()

func _botao_direito(nome: String):
	match nome:
		"ax_button": _alternar_energia()
		"by_button": _dash()
		"trigger_click": _ultimo_gatilho = _toque_duplo(_ultimo_gatilho)

func _physics_process(delta):
	if _esperando_chao:
		var consulta := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 2.0, global_position + Vector3.DOWN * 5.0, mascara_chao, [get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(consulta):
			return
		_esperando_chao = false
		freeze = false
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
	_recarga = max(_recarga - delta, 0.0)
	_aviso_tempo -= delta

	if gerando:
		_andar_na_energia(delta, acel, vira, sobe)
	else:
		_andar_com_fisica(delta, acel, vira, freio_mao)
	# Caiu no vazio (buraco ou fora do mapa): volta ao último lugar seguro
	if global_position.y < -30.0:
		_reposicionar(_ultimo_seguro)
		_avisar("REPOSICIONADO", 1.5)
	_animar(delta)
	_atualizar_painel()

# --- Chão: corpo rígido com suspensão por raio ------------------------------

func _andar_com_fisica(delta: float, acel: float, vira: float, freio_mao: bool):
	var cima := global_basis.y
	var frente := -global_basis.z
	velocidade = linear_velocity.dot(frente)
	var rapidez: float = clamp(abs(velocidade) / velocidade_max, 0.0, 1.0)
	direcao = move_toward(direcao, vira * direcao_max * lerp(1.0, 0.35, rapidez), 2.5 * delta)

	var espaco_fisico := get_world_3d().direct_space_state
	var alcance := curso_suspensao + raio_roda
	var parte := mass / 3.0
	rodas_no_chao = 0
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
			continue
		rodas_no_chao += 1
		_distancias[i] = max((curso_suspensao + FOLGA_RODA) * fracao[0] - FOLGA_RODA, 0.0) + raio_roda
		var ponto := ancora - cima * _distancias[i]
		var braco := ponto - global_position
		var vel_ponto := linear_velocity + angular_velocity.cross(braco)

		# Mola + amortecedor ao longo do eixo do carro
		var carga: float = max(0.0, rigidez * (alcance - _distancias[i]) - amortecimento * vel_ponto.dot(cima))

		# Pneu: direção da roda (as dianteiras esterçam) e escorregamentos
		var frente_roda := frente.rotated(cima, direcao) if i < 2 else frente
		var lado_roda := frente_roda.cross(cima)
		var v_long := vel_ponto.dot(frente_roda)
		var v_lat := vel_ponto.dot(lado_roda)
		var traseira := i == 2

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
	if pista == null:
		return
	if gerando:
		_sair_da_energia(false)
	else:
		_entrar_na_energia()

func _entrar_na_energia():
	var e := global_basis.get_euler()
	inclinacao = e.x
	rumo = e.y
	giro = e.z
	velocidade = max(linear_velocity.dot(-global_basis.z), 0.0)
	freeze = true
	gerando = true
	pista.comecar(global_transform)
	_vibrar_ambas(0.3, 0.1)

func _sair_da_energia(caiu: bool):
	gerando = false
	pista.terminar(global_transform)
	freeze = false
	linear_velocity = -global_basis.z * velocidade
	angular_velocity = Vector3.ZERO
	if caiu:
		# Desgrudou: sai rodopiando um pouco
		angular_velocity = global_basis.z * randf_range(-1.5, 1.5) + global_basis.x * randf_range(-0.6, 0.6)
		_avisar("SEM ADERÊNCIA!", 2.0)
		_vibrar_ambas(1.0, 0.4)

func _andar_na_energia(delta: float, acel: float, vira: float, sobe: float):
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
	# A pista não atravessa o chão: encosta e vai nivelando o nariz
	var h := _altura_terreno(pos)
	if pos.y < h:
		pos.y = h
		if inclinacao < 0.0 and not invertido:
			inclinacao = lerp(inclinacao, 0.0, min(1.0, 8.0 * delta))
	global_transform = Transform3D(b, pos)
	pista.adicionar(global_transform)

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
	if _recarga > 0.0:
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

func _desvirar():
	if gerando:
		return
	var f := -global_basis.z
	f.y = 0.0
	if f.length() < 0.1:
		f = global_basis.y.slide(Vector3.UP)
	_reposicionar(Transform3D(Basis.looking_at(f.normalized(), Vector3.UP), global_position + Vector3.UP))

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
	for i in 3:
		giros_rodas[i].rotation.x -= velocidade / raio_roda * delta
		# Roda acompanha a suspensão (no trilho fica na posição de repouso)
		var descida := 0.1 if gerando else _distancias[i] - raio_roda
		rodas[i].position.y = _ancoras[i].y - descida
	rodas[0].rotation.y = direcao
	rodas[1].rotation.y = direcao
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
	var linha_ader := "ADER %3d%%" % roundi(aderencia * 100.0) if gerando else "RODAS %d/3" % rodas_no_chao
	info_esquerda.text = "INCL %+4d°\nGIRO %+4d°\nRUMO  %03d°\n%s" % [
		roundi(rad_to_deg(incl)), roundi(rad_to_deg(gir)), roundi(fposmod(-rad_to_deg(rum), 360.0)), linha_ader]
	info_esquerda.modulate = Color(1.0, 0.3, 0.25) if gerando and aderencia < 0.25 else Color(0.55, 0.85, 1.0)

	var km_h := roundi((velocidade if gerando else linear_velocity.length()) * 3.6)
	var estado := "ENERGIA ON" if gerando else "[E] ENERGIA"
	if _aviso_tempo > 0.0:
		estado = _aviso
	var linha_dash := "DASH OK" if _recarga <= 0.0 else "DASH %.1fs" % _recarga
	info_direita.text = "%d km/h\nALT %.1f m\n%s\n%s" % [
		km_h, global_position.y - _altura_terreno(global_position), estado, linha_dash]
	if _aviso_tempo > 0.0:
		info_direita.modulate = Color(1.0, 0.3, 0.25)
	else:
		info_direita.modulate = Color(0.96, 0.62, 0.2) if gerando else Color(0.55, 0.85, 1.0)

	# Horizonte artificial: de cabeça para baixo mostra a mesma atitude sem passar de ±90°
	if cos(incl) < 0.0:
		incl = wrapf(PI - incl, -PI, PI)
		gir += PI
	horizonte.set_shader_parameter("inclinacao", incl)
	horizonte.set_shader_parameter("giro", gir)
