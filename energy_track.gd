extends Node3D
## Rastro de energia estilo Tron: duas paredes de luz verticais saindo das pontas das
## asas do carro no modo planador. As paredes são sólidas: bater nelas (no chão ou
## voando) derruba o carro. Cada seção guarda o topo e a base das duas paredes; o
## rastro é dividido em trechos (StaticBody3D próprio com malha + colisão) para só
## reconstruir o trecho atual.

const TRACK_SHADER := preload("res://energy_track.gdshader")

## Altura da parede acima e abaixo da ponta da asa (m)
@export var acima := 0.6
@export var abaixo := 1.2
## Distância mínima entre seções (m)
@export var passo := 0.35
@export var secoes_por_trecho := 48
## Trechos mais antigos são apagados acima deste limite
@export var max_trechos := 150
@export_flags_3d_physics var camada_colisao := 2

## Cada seção: [topo esq., base esq., topo dir., base dir.]
var _secoes: Array[PackedVector3Array] = []
var _comprimentos := PackedFloat32Array()
var _origem := Vector3.ZERO
var _distancia := 0.0
var _trecho: StaticBody3D
var _trechos: Array[StaticBody3D] = []
var _material := ShaderMaterial.new()

func _ready():
	_material.shader = TRACK_SHADER

## Remove também a colisão imediatamente, antes da liberação no fim do frame.
func limpar():
	for corpo in _trechos:
		corpo.collision_layer = 0
		corpo.queue_free()
	_trechos.clear()
	_secoes.clear()
	_comprimentos.clear()
	_trecho = null
	_origem = Vector3.ZERO
	_distancia = 0.0

## t = transform do carro (a parede fica na vertical dele); pontas = pontas das asas
func comecar(t: Transform3D, pontas: Array[Vector3]):
	_secoes.clear()
	_comprimentos.clear()
	_novo_trecho()
	_adicionar_secao(t, pontas)

func adicionar(t: Transform3D, pontas: Array[Vector3]):
	if not _secoes.is_empty() and t.origin.distance_to(_origem) >= passo:
		_adicionar_secao(t, pontas)

func terminar(t: Transform3D, pontas: Array[Vector3]):
	if not _secoes.is_empty() and t.origin.distance_to(_origem) > 0.05:
		_adicionar_secao(t, pontas)
	_secoes.clear()
	_comprimentos.clear()

## Corpos do trecho atual e do anterior: as pontas das asas encostam neles o tempo
## todo, então a checagem de batida das asas precisa ignorá-los
func recentes() -> Array[RID]:
	var rids: Array[RID] = []
	for corpo in _trechos.slice(-2):
		rids.append(corpo.get_rid())
	return rids

func _adicionar_secao(t: Transform3D, pontas: Array[Vector3]):
	if not _secoes.is_empty():
		_distancia += t.origin.distance_to(_origem)
	_origem = t.origin
	var cima := t.basis.y.normalized()
	_secoes.append(PackedVector3Array([
		pontas[0] + cima * acima, pontas[0] - cima * abaixo,
		pontas[1] + cima * acima, pontas[1] - cima * abaixo]))
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
	var pos := PackedVector3Array()
	var normais := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var colisao := PackedVector3Array()

	# Uma fita vertical por asa; UV.x = altura (0 = topo, 1 = base), UV.y = metros
	for parede in 2:
		var base := pos.size()
		for i in _secoes.size():
			var topo := _secoes[i][parede * 2]
			var baixo := _secoes[i][parede * 2 + 1]
			var seguinte := _secoes[mini(i + 1, _secoes.size() - 1)][parede * 2]
			var anterior := _secoes[maxi(i - 1, 0)][parede * 2]
			var n := (seguinte - anterior).cross(topo - baixo).normalized()
			pos.append(topo)
			pos.append(baixo)
			normais.append(n)
			normais.append(n)
			uv.append(Vector2(0.0, _comprimentos[i]))
			uv.append(Vector2(1.0, _comprimentos[i]))
		for i in _secoes.size() - 1:
			var a := base + i * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
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
