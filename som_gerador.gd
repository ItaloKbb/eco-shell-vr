class_name SomGerador
extends RefCounted
## Gera em código os sons do carro que não são o motor (o projeto não tem arquivos de
## áudio): camadas em loop, controladas por volume e pitch, e efeitos pontuais.
## Tudo mono, 16 bits. Roda uma vez, numa thread, quando o carro entra na cena.

## Sons já gerados (preenchida pelo som_carro.gd), para adversários e explosões usarem também
static var biblioteca := {}
## Barramento dos sons de fora da cabine
const BARRAMENTO_MUNDO := "Mundo"

var taxa := 22050
var _sem := 987654

func _ruido() -> float:
	_sem = (_sem * 1103515245 + 12345) & 0x7fffffff
	return float(_sem) / 1073741823.5 - 1.0

func _sorteio() -> float:
	return _ruido() * 0.5 + 0.5

## Todos os sons, por nome
func gerar() -> Dictionary:
	return {
		"vento": vento(),
		"rolamento": rolamento(),
		"chiado": chiado_pneu(),
		"freio": freio(),
		"raspagem": raspagem(),
		"zumbido": zumbido(),
		"assobio": assobio(),
		"arrancada": arrancada(),
		"nitro": ronco_nitro(),
		"impacto": impacto(),
		"batida": batida(),
		"carga": carga_eletrica(),
		"descarga": descarga_eletrica(),
		"faisca": faisca(),
		"clique": clique(),
		"explosao": explosao(),
		"trinca": trinca(),
		"bip": bip(),
		"bip_continuo": bip_continuo(),
		"portal": portal(),
		"volta": volta(),
		"corpo": corpo(),
		"amassado": amassado(),
		"detritos": detritos(),
		"clang": clang(),
		"zap": zap(),
		"zumbido_ouvido": zumbido_ouvido(),
		"motor_rival": motor_rival(),
		"passagem": passagem(),
	}

# --- Loops ---------------------------------------------------------------------

## Ar passando pela bolha: ruído rosa, abafado
func vento() -> AudioStreamWAV:
	var n := int(taxa * 3.0)
	var f := int(taxa * 0.4)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var lp := 0.0
	for i in n + f:
		var w := _ruido()
		b0 = 0.99765 * b0 + w * 0.0990460
		b1 = 0.96300 * b1 + w * 0.2965164
		b2 = 0.57000 * b2 + w * 1.0526913
		lp += ((b0 + b1 + b2 + w * 0.1848) - lp) * 0.3
		a[i] = lp
	return _loop(a, n, f)

## Pneus rodando sobre o piso neon: ronco grave e o "grão" da banda de rodagem
func rolamento() -> AudioStreamWAV:
	var n := int(taxa * 2.0)
	var f := int(taxa * 0.3)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var marrom := 0.0
	var lp := 0.0
	var res := _ressonador(240.0, 0.992)
	var r1 := 0.0
	var r2 := 0.0
	for i in n + f:
		marrom = (marrom + 0.03 * _ruido()) * 0.996
		lp += (marrom - lp) * 0.08
		var grao := _ruido() if _sorteio() < 0.006 else 0.0
		var r := res.z * grao + res.x * r1 - res.y * r2
		r2 = r1
		r1 = r
		a[i] = lp * 3.0 + r * 0.6 + _ruido() * 0.005
	return _loop(a, n, f)

## Pneu cantando de lado: tons com vibrato (ciclos inteiros no loop) e ruído de faixa
func chiado_pneu() -> AudioStreamWAV:
	var n := int(taxa * 2.0)
	var f := int(taxa * 0.2)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var lo := 0.0
	var hi := 0.0
	for i in n + f:
		var t := float(i) / taxa
		var vib := 0.004 * sin(TAU * 5.0 * t)
		var tom := sin(TAU * 1100.0 * t + 1100.0 * TAU * vib / 5.0) * 0.6 \
			+ sin(TAU * 1650.0 * t) * 0.25 + sin(TAU * 2200.0 * t + 0.7) * 0.15
		var am := 0.7 + 0.3 * sin(TAU * 3.0 * t)
		var w := _ruido()
		lo += (w - lo) * 0.45
		hi += (w - hi) * 0.15
		a[i] = tom * am * 0.6 + (lo - hi) * 0.5
	return _loop(a, n, f)

