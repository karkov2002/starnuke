class_name TvNews
extends RefCounted
## Texte du bandeau défilant de la télévision (TvDisplay) : infos ordinaires (bourse, météo de la capitale d'après les
## nuages réels, CloudWeather, sport) tant qu'il n'y a eu aucune explosion, puis « Alerte info ». Dans la langue de la
## chaîne (colonne lang de assets/tv/channels.csv : langue majoritaire du pays, à défaut celle de ses journaux
## télévisés).
##
## Le bandeau suit l'état du monde : nombre d'explosions et puissance cumulée, pays touchés (point zéro sur leur
## territoire, NukeTally), morts (bilan à l'instant présent, NukeTally), capitales détruites (chaînes hors d'antenne,
## TvConsole), le pays qui diffuse (touché ou non, puissance nucléaire ou non). Quelle phrase pour quel cas : règles de
## assets/tv/news_rules.json (préfixe puis sections dans l'ordre ; dans chaque section, la première règle dont la
## condition sur ces faits est vraie donne la clé de la phrase ; voir _doc et facts dans le fichier).
##
## Textes (assets/tv/news_ticker.csv, une ligne par clé et variante « CLE.n », une colonne par langue) : chaque
## phrase a plusieurs variantes, tirées au hasard à chaque passage du bandeau (pas d'effet de répétition). Pour les
## langues à déclinaisons, les noms de pays et de capitales sont placés après deux-points (nominatif, sans accord).
## Noms des pays et des capitales dans chaque langue : assets/tv/news_country_names.csv et news_capital_names.csv
## (CLDR et Wikidata, tools/build_tv_news_names.ps1) ; à défaut, le nom anglais. Ces textes du monde du jeu ne
## dépendent pas de la langue du joueur : ils ne passent pas par les fichiers de langue (locale/).

const TICKER_PATH := "res://assets/tv/news_ticker.csv"
const RULES_PATH := "res://assets/tv/news_rules.json"
const COUNTRY_NAMES_PATH := "res://assets/tv/news_country_names.csv"
const CAPITAL_NAMES_PATH := "res://assets/tv/news_capital_names.csv"
## Langues écrites de droite à gauche (le bandeau défile alors vers la droite).
const RTL_LANGS: Array[String] = ["ar", "fa", "he", "ur"]
const SEPARATOR := "   •   "

## Clé -> {langue -> texte}, variantes regroupées : "PREFIX" -> [{...}, {...}].
static var _texts := {}
static var _variants := {}
static var _country_names := {}
static var _capital_names := {}
static var _rules := {}
static var _loaded := false


