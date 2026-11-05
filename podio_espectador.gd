class_name PodioEspectador
extends Node3D
## Pódio do fim da corrida no telão: três blocos low-poly escuros com a borda neon em
## ouro, prata e bronze (1º no meio e mais alto, 2º à esquerda e 3º à direita de quem
## olha da pista), montado ao lado da linha de chegada, virado para a pista. Em cima de
## cada bloco o carro de quem chegou naquela posição, com a pintura dele, e uma placa com
## o nome (★ para jogador real) e o tempo. Confete caindo. A câmera passeia num arco na
## frente dele (pose_camera). Criado pelo espectador só durante o pódio.

const ALTURAS := [1.7, 1.15, 0.8]
const LARGURA := 4.4
const PROFUNDIDADE := 4.0
## Distância da borda da pista até a frente do pódio (m)
const AFASTAMENTO := 16.0
const CORES := [TemaEvento.OURO, TemaEvento.PRATA, TemaEvento.BRONZE]
## Arco da câmera (rad para cada lado), raio e altura (m)
const ARCO := 0.75
const RAIO_CAMERA := 15.0
const ALTURA_CAMERA := 4.5

## Centro do pódio no chão e a direção em que ele olha (para a pista)
var centro := Vector3.ZERO
var frente := Vector3.FORWARD

## `pista` do mapa em foco; `lugares` até 3 de {nome, real, pintura, numero, tempo}.
## Fica ao lado da linha de chegada (na sprint) ou da largada (no circuito), do lado do
## miolo no circuito
func montar(pista: PistaCorrida, lugares: Array):
	var s := pista.s_chegada if pista.aberta else pista.s_largada
	var q := pista.global_transform * pista.quadro(s)
	var lado := Vector3(q.basis.x.x, 0.0, q.basis.x.z).normalized()
	var sinal := 1.0
	if not pista.aberta:
		var meio := Vector3.ZERO
		for i in range(0, PistaCorrida.AMOSTRAS, 24):
			meio += pista.global_transform * pista.pontos[i]
		meio /= float(PistaCorrida.AMOSTRAS / 24)
		sinal = 1.0 if lado.dot(meio - q.origin) >= 0.0 else -1.0
	var base := q.origin + lado * sinal * (pista.largura * 0.5 + AFASTAMENTO + PROFUNDIDADE * 0.5)
	base.y = _chao(base, q.origin.y)
	centro = base
	frente = -lado * sinal
	# Quem olha da pista: direita dele = frente x cima invertido
	var direita := (-frente).cross(Vector3.UP).normalized()
	var giro := Basis.looking_at(frente, Vector3.UP)
	# 1º no meio, 2º à esquerda, 3º à direita
	var deslocamentos := [0.0, -LARGURA, LARGURA]
	for k in 3:
		var origem: Vector3 = base + direita * float(deslocamentos[k])
		_bloco(origem, giro, k)
		if k < lugares.size():
			_lugar(origem + Vector3.UP * float(ALTURAS[k]), giro, k, lugares[k])
	_confete()

## Pose da câmera no instante `u` (0 a 1) do pódio: arco na frente, olhando o 1º lugar
func pose_camera(u: float) -> Transform3D:
	var a := lerpf(-ARCO, ARCO, smoothstep(0.0, 1.0, u))
	var dir := frente.rotated(Vector3.UP, a)
	var posicao := centro + dir * RAIO_CAMERA + Vector3.UP * ALTURA_CAMERA
	var mira := centro + Vector3.UP * (float(ALTURAS[0]) + 0.6)
	return Transform3D(Basis.looking_at(mira - posicao, Vector3.UP), posicao)

