# Génère les sons d'alarme provisoires de la station (assets/audio/alarms/*.ogg, Ogg Vorbis mono 44,1 kHz),
# synthétisés par ffmpeg (aevalsrc : formules d'onde, pas d'enregistrement), en attendant des sons faits à la main
# (même nom, même format : ils les remplacent simplement). Chaque fichier est un cycle qui se joue en boucle
# (AudioStreamOggVorbis.loop, réglé par le code). Un fichier déjà présent n'est pas écrasé, sauf avec -Force :
# - alert_yellow.ogg (4 s) : alerte jaune (précaution), carillon doux de deux notes descendantes (660 puis 523 Hz,
#   timbre de cloche, décroissance) ;
# - alert_orange.ogg (2,4 s) : alerte orange (avertissement), trois bips secs à 740 Hz (onde presque carrée :
#   harmoniques impaires) de 0,25 s, séparés de 0,15 s ;
# - alert_red.ogg (1,6 s) : alerte rouge (urgence), sirène montante de 550 à 1450 Hz (balayage), continue.
# Crête ~ -1 dBFS ; le volume relatif se règle dans le code (AlertSirens). Usage :
#   powershell -ExecutionPolicy Bypass -File tools/build_alarm_sounds.ps1 [-Force]
# Nécessite ffmpeg (avec libvorbis) dans le PATH.

param([switch]$Force)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "assets/audio/alarms"
New-Item -ItemType Directory -Force $out | Out-Null

# Formules (t en secondes) ; les virgules sont protégées par les apostrophes du filtre.
$sounds = [ordered]@{
	"alert_yellow" = @{
		"duration" = 4.0
		"expr" = "0.6*gte(t,0)*min(1,t/0.005)*exp(-t*3.5)*(sin(2*PI*660*t)+0.4*sin(2*PI*1320*t)+0.2*sin(2*PI*1980*t))+0.6*gte(t,0.5)*min(1,(t-0.5)/0.005)*exp(-(t-0.5)*2.5)*(sin(2*PI*523*(t-0.5))+0.4*sin(2*PI*1046*(t-0.5))+0.2*sin(2*PI*1569*(t-0.5)))"
	}
	"alert_orange" = @{
		"duration" = 2.4
		"expr" = "lt(mod(t,0.4),0.25)*lt(t,1.2)*min(1,min(mod(t,0.4),0.25-mod(t,0.4))/0.005)*0.7*(sin(2*PI*740*t)+sin(6*PI*740*t)/3+sin(10*PI*740*t)/5)"
	}
	"alert_red" = @{
		"duration" = 1.6
		"expr" = "min(1,t/0.01)*min(1,(1.6-t)/0.03)*0.8*(sin(2*PI*(550*t+900*t*t/3.2))+0.3*sin(4*PI*(550*t+900*t*t/3.2)))"
	}
}

foreach ($name in $sounds.Keys) {
	$sound = $sounds[$name]
	$file = Join-Path $out "$name.ogg"
	if ((Test-Path $file) -and -not $Force) {
		Write-Output "$name.ogg : déjà présent, gardé (-Force pour le régénérer)"
		continue
	}
	$source = "aevalsrc='" + $sound.expr + "':s=44100:d=" + $sound.duration
	& ffmpeg -hide_banner -loglevel error -y -f lavfi -i $source -ac 1 -c:a libvorbis -q:a 6 $file
	if ($LASTEXITCODE -ne 0) { throw "ffmpeg : échec pour $name" }
	Write-Output "$name.ogg"
}
