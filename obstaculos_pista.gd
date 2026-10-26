class_name ObstaculosPista
extends Node3D
## Obstáculos móveis de uma pista (ObstaculoPista): põe cada um na pose da pista,
## anima todos no mesmo relógio da física e resolve quem bate neles.
## - Jogador: tranco para trás (para fora do obstáculo), um empurrão de lado, 1 barra
##   de dano e o aviso no visor quando ele chega perto.
## - Adversários: antes de mover, o tráfego pede `guiar` para cada um. Eles olham o
##   obstáculo à frente e procuram uma faixa livre para a hora em que vão chegar; sem
##   faixa, tiram o pé e esperam. Os distraídos às vezes não olham e batem.
## Filho da pista: tudo em coordenadas locais dela.

## Força do choque que conta 1 barra de dano em car.gd (entre choque_minimo e choque_medio)
const FORCA_BATIDA := 5.0
## Velocidade com que o carro é jogado para trás e para o lado na batida (m/s)
const RECUO := 4.0
const EMPURRAO_LATERAL := 2.5
## Distância à frente em que o piloto recebe o aviso e os adversários planejam (m)
const AVISO := 45.0
const OLHAR := 30.0
## De quanto em quanto tempo cada adversário refaz o plano (s): planejar é caro
const REPLANEJAR := 0.25
const MEIO_CARRO_FRENTE := 1.2

var pista: PistaCorrida
var trafego: TrafegoCorrida
var obstaculos: Array[ObstaculoPista] = []
## Relógio dos obstáculos (s), somado na física
var tempo := 0.0
## Quantas batidas cada um levou (estatística e testes de equilíbrio)
var batidas_jogador := 0
var batidas_rivais := 0

var _espera_jogador := 0.0
var _avisado: ObstaculoPista
var _espera_rival := {}
var _distraido := {}
## Plano de cada adversário: [válido até (tempo), obstáculo, v máxima, faixa (NAN = qualquer)]
var _plano := {}

## Põe o obstáculo na pista, centrado em s
func adicionar(obstaculo: ObstaculoPista, s: float):
	obstaculo.s0 = fposmod(s, pista.comprimento)
	obstaculo.transform = pista.quadro(obstaculo.s0)
	obstaculos.append(obstaculo)
	add_child(obstaculo)

## Distância de s até o centro do obstáculo pela volta (positivo = s já passou dele)
func _ds(obstaculo: ObstaculoPista, s: float) -> float:
	return wrapf(s - obstaculo.s0, -pista.comprimento * 0.5, pista.comprimento * 0.5)

## Obstáculo que bloqueia o carro em (s, d) no instante t, ou null
func bloqueado(s: float, d: float, t: float) -> ObstaculoPista:
	for obstaculo in obstaculos:
		var ds := _ds(obstaculo, s)
		if absf(ds) <= obstaculo.alcance_s and obstaculo.bloqueia(ds, d, t):
			return obstaculo
	return null

func _physics_process(dt: float):
	tempo += dt
	for obstaculo in obstaculos:
		obstaculo.animar(tempo)
	_espera_jogador = maxf(_espera_jogador - dt, 0.0)
	for rival in _espera_rival.keys():
		_espera_rival[rival] -= dt
		if _espera_rival[rival] <= 0.0:
			_espera_rival.erase(rival)
	if trafego == null or trafego.carro == null:
		return
	_jogador()

# --- Jogador ------------------------------------------------------------------------

