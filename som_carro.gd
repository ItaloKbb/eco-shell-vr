extends Node3D
## Som do carro: lê o estado do car.gd a cada frame e comanda o motor sintetizado
## (som_motor.gd), as camadas em loop e os efeitos pontuais (som_gerador.gd).
## Cada fonte fica onde está no carro real: motor e escapamento atrás do piloto, freios
## nas rodas da frente, vento na bolha. Em VR o som vem do lugar certo da cabeça.
##
## O que muda o som:
## - acelerador e subida (esforço): carga do motor, aspereza, admissão
## - velocidade: rotação pelo variador, limitador, vento, rolamento, assobio elétrico
## - frenagem e freio de mão: atrito do disco e guincho
## - escorregamento dos pneus: pneu cantando
## - pousos, degraus e batidas: baques no casco
## - energia ligada/desligada/caiu, pouca aderência, dash: efeitos elétricos e estouros
## - dano: vidro trincando; explosão: estrondo e o motor apaga até o carro renascer

const BARRAMENTO := "Carro"
## Relação final: rotação do motor por m/s quando a embreagem está engatada
const RPM_POR_MS := 690.0

@onready var carro: RigidBody3D = get_parent()

var motor: SomMotor
var _loops := {}
var _efeitos := {}
var _volumes := {}
var _tarefa := -1
var _sons := {}
var _energia := 0.0
var _rpm_dash := 0.0
## Alarme de míssil na cabine: "pi" cada vez mais rápido e o "piiii" contínuo
var _bip: AudioStreamPlayer
var _bip_continuo: AudioStreamPlayer
var _proximo_bip := 0.0

func _ready():
	_criar_barramento()
	motor = SomMotor.new()
	motor.position = Vector3(0.0, 0.35, 0.85)
	_configurar(motor)
	add_child(motor)
	carro.largou.connect(motor.ligar)
	carro.dash_usado.connect(_dash)
	carro.energia_mudou.connect(_energia_mudou)
	carro.impacto.connect(_impacto)
	carro.botao_apertado.connect(func(ponto: Vector3): _efeito("clique", 0.5, 1.0, to_local(ponto)))
	carro.dano.connect(func(_barras: int): _efeito("trinca", 0.45, randf_range(0.9, 1.1)))
	carro.explodiu.connect(_explodiu)
	# Barra de energia cheia: bip agudo com faísca; sem energia para voar: bip grave
	carro.energia_carregada.connect(func(_barras: int):
		_efeito("clique", 0.45, 1.6)
		_efeito("faisca", 0.2, 1.4))
	carro.sem_energia.connect(func(): _efeito("clique", 0.45, 0.55))
	carro.renasceu.connect(motor.ligar)
	# Gerar os loops e efeitos leva alguns décimos de segundo: fora da thread principal
	_tarefa = WorkerThreadPool.add_task(func(): _sons = SomGerador.new().gerar())

func _criar_barramento():
	if AudioServer.get_bus_index(BARRAMENTO) >= 0:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, BARRAMENTO)
	AudioServer.set_bus_send(i, "Master")
	# Cola as camadas, dá o "corpo" de estar dentro do casco e nunca estoura
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -18.0
	compressor.ratio = 2.5
	compressor.attack_us = 3000.0
	compressor.release_ms = 150.0
	AudioServer.add_bus_effect(i, compressor)
	# Arredonda o agudo: som macio, de veículo elétrico/futurista
	var macio := AudioEffectLowPassFilter.new()
	macio.cutoff_hz = 7000.0
	AudioServer.add_bus_effect(i, macio)
	var cabine := AudioEffectReverb.new()
	cabine.room_size = 0.12
	cabine.damping = 0.7
	cabine.spread = 0.6
	cabine.hipass = 0.2
	cabine.wet = 0.07
	cabine.dry = 1.0
	AudioServer.add_bus_effect(i, cabine)
	var limitador := AudioEffectHardLimiter.new()
	limitador.ceiling_db = -0.5
	AudioServer.add_bus_effect(i, limitador)

