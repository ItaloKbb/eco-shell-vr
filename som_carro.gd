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
## - pousos, degraus e batidas: baques no casco em camadas (estalo, corpo sub-grave, o
##   material atingido: clangor de carro, zap de parede de luz) e, com dano, o casco
##   amassando e pedacinhos caindo; pancada de 2+ barras abafa tudo e zune o ouvido
## - nitro: ronco de V12 ao ligar, zumbido elétrico enquanto ligado; placa de turbo: estouro
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
var _rpm_turbo := 0.0
## Alarme da sobrecarga do lobby na cabine: "pi" cada vez mais rápido e o "piiii" contínuo
var _bip: AudioStreamPlayer
var _bip_continuo: AudioStreamPlayer
var _proximo_bip := 0.0
## Zumbido no ouvido da concussão (fora dos barramentos abafados, "dentro da cabeça")
var _zumbido_ouvido: AudioStreamPlayer
var _abafando: Tween
var _ponto_impacto := Vector3.ZERO

func _ready():
	_criar_barramento()
	motor = SomMotor.new()
	motor.position = Vector3(0.0, 0.35, 0.85)
	_configurar(motor)
	add_child(motor)
	carro.largou.connect(motor.ligar)
	carro.turbo_placa.connect(_turbo_placa)
	carro.nitro_mudou.connect(_nitro_mudou)
	carro.impacto.connect(_impacto)
	carro.botao_apertado.connect(func(ponto: Vector3): _efeito("clique", 0.5, 1.0, to_local(ponto)))
	carro.dano.connect(_dano)
	carro.explodiu.connect(_explodiu)
	# Pegou nitro: bip agudo com faísca; sem nitro (ou portal fechado): bip grave
	carro.nitro_coletado.connect(func(_barras: int):
		_efeito("clique", 0.45, 1.6)
		_efeito("faisca", 0.2, 1.4)
		_efeito("carga", 0.35, 1.3))
	carro.sem_nitro.connect(func(): _efeito("clique", 0.45, 0.55))
	carro.renasceu.connect(motor.ligar)
	# Gerar os loops e efeitos leva alguns décimos de segundo: fora da thread principal
	_tarefa = WorkerThreadPool.add_task(func(): _sons = SomGerador.new().gerar())

func _criar_barramento():
	SomGerador.garantir_barramento_mundo()
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
		"raspagem": Vector3(0.0, 0.15, 0.0),
		"zumbido": Vector3(0.0, 0.1, 0.3),
		"assobio": Vector3(0.0, 0.2, 0.6),
	}
	for nome in lugares:
		var p := _fonte(nome, lugares[nome], 1)
		p.volume_db = -80.0
		p.play()
		_loops[nome] = p
		_volumes[nome] = 0.0
	for nome in ["arrancada", "nitro", "impacto", "batida", "carga", "descarga", "faisca", "clique", "trinca",
			"corpo", "amassado", "detritos", "clang", "zap"]:
		_efeitos[nome] = _fonte(nome, Vector3(0.0, 0.3, 0.2), 4)
	_efeitos["arrancada"].position = Vector3(0.0, 0.4, 0.9)
	# O ronco sai do escapamento, atrás do piloto
	_efeitos["nitro"].position = Vector3(0.0, 0.35, 1.2)
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
	_zumbido_ouvido = AudioStreamPlayer.new()
	_zumbido_ouvido.stream = _sons["zumbido_ouvido"]
	_zumbido_ouvido.bus = "Master"
	add_child(_zumbido_ouvido)

func _process(delta: float):
	if _tarefa >= 0 and WorkerThreadPool.is_task_completed(_tarefa):
		WorkerThreadPool.wait_for_task_completion(_tarefa)
		_tarefa = -1
		SomGerador.biblioteca = _sons
		_montar()

	var nitro: bool = carro.nitro_ativo
	var frente: float = carro.velocidade
	var v: float = 0.0 if carro.explodindo else carro.linear_velocity.length()
	var acel: float = carro.comando_acel
	var no_chao: bool = not carro.explodindo and carro.rodas_no_chao > 0
	_energia = move_toward(_energia, 1.0 if nitro else 0.0, 2.5 * delta)

	# Motor: acelerador (também na ré) e rotação imposta pela roda; o nitro força o motor
	var re := acel < 0.0 and frente < 0.5
	motor.acelerador = -acel * 0.7 if re else maxf(acel, 0.0)
	_rpm_turbo = move_toward(_rpm_turbo, 0.0, 2500.0 * delta)
	# O motor tem o dobro da velocidade para cobrir: a relação final cai à metade
	motor.rpm_roda = absf(frente) * RPM_POR_MS * 0.5 + _rpm_turbo
	motor.livre = carro.rodas_no_chao == 0
	motor.esforco = 0.6 * _energia * maxf(acel, 0.0)

	if _loops.is_empty():
		return
	_alarme_sobrecarga(delta)
	var rapidez := clampf(v / 36.0, 0.0, 1.5)
	var derrapa := smoothstep(1.2, 4.0, carro.derrapagem) * clampf(v / 3.0, 0.0, 1.0)
	_tocar("vento", pow(clampf(v / 44.0, 0.0, 1.0), 2.0) * 0.8, 0.75 + minf(v, 90.0) / 70.0, delta)
	_tocar("rolamento", (pow(clampf(v / 20.0, 0.0, 1.0), 0.8) * 0.4 if no_chao else 0.0), 0.6 + minf(v, 90.0) / 32.0, delta)
	_tocar("chiado", derrapa * 0.35 if no_chao else 0.0, 0.85 + clampf(carro.derrapagem / 12.0, 0.0, 1.0) * 0.35, delta)
	_tocar("freio", (carro.freio * clampf(v / 5.0, 0.0, 1.0) * 0.3 if no_chao else 0.0), 0.8 + v / 30.0, delta)
	var pode_raspar: bool = not carro.explodindo and not carro.em_ritual and not carro.em_transicao and not carro.segurado
	var raspa := smoothstep(1.5, 8.0, carro.raspagem) if pode_raspar else 0.0
	_tocar("raspagem", raspa * 0.65, 0.75 + minf(carro.raspagem / 14.0, 0.7), delta)
	# Nitro ligado: zumbido elétrico e o assobio subindo com a velocidade, por baixo do motor
	_tocar("zumbido", _energia * (0.22 + 0.3 * minf(rapidez, 1.0)), 1.0 + 0.04 * rapidez, delta)
	_tocar("assobio", _energia * (0.1 + 0.35 * minf(rapidez, 1.0) + 0.15 * maxf(acel, 0.0)),
		0.55 + rapidez * 1.3, delta)

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