## Freio a disco de bicicleta: chiado de atrito, ronco do disco e o guincho intermitente
func freio() -> AudioStreamWAV:
	var n := int(taxa * 4.0)
	var f := int(taxa * 0.3)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var lp := 0.0
	var lp2 := 0.0
	var marrom := 0.0
	for i in n + f:
		var t := float(i) / taxa
		var w := _ruido()
		lp += (w - lp) * 0.7
		lp2 += (w - lp2) * 0.12
		marrom = (marrom + 0.04 * _ruido()) * 0.99
		var guincho := pow(0.5 + 0.5 * sin(TAU * 0.5 * t), 6.0) * sin(TAU * 2900.0 * t)
		a[i] = (lp - lp2) * 0.35 + marrom * 1.5 + guincho * 0.1
	return _loop(a, n, f)

## Casco deslizando no chão ou numa parede: metal/fibra áspero com pequenas
## ressonâncias. É um loop controlado pela velocidade tangencial do contato.
func raspagem() -> AudioStreamWAV:
	var n := int(taxa * 2.0)
	var f := int(taxa * 0.25)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var grave := 0.0
	var medio := 0.0
	var ra := _ressonador(1250.0, 0.975)
	var rb := _ressonador(3100.0, 0.955)
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n + f:
		var w := _ruido()
		grave += (w - grave) * 0.06
		medio += (w - medio) * 0.35
		var grao := (medio - grave) * (0.35 if _sorteio() > 0.025 else 2.0)
		var ya := ra.z * grao + ra.x * a1 - ra.y * a2
		a2 = a1
		a1 = ya
		var yb := rb.z * grao + rb.x * b1 - rb.y * b2
		b2 = b1
		b1 = yb
		a[i] = grave * 0.7 + ya * 0.8 + yb * 0.35
	return _loop(a, n, f)

## Gerador da pista de energia: zumbido de 100 Hz com harmônicos e um zunido áspero
func zumbido() -> AudioStreamWAV:
	var n := taxa
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var p := TAU * 100.0 * float(i) / taxa
		var s := sin(p) * 0.5 + sin(2.0 * p) * 0.35 + sin(3.0 * p) * 0.25 + sin(5.0 * p) * 0.12 + sin(7.0 * p) * 0.06
		var zz := 1.0 if sin(2.0 * p) > 0.0 else -1.0
		lp += (zz - lp) * 0.25
		var estalo := _ruido() * 0.6 if _sorteio() < 0.0008 else 0.0
		a[i] = s * 0.7 + lp * 0.12 + estalo
	return _wav(_normalizar(a, 0.8), true)

## Inversor e motor elétrico: assobio tonal (tocado com pitch pela velocidade)
func assobio() -> AudioStreamWAV:
	var n := taxa
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		var am := 0.85 + 0.15 * sin(TAU * 30.0 * t)
		a[i] = (sin(TAU * 700.0 * t) * 0.6 + sin(TAU * 707.0 * t) * 0.25 + sin(TAU * 1400.0 * t) * 0.3
			+ sin(TAU * 2100.0 * t) * 0.12 + sin(TAU * 600.0 * t) * 0.1 + sin(TAU * 800.0 * t) * 0.1) * am
	return _wav(_normalizar(a, 0.8), true)

# --- Efeitos pontuais ---------------------------------------------------------

