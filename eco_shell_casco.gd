@tool
class_name CascoEcoShell
extends MeshInstance3D
## Casco do protótipo Eco Shell 326 (SENAI), gerado por loft.
## O perfil segue a espessura de um aerofólio NACA, com bico rombudo e cauda cheia
## arredondada como no carro real, e um domo no teto sobre a cabeça do piloto.
## UV.x = posição ao longo do carro (0 = bico, 1 = cauda), UV.y = cos do ângulo
## em volta da seção (1 = topo, -1 = fundo), usados pelo shader para pintar faixas.
##
## Superfícies: 0 = lataria (por fora), 1 = interior (mesmos triângulos virados para
## dentro, assim adesivos não aparecem espelhados no cockpit), 2 = vidros.
##
## Dano: marcar() guarda onde o carro bateu; o shader da lataria amassa e arranha em
## volta, e o do vidro trinca. consertar() limpa tudo (quando o carro renasce).

const SHELL_SHADER := preload("res://eco_shell_casco.gdshader")
const VIDRO_SHADER := preload("res://vidro.gdshader")

enum { LATARIA, VIDRO, ABERTO }

@export var comprimento := 2.6:
	set(v): comprimento = v; _construir()
@export var largura := 0.72:
	set(v): largura = v; _construir()
## Altura do eixo do casco em relação ao chão
@export var centro := 0.3:
	set(v): centro = v; _construir()
@export var altura_cima := 0.42:
	set(v): altura_cima = v; _construir()
@export var altura_baixo := 0.22:
	set(v): altura_baixo = v; _construir()
## 2 = seção elíptica; valores maiores deixam a seção mais "quadrada"
@export var quadratura := 2.5:
	set(v): quadratura = v; _construir()
## Espessura (0-1) que o bico arredondado alcança em `comprimento_bico`; mais = mais rombudo
@export var rombudo_bico := 0.9:
	set(v): rombudo_bico = v; _construir()
@export var comprimento_bico := 0.1:
	set(v): comprimento_bico = v; _construir()
## Espessura mínima (0-1) da metade de trás; fecha arredondada a partir de `inicio_cauda`
@export var cauda_minima := 0.8:
	set(v): cauda_minima = v; _construir()
@export var inicio_cauda := 0.8:
	set(v): inicio_cauda = v; _construir()
## Domo do teto sobre a cabeça: centro em Z, meia largura, meio comprimento
@export var domo := Vector3(0.05, 0.35, 0.8):
	set(v): domo = v; _construir()
@export var domo_altura := 0.2:
	set(v): domo_altura = v; _construir()
## Vidro dianteiro no teto, elíptico (centro em Z, meia largura, meio comprimento)
@export var cockpit := Vector3(-0.4, 0.22, 0.62):
	set(v): cockpit = v; _construir()
## Janelas laterais elípticas (centro em Z, centro em Y, meio comprimento, meia altura)
@export var janela_lateral := Vector4(0.03, 0.45, 0.36, 0.08):
	set(v): janela_lateral = v; _construir()
## Recorte do para-lama dianteiro em volta da roda (centro em Z, centro em Y, raio, |x| mínimo)
@export var para_lama := Vector4(-0.75, 0.245, 0.27, 0.22):
	set(v): para_lama = v; _construir()
@export var secoes := 112
@export var lados := 72

## Quantas marcas de batida (amassados) e trincas no vidro ficam ao mesmo tempo
const MAX_MARCAS := 6

var material_casco := ShaderMaterial.new()
var _material_interior := ShaderMaterial.new()
var _material_vidro := ShaderMaterial.new()
## xyz = ponto no espaço do casco, w = intensidade (0 = sem marca)
var _marcas := PackedVector4Array()
var _trincas := PackedVector4Array()

