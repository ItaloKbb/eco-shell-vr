class_name TrafegoCorrida
extends Node
## Tráfego da corrida: junta todos os carros em coordenadas da pista (CarroNaPista),
## responde às perguntas da IA (quem está na frente, atrás, que lado está livre, quem
## dá para atacar), roda os cérebros e os veículos a cada passo de física e resolve
## os contatos: adversário com adversário (empurrão e troca de velocidade) e
## adversário com o jogador (o corpo animável empurra o carro de verdade; aqui o
## adversário reage, e os ataques ganham um tranco extra).
## Também guarda a ordem de chegada.
## Corrida em grupo: no anfitrião os outros jogadores entram em `carros` (a IA desvia
## e disputa posição com eles); nos outros Quests (`remoto`) os adversários só seguem
## a pose que o anfitrião manda, e a chegada deles é conferida pelo progresso recebido.

signal rival_chegou(rival: CarroRival, posicao: int)
## Um brigão acertou o jogador (som, conquistas, estatística...)
signal jogador_atacado(rival: CarroRival)

## Alcance em que um brigão escolhe vítima (m à frente; um pouco atrás também vale)
const ALCANCE_ATAQUE := 18.0
## Tranco extra de um ataque no jogador (m/s de variação de velocidade)
const TRANCO_ATAQUE := 2.2

var pista: PistaCorrida
var carro: RigidBody3D
var rivais: Array[CarroRival] = []
## Obstáculos móveis da pista (Vale das Turbinas); null nas pistas sem eles
var obstaculos: ObstaculosPista

var ativo := false
## Corrida em grupo num Quest que não é o anfitrião
var remoto := false
## Outros jogadores da corrida em grupo, por peer (só no anfitrião)
var remotos := {}
var tempo_corrida := 0.0
## O jogador visto pela IA (progresso vem da corrida, que conta as voltas dele)
var jogador := CarroNaPista.new()
var carros: Array[CarroNaPista] = []
var chegada: Array[CarroNaPista] = []

var _dica_jogador := -1
## Contatos recentes por par (evita repetir a reação no mesmo encontro)
var _contatos := {}

func _ready():
	jogador.eh_jogador = true
	jogador.presente = false
	definir_rivais(rivais)

## Adversários desta corrida (no grupo sobram menos vagas para a IA)
func definir_rivais(lista: Array[CarroRival]):
	rivais = lista
	carros.assign([jogador])
	for rival in rivais:
		carros.append(rival.info)
	for info in remotos.values():
		carros.append(info)

## Outro jogador da corrida em grupo, como a IA o enxerga (criado na primeira vez)
func jogador_remoto(peer: int) -> CarroNaPista:
	if not remotos.has(peer):
		var info := CarroNaPista.new()
		info.eh_jogador = true
		remotos[peer] = info
		carros.append(info)
	return remotos[peer]

func tirar_remoto(peer: int):
	if remotos.has(peer):
		carros.erase(remotos[peer])
		remotos.erase(peer)

func limpar_remotos():
	for peer in remotos.keys():
		tirar_remoto(peer)

## Todos estacionados nas vagas do grid
func preparar():
	ativo = false
	tempo_corrida = 0.0
	chegada.clear()
	_contatos.clear()
	for i in rivais.size():
		var vaga := pista.grid_sd(i)
		rivais[i].estacionar(vaga.x, vaga.y)

func largar():
	ativo = true
	tempo_corrida = 0.0
	if remoto:
		return
	for rival in rivais:
		rival.ia.largar(rival.perfil.reacao + randf_range(0.05, 0.4))

## Este Quest virou o anfitrião no meio da corrida: os bonecos voltam a ter IA
func assumir_ia():
	if not remoto:
		return
	remoto = false
	for rival in rivais:
		rival.assumir()
		if ativo and not rival.terminou:
			rival.ia.largar(0.0)

