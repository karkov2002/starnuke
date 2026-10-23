# Lance une sonde headless (tools/bench/<nom>.tscn) ou un script SceneTree (-Script) avec l'exécutable Godot de Steam et
# affiche sa sortie ; code de retour : celui de Godot (0 si tout passe).
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_probe.ps1 campaign_probe
#   powershell -ExecutionPolicy Bypass -File tools/bench/run_probe.ps1 -Script tools/balance_campaign.gd -ScriptArgs "starnuke","200"
param(
    [string]$Probe = "console_probe",
    [string]$Script = "",
    [string[]]$ScriptArgs = @(),
    [string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [int]$Tail = 120
)
$out = Join-Path $env:TEMP "probe_out.txt"
$err = Join-Path $env:TEMP "probe_err.txt"
if ($Script -ne "") {
    $list = @("--headless", "--path", ".", "-s", $Script)
    if ($ScriptArgs.Count -gt 0) { $list += "--"; $list += $ScriptArgs }
} else {
    $list = @("--headless", "--path", ".", "res://tools/bench/$Probe.tscn")
}
$p = Start-Process -FilePath $Godot -ArgumentList $list -Wait -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
Get-Content $out -Encoding UTF8 | Select-Object -Last $Tail
"--- stderr ---"
Get-Content $err -Encoding UTF8 | Select-Object -Last 30
"EXIT=$($p.ExitCode)"
exit $p.ExitCode
