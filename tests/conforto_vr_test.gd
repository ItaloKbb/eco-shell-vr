extends SceneTree
## godot --headless --path . --xr-mode off --script res://tests/conforto_vr_test.gd

class CarroFalso extends Node3D:
	var em_ritual := false
	var em_transicao := false
	var segurado := false
	var velocidade := Vector3.ZERO
	func velocidade_mundo() -> Vector3:
		return velocidade

func _initialize():
	_testar.call_deferred()

func _testar():
	var carro := CarroFalso.new()
	root.add_child(carro)
	var camera := Camera3D.new()
	carro.add_child(camera)
	var conforto = preload("res://conforto_vr.gd").new(carro)
	camera.add_child(conforto)
	conforto.nivel = 1
	await process_frame
	conforto.set_process(false)
	assert(conforto._intensidade < 0.01)
	carro.velocidade = Vector3(0.0, 0.0, -12.0)
	for i in 12:
		conforto._process(1.0 / 60.0)
	assert(conforto._intensidade > 0.1, "O movimento deve fechar a periferia")
	conforto.nivel = 0
	for i in 90:
		conforto._process(1.0 / 60.0)
	assert(conforto._intensidade < 0.01, "Desligado deve abrir a visão")
	assert(conforto.material_override is ShaderMaterial)
	print("CONFORTO_VR_OK: vinheta reage ao movimento e pode ser desligada")
	carro.queue_free()
	await process_frame
	quit()
