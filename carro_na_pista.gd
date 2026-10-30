class_name CarroNaPista
extends RefCounted
## Retrato de um carro em coordenadas da pista, que é o que a IA enxerga de todos
## (adversários e jogador): s = metros ao longo da volta, d = desvio lateral
## (positivo à direita), v = velocidade ao longo da pista e progresso = metros desde a
## linha de largada somando as voltas (negativo antes de cruzá-la no começo).

var s := 0.0
var d := 0.0
var v := 0.0
var progresso := 0.0
var eh_jogador := false
## Fora da pista, em transição ou parado no grid antes da largada: a IA ignora
var presente := true
## Adversário dono deste retrato (null para o jogador)
var rival: CarroRival
## Outro jogador da corrida em grupo (vazio = o jogador deste Quest)
var nome_remoto := ""

func nome() -> String:
	if rival:
		return rival.perfil.nome
	return nome_remoto if nome_remoto != "" else "VOCÊ"