func _jogador():
	var carro := trafego.carro
	var info := trafego.jogador
	if not info.presente or carro.explodindo or carro.em_transicao or carro.segurado:
		_avisado = null
		return
	_avisar(carro, info.s)
	var obstaculo := bloqueado(info.s, info.d, tempo)
	if obstaculo == null:
		return
	# Volta para fora do obstáculo pelo lado de onde veio; a cada passo que ainda
	# estiver dentro, mas o dano conta uma vez por batida
	var q := pista.global_transform * pista.quadro(info.s)
	var frente := -q.basis.z
	var lado := q.basis.x
	var ds := _ds(obstaculo, info.s)
	var sentido := -1.0 if ds <= 0.0 else 1.0
	var empurra := obstaculo.lado_empurrao(ds, info.d, tempo)
	if empurra == 0.0:
		empurra = 1.0
	var v := carro.linear_velocity
	v -= frente * v.dot(frente) + lado * v.dot(lado)
	carro.linear_velocity = v + frente * sentido * RECUO + lado * empurra * EMPURRAO_LATERAL
	if _espera_jogador <= 0.0:
		_espera_jogador = 0.8
		batidas_jogador += 1
		var ponto: Vector3 = carro.global_position + frente * MEIO_CARRO_FRENTE * -sentido + Vector3.UP * 0.5
		carro._registrar_choque(FORCA_BATIDA, ponto, 0.0, &"estrutura")
		carro._avisar("BATEU!", 1.2)

## Aviso no visor uma vez por obstáculo, quando ele entra no alcance à frente
func _avisar(carro: RigidBody3D, s: float):
	var perto: ObstaculoPista
	var menor := AVISO
	for obstaculo in obstaculos:
		var falta := -_ds(obstaculo, s)
		if falta > 0.0 and falta < menor:
			menor = falta
			perto = obstaculo
	if perto and perto != _avisado:
		carro._avisar(perto.aviso, 1.6)
	_avisado = perto

# --- Adversários --------------------------------------------------------------------

## Antes do rival mover: ajusta v_alvo e d_alvo para não entrar num obstáculo
func guiar(rival: CarroRival):
	if rival.terminou and rival.v < 8.0:
		return
	var alvo := _proximo(rival.s)
	if alvo == null:
		_distraido.erase(rival)
		return
	# Decide uma vez por obstáculo se vai prestar atenção (os que erram mais se distraem)
	if not _distraido.has(rival) or _distraido[rival][0] != alvo:
		_distraido[rival] = [alvo, randf() < rival.perfil.erros * 6.0]
	if _distraido[rival][1]:
		return
	var falta := -_ds(alvo, rival.s)
	var plano: Array = _plano.get(rival, [])
	if plano.is_empty() or tempo >= plano[0] or plano[1] != alvo:
		plano = _planejar(rival, alvo, falta)
		_plano[rival] = plano
	if is_nan(plano[3]):
		# Já dentro: frear ali só piora, segue em frente
		if falta < alvo.alcance_s:
			return
		# Nada livre a tempo: segura antes do obstáculo e espera
		var parar := maxf(falta - alvo.alcance_s - 1.0, 0.0)
		rival.v_alvo = minf(rival.v_alvo, sqrt(2.0 * rival.perfil.frenagem * parar))
		return
	rival.v_alvo = minf(rival.v_alvo, plano[2])
	rival.d_alvo = plano[3]

## Tenta manter a velocidade mudando de faixa; depois tenta ir mais devagar.
## Já entrando na zona do obstáculo não dá mais para trocar de faixa nem frear: só
## confere se a faixa atual continua boa
func _planejar(rival: CarroRival, alvo: ObstaculoPista, falta: float) -> Array:
	var v_atual := maxf(rival.v, 0.0)
	var entrada := falta - alvo.alcance_s
	var dentro := entrada < 1.5
	var fatores := [1.0] if dentro else [1.0, 0.7, 0.45]
	for fator: float in fatores:
		var vel := maxf(v_atual, 3.0) if dentro else maxf(maxf(rival.v_alvo, v_atual) * fator, 3.0)
		# Até a entrada da zona ele vai mudando da velocidade atual para a planejada
		var media := maxf((v_atual + vel) * 0.5, 1.5)
		var ate_entrada := maxf(entrada, 0.0) / media
		var faixa := _faixa_livre(alvo, rival, ate_entrada, vel, dentro, -minf(falta, alvo.alcance_s))
		if not is_nan(faixa):
			return [tempo + REPLANEJAR, alvo, vel, faixa]
	return [tempo + REPLANEJAR, alvo, 0.0, NAN]

