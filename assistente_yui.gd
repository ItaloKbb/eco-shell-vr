class_name AssistenteYui
extends Node
## Yui, a assistente do SENAI: ao abrir o jogo ela se apresenta (dentro da esfera de
## nascimento), na primeira largada conta que lugar é este, e ao entrar numa corrida
## encoraja o piloto. Se ele bate na parede invisível do abismo, manda procurar uma ponte. Aparece num pequeno painel holográfico com o rosto dela (a boca
## acompanha a voz) e a legenda da fala.
##
## As falas ficam em voz/yui/falas.json (legenda) e voz/yui/<id>.wav (voz gravada pela
## ferramentas/gerar_voz_yui.ps1). O timbre, levemente agudo e suave com um coro
## discreto, vem do barramento "Yui": tom um pouco acima, ronco cortado, agudos
## amaciados, compressão leve, chorus e um fio de sala. Ajustável aqui, sem gerar os
## .wav de novo.

const PASTA := "res://voz/yui"
const BARRAMENTO := "Yui"
const COR := Color(0.35, 0.95, 0.9)
const FALAS_CORRIDA := ["corrida_1", "corrida_2", "corrida_3"]
const FALAS_LUGAR := ["lugar_1", "lugar_2", "lugar_3"]

## Quanto a voz sobe de tom (1 = original). Cada passo acima borra as consoantes;
## acima de ~1,2 ela já fica metálica e difícil de entender
@export_range(1.0, 1.6, 0.01) var tom := 1.12
## Alto o bastante para os alto-falantes do Quest vencerem motor e música
@export var volume_db := 4.0
## Pausa entre duas falas seguidas e quanto o painel fica depois da última (s)
@export var pausa := 0.45
@export var permanencia := 2.5
## Espera depois de abrir o jogo antes da apresentação (tempo do fade e do painel)
@export var atraso_inicio := 2.0
## Intervalo mínimo entre dois avisos de "procure uma ponte" (s): quem fica raspando
## na parede não ouve o aviso em repetição
@export var intervalo_ponte := 25.0

var carro: RigidBody3D
var musica: Node
var falando := false

var _textos := {}
var _fila: Array[String] = []
var _player: AudioStreamPlayer
var _analisador: AudioEffectSpectrumAnalyzerInstance
var _painel: PainelHolografico
var _rosto: RostoYui
var _legenda: Label
var _apresentou_lugar := false
var _ultima_corrida := ""
## Tempo (s, relógio do jogo) do último aviso de procurar uma ponte
var _aviso_ponte := -INF
## Segundos até recolher o painel (-1 = aberto enquanto fala)
var _fechar_em := -1.0

func _ready():
	add_to_group("yui")
	_carregar_textos()
	_montar_barramento()
	_player = AudioStreamPlayer.new()
	_player.bus = BARRAMENTO
	_player.volume_db = volume_db
	_player.finished.connect(_terminou_fala)
	add_child(_player)
	if carro:
		_montar_painel.call_deferred()
		carro.largou.connect(_largou)
		carro.bateu_barreira.connect(_bateu_barreira)
		get_tree().create_timer(atraso_inicio).timeout.connect(func():
			if carro.em_ritual:
				falar(["boas_vindas"]))

## Enfileira falas pelo id; começa na hora se ela não estiver falando
func falar(ids: Array):
	for id in ids:
		if _textos.has(id) and ResourceLoader.exists(PASTA.path_join(id + ".wav")):
			_fila.append(id)
	if not falando:
		_proxima()

## Entrada numa corrida (mundos.gd): uma fala de encorajamento, sem repetir a última,
## depois de `chegada` (a apresentação do mapa, se houver).
## Corta o que estiver falando: a corrida é o que importa agora
## `sprint`: pista ponta a ponta, sem a fala que conta as três voltas
func falar_corrida(chegada := "", sprint := false):
	var opcoes := FALAS_CORRIDA.filter(func(id): return id != _ultima_corrida and not (sprint and id == "corrida_2"))
	_ultima_corrida = opcoes.pick_random()
	_fila.clear()
	_player.stop()
	falando = false
	falar([chegada, _ultima_corrida] if not chegada.is_empty() else [_ultima_corrida])

## Primeira largada da sessão (saída da esfera): conta que lugar é este
func _largou():
	if _apresentou_lugar:
		return
	_apresentou_lugar = true
	_fila.erase("boas_vindas")
	if falando and _player.stream and _player.stream.resource_path.ends_with("boas_vindas.wav"):
		_player.stop()
		falando = false
	falar(FALAS_LUGAR)

## Bateu na parede do abismo: aviso para procurar uma ponte, sem cortar outra fala
func _bateu_barreira():
	var agora := Time.get_ticks_msec() / 1000.0
	if falando or agora - _aviso_ponte < intervalo_ponte:
		return
	_aviso_ponte = agora
	falar(["procure_ponte"])

func _proxima():
	if _fila.is_empty():
		falando = false
		_fechar_em = permanencia
		return
	var id: String = _fila.pop_front()
	falando = true
	_fechar_em = -1.0
	_player.stream = load(PASTA.path_join(id + ".wav"))
	_player.play()
	if _legenda:
		_legenda.text = _textos[id]
		_painel.mostrar()

func _terminou_fala():
	if _fila.is_empty():
		_proxima()
		return
	await get_tree().create_timer(pausa).timeout
	if not _player.playing:
		_proxima()

