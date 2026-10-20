class_name GroundTarget
extends Node
## Cibles au sol (nœud GroundTarget de scenes/orbit_view.tscn, groupe GROUP) : jusqu'à MAX_TARGETS points de la Terre,
## numérotés de 1 à MAX_TARGETS, dont une cible choisie (selected). Règle de jeu : on ne les place que sur la carte
## de l'écran de pilotage (OrbitalMap.targets_editable : menu des cibles, clic sur la carte, saisie des coordonnées) ;
## la carte de la tablette les affiche seulement. Affichées sur les cartes avec leur numéro et leurs coordonnées et,
## dans la cupola en mode « HUD : On », en surimpression jaune sur la Terre (Hud, TargetMarker ; la cible choisie
## pleine, les autres plus pâles).

signal changed

const GROUP := &"ground_target"
const MAX_TARGETS := 5
## Jaune doré : lisible sur la mer et les nuages, distinct du jaune pâle de la station sur la carte.
const COLOR := Color(1.0, 0.78, 0.1)

## Cible de chaque numéro (indice 0 à MAX_TARGETS − 1) : Vector2(latitude, longitude) en degrés, ou null (vide).
var targets: Array = []
## Numéro choisi (indice) : celui que place un clic sur la carte.
var selected := 0


func _ready() -> void:
	add_to_group(GROUP)
	targets.resize(MAX_TARGETS)


func set_target(slot: int, lat_deg: float, lon_deg: float) -> void:
	if slot < 0 or slot >= MAX_TARGETS:
		return
	targets[slot] = Vector2(clampf(lat_deg, -90.0, 90.0), wrapf(lon_deg, -180.0, 180.0))
	changed.emit()


func clear_target(slot: int) -> void:
	if has_target(slot):
		targets[slot] = null
		changed.emit()


func select(slot: int) -> void:
	slot = clampi(slot, 0, MAX_TARGETS - 1)
	if slot != selected:
		selected = slot
		changed.emit()


func has_target(slot: int) -> bool:
	return slot >= 0 and slot < targets.size() and targets[slot] != null


## Cible du numéro slot (latitude, longitude) ; Vector2.INF si vide.
func get_target(slot: int) -> Vector2:
	return targets[slot] if has_target(slot) else Vector2.INF


## Numéros (indices) des cibles posées.
func active_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in MAX_TARGETS:
		if has_target(slot):
			slots.append(slot)
	return slots


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
