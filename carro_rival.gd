class_name CarroRival
extends AnimatableBody3D
## Adversário da corrida: o veículo. Anda preso à pista em coordenadas (s, d) e
## segue os alvos de velocidade e de faixa que o cérebro (IARival) escolhe, com os
## limites de aceleração, frenagem e agilidade do perfil. É um corpo animável: empurra
## o carro do jogador quando encosta, e as batidas (TrafegoCorrida) chegam aqui como
## empurrões laterais e perda ou ganho de velocidade.
## Visual: o casco do Eco Shell com outra pintura, três rodas, número e nome.

## [lataria, filete] de cada adversário, pelo número
const PINTURAS := [
	[Color(0.85, 0.12, 0.1), Color(1.0, 0.75, 0.2)],
	[Color(0.95, 0.5, 0.08), Color(1.0, 0.95, 0.8)],
	[Color(0.95, 0.82, 0.15), Color(0.1, 0.1, 0.1)],
	[Color(0.35, 0.8, 0.15), Color(0.9, 1.0, 0.6)],
	[Color(0.05, 0.45, 0.25), Color(0.4, 1.0, 0.7)],
	[Color(0.1, 0.7, 0.75), Color(0.8, 1.0, 1.0)],
	[Color(0.45, 0.18, 0.8), Color(0.85, 0.6, 1.0)],
	[Color(0.85, 0.15, 0.55), Color(1.0, 0.7, 0.9)],
	[Color(0.9, 0.9, 0.92), Color(0.9, 0.15, 0.1)],
	[Color(0.12, 0.12, 0.14), Color(1.0, 0.85, 0.1)],
]
## Mesmas rodas do carro do jogador (car.tscn)
const RODAS := [Vector3(-0.27, 0.245, -0.75), Vector3(0.27, 0.245, -0.75), Vector3(0.0, 0.245, 0.7)]
const RAIO_RODA := 0.245
## Tamanho do carro em coordenadas da pista, para contatos (m)
const COMPRIMENTO := 2.7
const LARGURA := 0.85

static var _malha: Mesh
static var _tinta_base: ShaderMaterial

var numero := 0
var perfil: PerfilPiloto
var ia: IARival
var pista: PistaCorrida
## O que os outros enxergam deste carro (atualizado a cada passo)
var info := CarroNaPista.new()

## Estado na pista
var s := 0.0
var d := 0.0
var v := 0.0
var progresso := 0.0
var terminou := false
## Alvos do cérebro
var v_alvo := 0.0
var d_alvo := 0.0
## Multiplicador da agilidade (o cérebro aumenta na hora de atacar)
var agilidade_extra := 1.0

var _vel_lateral := 0.0
## Empurrão lateral de batidas (m/s), que vai sumindo
var _empurrao := 0.0
var _giros: Array[Node3D] = []
var _zumbido: AudioStreamPlayer3D
var _batida: AudioStreamPlayer3D

## Gera o casco uma única vez, num CascoEcoShell temporário (ele só constrói na árvore)
static func preparar(pai: Node):
	if _malha != null:
		return
	var modelo := CascoEcoShell.new()
	pai.add_child(modelo)
	_malha = modelo.mesh
	_tinta_base = modelo.material_casco
	modelo.queue_free()

func _init(n: int = 0, perfil_: PerfilPiloto = null):
	numero = n
	perfil = perfil_ if perfil_ else PerfilPiloto.new()
	ia = IARival.new(self)
	info.rival = self
	collision_layer = 1
	collision_mask = 0

func _ready():
	var pintura: Array = PINTURAS[(numero - 1) % PINTURAS.size()]
	var casco := MeshInstance3D.new()
	casco.mesh = _malha
	var tinta: ShaderMaterial = _tinta_base.duplicate()
	tinta.set_shader_parameter("cor_lataria", pintura[0])
	tinta.set_shader_parameter("cor_filete", pintura[1])
	casco.set_surface_override_material(0, tinta)
	add_child(casco)

	var pneu := CylinderMesh.new()
	pneu.top_radius = RAIO_RODA
	pneu.bottom_radius = RAIO_RODA
	pneu.height = 0.11
	pneu.radial_segments = 18
	var borracha := StandardMaterial3D.new()
	borracha.albedo_color = Color(0.06, 0.06, 0.07)
	borracha.roughness = 0.9
	pneu.material = borracha
	for posicao: Vector3 in RODAS:
		var giro := Node3D.new()
		giro.position = posicao
		var roda := MeshInstance3D.new()
		roda.mesh = pneu
		roda.rotation.z = PI * 0.5
		giro.add_child(roda)
		add_child(giro)
		_giros.append(giro)

	# Número na traseira, legível para quem vem atrás
	var placa := Label3D.new()
	placa.text = str(numero)
	placa.font_size = 96
	placa.pixel_size = 0.003
	placa.outline_size = 18
	placa.modulate = pintura[1]
	placa.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	placa.double_sided = false
	placa.position = Vector3(0.0, 0.5, 1.33)
	add_child(placa)
	# Nome flutuando em cima, sempre virado para quem olha
	var nome := Label3D.new()
	nome.text = perfil.nome
	nome.font_size = 48
	nome.pixel_size = 0.004
	nome.outline_size = 10
	nome.modulate = pintura[1]
	nome.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.position = Vector3(0.0, 1.35, 0.0)
	nome.visibility_range_end = 45.0
	add_child(nome)

	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(0.8, 0.7, 2.6)
	forma.shape = caixa
	forma.position = Vector3(0.0, 0.4, 0.0)
	add_child(forma)

	_batida = SomGerador.fonte("batida")
	add_child(_batida)