## Nitro: ronco de V12 estilo Ferrari. O giro sobe rápido de ~3500 a ~9000 rpm, segura
## lá em cima gritando e alivia no fim com os estalos do escapamento. Toca no carro e
## nos carros dos outros jogadores (a rede avisa quando cada um liga o nitro)
func ronco_nitro() -> AudioStreamWAV:
	var dur := 2.6
	var n := int(taxa * dur)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / taxa
		var sobe := 1.0 - exp(-t / 0.32)
		var alivio := smoothstep(1.7, 2.5, t)
		var rpm := lerpf(3500.0, 9000.0, sobe) * (1.0 - 0.45 * alivio)
		# Quatro tempos, 12 cilindros: 6 explosões por volta do virabrequim
		fase += TAU * rpm / 60.0 * 6.0 / taxa
		# Tom: harmônicos do disparo e a meia ordem que dá a aspereza do V12
		var tom := sin(fase) + 0.55 * sin(2.0 * fase + 0.3) + 0.35 * sin(3.0 * fase + 0.9) \
			+ 0.18 * sin(4.0 * fase + 1.7) + 0.3 * sin(0.5 * fase)
		# Pulso do escapamento a cada explosão: o "rasgado" do grito
		var pulso := pow(0.5 + 0.5 * sin(fase), 6.0)
		# Admissão: ruído filtrado subindo com o giro
		var fc := 900.0 + 2200.0 * sobe * (1.0 - 0.5 * alivio)
		var fk := 2.0 * sin(PI * fc / taxa)
		var high := _ruido() - low - 0.6 * band
		band += fk * high
		low += fk * band
		var carga := 1.0 - 0.6 * alivio
		var env := minf(t / 0.04, 1.0) * (1.0 - smoothstep(2.25, dur, t))
		var x := (tom * 0.45 + pulso * 0.7 * carga + band * 0.15) * env
		# Saturação suave: o escapamento "estoura" sem clipar
		a[i] = tanh(x * 2.4)
	# Estalos do escapamento no alívio
	for k in 6:
		var inicio := int((1.8 + k * 0.1 + _sorteio() * 0.05) * taxa)
		var forca := 0.9 - k * 0.1
		for j in int(taxa * 0.035):
			if inicio + j < n:
				a[inicio + j] += _ruido() * exp(-float(j) / (taxa * 0.007)) * forca
	return _wav(_normalizar(a, 0.9), false)

## Dash: golfada de ar macia, um "whoom" tonal subindo e um baque grave
func arrancada() -> AudioStreamWAV:
	var n := int(taxa * 0.9)
	var a := PackedFloat32Array()
	a.resize(n)
	var low := 0.0
	var band := 0.0
	var fase := 0.0
	for i in n:
		var t := float(i) / taxa
		var x := t / 0.9
		var fc := 350.0 + 2600.0 * pow(sin(PI * minf(x * 1.4, 1.0)), 1.5)
		var fk := 2.0 * sin(PI * fc / taxa)
		var high := _ruido() - low - 0.5 * band
		band += fk * high
		low += fk * band
		var env := minf(t / 0.04, 1.0) * pow(1.0 - x, 1.6)
		var boom := sin(TAU * (55.0 * t - 20.0 * t * t)) * exp(-t / 0.18)
		# "Whoom" tonal subindo, por cima do ar
		fase += TAU * (180.0 + 520.0 * pow(sin(PI * minf(x * 1.2, 1.0)), 1.2)) / taxa
		var whoom := (sin(fase) + 0.3 * sin(2.0 * fase)) * env
		a[i] = band * env * 0.2 + boom * 0.6 + whoom * 0.45
	return _wav(_normalizar(a, 0.9), false)

## Roda pousando ou pegando um degrau: baque grave e o casco de fibra vibrando
func impacto() -> AudioStreamWAV:
	return _pancada(0.35, 85.0, 0.06, 0.08, Vector2(320.0, 900.0))

## Casco batendo forte
func batida() -> AudioStreamWAV:
	return _pancada(0.8, 62.0, 0.15, 0.25, Vector2(210.0, 640.0))