func _configurar(p: AudioStreamPlayer3D):
	p.bus = BARRAMENTO
	p.unit_size = 3.0
	p.attenuation_filter_db = 0.0
	p.panning_strength = 0.6
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED

func _fonte(nome: String, onde: Vector3, vozes: int) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _sons[nome]
	p.position = onde
	p.max_polyphony = vozes
	_configurar(p)
	add_child(p)
	return p

func _montar():
	var lugares := {
		"vento": Vector3(0.0, 0.85, -0.3),
		"rolamento": Vector3(0.0, 0.15, 0.0),
		"chiado": Vector3(0.0, 0.15, 0.2),
		"freio": Vector3(0.0, 0.25, -0.75),
		"zumbido": Vector3(0.0, 0.1, 0.3),
		"assobio": Vector3(0.0, 0.2, 0.6),
	}
	for nome in lugares:
		var p := _fonte(nome, lugares[nome], 1)
		p.volume_db = -80.0
		p.play()
		_loops[nome] = p
		_volumes[nome] = 0.0
	for nome in ["arrancada", "impacto", "batida", "carga", "descarga", "faisca", "clique", "trinca"]:
		_efeitos[nome] = _fonte(nome, Vector3(0.0, 0.3, 0.2), 4)
	_efeitos["arrancada"].position = Vector3(0.0, 0.4, 0.9)
	# Alarme sai do painel, sem posição 3D: é o sistema do carro avisando o piloto
	_bip = AudioStreamPlayer.new()
	_bip.stream = _sons["bip"]
	_bip.bus = BARRAMENTO
	_bip.volume_db = -6.0
	_bip.max_polyphony = 2
	add_child(_bip)
	_bip_continuo = AudioStreamPlayer.new()
	_bip_continuo.stream = _sons["bip_continuo"]
	_bip_continuo.bus = BARRAMENTO
	_bip_continuo.volume_db = -8.0
	add_child(_bip_continuo)

func _process(delta: float):
	if _tarefa >= 0 and WorkerThreadPool.is_task_completed(_tarefa):
		WorkerThreadPool.wait_for_task_completion(_tarefa)
		_tarefa = -1
		SomGerador.biblioteca = _sons
		_montar()

	var gerando: bool = carro.gerando
	var frente: float = carro.velocidade
	var v: float = 0.0 if carro.explodindo else (frente if gerando else carro.linear_velocity.length())
	var acel: float = carro.comando_acel
	var no_chao: bool = not gerando and not carro.explodindo and carro.rodas_no_chao > 0
	_energia = move_toward(_energia, 1.0 if gerando else 0.0, 2.5 * delta)

	# Motor: acelerador (também na ré), rotação imposta pela roda e esforço da subida
	var re := acel < 0.0 and frente < 0.5 and not gerando
	motor.acelerador = -acel * 0.7 if re else maxf(acel, 0.0)
	_rpm_dash = move_toward(_rpm_dash, 0.0, 2500.0 * delta)
	motor.rpm_roda = absf(frente) * RPM_POR_MS + _rpm_dash
	motor.livre = not gerando and carro.rodas_no_chao == 0
	motor.esforco = clampf(sin(carro.inclinacao) * 1.5, 0.0, 1.0) if gerando else 0.0

	if _loops.is_empty():
		return
	_alarme_missil(delta)
	var rapidez := clampf(v / 18.0, 0.0, 1.5)
	var derrapa := smoothstep(1.2, 4.0, carro.derrapagem) * clampf(v / 3.0, 0.0, 1.0)
	_tocar("vento", pow(clampf(v / 22.0, 0.0, 1.0), 2.0) * 0.8, 0.75 + v / 35.0, delta)
	_tocar("rolamento", (pow(clampf(v / 10.0, 0.0, 1.0), 0.8) * 0.4 if no_chao else 0.0), 0.6 + v / 16.0, delta)
	_tocar("chiado", derrapa * 0.35 if no_chao else 0.0, 0.85 + clampf(carro.derrapagem / 12.0, 0.0, 1.0) * 0.35, delta)
	_tocar("freio", (carro.freio * clampf(v / 5.0, 0.0, 1.0) * 0.3 if no_chao else 0.0), 0.8 + v / 30.0, delta)
	# Elétrico ao fundo: zumbido do gerador e assobio do motor elétrico pela velocidade;
	# frear na pista (regeneração) derruba o tom e deixa o assobio mais alto
	var regenera := maxf(-acel, 0.0) if gerando else 0.0
	_tocar("zumbido", _energia * (0.22 + 0.3 * minf(rapidez, 1.0)), 1.0 + 0.04 * rapidez, delta)
	# Derrapando e carregando: o assobio elétrico aparece no chão e sobe com a energia
	var carga := 1.0 if carro.carregando else 0.0
	_tocar("assobio", _energia * (0.1 + 0.35 * minf(rapidez, 1.0) + 0.15 * maxf(acel, 0.0) + 0.2 * regenera) + carga * 0.3,
		lerpf(0.55 + rapidez * 1.3 - regenera * 0.15, 0.7 + carro.energia / carro.energia_max * 1.2, carga), delta)

	# Pouca aderência na pista: arcos elétricos cada vez mais frequentes
	if gerando and carro.aderencia < 0.4 and randf() < (0.4 - carro.aderencia) / 0.4 * 7.0 * delta:
		_efeito("faisca", 0.1 + 0.25 * (1.0 - carro.aderencia), randf_range(0.8, 1.3))