## Bipes da sobrecarga do lobby: um "pi" por segundo nos 10 s de aviso antes dela; na
## sobrecarga o intervalo encolhe com o tempo que falta até virar o "piiii" contínuo
func _alarme_sobrecarga(delta: float):
	var falta: float = carro.segundos_para_explodir()
	var sobrecarga: float = carro.tempo_sobrecarga
	var continuo := falta < 1.0
	if continuo != _bip_continuo.playing:
		if continuo:
			_bip_continuo.play()
		else:
			_bip_continuo.stop()
	_proximo_bip -= delta
	if continuo or _proximo_bip > 0.0:
		return
	if falta <= sobrecarga:
		_bip.play()
		_proximo_bip = clampf(falta / sobrecarga * 0.7, 0.1, 0.7)
	elif falta <= sobrecarga + 10.0:
		_bip.play()
		_proximo_bip = 1.0

func _turbo_placa():
	_rpm_turbo = 2500.0
	motor.arrancada()
	_efeito("arrancada", 0.7, randf_range(0.95, 1.05))
	if carro.nitro_ativo:
		_efeito("faisca", 0.35, 1.3)

func _nitro_mudou(ligado: bool):
	if ligado:
		_efeito("nitro", 0.9, randf_range(0.97, 1.03))
		_efeito("carga", 0.4)
		motor.arrancada()
	else:
		_efeito("descarga", 0.4)

func _impacto(forca: float, ponto: Vector3, material: StringName):
	var onde := to_local(ponto)
	_ponto_impacto = onde
	# Material atingido, por cima do baque
	match material:
		&"rival":
			_efeito("clang", clampf(forca / 8.0, 0.2, 0.8), randf_range(0.85, 1.15), onde)
		&"luz":
			_efeito("zap", clampf(forca / 10.0, 0.35, 0.8), randf_range(0.9, 1.1), onde)
	# Peso: o sub-grave entra a partir de um choque médio
	if forca > 6.0:
		_efeito("corpo", clampf((forca - 6.0) / 9.0, 0.3, 1.0), randf_range(0.9, 1.05), onde)
	if forca > 3.5:
		_efeito("batida", clampf(forca / 12.0, 0.25, 0.7), randf_range(0.85, 1.1), onde)
		_efeito("faisca", clampf((forca - 3.5) / 16.0, 0.08, 0.32), randf_range(0.75, 1.25), onde)
	else:
		_efeito("impacto", clampf((forca - 0.6) / 4.0, 0.05, 0.6), randf_range(0.85, 1.15), onde)

## Dano: o casco amassa (mais forte quanto mais barras), o vidro trinca e pedacinhos
## caem logo depois. Duas barras ou mais: concussão
func _dano(barras: int):
	var onde := _ponto_impacto
	_efeito("trinca", 0.45, randf_range(0.9, 1.1))
	_efeito("amassado", clampf(0.35 + 0.2 * barras, 0.35, 0.9), randf_range(0.85, 1.1), onde)
	get_tree().create_timer(0.12).timeout.connect(func():
		_efeito("detritos", 0.25 + 0.1 * barras, randf_range(0.9, 1.2), onde))
	if barras >= 2:
		_concussao(0.6 + 0.2 * barras)

## Pancada forte: cabine e mundo abafam de repente e voltam aos poucos, com um zumbido
## fino no ouvido. A música e a voz da Yui não abafam (não estão "no ar" do carro)
func _concussao(intensidade: float):
	var corte := lerpf(2200.0, 500.0, clampf(intensidade - 0.6, 0.0, 1.0))
	var filtros: Array[AudioEffectLowPassFilter] = []
	var normais: Array[float] = []
	for nome in [BARRAMENTO, SomGerador.BARRAMENTO_MUNDO]:
		var bus := AudioServer.get_bus_index(nome)
		for i in AudioServer.get_bus_effect_count(bus):
			var efeito := AudioServer.get_bus_effect(bus, i)
			if efeito is AudioEffectLowPassFilter:
				filtros.append(efeito)
				normais.append(7000.0 if nome == BARRAMENTO else 20000.0)
				break
	if _abafando and _abafando.is_valid():
		_abafando.kill()
	var abrir := func(k: float):
		for i in filtros.size():
			filtros[i].cutoff_hz = lerpf(corte, normais[i], k * k)
	abrir.call(0.0)
	_abafando = create_tween()
	_abafando.tween_method(abrir, 0.0, 1.0, 1.6).set_delay(0.05)
	if _zumbido_ouvido:
		_zumbido_ouvido.volume_db = linear_to_db(clampf(intensidade * 0.12, 0.05, 0.2))
		_zumbido_ouvido.play()
