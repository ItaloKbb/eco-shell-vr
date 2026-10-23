class_name Transicao
extends MeshInstance3D
## Loading como viagem por um túnel de energia (no espírito das viagens de órbita do
## Destiny): ao cobrir, o mundo escurece na cor do destino e um funil em espiral se
## estica na frente do piloto, puxando-o para dentro; os braços giram, filetes de luz
## passam correndo e um núcleo branco brilha no fundo. O nome do destino e a etapa real
## do carregamento flutuam dentro do túnel. Ao descobrir, o núcleo explode num clarão
## branco e o mundo novo aparece.
##
## Tudo sem teste de profundidade, então cobre a cena inteira nos dois olhos. No VR
## usa apenas escurecimento e texto, sem fluxo espiral na periferia da visão.

const SHADER := preload("res://vortice.gdshader")

## Velocidade do fluxo dos filetes (túnel percorrido por segundo)
@export var velocidade_monitor := 2.6
@export var velocidade_vr := 1.5

var _material := StandardMaterial3D.new()
var _som := AudioStreamPlayer.new()
## Ronco do túnel em loop enquanto carrega
var _som_tunel := AudioStreamPlayer.new()
var _loading := Label3D.new()
var _titulo := Label3D.new()
var _emblema := MeshInstance3D.new()
## Núcleo: o brilho branco no fundo do túnel, para onde o piloto é puxado
var _nucleo := MeshInstance3D.new()
var _material_nucleo := StandardMaterial3D.new()
var _material_emblema := StandardMaterial3D.new()
var _camadas: Array[MeshInstance3D] = []
var _materiais: Array[ShaderMaterial] = []
var _destino := ""
var _etapa := ""
var _tempo_loading := 0.0
var _carregando := false

## Estado do túnel: brilho (0 a 1), velocidade e o que já percorreu/girou, clarão da
## saída e o quanto o funil já se esticou na frente do piloto
var _intensidade := 0.0
var _velocidade := 0.0
var _fluxo := 0.0
var _giro := 0.0
var _clarao := 0.0
var _estica := 1.0
var _espiral := true
var _cor := Color.WHITE
var _animacao: Tween

func _ready():
	top_level = true
	var bola := SphereMesh.new()
	bola.radius = 0.2
	bola.height = 0.4
	bola.flip_faces = true
	mesh = bola
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.disable_fog = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX - 3
	_material.albedo_color = Color(0, 0, 0, 0)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	_som.bus = "Carro"
	add_child(_som)
	_som_tunel.bus = "Carro"
	_som_tunel.volume_db = -80.0
	add_child(_som_tunel)

	# Duas camadas de funil: a externa larga, a interna mais estreita girando ao
	# contrário (paralaxe: dá profundidade sem partículas)
	_camada(Vector3(0.02, 2.6, 26.0), 3.0, 2.5, 56.0)
	_camada(Vector3(0.02, 1.5, 22.0), 5.0, -3.5, 34.0)

	_titulo.name = "Destino"
	_titulo.position = Vector3(0, -0.62, -2.6)
	_titulo.font_size = 72
	_titulo.pixel_size = 0.0028
	_titulo.outline_size = 10
	_loading.name = "TelaLoading"
	_loading.position = Vector3(0, -0.92, -2.6)
	_loading.font_size = 34
	_loading.pixel_size = 0.0028
	_loading.outline_size = 8
	for rotulo in [_titulo, _loading]:
		rotulo.no_depth_test = true
		rotulo.render_priority = Material.RENDER_PRIORITY_MAX
		rotulo.shaded = false
		rotulo.outline_modulate = Color(0, 0, 0, 0.75)
		add_child(rotulo)
	var luz := QuadMesh.new()
	luz.size = Vector2(9.0, 9.0)
	_material_nucleo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material_nucleo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_nucleo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material_nucleo.no_depth_test = true
	_material_nucleo.disable_fog = true
	_material_nucleo.render_priority = Material.RENDER_PRIORITY_MAX - 2
	_material_nucleo.albedo_texture = Explosao._bolinha()
	luz.material = _material_nucleo
	_nucleo.mesh = luz
	_nucleo.position = Vector3(0, 0, -24.0)
	_nucleo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_nucleo)
	# Emblema: anel fino de seis lados girando em volta do núcleo, no fundo do túnel
	var anel := TorusMesh.new()
	anel.inner_radius = 0.56
	anel.outer_radius = 0.6
	anel.rings = 6
	anel.ring_segments = 3
	_material_emblema.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material_emblema.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material_emblema.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material_emblema.no_depth_test = true
	_material_emblema.disable_fog = true
	_material_emblema.render_priority = Material.RENDER_PRIORITY_MAX - 1
	anel.material = _material_emblema
	_emblema.mesh = anel
	_emblema.position = Vector3(0, 0.0, -2.7)
	_emblema.rotation.x = PI * 0.5
	_emblema.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_emblema)

