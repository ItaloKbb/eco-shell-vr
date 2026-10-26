class_name InterpoladorRede
extends RefCounted
## Interpolação de instantâneos da rede: guarda as últimas poses com o relógio de quem
## enviou e mostra o estado de ATRASO segundos atrás, entre as duas amostras reais que
## cercam esse instante. Pacotes chegando em intervalos irregulares (Wi-Fi, repasse pelo
## servidor) não viram trancos. Se as amostras acabam (pacote atrasado ou perdido),
## segue pela velocidade por até EXTRAPOLA_MAX e então segura a última pose.

## Quanto o carro mostrado fica no passado: cobre o intervalo de envio (1/30 s) e a
## variação de atraso do Wi-Fi sem que falte amostra à frente
const ATRASO := 0.1
const EXTRAPOLA_MAX := 0.25
const MAX_AMOSTRAS := 40

## [t do remetente, posição, rotação], em ordem de t
var _amostras: Array = []
## Relógio local menos o do remetente. Fica no menor valor visto (o pacote que chegou
## mais rápido) e sobe devagar, acompanhando a deriva entre os dois relógios
var _desvio := INF

static func agora() -> float:
	return Time.get_ticks_usec() / 1000000.0

func vazio() -> bool:
	return _amostras.is_empty()

func limpar():
	_amostras.clear()
	_desvio = INF

## `t` no relógio de quem enviou (InterpoladorRede.agora() do lado de lá)
func adicionar(t: float, pos: Vector3, rot: Quaternion):
	if not _amostras.is_empty():
		var ultima: float = _amostras[-1][0]
		if t <= ultima:
			# Remetente reiniciou (relógio voltou): recomeça; senão é pacote repetido
			if t < ultima - 1.0:
				limpar()
			else:
				return
	var desvio := agora() - t
	_desvio = desvio if desvio < _desvio else _desvio + (desvio - _desvio) * 0.002
	_amostras.append([t, pos, rot])
	if _amostras.size() > MAX_AMOSTRAS:
		_amostras.pop_front()

## Pose para mostrar agora
func pose() -> Transform3D:
	if _amostras.is_empty():
		return Transform3D.IDENTITY
	var alvo := agora() - _desvio - ATRASO
	var primeira: Array = _amostras[0]
	if alvo <= primeira[0]:
		return Transform3D(Basis(primeira[2]), primeira[1])
	for i in range(_amostras.size() - 1, 0, -1):
		var a: Array = _amostras[i - 1]
		var b: Array = _amostras[i]
		if alvo >= a[0] and alvo < b[0]:
			var f: float = (alvo - a[0]) / (b[0] - a[0])
			return Transform3D(Basis(a[2].slerp(b[2], f)), a[1].lerp(b[1], f))
	# Sem amostra à frente: continua na velocidade das duas últimas, por pouco tempo
	var ultima: Array = _amostras[-1]
	if _amostras.size() < 2:
		return Transform3D(Basis(ultima[2]), ultima[1])
	var penultima: Array = _amostras[-2]
	var intervalo: float = maxf(ultima[0] - penultima[0], 0.001)
	var velocidade: Vector3 = (ultima[1] - penultima[1]) / intervalo
	var alem := minf(alvo - ultima[0], EXTRAPOLA_MAX)
	return Transform3D(Basis(ultima[2]), ultima[1] + velocidade * alem)