func _pancada(dur: float, freq: float, decai: float, chacoalho: float, casco: Vector2) -> AudioStreamWAV:
	var n := int(taxa * dur)
	var a := PackedFloat32Array()
	a.resize(n)
	var ra := _ressonador(casco.x, 0.996)
	var rb := _ressonador(casco.y, 0.993)
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var fase := 0.0
	for i in n:
		var t := float(i) / taxa
		fase += TAU * freq * (0.55 + 0.45 * exp(-t / 0.05)) / taxa
		var baque := sin(fase) * exp(-t / decai)
		var estalo := _ruido() * exp(-t / 0.004)
		var grao := _ruido() * exp(-t / chacoalho) * (1.0 if _sorteio() < 0.3 else 0.2)
		var ya := ra.z * grao + ra.x * a1 - ra.y * a2
		a2 = a1
		a1 = ya
		var yb := rb.z * grao + rb.x * b1 - rb.y * b2
		b2 = b1
		b1 = yb
		a[i] = baque + estalo * 0.08 + (ya + yb) * 0.9
	return _wav(_normalizar(a, 0.9), false)

## Liga a energia: varredura subindo, com trêmulo cada vez mais rápido, e o estalo final
func carga_eletrica() -> AudioStreamWAV:
	var n := int(taxa * 1.1)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	var trem := 0.0
	for i in n:
		var t := float(i) / taxa
		var x := t / 1.1
		fase += TAU * 120.0 * pow(15.0, minf(x / 0.85, 1.0)) / taxa
		trem += TAU * lerpf(8.0, 45.0, x) / taxa
		var tom := sin(fase) + 0.4 * sin(2.0 * fase) + 0.2 * sin(3.01 * fase)
		var env := minf(t / 0.05, 1.0) * (1.0 if x < 0.85 else exp(-(x - 0.85) * 25.0))
		var estalo := _ruido() * exp(-maxf(t - 0.85 * 1.1, 0.0) / 0.03) * (1.0 if x > 0.85 else 0.0)
		a[i] = tom * env * (0.8 + 0.2 * sin(trem)) * 0.5 + estalo * 0.15
	return _wav(_normalizar(a, 0.85), false)

## Desliga a energia: varredura descendo e apagando
func descarga_eletrica() -> AudioStreamWAV:
	var n := int(taxa * 0.8)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	for i in n:
		var t := float(i) / taxa
		var x := t / 0.8
		fase += TAU * 1500.0 * pow(1.0 / 25.0, x) / taxa
		var tom := sin(fase) + 0.35 * sin(2.0 * fase)
		a[i] = tom * pow(1.0 - x, 1.5) * minf(t / 0.01, 1.0) + _ruido() * 0.05 * (1.0 - x)
	return _wav(_normalizar(a, 0.8), false)

## Faísca/arco: estalos esparsos num ressonador agudo e um zunido de 100 Hz
func faisca() -> AudioStreamWAV:
	var n := int(taxa * 0.22)
	var a := PackedFloat32Array()
	a.resize(n)
	var ra := _ressonador(2800.0, 0.97)
	var rb := _ressonador(5200.0, 0.95)
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var t := float(i) / taxa
		var chance := 0.08 * exp(-t / 0.08)
		var imp := _ruido() * 1.2 if _sorteio() < chance else 0.0
		var ya := ra.z * imp + ra.x * a1 - ra.y * a2
		a2 = a1
		a1 = ya
		var yb := rb.z * imp + rb.x * b1 - rb.y * b2
		b2 = b1
		b1 = yb
		var zz := sin(TAU * 100.0 * t) * 0.3 * exp(-t / 0.05)
		a[i] = ya + yb * 0.4 + zz
	return _wav(_normalizar(a, 0.85), false)

