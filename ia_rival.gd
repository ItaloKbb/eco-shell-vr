class_name IARival
extends RefCounted
## Cérebro de um adversário: máquina de estados que, a partir do que o tráfego mostra
## (TrafegoCorrida) e da personalidade (PerfilPiloto), escolhe a cada passo dois
## números para o veículo (CarroRival): velocidade alvo e faixa alvo (desvio d).
##
## Duas camadas:
## - Decisão (a cada `perfil.reacao` segundos): troca de estado, escolhe alvo.
## - Condução (todo passo): transforma o estado em v_alvo / d_alvo.
##
## Estados:
##   PARADO       no grid ou fora da corrida
##   LARGADA      reagindo à luz verde (cada um com seu tempo de reação)
##   CORRER       ritmo de corrida na linha ideal, seguindo quem está na frente
##   ULTRAPASSAR  sai da linha para passar um carro mais lento
##   DEFENDER     fecha a linha de quem vem atrás (bloqueadores)
##   ATACAR       persegue um carro e bate de traseira ou de lado (brigões)
##   RECUPERAR    tomou uma pancada: tira o pé e volta para a linha
##   ERRO         errou a curva: abre e perde ritmo
##   VOLTA_LENTA  já recebeu a bandeirada

enum Estado { PARADO, LARGADA, CORRER, ULTRAPASSAR, DEFENDER, ATACAR, RECUPERAR, ERRO, VOLTA_LENTA }

## Distância lateral para passar ao lado de outro carro (m)
const FOLGA_ULTRAPASSAGEM := 2.2
## Alcance de quem conta como "logo à frente" ou "logo atrás" (m)
const OLHAR_FRENTE := 22.0
const OLHAR_ATRAS := 10.0
## Sem ataques nos primeiros segundos: a largada não vira demolição
const TREGUA_LARGADA := 5.0

var carro: CarroRival
var perfil: PerfilPiloto
var estado := Estado.PARADO
var tempo_estado := 0.0
## Carro de interesse do estado atual (quem ultrapassar, segurar ou atacar)
var alvo: CarroNaPista

var _pensar := 0.0
var _duracao := 0.0
var _lado := 1.0
var _recarga_ataque := 0.0
var _recarga_defesa := 0.0
var _acertou := false
var _fase_ruido := randf() * TAU

func _init(carro_: CarroRival):
	carro = carro_
	perfil = carro_.perfil

func parar():
	_mudar(Estado.PARADO)
	_recarga_ataque = 0.0
	_recarga_defesa = 0.0

## Luz verde: sai depois do tempo de reação
func largar(atraso: float):
	_mudar(Estado.LARGADA)
	_duracao = atraso

func _mudar(novo: Estado, duracao := 0.0):
	estado = novo
	tempo_estado = 0.0
	_duracao = duracao
	_acertou = false
	if novo in [Estado.CORRER, Estado.PARADO, Estado.LARGADA, Estado.VOLTA_LENTA]:
		alvo = null
	carro.agilidade_extra = 1.0

func atualizar(t: TrafegoCorrida, dt: float):
	tempo_estado += dt
	_recarga_ataque -= dt
	_recarga_defesa -= dt
	_pensar -= dt
	if _pensar <= 0.0:
		_pensar = perfil.reacao * randf_range(0.8, 1.2)
		_decidir(t)
		_tentar_dash(t)
	_conduzir(t)

# --- Decisão --------------------------------------------------------------------

func _decidir(t: TrafegoCorrida):
	if carro.terminou and estado != Estado.VOLTA_LENTA:
		_mudar(Estado.VOLTA_LENTA)
		return
	match estado:
		Estado.PARADO, Estado.VOLTA_LENTA:
			return
		Estado.LARGADA:
			if tempo_estado >= _duracao:
				_mudar(Estado.CORRER)
			return
		Estado.RECUPERAR, Estado.ERRO:
			if tempo_estado >= _duracao:
				_mudar(Estado.CORRER)
			return
		Estado.ATACAR:
			if _ataque_acabou(t):
				_recarga_ataque = perfil.recarga_ataque * randf_range(0.8, 1.3)
				_mudar(Estado.CORRER)
			return
		Estado.ULTRAPASSAR:
			if _ultrapassagem_acabou(t):
				_mudar(Estado.CORRER)
			return
		Estado.DEFENDER:
			if tempo_estado > _duracao or alvo == null or not alvo.presente or t.delta_s(carro.info, alvo) > 1.0 \
					or t.delta_s(carro.info, alvo) < -OLHAR_ATRAS:
				_recarga_defesa = 3.0
				_mudar(Estado.CORRER)
			return
	# CORRER: o que fazer agora?
	if _tentar_atacar(t) or _tentar_errar(t) or _tentar_ultrapassar(t) or _tentar_defender(t):
		return

