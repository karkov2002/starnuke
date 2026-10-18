class_name TvNews
extends RefCounted
## Texte du bandeau défilant de l'édition spéciale « Alerte info » (TvDisplay), dans la langue de la chaîne (colonne
## lang de assets/tv/channels.csv : langue majoritaire du pays, à défaut celle de ses journaux télévisés).
##
## Le bandeau suit l'état du monde : nombre d'explosions et puissance cumulée, pays touchés (point zéro sur leur
## territoire, NukeTally), morts (bilan à l'instant présent, NukeTally), capitales détruites (chaînes hors d'antenne,
## TvConsole), puis la déclaration du gouvernement du pays qui diffuse, selon qu'il est touché ou non et qu'il est
## ou non une puissance nucléaire (NUCLEAR_POWERS).
##
## Textes (assets/tv/news_ticker.csv, une ligne par clé et variante « CLE.n », une colonne par langue) : chaque
## phrase a plusieurs variantes, tirées au hasard à chaque passage du bandeau (pas d'effet de répétition). Pour les
## langues à déclinaisons, les noms de pays et de capitales sont placés après deux-points (nominatif, sans accord).
## Noms des pays et des capitales dans chaque langue : assets/tv/news_country_names.csv et news_capital_names.csv
## (CLDR et Wikidata, tools/build_tv_news_names.ps1) ; à défaut, le nom anglais. Ces textes du monde du jeu ne
## dépendent pas de la langue du joueur : ils ne passent pas par les fichiers de langue (locale/).

const TICKER_PATH := "res://assets/tv/news_ticker.csv"
const COUNTRY_NAMES_PATH := "res://assets/tv/news_country_names.csv"
const CAPITAL_NAMES_PATH := "res://assets/tv/news_capital_names.csv"
const NUCLEAR_POWERS: Array[String] = ["USA", "RUS", "FRA", "GBR", "IND", "PAK", "CHN", "ISR", "PRK"]
## Langues écrites de droite à gauche (le bandeau défile alors vers la droite).
const RTL_LANGS: Array[String] = ["ar", "fa", "he", "ur"]
const SEPARATOR := "   •   "

## Clé -> {langue -> texte}, variantes regroupées : "PREFIX" -> [{...}, {...}].
static var _texts := {}
static var _variants := {}
static var _country_names := {}
static var _capital_names := {}
static var _loaded := false


## Texte du bandeau pour la chaîne du pays code, en langue lang. state : {effects (Array[NukeEffect]), tally
## (NukeTally.compute), off_air (Array[String] : pays dont la capitale est détruite)}. rng : tirage des variantes.
static func compose(code: String, lang: String, state: Dictionary, rng: RandomNumberGenerator) -> String:
	_load()
	var effects: Array = state.get("effects", [])
	var tally: Dictionary = state.get("tally", {})
	var off_air: Array = state.get("off_air", [])
	var sentences: Array[String] = []
	# Explosions, puissance cumulée, pays touchés.
	var total_kt := 0.0
	for effect: NukeEffect in effects:
		if effect.params:
			total_kt += effect.params.yield_kt
	var hit: Array[String] = []
	for entry: Dictionary in tally.get("countries", []):
		if int(entry.get("explosions", 0)) > 0:
			hit.append(String(entry.code))
	var values := {"count": str(effects.size()), "yield": _yield_text(total_kt, lang)}
	if hit.is_empty():
		sentences.append(_pick("ONE_SEA" if effects.size() == 1 else "MANY_SEA", lang, rng).format(values))
	else:
		values["countries"] = _join(hit.map(func(c: String) -> String: return country_name(c, lang)), lang)
		sentences.append(_pick("STRIKE_ONE" if effects.size() == 1 else "STRIKE_MANY", lang, rng).format(values))
	# Bilan.
	var killed := int(tally.get("killed", 0))
	if killed > 0:
		sentences.append(_pick("DEATHS", lang, rng).format({"deaths": _number(_round_estimate(killed), lang)}))
	# Capitales détruites (la chaîne qui diffuse ne peut pas en faire partie : elle serait hors d'antenne).
	var capitals: Array = off_air.filter(func(c: String) -> bool: return c != code)
	if not capitals.is_empty():
		sentences.append(_pick("CAPITALS", lang, rng).format(
				{"capitals": _join(capitals.map(func(c: String) -> String: return capital_name(c, lang)), lang)}))
	# Déclaration du gouvernement.
	var touched := code in hit
	var key := "SAFE"
	if touched:
		key = "NUCLEAR_HIT" if code in NUCLEAR_POWERS else "OTHER_HIT"
	sentences.append(_pick(key, lang, rng))
	return _pick("PREFIX", lang, rng) + " " + SEPARATOR.join(sentences)


