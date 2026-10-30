extends Node3D
## Rastro do nitro: uma linha de luz estilo Tron saindo do centro da traseira do carro
## enquanto o nitro está ligado. Só visual (sem colisão: não atrapalha ninguém). Cada
## seção guarda o topo e a base da fita; o rastro é dividido em trechos (malha própria)
## para só reconstruir o trecho atual, e os mais antigos somem acima de max_trechos.

const TRACK_SHADER := preload("res://energy_track.gdshader")

## Altura da fita acima e abaixo do ponto da traseira (m): uma linha fina
@export var acima := 0.05
@export var abaixo := 0.12
## Distância mínima entre seções (m)
@export var passo := 0.35
@export var secoes_por_trecho := 48
## Trechos mais antigos são apagados acima deste limite (~17 m cada)
@export var max_trechos := 8

## Cada seção: [topo, base]
var _secoes: Array[PackedVector3Array] = []
var _comprimentos := PackedFloat32Array()
var _origem := Vector3.ZERO
var _distancia := 0.0
var _trecho: MeshInstance3D
var _trechos: Array[MeshInstance3D] = []
var _material := ShaderMaterial.new()

func _ready():
	_material.shader = TRACK_SHADER

func limpar():
	for trecho in _trechos:
		trecho.queue_free()
	_trechos.clear()
	_secoes.clear()
	_comprimentos.clear()
	_trecho = null
	_origem = Vector3.ZERO
	_distancia = 0.0

## `ponto`: centro da traseira; `cima`: vertical do carro (a fita fica em pé nela)
func comecar(ponto: Vector3, cima: Vector3):
	_secoes.clear()
	_comprimentos.clear()
	_novo_trecho()
	_adicionar_secao(ponto, cima)

func adicionar(ponto: Vector3, cima: Vector3):
	if not _secoes.is_empty() and ponto.distance_to(_origem) >= passo:
		_adicionar_secao(ponto, cima)

func terminar(ponto: Vector3, cima: Vector3):
	if not _secoes.is_empty() and ponto.distance_to(_origem) > 0.05:
		_adicionar_secao(ponto, cima)
	_secoes.clear()
	_comprimentos.clear()

func _adicionar_secao(ponto: Vector3, cima: Vector3):
	if not _secoes.is_empty():
		_distancia += ponto.distance_to(_origem)
	_origem = ponto
	cima = cima.normalized()
	_secoes.append(PackedVector3Array([ponto + cima * acima, ponto - cima * abaixo]))
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
	_trecho = MeshInstance3D.new()
	_trecho.material_override = _material
	_trecho.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trecho)
	_trechos.append(_trecho)
	while _trechos.size() > max_trechos:
		_trechos.pop_front().queue_free()

func _reconstruir():
	var pos := PackedVector3Array()
	var normais := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	# Uma fita vertical; UV.x = altura (0 = topo, 1 = base), UV.y = metros
	for i in _secoes.size():
		var topo := _secoes[i][0]
		var baixo := _secoes[i][1]
		var seguinte := _secoes[mini(i + 1, _secoes.size() - 1)][0]
		var anterior := _secoes[maxi(i - 1, 0)][0]
		var n := (seguinte - anterior).cross(topo - baixo).normalized()
		pos.append(topo)
		pos.append(baixo)
		normais.append(n)
		normais.append(n)
		uv.append(Vector2(0.0, _comprimentos[i]))
		uv.append(Vector2(1.0, _comprimentos[i]))
	for i in _secoes.size() - 1:
		var a := i * 2
		idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normais
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_trecho.mesh = m