func _bloco(origem: Vector3, giro: Basis, k: int):
	var altura: float = ALTURAS[k]
	var caixa := BoxMesh.new()
	caixa.size = Vector3(LARGURA - 0.15, altura, PROFUNDIDADE)
	var corpo := MeshInstance3D.new()
	corpo.mesh = LowPoly.facetar(caixa)
	corpo.material_override = LowPoly.liso(Color(0.08, 0.09, 0.13))
	corpo.transform = Transform3D(giro, origem + Vector3.UP * altura * 0.5)
	add_child(corpo)
	# Borda neon no topo e o número na frente
	var borda := BoxMesh.new()
	borda.size = Vector3(LARGURA - 0.05, 0.08, PROFUNDIDADE + 0.1)
	var filete := MeshInstance3D.new()
	filete.mesh = borda
	filete.material_override = LowPoly.neon(CORES[k], 3.0)
	filete.transform = Transform3D(giro, origem + Vector3.UP * altura)
	add_child(filete)
	var numero := Label3D.new()
	numero.text = str(k + 1)
	numero.font_size = 220
	numero.pixel_size = 0.006
	numero.modulate = CORES[k]
	numero.outline_size = 0
	numero.shaded = false
	numero.transform = Transform3D(giro, origem + Vector3.UP * altura * 0.5 + giro * Vector3(0.0, 0.0, -PROFUNDIDADE * 0.5 - 0.02))
	numero.rotate_object_local(Vector3.UP, PI)
	add_child(numero)

func _lugar(topo: Vector3, giro: Basis, k: int, lugar: Dictionary):
	var real: bool = lugar.get("real", false)
	var carro := CarroFantasma.new(lugar.get("pintura", CarroRival.PINTURAS[0]), str(lugar.get("nome", "")), int(lugar.get("numero", 0)), real)
	carro.rotulo.visible = false
	add_child(carro)
	# Bico virado para a pista (para a câmera)
	carro.global_transform = Transform3D(Basis.looking_at(frente, Vector3.UP), topo + Vector3.UP * 0.05)
	var placa := Label3D.new()
	var nome := str(lugar.get("nome", "")).to_upper()
	var tempo: float = lugar.get("tempo", -1.0)
	placa.text = ("★ " if real else "") + nome + ("\n" + Ranking.formatar_tempo(tempo) if tempo > 0.0 else "")
	placa.font_size = 96
	placa.pixel_size = 0.009
	placa.outline_size = 22
	placa.modulate = Color.WHITE if k > 0 else CORES[0].lerp(Color.WHITE, 0.35)
	placa.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	placa.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	placa.no_depth_test = true
	placa.position = topo + Vector3.UP * 2.6
	placa.position = to_local(placa.position)
	add_child(placa)

## Altura do chão no ponto (mundo): raio de cima para baixo; sem chão, a da pista
func _chao(p: Vector3, padrao: float) -> float:
	var espaco := get_world_3d().direct_space_state
	var consulta := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 60.0, 1)
	var achou := espaco.intersect_ray(consulta)
	return achou.position.y if not achou.is_empty() else padrao

func _confete():
	var particulas := GPUParticles3D.new()
	particulas.amount = 220
	particulas.lifetime = 5.0
	particulas.preprocess = 2.0
	particulas.visibility_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 16.0, 24.0))
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(LARGURA * 1.8, 0.5, PROFUNDIDADE)
	material.direction = Vector3.DOWN
	material.spread = 25.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.gravity = Vector3(0.0, -1.6, 0.0)
	material.angular_velocity_min = -360.0
	material.angular_velocity_max = 360.0
	var cores := Gradient.new()
	cores.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	cores.colors = PackedColorArray([TemaEvento.OURO, TemaEvento.CIANO, TemaEvento.QUENTE, TemaEvento.VERDE, Color(1.0, 0.4, 0.8)])
	var rampa := GradientTexture1D.new()
	rampa.gradient = cores
	material.color_initial_ramp = rampa
	particulas.process_material = material
	var papel := QuadMesh.new()
	papel.size = Vector2(0.16, 0.1)
	var tinta := StandardMaterial3D.new()
	tinta.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tinta.vertex_color_use_as_albedo = true
	tinta.cull_mode = BaseMaterial3D.CULL_DISABLED
	papel.material = tinta
	particulas.draw_pass_1 = papel
	add_child(particulas)
	particulas.global_position = centro + Vector3.UP * 9.0
