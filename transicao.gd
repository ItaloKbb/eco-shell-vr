class_name Transicao
extends MeshInstance3D
## Passagem de portal: uma esfera pequena em volta da câmera (por dentro, sem teste de
## profundidade) que escurece na cor do portal e depois clareia, com o "vuum" do portal.
## Funciona igual no monitor e no VR (cobre os dois olhos).

var _material := StandardMaterial3D.new()
var _som := AudioStreamPlayer.new()
var _loading := Label3D.new()
var _destino := ""
var _etapa := ""
var _tempo_loading := 0.0
var _carregando := false

func _ready():
	var bola := SphereMesh.new()
	bola.radius = 0.2
	bola.height = 0.4
	bola.flip_faces = true
	mesh = bola
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	_material.albedo_color = Color(0, 0, 0, 0)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false
	_som.bus = "Carro"
	add_child(_som)
	_loading.name = "TelaLoading"
	_loading.position = Vector3(0, 0, -1.2)
	_loading.font_size = 40
	_loading.pixel_size = 0.0016
	_loading.outline_size = 8
	_loading.no_depth_test = true
	_loading.render_priority = Material.RENDER_PRIORITY_MAX
	_loading.shaded = false
	add_child(_loading)

## Indicador por etapas reais; não apresenta porcentagens estimadas.
func atualizar_loading(destino: String, etapa: String):
	_destino = destino
	_etapa = etapa
	_atualizar_texto()

func _process(delta: float):
	if _carregando:
		_tempo_loading += delta
		_atualizar_texto()

func _atualizar_texto():
	var pontos := ".".repeat(1 + int(_tempo_loading * 3.0) % 3)
	_loading.text = "ECO SHELL / PORTAL\n\n%s\n\nCARREGANDO%s\n%s" % [_destino.to_upper(), pontos, _etapa]

## Cobre a visão na cor dada (o mundo pode ser trocado por trás enquanto isso)
func cobrir(cor: Color, tempo := 0.5, destino := "DESTINO"):
	_seguir_camera()
	visible = true
	_carregando = true
	_tempo_loading = 0.0
	_loading.modulate = cor.lerp(Color.WHITE, 0.65)
	_loading.modulate.a = 0.0
	atualizar_loading(destino, "Estabilizando passagem")
	_material.albedo_color = Color(cor.r, cor.g, cor.b, 0.0)
	var som: AudioStream = SomGerador.biblioteca.get("arrancada")
	if som:
		_som.stream = som
		_som.pitch_scale = 0.7
		_som.play()
	var tw := create_tween().set_parallel(true)
	tw.parallel().tween_property(_loading, "modulate:a", 1.0, tempo)
	# Uma única animação controla cor e opacidade, sem tweens concorrentes.
	tw.tween_property(_material, "albedo_color", Color(cor.r * 0.08, cor.g * 0.08, cor.b * 0.08, 1.0), tempo).set_ease(Tween.EASE_IN)
	await tw.finished

func descobrir(tempo := 0.7):
	_seguir_camera()
	atualizar_loading(_destino, "Destino pronto")
	var tw := create_tween()
	tw.tween_property(_material, "albedo_color:a", 0.0, tempo).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_loading, "modulate:a", 0.0, tempo)
	await tw.finished
	visible = false
	_carregando = false

func _seguir_camera():
	var cam := get_viewport().get_camera_3d()
	if cam and get_parent() != cam:
		if get_parent():
			reparent(cam, false)
		else:
			cam.add_child(self)
		transform = Transform3D.IDENTITY