## Botão do painel: clique macio de tecla com um "bip" curto de confirmação
func clique() -> AudioStreamWAV:
	var n := int(taxa * 0.12)
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / taxa
		lp += (_ruido() - lp) * 0.3
		var toque := lp * exp(-t / 0.003)
		var bip := sin(TAU * 1760.0 * t) * exp(-maxf(t - 0.02, 0.0) / 0.03) * (1.0 if t > 0.02 else 0.0)
		a[i] = toque * 1.5 + bip * 0.3
	return _wav(_normalizar(a, 0.7), false)

## Explosão: estrondo grave descendo, ronco que vai sumindo e destroços crepitando.
## Sem estalo áspero no começo: o ataque é rápido mas arredondado
func explosao() -> AudioStreamWAV:
	var n := int(taxa * 2.6)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	var marrom := 0.0
	var lp := 0.0
	var ra := _ressonador(700.0, 0.97)
	var r1 := 0.0
	var r2 := 0.0
	for i in n:
		var t := float(i) / taxa
		var ataque := 1.0 - exp(-t / 0.008)
		fase += TAU * (30.0 + 60.0 * exp(-t / 0.25)) / taxa
		var estrondo := sin(fase) * exp(-t / 0.5)
		marrom = (marrom + 0.05 * _ruido()) * 0.997
		lp += (marrom - lp) * 0.06
		var ronco := lp * 6.0 * exp(-t / 0.9)
		var chance := 0.012 * exp(-t / 0.7)
		var estalo := _ruido() if _sorteio() < chance else 0.0
		var crepita := ra.z * estalo + ra.x * r1 - ra.y * r2
		r2 = r1
		r1 = crepita
		a[i] = (estrondo * 0.9 + ronco + crepita * 0.5) * ataque
	return _wav(_normalizar(a, 0.9), false)

## Vidro trincando: estalos agudos em sequência, cada vez mais fracos
func trinca() -> AudioStreamWAV:
	var n := int(taxa * 0.35)
	var a := PackedFloat32Array()
	a.resize(n)
	var ra := _ressonador(3400.0, 0.985)
	var rb := _ressonador(5600.0, 0.98)
	var a1 := 0.0
	var a2 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	for i in n:
		var t := float(i) / taxa
		var chance := 0.03 * exp(-t / 0.06)
		var imp := _ruido() if _sorteio() < chance or i < 30 else 0.0
		var ya := ra.z * imp + ra.x * a1 - ra.y * a2
		a2 = a1
		a1 = ya
		var yb := rb.z * imp + rb.x * b1 - rb.y * b2
		b2 = b1
		b1 = yb
		a[i] = ya + yb * 0.6
	return _wav(_normalizar(a, 0.7), false)

## Alarme do painel: "pi" curto e limpo, com ataque e soltura macios
func bip() -> AudioStreamWAV:
	var n := int(taxa * 0.07)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		var env := minf(t / 0.003, 1.0) * minf((0.07 - t) / 0.015, 1.0)
		a[i] = (sin(TAU * 1800.0 * t) + 0.25 * sin(TAU * 3600.0 * t)) * env
	return _wav(_normalizar(a, 0.6), false)

## O "piiii" do alarme no último instante: o mesmo tom, em loop
func bip_continuo() -> AudioStreamWAV:
	var n := taxa
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		a[i] = sin(TAU * 1800.0 * t) + 0.25 * sin(TAU * 3600.0 * t)
	return _wav(_normalizar(a, 0.6), true)

## Portal: ronco grave com batimento lento e vento girando (filtro varrendo devagar),
## como ar sendo sugado por um túnel
func portal() -> AudioStreamWAV:
	var n := taxa * 4
	var f := int(taxa * 0.5)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var low := 0.0
	var band := 0.0
	var marrom := 0.0
	for i in n + f:
		var t := float(i) / taxa
		var ronco := sin(TAU * 41.0 * t) + 0.7 * sin(TAU * 41.6 * t) + 0.3 * sin(TAU * 82.0 * t)
		var fc := 500.0 + 450.0 * sin(TAU * 0.25 * t) + 200.0 * sin(TAU * 0.7 * t)
		var fk := 2.0 * sin(PI * fc / taxa)
		var high := _ruido() - low - 0.35 * band
		band += fk * high
		low += fk * band
		marrom = (marrom + 0.03 * _ruido()) * 0.995
		a[i] = ronco * 0.45 + band * 0.5 + marrom * 2.0
	return _loop(a, n, f)