func _tentar_atacar(t: TrafegoCorrida) -> bool:
	if perfil.agressividade <= 0.0 or _recarga_ataque > 0.0 or t.tempo_corrida < TREGUA_LARGADA:
		return false
	var vitima := t.vitima(carro.info, perfil.foco_no_jogador)
	if vitima == null or randf() > perfil.agressividade * 0.35:
		return false
	_mudar(Estado.ATACAR, randf_range(4.0, 7.0))
	alvo = vitima
	return true

func _tentar_errar(t: TrafegoCorrida) -> bool:
	var curva := absf(t.pista.curvatura(carro.s + 8.0))
	if curva < 0.012 or randf() > perfil.erros * perfil.reacao * 10.0:
		return false
	# Abre para fora da curva
	_lado = -signf(t.pista.curvatura(carro.s + 8.0))
	_mudar(Estado.ERRO, randf_range(0.8, 1.6))
	return true

func _tentar_ultrapassar(t: TrafegoCorrida) -> bool:
	var frente := t.a_frente(carro.info, OLHAR_FRENTE * 0.7, carro.d, 1.6)
	if frente == null or frente.v > _ritmo(t) - 0.3 or randf() > perfil.ousadia:
		return false
	var lado := t.lado_livre(carro.info, frente, _linha(t))
	if lado == 0.0:
		return false
	_lado = lado
	_mudar(Estado.ULTRAPASSAR, 5.0)
	alvo = frente
	return true

func _tentar_defender(t: TrafegoCorrida) -> bool:
	if perfil.defesa <= 0.0 or _recarga_defesa > 0.0:
		return false
	var tras := t.atras(carro.info, OLHAR_ATRAS)
	# Só defende de quem está chegando (mais rápido) e ainda não emparelhou
	if tras == null or tras.v < carro.v + 0.3 or t.delta_s(carro.info, tras) > -2.5 or randf() > perfil.defesa * 0.6:
		return false
	_mudar(Estado.DEFENDER, randf_range(1.5, 3.0))
	alvo = tras
	return true

## Dash tático: prioriza perseguição e ultrapassagem, mas também aproveita uma reta
## livre. Curvas fortes, recuperação e a largada nunca recebem impulso surpresa.
func _tentar_dash(t: TrafegoCorrida) -> bool:
	if not carro.pode_usar_dash() or estado in [Estado.PARADO, Estado.LARGADA, Estado.RECUPERAR, Estado.ERRO, Estado.VOLTA_LENTA]:
		return false
	var antecipacao := 12.0 + carro.v * 1.2
	if absf(t.pista.curvatura(carro.s + antecipacao)) > 0.014:
		return false
	var chance := perfil.uso_dash * 0.32
	if estado == Estado.ATACAR and alvo != null:
		var distancia_ataque := t.delta_s(carro.info, alvo)
		if distancia_ataque > 3.0 and distancia_ataque < 18.0:
			chance = perfil.uso_dash
	elif estado == Estado.ULTRAPASSAR and alvo != null:
		var distancia_passe := t.delta_s(carro.info, alvo)
		if distancia_passe > 2.0 and distancia_passe < 14.0:
			chance = perfil.uso_dash * 0.85
	elif t.a_frente(carro.info, 14.0, carro.d, 1.5) != null:
		return false
	if randf() > chance:
		return false
	return carro.usar_dash()

func _ataque_acabou(t: TrafegoCorrida) -> bool:
	if _acertou or alvo == null or not alvo.presente or tempo_estado > _duracao:
		return true
	var ds := t.delta_s(carro.info, alvo)
	# A vítima fugiu ou ficou para trás demais
	return ds > OLHAR_FRENTE * 1.5 or ds < -6.0

func _ultrapassagem_acabou(t: TrafegoCorrida) -> bool:
	if alvo == null or not alvo.presente or tempo_estado > _duracao:
		return true
	if t.delta_s(carro.info, alvo) < -CarroRival.COMPRIMENTO:
		return true
	# O lado fechou: desiste e volta a seguir
	return t.lado_livre(carro.info, alvo, _linha(t)) != _lado and absf(carro.d - alvo.d) < 1.2

# --- Condução -------------------------------------------------------------------