## Texte du bandeau pour la chaîne du pays code, en langue lang. state : {effects (Array[NukeEffect]), tally
## (NukeTally.compute), off_air (Array[String] : pays dont la capitale est détruite)}. rng : tirage des variantes.
static func compose(code: String, lang: String, state: Dictionary, rng: RandomNumberGenerator) -> String:
	_load()
	var effects: Array = state.get("effects", [])
	var tally: Dictionary = state.get("tally", {})
	var off_air: Array = state.get("off_air", [])
	# Faits (conditions des règles) et valeurs (variables des phrases).
	var total_kt := 0.0
	for effect: NukeEffect in effects:
		if effect.params:
			total_kt += effect.params.yield_kt
	var hit: Array[String] = []
	for entry: Dictionary in tally.get("countries", []):
		if int(entry.get("explosions", 0)) > 0:
			hit.append(String(entry.code))
	var killed := int(tally.get("killed", 0))
	# Capitales détruites (la chaîne qui diffuse ne peut pas en faire partie : elle serait hors d'antenne).
	var capitals: Array = off_air.filter(func(c: String) -> bool: return c != code)
	# Infos ordinaires (bourse, météo, sport) : valeurs du jour, stables pour une chaîne pendant une journée de jeu.
	var utc: float = state.get("utc_unix", 0.0)
	var capital: Vector2 = state.get("capital", Vector2.ZERO)
	var day := Time.get_datetime_dict_from_unix_time(int(utc))
	var day_of_year := int((utc - Time.get_unix_time_from_datetime_dict(
			{"year": day.year, "month": 1, "day": 1})) / 86400.0) + 1
	var local_hour := fposmod(utc / 3600.0 + capital.y / 15.0, 24.0)
	var cover := CloudWeather.cloud_cover(capital.x, capital.y, utc)
	var daily := RandomNumberGenerator.new()
	daily.seed = hash(code) ^ int(utc / 86400.0)
	var stock_change := snappedf(clampf(daily.randfn(0.2, 1.1), -4.5, 4.5), 0.01)
	var pool: Array = state.get("channels", []).filter(func(c: String) -> bool: return c != code)
	var team_a := String(pool[daily.randi() % pool.size()]) if not pool.is_empty() else code
	var team_b := team_a
	while team_b == team_a and pool.size() > 1:
		team_b = String(pool[daily.randi() % pool.size()])
	var goals := [daily.randi_range(0, 4), daily.randi_range(0, 3)]
	var points := [daily.randi_range(78, 118), daily.randi_range(70, 112)]
	if points[0] == points[1]:
		points[0] += 3
	var facts := {
		"explosions": effects.size(),
		"yield_kt": total_kt,
		"countries_hit": hit.size(),
		"deaths": killed,
		"capitals_destroyed": capitals.size(),
		"broadcaster_hit": code in hit,
		"broadcaster_nuclear": code in _rules.get("nuclear_powers", []),
		"cloud_cover": cover,
		"night": local_hour < 6.5 or local_hour >= 20.0,
		"temperature": CloudWeather.temperature(capital.x, day_of_year, local_hour, cover),
		"stock_change": stock_change,
		"roll": rng.randf(),
		"alert": bool(state.get("alert", false)),
	}
	var values := {
		"count": str(effects.size()),
		"yield": _yield_text(total_kt, lang),
		"countries": _join(hit.map(func(c: String) -> String: return country_name(c, lang)), lang),
		"deaths": _number(_round_estimate(killed), lang),
		"capitals": _join(capitals.map(func(c: String) -> String: return capital_name(c, lang)), lang),
		"city": capital_name(code, lang),
		"temp": str(roundi(facts.temperature)),
		"stock_change": _decimal(absf(stock_change), lang),
		"team_a": country_name(team_a, lang),
		"team_b": country_name(team_b, lang),
		"goals_a": str(goals[0]),
		"goals_b": str(goals[1]),
		"points_a": str(points[0]),
		"points_b": str(points[1]),
	}
	var sentences: Array[String] = []
	for section: Dictionary in _rules.get("sections", []):
		var key := _rule_key(section.get("rules", []), facts)
		if key != "":
			sentences.append(_pick(key, lang, rng).format(values))
	var prefix_key := _rule_key(_rules.get("prefix", []), facts)
	var prefix := _pick(prefix_key, lang, rng).format(values) if prefix_key != "" else ""
	# Espace après le préfixe, sauf après une ponctuation pleine chasse (chinois, japonais).
	if prefix != "" and not prefix.ends_with("：") and not prefix.ends_with("、"):
		prefix += " "
	return prefix + SEPARATOR.join(sentences)


## Clé de la première règle dont la condition est vraie ("" : aucune).
static func _rule_key(rules: Array, facts: Dictionary) -> String:
	for rule: Dictionary in rules:
		if _matches(rule.get("when", {}), facts):
			return String(rule.get("key", ""))
	return ""


## Condition {fait: test} : tous les tests vrais. Test d'un nombre : nombre (égal) ou texte « >0 », « >=2 », « <5 »,
## « <=5 », « !=1 », « 3 » ; test d'un booléen : true / false. Fait inconnu : faux (signalé).
static func _matches(when: Dictionary, facts: Dictionary) -> bool:
	for fact: String in when:
		if not facts.has(fact):
			push_warning("TvNews : fait inconnu « %s » dans %s" % [fact, RULES_PATH])
			return false
		var value: Variant = facts[fact]
		var test: Variant = when[fact]
		if test is bool or value is bool:
			if bool(value) != bool(test):
				return false
			continue
		var number := float(value)
		if test is float or test is int:
			if not is_equal_approx(number, float(test)):
				return false
			continue
		var text := String(test).strip_edges()
		var ok := false
		for op: String in [">=", "<=", "!=", ">", "<", "="]:
			if text.begins_with(op):
				var limit := text.substr(op.length()).to_float()
				match op:
					">=": ok = number >= limit
					"<=": ok = number <= limit
					"!=": ok = not is_equal_approx(number, limit)
					">": ok = number > limit
					"<": ok = number < limit
					"=": ok = is_equal_approx(number, limit)
				break
		if not ok and text.is_valid_float():
			ok = is_equal_approx(number, text.to_float())
		if not ok:
			return false
	return true


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


## Nombre à deux décimales, séparateur décimal de la langue (« 1,24 »).
static func _decimal(value: float, lang: String) -> String:
	var cents := roundi(value * 100.0)
	return "%d%s%02d" % [cents / 100, _format("DECIMAL", lang), cents % 100]


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
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if rules is Dictionary:
		_rules = rules
	else:
		push_error("TvNews : %s illisible (JSON)" % RULES_PATH)
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
