class_name SistemaS
extends MapaCorrida
## Mapa do portal ciano: o Sistema S, um campus enorme no fim da tarde cortado pela
## pista em S (PistaSistemaS), larga e ponta a ponta. Prédios de blocos em volta e
## árvores nos miolos das curvas. O portal de volta fica no fim da reta de frenagem.

## Quanto antes do fim da pista fica o portal de volta (m)
const PORTAL_ANTES_DO_FIM := 25.0
const PREDIOS := 70
const ARVORES := 160
## Cores das fachadas: azul, laranja, branco e cinza
const FACHADAS: Array[Color] = [Color(0.12, 0.32, 0.62), Color(0.92, 0.45, 0.12),
	Color(0.88, 0.89, 0.9), Color(0.45, 0.48, 0.52), Color(0.2, 0.5, 0.75)]

func _init():
	nome = "Sistema S"
	faixa_corrida = "res://musicas/musica_4.mp3"
	fala_chegada = "sistema_s"

func _etapas() -> Array:
	return [
		["Traçando o S", _montar_circuito],
		["Gramando o campus", _gramado],
		["Erguendo os prédios", _predios],
		["Plantando as árvores", _arvores],
	]

func _nova_pista() -> PistaCorrida:
	return PistaSistemaS.new()

## No fim da reta de frenagem, depois de onde os adversários estacionam
func _posicao_portal_volta() -> Vector3:
	return pista.pontos[pista.amostra_em(pista.comprimento - PORTAL_ANTES_DO_FIM)]

func _montar_ambiente():
	var ceu := ProceduralSkyMaterial.new()
	ceu.sky_top_color = Color(0.2, 0.36, 0.7)
	ceu.sky_horizon_color = Color(0.98, 0.72, 0.5)
	ceu.ground_horizon_color = Color(0.7, 0.62, 0.5)
	ceu.ground_bottom_color = Color(0.25, 0.3, 0.22)
	ceu.sun_angle_max = 22.0
	var sky := Sky.new()
	sky.sky_material = ceu
	ambiente.background_mode = Environment.BG_SKY
	ambiente.sky = sky
	ambiente.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	ambiente.ambient_light_energy = 0.85
	ambiente.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ambiente.glow_enabled = true
	ambiente.glow_intensity = 0.4
	ambiente.glow_hdr_threshold = 1.1
	ambiente.fog_enabled = true
	ambiente.fog_mode = Environment.FOG_MODE_DEPTH
	ambiente.fog_light_color = Color(0.9, 0.75, 0.6)
	ambiente.fog_depth_begin = 300.0
	ambiente.fog_depth_end = 750.0
	ambiente.fog_sky_affect = 0.3

## Sol de fim de tarde, ainda alto o bastante para não ofuscar na reta
func sol(luz: DirectionalLight3D):
	luz.rotation_degrees = Vector3(-28.0, 60.0, 0.0)
	luz.light_color = Color(1.0, 0.82, 0.62)
	luz.light_energy = 1.35

func _gramado():
	_chao_plano(Color(0.3, 0.45, 0.24))

## Prédios de blocos (caixas com cor por fachada) em volta do S, longe dos muros
func _predios():
	var rng := RandomNumberGenerator.new()
	rng.seed = 1946
	var caixa := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	caixa.material = material
	var pecas: Array[Transform3D] = []
	var cores: Array[Color] = []
	var tentativas := 0
	while pecas.size() < PREDIOS and tentativas < 2000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-650.0, 650.0), rng.randf_range(-750.0, 650.0))
		var tamanho := Vector3(rng.randf_range(18.0, 50.0), rng.randf_range(10.0, 45.0), rng.randf_range(18.0, 40.0))
		if distancia_pista(p.x, p.y) < pista.largura * 0.5 + 18.0 + tamanho.length() * 0.5:
			continue
		var giro := Basis(Vector3.UP, rng.randf() * TAU)
		pecas.append(Transform3D(giro * Basis.from_scale(tamanho), Vector3(p.x, tamanho.y * 0.5, p.y)))
		cores.append(FACHADAS[rng.randi() % FACHADAS.size()])
	_instancias(caixa, pecas, cores)

## Árvores (tronco e copa) espalhadas, mais nos miolos das curvas do S
func _arvores():
	var rng := RandomNumberGenerator.new()
	rng.seed = 326
	var tronco := CylinderMesh.new()
	tronco.top_radius = 0.25
	tronco.bottom_radius = 0.35
	tronco.height = 1.0
	tronco.radial_segments = 6
	tronco.rings = 1
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.35, 0.24, 0.15)
	tronco.material = madeira
	var copa := SphereMesh.new()
	copa.radius = 1.0
	copa.height = 2.0
	copa.radial_segments = 8
	copa.rings = 4
	var folha := StandardMaterial3D.new()
	folha.albedo_color = Color(0.2, 0.42, 0.18)
	folha.roughness = 0.9
	copa.material = folha
	var troncos: Array[Transform3D] = []
	var copas: Array[Transform3D] = []
	var tentativas := 0
	while troncos.size() < ARVORES and tentativas < 3000:
		tentativas += 1
		var p := Vector2(rng.randf_range(-450.0, 450.0), rng.randf_range(-550.0, 450.0))
		if distancia_pista(p.x, p.y) < pista.largura * 0.5 + 8.0:
			continue
		var alto := rng.randf_range(3.0, 6.0)
		var raio := rng.randf_range(2.0, 3.5)
		troncos.append(Transform3D(Basis.from_scale(Vector3(1.0, alto, 1.0)), Vector3(p.x, alto * 0.5, p.y)))
		copas.append(Transform3D(Basis.from_scale(Vector3(raio, raio * 0.9, raio)), Vector3(p.x, alto + raio * 0.6, p.y)))
	_instancias(tronco, troncos)
	_instancias(copa, copas)
