class_name BearingTool
extends RefCounted
## Rapporteur de la carte du poste de pilotage (OrbitalMap, carte modifiable) : relevés de cap pour situer une source
## radar par triangulation (RadarConsole). Relevés gardés par BearingLog ; affichés sur toutes les cartes.
## - Bouton « Rapporteur » (start) : un clic sur la carte pose le centre du rapporteur (là où était la station lors du
##   relevé radar) ; puis, en déplaçant la souris, un trait part du centre vers le pointeur, le long du **grand
##   cercle** (comme le cap donné par le radar : GeoMath.initial_bearing_deg ; courbe sur la carte de Mercator), avec
##   l'azimut et la distance écrits en temps réel, et le cercle de portée du radar autour du centre (horizon de la
##   station à son altitude actuelle, comme RadarReceiver) : le trait s'y arrête. Un dernier clic valide le relevé.
##   Glisser déplace toujours la carte ; un nouveau clic sur « Rapporteur » annule.
## - Sans outil en cours : un clic sur le centre ou l'extrémité d'un relevé le choisit (trait blanc épais et son
##   cercle de portée) ; « Effacer le relevé » l'efface.

enum Mode { OFF, PLACE, AIM }

const COLOR_BEARING := Color(1.0, 0.82, 0.5)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0)
const COLOR_LIVE := Color(1.0, 1.0, 1.0)
## Rayon (px) autour du centre ou de l'extrémité d'un relevé où un clic le choisit.
const PICK := 14.0
## Pas (km) des points d'un trait de grand cercle et nombre de points du cercle de portée.
const STEP_KM := 40.0
const CIRCLE_POINTS := 96

var mode := Mode.OFF
## Centre posé (latitude, longitude en degrés) et pointeur (pixels de la carte, INF : hors de la carte).
var center := Vector2.ZERO
var pointer := Vector2.INF

var _map: OrbitalMap


func _init(map: OrbitalMap) -> void:
	_map = map


func get_log() -> BearingLog:
	return _map.get_tree().get_first_node_in_group(BearingLog.GROUP) as BearingLog if _map.is_inside_tree() else null


## Bouton « Rapporteur » : démarre l'outil, ou l'annule s'il est en cours.
func toggle() -> void:
	mode = Mode.PLACE if mode == Mode.OFF else Mode.OFF


## Portée du radar (km) : distance au sol de l'horizon de la station à son altitude actuelle.
func range_km() -> float:
	var altitude := _map.orbit.altitude_km if _map.orbit else 400.0
	return GeoMath.horizon_angle_rad(altitude) * GeoMath.EARTH_RADIUS_KM


## Azimut (degrés) et distance (km, bornée à la portée) du centre posé vers le point de la carte at.
func aim_at(at: Vector2) -> Vector2:
	var point := _map.lat_lon_at(at)
	return Vector2(GeoMath.initial_bearing_deg(center.x, center.y, point.x, point.y),
			minf(GeoMath.distance_km(center.x, center.y, point.x, point.y), range_km()))


## Clic (sans glisser) sur la carte ; vrai si le rapporteur l'a utilisé.
func click(at: Vector2) -> bool:
	match mode:
		Mode.PLACE:
			center = _map.lat_lon_at(at)
			pointer = at
			mode = Mode.AIM
			return true
		Mode.AIM:
			var bearing_log := get_log()
			var aim := aim_at(at)
			if bearing_log and aim.y > 0.0:
				bearing_log.add(center.x, center.y, aim.x, aim.y, range_km())
			mode = Mode.OFF
			return true
	return _pick(at)


## Choix d'un relevé par son centre ou son extrémité.
func _pick(at: Vector2) -> bool:
	var bearing_log := get_log()
	if bearing_log == null:
		return false
	for i in range(bearing_log.bearings.size() - 1, -1, -1):
		var b := bearing_log.bearings[i]
		var end := BearingLog.end_of(b)
		for copy in _map._visible_copies():
			if _map.project(b.lat, b.lon, copy).distance_to(at) <= PICK \
					or _map.project(end.x, end.y, copy).distance_to(at) <= PICK:
				bearing_log.select(i)
				return true
	return false


