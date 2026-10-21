extends SceneTree
## Testa o caminho visual VR sem exigir um runtime OpenXR ou headset.
## godot --headless --path . --xr-mode off --script res://tests/spawn_vr_test.gd

func _initialize():
	_testar.call_deferred()

func _testar():
	create_timer(30.0).timeout.connect(func():
		push_error("Timeout no teste do spawn VR")
		quit(1))
	var mapa = load("res://menu.tscn").instantiate()
	root.add_child(mapa)
	current_scene = mapa
	for i in 30:
		await physics_frame
	var ritual = mapa.ritual
	var carro = mapa.carro
	var ambiente: Environment = mapa.get_node("WorldEnvironment").environment
	var nevoa: bool = ambiente.volumetric_fog_enabled
	var brilho: bool = ambiente.glow_enabled
	var chunks: int = mapa.get_node("HexWorld").chunks_per_frame
	# Seleciona explicitamente o ramo VR, sem ativar um viewport XR sem dispositivo.
	ritual._modo_vr = true
	ritual._painel.queue_free()
	ritual._tela.queue_free()
	ritual._montar_painel()
	ritual._fade_spawn = Transicao.new()
	ritual.add_child(ritual._fade_spawn)
	await ritual._nova_vida()
	assert(ritual._pronto and carro.em_ritual and carro.freeze)
	assert(not ambiente.volumetric_fog_enabled and not ambiente.glow_enabled)
	assert(mapa.get_node("HexWorld").chunks_per_frame == 1)
	assert(ritual._painel.get_parent() == mapa)
	assert(ritual._painel.material_override is StandardMaterial3D)
	assert(not ritual._som.playing)
	var posicao: Vector3 = ritual._painel.global_position
	carro.camera_xr.position.x += 0.1
	await physics_frame
	assert(ritual._painel.global_position.is_equal_approx(posicao), "O painel não deve acompanhar movimentos da cabeça")
	assert(carro.tela_traseira.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(not carro.capacete.visible)
	ritual.estado = ritual.Estado.CARGA
	ritual.carga = 1.0
	await physics_frame
	ritual._tentar_partida()
	assert(ritual.estado == ritual.Estado.PARTIDA)
	assert(carro.em_ritual and carro.freeze, "A mudança de posição acontece coberta pelo fade")
	while carro.em_ritual:
		await physics_frame
	assert(not carro.freeze and not ritual.esfera.visible)
	assert(ambiente.volumetric_fog_enabled == nevoa and ambiente.glow_enabled == brilho)
	assert(mapa.get_node("HexWorld").chunks_per_frame == chunks)
	assert(mapa._perfil_spawn.is_empty())
	assert(not ritual._fade_spawn.visible)
	assert(ritual._material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	print("SPAWN_VR_OK: painel estável, perfil temporário, retrovisor suspenso e saída com fade")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
