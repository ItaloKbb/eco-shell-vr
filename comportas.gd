class_name Comportas
extends ObstaculoPista
## Paredão da represa atravessando a pista com três passagens. As comportas sobem e
## descem e só uma fica aberta por vez, andando de faixa (esquerda, meio, direita,
## meio...). A próxima começa a subir um pouco antes de a atual descer, e a luz em cima
## de cada uma fica verde enquanto dá para passar.

const FAIXAS := 3
## Centro de cada passagem (d) e meia largura livre dela (m)
const LARGURA_FAIXA := 4.0
const MEIA_PASSAGEM := 1.7
## Meia espessura do paredão ao longo da pista (m)
const MEIA_ESPESSURA := 0.5
const ALTURA_VIGA := 4.6
## Comporta aberta o suficiente para o carro passar por baixo (0 a 1)
const LIVRE := 0.8
## Ordem das faixas abertas (vai e volta, sempre para uma vizinha)
const SEQUENCIA := [0, 1, 2, 1]

## Quanto tempo cada faixa fica aberta (s)
var passo := 2.4
var fase := 0.0
var _portas: Array[MeshInstance3D] = []
var _luzes: Array[StandardMaterial3D] = []

func _init():
	alcance_s = MEIA_ESPESSURA + MEIO_CARRO
	aviso = "COMPORTAS À FRENTE"

func _ready():
	var concreto := material_metal(Color(0.62, 0.6, 0.56), 0.0, 0.9)
	var aco := material_metal(Color(0.3, 0.34, 0.38), 0.7, 0.45)
	var faixa := material_metal(COR_PERIGO, 0.1, 0.6)
	var meia := PistaCorrida.LARGURA * 0.5
	# Pilares: dois entre as passagens e um em cada borda, por fora da pista
	for d: float in [-meia - 0.6, -LARGURA_FAIXA * 0.5, LARGURA_FAIXA * 0.5, meia + 0.6]:
		var largura := 1.2 if absf(d) > meia else 0.6
		caixa(Vector3(largura, ALTURA_VIGA + 4.5, MEIA_ESPESSURA * 2.0 + 0.6), concreto, Vector3(d, (ALTURA_VIGA + 4.5) * 0.5 - 1.0, 0.0))
	# Casa das máquinas em cima, onde as comportas se escondem
	caixa(Vector3(PistaCorrida.LARGURA + 3.6, 4.0, MEIA_ESPESSURA * 2.0 + 1.2), concreto, Vector3(0.0, ALTURA_VIGA + 2.0, 0.0))
	caixa(Vector3(PistaCorrida.LARGURA + 3.7, 0.35, MEIA_ESPESSURA * 2.0 + 1.25), faixa, Vector3(0.0, ALTURA_VIGA + 0.2, 0.0))
	for i in FAIXAS:
		var d := _centro_faixa(i)
		var porta := caixa(Vector3(MEIA_PASSAGEM * 2.0 + 0.2, ALTURA_VIGA, 0.35), aco, Vector3(d, 0.0, 0.0))
		_portas.append(porta)
		# Listras de perigo na borda de baixo da comporta
		caixa(Vector3(MEIA_PASSAGEM * 2.0 + 0.22, 0.3, 0.4), faixa, Vector3(0.0, -ALTURA_VIGA * 0.5 + 0.15, 0.0), porta)
		var luz := material_luz(Color.RED, 4.0)
		_luzes.append(luz)
		for lado: float in [-1.0, 1.0]:
			var lampada := MeshInstance3D.new()
			var esfera := SphereMesh.new()
			esfera.radius = 0.28
			esfera.height = 0.56
			esfera.material = luz
			lampada.mesh = esfera
			lampada.position = Vector3(d, ALTURA_VIGA + 1.0, lado * (MEIA_ESPESSURA + 0.65))
			add_child(lampada)
	for virado: bool in [false, true]:
		var nome := Label3D.new()
		nome.text = "REPRESA · COMPORTAS"
		nome.font_size = 96
		nome.pixel_size = 0.01
		nome.outline_size = 14
		nome.double_sided = false
		nome.modulate = Color(1.0, 0.85, 0.3)
		nome.transform = Transform3D(Basis(Vector3.UP, PI) if virado else Basis.IDENTITY, Vector3(0.0, ALTURA_VIGA + 2.6, (MEIA_ESPESSURA + 0.62) * (-1.0 if virado else 1.0)))
		add_child(nome)
	animar(0.0)

func _centro_faixa(i: int) -> float:
	return (i - 1) * LARGURA_FAIXA

## 0 = fechada, 1 = toda aberta
func abertura(i: int, t: float) -> float:
	var tempo := t + fase
	var k0 := floori(tempo / passo)
	var a := 0.0
	for k: int in [k0 - 1, k0, k0 + 1]:
		if SEQUENCIA[posmod(k, SEQUENCIA.size())] != i:
			continue
		var tau: float = tempo - k * passo
		# Sobe um pouco antes da vez dela e desce no fim (com sobreposição)
		a = maxf(a, smoothstep(-0.5, 0.15, tau) * (1.0 - smoothstep(passo - 0.25, passo + 0.3, tau)))
	return a

func bloqueia(ds: float, d: float, t: float) -> bool:
	if absf(ds) > alcance_s:
		return false
	var esq := d - MEIA_LARGURA_CARRO
	var dir := d + MEIA_LARGURA_CARRO
	for i in FAIXAS:
		var c := _centro_faixa(i)
		# Pega em alguma parte da faixa i (passagem ou pilar ao lado dela)?
		if dir < c - LARGURA_FAIXA * 0.5 or esq > c + LARGURA_FAIXA * 0.5:
			continue
		var cabe := esq > c - MEIA_PASSAGEM and dir < c + MEIA_PASSAGEM
		if not cabe or abertura(i, t) < LIVRE:
			return true
	return false

## Joga para o meio da passagem aberta mais perto
func lado_empurrao(_ds: float, d: float, t: float) -> float:
	var melhor := 0.0
	var menor := INF
	for i in FAIXAS:
		var c := _centro_faixa(i)
		if abertura(i, t) >= LIVRE and absf(c - d) < menor:
			menor = absf(c - d)
			melhor = c
	return signf(melhor - d) if absf(melhor - d) > 0.1 else 1.0

func animar(t: float):
	for i in _portas.size():
		var a := abertura(i, t)
		_portas[i].position.y = ALTURA_VIGA * 0.5 + a * (ALTURA_VIGA - 0.3)
		var verde := a >= LIVRE
		_luzes[i].albedo_color = Color(0.2, 1.0, 0.35) if verde else Color(1.0, 0.12, 0.08)
		_luzes[i].emission = _luzes[i].albedo_color