## Volta completa: sino de duas notas subindo, com brilho de oitava
func volta() -> AudioStreamWAV:
	var n := int(taxa * 1.2)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		var nota1 := (sin(TAU * 880.0 * t) + 0.3 * sin(TAU * 1760.0 * t)) * exp(-t / 0.35)
		var t2 := maxf(t - 0.14, 0.0)
		var nota2 := (sin(TAU * 1318.5 * t2) + 0.3 * sin(TAU * 2637.0 * t2)) * exp(-t2 / 0.5) * (1.0 if t > 0.14 else 0.0)
		a[i] = (nota1 + nota2) * minf(t / 0.004, 1.0)
	return _wav(_normalizar(a, 0.7), false)

# --- Impactos em camadas -------------------------------------------------------

## Corpo do choque: sub-grave curto (sente-se mais do que se ouve; no headset dá peso)
func corpo() -> AudioStreamWAV:
	var n := int(taxa * 0.55)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	for i in n:
		var t := float(i) / taxa
		fase += TAU * (32.0 + 26.0 * exp(-t / 0.06)) / taxa
		var env := (1.0 - exp(-t / 0.004)) * exp(-t / 0.16)
		a[i] = (sin(fase) + 0.25 * sin(2.0 * fase)) * env
	return _wav(_normalizar(a, 0.95), false)

## Casco amassando: rajadas de ruído em ressonâncias metálicas (fibra e alumínio
## dobrando), com o ranger diminuindo
func amassado() -> AudioStreamWAV:
	var n := int(taxa * 0.7)
	var a := PackedFloat32Array()
	a.resize(n)
	var res: Array[Vector3] = []
	for f in [430.0, 760.0, 1180.0, 1730.0, 2450.0]:
		res.append(_ressonador(f, 0.985))
	var y1 := PackedFloat32Array([0, 0, 0, 0, 0])
	var y2 := PackedFloat32Array([0, 0, 0, 0, 0])
	var lp := 0.0
	for i in n:
		var t := float(i) / taxa
		var chance := 0.05 * exp(-t / 0.18)
		var estalo := _ruido() * (2.0 if _sorteio() < chance else 0.12) * exp(-t / 0.25)
		var soma := 0.0
		for k in res.size():
			var r: Vector3 = res[k]
			var y := r.z * estalo + r.x * y1[k] - r.y * y2[k]
			y2[k] = y1[k]
			y1[k] = y
			soma += y / (1.0 + k * 0.4)
		lp += (_ruido() - lp) * 0.08
		a[i] = soma + lp * exp(-t / 0.05) * 0.8
	return _wav(_normalizar(a, 0.85), false)

## Pedacinhos caindo e quicando depois de uma batida forte
func detritos() -> AudioStreamWAV:
	var n := int(taxa * 1.1)
	var a := PackedFloat32Array()
	a.resize(n)
	var res: Array[Vector3] = [_ressonador(2300.0, 0.97), _ressonador(3900.0, 0.96), _ressonador(1500.0, 0.975)]
	var pesos := [1.0, 0.6, 0.8]
	var y1 := PackedFloat32Array([0, 0, 0])
	var y2 := PackedFloat32Array([0, 0, 0])
	for i in n:
		var t := float(i) / taxa
		var chance := 0.004 * exp(-t / 0.4) * (1.0 if t > 0.05 else 0.0)
		var imp := _ruido() * exp(-t / 0.6) if _sorteio() < chance else 0.0
		var soma := 0.0
		for k in 3:
			var r: Vector3 = res[k]
			var y := r.z * imp + r.x * y1[k] - r.y * y2[k]
			y2[k] = y1[k]
			y1[k] = y
			soma += y * pesos[k]
		a[i] = soma
	return _wav(_normalizar(a, 0.6), false)

