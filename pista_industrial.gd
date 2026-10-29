class_name PistaIndustrial
extends PistaAberta
## Pista do Parque Industrial: o "i". A haste é uma reta de ~1,8 km (com curvas de raio
## enorme só para não ficar monótona) e quatro rampas de salto com turbo no pouso
## (RampasPista), alternando esquerda, centro e direita. O pingo é uma praça redonda
## depois da área de frenagem, aberta para a pista, com o portal de volta no meio.

const LARGURA_I := 18.0
## Metros de corrida (da largada à chegada)
const CORRIDA := 1800.0
## Ondulação suave da reta: amplitude e comprimento de onda (m)
const ONDA := 22.0
const COMPRIMENTO_ONDA := 950.0
## Retas sem ondulação depois da largada e antes da chegada (m)
const RETA_PONTAS := 200.0
## [fração da corrida, faixa em fração da meia largura útil] de cada rampa
const RAMPAS := [[0.25, -0.55], [0.45, 0.0], [0.65, 0.55], [0.85, 0.0]]
const LARGURA_RAMPA := 8.0
## Praça do pingo (m)
const RAIO_PINGO := 32.0

func _init():
	super()
	largura = LARGURA_I
	letreiro = "SENAI 326 · PARQUE INDUSTRIAL"

func _ready():
	super()
	var lista: Array[Dictionary] = []
	for r in RAMPAS:
		lista.append({"s": s_largada + CORRIDA * float(r[0]), "d": meia_util * float(r[1]), "largura": LARGURA_RAMPA})
	rampas = RampasPista.new(self, lista)
	add_child(rampas)
	_pingo()

## Haste do i ao longo de X, centrada na origem
func _tracado() -> PackedVector2Array:
	var total := entrada + CORRIDA + saida
	var linha := PackedVector2Array()
	var x := 0.0
	while x <= total:
		var corrida := x - entrada
		var suave := smoothstep(0.0, RETA_PONTAS, corrida) * (1.0 - smoothstep(CORRIDA - RETA_PONTAS, CORRIDA, corrida))
		linha.append(Vector2(x - total * 0.5, ONDA * sin(TAU * corrida / COMPRIMENTO_ONDA) * suave))
		x += 2.0
	return linha

## O fim fica aberto para a praça
func _mureta_no_fim() -> bool:
	return false

## Centro da praça do pingo (local da pista)
func centro_pingo() -> Vector3:
	var fim := pontos[AMOSTRAS - 1]
	var frente := Vector3(frentes[AMOSTRAS - 1].x, 0.0, frentes[AMOSTRAS - 1].z).normalized()
	return fim + frente * RAIO_PINGO

## Praça redonda no fim da pista: piso com colisão e mureta em volta, aberta onde a
## pista chega
func _pingo():
	var centro := centro_pingo()
	var topo := pontos[AMOSTRAS - 1].y
	var piso := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = RAIO_PINGO
	disco.bottom_radius = RAIO_PINGO
	disco.height = 0.6
	disco.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.18, 0.2)
	material.roughness = 0.85
	disco.material = material
	piso.mesh = disco
	piso.position = Vector3(centro.x, topo - 0.3, centro.z)
	add_child(piso)
	var anel := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = RAIO_PINGO * 0.42
	toro.outer_radius = RAIO_PINGO * 0.46
	var neon := StandardMaterial3D.new()
	neon.albedo_color = Color(1.0, 0.6, 0.08)
	neon.emission_enabled = true
	neon.emission = Color(1.0, 0.6, 0.08)
	neon.emission_energy_multiplier = 2.0
	toro.material = neon
	anel.mesh = toro
	anel.scale = Vector3(1.0, 0.05, 1.0)
	anel.position = Vector3(centro.x, topo + 0.01, centro.z)
	add_child(anel)

	var corpo := StaticBody3D.new()
	corpo.name = "Pingo"
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var cilindro := CylinderShape3D.new()
	cilindro.radius = RAIO_PINGO
	cilindro.height = 0.6
	forma.shape = cilindro
	forma.position = piso.position
	corpo.add_child(forma)
	# Mureta: blocos em volta, menos na boca por onde a pista chega
	var entrada_pista := Vector2(pontos[AMOSTRAS - 1].x - centro.x, pontos[AMOSTRAS - 1].z - centro.z).angle()
	var abertura := asin(clampf((largura * 0.5 + 0.8) / RAIO_PINGO, 0.0, 1.0))
	var blocos := 40
	var arco := TAU * RAIO_PINGO / blocos
	var bloco := BoxMesh.new()
	bloco.size = Vector3(arco + 0.2, MURO_ALTURA * 1.4, MURO_ESPESSURA)
	var muro := ShaderMaterial.new()
	muro.shader = preload("res://muro_corrida.gdshader")
	bloco.material = muro
	for k in blocos:
		var a := TAU * (k + 0.5) / blocos
		if absf(angle_difference(a, entrada_pista)) < abertura + 0.04:
			continue
		var p := centro + Vector3(cos(a), 0.0, sin(a)) * (RAIO_PINGO + MURO_ESPESSURA * 0.5)
		var t := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(p.x, topo + MURO_ALTURA * 0.7 - 0.3, p.z))
		var m := MeshInstance3D.new()
		m.mesh = bloco
		m.transform = t
		add_child(m)
		var f := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = bloco.size
		f.shape = caixa
		f.transform = t
		corpo.add_child(f)
	add_child(corpo)
