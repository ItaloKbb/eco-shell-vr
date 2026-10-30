class_name PerfilPiloto
extends Resource
## Personalidade de um adversário: só números, sem lógica. O cérebro (ia_rival.gd)
## lê daqui o quanto o piloto é rápido, ousado, defensivo, agressivo e consistente.
## elenco() devolve os 10 pilotos do grid, do mais rápido (pole) ao mais lento.

## Ritmo dos rivais nas curvas (aderência ao quadrado) e na troca de faixa
const FATOR_VELOCIDADE_CORRIDA := 1.4
## Reta, arrancada e frenagem no mesmo nível do carro do jogador (24 m/s no chão, ~6 m/s²
## de motor): os perfis valem ~12 m/s e ~4 m/s², então dobram. Sem o dash o jogador não
## tem mais como compensar rival mais rápido que ele na reta
const VELOCIDADE_DOBRADA := 2.0
const FATOR_ARRANCADA := 1.5

enum Estilo {
	## Foco em andar rápido e limpo: ultrapassa por fora, quase nunca bate de propósito
	CORREDOR,
	## Caça carros por perto (de preferência o jogador) para bater e tirar da linha
	BRIGAO,
	## Segura posição: fecha a porta de quem tenta passar
	BLOQUEADOR,
	## Mais lento, mas constante; evita contato
	CAUTELOSO,
}

@export var nome := "PILOTO"
@export var estilo := Estilo.CORREDOR

@export_group("Ritmo")
## Velocidade de reta (m/s) antes dos fatores; o jogador chega a 24 no chão
@export var velocidade_max := 12.0
@export var aceleracao := 4.0
@export var frenagem := 8.0
## Aceleração lateral que ele aguenta na curva (m/s²): mais = curva mais rápido
@export var aderencia := 8.0
## Quão rápido muda de faixa (m/s)
@export var agilidade := 2.5
## Quanto usa a largura da pista na linha de corrida (0 = sempre no meio, 1 = tangencia)
@export_range(0.0, 1.0) var linha := 0.7
## Variação do ritmo ao longo da volta (fração da velocidade)
@export_range(0.0, 0.2) var inconsistencia := 0.03
## Chance por segundo de errar uma curva (abre e perde ritmo)
@export_range(0.0, 0.1) var erros := 0.01
## Tempo entre uma decisão e outra (s): menos = reage mais rápido
@export_range(0.05, 0.6) var reacao := 0.2
## Quanto o ritmo se ajusta à distância do jogador (corrida mais disputada)
@export_range(0.0, 1.0) var elastico := 0.5

@export_group("Turbo")
## Probabilidade de aproveitar uma oportunidade de turbo encontrada pelo cérebro. O
## tanque é o mesmo do jogador: enche sozinho (CarroRival.CARGA_PASSIVA)
@export_range(0.0, 1.0) var uso_turbo := 0.6
## Barras mínimas no tanque para ele gastar num turbo
@export var reserva_turbo := 2.0

@export_group("Comportamento")
## Vontade de ultrapassar quem está devagar na frente (0 = fica atrás)
@export_range(0.0, 1.0) var ousadia := 0.6
## Vontade de fechar a linha de quem vem atrás
@export_range(0.0, 1.0) var defesa := 0.3
## Vontade de bater de propósito (só brigões passam de ~0.5)
@export_range(0.0, 1.0) var agressividade := 0.0
## Quanto prefere atacar o jogador a atacar outro adversário
@export_range(0.0, 1.0) var foco_no_jogador := 0.8
## Tempo mínimo entre um ataque e outro (s)
@export var recarga_ataque := 6.0
## Velocidade extra na hora da pancada (m/s, limitada para não ser letal)
@export var forca_ataque := 3.0

