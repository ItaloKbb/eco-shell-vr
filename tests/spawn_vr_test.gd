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
	for lado in ["Sul", "Norte"]:
		assert(mapa.get_node("HexWorld/Piso" + lado).mesh is PlaneMesh)
		assert(mapa.get_node("HexWorld/ColisaoPiso/Forma" + lado).shape is BoxShape3D)
	# Um piso de cada lado do abismo, uma colisão e o nó das estruturas
	assert(mapa.get_node("HexWorld").get_child_count() == 4, "O piso deve usar uma malha por lado e uma colisão")
	assert(mapa.get_node("HexWorld/Estruturas") is EstruturasNeon)
	mapa._configurar_render_vr()
	assert(is_equal_approx(root.scaling_3d_scale, mapa.escala_render_vr_pc))
	assert(root.msaa_3d == Viewport.MSAA_2X)
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
	assert(not mapa.get_node("HexWorld").visible)
	assert(not mapa.get_node("PistaEnergia").visible and mapa.get_node("PistaEnergia").process_mode == Node.PROCESS_MODE_DISABLED)
	assert(not mapa.get_node("Inimigos").visible and mapa.get_node("Inimigos").process_mode == Node.PROCESS_MODE_DISABLED)
	assert(not mapa.get_node("Portais").visible and mapa.get_node("Portais").process_mode == Node.PROCESS_MODE_DISABLED)
	assert(not mapa.get_node("DirectionalLight3D").shadow_enabled)
	assert(ritual._painel.get_parent() == mapa)
	assert(ritual._painel.material_override is StandardMaterial3D)
	assert(ritual._painel.mesh.size == ritual.TAMANHO_PAINEL_VR)
	assert(ritual._painel._fundo.bg_color.a >= 0.95, "O fundo do menu VR precisa ter alto contraste")
	var ancora: Vector3 = carro.global_transform * carro.ANCORA_CABECA_LOCAL
	var frente_carro: Vector3 = -carro.global_basis.z
	frente_carro.y = 0.0
	frente_carro = frente_carro.normalized()
	var posicao_esperada: Vector3 = ancora + frente_carro * ritual.DISTANCIA_PAINEL_VR
	assert(ritual._painel.global_position.is_equal_approx(posicao_esperada), "O menu deve nascer à frente do carro")
	assert(not ritual._som.playing)
	var posicao: Vector3 = ritual._painel.global_position
	carro.camera_xr.position.x += 0.1
	await physics_frame
	assert(ritual._painel.global_position.is_equal_approx(posicao), "O painel não deve acompanhar movimentos da cabeça")
	carro.camera_xr.position = Vector3(0.3, 1.4, -0.2)
	carro._alinhar_origem_xr()
	await process_frame
	assert(carro.camera_xr.global_position.is_equal_approx(ancora), "A cabeça deve voltar exatamente à âncora do cockpit")
	assert(ritual._painel.global_position.is_equal_approx(posicao_esperada), "Recentralizar mantém o menu à frente do carro")
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
	assert(mapa.get_node("HexWorld").visible)
	assert(mapa.get_node("PistaEnergia").visible and mapa.get_node("PistaEnergia").process_mode == Node.PROCESS_MODE_INHERIT)
	assert(mapa.get_node("Inimigos").visible and mapa.get_node("Inimigos").process_mode == Node.PROCESS_MODE_INHERIT)
	assert(mapa.get_node("Portais").visible and mapa.get_node("Portais").process_mode == Node.PROCESS_MODE_INHERIT)
	assert(mapa._perfil_spawn.is_empty())
	assert(not ritual._fade_spawn.visible)
	assert(ritual._material.get_shader_parameter("ruptura") == 0.0)
	print("SPAWN_VR_OK: painel estável, perfil temporário, retrovisor suspenso e saída com fade")
	mapa.queue_free()
	for i in 5:
		await process_frame
	quit()