## Funil (raio no fundo, raio perto, comprimento) visto por dentro; o fundo fica em -Z
func _camada(forma: Vector3, bracos: float, torcao: float, colunas: float):
	var funil := CylinderMesh.new()
	funil.top_radius = forma.x
	funil.bottom_radius = forma.y
	funil.height = forma.z
	funil.radial_segments = 48
	funil.rings = 12
	funil.cap_top = false
	funil.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = Material.RENDER_PRIORITY_MAX - 2
	mat.set_shader_parameter("bracos", bracos)
	mat.set_shader_parameter("torcao", torcao)
	mat.set_shader_parameter("colunas", colunas)
	var camada := MeshInstance3D.new()
	camada.mesh = funil
	camada.material_override = mat
	camada.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Topo do cilindro (+Y) vira o fundo (-Z); a boca fica um pouco atrás da cabeça
	camada.rotation.x = -PI * 0.5
	camada.position.z = -forma.z * 0.5 + 1.0
	add_child(camada)
	_camadas.append(camada)
	_materiais.append(mat)

## Indicador por etapas reais; não apresenta porcentagens estimadas.
func atualizar_loading(destino: String, etapa: String):
	_destino = destino
	_etapa = etapa
	_atualizar_texto()

func _process(delta: float):
	if not visible:
		return
	if _carregando:
		_tempo_loading += delta
		_atualizar_texto()
	_seguir_camera()
	_fluxo += _velocidade * delta
	_giro += (0.06 + 0.04 * _velocidade) * delta
	for i in _materiais.size():
		var m := _materiais[i]
		m.set_shader_parameter("intensidade", _intensidade * (1.0 if i == 0 else 0.6))
		m.set_shader_parameter("fluxo", _fluxo * (1.0 if i == 0 else 1.4))
		m.set_shader_parameter("giro", _giro * (1.0 if i == 0 else -1.3))
		m.set_shader_parameter("clarao", _clarao)
		_camadas[i].scale = Vector3(1.0, maxf(_estica, 0.02), 1.0)
	_emblema.rotate_object_local(Vector3.UP, delta * 0.6)
	var pulso := 0.85 + 0.15 * sin(_tempo_loading * 2.2)
	var branco := lerpf(0.55, 1.0, _clarao)
	_material_nucleo.albedo_color = Color(_cor.lerp(Color.WHITE, branco), _intensidade * pulso)
	_nucleo.scale = Vector3.ONE * (1.0 + 2.5 * _clarao)
	_material_emblema.albedo_color.a = _intensidade * (0.55 + 0.25 * sin(_tempo_loading * 3.0))
	if _som_tunel.playing:
		_som_tunel.pitch_scale = 0.55 + 0.18 * _velocidade

func _atualizar_texto():
	var pontos := ".".repeat(1 + int(_tempo_loading * 3.0) % 3)
	_titulo.text = _destino.to_upper()
	_loading.text = "CARREGANDO%s\n%s" % [pontos, _etapa]