## Próximo obstáculo à frente dentro do alcance de planejamento (ou o que ele está atravessando)
func _proximo(s: float) -> ObstaculoPista:
	var melhor: ObstaculoPista
	var menor := OLHAR
	for obstaculo in obstaculos:
		var falta := -_ds(obstaculo, s)
		if falta > -obstaculo.alcance_s and falta < menor:
			menor = falta
			melhor = obstaculo
	return melhor

## Faixa d livre durante toda a travessia (de `inicio_ds` até o fim da zona, entrando
## daqui a `ate_entrada` s), a mais perto da preferida e que dá tempo de alcançar de
## lado antes de entrar; NAN se nenhuma serve
func _faixa_livre(obstaculo: ObstaculoPista, rival: CarroRival, ate_entrada: float, vel: float, dentro: bool, inicio_ds: float) -> float:
	var melhor := NAN
	var menor := INF
	var limite := PistaCorrida.MEIA_UTIL
	var alcance_lateral := rival.perfil.agilidade * ate_entrada * 0.8 + 0.3
	var d := -limite
	while d <= limite + 0.01:
		var desvio := absf(d - rival.d)
		var custo := absf(d - rival.d_alvo) + desvio * 0.5
		var alcancavel := desvio < 0.45 if dentro else desvio <= alcance_lateral
		if alcancavel and custo < menor and _livre(obstaculo, d, inicio_ds, tempo + ate_entrada, vel):
			menor = custo
			melhor = d
		d += 0.85
	if dentro and is_nan(melhor) and _livre(obstaculo, rival.d, inicio_ds, tempo + ate_entrada, vel):
		melhor = rival.d
	return melhor

## A faixa d fica livre desde `inicio_ds` (no instante `chegada`) até sair da zona?
func _livre(obstaculo: ObstaculoPista, d: float, inicio_ds: float, chegada: float, vel: float) -> bool:
	var passos := 5
	var percurso := obstaculo.alcance_s - inicio_ds
	for k in passos + 1:
		var andado := percurso * k / passos
		var instante := chegada + andado / vel
		# Folga de tempo: chega um pouco antes ou depois do previsto
		for erro: float in [-0.3, 0.3]:
			if obstaculo.bloqueia(inicio_ds + andado, d, instante + erro):
				return false
	return true

## Depois de mover: quem entrou num obstáculo leva a batida e volta para fora dele
func colidir_rivais():
	for rival in trafego.rivais:
		var obstaculo := bloqueado(rival.s, rival.d, tempo)
		if obstaculo == null:
			continue
		# Recua um pouco para fora do que bateu (o resto é a espera e o replanejamento)
		var ds := _ds(obstaculo, rival.s)
		var sentido := -1.0 if ds <= 0.0 else 1.0
		var recuo := 0.2 if _espera_rival.has(rival) else 1.0
		rival.s = fposmod(rival.s + sentido * recuo, pista.comprimento)
		rival.progresso += sentido * recuo
		if _espera_rival.has(rival):
			rival.v = 0.0
			continue
		_espera_rival[rival] = 1.0
		batidas_rivais += 1
		# Aprendeu: neste obstáculo ele passa a prestar atenção
		_distraido[rival] = [obstaculo, false]
		_plano.erase(rival)
		if OS.has_environment("DEBUG_OBSTACULOS"):
			var plano: Array = _plano.get(rival, [])
			print("BATIDA %s em %s ds=%.1f d=%.1f v=%.1f distraido=%s plano=%s" % [rival.perfil.nome, obstaculo.get_class() if obstaculo.get_script() == null else obstaculo.get_script().get_global_name(), ds, rival.d, rival.v, _distraido.get(rival, [null, "?"])[1], plano.slice(2)])
		var empurra := obstaculo.lado_empurrao(ds, rival.d, tempo)
		rival.levar_batida((empurra if empurra != 0.0 else 1.0) * 2.0, -rival.v, 4.0, null, false)
		rival.v = 0.0
