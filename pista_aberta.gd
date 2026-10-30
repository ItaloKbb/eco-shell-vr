class_name PistaAberta
extends PistaCorrida
## Pista ponta a ponta (Sistema S, Parque Industrial, I de Incrível): largada numa ponta,
## chegada na outra, uma "volta" só. Cada pista desenha o traçado no plano em _tracado() (uma
## polilinha densa, começando pela reta do grid e terminando na área de frenagem), que é
## reamostrado por comprimento em AMOSTRAS amostras. Muro dos dois lados em toda a
## pista (ninguém corta caminho e perde os portões) e mureta atravessada nas pontas.
## Com `raio_pingo` a pista vira um "i": o fim fica aberto para uma praça redonda (o
## pingo), onde o mapa costuma pôr o portal de volta.

## Reta do grid antes da linha de largada (m): cabem as 11 vagas
var entrada := 80.0
## Área de frenagem depois da chegada, até o fim da pista (m): os adversários
## estacionam nela e o portal de volta fica no fim
var saida := 140.0
## Raio da praça do pingo no fim da pista (m); 0 = sem praça, mureta no fim
var raio_pingo := 0.0
## Piso da praça e o anel aceso no meio dela
var cor_piso_pingo := Color(0.18, 0.18, 0.2)
var cor_anel_pingo := Color(1.0, 0.6, 0.08)

func _init():
	aberta = true
	voltas = 1
	muro_dos_dois_lados = true

func _ready():
	super()
	if raio_pingo > 0.0:
		_pingo()

## Centro da pista no plano (x, z), do começo do grid até o fim, com pontos a cada ~2 m
func _tracado() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(0.0, -entrada - saida - 100.0)])

## O traçado reamostrado por comprimento de arco, com a altura do terreno embaixo
func _amostras_brutas() -> PackedVector3Array:
	var linha := _tracado()
	var acumulado := PackedFloat32Array([0.0])
	for i in range(1, linha.size()):
		acumulado.append(acumulado[i - 1] + linha[i].distance_to(linha[i - 1]))
	var total := acumulado[acumulado.size() - 1]
	var brutos := PackedVector3Array()
	var k := 0
	for i in AMOSTRAS:
		var alvo := total * i / (AMOSTRAS - 1)
		while k < linha.size() - 2 and acumulado[k + 1] < alvo:
			k += 1
		var f := clampf((alvo - acumulado[k]) / maxf(acumulado[k + 1] - acumulado[k], 0.0001), 0.0, 1.0)
		var p := linha[k].lerp(linha[k + 1], f)
		brutos.append(Vector3(p.x, _chao(p.x, p.y), p.y))
	return brutos

func _calcular():
	super()
	s_largada = entrada
	s_chegada = comprimento - saida

## Nenhum trecho passa por cima de outro
func _sob_viaduto(_p: Vector3) -> bool:
	return false

## Com o pingo o fim fica aberto para a praça
func _mureta_no_fim() -> bool:
	return raio_pingo <= 0.0

# --- Pingo do i -------------------------------------------------------------------

## Centro da praça do pingo (local da pista)
func centro_pingo() -> Vector3:
	var fim := pontos[AMOSTRAS - 1]
	var frente := Vector3(frentes[AMOSTRAS - 1].x, 0.0, frentes[AMOSTRAS - 1].z).normalized()
	return fim + frente * raio_pingo

## Praça redonda no fim da pista: piso com colisão e mureta em volta, aberta onde a
## pista chega
func _pingo():
	var centro := centro_pingo()
	var topo := pontos[AMOSTRAS - 1].y
	var piso := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = raio_pingo
	disco.bottom_radius = raio_pingo
	disco.height = 0.6
	disco.radial_segments = 48
	var material := StandardMaterial3D.new()
	material.albedo_color = cor_piso_pingo
	material.roughness = 0.85
	disco.material = material
	piso.mesh = disco
	piso.position = Vector3(centro.x, topo - 0.3, centro.z)
	add_child(piso)
	var anel := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = raio_pingo * 0.42
	toro.outer_radius = raio_pingo * 0.46
	var neon := StandardMaterial3D.new()
	neon.albedo_color = cor_anel_pingo
	neon.emission_enabled = true
	neon.emission = cor_anel_pingo
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
	cilindro.radius = raio_pingo
	cilindro.height = 0.6
	forma.shape = cilindro
	forma.position = piso.position
	corpo.add_child(forma)
	# Mureta: blocos em volta, menos na boca por onde a pista chega
	var entrada_pista := Vector2(pontos[AMOSTRAS - 1].x - centro.x, pontos[AMOSTRAS - 1].z - centro.z).angle()
	var abertura := asin(clampf((largura * 0.5 + 0.8) / raio_pingo, 0.0, 1.0))
	var blocos := 40
	var arco := TAU * raio_pingo / blocos
	var bloco := BoxMesh.new()
	bloco.size = Vector3(arco + 0.2, MURO_ALTURA * 1.4, MURO_ESPESSURA)
	var muro := ShaderMaterial.new()
	muro.shader = preload("res://muro_corrida.gdshader")
	muro.set_shader_parameter("corpo", paleta.muro)
	muro.set_shader_parameter("neon", paleta.neon)
	bloco.material = muro
	for k in blocos:
		var a := TAU * (k + 0.5) / blocos
		if absf(angle_difference(a, entrada_pista)) < abertura + 0.04:
			continue
		var p := centro + Vector3(cos(a), 0.0, sin(a)) * (raio_pingo + MURO_ESPESSURA * 0.5)
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

# --- Desenho do traçado -----------------------------------------------------------

## Reta de `metros` a partir do último ponto da linha, na direção dada
static func reta(linha: PackedVector2Array, direcao: Vector2, metros: float):
	var inicio := linha[linha.size() - 1]
	var passos := maxi(ceili(metros / 2.0), 1)
	for i in range(1, passos + 1):
		linha.append(inicio + direcao.normalized() * metros * i / passos)

## Arco de circunferência de `de` a `ate` (rad, no sentido que for) em volta de `centro`
static func arco(linha: PackedVector2Array, centro: Vector2, raio: float, de: float, ate: float):
	var passos := maxi(ceili(absf(ate - de) * raio / 2.0), 1)
	for i in range(1, passos + 1):
		var a := lerpf(de, ate, float(i) / passos)
		linha.append(centro + Vector2(cos(a), sin(a)) * raio)
