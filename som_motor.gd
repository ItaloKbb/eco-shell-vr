class_name SomMotor
extends AudioStreamPlayer3D
## Motor híbrido futurista: um monocilíndrico de 4 tempos pequeno e de giro alto,
## sintetizado em tempo real, com uma camada tonal de "turbina elétrica" por cima.
##
## Cada explosão é um pulso de pressão que desce pelo tubo do escapamento (filtro pente
## com a reflexão invertida da ponta aberta) e enche a caixa do silencioso (ressonador
## grave). Por cima, tons nos harmônicos da rotação e um assobio de turbina que sobe com
## o giro dão o caráter limpo e "de ficção". A carga do acelerador encorpa o pulso e os
## tons; tirando o pé em giro alto há um ou outro estalo abafado; no limitador o giro
## pulsa suave. A transmissão é um variador (CVT) com embreagem centrífuga.

@export var rpm_lenta := 1900.0
@export var rpm_limite := 10500.0
## Rotação que o variador segura com o acelerador no fundo, até o carro "alcançar"
@export var rpm_variador := 8200.0
## Abaixo disso a embreagem centrífuga solta a roda
@export var rpm_embreagem := 3200.0
## Comprimento do escapamento (m): define a nota do tubo
@export var escapamento := 0.55
@export var silencioso_hz := 150.0
@export_range(0.0, 1.0) var volume := 0.45
## Quanto da camada tonal futurista entra na mistura (0 = só combustão)
@export_range(0.0, 1.0) var futurista := 0.55

## Entradas, escritas pelo som_carro.gd a cada frame
var acelerador := 0.0
## Rotação que as rodas impõem pela relação final
var rpm_roda := 0.0
## Roda motriz no ar: o motor gira solto
var livre := false
## Subida/resistência extra (0 a 1): o motor "sofre" mais com o mesmo acelerador
var esforco := 0.0

var rpm := 0.0
var ligado := false

const TUBO := 512

var _taxa := 22050
var _playback: AudioStreamGeneratorPlayback
var _pulso := PackedFloat32Array()
var _tubo := PackedFloat32Array()
var _carga := 0.0
var _corte := false
var _partida := 0.0
var _estouros := 0
var _volume_atual := 0.0
var _rpm_tocado := 0.0
var _vel_corrente := 0.0

# Estado da síntese entre um bloco e outro
var _sem := 22222
var _ciclo := 0.0
var _fator := 1.0
var _ip1 := -1
var _ip2 := -1
var _a1 := 0.0
var _a2 := 0.0
var _env_r := 0.0
var _env_c := 0.0
var _w := 0
var _lpt := 0.0
var _m1 := 0.0
var _m2 := 0.0
var _lps := 0.0
var _la := 0.0
var _lb := 0.0
var _oc := 1.0
var _os := 0.0
var _dx := 0.0
var _dy := 0.0
var _fase_rot := 0.0
var _fase_turbina := 0.0
var _lpf := 0.0

func _ready():
	# GPU e CPU do Quest são de celular: taxa menor custa menos e o motor quase não tem agudo
	_taxa = 16000 if OS.has_feature("android") else 22050
	var gerador := AudioStreamGenerator.new()
	gerador.mix_rate = _taxa
	gerador.buffer_length = 0.08
	stream = gerador
	_tubo.resize(TUBO)
	_montar_pulso()
	play()
	_playback = get_stream_playback()

## Pulso de pressão de uma explosão (~14 ms): pico positivo da descarga seguido da
## rarefação, as duas curvas em forma de "sino" assimétrico
func _montar_pulso():
	var n := int(0.014 * _taxa)
	_pulso.resize(n)
	for k in n:
		var t := float(k) / _taxa
		var a := t / 0.0009
		var pico := a * exp(1.0 - a)
		var b := maxf(t - 0.0016, 0.0) / 0.0024
		var volta := b * exp(1.0 - b)
		var fim := clampf((n - k) / (0.25 * n), 0.0, 1.0)
		_pulso[k] = (pico - 0.6 * volta) * fim

## Motor de arranque girando e o motor pegando
func ligar():
	_partida = 0.75
	ligado = true

func desligar():
	ligado = false

## Dash: o giro dá um salto e o escapamento estoura
func arrancada():
	rpm = minf(rpm + 1800.0, rpm_limite)
	_estouros += 2

func _process(delta: float):
	_atualizar(delta)
	if _playback:
		var quadros := _playback.get_frames_available()
		if quadros > 0:
			_playback.push_buffer(_sintetizar(quadros))

