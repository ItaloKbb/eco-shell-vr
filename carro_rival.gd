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
## Turbo: o mesmo tanque do jogador (barras, enche sozinho, gasta 1 barra/s ligado). A
## reta com turbo chega a FATOR_TURBO x a máxima dele (~a máxima do nitro do jogador),
## sempre limitada pela velocidade segura das curvas à frente
const TANQUE := 5.0
const CARGA_PASSIVA := 0.2
const CONSUMO_TURBO := 1.0
const FATOR_TURBO := 2.5
## Quantos segundos de tanque cada turbo gasta no máximo
const DURACAO_TURBO := 3.0

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
## Tanque do turbo, quantos usou e quanto falta do atual (IA e testes de equilíbrio)
var nitro := 0.0
var turbos_usados := 0
var _tempo_turbo := 0.0
## Alvos do cérebro
var v_alvo := 0.0
var d_alvo := 0.0
## Multiplicador da agilidade (o cérebro aumenta na hora de atacar)
var agilidade_extra := 1.0

## Rampa de onde saltou (s da borda) enquanto está no ar; -INF no chão
var salto_s := -INF
## Turbo de placa (rampa) ainda valendo (s): segura a velocidade alta
var _turbo := 0.0

var _vel_lateral := 0.0
## Empurrão lateral de batidas (m/s), que vai sumindo
var _empurrao := 0.0
var _giros: Array[Node3D] = []
## Som: motor (tom próprio de cada carro), rolamento e raspagem no muro, em loop;
## batida e clangor nos contatos
var _motor: AudioStreamPlayer3D
var _rolamento: AudioStreamPlayer3D
var _raspagem: AudioStreamPlayer3D
var _batida: AudioStreamPlayer3D
var _clang: AudioStreamPlayer3D
var _faiscas_muro: GPUParticles3D
## Segundos raspando no muro (vai a zero quando solta) e lado do muro
var _no_muro := 0.0
var _lado_muro := 1.0
## Passagem rente pelo jogador: lado em que ele estava no passo anterior e espera
var _lado_jogador := 0.0
var _espera_passagem := 0.0
var _trilhas_turbo := Node3D.new()
## Corrida em grupo, Quest que não é o anfitrião: este carro não pensa nem anda sozinho,
## só segue o que o anfitrião manda (seguir_rede)
var remoto := false
var _interpolador := InterpoladorRede.new()

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
	_giros = montar_visual(self, pintura, perfil.nome, numero).giros

	# Dois filetes simples deixam o turbo legível sem partículas ou pós-processamento.
	_trilhas_turbo.name = "TrilhasTurbo"
	_trilhas_turbo.visible = false
	var rastro := BoxMesh.new()
	rastro.size = Vector3(0.055, 0.045, 1.8)
	var brilho := StandardMaterial3D.new()
	brilho.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brilho.albedo_color = pintura[1]
	brilho.emission_enabled = true
	brilho.emission = pintura[1]
	brilho.emission_energy_multiplier = 4.0
	rastro.material = brilho
	for x in [-0.23, 0.23]:
		var filete := MeshInstance3D.new()
		filete.mesh = rastro
		filete.position = Vector3(x, 0.27, 1.75)
		filete.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trilhas_turbo.add_child(filete)
	add_child(_trilhas_turbo)

	var forma := CollisionShape3D.new()
	var caixa := BoxShape3D.new()
	caixa.size = Vector3(0.8, 0.7, 2.6)
	forma.shape = caixa
	forma.position = Vector3(0.0, 0.4, 0.0)
	add_child(forma)

	_batida = SomGerador.fonte("batida")
	add_child(_batida)
	_clang = SomGerador.fonte("clang")
	add_child(_clang)
	_faiscas_muro = Explosao.faiscas_atrito()
	_faiscas_muro.position = Vector3(0.0, 0.25, 0.3)
	add_child(_faiscas_muro)