func draw(canvas: CanvasItem, copies: Array[int], font: Font, font_size: int) -> void:
	var bearing_log := get_log()
	if bearing_log:
		for i in bearing_log.bearings.size():
			var b := bearing_log.bearings[i]
			var chosen := i == bearing_log.selected
			var color := COLOR_SELECTED if chosen else COLOR_BEARING
			if chosen:
				_stroke(canvas, _circle(b.lat, b.lon, b.range_km), Color(color, 0.35), 1.5, copies)
			_stroke(canvas, _geodesic(b.lat, b.lon, b.azimuth, b.length_km), color, 3.0 if chosen else 2.0, copies)
			var end := BearingLog.end_of(b)
			for copy in copies:
				var origin := _map.project(b.lat, b.lon, copy)
				canvas.draw_arc(origin, 6.0, 0.0, TAU, 24, color, 2.0, true)
				_map._draw_label(_map.project(end.x, end.y, copy) + Vector2(10.0, -8.0), "%05.1f°" % b.azimuth,
						font, font_size, color)
	if mode == Mode.AIM:
		_stroke(canvas, _circle(center.x, center.y, range_km()), Color(COLOR_LIVE, 0.4), 1.5, copies)
		var aim := aim_at(pointer) if pointer != Vector2.INF else Vector2.ZERO
		if aim.y > 0.0:
			_stroke(canvas, _geodesic(center.x, center.y, aim.x, aim.y), COLOR_LIVE, 2.5, copies)
		for copy in copies:
			canvas.draw_arc(_map.project(center.x, center.y, copy), 7.0, 0.0, TAU, 24, COLOR_LIVE, 2.5, true)
		if pointer != Vector2.INF:
			var text := tr_text("MAP_BEARING_READOUT").format({"az": "%05.1f" % aim.x,
					"km": NumberFormat.group(roundi(aim.y), " ")})
			_map._draw_label(pointer + Vector2(18.0, -14.0), text, font, font_size, COLOR_LIVE)
	elif mode == Mode.PLACE and pointer != Vector2.INF:
		canvas.draw_arc(pointer, 7.0, 0.0, TAU, 24, COLOR_LIVE, 2.0, true)
		_map._draw_label(pointer + Vector2(18.0, -14.0), tr_text("MAP_BEARING_PLACE"), font, font_size, COLOR_LIVE)


func tr_text(key: String) -> String:
	return _map.tr(key)


## Trait de grand cercle (coordonnées du monde de la carte, longitude déroulée sans saut à ±180°).
func _geodesic(lat: float, lon: float, azimuth: float, length_km: float) -> PackedVector2Array:
	var count := maxi(2, ceili(length_km / STEP_KM) + 1)
	var points: Array[Vector2] = []
	for k in count:
		points.append(GeoMath.destination(lat, lon, azimuth, length_km * k / (count - 1)))
	return _to_world(points)


## Cercle de portée (distance radius_km autour du point).
func _circle(lat: float, lon: float, radius_km: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for k in CIRCLE_POINTS + 1:
		points.append(GeoMath.destination(lat, lon, 360.0 * k / CIRCLE_POINTS, radius_km))
	return _to_world(points)


func _to_world(points: Array[Vector2]) -> PackedVector2Array:
	var world := PackedVector2Array()
	var previous := points[0].y
	var unwrapped := previous
	for p in points:
		unwrapped += wrapf(p.y - previous, -180.0, 180.0)
		previous = p.y
		var lat := clampf(p.x, -_map.max_lat_deg, _map.max_lat_deg)
		world.append(Vector2((unwrapped + 180.0) / 360.0, _map.world_of(lat, 0.0).y))
	return world


func _stroke(canvas: CanvasItem, world: PackedVector2Array, color: Color, width: float, copies: Array[int]) -> void:
	for copy in copies:
		var screen := PackedVector2Array()
		for w in world:
			screen.append(_map.to_screen(w, copy))
		canvas.draw_polyline(screen, color, width, true)