func _atualizar(delta: float):
	var acel := clampf(acelerador, 0.0, 1.0)
	var carga_alvo := clampf(acel * (1.0 + 0.6 * esforco), 0.0, 1.0)
	_carga = move_toward(_carga, carga_alvo, (14.0 if carga_alvo > _carga else 7.0) * delta)
	if _partida > 0.0:
		_partida -= delta
		rpm = 330.0
		if _partida <= 0.0:
			rpm = 3800.0 # pegou: sobe e assenta na lenta
		return
	if not ligado:
		rpm = move_toward(rpm, 0.0, 3000.0 * delta)
		return
	var alvo: float
	if livre:
		alvo = lerpf(rpm_lenta, rpm_limite + 500.0, acel)
	else:
		var pela_roda := rpm_roda if rpm_roda > rpm_embreagem else rpm_lenta
		alvo = maxf(lerpf(rpm_lenta, rpm_variador, acel), pela_roda)
	if _corte:
		rpm -= 4500.0 * delta
	else:
		var taxa := (4500.0 + 10000.0 * acel) if alvo > rpm else (5500.0 if livre else 3500.0)
		rpm = move_toward(rpm, alvo, taxa * delta)
	if rpm >= rpm_limite:
		_corte = true
	elif rpm < rpm_limite - 280.0:
		_corte = false
	_vel_corrente = rpm_roda / 60.0 * 0.6

