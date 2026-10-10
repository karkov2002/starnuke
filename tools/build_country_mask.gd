extends SceneTree
## Outil hors-jeu : construit le masque des pays (assets/country_mask.res, classe CountryMask) à partir de la couche
## « admin 0 countries » de Natural Earth 1:10 M (GeoJSON). Pour chaque ligne de latitude (CountryMask.ROWS_PER_DEGREE
## par degré, au milieu de la ligne), il calcule les longitudes où les contours de chaque pays la traversent, puis
## parcourt la ligne d'ouest en est (règle pair-impair par pays) pour savoir quel pays l'occupe entre deux
## traversées. Usage :
##   godot --headless --path <projet> --script res://tools/build_country_mask.gd -- <ne_10m_admin_0_countries.geojson>

const CountryMaskScript := preload("res://scripts/country_mask.gd")


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

	var rows: int = CountryMaskScript.row_count()
	# Traversées de chaque ligne : Vector2(longitude, indice du pays), triées nativement (longitude puis pays).
	var per_row: Array[Array] = []
	per_row.resize(rows)
	for i in rows:
		per_row[i] = []
	var countries: Array[Dictionary] = []
	var edges := 0
	for feature: Dictionary in json.features:
		var index := countries.size()
		countries.append(_describe(feature.properties))
		var geometry: Dictionary = feature.geometry
		var polygons: Array = geometry.coordinates if geometry.type == "MultiPolygon" else [geometry.coordinates]
		for polygon: Array in polygons:
			for ring: Array in polygon:
				for k in ring.size() - 1:
					_add_edge(per_row, ring[k], ring[k + 1], index)
					edges += 1

	# Nom français de l'État souverain (celui du pays de même nom, sinon le nom anglais).
	var french := {}
	for country in countries:
		french[country.name_en] = country.name_fr
	for country in countries:
		country.sovereign_fr = french.get(country.sovereign, country.sovereign)

	var breaks := PackedFloat32Array()
	var owners := PackedInt32Array()
	var offsets := PackedInt32Array()
	offsets.resize(rows + 1)
	var conflicts := 0
	for i in rows:
		offsets[i] = breaks.size()
		var row := per_row[i]
		row.sort()
		var parity := {} # indice du pays -> nombre de traversées passées (impair : à l'intérieur)
		var inside: Array[int] = []
		var current := -1
		for j in row.size():
			var crossing: Vector2 = row[j]
			var country := int(crossing.y)
			parity[country] = parity.get(country, 0) + 1
			if parity[country] % 2 == 1:
				inside.append(country)
			else:
				inside.erase(country)
			# Plusieurs traversées à la même longitude : on ne tranche qu'après la dernière.
			if j + 1 < row.size() and row[j + 1].x == crossing.x:
				continue
			if inside.size() > 1:
				conflicts += 1 # recouvrement (frontières imprécises) : le dernier pays entré l'emporte
			var owner: int = inside.back() if not inside.is_empty() else -1
			if owner != current:
				breaks.append(crossing.x)
				owners.append(owner)
				current = owner
		if current != -1:
			push_warning("Ligne %d : pays %s ouvert en fin de ligne" % [i, countries[current].code])
	offsets[rows] = breaks.size()

	var mask: Resource = CountryMaskScript.new()
	mask.breaks = breaks
	mask.owners = owners
	mask.row_offsets = offsets
	mask.countries = countries
	var path: String = CountryMaskScript.PATH
	var error := ResourceSaver.save(mask, path, ResourceSaver.FLAG_COMPRESS)
	print("%d pays, %d arêtes, %d changements, %d recouvrements -> %s (%s)" % [countries.size(), edges, breaks.size(),
			conflicts, path, error_string(error)])
	if error == OK:
		error = _save_id_texture(breaks, owners, offsets)
	quit(0 if error == OK else 1)


## Carte des pays pour les shaders (black-out national, nuke/shaders/nuke_blackout.gdshaderinc) : ID_TEXTURE_WIDTH x
## moitié autant de pixels (~2,4 km), équirectangulaire (x = 0 à 180° O, y = 0 à 90° N), au centre de chaque pixel.
## Indice du pays + 1 sur 16 bits (R = octet faible, G = octet fort ; 0 = aucun pays).
const ID_TEXTURE_WIDTH := 8192
const ID_TEXTURE_PATH := "res://assets/textures/country_ids.png"


func _save_id_texture(breaks: PackedFloat32Array, owners: PackedInt32Array, offsets: PackedInt32Array) -> Error:
	var width := ID_TEXTURE_WIDTH
	var height := width / 2
	var data := PackedByteArray()
	data.resize(width * height * 2)
	for y in height:
		var lat := 90.0 - (y + 0.5) * 180.0 / height
		var row: int = CountryMaskScript._row_of(lat)
		var i := offsets[row]
		var end := offsets[row + 1]
		var owner := -1
		var base := y * width * 2
		for x in width:
			var lon := -180.0 + (x + 0.5) * 360.0 / width
			while i < end and breaks[i] <= lon:
				owner = owners[i]
				i += 1
			if owner >= 0:
				data[base + x * 2] = (owner + 1) & 0xFF
				data[base + x * 2 + 1] = (owner + 1) >> 8
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RG8, data)
	var error := image.save_png(ID_TEXTURE_PATH)
	print("carte des pays %d x %d -> %s (%s)" % [width, height, ID_TEXTURE_PATH, error_string(error)])
	return error


## Fiche d'un pays à partir des attributs Natural Earth.
func _describe(p: Dictionary) -> Dictionary:
	return {
		"code": p.ADM0_A3,
		"iso_a2": p.ISO_A2_EH if p.ISO_A2_EH != "-99" else "",
		"name_fr": p.NAME_FR if p.NAME_FR else p.NAME,
		"name_en": p.ADMIN,
		"sovereign_code": p.SOV_A3,
		"sovereign": p.SOVEREIGNT,
		"type": p.TYPE,
		"continent": p.CONTINENT,
		"pop_est": int(p.POP_EST),
		"pop_year": int(p.POP_YEAR),
		"gdp_md": int(p.GDP_MD),
		"gdp_year": int(p.GDP_YEAR),
		"income_group": p.INCOME_GRP,
	}


## Ajoute la traversée de l'arête (a, b) (longitude, latitude en degrés) du pays country à chaque ligne dont la
## latitude centrale est dans [min, max[ de l'arête (un sommet sur la ligne ne compte qu'une fois).
func _add_edge(per_row: Array[Array], a: Array, b: Array, country: int) -> void:
	var ax: float = a[0]
	var ay: float = a[1]
	var bx: float = b[0]
	var by: float = b[1]
	if ay == by:
		return
	var n: int = CountryMaskScript.ROWS_PER_DEGREE
	var lo := minf(ay, by)
	var hi := maxf(ay, by)
	var first := maxi(int(ceil((90.0 - hi) * n - 0.5)), 0)
	var last := mini(int(floor((90.0 - lo) * n - 0.5)), per_row.size() - 1)
	for i in range(first, last + 1):
		var y := 90.0 - (i + 0.5) / n
		if y < lo or y >= hi:
			continue
		per_row[i].append(Vector2(ax + (y - ay) * (bx - ax) / (by - ay), country))
