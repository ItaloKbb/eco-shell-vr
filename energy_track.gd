extends Node3D
## Pista de energia estilo Tron, gerada seção a seção embaixo do carro.
## Cada seção é o transform do ponto de contato das rodas; a pista é dividida em
## trechos (StaticBody3D próprio com malha + colisão) para só reconstruir o trecho atual.

const TRACK_SHADER := preload("res://energy_track.gdshader")

@export var largura := 1.1
@export var espessura := 0.06
## Distância mínima entre seções (m)
@export var passo := 0.35
@export var secoes_por_trecho := 48
## Trechos mais antigos são apagados acima deste limite
@export var max_trechos := 150
@export_flags_3d_physics var camada_colisao := 2

var _secoes: Array[Transform3D] = []
var _comprimentos := PackedFloat32Array()
var _distancia := 0.0
var _trecho: StaticBody3D
var _trechos: Array[StaticBody3D] = []
var _material := ShaderMaterial.new()

func _ready():
	_material.shader = TRACK_SHADER

func comecar(t: Transform3D):
	_secoes.clear()
	_comprimentos.clear()
	_novo_trecho()
	_adicionar_secao(t)

func adicionar(t: Transform3D):
	if not _secoes.is_empty() and t.origin.distance_to(_secoes[-1].origin) >= passo:
		_adicionar_secao(t)

func terminar(t: Transform3D):
	if not _secoes.is_empty() and t.origin.distance_to(_secoes[-1].origin) > 0.05:
		_adicionar_secao(t)
	_secoes.clear()
	_comprimentos.clear()

func _adicionar_secao(t: Transform3D):
	if not _secoes.is_empty():
		_distancia += t.origin.distance_to(_secoes[-1].origin)
	_secoes.append(t.orthonormalized())
	_comprimentos.append(_distancia)
	if _secoes.size() >= 2:
		_reconstruir()
	# Trecho cheio: o próximo começa na última seção, sem emenda visível
	if _secoes.size() >= secoes_por_trecho:
		var ultima := _secoes[-1]
		_secoes.clear()
		_secoes.append(ultima)
		_comprimentos = PackedFloat32Array([_distancia])
		_novo_trecho()

func _novo_trecho():
	_trecho = StaticBody3D.new()
	_trecho.collision_layer = camada_colisao
	_trecho.collision_mask = 0
	var malha := MeshInstance3D.new()
	malha.material_override = _material
	malha.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trecho.add_child(malha)
	var forma := CollisionShape3D.new()
	var concava := ConcavePolygonShape3D.new()
	concava.backface_collision = true
	forma.shape = concava
	_trecho.add_child(forma)
	add_child(_trecho)
	_trechos.append(_trecho)
	while _trechos.size() > max_trechos:
		_trechos.pop_front().queue_free()

func _reconstruir():
	var meia := largura * 0.5
	# Faixas da seção transversal: [ponto a, ponto b, normal, u de a, u de b]
	var faixas := [
		[Vector3(-meia, 0, 0), Vector3(meia, 0, 0), Vector3.UP, 0.0, 1.0],
		[Vector3(meia, -espessura, 0), Vector3(-meia, -espessura, 0), Vector3.DOWN, 1.0, 0.0],
		[Vector3(meia, 0, 0), Vector3(meia, -espessura, 0), Vector3.RIGHT, 1.0, 1.0],
		[Vector3(-meia, -espessura, 0), Vector3(-meia, 0, 0), Vector3.LEFT, 0.0, 0.0],
	]
	var pos := PackedVector3Array()
	var normais := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var colisao := PackedVector3Array()

	for f in faixas.size():
		var faixa: Array = faixas[f]
		var base := pos.size()
		for i in _secoes.size():
			var t := _secoes[i]
			pos.append(t * faixa[0])
			pos.append(t * faixa[1])
			var n: Vector3 = t.basis * faixa[2]
			normais.append(n)
			normais.append(n)
			uv.append(Vector2(faixa[3], _comprimentos[i]))
			uv.append(Vector2(faixa[4], _comprimentos[i]))
		for i in _secoes.size() - 1:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
			# Só o topo precisa de colisão (backface_collision cobre o outro lado)
			if f == 0:
				colisao.append_array([pos[a], pos[a + 1], pos[a + 2], pos[a + 1], pos[a + 3], pos[a + 2]])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normais
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	(_trecho.get_child(0) as MeshInstance3D).mesh = m
	((_trecho.get_child(1) as CollisionShape3D).shape as ConcavePolygonShape3D).set_faces(colisao)