## Carro contra carro: parciais inarmônicas de casco (sino abafado) sobre um baque
func clang() -> AudioStreamWAV:
	var n := int(taxa * 0.9)
	var a := PackedFloat32Array()
	a.resize(n)
	# [frequência, decaimento, ganho]
	var parciais := [[310.0, 0.18, 1.0], [742.0, 0.12, 0.6], [1287.0, 0.08, 0.45], [2013.0, 0.05, 0.3], [3140.0, 0.03, 0.2]]
	for i in n:
		var t := float(i) / taxa
		var s := 0.0
		for p in parciais:
			s += sin(TAU * p[0] * t * (1.0 + 0.002 * sin(TAU * 6.0 * t))) * exp(-t / p[1]) * p[2]
		var baque := sin(TAU * (70.0 + 40.0 * exp(-t / 0.03)) * t) * exp(-t / 0.07)
		var estalo := _ruido() * exp(-t / 0.003)
		a[i] = (s * 0.6 + baque * 0.9 + estalo * 0.3) * (1.0 - exp(-t / 0.0015))
	return _wav(_normalizar(a, 0.85), false)

## Parede de luz: estalo elétrico, zumbido de 100 Hz e um tom despencando
func zap() -> AudioStreamWAV:
	var n := int(taxa * 0.6)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	var ra := _ressonador(3600.0, 0.95)
	var r1 := 0.0
	var r2 := 0.0
	for i in n:
		var t := float(i) / taxa
		fase += TAU * (2200.0 * exp(-t / 0.09) + 90.0) / taxa
		var tom := (1.0 if sin(fase) > 0.0 else -1.0) * exp(-t / 0.12) * 0.35
		var chance := 0.25 * exp(-t / 0.05)
		var imp := _ruido() if _sorteio() < chance else 0.0
		var y := ra.z * imp + ra.x * r1 - ra.y * r2
		r2 = r1
		r1 = y
		var zumbido := (sin(TAU * 100.0 * t) + 0.5 * sin(TAU * 200.0 * t)) * exp(-t / 0.2) * 0.5
		a[i] = tom + y * 1.2 + zumbido + _ruido() * exp(-t / 0.006) * 0.5
	return _wav(_normalizar(a, 0.85), false)

## Zumbido no ouvido depois de uma pancada forte (tom puro, entra e some devagar)
func zumbido_ouvido() -> AudioStreamWAV:
	var n := int(taxa * 2.4)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		var env := minf(t / 0.08, 1.0) * pow(1.0 - t / 2.4, 2.0)
		a[i] = (sin(TAU * 3400.0 * t) + 0.15 * sin(TAU * 3412.0 * t)) * env
	return _wav(_normalizar(a, 0.5), false)

# --- Adversários -------------------------------------------------------------------

## Motor elétrico dos adversários: assobio mais áspero que o do jogador (inversor
## barato) com ronco embaixo. Cada carro toca com um tom base diferente
func motor_rival() -> AudioStreamWAV:
	var n := taxa
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / taxa
		var p := TAU * 440.0 * t
		var pwm := 1.0 if sin(TAU * 1320.0 * t) > 0.6 else 0.0
		lp += (_ruido() - lp) * 0.05
		a[i] = sin(p) * 0.5 + sin(2.0 * p) * 0.3 + sin(3.0 * p + 0.3) * 0.15 + pwm * 0.08 \
			+ sin(TAU * 110.0 * t) * 0.25 + lp * 0.6
	return _wav(_normalizar(a, 0.8), true)