## Batida em `ponto` (espaço do casco) com intensidade 0 a 1: amassa a lataria ali e
## trinca o vidro na região mais próxima do lado da batida. Cheio, troca a mais antiga.
func marcar(ponto: Vector3, intensidade: float):
	_marcas.append(Vector4(ponto.x, ponto.y, ponto.z, intensidade))
	# O vidro fica no teto: a trinca vai para o ponto do vidro mais perto da batida
	var z := clampf(ponto.z, cockpit.x - cockpit.z * 0.8, cockpit.x + cockpit.z * 0.8)
	var x := clampf(ponto.x, -cockpit.y * 0.75, cockpit.y * 0.75)
	_trincas.append(Vector4(x, topo(z), z, intensidade))
	if _marcas.size() > MAX_MARCAS:
		_marcas.remove_at(0)
		_trincas.remove_at(0)
	_enviar_marcas()

func consertar():
	_marcas.clear()
	_trincas.clear()
	_enviar_marcas()

func _enviar_marcas():
	var marcas := _marcas.duplicate()
	var trincas := _trincas.duplicate()
	marcas.resize(MAX_MARCAS)
	trincas.resize(MAX_MARCAS)
	material_casco.set_shader_parameter("marcas", marcas)
	_material_interior.set_shader_parameter("marcas", marcas)
	_material_vidro.set_shader_parameter("trincas", trincas)

func _ready():
	material_casco.shader = SHELL_SHADER
	_material_interior.shader = SHELL_SHADER
	_material_interior.set_shader_parameter("interior", true)
	_material_vidro.shader = VIDRO_SHADER
	_construir()

func _construir():
	if not is_inside_tree() or material_casco.shader == null:
		return
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()

	# Anéis ao longo do comprimento, mais densos no bico e na cauda
	for i in secoes + 1:
		var t: float = lerp(0.002, 1.0, 0.5 - 0.5 * cos(PI * i / secoes))
		var secao := _secao(t)
		var z := (t - 0.5) * comprimento
		for j in lados:
			var a := TAU * j / lados
			var c := cos(a)
			var x := secao.x * _superelipse(sin(a))
			var y := centro + (secao.y if c >= 0.0 else secao.z) * _superelipse(c)
			if c > 0.0:
				y += _domo(x, z) * pow(c, 1.5)
			pos.append(Vector3(x, y, z))
			uv.append(Vector2(t, c))

	var fora := PackedInt32Array()
	var vidro := PackedInt32Array()
	for i in secoes:
		for j in lados:
			var a := i * lados + j
			var b := i * lados + (j + 1) % lados
			# Quad na borda de uma abertura vai para as duas superfícies; o shader de
			# cada uma recorta o seu lado da borda exata
			var regioes := {}
			for k in [a, b, a + lados, b + lados]:
				regioes[_regiao(pos[k])] = true
			regioes[_regiao((pos[a] + pos[b + lados]) * 0.5)] = true
			if regioes.has(LATARIA) or regioes.size() > 1:
				_tri(fora, pos, a, a + lados, b)
				_tri(fora, pos, b, a + lados, b + lados)
			if regioes.has(VIDRO):
				_tri(vidro, pos, a, a + lados, b)
				_tri(vidro, pos, b, a + lados, b + lados)

	# Tampas: ponta do bico e fim da cauda
	var bico := pos.size()
	pos.append(Vector3(0, centro, -comprimento * 0.5))
	uv.append(Vector2(0, 0))
	var cauda := pos.size()
	var ultimo := secoes * lados
	pos.append(Vector3(0, centro, comprimento * 0.5))
	uv.append(Vector2(1, 0))
	for j in lados:
		var k := (j + 1) % lados
		_tri(fora, pos, bico, j, k)
		_tri(fora, pos, cauda, ultimo + k, ultimo + j)

	# Normais suaves somando lataria e vidro, para não marcar a borda das janelas
	var normais := PackedVector3Array()
	normais.resize(pos.size())
	for lista in [fora, vidro]:
		for f in range(0, lista.size(), 3):
			var p0 := pos[lista[f]]
			var n := (pos[lista[f + 2]] - p0).cross(pos[lista[f + 1]] - p0)
			for k in 3:
				normais[lista[f + k]] += n
	var normais_dentro := PackedVector3Array()
	normais_dentro.resize(pos.size())
	for v in normais.size():
		normais[v] = normais[v].normalized()
		normais_dentro[v] = -normais[v]
	var dentro := PackedInt32Array()
	for f in range(0, fora.size(), 3):
		dentro.append_array([fora[f], fora[f + 2], fora[f + 1]])

	var m := ArrayMesh.new()
	_superficie(m, pos, normais, uv, fora, material_casco)
	_superficie(m, pos, normais_dentro, uv, dentro, _material_interior)
	_superficie(m, pos, normais, uv, vidro, _material_vidro)
	mesh = m

	for material in [material_casco, _material_interior, _material_vidro]:
		material.set_shader_parameter("centro_y", centro)
		material.set_shader_parameter("vidro", cockpit)
		material.set_shader_parameter("janela", janela_lateral)
		material.set_shader_parameter("para_lama", para_lama)
	# Acessórios do teto (alça, cinta) assentam na lataria
	for filho in get_children():
		if filho is Node3D and filho.has_meta("no_teto"):
			filho.position.y = topo(filho.position.z)

