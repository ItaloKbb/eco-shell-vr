extends Node
## Uma vida começa na esfera, com identificação e lançamento, no PC e no XR.
enum Estado { ESCOLHA, CARGA, PARTIDA, MORTE }
const ARQUIVO := "user://piloto.cfg"
const LETRAS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "
const RESOLUCAO := Vector2i(600, 240)

var arquivo_perfil := ARQUIVO
var estado := Estado.ESCOLHA
var nick := "PILOTO"
var cursor := 0
var carga := 0.0
var _soltou := false
var _repeticao := 0.0
var _eixo_anterior := Vector2i.ZERO
var _fase := 0.0
var _tom: AudioStreamGeneratorPlayback
var _som: AudioStreamPlayer
var _tela: SubViewport
var _texto: Label
var _painel: MeshInstance3D
var _material: StandardMaterial3D
var _ruptura: Tween
var _pronto := false
var _reiniciando := false
var _modo_vr := false
var _fade_spawn: Transicao
@onready var mapa = get_parent()
@onready var carro = mapa.get_node("Carro")
@onready var esfera: MeshInstance3D = mapa.get_node("EsferaInicial")

func _ready():
	_modo_vr = get_viewport().use_xr
	carro.em_ritual = true
	carro.explodiu.connect(_morreu)
	carro.retorno_solicitado.connect(_nova_vida)
	carro.mao_direita.button_pressed.connect(_botao_vr)
	var config := ConfigFile.new()
	if config.load(arquivo_perfil) == OK:
		nick = _sanitizar(str(config.get_value("piloto", "nick", "PILOTO")))
	if nick.is_empty():
		nick = "PILOTO"
	_material = esfera.get_surface_override_material(0).duplicate()
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _modo_vr:
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fade_spawn = Transicao.new()
		add_child(_fade_spawn)
	esfera.set_surface_override_material(0, _material)
	esfera.get_node("Colisao").collision_layer = 0
	_montar_painel()
	_montar_som()
	# O pai escolhe a câmera XR depois de adicionar este controlador.
	_nova_vida.call_deferred()

func _sanitizar(valor: String) -> String:
	var resultado := ""
	for letra in valor.strip_edges().to_upper():
		if letra in LETRAS and resultado.length() < 8:
			resultado += letra
	return resultado.strip_edges()

func _nova_vida():
	if _reiniciando:
		return
	_reiniciando = true
	_pronto = false
	carro.em_ritual = true
	carro.freeze = true
	var mundos = mapa.get_node_or_null("Mundos")
	if mundos:
		await mundos.restaurar_inicio()
	if _modo_vr:
		await _fade_spawn.cobrir(Color(0.05, 0.1, 0.2), 0.15, "Nascimento")
	carro.pista.limpar()
	if _modo_vr:
		mapa.ajustar_spawn_vr(true)
	for grupo in ["piramides", "misseis"]:
		for inimigo in get_tree().get_nodes_in_group(grupo):
			inimigo.queue_free()
	if _ruptura and _ruptura.is_valid():
		_ruptura.kill()
	esfera.scale = Vector3.ONE
	esfera.visible = true
	_material.albedo_color.a = 1.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	estado = Estado.ESCOLHA
	carga = 0.0
	_resetar_carga()
	cursor = 0
	carro.preparar_vida(Transform3D(Basis.IDENTITY, esfera.global_position - Vector3.UP * 0.3))
	if get_viewport().use_xr:
		carro.camera_xr.make_current()
	else:
		carro.camera.make_current()
	if _modo_vr:
		await get_tree().process_frame
		await get_tree().process_frame
		# Painel ancorado no mundo: a cabeça pode olhar e se mover livremente.
		_painel.reparent(mapa, false)
		var frente: Vector3 = -carro.camera_xr.global_basis.z
		frente.y = 0.0
		if frente.length_squared() < 0.01:
			frente = Vector3.FORWARD
		_painel.global_position = carro.camera_xr.global_position + frente.normalized() * 1.5
		_painel.look_at(carro.camera_xr.global_position, Vector3.UP, true)
	else:
		_painel.reparent(carro.camera, false)
		_painel.position = Vector3(0.0, 0.08, -1.2)
	_painel.visible = true
	_atualizar_texto()
	if _modo_vr:
		await _fade_spawn.descobrir(0.25)
	_pronto = true
	_reiniciando = false

func _resetar_carga():
	_soltou = false
	_repeticao = 0.0
	_eixo_anterior = Vector2i.ZERO