## Visual do carro em `pai`: casco do Eco Shell com a pintura [lataria, filete], três
## rodas, o número na traseira (0 = sem número) e o nome flutuando em cima. Também usado
## pelo espectador (carros vindos da telemetria). Precisa de preparar() antes.
## Devolve {giros: Array[Node3D] (rodas, para girar), nome: Label3D}
static func montar_visual(pai: Node3D, pintura: Array, texto_nome: String, numero_: int) -> Dictionary:
	var casco := MeshInstance3D.new()
	casco.mesh = _malha
	var tinta: ShaderMaterial = _tinta_base.duplicate()
	tinta.set_shader_parameter("cor_lataria", pintura[0])
	tinta.set_shader_parameter("cor_filete", pintura[1])
	casco.set_surface_override_material(0, tinta)
	pai.add_child(casco)

	var pneu := CylinderMesh.new()
	pneu.top_radius = RAIO_RODA
	pneu.bottom_radius = RAIO_RODA
	pneu.height = 0.11
	pneu.radial_segments = 18
	var borracha := StandardMaterial3D.new()
	borracha.albedo_color = Color(0.06, 0.06, 0.07)
	borracha.roughness = 0.9
	pneu.material = borracha
	var giros: Array[Node3D] = []
	for posicao: Vector3 in RODAS:
		var giro := Node3D.new()
		giro.position = posicao
		var roda := MeshInstance3D.new()
		roda.mesh = pneu
		roda.rotation.z = PI * 0.5
		giro.add_child(roda)
		pai.add_child(giro)
		giros.append(giro)

	# Número na traseira, legível para quem vem atrás
	if numero_ > 0:
		var placa := Label3D.new()
		placa.text = str(numero_)
		placa.font_size = 96
		placa.pixel_size = 0.003
		placa.outline_size = 18
		placa.modulate = pintura[1]
		placa.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		placa.double_sided = false
		placa.position = Vector3(0.0, 0.5, 1.33)
		pai.add_child(placa)

	# Nome flutuando em cima, sempre virado para quem olha
	var nome := Label3D.new()
	nome.text = texto_nome
	nome.font_size = 48
	nome.pixel_size = 0.004
	nome.outline_size = 10
	nome.modulate = pintura[1]
	nome.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.position = Vector3(0.0, 1.35, 0.0)
	nome.visibility_range_end = 45.0
	pai.add_child(nome)
	return {"giros": giros, "nome": nome}

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
	fantasma(false)
	turbos_usados = 0
	nitro = 0.0
	_tempo_turbo = 0.0
	_trilhas_turbo.visible = false
	salto_s = -INF
	_turbo = 0.0
	# Atrás da linha conta como negativo: ainda não começou a primeira volta
	progresso = pista.progresso_inicial(s)
	ia.parar()
	_posar()
	_sincronizar()

## Um passo de física: velocidade e faixa indo para os alvos, dentro dos limites
func mover(dt: float):
	_turbo = maxf(_turbo - dt, 0.0)
	var alvo_movimento := v_alvo
	var freio := perfil.frenagem
	var aceleracao := perfil.aceleracao
	if _tempo_turbo > 0.0:
		_tempo_turbo = maxf(_tempo_turbo - dt, 0.0)
		nitro = maxf(nitro - CONSUMO_TURBO * dt, 0.0)
		# Turbo: estica a reta até FATOR_TURBO x a máxima, freando a tempo das curvas
		var frente := 60.0 + v * v / (2.0 * perfil.frenagem)
		var seguro := pista.velocidade_segura(s, perfil.aderencia, perfil.frenagem, frente)
		alvo_movimento = maxf(v_alvo, minf(perfil.velocidade_max * FATOR_TURBO, seguro))
		aceleracao *= 3.0
	elif not terminou:
		nitro = minf(nitro + CARGA_PASSIVA * dt, TANQUE)
	_trilhas_turbo.visible = _tempo_turbo > 0.0
	# Turbo de placa e voo da rampa: a velocidade cai devagar, como no carro do jogador
	if _turbo > 0.0 or salto_s > -INF:
		alvo_movimento = maxf(alvo_movimento, v)
		freio = perfil.frenagem * 0.08
	v += clampf(alvo_movimento - v, -freio * dt, aceleracao * dt)
	v = maxf(v, 0.0)
	var agil := perfil.agilidade * agilidade_extra
	var desejada := clampf((d_alvo - d) * 2.5, -agil, agil)
	_vel_lateral = move_toward(_vel_lateral, desejada, 10.0 * dt)
	d += (_vel_lateral + _empurrao) * dt
	_empurrao = move_toward(_empurrao, 0.0, 5.0 * dt)
	# Muro: raspa, perde um pouco e para de ir para o lado
	var limite := pista.meia_util
	if absf(d) > limite:
		d = signf(d) * limite
		if v > 2.0:
			_no_muro = 0.25
			_lado_muro = signf(d)
		_empurrao = 0.0
		_vel_lateral = 0.0
		v *= 1.0 - 0.6 * dt
	var antes := s
	s = pista.avancar(s, v * dt)
	# Pista aberta: chegou na mureta do fim e parou
	if pista.aberta and s < antes + v * dt - 0.001:
		v = 0.0
	progresso += v * dt
	if pista.rampas:
		pista.rampas.passar(self, antes)
	_posar()
	for giro in _giros:
		giro.rotation.x -= v * dt / RAIO_RODA
	# Rodas da frente esterçam com o movimento lateral
	var esterco := clampf(-(_vel_lateral + _empurrao) / maxf(v, 2.0), -0.5, 0.5)
	_giros[0].rotation.y = esterco
	_giros[1].rotation.y = esterco
	_no_muro = maxf(_no_muro - dt, 0.0)
	_espera_passagem = maxf(_espera_passagem - dt, 0.0)
	_som()
	_sincronizar()

