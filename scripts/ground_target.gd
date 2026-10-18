class_name GroundTarget
extends Node
## Cible au sol (nœud GroundTarget de scenes/orbit_view.tscn, groupe GROUP) : un point de la Terre choisi d'un clic
## sur la carte de l'écran de pilotage ou de la tablette (OrbitalMap), affiché sur les cartes avec ses coordonnées et,
## dans la cupola en mode « HUD : On », en surimpression bleue sur la Terre (Hud, TargetMarker). Une seule cible : un
## nouveau clic la déplace, un clic dessus la retire.

signal changed

const GROUP := &"ground_target"
const COLOR := Color(0.35, 0.65, 1.0)

var active := false
var latitude_deg := 0.0
var longitude_deg := 0.0


func _ready() -> void:
	add_to_group(GROUP)


func set_target(lat_deg: float, lon_deg: float) -> void:
	active = true
	latitude_deg = clampf(lat_deg, -90.0, 90.0)
	longitude_deg = wrapf(lon_deg, -180.0, 180.0)
	changed.emit()


func clear() -> void:
	if active:
		active = false
		changed.emit()


## « 48.86° N  2.35° E » (directions traduites : DIR_N, DIR_S, DIR_E, DIR_W).
static func format(lat_deg: float, lon_deg: float) -> String:
	return "%.2f° %s  %.2f° %s" % [absf(lat_deg), TranslationServer.translate("DIR_N" if lat_deg >= 0.0 else "DIR_S"),
			absf(lon_deg), TranslationServer.translate("DIR_E" if lon_deg >= 0.0 else "DIR_W")]


## Point de la surface (repère du nœud Earth) de coordonnées données, comme NukeLauncher.aim_at.
static func earth_local(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	# ECEF vers le repère du maillage (SphereMesh : +Y nord, +Z vers −180°), cf. NukeEffect.place.
	var up := Vector3(-cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
	return up * OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