## Para na posição (s, d) da pista, sem velocidade (grid ou fim da corrida)
func estacionar(s_: float, d_: float):
	s = s_
	d = d_
	v = 0.0
	v_alvo = 0.0
	d_alvo = d_
	_vel_lateral = 0.0
	_empurrao = 0.0
	agilidade_extra = 1.0
	terminou = false
	# Atrás da linha conta como negativo: ainda não começou a primeira volta
	progresso = s - pista.comprimento if s > pista.comprimento * 0.5 else s
	ia.parar()
	_posar()
	_sincronizar()

## Um passo de física: velocidade e faixa indo para os alvos, dentro dos limites
func mover(dt: float):
	v += clampf(v_alvo - v, -perfil.frenagem * dt, perfil.aceleracao * dt)
	v = maxf(v, 0.0)
	var agil := perfil.agilidade * agilidade_extra
	var desejada := clampf((d_alvo - d) * 2.5, -agil, agil)
	_vel_lateral = move_toward(_vel_lateral, desejada, 10.0 * dt)
	d += (_vel_lateral + _empurrao) * dt
	_empurrao = move_toward(_empurrao, 0.0, 5.0 * dt)
	# Muro: raspa, perde um pouco e para de ir para o lado
	var limite := PistaCorrida.MEIA_UTIL
	if absf(d) > limite:
		d = signf(d) * limite
		_empurrao = 0.0
		_vel_lateral = 0.0
		v *= 1.0 - 0.6 * dt
	s = fposmod(s + v * dt, pista.comprimento)
	progresso += v * dt
	_posar()
	for giro in _giros:
		giro.rotation.x -= v * dt / RAIO_RODA
	# Rodas da frente esterçam com o movimento lateral
	var esterco := clampf(-(_vel_lateral + _empurrao) / maxf(v, 2.0), -0.5, 0.5)
	_giros[0].rotation.y = esterco
	_giros[1].rotation.y = esterco
	_som()
	_sincronizar()

## Batida vinda do tráfego: empurrão lateral (m/s, positivo = para a direita) e
## mudança de velocidade
func levar_batida(lateral: float, dv: float, forca: float, outro: CarroNaPista, culpado: bool):
	_empurrao = clampf(_empurrao + lateral, -4.0, 4.0)
	v = maxf(v + dv, 0.0)
	ia.notificar_batida(forca, outro, culpado)
	if forca > 0.8 and _batida.stream and not _batida.playing:
		_batida.volume_db = linear_to_db(clampf(forca / 5.0, 0.15, 1.0)) - 4.0
		_batida.pitch_scale = randf_range(0.9, 1.15)
		_batida.play()

func _posar():
	var q := pista.quadro(s)
	# Aponta o bico para onde o carro está indo (frente + deslize lateral)
	var guinada := atan2(_vel_lateral + _empurrao, maxf(v, 1.5))
	var base := q.basis.rotated(q.basis.y, -guinada)
	global_transform = pista.global_transform * Transform3D(base, q.origin + q.basis.x * d)

func _sincronizar():
	info.s = s
	info.d = d
	info.v = v
	info.progresso = progresso

## Zumbido do motor elétrico, mais agudo com a velocidade (a biblioteca de sons é
## gerada em segundo plano: entra quando estiver pronta)
func _som():
	if _zumbido == null:
		if not SomGerador.biblioteca.has("zumbido"):
			return
		_zumbido = SomGerador.fonte("zumbido")
		_zumbido.volume_db = -14.0
		_zumbido.max_distance = 60.0
		add_child(_zumbido)
		_zumbido.play()
		if _batida.stream == null:
			_batida.stream = SomGerador.biblioteca.get("batida")
	_zumbido.pitch_scale = 0.55 + v / 12.0 * 0.9
	_zumbido.volume_db = lerpf(-30.0, -12.0, clampf(v / 12.0, 0.0, 1.0))