func _morreu():
	estado = Estado.MORTE
	carga = 0.0
	_painel.visible = false

func _input(event: InputEvent):
	if not _pronto or estado != Estado.ESCOLHA:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirmar()
		elif event.keycode == KEY_BACKSPACE:
			nick = nick.left(maxi(0, nick.length() - 1))
			cursor = mini(cursor, nick.length())
		elif event.unicode >= 32 and event.unicode < 127 and nick.length() < 8:
			var letra := String.chr(event.unicode).to_upper()
			if letra in LETRAS:
				nick += letra
				cursor = mini(nick.length(), 7)
		_atualizar_texto()
		get_viewport().set_input_as_handled()

func _botao_vr(nome: String):
	if _pronto and estado == Estado.ESCOLHA and nome == "ax_button":
		_confirmar()

func _confirmar():
	var limpo := _sanitizar(nick)
	if limpo.is_empty():
		return
	nick = limpo
	carro.nickname = nick
	var config := ConfigFile.new()
	config.set_value("piloto", "nick", nick)
	var erro := config.save(arquivo_perfil)
	if erro != OK:
		push_warning("Não foi possível salvar o nickname: %s" % error_string(erro))
	estado = Estado.CARGA
	_resetar_carga()
	_atualizar_texto()

func _physics_process(delta: float):
	if not _pronto or estado == Estado.MORTE or estado == Estado.PARTIDA:
		return
	if estado == Estado.ESCOLHA and get_viewport().use_xr:
		_editar_vr(delta)
	if estado == Estado.CARGA:
		var acel := 1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0
		if get_viewport().use_xr:
			acel = maxf(acel, carro.mao_direita.get_float("trigger"))
		if acel < 0.15:
			_soltou = true
		if _soltou:
			carga = move_toward(carga, 1.0 if acel > 0.5 else 0.0, delta * 0.5)
		carro.comando_acel = carga
		if carga >= 1.0:
			_tentar_partida()
	var pulso := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (3.0 + carga * 14.0))
	_material.emission_energy_multiplier = 0.25 + carga * 0.3 if _modo_vr else 0.25 + carga * (2.0 + pulso)
	esfera.get_node("LuzEsfera").light_energy = 0.0 if _modo_vr else 2.0 + carga * (6.0 + pulso * 2.0)
	_atualizar_texto()

func _editar_vr(delta: float):
	var analogico: Vector2 = carro.mao_esquerda.get_vector2("primary")
	var eixo := Vector2i(int(signf(analogico.x)) if absf(analogico.x) > 0.6 else 0,
		int(signf(analogico.y)) if absf(analogico.y) > 0.6 else 0)
	_repeticao -= delta
	if eixo == Vector2i.ZERO:
		_repeticao = 0.0
	elif eixo != _eixo_anterior or _repeticao <= 0.0:
		_repeticao = 0.25 if eixo == _eixo_anterior else 0.4
		if eixo.x != 0:
			cursor = clampi(cursor + eixo.x, 0, mini(nick.length(), 7))
		elif eixo.y != 0:
			while nick.length() <= cursor:
				nick += " "
			var indice := LETRAS.find(nick[cursor])
			nick = nick.left(cursor) + LETRAS[posmod(indice + eixo.y, LETRAS.length())] + nick.substr(cursor + 1)
	_eixo_anterior = eixo

