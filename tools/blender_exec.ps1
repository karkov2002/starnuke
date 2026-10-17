# Outil hors-jeu : exécute du Python dans le Blender ouvert, via l'extension officielle « MCP » de Blender Lab
# (Blender ≥ 5.1, serveur TCP sur localhost:9876 à démarrer dans Blender : Préférences › Extensions › MCP, ou
# `blender --background fichier.blend --command blender_mcp`). Protocole : requête JSON {"type": "execute",
# "code": "...", "strict_json": false} terminée par un octet nul ; réponse JSON {"status", "result", "stdout",
# "stderr"}. Le code assigne `result` pour renvoyer une valeur (sérialisée en JSON, `repr` sinon).
# Usage, depuis PowerShell (un code passé en -Code contient espaces et guillemets : l'appeler avec « & » plutôt
# que par un powershell.exe imbriqué, qui redécoupe les arguments ; pour un script long, -File script.py) :
#   & ./tools/blender_exec.ps1 -Code 'import bpy; result = bpy.data.filepath'
#   & ./tools/blender_exec.ps1 -File script.py [-Server 127.0.0.1] [-Port 9876] [-TimeoutS 60]
param(
    [string]$Code = "",
    [string]$File = "",
    [string]$Server = "127.0.0.1",
    [int]$Port = 9876,
    [int]$TimeoutS = 60
)
$ErrorActionPreference = "Stop"
if ($File -ne "") { $Code = [System.IO.File]::ReadAllText($File, [System.Text.Encoding]::UTF8) }
if ($Code -eq "") { Write-Error "Rien à exécuter : -Code ou -File"; exit 2 }
$client = New-Object System.Net.Sockets.TcpClient($Server, $Port)
$stream = $client.GetStream()
$stream.ReadTimeout = $TimeoutS * 1000
$request = @{ type = "execute"; code = $Code; strict_json = $false } | ConvertTo-Json -Compress -Depth 4
$bytes = [System.Text.Encoding]::UTF8.GetBytes($request + [char]0)
$stream.Write($bytes, 0, $bytes.Length)
$stream.Flush()
# La réponse est elle aussi terminée par un octet nul : lecture jusqu'à ce terminateur.
$memory = New-Object System.IO.MemoryStream
$buffer = New-Object byte[] 65536
do {
    $n = $stream.Read($buffer, 0, $buffer.Length)
    if ($n -le 0) { break }
    $memory.Write($buffer, 0, $n)
} while ($buffer[$n - 1] -ne 0)
$client.Close()
$text = [System.Text.Encoding]::UTF8.GetString($memory.ToArray()).TrimEnd([char]0)
$response = $text | ConvertFrom-Json
if ($response.stdout) { Write-Output $response.stdout }
if ($response.stderr) { Write-Output "stderr: $($response.stderr)" }
if ($response.status -ne "ok") { Write-Output "erreur : $($response.message)"; exit 1 }
if ($null -ne $response.result) { $response.result | ConvertTo-Json -Depth 8 -Compress }