func _physics_process(dt: float):
	if pista == null or carro == null:
		return
	_ver_jogador()
	if remoto:
		# Bonecos: a IA roda no anfitrião; aqui só seguem a pose e contam a chegada
		for rival in rivais:
			rival.seguir_rede(dt)
		if ativo:
			_ver_chegadas()
		return
	if not ativo:
		return
	tempo_corrida += dt
	for rival in rivais:
		rival.ia.atualizar(self, dt)
		if obstaculos:
			obstaculos.guiar(rival)
	for rival in rivais:
		rival.mover(dt)
	if obstaculos:
		obstaculos.colidir_rivais()
	_contatos_entre_rivais()
	_contatos_com_jogador()
	_ver_chegadas()
	for chave in _contatos.keys():
		_contatos[chave] -= dt
		if _contatos[chave] <= 0.0:
			_contatos.erase(chave)

func _ver_jogador():
	var local := pista.to_local(carro.global_position)
	var proj := pista.projetar(local, _dica_jogador)
	_dica_jogador = int(proj.z)
	jogador.s = proj.x
	jogador.d = proj.y
	var frente: Vector3 = pista.global_basis * -pista.quadro(proj.x).basis.z
	jogador.v = carro.linear_velocity.dot(frente)
	jogador.presente = ativo and not carro.em_transicao and not carro.explodindo \
		and absf(proj.y) < pista.largura and absf(local.y - pista.quadro(proj.x).origin.y) < 4.0

# --- Perguntas da IA ------------------------------------------------------------

## Metros de a até b ao longo da pista (positivo = b está na frente), pelo caminho curto
func delta_s(a: CarroNaPista, b: CarroNaPista) -> float:
	return pista.delta(a.s, b.s)

## Carro mais próximo à frente, até `alcance` m, cuja faixa cruza a faixa d
func a_frente(eu: CarroNaPista, alcance: float, d: float, faixa: float) -> CarroNaPista:
	var melhor: CarroNaPista
	var menor := alcance
	for outro in carros:
		if outro == eu or not outro.presente:
			continue
		var ds := delta_s(eu, outro)
		if ds > 0.0 and ds < menor and absf(outro.d - d) < faixa:
			menor = ds
			melhor = outro
	return melhor

## Carro mais próximo atrás, até `alcance` m (qualquer faixa)
func atras(eu: CarroNaPista, alcance: float) -> CarroNaPista:
	var melhor: CarroNaPista
	var menor := alcance
	for outro in carros:
		if outro == eu or not outro.presente:
			continue
		var ds := -delta_s(eu, outro)
		if ds > 0.0 and ds < menor:
			menor = ds
			melhor = outro
	return melhor

## Lado (+1 direita, -1 esquerda) para passar `outro`, ou 0 se os dois estão fechados.
## Prefere o lado da linha de corrida quando os dois servem
func lado_livre(eu: CarroNaPista, outro: CarroNaPista, linha: float) -> float:
	var primeiro := 1.0 if linha >= outro.d else -1.0
	for lado: float in [primeiro, -primeiro]:
		var faixa := outro.d + lado * IARival.FOLGA_ULTRAPASSAGEM
		if absf(faixa) > pista.meia_util:
			continue
		var livre := true
		for terceiro in carros:
			if terceiro == eu or terceiro == outro or not terceiro.presente:
				continue
			var ds := delta_s(eu, terceiro)
			if ds > -CarroRival.COMPRIMENTO and ds < 14.0 and absf(terceiro.d - faixa) < 1.4:
				livre = false
				break
		if livre:
			return lado
	return 0.0

## Quem um brigão pode atacar: perto, presente e ainda correndo. O jogador pesa
## `foco_no_jogador`; os outros adversários, o resto
func vitima(eu: CarroNaPista, foco_no_jogador: float) -> CarroNaPista:
	var melhor: CarroNaPista
	var nota := 0.0
	for outro in carros:
		if outro == eu or not outro.presente or (outro.rival and outro.rival.terminou):
			continue
		var ds := delta_s(eu, outro)
		if ds < -3.0 or ds > ALCANCE_ATAQUE:
			continue
		var peso := foco_no_jogador if outro.eh_jogador else (1.0 - foco_no_jogador) * 0.5
		var valor := peso / (1.0 + absf(ds) * 0.2)
		if valor > nota:
			nota = valor
			melhor = outro
	return melhor

# --- Contatos ---------------------------------------------------------------------