static func is_rtl(lang: String) -> bool:
	return lang in RTL_LANGS


static func country_name(code: String, lang: String) -> String:
	_load()
	return _name_in(_country_names, code, lang, TranslationServer.translate("COUNTRY_" + code))


static func capital_name(code: String, lang: String) -> String:
	_load()
	return _name_in(_capital_names, code, lang, code)


static func _name_in(table: Dictionary, code: String, lang: String, fallback: String) -> String:
	var names: Dictionary = table.get(code, {})
	var name := String(names.get(lang, ""))
	if name == "":
		name = String(names.get("en", ""))
	return name if name != "" else fallback


static func _pick(key: String, lang: String, rng: RandomNumberGenerator) -> String:
	var variants: Array = _variants.get(key, [])
	if variants.is_empty():
		return ""
	var row: Dictionary = variants[rng.randi() % variants.size()]
	var text := String(row.get(lang, ""))
	return text if text != "" else String(row.get("en", ""))


static func _format(key: String, lang: String) -> String:
	var row: Dictionary = _texts.get(key, {})
	return String(row.get(lang, row.get("en", "")))


static func _join(names: Array, lang: String) -> String:
	return _format("LIST_SEP", lang).join(PackedStringArray(names))


## Puissance cumulée : kilotonnes entières sous 1 Mt, mégatonnes à une décimale au-delà (« 1,5 Mt », « 20 Mt »).
static func _yield_text(kt: float, lang: String) -> String:
	if kt < 1000.0:
		return _format("UNIT_KT", lang).format({"n": _number(roundi(kt), lang)})
	var mt := snappedf(kt / 1000.0, 0.1)
	var text := _number(int(mt), lang)
	if not is_equal_approx(mt, roundf(mt)):
		text += _format("DECIMAL", lang) + str(roundi(mt * 10.0) % 10)
	return _format("UNIT_MT", lang).format({"n": text})


## Estimation arrondie à trois chiffres significatifs (175 342 -> 175 000).
static func _round_estimate(value: int) -> int:
	if value < 1000:
		return value
	var step := int(pow(10.0, floorf(log(float(value)) / log(10.0)) - 2.0))
	return roundi(float(value) / step) * step


static func _number(value: int, lang: String) -> String:
	var digits := str(absi(value))
	var separator := _format("THOUSANDS", lang)
	var grouped := ""
	while digits.length() > 3:
		grouped = separator + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_texts = _read_table(TICKER_PATH)
	for key: String in _texts:
		var base := key.get_slice(".", 0)
		if not _variants.has(base):
			_variants[base] = []
		_variants[base].append(_texts[key])
	_country_names = _read_table(COUNTRY_NAMES_PATH)
	_capital_names = _read_table(CAPITAL_NAMES_PATH)


## CSV « clé, langue 1, langue 2… » -> {clé -> {langue -> texte}}.
static func _read_table(path: String) -> Dictionary:
	var table := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TvNews : %s illisible" % path)
		return table
	var header := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2:
			continue
		var cells := {}
		for i in range(1, mini(row.size(), header.size())):
			cells[header[i]] = row[i]
		table[row[0]] = cells
	return table
