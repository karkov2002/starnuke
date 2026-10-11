extends SceneTree
## Outil hors-jeu : construit la table de traduction des noms de pays (locale/countries.csv, importée par Godot comme
## les autres fichiers de langue) à partir de la couche « admin 0 countries » de Natural Earth 1:10 M (GeoJSON), la
## même que tools/build_country_mask.gd. Deux clés par territoire :
## - COUNTRY_<ADM0_A3> : nom du pays ou territoire (même code que CountryMask) ;
## - SOVEREIGN_<SOV_A3> : nom de l'État souverain dont il dépend (Natural Earth : entité dont ADMIN = SOVEREIGNT).
## Colonnes : LOCALES (en, fr, es, de, it), champs NAME_EN, NAME_FR… (à défaut : NAME). Le français
## reprend la règle de CountryMask (NAME_FR, à défaut NAME). Usage :
##   godot --headless --path <projet> --script res://tools/build_country_names.gd -- <ne_10m_admin_0_countries.geojson>

const OUTPUT := "res://locale/countries.csv"
const LOCALES: Array[String] = ["en", "fr", "es", "de", "it"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage : -- <ne_10m_admin_0_countries.geojson>")
		quit(1)
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not json is Dictionary:
		push_error("Lecture impossible : " + args[0])
		quit(1)
		return

	var countries := {} # ADM0_A3 -> noms par langue
	var sovereigns := {} # SOV_A3 -> noms par langue
	var by_admin := {} # ADMIN -> noms (pour retrouver l'État souverain par son nom)
	var sovereign_names := {} # SOV_A3 -> SOVEREIGNT
	for feature: Dictionary in json.features:
		var p: Dictionary = feature.properties
		var names := _names(p)
		countries[p.ADM0_A3] = names
		by_admin[p.ADMIN] = names
		sovereign_names[p.SOV_A3] = p.SOVEREIGNT
	for code: String in sovereign_names:
		var name: String = sovereign_names[code]
		sovereigns[code] = by_admin.get(name, _same_name(name))

	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["keys"] + LOCALES))
	for code: String in _sorted(countries):
		file.store_csv_line(PackedStringArray(["COUNTRY_" + code] + countries[code]))
	for code: String in _sorted(sovereigns):
		file.store_csv_line(PackedStringArray(["SOVEREIGN_" + code] + sovereigns[code]))
	file.close()
	print("%d pays, %d États souverains -> %s" % [countries.size(), sovereigns.size(), OUTPUT])
	quit(0)


func _names(p: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for locale in LOCALES:
		var value: Variant = p.get("NAME_" + locale.to_upper())
		names.append(String(value) if value is String and not String(value).is_empty() else String(p.NAME))
	return names


func _same_name(name: String) -> Array[String]:
	var names: Array[String] = []
	for locale in LOCALES:
		names.append(name)
	return names


func _sorted(dict: Dictionary) -> Array:
	var keys := dict.keys()
	keys.sort()
	return keys
