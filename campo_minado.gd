class_name CampoMinado
extends ObstaculoPista
## Campo de minas terrestres pequenas espalhadas pela pista (I de Incrível). Cada mina
## é um disco baixo com uma luz vermelha piscando em cima e um halo no asfalto; as
## fileiras piscam em sequência, puxando o olho para a frente. Quem passa por cima
## detona: explosão pequena, um pulinho, 1 barra de dano, e a mina some até se rearmar.
## As minas ficam desencontradas entre as fileiras, mas sempre sobra pelo menos uma
## faixa reta livre (os adversários atravessam numa faixa só, ver ObstaculosPista).

## Raio do disco da mina (m)
const RAIO := 0.38
## Quanto tempo a mina detonada leva para voltar (s)
const REARME := 6.0
## Piscada: período (s), quanto dele a luz fica acesa e o atraso entre fileiras
const PERIODO := 0.9
const ACESA := 0.22
const ATRASO_FILEIRA := 0.15
## Pulinho que a explosão dá no carro do jogador (m/s): baixo, por causa da VR
const PULO := 2.5
const COR_LUZ := Color(1.0, 0.06, 0.03)

## (ds, d) de cada mina em volta do centro do campo (m)
var minas: Array[Vector2] = []
var _detonada: Array[float] = []
var _corpos: Array[Node3D] = []
## Uma luz e um halo por fileira (mesmo ds), piscando juntos
var _fileira: Array[int] = []
var _luzes: Array[StandardMaterial3D] = []
var _halos: Array[StandardMaterial3D] = []

func _init(minas_: Array[Vector2] = []):
	minas = minas_
	aviso = "CAMPO MINADO"
	aviso_batida = "MINA!"
	var longe := 0.0
	for m in minas:
		longe = maxf(longe, absf(m.x))
		_detonada.append(-INF)
	alcance_s = longe + RAIO + MEIO_CARRO

func _ready():
	var casco := material_metal(Color(0.16, 0.17, 0.14), 0.7, 0.5)
	var tampa := material_metal(Color(0.32, 0.3, 0.26), 0.8, 0.35)
	var corpo := CylinderMesh.new()
	corpo.top_radius = RAIO * 0.85
	corpo.bottom_radius = RAIO
	corpo.height = 0.1
	corpo.radial_segments = 12
	corpo.rings = 1
	corpo.material = casco
	var topo := CylinderMesh.new()
	topo.top_radius = RAIO * 0.5
	topo.bottom_radius = RAIO * 0.6
	topo.height = 0.06
	topo.radial_segments = 10
	topo.rings = 1
	topo.material = tampa
	var bolinha := Explosao._bolinha()
	var linhas := {}
	for k in minas.size():
		var m := minas[k]
		if not linhas.has(m.x):
			linhas[m.x] = _luzes.size()
			_luzes.append(material_luz(COR_LUZ, 6.0))
			var halo := StandardMaterial3D.new()
			halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			halo.albedo_texture = bolinha
			halo.albedo_color = Color(COR_LUZ.r * 1.5, COR_LUZ.g, COR_LUZ.b, 0.0)
			_halos.append(halo)
		_fileira.append(linhas[m.x])
		var mina := Node3D.new()
		mina.name = "Mina%d" % k
		mina.position = Vector3(m.y, 0.0, -m.x)
		mina.rotation.y = k * 1.3
		add_child(mina)
		_corpos.append(mina)
		var base := MeshInstance3D.new()
		base.mesh = corpo
		base.position.y = 0.05
		mina.add_child(base)
		var cima := MeshInstance3D.new()
		cima.mesh = topo
		cima.position.y = 0.13
		mina.add_child(cima)
		var lampada := MeshInstance3D.new()
		var esfera := SphereMesh.new()
		esfera.radius = 0.07
		esfera.height = 0.1
		esfera.radial_segments = 8
		esfera.rings = 4
		esfera.material = _luzes[_fileira[k]]
		lampada.mesh = esfera
		lampada.position.y = 0.18
		lampada.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mina.add_child(lampada)
		var chao := MeshInstance3D.new()
		var plano := PlaneMesh.new()
		plano.size = Vector2(RAIO * 5.0, RAIO * 5.0)
		plano.material = _halos[_fileira[k]]
		chao.mesh = plano
		chao.position.y = 0.025
		chao.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mina.add_child(chao)
	animar(0.0)

func armada(k: int, t: float) -> bool:
	return t - _detonada[k] >= REARME

## Mina armada encostando no carro em (ds, d), ou -1
func mina_em(ds: float, d: float, t: float) -> int:
	for k in minas.size():
		var m := minas[k]
		if absf(ds - m.x) < RAIO + MEIO_CARRO and absf(d - m.y) < RAIO + MEIA_LARGURA_CARRO and armada(k, t):
			return k
	return -1

func bloqueia(ds: float, d: float, t: float) -> bool:
	return mina_em(ds, d, t) >= 0

func lado_empurrao(ds: float, d: float, t: float) -> float:
	var k := mina_em(ds, d, t)
	if k < 0:
		return super(ds, d, t)
	return 1.0 if d >= minas[k].y else -1.0

func animar(t: float):
	for f in _luzes.size():
		var fase := fposmod(t - f * ATRASO_FILEIRA, PERIODO)
		var acesa := 1.0 - smoothstep(0.0, ACESA, fase)
		_luzes[f].emission_energy_multiplier = 0.4 + 7.0 * acesa
		_halos[f].albedo_color.a = 0.08 + 0.7 * acesa
	for k in minas.size():
		_corpos[k].visible = armada(k, t)

func atingido(ds: float, d: float, t: float, carro: RigidBody3D):
	var k := mina_em(ds, d, t)
	if k < 0:
		return
	_detonada[k] = t
	_corpos[k].visible = false
	if is_inside_tree():
		var explosao := Explosao.new()
		explosao.escala = 0.35
		explosao.com_pedacos = false
		add_child(explosao)
		explosao.position = _corpos[k].position + Vector3.UP * 0.2
	if carro:
		carro.linear_velocity += Vector3.UP * PULO
