class_name Portal
extends Node3D
## Portal minimalista para VR: dois feixes de luz suaves marcam o destino sem
## partículas, vórtices ou detritos que geravam ruído visual e consumo de bitrate.

const RAIO := 4.5
const ALTURA := 4.2
const ENTRADA := 1.4
const ALTURA_FEIXE := 110.0

signal atravessado
const ALCANCE_PUXAO := 20.0
const PUXAO_MAX := 4.5

var cor := Color(0.1, 0.85, 1.0)
## O destino também determina se este portal recebe o marcador de corrida.
var destino_corrida := ""
var alvo: RigidBody3D
var _pronto := true

func _ready():
	add_to_group("portais")
	if not destino_corrida.is_empty():
		var marcador := Label3D.new()
		marcador.name = "MarcadorCorrida"
		marcador.text = "CORRIDA\n%s\n▼" % destino_corrida.to_upper()
		marcador.position = Vector3.UP * (ALTURA + RAIO + 2.5)
		marcador.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marcador.font_size = 48
		marcador.pixel_size = 0.012
		marcador.modulate = Color(1.0, 0.95, 0.75)
		marcador.outline_modulate = Color(0.02, 0.02, 0.06)
		marcador.outline_size = 12
		marcador.shaded = false
		add_child(marcador)

	# Núcleo nítido e aura larga usam a mesma animação lenta. São apenas duas
	# superfícies simples, estáveis nos dois olhos e fáceis de comprimir no Link.
	add_child(_criar_feixe("Aura", 1.65, 0.25, 0.35))
	add_child(_criar_feixe("Nucleo", 0.48, 0.9, 0.0))

func _criar_feixe(nome: String, raio: float, forca: float, fase: float) -> MeshInstance3D:
	var feixe := MeshInstance3D.new()
	feixe.name = nome
	var cilindro := CylinderMesh.new()
	cilindro.top_radius = raio * 0.7
	cilindro.bottom_radius = raio
	cilindro.height = ALTURA_FEIXE
	cilindro.radial_segments = 12
	cilindro.rings = 0
	feixe.mesh = cilindro
	var material := ShaderMaterial.new()
	material.shader = preload("res://feixe_portal.gdshader")
	material.set_shader_parameter("cor", cor)
	material.set_shader_parameter("altura", ALTURA_FEIXE)
	material.set_shader_parameter("forca", forca)
	material.set_shader_parameter("fase", fase)
	feixe.material_override = material
	feixe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	feixe.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	feixe.position = Vector3.UP * (ALTURA_FEIXE * 0.5)
	return feixe

func _physics_process(_delta: float):
	if alvo == null or alvo.explodindo or alvo.em_ritual or alvo.em_transicao:
		return
	var centro := global_position + Vector3.UP * ALTURA
	var para := centro - alvo.global_transform * Vector3(0.0, 0.4, 0.0)
	var d := Vector2(para.x, para.z).length()
	if d < ALCANCE_PUXAO and para.length() > 0.5:
		var forca := PUXAO_MAX * pow(1.0 - d / ALCANCE_PUXAO, 1.5)
		alvo.puxar(para.normalized() * forca)
	if para.length() < RAIO + ENTRADA and _pronto:
		_pronto = false
		atravessado.emit()
		get_tree().create_timer(5.0).timeout.connect(func(): _pronto = true)