## Dois adversários se sobrepondo: separa, troca velocidade (quem vinha atrás mais
## rápido empurra) e empurra cada um para o seu lado
func _contatos_entre_rivais():
	for i in rivais.size():
		var a := rivais[i]
		for j in range(i + 1, rivais.size()):
			var b := rivais[j]
			var ds := delta_s(a.info, b.info)
			var dd := b.d - a.d
			if absf(ds) >= CarroRival.COMPRIMENTO or absf(dd) >= CarroRival.LARGURA:
				continue
			var lado := signf(dd) if dd != 0.0 else (1.0 if randf() < 0.5 else -1.0)
			var sobra := CarroRival.LARGURA - absf(dd)
			a.d = clampf(a.d - lado * sobra * 0.5, -pista.meia_util, pista.meia_util)
			b.d = clampf(b.d + lado * sobra * 0.5, -pista.meia_util, pista.meia_util)
			var tras := a if ds > 0.0 else b
			var frente := b if ds > 0.0 else a
			var choque := maxf(tras.v - frente.v, 0.0)
			var lateral := absf(a._vel_lateral - b._vel_lateral)
			var forca := choque + lateral
			var chave := Vector2i(i, j)
			if _contatos.has(chave):
				# Ainda encostados: só mantém separados e sem atravessar
				if choque > 0.0:
					tras.v = frente.v
				continue
			_contatos[chave] = 0.6
			# Culpado: quem vinha mais rápido por trás ou quem fechou de lado
			var a_culpa := (a == tras and choque > lateral) or (absf(a._vel_lateral) > absf(b._vel_lateral) and lateral >= choque)
			a.levar_batida(-lado * (0.6 + lateral * 0.5), -choque * 0.5 if a == tras else choque * 0.4, forca, b.info, a_culpa)
			b.levar_batida(lado * (0.6 + lateral * 0.5), -choque * 0.5 if b == tras else choque * 0.4, forca, a.info, not a_culpa)

## Adversário encostando no jogador. O corpo animável já empurra o carro pela física;
## aqui o adversário reage (sai de lado, perde ou ganha velocidade) e, se estava
## atacando, dá um tranco extra no jogador
func _contatos_com_jogador():
	if not jogador.presente:
		return
	for i in rivais.size():
		var rival := rivais[i]
		var ds := delta_s(jogador, rival.info)
		var dd := rival.d - jogador.d
		if absf(ds) >= CarroRival.COMPRIMENTO or absf(dd) >= CarroRival.LARGURA + 0.1:
			continue
		var chave := Vector2i(i, -1)
		if _contatos.has(chave):
			continue
		_contatos[chave] = 0.5
		var lado := signf(dd) if dd != 0.0 else 1.0
		var rival_atras := ds < 0.0
		var choque := absf(rival.v - jogador.v)
		var atacando := rival.ia.estado == IARival.Estado.ATACAR and rival.ia.alvo == jogador
		var lateral := absf(rival._vel_lateral)
		var dv := 0.0
		if rival_atras:
			# Bateu na traseira do jogador: perde o embalo
			dv = -choque * 0.6
		else:
			# Levou do jogador por trás: é empurrado para a frente
			dv = choque * 0.5
		rival.levar_batida(lado * (0.8 + lateral * 0.4), dv, choque + lateral, jogador, atacando or rival_atras)
		if atacando:
			_tranco_no_jogador(rival, -lado, rival_atras)

## Pancada de brigão: empurra o carro do jogador (para a frente se veio por trás,
## para o lado se veio de lado) e treme o controle
func _tranco_no_jogador(rival: CarroRival, lado: float, por_tras: bool):
	var q := pista.global_transform * pista.quadro(jogador.s)
	var direcao: Vector3 = (-q.basis.z * 0.6 + q.basis.x * lado * 0.4) if por_tras else (q.basis.x * lado)
	carro.apply_central_impulse(direcao.normalized() * TRANCO_ATAQUE * carro.mass)
	carro.apply_torque_impulse(q.basis.y * lado * 0.4 * carro.mass)
	carro._vibrar_ambas(0.8, 0.2)
	carro._avisar("%s TE ACERTOU!" % rival.perfil.nome, 1.2)
	jogador_atacado.emit(rival)

func _ver_chegadas():
	var linha := pista.distancia_corrida()
	for rival in rivais:
		if not rival.terminou and rival.progresso >= linha:
			rival.terminou = true
			chegada.append(rival.info)
			rival_chegou.emit(rival, chegada.size())