## Passagem rente: ar rasgando, sobe e desce (o doppler da fonte 3D completa o efeito)
func passagem() -> AudioStreamWAV:
	var n := int(taxa * 1.0)
	var a := PackedFloat32Array()
	a.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / taxa
		var pico := exp(-pow((t - 0.4) / 0.18, 2.0))
		var fk := 2.0 * sin(PI * (400.0 + 2200.0 * pico) / taxa)
		var high := _ruido() - low - 0.5 * band
		band += fk * high
		low += fk * band
		a[i] = (band + low * 0.15) * pico
	return _wav(_normalizar(a, 0.8), false)

## Fonte 3D de um som da biblioteca para o que acontece fora da cabine
## (adversários, explosões), no barramento "Mundo". Longe, o ar abafa os agudos.
## Vazia se a biblioteca ainda não foi gerada
static func fonte(nome: String) -> AudioStreamPlayer3D:
	garantir_barramento_mundo()
	var p := AudioStreamPlayer3D.new()
	p.stream = biblioteca.get(nome)
	p.bus = BARRAMENTO_MUNDO
	p.unit_size = 6.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -14.0
	p.panning_strength = 0.8
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	return p

## Som pontual solto no mundo: toca uma vez em `onde` e se apaga sozinho
static func tocar_em(pai: Node, onde: Vector3, nome: String, volume_db := 0.0, pitch := 1.0, unidade := 6.0) -> AudioStreamPlayer3D:
	if not biblioteca.has(nome) or pai == null or not pai.is_inside_tree():
		return null
	var p := fonte(nome)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = unidade
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	pai.add_child(p)
	p.global_position = onde
	p.play()
	p.finished.connect(p.queue_free)
	return p

## Barramento dos sons de fora: compressão leve, ar livre (reverb curto e aberto) e
## limitador. Separado do "Carro" para a cabine e o mundo terem cada um o seu espaço
static func garantir_barramento_mundo():
	if AudioServer.get_bus_index(BARRAMENTO_MUNDO) >= 0:
		return
	var i := AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, BARRAMENTO_MUNDO)
	AudioServer.set_bus_send(i, "Master")
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -14.0
	compressor.ratio = 3.0
	compressor.attack_us = 2000.0
	compressor.release_ms = 220.0
	AudioServer.add_bus_effect(i, compressor)
	# Abafamento (concussão depois de batida forte): o som_carro.gd mexe no corte
	var abafa := AudioEffectLowPassFilter.new()
	abafa.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(i, abafa)
	var ar := AudioEffectReverb.new()
	ar.room_size = 0.55
	ar.damping = 0.5
	ar.spread = 1.0
	ar.hipass = 0.3
	ar.predelay_msec = 40.0
	ar.wet = 0.12
	ar.dry = 1.0
	AudioServer.add_bus_effect(i, ar)
	var limitador := AudioEffectHardLimiter.new()
	limitador.ceiling_db = -0.5
	AudioServer.add_bus_effect(i, limitador)

# --- Utilidades ---------------------------------------------------------------

## Coeficientes de um ressonador de dois polos: (2r·cos w, r², ganho)
func _ressonador(freq: float, r: float) -> Vector3:
	return Vector3(2.0 * r * cos(TAU * freq / taxa), r * r, 1.0 - r)

## Fecha o loop sem estalo: os últimos `f` quadros se misturam com o começo
func _loop(a: PackedFloat32Array, n: int, f: int) -> AudioStreamWAV:
	for i in f:
		var k := float(i) / f
		a[i] = a[i] * sqrt(k) + a[n + i] * sqrt(1.0 - k)
	a.resize(n)
	return _wav(_normalizar(a, 0.8), true)

func _normalizar(a: PackedFloat32Array, pico: float) -> PackedFloat32Array:
	var maior := 0.0001
	for v in a:
		maior = maxf(maior, absf(v))
	var g := pico / maior
	for i in a.size():
		a[i] *= g
	return a

func _wav(a: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var dados := PackedByteArray()
	dados.resize(a.size() * 2)
	for i in a.size():
		dados.encode_s16(i * 2, int(clampf(a[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = taxa
	wav.data = dados
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = a.size()
	return wav