## Placa de turbo: garante `alvo` m/s e segura por um tempo
func turbo(alvo: float):
	v = maxf(v, alvo)
	_turbo = 2.5

## Mina: o turbo apaga na hora
func cortar_turbo():
	_tempo_turbo = 0.0
	_trilhas_turbo.visible = false

func pode_usar_turbo() -> bool:
	return _tempo_turbo <= 0.0 and nitro >= perfil.reserva_turbo and not terminou and v > 5.0

## Liga o turbo: gasta até DURACAO_TURBO s do tanque, com o ronco do nitro
func usar_turbo() -> bool:
	if not pode_usar_turbo():
		return false
	_tempo_turbo = minf(nitro / CONSUMO_TURBO, DURACAO_TURBO)
	turbos_usados += 1
	CarroFantasma.roncar(self, -8.0)
	# Rajada de faíscas na traseira, da cor do filete
	var rajada := Explosao.faiscas_impacto(6.0)
	Explosao._soltar(get_parent(), rajada, global_transform * Vector3(0.0, 0.3, 1.4), 0.8)
	var som := SomGerador.fonte("arrancada")
	som.volume_db = -8.0
	som.pitch_scale = randf_range(0.9, 1.08)
	som.max_distance = 45.0
	add_child(som)
	if som.stream:
		som.play()
		som.finished.connect(som.queue_free)
	else:
		som.queue_free()
	return true

## Batida vinda do tráfego: empurrão lateral (m/s, positivo = para a direita) e
## mudança de velocidade
func levar_batida(lateral: float, dv: float, forca: float, outro: CarroNaPista, culpado: bool):
	_empurrao = clampf(_empurrao + lateral, -4.0, 4.0)
	v = maxf(v + dv, 0.0)
	ia.notificar_batida(forca, outro, culpado)
	if forca <= 0.8:
		return
	if _batida.stream and not _batida.playing:
		_batida.volume_db = linear_to_db(clampf(forca / 5.0, 0.15, 1.0)) - 4.0
		_batida.pitch_scale = randf_range(0.9, 1.15)
		_batida.play()
	# Casco contra casco: clangor e faíscas do lado que bateu (empurrado para a
	# direita = bateu do lado esquerdo)
	if _clang.stream and forca > 1.5:
		_clang.volume_db = linear_to_db(clampf(forca / 6.0, 0.15, 0.9)) - 3.0
		_clang.pitch_scale = randf_range(0.85, 1.2)
		_clang.play()
	if forca > 1.5:
		var lado := -signf(lateral) if lateral != 0.0 else 1.0
		var ponto := global_transform * Vector3(lado * 0.45, 0.35, 0.0)
		Explosao._soltar(get_parent(), Explosao.faiscas_impacto(forca * 2.5), ponto, 1.0)

func _posar():
	var q := pista.quadro(s)
	# Aponta o bico para onde o carro está indo (frente + deslize lateral)
	var guinada := atan2(_vel_lateral + _empurrao, maxf(v, 1.5))
	var base := q.basis.rotated(q.basis.y, -guinada)
	var alto := pista.rampas.altura(self) if pista.rampas else 0.0
	global_transform = pista.global_transform * Transform3D(base, q.origin + q.basis.x * d + q.basis.y * alto)

func _sincronizar():
	info.s = s
	info.d = d
	info.v = v
	info.progresso = progresso

# --- Corrida em grupo -----------------------------------------------------------------

## Modo fantasma (já recebeu a bandeirada): meio transparente; quem tira a colisão
## com o jogador é o TrafegoCorrida
func fantasma(sim: bool):
	_transparencia(self, 0.55 if sim else 0.0)

func _transparencia(no: Node, valor: float):
	for filho in no.get_children():
		if filho is GeometryInstance3D and not filho is Label3D:
			filho.transparency = valor
		_transparencia(filho, valor)

