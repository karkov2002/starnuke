class_name BearingLog
extends Node
## Relevés de cap posés au rapporteur de la carte du poste de pilotage (nœud BearingLog de scenes/orbit_view.tscn,
## groupe GROUP ; outil : BearingTool). Un relevé est un trait de grand cercle partant d'un point de la Terre (là où
## était la station quand le radar a donné le cap) dans un azimut vrai, jusqu'à une longueur au plus égale à la
## portée du radar au moment du relevé (horizon de la station, RadarReceiver). Deux relevés pris de deux points de
## l'orbite se croisent sur la source : triangulation. Un relevé choisi (selected) peut être effacé. Affichés sur les
## cartes du poste et de la tablette ; sauvegardés avec le monde d'une campagne (WorldSnapshot).

signal changed

const GROUP := &"bearing_log"
## Nombre maximal de relevés gardés (le plus ancien part au-delà).
const MAX_BEARINGS := 24

## Relevés : {lat, lon (degrés : origine), azimuth (degrés, 0 = nord, sens horaire), length_km (trait),
## range_km (portée du radar au relevé)}.
var bearings: Array[Dictionary] = []
## Relevé choisi (indice), −1 : aucun.
var selected := -1


func _ready() -> void:
	add_to_group(GROUP)


## Ajoute un relevé et le choisit ; rend son indice.
func add(lat: float, lon: float, azimuth: float, length_km: float, range_km: float) -> int:
	bearings.append({"lat": clampf(lat, -90.0, 90.0), "lon": wrapf(lon, -180.0, 180.0),
			"azimuth": fposmod(azimuth, 360.0), "length_km": clampf(length_km, 0.0, range_km),
			"range_km": range_km})
	while bearings.size() > MAX_BEARINGS:
		bearings.remove_at(0)
	selected = bearings.size() - 1
	changed.emit()
	return selected


func remove(index: int) -> void:
	if index < 0 or index >= bearings.size():
		return
	bearings.remove_at(index)
	selected = -1
	changed.emit()


func select(index: int) -> void:
	index = index if index >= 0 and index < bearings.size() else -1
	if index != selected:
		selected = index
		changed.emit()


func clear() -> void:
	bearings.clear()
	selected = -1
	changed.emit()


## Extrémité du trait d'un relevé (latitude, longitude en degrés).
static func end_of(bearing: Dictionary) -> Vector2:
	return GeoMath.destination(bearing.lat, bearing.lon, bearing.azimuth, bearing.length_km)


func to_save() -> Array:
	return bearings.duplicate(true)


func restore(saved: Array) -> void:
	bearings.clear()
	for b: Dictionary in saved:
		bearings.append({"lat": float(b.lat), "lon": float(b.lon), "azimuth": float(b.azimuth),
				"length_km": float(b.length_km), "range_km": float(b.range_km)})
	selected = -1
	changed.emit()
