class_name SomGerador
extends RefCounted
## Gera em código os sons do carro que não são o motor (o projeto não tem arquivos de
## áudio): camadas em loop, controladas por volume e pitch, e efeitos pontuais.
## Tudo mono, 16 bits. Roda uma vez, numa thread, quando o carro entra na cena.

## Sons já gerados (preenchida pelo som_carro.gd), para os inimigos usarem também
static var biblioteca := {}

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
		"zumbido": zumbido(),
		"assobio": assobio(),
		"arrancada": arrancada(),
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
		"zumbido_inimigo": zumbido_inimigo(),
		"missil": missil(),
		"lancamento": lancamento(),
		"portal": portal(),
		"volta": volta(),
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

## Pneus rodando sobre os hexágonos: ronco grave e o "grão" da banda de rodagem
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

## Alarme de míssil: "pi" curto e limpo, com ataque e soltura macios
func bip() -> AudioStreamWAV:
	var n := int(taxa * 0.07)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		var env := minf(t / 0.003, 1.0) * minf((0.07 - t) / 0.015, 1.0)
		a[i] = (sin(TAU * 1800.0 * t) + 0.25 * sin(TAU * 3600.0 * t)) * env
	return _wav(_normalizar(a, 0.6), false)

## O "piiii" de quando o míssil está para acertar: o mesmo tom, em loop
func bip_continuo() -> AudioStreamWAV:
	var n := taxa
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / taxa
		a[i] = sin(TAU * 1800.0 * t) + 0.25 * sin(TAU * 3600.0 * t)
	return _wav(_normalizar(a, 0.6), true)

## Pirâmide: acorde grave e sinistro com batimento lento e pulsação de energia
func zumbido_inimigo() -> AudioStreamWAV:
	var n := taxa * 2
	var a := PackedFloat32Array()
	a.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / taxa
		var acorde := sin(TAU * 55.0 * t) + 0.6 * sin(TAU * 82.5 * t) + 0.4 * sin(TAU * 110.0 * t) + 0.4 * sin(TAU * 111.0 * t)
		var pulso := 0.65 + 0.35 * sin(TAU * 2.0 * t)
		lp += (_ruido() - lp) * 0.05
		a[i] = acorde * pulso + lp * 0.8 + sin(TAU * 440.0 * t) * 0.05 * pulso
	return _wav(_normalizar(a, 0.7), true)

## Ponta voando: chiado de propulsor com um assobio tremendo por cima
func missil() -> AudioStreamWAV:
	var n := taxa
	var f := int(taxa * 0.2)
	var a := PackedFloat32Array()
	a.resize(n + f)
	var lo := 0.0
	var hi := 0.0
	for i in n + f:
		var t := float(i) / taxa
		var w := _ruido()
		lo += (w - lo) * 0.35
		hi += (w - hi) * 0.08
		var assobio := sin(TAU * 900.0 * t + 3.0 * sin(TAU * 12.0 * t))
		a[i] = (lo - hi) * 0.8 + assobio * 0.3
	return _loop(a, n, f)

## Pirâmide disparando uma ponta: estalo de energia e o ar rasgando
func lancamento() -> AudioStreamWAV:
	var n := int(taxa * 0.6)
	var a := PackedFloat32Array()
	a.resize(n)
	var low := 0.0
	var band := 0.0
	var fase := 0.0
	for i in n:
		var t := float(i) / taxa
		var x := t / 0.6
		var fc := 500.0 + 2500.0 * x
		var fk := 2.0 * sin(PI * fc / taxa)
		var high := _ruido() - low - 0.6 * band
		band += fk * high
		low += fk * band
		fase += TAU * (300.0 + 900.0 * x) / taxa
		var env := minf(t / 0.01, 1.0) * pow(1.0 - x, 2.0)
		a[i] = (band * 0.4 + sin(fase) * 0.4) * env + sin(TAU * 70.0 * t) * exp(-t / 0.06) * 0.6
	return _wav(_normalizar(a, 0.8), false)

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

## Fonte 3D de um som da biblioteca, configurada como as do carro (vazia se ainda
## não foi gerado)
static func fonte(nome: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = biblioteca.get(nome)
	p.bus = "Carro"
	p.unit_size = 6.0
	p.attenuation_filter_db = 0.0
	p.panning_strength = 0.8
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	return p

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