## Cobre a visão na cor dada (o mundo pode ser trocado por trás enquanto isso). Com
## `espiral`, o túnel de energia aparece e puxa o piloto; sem, é só um escurecer rápido
func cobrir(cor: Color, tempo := 0.5, destino := "DESTINO", espiral := true):
	# O fluxo espiral ocupa a periferia inteira do headset durante o loading.
	if get_viewport().use_xr:
		espiral = false
	_seguir_camera(true)
	visible = true
	_carregando = true
	_espiral = espiral
	_tempo_loading = 0.0
	_clarao = 0.0
	# O túnel usa o matiz do destino em brilho cheio (cores escuras somariam quase nada)
	var viva := cor / maxf(maxf(cor.r, maxf(cor.g, cor.b)), 0.001)
	viva = Color(viva.r, viva.g, viva.b).lerp(Color.WHITE, 0.1)
	_cor = viva
	for m in _materiais:
		m.set_shader_parameter("cor", Vector3(viva.r, viva.g, viva.b))
	_material_emblema.albedo_color = Color(viva.r, viva.g, viva.b, 0.0)
	var texto := viva.lerp(Color.WHITE, 0.65)
	for rotulo in [_titulo, _loading]:
		rotulo.modulate = Color(texto, 0.0)
	atualizar_loading(destino, "Estabilizando passagem")
	_material.albedo_color = Color(cor.r, cor.g, cor.b, 0.0)
	var som: AudioStream = SomGerador.biblioteca.get("arrancada")
	if som:
		_som.stream = som
		_som.pitch_scale = 0.7
		_som.volume_db = 0.0
		_som.play()
	var vr := get_viewport().use_xr
	var velocidade := velocidade_vr if vr else velocidade_monitor
	if _animacao and _animacao.is_valid():
		_animacao.kill()
	if espiral:
		_tocar_tunel()
		# O puxão: o funil se estica na frente e o fluxo acelera além do que a cobertura
		# leva (continua depois que o await termina)
		_intensidade = 0.0
		_velocidade = 0.3
		_estica = 0.15
		_animacao = create_tween().set_parallel(true)
		_animacao.tween_property(self, "_estica", 1.0, maxf(tempo * 2.0, 0.6)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_animacao.tween_property(self, "_velocidade", velocidade, maxf(tempo, 0.3) + 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	else:
		_intensidade = 0.0
		_velocidade = 0.0
	var tw := create_tween().set_parallel(true)
	for rotulo in [_titulo, _loading]:
		tw.tween_property(rotulo, "modulate:a", 1.0, tempo)
	# Uma única animação controla cor e opacidade, sem tweens concorrentes.
	tw.tween_property(_material, "albedo_color", Color(cor.r * 0.08, cor.g * 0.08, cor.b * 0.08, 1.0), tempo).set_ease(Tween.EASE_IN)
	if espiral:
		tw.tween_property(self, "_intensidade", 1.0, tempo).set_ease(Tween.EASE_IN)
	await tw.finished

## Saída: (com espiral) o fluxo dá um último arranque e o núcleo estoura em branco;
## depois tudo some e o mundo novo aparece
func descobrir(tempo := 0.7):
	_seguir_camera()
	atualizar_loading(_destino, "Destino pronto")
	if _animacao and _animacao.is_valid():
		_animacao.kill()
	if _espiral and _intensidade > 0.05:
		var som: AudioStream = SomGerador.biblioteca.get("arrancada")
		if som:
			_som.stream = som
			_som.pitch_scale = 1.25
			_som.volume_db = -2.0
			_som.play()
		var saida := create_tween().set_parallel(true)
		saida.tween_property(self, "_velocidade", _velocidade * 2.5, 0.2).set_ease(Tween.EASE_IN)
		saida.tween_property(self, "_clarao", 1.0, 0.2).set_ease(Tween.EASE_IN)
		await saida.finished
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_material, "albedo_color:a", 0.0, tempo).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_intensidade", 0.0, tempo).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "_clarao", 0.0, tempo * 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(_som_tunel, "volume_db", -60.0, tempo)
	for rotulo in [_titulo, _loading]:
		tw.tween_property(rotulo, "modulate:a", 0.0, tempo * 0.6)
	await tw.finished
	_som_tunel.stop()
	visible = false
	_carregando = false

## Ronco do túnel (o vento girando do portal), entrando aos poucos
func _tocar_tunel():
	var loop: AudioStream = SomGerador.biblioteca.get("portal")
	if loop == null:
		return
	_som_tunel.stream = loop
	_som_tunel.volume_db = -40.0
	_som_tunel.play()
	create_tween().tween_property(_som_tunel, "volume_db", -9.0, 0.8)

## Acompanha a posição da cabeça; a orientação (só o rumo, sempre na vertical) é
## tomada uma vez ao cobrir, para o túnel ficar preso ao mundo e não à cabeça
func _seguir_camera(orientar := false):
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if get_parent() == null:
		cam.get_tree().root.add_child(self)
	if orientar:
		var frente := -cam.global_basis.z
		frente.y = 0.0
		if frente.length() < 0.01:
			frente = Vector3.FORWARD
		global_basis = Basis.looking_at(frente.normalized(), Vector3.UP)
	global_position = cam.global_position