## Fora do grid (no grupo sobram menos vagas para a IA): some, para e não colide
func ativar(sim: bool):
	visible = sim
	process_mode = Node.PROCESS_MODE_INHERIT if sim else Node.PROCESS_MODE_DISABLED
	collision_layer = 1 if sim else 0
	for som in [_motor, _rolamento, _raspagem]:
		if som:
			som.stream_paused = not sim

## Pose vinda do anfitrião (no relógio dele), com progresso e velocidade. A chegada é
## conferida aqui mesmo pelo progresso (TrafegoCorrida._ver_chegadas)
func receber_rede(t: float, pos: Vector3, rot: Quaternion, progresso_: float, v_: float):
	_interpolador.adicionar(t, pos, rot)
	progresso = progresso_
	v = v_

## Um passo de física de boneco: segue a pose interpolada (o corpo animável continua
## empurrando o carro do jogador), gira as rodas e faz o som
func seguir_rede(dt: float):
	_espera_passagem = maxf(_espera_passagem - dt, 0.0)
	if _interpolador.vazio():
		return
	global_transform = _interpolador.pose()
	for giro in _giros:
		giro.rotation.x -= v * dt / RAIO_RODA
	_som()
	_sincronizar()

## Este Quest virou o anfitrião: retoma a IA de onde o boneco está
func assumir():
	remoto = false
	var proj := pista.projetar(pista.to_local(global_position))
	s = proj.x
	d = proj.y
	d_alvo = d
	v_alvo = v
	_vel_lateral = 0.0
	_empurrao = 0.0
	_interpolador.limpar()
	_sincronizar()

## Motor elétrico (cada carro num tom: o pelotão soa como um enxame, não como um
## carro só), rolamento e raspagem no muro. A biblioteca de sons é gerada em segundo
## plano: entra quando estiver pronta
func _som():
	if _motor == null:
		if not SomGerador.biblioteca.has("motor_rival"):
			return
		_motor = _loop("motor_rival", 70.0)
		_rolamento = _loop("rolamento", 30.0)
		_raspagem = _loop("raspagem", 40.0)
		for p in [_batida, _clang]:
			if p.stream == null:
				p.stream = SomGerador.biblioteca.get("batida" if p == _batida else "clang")
	var rapidez := clampf(v / 34.0, 0.0, 1.4)
	var tom := 0.86 + 0.045 * (numero % 7)
	# Turbo: o motor grita mais agudo enquanto dura
	var grito := 0.25 if _tempo_turbo > 0.0 else 0.0
	_motor.pitch_scale = tom * (0.45 + 0.8 * rapidez + grito)
	_motor.volume_db = lerpf(-28.0, -9.0, minf(rapidez, 1.0)) + (3.0 if grito > 0.0 else 0.0)
	_rolamento.pitch_scale = 0.6 + rapidez * 0.7
	_rolamento.volume_db = lerpf(-40.0, -14.0, minf(rapidez, 1.0))
	var raspa := minf(_no_muro / 0.25, 1.0) * minf(rapidez, 1.0)
	_raspagem.volume_db = linear_to_db(maxf(raspa * 0.5, 0.0001))
	_raspagem.pitch_scale = 0.8 + rapidez * 0.4
	_faiscas_muro.emitting = raspa > 0.3
	_faiscas_muro.position.x = _lado_muro * 0.42
	_passagem()

## Passou rente pelo jogador (de frente para trás ou de trás para a frente) com
## diferença de velocidade: o ar rasgando, vindo deste carro
func _passagem():
	var jogador := get_tree().get_first_node_in_group("carro") as RigidBody3D
	if jogador == null or _espera_passagem > 0.0:
		return
	var rel := global_position - jogador.global_position
	if rel.length() > 8.0:
		_lado_jogador = 0.0
		return
	var frente := -jogador.global_basis.z
	var lado := signf(rel.dot(frente))
	var lateral := absf(rel.dot(jogador.global_basis.x))
	var diferenca := absf(v - jogador.linear_velocity.dot(frente))
	if _lado_jogador != 0.0 and lado != _lado_jogador and lateral < 3.5 and diferenca > 2.5:
		_espera_passagem = 1.5
		var som := SomGerador.tocar_em(self, global_position, "passagem", lerpf(-10.0, -2.0, clampf(diferenca / 10.0, 0.0, 1.0)), randf_range(0.9, 1.1), 4.0)
		if som:
			som.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	_lado_jogador = lado

func _loop(nome: String, alcance: float) -> AudioStreamPlayer3D:
	var p := SomGerador.fonte(nome)
	p.volume_db = -80.0
	p.max_distance = alcance
	add_child(p)
	p.play()
	return p