func _tentar_partida():
	# Só sai quando a colisão real do terreno estiver disponível sob as três rodas.
	var saida := Vector3(0.0, 0.0, -7.0)
	var altura := -INF
	for deslocamento in [Vector3(-0.36, 0, -0.75), Vector3(0.36, 0, -0.75), Vector3(0, 0, 0.7)]:
		var p: Vector3 = saida + deslocamento
		var consulta := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 4.0, p + Vector3.DOWN * 4.0, carro.mascara_chao, [carro.get_rid()])
		var chao: Dictionary = carro.get_world_3d().direct_space_state.intersect_ray(consulta)
		if chao.is_empty():
			return
		altura = maxf(altura, chao.position.y)
	estado = Estado.PARTIDA
	_painel.visible = false
	if _modo_vr:
		_sair_vr(Transform3D(Basis.IDENTITY, Vector3(saida.x, altura + 0.15, saida.z)))
		return
	carro.liberar_partida(Transform3D(Basis.IDENTITY, Vector3(saida.x, altura + 0.15, saida.z)))
	# A casca expande e se dissolve; o corpo de colisão permanece desativado.
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ruptura = create_tween().set_parallel(true)
	_ruptura.tween_property(esfera, "scale", Vector3.ONE * 1.8, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ruptura.tween_property(_material, "albedo_color:a", 0.0, 0.45)
	_ruptura.tween_property(esfera.get_node("LuzEsfera"), "light_energy", 0.0, 0.45)
	_ruptura.chain().tween_callback(func(): esfera.visible = false)

func _sair_vr(destino: Transform3D):
	await _fade_spawn.cobrir(Color(0.05, 0.1, 0.2), 0.15, "Saída da esfera")
	# Evita transparência de tela inteira, expansão sobre os olhos e salto visível.
	esfera.hide()
	carro.teleportar(destino)
	mapa.ajustar_spawn_vr(false)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_spawn.descobrir(0.3)
	carro.liberar_partida(destino)

func _montar_painel():
	_tela = SubViewport.new()
	_tela.size = RESOLUCAO
	_tela.transparent_bg = true
	_tela.disable_3d = true
	_tela.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_tela)
	_texto = Label.new()
	_texto.size = Vector2(RESOLUCAO)
	_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var fonte := SystemFont.new()
	fonte.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	_texto.add_theme_font_override("font", fonte)
	_texto.add_theme_font_size_override("font_size", 24)
	_texto.modulate = Color(0.3, 0.8, 1.0)
	_tela.add_child(_texto)
	var material := ShaderMaterial.new()
	material.shader = preload("res://visor_holografico.gdshader")
	material.set_shader_parameter("tela", _tela.get_texture())
	material.set_shader_parameter("resolucao", Vector2(RESOLUCAO))
	material.render_priority = 127
	_painel = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.36)
	_painel.mesh = quad
	_painel.material_override = material
	if _modo_vr:
		# Texto sem grade de LEDs, varredura, cintilação ou halos aditivos no Link.
		var simples := StandardMaterial3D.new()
		simples.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		simples.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		simples.albedo_texture = _tela.get_texture()
		simples.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		_painel.material_override = simples
	_painel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_painel)

func _atualizar_texto():
	var texto: String
	if estado == Estado.ESCOLHA:
		var slots := nick.rpad(8, "_")
		if _modo_vr:
			slots = slots.left(cursor) + "[" + slots[cursor] + "]" + slots.substr(cursor + 1)
		texto = "ECO SHELL / IDENTIFIQUE-SE\n\n%s\n\n" % slots
		texto += "← → POSIÇÃO / ↑ ↓ LETRA\nA: CONFIRMAR NICK" if _modo_vr else "DIGITE SEU NICK • ENTER PARA CONFIRMAR"
	else:
		var passos := int(carga * 20)
		var porcentagem := passos * 5 if _modo_vr else int(carga * 100)
		texto = "%s / PRONTO PARA NASCER\n\n[%s%s] %03d%%\n\n" % [nick, "|".repeat(passos), ".".repeat(20 - passos), porcentagem]
		if _modo_vr:
			texto += "SOLTE O GATILHO DIREITO" if not _soltou else "SEGURE O GATILHO DIREITO PARA SAIR"
		else:
			texto += "SOLTE O ACELERADOR" if not _soltou else "SEGURE O ACELERADOR PARA ROMPER"
	if _texto.text != texto:
		_texto.text = texto
		_tela.render_target_update_mode = SubViewport.UPDATE_ONCE

func _montar_som():
	_som = AudioStreamPlayer.new()
	var gerador := AudioStreamGenerator.new()
	gerador.mix_rate = 16000.0
	gerador.buffer_length = 0.08
	_som.stream = gerador
	_som.volume_db = -18.0
	add_child(_som)

func _process(_delta: float):
	if estado != Estado.CARGA or carga <= 0.0:
		if _som.playing:
			_som.stop()
		return
	if not _som.playing:
		_som.play()
		_tom = _som.get_stream_playback()
	for i in _tom.get_frames_available():
		_fase = fmod(_fase + TAU * (100.0 + carga * 650.0) / 16000.0, TAU)
		var amplitude := carga * 0.35 if estado == Estado.CARGA else 0.0
		var valor := (sin(_fase) + 0.25 * sin(_fase * 2.0)) * amplitude
		_tom.push_frame(Vector2.ONE * valor)

func _exit_tree():
	# O painel foi movido para a câmera; sua vida continua pertencendo ao controlador.
	if is_instance_valid(_painel):
		_painel.queue_free()
