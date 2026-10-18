# Outil hors-jeu : noms des pays et des capitales dans les langues des chaînes de télévision (bandeau défilant de
# l'édition spéciale, scripts/tv_news.gd), téléchargés depuis Wikidata (libellés, licence CC0).
#   tools/build_tv_news_names.ps1
# Sorties (colonnes : code, puis une colonne par langue de assets/tv/channels.csv ; case vide : nom anglais du jeu) :
#   assets/tv/news_country_names.csv : tous les pays et territoires du masque (codes ADM0 de locale/countries.csv) ;
#   assets/tv/news_capital_names.csv : capitales des chaînes (la plus proche des coordonnées de channels.csv quand
#   un pays en a plusieurs).
# Correspondance code ADM0 (Natural Earth) -> élément Wikidata : par le code ISO 3166-1 alpha-3 (P298), sauf
# quelques codes propres à Natural Earth (OVERRIDES). Fichiers modifiables à la main (tableur, UTF-8).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$endpoint = "https://query.wikidata.org/sparql"
$headers = @{ "User-Agent" = "StarNuke-tools/1.0 (game asset build)"; "Accept" = "application/sparql-results+json" }

# Langue du jeu -> codes de langue Wikidata, par ordre de préférence.
$wikiLangs = @{ "zh" = @("zh-hans", "zh-cn", "zh"); "zh_TW" = @("zh-tw", "zh-hant", "zh"); "sr" = @("sr-ec", "sr"); "nb" = @("nb", "no") }
$overrides = @{ "KOS" = "Q1246"; "PSX" = "Q219060"; "SDS" = "Q958"; "SAH" = "Q6250"; "CYN" = "Q23681"; "SOL" = "Q34754" }

