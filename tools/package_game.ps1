# Outil hors-jeu : construit la version Windows distribuable de Star Nuke et son archive zip.
#  1. export « release » du preset « Windows Desktop » (export_presets.cfg) : Star Nuke.exe + Star Nuke.pck (toutes les
#     ressources, plus assets/population_2030.bin, fichier brut ajouté par include_filter ; tools/ et le cache du MCP exclus) ;
#  2. copie des tuiles HD (assets/earth_tiles, earth_night_tiles, earth_cloud_tiles) à côté de l'exécutable : leurs
#     dossiers ont un .gdignore et ne peuvent pas entrer dans le .pck. Le jeu exporté les trouve quand même : un
#     fichier res:// absent du .pck est cherché dans le dossier de l'exécutable (<dossier de l'exe>/assets/…) ;
#  3. copie des dossiers playlist/ (musiques) et campaign/ (campagnes) : .gdignore, hors du .pck, lus sur le disque
#     par le jeu ;
#  4. archive zip du dossier, nommée d'après la version du jeu (application/config/version de project.godot,
#     convention x.y.z du README « Version distribuable ») : StarNuke_<version>.zip ; la même version est affichée
#     en bas à droite de l'écran de démarrage et portée par les métadonnées de l'exe (champs de version du preset
#     laissés vides : Godot y met celle du projet).
# Le dossier de sortie est vidé des fichiers d'un export précédent (exe, pck, assets). L'éditeur Godot peut rester
# ouvert. Usage :
#   powershell -ExecutionPolicy Bypass -File tools/package_game.ps1 [-Output <dossier>] [-Zip <fichier.zip>] [-Godot <godot.exe>]
param(
    [string]$Output = (Join-Path $PSScriptRoot "..\..\exe\starnuke"),
    [string]$Zip = "",
    [string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
)
$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Version du jeu, lue dans project.godot (config/version="x.y.z").
$versionLine = Select-String -Path (Join-Path $project "project.godot") -Pattern '^config/version="([^"]+)"' | Select-Object -First 1
if (-not $versionLine) { throw "project.godot : application/config/version absent (convention x.y.z, voir le README)" }
$version = $versionLine.Matches[0].Groups[1].Value
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "project.godot : version « $version » hors convention x.y.z" }
Write-Host "Star Nuke $version"
if ($Zip -eq "") { $Zip = Join-Path $PSScriptRoot "..\..\exe\StarNuke_$version.zip" }
New-Item -ItemType Directory -Force $Output | Out-Null
$Output = (Resolve-Path $Output).Path
$exe = Join-Path $Output "Star Nuke.exe"

foreach ($old in @("Star Nuke.exe", "Star Nuke.console.exe", "Star Nuke.pck", "assets", "playlist", "campaign")) {
    $path = Join-Path $Output $old
    if (Test-Path $path) { Remove-Item -Recurse -Force $path }
}

Write-Host "Export release -> $exe"
# Godot est un exécutable graphique : PowerShell ne l'attend que s'il est lancé avec -Wait.
$arguments = @("--headless", "--path", "`"$project`"", "--export-release", "`"Windows Desktop`"", "`"$exe`"")
Start-Process -FilePath $Godot -ArgumentList $arguments -Wait -NoNewWindow
if (-not (Test-Path $exe) -or -not (Test-Path (Join-Path $Output "Star Nuke.pck"))) {
    throw "Export raté (modèles d'export 4.7 installés ? preset « Windows Desktop » ?)"
}

foreach ($tiles in @("earth_tiles", "earth_night_tiles", "earth_cloud_tiles")) {
    $source = Join-Path $project "assets\$tiles"
    $target = Join-Path $Output "assets\$tiles"
    Write-Host "Tuiles $tiles"
    robocopy $source $target /MIR /XF .gdignore /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copie des tuiles $tiles ratée (robocopy $LASTEXITCODE)" }
}

# Playlists : dossier playlist/ à côté de l'exécutable (jamais dans le .pck, .gdignore) ; le joueur y ajoute les
# siennes (un sous-dossier par playlist), lues au lancement par l'autoload Music.
Write-Host "Playlists"
robocopy (Join-Path $project "playlist") (Join-Path $Output "playlist") /MIR /XF .gdignore /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copie des playlists ratée (robocopy $LASTEXITCODE)" }

# Campagnes : dossier campaign/ à côté de l'exécutable (jamais dans le .pck, .gdignore) ; les joueurs y ajoutent les
# leurs (un sous-dossier par campagne, avec son campaign.json), lues par scripts/campaigns.gd.
Write-Host "Campagnes"
robocopy (Join-Path $project "campaign") (Join-Path $Output "campaign") /MIR /XF .gdignore /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Copie des campagnes ratée (robocopy $LASTEXITCODE)" }

$Zip = [System.IO.Path]::GetFullPath($Zip)
if (Test-Path $Zip) { Remove-Item -Force $Zip }
Write-Host "Archive -> $Zip"
# tar de Windows (bsdtar) écrit des zip, bien plus vite que Compress-Archive pour des milliers de tuiles.
Push-Location (Split-Path $Output -Parent)
try {
    # Celui de Windows explicitement : un tar de Git Bash dans le PATH ne comprend pas les chemins « E:\… ».
    & (Join-Path $env:SystemRoot "System32\tar.exe") -a -c -f $Zip (Split-Path $Output -Leaf)
    if ($LASTEXITCODE -ne 0) { throw "Archive ratée (tar $LASTEXITCODE)" }
} finally {
    Pop-Location
}
$size = (Get-Item $Zip).Length / 1MB
Write-Host ("Terminé : {0} ({1:N0} Mo)" -f $Zip, $size)