## Altura do teto (na linha do meio) na posição Z do carro
func topo(z: float) -> float:
	var t := clampf(z / comprimento + 0.5, 0.0, 1.0)
	return centro + _secao(t).y + _domo(0.0, z)

## Meia largura, altura para cima e para baixo do eixo, na posição t (0 = bico)
func _secao(t: float) -> Vector3:
	var s: float = max(_espessura(t) / _espessura(0.3), 0.0)
	if t < 0.3:
		var b := 1.0 - minf(t / comprimento_bico, 1.0)
		s = max(s, rombudo_bico * sqrt(1.0 - b * b))
	elif t > 0.5:
		var r := maxf(t - inicio_cauda, 0.0) / (1.0 - inicio_cauda)
		s = max(s, cauda_minima * sqrt(maxf(1.0 - r * r, 0.0)))
	return Vector3(largura * 0.5 * pow(s, 0.7), altura_cima * pow(s, 0.5), altura_baixo * pow(s, 0.5))

func _domo(x: float, z: float) -> float:
	var d := pow(x / domo.y, 2.0) + pow((z - domo.x) / domo.z, 2.0)
	return domo_altura * (1.0 - smoothstep(0.0, 1.0, d))

## Mesmas regras de eco_shell_aberturas.gdshaderinc
func _regiao(p: Vector3) -> int:
	var lado := absf(p.x)
	var dz := p.z - para_lama.x
	var dy := p.y - para_lama.y
	if lado > para_lama.w and dz * dz + dy * dy < para_lama.z * para_lama.z:
		return ABERTO
	if p.y > centro + 0.1 and pow(p.x / cockpit.y, 2.0) + pow((p.z - cockpit.x) / cockpit.z, 2.0) < 1.0:
		return VIDRO
	if lado > 0.1 and pow((p.z - janela_lateral.x) / janela_lateral.z, 2.0) + pow((p.y - janela_lateral.y) / janela_lateral.w, 2.0) < 1.0:
		return VIDRO
	return LATARIA

func _superficie(m: ArrayMesh, pos: PackedVector3Array, normais: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, material: Material):
	if idx.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normais
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.surface_set_material(m.get_surface_count() - 1, material)

## Godot considera frente o triângulo em sentido horário: garante isso
## comparando com a direção para fora do eixo do casco.
func _tri(idx: PackedInt32Array, pos: PackedVector3Array, a: int, b: int, c: int):
	var n := (pos[b] - pos[a]).cross(pos[c] - pos[a])
	var centroide := (pos[a] + pos[b] + pos[c]) / 3.0
	var fora := centroide - Vector3(0, centro, clamp(centroide.z, -comprimento * 0.45, comprimento * 0.45))
	if n.dot(fora) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])

func _superelipse(v: float) -> float:
	return sign(v) * pow(abs(v), 2.0 / quadratura)

func _espessura(t: float) -> float:
	return 0.2969 * sqrt(t) - 0.1260 * t - 0.3516 * t * t + 0.2843 * t * t * t - 0.1015 * t * t * t * t
