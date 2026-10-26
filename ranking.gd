extends Node
## Ranking geral do evento (autoload). No servidor guarda TODAS as tentativas, de todas
## as pistas e dias, em user://ranking.json (nunca zera sozinho) e calcula o top: só o
## melhor tempo de cada jogador. No cliente só guarda o top recebido do servidor.
## O telão do lobby e o painel do servidor escutam ranking_mudou.

const ARQUIVO := "user://ranking.json"
const TOP := 10

signal ranking_mudou(top: Array)
## Servidor: entrou um tempo novo (para destacar no painel e no log)
signal novo_tempo(registro: Dictionary)

## Servidor: {nome, tempo, pista, data, oculos} de cada corrida terminada
var tentativas: Array[Dictionary] = []
## Top atual: melhor tempo por jogador, do mais rápido ao mais lento
var top: Array = []

func carregar():
	tentativas.clear()
	if FileAccess.file_exists(ARQUIVO):
		var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
		if dados is Array:
			for registro in dados:
				if registro is Dictionary and registro.has("nome") and registro.has("tempo"):
					tentativas.append(registro)
	_recalcular()

func salvar():
	var arquivo := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if arquivo == null:
		push_warning("Não foi possível salvar o ranking: %s" % error_string(FileAccess.get_open_error()))
		return
	arquivo.store_string(JSON.stringify(tentativas, "\t"))

## Servidor: a data/hora é carimbada aqui, nunca vem do cliente
func adicionar(nome: String, tempo: float, pista: String, oculos: String) -> Dictionary:
	var registro := {
		"nome": nome,
		"tempo": snappedf(tempo, 0.001),
		"pista": pista,
		"data": Time.get_datetime_string_from_system(false, true),
		"oculos": oculos,
	}
	tentativas.append(registro)
	salvar()
	novo_tempo.emit(registro)
	_recalcular()
	return registro

## Servidor: guarda uma cópia antes de apagar
func limpar() -> String:
	var backup := "user://ranking_backup_%s.json" % _carimbo()
	if FileAccess.file_exists(ARQUIVO):
		DirAccess.copy_absolute(ARQUIVO, backup)
	tentativas.clear()
	salvar()
	_recalcular()
	return backup

## Servidor: CSV com todas as tentativas; devolve o caminho no disco
func exportar_csv() -> String:
	var caminho := "user://ranking_%s.csv" % _carimbo()
	var arquivo := FileAccess.open(caminho, FileAccess.WRITE)
	if arquivo == null:
		return ""
	arquivo.store_csv_line(PackedStringArray(["nome", "tempo", "pista", "data", "oculos"]))
	for registro in tentativas:
		arquivo.store_csv_line(PackedStringArray([registro.nome, "%.3f" % float(registro.tempo), registro.get("pista", ""),
			registro.get("data", ""), registro.get("oculos", "")]))
	return ProjectSettings.globalize_path(caminho)

## Cliente: top vindo do servidor
func receber_top(lista: Array):
	top = lista
	ranking_mudou.emit(top)

func _recalcular():
	var melhores := {}
	for registro in tentativas:
		var chave := str(registro.nome).strip_edges().to_lower()
		if not melhores.has(chave) or float(registro.tempo) < float(melhores[chave].tempo):
			melhores[chave] = registro
	var lista: Array = melhores.values()
	lista.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.tempo) < float(b.tempo))
	top = lista.slice(0, TOP)
	ranking_mudou.emit(top)

func _carimbo() -> String:
	return Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")

static func formatar_tempo(s: float) -> String:
	if s < 0.0:
		return "-:--.--"
	return "%d:%05.2f" % [int(s / 60.0), fmod(s, 60.0)]
