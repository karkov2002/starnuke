class_name WorldMapLines
extends Resource
## Contours des pays pour la carte de l'écran de pilotage (assets/world_map_lines.res, généré par
## tools/build_map_lines.gd à partir de la couche « admin 0 countries » de Natural Earth 1:50 M). Chaque anneau de
## polygone est une ligne fermée de points (longitude, latitude) en degrés, allégée (sommets distants d'au moins
## MIN_STEP_DEG) ; les frontières communes à deux pays sont tracées deux fois, les côtes une fois.

const PATH := "res://assets/world_map_lines.res"
const MIN_STEP_DEG := 0.05

## Points de tous les anneaux, à la suite : Vector2(longitude, latitude) en degrés.
@export var points := PackedVector2Array()
## Début de chaque anneau dans points (taille : nombre d'anneaux + 1).
@export var ring_offsets := PackedInt32Array()

static var _instance: WorldMapLines
static var _load_failed := false


## Contours chargés une fois (null si le fichier manque).
static func get_lines() -> WorldMapLines:
	if _instance == null and not _load_failed:
		_instance = load(PATH) as WorldMapLines if ResourceLoader.exists(PATH) else null
		_load_failed = _instance == null
		if _load_failed:
			push_warning("WorldMapLines : %s introuvable (tools/build_map_lines.gd)" % PATH)
	return _instance


func ring_count() -> int:
	return maxi(ring_offsets.size() - 1, 0)


## Points de l'anneau index (longitude, latitude).
func ring(index: int) -> PackedVector2Array:
	return points.slice(ring_offsets[index], ring_offsets[index + 1])
