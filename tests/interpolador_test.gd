extends SceneTree
## Interpolação da rede: carro a 20 m/s mandando 30 poses/s, chegando em rajadas e com
## um pacote perdido. O mostrado deve andar liso (sem saltos nem ré), uns 0,1 s atrás,
## e extrapolar pouco quando as poses param.
## godot --headless --path . --script res://tests/interpolador_test.gd

const VELOCIDADE := 20.0
const PASSO := 1.0 / 30.0

func _initialize():
	_testar.call_deferred()

## Espera de verdade (o interpolador usa o relógio real, não o da física)
func _esperar(segundos: float):
	var fim := InterpoladorRede.agora() + segundos
	while InterpoladorRede.agora() < fim:
		await process_frame

func _testar():
	var interp := InterpoladorRede.new()
	assert(interp.vazio() and interp.pose() == Transform3D.IDENTITY)
	# O remetente tem outro relógio: 1000 s à frente do nosso
	var desvio := 1000.0
	var inicio := InterpoladorRede.agora()
	var enviadas := 0
	var ultimo_x := -INF
	var maior_salto := 0.0
	var amostras_vistas := 0
	while InterpoladorRede.agora() - inicio < 1.5:
		var agora := InterpoladorRede.agora()
		# Rajadas: o que deveria ter saído até agora chega de 2 em 2; o pacote 20 se perde
		while (enviadas + 2) * PASSO <= agora - inicio:
			for k in 2:
				if enviadas != 20:
					var t := inicio + enviadas * PASSO
					interp.adicionar(t + desvio, Vector3(t * VELOCIDADE, 0, 0), Quaternion.IDENTITY)
				enviadas += 1
		if not interp.vazio():
			var x := interp.pose().origin.x
			if ultimo_x > -INF:
				assert(x >= ultimo_x - 0.001, "Nunca anda para trás")
				maior_salto = maxf(maior_salto, x - ultimo_x)
			ultimo_x = x
			amostras_vistas += 1
			# Atrás da pose real mais ou menos ATRASO (mais a espera das rajadas)
			var real := (agora) * VELOCIDADE
			var atras := (real - x) / VELOCIDADE
			if amostras_vistas > 10:
				assert(atras > 0.05 and atras < 0.25, "Atraso %.3f s" % atras)
		await process_frame
	assert(amostras_vistas > 20)
	# Um quadro a 60 fps anda ~0,33 m; com rajadas e perda não pode saltar muito mais
	assert(maior_salto < 1.2, "Maior salto %.2f m" % maior_salto)

	# Poses param: extrapola no máximo EXTRAPOLA_MAX e segura
	await _esperar(0.6)
	var parado := interp.pose().origin.x
	await _esperar(0.2)
	assert(is_equal_approx(interp.pose().origin.x, parado), "Segura depois de extrapolar")

	# Remetente reiniciou (relógio voltou): recomeça da pose nova
	interp.adicionar(5.0, Vector3(-50, 0, 0), Quaternion.IDENTITY)
	assert(interp.pose().origin.is_equal_approx(Vector3(-50, 0, 0)))
	print("INTERPOLADOR_OK: rajadas, perda de pacote, atraso estável, extrapolação curta e reinício")
	quit()