func _sintetizar(n: int) -> PackedVector2Array:
	var sr := float(_taxa)
	var buf := PackedVector2Array()
	buf.resize(n)

	var r := _rpm_tocado
	var drpm := (rpm - r) / n
	_rpm_tocado = rpm
	var giro := clampf(rpm / rpm_limite, 0.0, 1.2)
	var carga := _carga
	var vol0 := _volume_atual
	var vol1 := volume * (0.45 + 0.55 * carga) * (0.55 + 0.45 * giro) if rpm > 50.0 else 0.0
	_volume_atual = vol1
	var dvol := (vol1 - vol0) / n
	var vol := vol0

	var k_ciclo := 1.0 / (120.0 * sr)
	var irregular := 0.05 * (1.0 - clampf(giro * 2.0, 0.0, 1.0)) + 0.008
	var base := lerpf(0.22, 1.0, carga)
	var partida := _partida > 0.0
	if partida:
		base = 0.15 # só a compressão "tossindo" no arranque
	var corte := _corte
	var estalos := carga < 0.12 and rpm > 4200.0

	# Tubo: ida e volta do pulso na velocidade do som do gás quente (~480 m/s)
	var atraso := clampi(int(2.0 * escapamento / 480.0 * sr), 4, TUBO - 1)
	var dec_r := exp(-1.0 / (0.0018 * sr))
	var k_brilho := 0.1 + 0.18 * carga
	# Silencioso: ressonador de dois polos
	var w0 := TAU * silencioso_hz / sr
	var rr := 0.975
	var c1 := 2.0 * rr * cos(w0)
	var c2 := rr * rr
	var g_m := 1.0 - rr
	# Admissão: faixa de ruído entre ~500 Hz e ~1,6 kHz
	var ka := 1.0 - exp(-TAU * 1600.0 / sr)
	var kb := 1.0 - exp(-TAU * 500.0 / sr)
	var g_adm := 0.12 * carga * giro
	var drive := 0.7 + 0.5 * carga
	# Corrente/coroa (ou motor de arranque na partida): oscilador em quadratura
	var f_osc := 180.0 if partida else _vel_corrente * 42.0
	var g_osc := 0.08 if partida else 0.018 * clampf(_vel_corrente / 5.0, 0.0, 1.0)
	var co := cos(TAU * f_osc / sr)
	var si := sin(TAU * f_osc / sr)
	# Camada futurista: harmônicos da rotação do virabrequim e assobio de turbina (14×)
	var k_rot := 1.0 / (60.0 * sr)
	var g_comb := 1.0 - 0.6 * futurista
	var g_tom := 0.5 * futurista * (0.5 + 0.5 * carga)
	var g_harm := 0.25 + 0.35 * carga
	var g_turb := futurista * (0.03 + 0.07 * giro) * (0.6 + 0.4 * carga)
	# Passa-baixa final (~4 kHz): tira a aspereza
	var k_lpf := 1.0 - exp(-TAU * 4000.0 / sr)
	var fase_rot := _fase_rot
	var fase_turb := _fase_turbina
	var lpf := _lpf

	var pulso := _pulso
	var np := pulso.size()
	var tubo := _tubo
	var sem := _sem
	var ciclo := _ciclo
	var fator := _fator
	var ip1 := _ip1
	var ip2 := _ip2
	var a1 := _a1
	var a2 := _a2
	var env_r := _env_r
	var env_c := _env_c
	var w := _w
	var lpt := _lpt
	var m1 := _m1
	var m2 := _m2
	var lps := _lps
	var la := _la
	var lb := _lb
	var oc := _oc
	var os := _os
	var dx := _dx
	var dy := _dy
	var estouros := _estouros

	for i in n:
		r += drpm
		vol += dvol
		var anterior := ciclo
		ciclo += r * k_ciclo * fator
		if ciclo >= 1.0:
			# Explosão (ou falha)
			ciclo -= 1.0
			sem = (sem * 1103515245 + 12345) & 0x7fffffff
			var u := float(sem) / 2147483647.0
			fator = 1.0 + (u - 0.5) * irregular
			var amp := base * (0.82 + 0.36 * u)
			var ruido := amp * (0.1 + 0.3 * carga)
			if corte:
				# Limitador: corta a ignição; às vezes sobra um pulso fraco
				amp = 0.4 if u < 0.2 else 0.0
				ruido = amp * 0.3
			elif estouros > 0:
				estouros -= 1
				amp = 1.0
				ruido = 0.4
			elif estalos and u < 0.04:
				amp = 0.6
				ruido = 0.3
			if amp > 0.0:
				if ip1 < 0 or (ip2 >= 0 and ip1 > ip2):
					ip1 = 0
					a1 = amp
				else:
					ip2 = 0
					a2 = amp
				env_r = maxf(env_r, ruido)
		elif anterior < 0.3 and ciclo >= 0.3:
			env_c = 1.0 # válvulas

		var x := 0.0
		if ip1 >= 0:
			x += pulso[ip1] * a1
			ip1 += 1
			if ip1 >= np:
				ip1 = -1
		if ip2 >= 0:
			x += pulso[ip2] * a2
			ip2 += 1
			if ip2 >= np:
				ip2 = -1
		sem = (sem * 1103515245 + 12345) & 0x7fffffff
		var ru := float(sem) / 1073741823.5 - 1.0
		x += ru * env_r * 0.2
		env_r *= dec_r

		# Tubo do escapamento: reflexão invertida e amortecida da ponta aberta
		lpt += (tubo[(w - atraso) & (TUBO - 1)] - lpt) * 0.45
		var y := x - 0.62 * lpt
		tubo[w] = y
		w = (w + 1) & (TUBO - 1)
		# Caixa do silencioso
		var m := g_m * y + c1 * m1 - c2 * m2
		m2 = m1
		m1 = m
		lps += (y - lps) * k_brilho
		var s := 0.8 * lps + 2.2 * m

		# Admissão: só no tempo de admissão do ciclo
		la += (ru - la) * ka
		lb += (ru - lb) * kb
		var janela := clampf((ciclo - 0.55) * 4.0, 0.0, 1.0)
		s += (la - lb) * janela * (1.0 - janela) * 4.0 * g_adm
		# Tique das válvulas, agudo e curto
		s += ru * env_c * 0.01 * giro
		env_c *= 0.6
		# Corrente (ou motor de arranque)
		var noc := oc * co - os * si
		os = oc * si + os * co
		oc = noc
		s += os * g_osc

		# Saturação bem leve, só para arredondar os picos
		s *= drive
		s = s / (1.0 + (s if s > 0.0 else -s))

		# Tons limpos acompanhando o giro, por cima da combustão
		fase_rot += r * k_rot
		if fase_rot >= 1.0:
			fase_rot -= 1.0
		var p := TAU * fase_rot
		var tom := sin(p) * 0.45 + sin(2.0 * p) * 0.5 + sin(4.0 * p) * g_harm
		fase_turb += r * 14.0 * k_rot
		if fase_turb >= 1.0:
			fase_turb -= 1.0
		s = s * g_comb + tom * g_tom + sin(TAU * fase_turb) * g_turb
		lpf += (s - lpf) * k_lpf

		# Tira o nível DC
		var o := lpf - dx + 0.995 * dy
		dx = lpf
		dy = o
		buf[i] = Vector2(o, o) * vol

	# Mantém o oscilador com amplitude 1 apesar dos arredondamentos
	var norma := sqrt(oc * oc + os * os)
	_oc = oc / norma
	_os = os / norma
	_tubo = tubo
	_fase_rot = fase_rot
	_fase_turbina = fase_turb
	_lpf = lpf
	_sem = sem
	_ciclo = ciclo
	_fator = fator
	_ip1 = ip1
	_ip2 = ip2
	_a1 = a1
	_a2 = a2
	_env_r = env_r
	_env_c = env_c
	_w = w
	_lpt = lpt
	_m1 = m1
	_m2 = m2
	_lps = lps
	_la = la
	_lb = lb
	_dx = dx
	_dy = dy
	_estouros = estouros
	return buf
