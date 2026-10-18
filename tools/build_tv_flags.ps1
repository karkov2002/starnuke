# Outil hors-jeu : drapeaux des chaînes de télévision (vignettes du guide des chaînes, scripts/ui/channel_tile.gd).
#   tools/build_tv_flags.ps1
# Pour chaque chaîne de assets/tv/channels.csv : PNG de 80 px de large téléchargé depuis flagcdn.com (drapeaux du
# projet flag-icons, licence MIT), enregistré sous assets/tv/flags/<CODE>.png (code pays du jeu, Natural Earth).
# Code ISO alpha-2 de chaque pays : Wikidata (P297, par le code alpha-3 P298), sauf codes propres à Natural Earth.
# Puis rescan dans l'éditeur Godot (les PNG sont importés comme textures).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root "assets/tv/flags"
New-Item -ItemType Directory -Force $out | Out-Null
$iso2 = @{ "KOS" = "xk"; "PSX" = "ps"; "SDS" = "ss" }

$channels = Import-Csv (Join-Path $root "assets/tv/channels.csv") -Encoding UTF8
$values = ($channels | Where-Object { -not $iso2.ContainsKey($_.code) } | ForEach-Object { '"' + $_.code + '"' }) -join " "
$query = "SELECT ?iso3 ?iso2 WHERE { VALUES ?iso3 { $values } ?c wdt:P298 ?iso3; wdt:P297 ?iso2. }"
$headers = @{ "User-Agent" = "StarNuke-tools/1.0 (game asset build)"; "Accept" = "application/sparql-results+json" }
$response = Invoke-WebRequest -Uri "https://query.wikidata.org/sparql" -Method Post -Headers $headers `
	-Body ("query=" + [uri]::EscapeDataString($query)) -ContentType "application/x-www-form-urlencoded" -UseBasicParsing
$rows = ([System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()) | ConvertFrom-Json).results.bindings
foreach ($r in $rows) {
	if (-not $iso2.ContainsKey($r.iso3.value)) { $iso2[$r.iso3.value] = $r.iso2.value.ToLower() }
}
foreach ($c in $channels) {
	if (-not $iso2.ContainsKey($c.code)) {
		Write-Output ("Attention : pas de code alpha-2 pour {0}" -f $c.code)
		continue
	}
	Invoke-WebRequest -Uri ("https://flagcdn.com/w80/{0}.png" -f $iso2[$c.code]) -OutFile (Join-Path $out ($c.code + ".png")) -UseBasicParsing
}
Write-Output ("{0} drapeaux dans {1}" -f (Get-ChildItem $out -Filter *.png).Count, $out)
