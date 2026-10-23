extends SceneTree
## Outil hors-jeu : construit les contours de la carte de l'écran de pilotage (assets/world_map_lines.res, classe
## WorldMapLines) à partir de la couche « admin 0 countries » de Natural Earth 1:50 M (GeoJSON, domaine public :
## https://github.com/nvkelso/natural-earth-vector, geojson/ne_50m_admin_0_countries.geojson). Usage :
##   godot --headless --path <projet> --script res://tools/build_map_lines.gd -- <ne_50m_admin_0_countries.geojson>

const WorldMapLinesScript := preload("res://scripts/geo/world_map_lines.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage : -- <ne_50m_admin_0_countries.geojson>")
		quit(1)
		return
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not json is Dictionary:
		push_error("Lecture impossible : " + args[0])
		quit(1)
		return

	var step: float = WorldMapLinesScript.MIN_STEP_DEG
	var points := PackedVector2Array()
	var offsets := PackedInt32Array()
	var source_points := 0
	for feature: Dictionary in json.features:
		var geometry: Dictionary = feature.geometry
		var polygons: Array = geometry.coordinates if geometry.type == "MultiPolygon" else [geometry.coordinates]
		for polygon: Array in polygons:
			for ring: Array in polygon:
				source_points += ring.size()
				var kept := PackedVector2Array()
				for k in ring.size():
					var p := Vector2(ring[k][0], ring[k][1])
					# Le dernier sommet (qui referme l'anneau) est toujours gardé.
					if kept.is_empty() or k == ring.size() - 1 or p.distance_to(kept[kept.size() - 1]) >= step:
						kept.append(p)
				if kept.size() < 3:
					continue
				offsets.append(points.size())
				points.append_array(kept)
	offsets.append(points.size())

	var lines: Resource = WorldMapLinesScript.new()
	lines.points = points
	lines.ring_offsets = offsets
	var path: String = WorldMapLinesScript.PATH
	var error := ResourceSaver.save(lines, path, ResourceSaver.FLAG_COMPRESS)
	print("%d anneaux, %d points (sur %d) -> %s (%s)" % [offsets.size() - 1, points.size(), source_points, path,
			error_string(error)])
	quit(0 if error == OK else 1)