## Volume (0 a 1) e pitch de uma camada, com ataque rápido e soltura mais lenta
func _tocar(nome: String, alvo: float, pitch: float, delta: float):
	var atual: float = _volumes[nome]
	atual = move_toward(atual, alvo, (6.0 if alvo > atual else 3.0) * delta)
	_volumes[nome] = atual
	var p: AudioStreamPlayer3D = _loops[nome]
	p.volume_db = linear_to_db(maxf(atual, 0.0001))
	p.pitch_scale = maxf(pitch, 0.05)

func _efeito(nome: String, volume: float, pitch := 1.0, onde = null):
	if not _efeitos.has(nome):
		return
	var p: AudioStreamPlayer3D = _efeitos[nome]
	if onde != null:
		p.position = onde
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = pitch
	p.play()

func _explodiu():
	# O estrondo vem da própria explosão (explosao.gd), no lugar dela
	motor.desligar()

## Bipes de travamento: com a pirâmide mirando, "pi... pi..."; com míssil no ar, o
## intervalo encolhe com o tempo que falta para acertar até virar o "piiii" contínuo
func _alarme_missil(delta: float):
	var falta := INF
	for missil in get_tree().get_nodes_in_group("misseis"):
		falta = minf(falta, missil.tempo_para_impacto())
	var mirando := false
	for piramide in get_tree().get_nodes_in_group("piramides"):
		mirando = mirando or (piramide.travando and piramide.alvo == carro)
	var continuo := falta < 0.6
	if continuo != _bip_continuo.playing:
		if continuo:
			_bip_continuo.play()
		else:
			_bip_continuo.stop()
	_proximo_bip -= delta
	if continuo or _proximo_bip > 0.0:
		return
	if falta < INF:
		_bip.play()
		_proximo_bip = clampf(falta * 0.2, 0.07, 0.6)
	elif mirando:
		_bip.play()
		_proximo_bip = 0.45

func _dash():
	_rpm_dash = 2500.0
	motor.arrancada()
	_efeito("arrancada", 0.7, randf_range(0.95, 1.05))
	if carro.gerando:
		_efeito("faisca", 0.35, 1.3)

func _energia_mudou(ligada: bool, caiu: bool):
	if ligada:
		_efeito("carga", 0.6)
	else:
		_efeito("descarga", 0.5)
	if caiu:
		_efeito("faisca", 0.5, 0.8)

func _impacto(forca: float, ponto: Vector3):
	var onde := to_local(ponto)
	if forca > 3.5:
		_efeito("batida", clampf(forca / 12.0, 0.25, 0.7), randf_range(0.85, 1.1), onde)
	else:
		_efeito("impacto", clampf((forca - 0.6) / 4.0, 0.05, 0.6), randf_range(0.85, 1.15), onde)