function Invoke-Sparql([string]$query) {
	$body = "query=" + [uri]::EscapeDataString($query)
	for ($try = 0; $try -lt 4; $try++) {
		try {
			$response = Invoke-WebRequest -Uri $endpoint -Method Post -Body $body -Headers $headers `
				-ContentType "application/x-www-form-urlencoded" -UseBasicParsing
			$text = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
			return ($text | ConvertFrom-Json).results.bindings
		} catch {
			Start-Sleep -Seconds (5 * ($try + 1))
		}
	}
	throw "Wikidata : requête en échec"
}

$channels = Import-Csv (Join-Path $root "assets/tv/channels.csv") -Encoding UTF8
$langs = $channels | ForEach-Object { $_.lang } | Sort-Object -Unique
$codes = Get-Content (Join-Path $root "locale/countries.csv") -Encoding UTF8 | Select-Object -Skip 1 |
	ForEach-Object { ($_ -split ",")[0] } | Where-Object { $_ -like "COUNTRY_*" } | ForEach-Object { $_.Substring(8) }
$wanted = @{}
foreach ($lang in $langs) { foreach ($w in $(if ($wikiLangs.ContainsKey($lang)) { $wikiLangs[$lang] } else { @($lang) })) { $wanted[$w] = $true } }
$langFilter = ($wanted.Keys | ForEach-Object { '"' + $_ + '"' }) -join ","

# 1. Élément Wikidata de chaque code (le plus cité quand plusieurs éléments portent le même code ISO).
$items = @{}
$isoValues = ($codes | Where-Object { -not $overrides.ContainsKey($_) } | ForEach-Object { '"' + $_ + '"' }) -join " "
$rows = Invoke-Sparql "SELECT ?iso ?c ?links WHERE { VALUES ?iso { $isoValues } ?c wdt:P298 ?iso; wikibase:sitelinks ?links. }"
$best = @{}
foreach ($r in $rows) {
	$links = [int]$r.links.value
	if (-not $best.ContainsKey($r.iso.value) -or $links -gt $best[$r.iso.value]) {
		$best[$r.iso.value] = $links
		$items[$r.iso.value] = ($r.c.value -split "/")[-1]
	}
}
foreach ($k in $overrides.Keys) { $items[$k] = $overrides[$k] }
$byItem = @{}
foreach ($k in $items.Keys) { $byItem[$items[$k]] = $k }
$itemValues = ($items.Values | ForEach-Object { "wd:" + $_ }) -join " "

function Pick([hashtable]$labels, [string]$lang) {
	foreach ($w in $(if ($wikiLangs.ContainsKey($lang)) { $wikiLangs[$lang] } else { @($lang) })) {
		if ($labels.ContainsKey($w)) { return $labels[$w] }
	}
	return ""
}

function Write-Table([string]$path, [string[]]$order, [hashtable]$labelsByCode) {
	$lines = New-Object System.Collections.Generic.List[string]
	$lines.Add("code," + ($langs -join ","))
	foreach ($code in $order) {
		$labels = if ($labelsByCode.ContainsKey($code)) { $labelsByCode[$code] } else { @{} }
		$cells = foreach ($lang in $langs) { '"' + ((Pick $labels $lang) -replace '"', '""') + '"' }
		$lines.Add($code + "," + ($cells -join ","))
	}
	# Importeur « keep » écrit d'abord : sinon l'éditeur prend le CSV pour un fichier de traduction.
	[System.IO.File]::WriteAllText($path + ".import", "[remap]`n`nimporter=`"keep`"`n")
	[System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding $false))
	Write-Output ("{0} : {1} lignes" -f $path, $order.Count)
}

# 2. Noms des pays.
$countryLabels = @{}
$rows = Invoke-Sparql "SELECT ?c ?label WHERE { VALUES ?c { $itemValues } ?c rdfs:label ?label. FILTER(LANG(?label) IN ($langFilter)) }"
foreach ($r in $rows) {
	$code = $byItem[($r.c.value -split "/")[-1]]
	if (-not $countryLabels.ContainsKey($code)) { $countryLabels[$code] = @{} }
	$countryLabels[$code][$r.label."xml:lang"] = $r.label.value
}
# Noms courts usuels du CLDR (Unicode, noms des territoires par langue) quand ils existent : Wikidata donne souvent
# le nom officiel long (« République de Chine », « Kosovo (République du) »…). Clé : code ISO alpha-2 (P297).
$iso2 = @{ "KOS" = "XK"; "PSX" = "PS"; "SDS" = "SS"; "SAH" = "EH" }
$rows = Invoke-Sparql "SELECT ?c ?iso2 WHERE { VALUES ?c { $itemValues } ?c wdt:P297 ?iso2. }"
foreach ($r in $rows) {
	$code = $byItem[($r.c.value -split "/")[-1]]
	if (-not $iso2.ContainsKey($code)) { $iso2[$code] = $r.iso2.value }
}
$cldrLocales = @{ "zh" = "zh"; "zh_TW" = "zh-Hant"; "tl" = "fil" }
# Le CLDR n'a pas de noms créoles haïtiens (il reprend le français) : Wikidata pour ht.
foreach ($lang in ($langs | Where-Object { $_ -ne "ht" })) {
	$locale = if ($cldrLocales.ContainsKey($lang)) { $cldrLocales[$lang] } else { $lang }
	$url = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-localenames-full/main/$locale/territories.json"
	try {
		$response = Invoke-WebRequest -Uri $url -UseBasicParsing
		$json = [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray()) | ConvertFrom-Json
	} catch {
		Write-Output "CLDR : pas de noms pour $locale"
		continue
	}
	$territories = $json.main.$locale.localeDisplayNames.territories
	$key = "cldr:" + $lang
	foreach ($code in $iso2.Keys) {
		$name = $territories.($iso2[$code])
		if ($name) {
			if (-not $countryLabels.ContainsKey($code)) { $countryLabels[$code] = @{} }
			$countryLabels[$code][$key] = $name
		}
	}
}
foreach ($lang in $langs) {
	$chain = @("cldr:" + $lang) + $(if ($wikiLangs.ContainsKey($lang)) { $wikiLangs[$lang] } else { @($lang) })
	$wikiLangs[$lang] = $chain
}
Write-Table (Join-Path $root "assets/tv/news_country_names.csv") ($codes | Sort-Object) $countryLabels

# 3. Capitales des chaînes : la plus proche des coordonnées de channels.csv.
$channelItems = ($channels | ForEach-Object { "wd:" + $items[$_.code] }) -join " "
$rows = Invoke-Sparql "SELECT ?c ?cap ?coord ?label WHERE { VALUES ?c { $channelItems } ?c wdt:P36 ?cap. ?cap wdt:P625 ?coord; rdfs:label ?label. FILTER(LANG(?label) IN ($langFilter)) }"
$capitalLabels = @{}
$capitalDistance = @{}
$candidates = @{}
foreach ($r in $rows) {
	$code = $byItem[($r.c.value -split "/")[-1]]
	$cap = ($r.cap.value -split "/")[-1]
	if (-not $candidates.ContainsKey("$code/$cap")) {
		$m = [regex]::Match($r.coord.value, "Point\(([-0-9.eE]+) ([-0-9.eE]+)\)")
		$candidates["$code/$cap"] = @{ "code" = $code; "lon" = [double]$m.Groups[1].Value; "lat" = [double]$m.Groups[2].Value; "labels" = @{} }
	}
	# Précision géographique retirée (« La Paz, Bolivia », « Tōkyō prefektuur » reste tel quel).
	$candidates["$code/$cap"].labels[$r.label."xml:lang"] = ($r.label.value -replace ",.*$", "").Trim()
}
$channelByCode = @{}
foreach ($c in $channels) { $channelByCode[$c.code] = $c }
foreach ($candidate in $candidates.Values) {
	$c = $channelByCode[$candidate.code]
	$d = [math]::Pow($candidate.lat - [double]$c.capital_lat, 2) + [math]::Pow($candidate.lon - [double]$c.capital_lon, 2)
	if (-not $capitalDistance.ContainsKey($candidate.code) -or $d -lt $capitalDistance[$candidate.code]) {
		$capitalDistance[$candidate.code] = $d
		$capitalLabels[$candidate.code] = $candidate.labels
	}
}
Write-Table (Join-Path $root "assets/tv/news_capital_names.csv") ($channels | ForEach-Object { $_.code } | Sort-Object) $capitalLabels
foreach ($c in $channels) {
	if ($capitalDistance.ContainsKey($c.code) -and $capitalDistance[$c.code] -gt 1.0) {
		Write-Output ("Attention : capitale de {0} à plus d'un degré des coordonnées de channels.csv" -f $c.code)
	}
	if (-not $capitalLabels.ContainsKey($c.code)) { Write-Output ("Attention : pas de capitale pour {0}" -f $c.code) }
}