func _conduzir(t: TrafegoCorrida):
	var v := 0.0
	var d := carro.d
	match estado:
		Estado.PARADO, Estado.LARGADA:
			v = 0.0
		Estado.CORRER:
			d = _linha(t)
			v = _seguir(t, _ritmo(t), d)
		Estado.ULTRAPASSAR:
			d = clampf(alvo.d + _lado * FOLGA_ULTRAPASSAGEM, -t.pista.meia_util, t.pista.meia_util)
			v = _seguir(t, _ritmo(t) * 1.04, d)
		Estado.DEFENDER:
			d = lerpf(_linha(t), alvo.d, clampf(perfil.defesa, 0.0, 0.9))
			v = _seguir(t, _ritmo(t), d)
		Estado.ATACAR:
			var ataque := _atacar(t)
			v = ataque.x
			d = ataque.y
		Estado.RECUPERAR:
			d = lerpf(carro.d, _linha(t), 0.3)
			v = _seguir(t, _ritmo(t) * 0.7, d)
		Estado.ERRO:
			d = _lado * t.pista.meia_util * 0.95
			v = _seguir(t, _ritmo(t) * 0.82, d)
		Estado.VOLTA_LENTA:
			d = t.pista.meia_util * 0.6
			v = _seguir(t, 7.0, d)
			if t.pista.aberta:
				# Ponta a ponta: estaciona encostado num dos muros depois da chegada, em
				# fila, deixando o meio livre para quem ainda vai até o portal do fim
				d = t.pista.meia_util * (0.9 if carro.numero % 2 == 1 else -0.9)
				var vaga := t.pista.s_chegada + 25.0 + ((carro.numero - 1) / 2) * 9.0
				v = minf(v, maxf((vaga - carro.s) * 0.6, 0.0))
	carro.v_alvo = v
	carro.d_alvo = d

## Ritmo de corrida neste ponto: o mais rápido que dá para frear a tempo das próximas
## curvas, com variação de ritmo e um pouco de "elástico" em relação ao jogador
func _ritmo(t: TrafegoCorrida) -> float:
	var curva := t.pista.velocidade_segura(carro.s, perfil.aderencia, perfil.frenagem)
	var base := minf(perfil.velocidade_max, curva)
	var tempo := Time.get_ticks_msec() * 0.001
	var ruido := 0.6 * sin(tempo * 0.31 + _fase_ruido) + 0.4 * sin(tempo * 0.83 + _fase_ruido * 2.0)
	var atras_do_jogador := clampf((t.jogador.progresso - carro.progresso) / 120.0, -1.0, 1.0)
	return base * (1.0 + ruido * perfil.inconsistencia + atras_do_jogador * 0.09 * perfil.elastico)

## Linha de corrida: abre na entrada, tangencia por dentro (a curvatura olhando um
## pouco à frente diz para que lado é a curva)
func _linha(t: TrafegoCorrida) -> float:
	# Rampa logo à frente: dois de cada três adversários vão para a faixa dela
	if t.pista.rampas and carro.numero % 3 != 0:
		var rampa := t.pista.rampas.proxima(carro.s, 90.0)
		if not rampa.is_empty():
			return clampf(float(rampa.d), -t.pista.meia_util, t.pista.meia_util)
	var k := t.pista.curvatura(carro.s + 10.0 + carro.v * 0.8)
	return clampf(k * 160.0, -1.0, 1.0) * t.pista.meia_util * perfil.linha

## Não bate em quem está na frente na faixa d: se aproxima até a distância de segurança
func _seguir(t: TrafegoCorrida, v: float, d: float) -> float:
	var frente := t.a_frente(carro.info, OLHAR_FRENTE, d, 1.5)
	if frente == null:
		return v
	var distancia := t.delta_s(carro.info, frente) - CarroRival.COMPRIMENTO
	var folga := 1.5 + carro.v * 0.3
	return minf(v, maxf(frente.v + (distancia - folga) * 0.9, 0.0))

## Perseguição: vem por trás na faixa da vítima e acelera para a pancada; emparelhado,
## joga o carro de lado. Devolve (v, d)
func _atacar(t: TrafegoCorrida) -> Vector2:
	var ds := t.delta_s(carro.info, alvo)
	carro.agilidade_extra = 1.6
	var v_max := perfil.velocidade_max * 1.08
	if ds > CarroRival.COMPRIMENTO:
		# Atrás: encosta na mesma faixa (mira um pouco à frente do movimento dela)
		var fechando := alvo.v + (perfil.forca_ataque if ds < 8.0 else perfil.forca_ataque * 1.5)
		return Vector2(minf(fechando, v_max), alvo.d)
	if ds > -CarroRival.COMPRIMENTO * 0.6:
		# Lado a lado: pancada lateral
		carro.agilidade_extra = 2.0
		return Vector2(minf(alvo.v + 0.4, v_max), alvo.d)
	# Já passou da vítima: fecha a frente dela (bloqueio sujo)
	return Vector2(maxf(alvo.v - 1.0, 4.0), alvo.d)

## Tráfego avisa de uma batida. `culpado`: foi este carro que entrou no outro
func notificar_batida(forca: float, outro: CarroNaPista, culpado: bool):
	if estado == Estado.ATACAR and outro == alvo:
		_acertou = true
		return
	if culpado or estado in [Estado.PARADO, Estado.LARGADA, Estado.VOLTA_LENTA]:
		return
	if forca > 1.5:
		_mudar(Estado.RECUPERAR, 0.5 + forca * 0.15)