func _process(delta: float):
	if musica and "voz_falando" in musica:
		musica.voz_falando = falando
	var nivel := 0.0
	if _player.playing and _analisador:
		nivel = clampf(_analisador.get_magnitude_for_frequency_range(150.0, 3500.0).length() * 9.0, 0.0, 1.0)
	if _rosto == null:
		return
	_rosto.atualizar(nivel)
	if _painel.visible:
		_painel.redesenhar("%s|%d|%d" % [_legenda.text, _rosto.passo_boca(), int(_rosto.piscando())])
	# Contado no tempo do jogo, igual aos timers das falas
	if _fechar_em > 0.0:
		_fechar_em -= delta
		if _fechar_em <= 0.0:
			_fechar_em = -1.0
			_painel.fechar()

func _carregar_textos():
	var arquivo := FileAccess.open(PASTA.path_join("falas.json"), FileAccess.READ)
	if arquivo == null:
		push_warning("Yui: voz/yui/falas.json não encontrado")
		return
	var dados = JSON.parse_string(arquivo.get_as_text())
	if dados is Dictionary:
		_textos = dados

## Barramento da voz: só o ronco cortado, tom um pouco acima, agudos amaciados
## (sem chiado no "s"), compressão leve para as sílabas fracas não sumirem sob o motor,
## um coro discreto (o "dobrado" dos vocaloids), um fio de sala e o analisador da boca
func _montar_barramento():
	var i := AudioServer.get_bus_index(BARRAMENTO)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, BARRAMENTO)
		AudioServer.set_bus_send(i, "Master")
	while AudioServer.get_bus_effect_count(i) > 0:
		AudioServer.remove_bus_effect(i, 0)
	# Bandas: 32, 100, 320, 1k, 3,2k e 10k Hz
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(0, -12.0)
	eq.set_band_gain_db(1, -2.0)
	eq.set_band_gain_db(2, 1.0)
	eq.set_band_gain_db(3, 1.0)
	eq.set_band_gain_db(4, 1.5)
	eq.set_band_gain_db(5, -3.0)
	AudioServer.add_bus_effect(i, eq)
	var altura := AudioEffectPitchShift.new()
	altura.pitch_scale = tom
	altura.oversampling = 8
	# Janela curta: preserva o ataque das consoantes, que é o que dá inteligibilidade
	altura.fft_size = AudioEffectPitchShift.FFT_SIZE_512
	AudioServer.add_bus_effect(i, altura)
	var compressor := AudioEffectCompressor.new()
	compressor.threshold = -18.0
	compressor.ratio = 3.0
	compressor.attack_us = 5000.0
	compressor.release_ms = 120.0
	compressor.gain = 3.0
	AudioServer.add_bus_effect(i, compressor)
	var coro := AudioEffectChorus.new()
	coro.voice_count = 2
	coro.dry = 1.0
	coro.wet = 0.1
	coro.set_voice_delay_ms(0, 12.0)
	coro.set_voice_rate_hz(0, 0.8)
	coro.set_voice_depth_ms(0, 1.5)
	coro.set_voice_delay_ms(1, 18.0)
	coro.set_voice_rate_hz(1, 1.1)
	coro.set_voice_depth_ms(1, 1.8)
	AudioServer.add_bus_effect(i, coro)
	var sala := AudioEffectReverb.new()
	sala.room_size = 0.25
	sala.damping = 0.6
	sala.wet = 0.05
	sala.dry = 1.0
	AudioServer.add_bus_effect(i, sala)
	AudioServer.add_bus_effect(i, AudioEffectSpectrumAnalyzer.new())
	_analisador = AudioServer.get_bus_effect_instance(i, AudioServer.get_bus_effect_count(i) - 1)

## Painel pequeno no alto à esquerda da visão: no monitor preso à câmera; na VR preso
## ao carro no cockpit (não segue a cabeça). Opaco e por cima de tudo, para o vidro da
## bolha e o bico não esconderem
func _montar_painel():
	var vr := get_viewport().use_xr
	_painel = PainelHolografico.new(Vector2i(760, 240), Vector2(0.38, 0.12), vr, "SENAI // ASSISTENTE YUI")
	_painel.opaco = true
	_painel.visible = false
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 18)
	linha.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_painel.coluna.add_child(linha)
	_rosto = RostoYui.new()
	_rosto.custom_minimum_size = Vector2(150, 150)
	linha.add_child(_rosto)
	_legenda = PainelHolografico.rotulo("", 23, Color(0.92, 1.0, 1.0))
	_legenda.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legenda.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_legenda.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	linha.add_child(_legenda)
	if vr:
		carro.add_child(_painel)
		var olho: Vector3 = carro.ANCORA_CABECA_LOCAL
		var pos := olho + Vector3(-0.38, 0.17, -0.62)
		_painel.transform = Transform3D(Basis.looking_at(olho - pos, Vector3.UP, true), pos)
	else:
		carro.camera.add_child(_painel)
		_painel.transform = Transform3D(Basis.IDENTITY, Vector3(-0.42, 0.21, -0.75))
	# Com a fala já em andamento (o painel nasce um frame depois)
	if falando and _player.stream:
		_legenda.text = _textos.get(_player.stream.resource_path.get_file().get_basename(), "")
		_painel.mostrar()