static func criar(nome_: String, estilo_: Estilo, valores: Dictionary) -> PerfilPiloto:
	var perfil := PerfilPiloto.new()
	perfil.nome = nome_
	perfil.estilo = estilo_
	match estilo_:
		Estilo.CORREDOR:
			perfil.uso_turbo = 0.85
			perfil.reserva_turbo = 2.0
		Estilo.BRIGAO:
			perfil.uso_turbo = 0.95
			perfil.reserva_turbo = 1.5
		Estilo.BLOQUEADOR:
			perfil.uso_turbo = 0.55
			perfil.reserva_turbo = 2.5
		Estilo.CAUTELOSO:
			perfil.uso_turbo = 0.25
			perfil.reserva_turbo = 3.5
	for chave in valores:
		perfil.set(chave, valores[chave])
	perfil.velocidade_max *= VELOCIDADE_DOBRADA
	perfil.aceleracao *= FATOR_ARRANCADA
	perfil.frenagem *= VELOCIDADE_DOBRADA
	perfil.aderencia *= FATOR_VELOCIDADE_CORRIDA * FATOR_VELOCIDADE_CORRIDA
	perfil.agilidade *= FATOR_VELOCIDADE_CORRIDA
	perfil.forca_ataque *= FATOR_VELOCIDADE_CORRIDA
	return perfil

## Os 10 do grid, na ordem de largada
static func elenco() -> Array[PerfilPiloto]:
	var lista: Array[PerfilPiloto] = [
		criar("VOLT", Estilo.CORREDOR, {velocidade_max = 12.6, aceleracao = 4.3, aderencia = 9.5, agilidade = 3.0,
			linha = 0.9, inconsistencia = 0.015, erros = 0.004, reacao = 0.12, ousadia = 0.85, defesa = 0.35}),
		criar("TROVÃO", Estilo.BLOQUEADOR, {velocidade_max = 12.3, aceleracao = 4.0, aderencia = 8.5,
			linha = 0.6, ousadia = 0.4, defesa = 0.95, reacao = 0.15}),
		criar("BRASA", Estilo.BRIGAO, {velocidade_max = 12.3, aceleracao = 4.4, aderencia = 8.0, agilidade = 3.4,
			ousadia = 0.7, agressividade = 0.85, foco_no_jogador = 0.85, recarga_ataque = 5.0, forca_ataque = 3.5}),
		criar("NOVA", Estilo.CORREDOR, {velocidade_max = 12.4, aceleracao = 4.1, aderencia = 9.0,
			linha = 0.85, ousadia = 0.75, defesa = 0.4, reacao = 0.15}),
		criar("MIRAGEM", Estilo.CORREDOR, {velocidade_max = 12.5, aceleracao = 4.2, aderencia = 8.8,
			linha = 0.8, inconsistencia = 0.08, erros = 0.03, ousadia = 0.9}),
		criar("SUCATA", Estilo.BRIGAO, {velocidade_max = 11.9, aceleracao = 4.6, aderencia = 7.5, agilidade = 3.8,
			linha = 0.4, erros = 0.02, ousadia = 0.8, agressividade = 1.0, foco_no_jogador = 0.6,
			recarga_ataque = 3.5, forca_ataque = 4.0}),
		criar("DUNA", Estilo.BLOQUEADOR, {velocidade_max = 11.9, aceleracao = 3.8, aderencia = 8.0,
			linha = 0.6, ousadia = 0.35, defesa = 0.85}),
		criar("RAIO", Estilo.CORREDOR, {velocidade_max = 12.2, aceleracao = 4.5, aderencia = 8.5, agilidade = 3.2,
			linha = 0.8, ousadia = 0.95, reacao = 0.18}),
		criar("ESPINHO", Estilo.BRIGAO, {velocidade_max = 12.0, aceleracao = 4.0, aderencia = 8.0, agilidade = 3.0,
			ousadia = 0.6, defesa = 0.5, agressividade = 0.7, foco_no_jogador = 1.0, recarga_ataque = 7.0}),
		criar("CACTO", Estilo.CAUTELOSO, {velocidade_max = 11.5, aceleracao = 3.6, aderencia = 7.5, agilidade = 2.0,
			linha = 0.5, inconsistencia = 0.01, erros = 0.002, ousadia = 0.25, defesa = 0.1, reacao = 0.3}),
	]
	return lista
