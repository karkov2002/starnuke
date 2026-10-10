extends SceneTree
## Outil hors-jeu : construit le masque mers et océans (assets/ocean_mask.res, classe OceanMask) à partir de la couche
## « ocean » de Natural Earth 1:10 M (GeoJSON). Pour chaque ligne de latitude (OceanMask.ROWS_PER_DEGREE par degré,
## au milieu de la ligne), il calcule les longitudes où les contours des polygones la traversent et les trie.
## Usage :
##   godot --headless --path <projet> --script res://tools/build_ocean_mask.gd -- <ne_10m_ocean.geojson>

const OceanMaskScript := preload("res://scripts/ocean_mask.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage : -- <ne_10m_ocean.geojson>")
		quit(1)
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not json is Dictionary:
		push_error("Lecture impossible : " + args[0])
		quit(1)
		return

	var rows: int = OceanMaskScript.row_count()
	# Tableaux génériques : un PackedFloat32Array lu dans un Array est une copie, append ne le modifierait pas.
	var per_row: Array[Array] = []
	per_row.resize(rows)
	for i in rows:
		per_row[i] = []
	var edges := 0
	for feature: Dictionary in json.features:
		var geometry: Dictionary = feature.geometry
		var polygons: Array = geometry.coordinates if geometry.type == "MultiPolygon" else [geometry.coordinates]
		for polygon: Array in polygons:
			for ring: Array in polygon:
				for k in ring.size() - 1:
					_add_edge(per_row, ring[k], ring[k + 1])
					edges += 1

	var offsets := PackedInt32Array()
	offsets.resize(rows + 1)
	var total := 0
	for i in rows:
		offsets[i] = total
		total += per_row[i].size()
	offsets[rows] = total
	var crossings := PackedFloat32Array()
	crossings.resize(total)
	for i in rows:
		var row := per_row[i]
		row.sort()
		for j in row.size():
			crossings[offsets[i] + j] = row[j]
		if row.size() % 2 != 0:
			push_warning("Ligne %d : nombre impair de traversées (%d)" % [i, row.size()])
	var mask: Resource = OceanMaskScript.new()
	mask.crossings = crossings
	mask.row_offsets = offsets
	var path: String = OceanMaskScript.PATH
	var error := ResourceSaver.save(mask, path, ResourceSaver.FLAG_COMPRESS)
	print("%d arêtes, %d traversées, %d lignes -> %s (%s)" % [edges, total, rows, path, error_string(error)])
	quit(0 if error == OK else 1)


## Ajoute la traversée de l'arête (a, b) (longitude, latitude en degrés) à chaque ligne dont la latitude centrale
## est dans [min, max[ de l'arête (règle demi-ouverte : un sommet sur la ligne ne compte qu'une fois).
func _add_edge(per_row: Array[Array], a: Array, b: Array) -> void:
	var ax: float = a[0]
	var ay: float = a[1]
	var bx: float = b[0]
	var by: float = b[1]
	if ay == by:
		return
	var n: int = OceanMaskScript.ROWS_PER_DEGREE
	var lo := minf(ay, by)
	var hi := maxf(ay, by)
	var first := maxi(int(ceil((90.0 - hi) * n - 0.5)), 0)
	var last := mini(int(floor((90.0 - lo) * n - 0.5)), per_row.size() - 1)
	for i in range(first, last + 1):
		var y := 90.0 - (i + 0.5) / n
		if y < lo or y >= hi:
			continue
		per_row[i].append(ax + (y - ay) * (bx - ax) / (by - ay))
