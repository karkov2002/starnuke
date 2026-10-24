# Enchaîne les vérifications headless du jeu (celles qui rendent un code de retour : 0 si tout passe, 1 sinon) et
# s'arrête à la première qui échoue. À lancer avant chaque commit qui touche au code du jeu ; l'éditeur Godot peut
# rester ouvert, une partie en cours aussi (les sondes tournent dans leur propre processus, sans fenêtre).
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_all_probes.ps1              toutes les étapes
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_all_probes.ps1 -KeepGoing   sans s'arrêter au premier échec
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_all_probes.ps1 -Only nuke_probe,orbit_probe
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_all_probes.ps1 -ShowOutput  sortie complète de chaque étape
# Chaque étape passe par run_probe.ps1 ; sa sortie n'est affichée qu'en cas d'échec (ou avec -ShowOutput).
# Les bancs de mesure (bench, cpu_probe, mushroom_probe, flash_probe…) et les sondes à captures (alert, settings,
# torch, exposure…) ne sont pas enchaînés : ils demandent une fenêtre, l'éditeur fermé, ou un œil humain.
param(
    [string[]]$Only = @(),
    [switch]$KeepGoing,
    [switch]$ShowOutput,
    [string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [int]$Tail = 40
)
# Étapes, de la plus rapide à la plus longue : une erreur simple sort vite.
$steps = @(
    @{ Name = "check_campaign"; Script = "tools/check_campaign.gd"; What = "campagnes du dossier campaign/ (format, missions, délais)" },
    @{ Name = "orbit_probe";    Probe = "orbit_probe";    What = "orbite et pose de la scène contre la référence" },
    @{ Name = "nuke_probe";     Probe = "nuke_probe";     What = "explosions : shaders et bilans contre la référence" },
    @{ Name = "campaign_probe"; Probe = "campaign_probe"; What = "campagne officielle jouée de bout en bout" },
    @{ Name = "console_probe";  Probe = "console_probe";  What = "écrans à vue assise (poste, radio, télévision, tablette)" }
)
if ($Only.Count -gt 0) {
    # Lancé par « powershell -File », une liste « a,b » arrive en une seule chaîne.
    $Only = @($Only | ForEach-Object { $_ -split "," } | ForEach-Object { $_.Trim() })
    $steps = @($steps | Where-Object { $Only -contains $_.Name })
    if ($steps.Count -eq 0) { throw "Aucune étape ne s'appelle $($Only -join ', ')" }
}

$runner = Join-Path $PSScriptRoot "run_probe.ps1"
$results = @()
$failed = 0
$total = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($step in $steps) {
    Write-Host ("> {0,-15} {1}" -f $step.Name, $step.What)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($step.ContainsKey("Script")) {
        $scriptArgs = @(); if ($step.ContainsKey("Args")) { $scriptArgs = $step.Args }
        $lines = & $runner -Script $step.Script -ScriptArgs $scriptArgs -Godot $Godot -Tail $Tail
    } else {
        $lines = & $runner -Probe $step.Probe -Godot $Godot -Tail $Tail
    }
    $code = $LASTEXITCODE
    $watch.Stop()
    $seconds = $watch.Elapsed.TotalSeconds
    if ($code -eq 0) {
        Write-Host ("  OK   {0,6:N1} s" -f $seconds) -ForegroundColor Green
        if ($ShowOutput) { $lines | ForEach-Object { "    $_" } }
    } else {
        $failed++
        Write-Host ("  ECHEC (code {0}) {1,6:N1} s" -f $code, $seconds) -ForegroundColor Red
        $lines | ForEach-Object { "    $_" }
    }
    $results += @{ Name = $step.Name; Code = $code; Seconds = $seconds }
    if ($code -ne 0 -and -not $KeepGoing) { break }
}
$total.Stop()

""
"Bilan ({0:N0} s) :" -f $total.Elapsed.TotalSeconds
foreach ($r in $results) {
    $state = if ($r.Code -eq 0) { "OK" } else { "ECHEC" }
    "  {0,-15} {1,-6} {2,6:N1} s" -f $r.Name, $state, $r.Seconds
}
$skipped = $steps.Count - $results.Count
if ($skipped -gt 0) { "  ($skipped étape(s) non lancée(s) après l'échec ; -KeepGoing pour tout enchaîner)" }
if ($failed -gt 0) { Write-Host "$failed étape(s) en échec." -ForegroundColor Red } else { Write-Host "Tout passe." -ForegroundColor Green }
exit $(if ($failed -gt 0) { 1 } else { 0 })
