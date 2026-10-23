# Gera as falas da assistente Yui (voz/yui/*.wav) a partir de voz/yui/falas.json,
# com a voz feminina pt-BR do Windows (Microsoft Maria). O timbre (levemente aguda,
# suave, com coro discreto) é aplicado no jogo, no barramento de áudio "Yui"
# (assistente_yui.gd), então dá para ajustar sem gerar os arquivos de novo.
#
# Uso (na raiz do projeto): powershell -ExecutionPolicy Bypass -File ferramentas/gerar_voz_yui.ps1
# Depois abra o editor (ou rode godot --headless --import) para importar os .wav.
param(
	[string]$Voz = "Microsoft Maria Desktop",
	# Velocidade da fala (-10 a 10): 0 é o ritmo natural; mais rápido que isso, somado
	# ao tom acima no jogo, emenda as sílabas e fica difícil de entender no headset
	[int]$Velocidade = 0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

$raiz = Split-Path -Parent $PSScriptRoot
$pasta = Join-Path $raiz "voz/yui"
$falas = Get-Content -Raw -Encoding UTF8 (Join-Path $pasta "falas.json") | ConvertFrom-Json

$sintetizador = New-Object System.Speech.Synthesis.SpeechSynthesizer
$sintetizador.SelectVoice($Voz)
$sintetizador.Rate = $Velocidade
$formato = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(22050, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)

foreach ($fala in $falas.PSObject.Properties) {
	$arquivo = Join-Path $pasta ($fala.Name + ".wav")
	$sintetizador.SetOutputToWaveFile($arquivo, $formato)
	$sintetizador.Speak($fala.Value)
	$sintetizador.SetOutputToNull()
	Write-Output ("{0}: {1:N1} KB" -f $fala.Name, ((Get-Item $arquivo).Length / 1KB))
}
$sintetizador.Dispose()
