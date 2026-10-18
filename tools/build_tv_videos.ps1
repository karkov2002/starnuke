# Vidéos des chaînes d'information (télévision du module Commande, scripts/ui/tv_display.gd).
#
# Maîtres modifiables (dossier assets/tv/source/, .gdignore : Godot ne les importe pas) :
#   explosion.mp4   images du mur vidéo de l'édition spéciale (1000 x 400), à remplacer à volonté ;
#   normal.mp4      présentateurs, édition normale (960 x 600, 25 im/s, boucle de 12 s) ;
#   alert.mp4       présentateurs, édition spéciale « alerte info » (même format) ;
#   tv_studio.blend scènes Blender du plateau (Studio_Normal, Studio_Alerte), à retoucher dans Blender ;
#   <CODE>/normal.mp4, <CODE>/alert.mp4 (facultatif) : vidéos propres au pays <CODE> (code ISO de assets/tv/channels.csv).
# Vidéos du jeu (Ogg Theora, seul format lu par Godot) : assets/tv/video/normal.ogv, alert.ogv et
# assets/tv/video/<CODE>/normal.ogv, alert.ogv, converties depuis les maîtres.
#
#   tools/build_tv_videos.ps1                 # tout : rendus Blender, maîtres MP4, conversion .ogv
#   tools/build_tv_videos.ps1 -Studio         # garde explosion.mp4 (remplacé à la main) : rend le plateau, convertit
#   tools/build_tv_videos.ps1 -ConvertOnly    # maîtres retouchés dans un logiciel vidéo : conversion .ogv seulement
# Puis rescan dans l'éditeur Godot.
param(
	[switch]$ConvertOnly,
	[switch]$Studio,
	[int]$Quality = 8
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root "assets/tv/source"
$video = Join-Path $root "assets/tv/video"
$frames = Join-Path $env:TEMP "starnuke_tv_frames"
$blender = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) {
	$ffmpeg = (Get-ChildItem "$env:LOCALAPPDATA/Microsoft/WinGet/Packages/Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe" | Select-Object -First 1).FullName
}
if (-not $ffmpeg) { throw "ffmpeg introuvable (winget install Gyan.FFmpeg)" }

function Render([string]$mode) {
	$ErrorActionPreference = "Continue" # Windows PowerShell 5.1 : la sortie d'erreur de Blender (avertissements) n'est pas un échec
	& $blender --background --factory-startup --python (Join-Path $root "tools/blender/build_tv_studio.py") -- $mode $source $frames
	if ($LASTEXITCODE -ne 0) { throw "Blender : échec du mode $mode" }
}

function Encode-Master([string]$name, [string]$out) {
	$ErrorActionPreference = "Continue"
	Get-ChildItem (Join-Path $frames $name) -Filter "apercu_*" -ErrorAction SilentlyContinue | Remove-Item
	& $ffmpeg -hide_banner -loglevel error -y -framerate 25 -i (Join-Path $frames "$name/%04d.png") `
		-c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p $out
	if ($LASTEXITCODE -ne 0) { throw "ffmpeg : échec de $out" }
}

if (-not $ConvertOnly) {
	Remove-Item -Recurse -Force $frames -ErrorAction SilentlyContinue
	if (-not $Studio) {
		Render "explosion"
		Encode-Master "explosion" (Join-Path $source "explosion.mp4")
	}
	Render "studio"
	Encode-Master "normal" (Join-Path $source "normal.mp4")
	Encode-Master "alert" (Join-Path $source "alert.mp4")
	Remove-Item -Recurse -Force $frames
}

# Conversion des maîtres (normal / alert, aussi dans les sous-dossiers de pays) en Ogg Theora sans son.
Get-ChildItem $source -Recurse -File | Where-Object { $_.BaseName -in @("normal", "alert") -and $_.Extension -ne ".ogv" } |
	ForEach-Object {
		$relative = $_.DirectoryName.Substring($source.Length).TrimStart("\", "/")
		$dir = if ($relative) { Join-Path $video $relative } else { $video }
		New-Item -ItemType Directory -Force $dir | Out-Null
		$out = Join-Path $dir ($_.BaseName + ".ogv")
		$ErrorActionPreference = "Continue"
		& $ffmpeg -hide_banner -loglevel error -y -i $_.FullName -an -c:v libtheora -q:v $Quality -g 25 $out
		if ($LASTEXITCODE -ne 0) { throw "ffmpeg : échec de $out" }
		Write-Output ("{0} -> {1} ({2:N1} Mo)" -f $_.Name, $out, ((Get-Item $out).Length / 1MB))
	}
