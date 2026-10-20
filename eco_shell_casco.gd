@tool
extends MeshInstance3D
## Casco aerodinâmico em gota do protótipo Eco Shell, gerado por loft.
## O perfil segue a espessura de um aerofólio NACA (máximo a 30% do comprimento).
## UV.x = posição ao longo do carro (0 = bico, 1 = cauda), UV.y = cos do ângulo
## em volta da seção (1 = topo, -1 = fundo), usados pelo shader para pintar faixas.

const SHELL_SHADER := preload("res://eco_shell_casco.gdshader")

@export var comprimento := 2.6:
	set(v): comprimento = v; _construir()
@export var largura := 0.72:
	set(v): largura = v; _construir()
## Altura do eixo do casco em relação ao chão
@export var centro := 0.3:
	set(v): centro = v; _construir()
@export var altura_cima := 0.34:
	set(v): altura_cima = v; _construir()
@export var altura_baixo := 0.22:
	set(v): altura_baixo = v; _construir()
## 2 = seção elíptica; valores maiores deixam a seção mais "quadrada"
@export var quadratura := 2.5:
	set(v): quadratura = v; _construir()
## Abertura elíptica do cockpit no topo (centro em Z, meia largura, meio comprimento)
@export var cockpit := Vector3(-0.1, 0.2, 0.4):
	set(v): cockpit = v; _construir()
@export var secoes := 56
@export var lados := 36

func _ready():
	_construir()

func _construir():
	if not is_inside_tree():
		return
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	# Anéis ao longo do comprimento, mais densos no bico e na cauda
	for i in secoes + 1:
		var t: float = lerp(0.002, 1.0, 0.5 - 0.5 * cos(PI * i / secoes))
		var s: float = max(_espessura(t) / _espessura(0.3), 0.0)
		var meia_largura := largura * 0.5 * pow(s, 0.7)
		var cima := altura_cima * pow(s, 0.5)
		var baixo := altura_baixo * pow(s, 0.5)
		var z := (t - 0.5) * comprimento
		for j in lados:
			var a := TAU * j / lados
			var c := cos(a)
			var x := meia_largura * _superelipse(sin(a))
			var y := centro + (cima if c >= 0.0 else baixo) * _superelipse(c)
			pos.append(Vector3(x, y, z))
			uv.append(Vector2(t, c))

	for i in secoes:
		for j in lados:
			var a := i * lados + j
			var b := i * lados + (j + 1) % lados
			if _no_cockpit((pos[a] + pos[b + lados]) * 0.5, uv[a].y + uv[b].y):
				continue
			_tri(idx, pos, a, a + lados, b)
			_tri(idx, pos, b, a + lados, b + lados)

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
		_tri(idx, pos, bico, j, k)
		_tri(idx, pos, cauda, ultimo + k, ultimo + j)

	var normais := PackedVector3Array()
	normais.resize(pos.size())
	for f in range(0, idx.size(), 3):
		var p0 := pos[idx[f]]
		var n := (pos[idx[f + 2]] - p0).cross(pos[idx[f + 1]] - p0)
		for k in 3:
			normais[idx[f + k]] += n
	for v in normais.size():
		normais[v] = normais[v].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normais
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = SHELL_SHADER
		material_override = mat
	mesh = m

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

func _no_cockpit(p: Vector3, topo: float) -> bool:
	if topo <= 0.0:
		return false
	var dx := p.x / cockpit.y
	var dz := (p.z - cockpit.x) / cockpit.z
	return dx * dx + dz * dz < 1.0

func _superelipse(v: float) -> float:
	return sign(v) * pow(abs(v), 2.0 / quadratura)

func _espessura(t: float) -> float:
	return 0.2969 * sqrt(t) - 0.1260 * t - 0.3516 * t * t + 0.2843 * t * t * t - 0.1015 * t * t * t * t
