class_name OrbitalMap
extends Control
## Carte du monde de l'écran de pilotage (scripts/ui/pilot_display.gd), en projection de Mercator de MAX_LAT_DEG nord
## à MAX_LAT_DEG sud : contours des pays en lignes blanches sur fond noir (WorldMapLines, Natural Earth), méridiens et
## parallèles tous les 10° et équateur en gris, trace au sol de l'orbite en vert (passée en vert sombre) et position
## de la station.
## Deux calques : le fond fixe (grille, pays : ~85 000 segments), rendu une seule fois dans la texture d'un
## SubViewport (redessiner autant de lignes lissées à chaque image coûtait ~20 ms de CPU), et le calque mobile (trace,
## station), redessiné à chaque image. Rapport largeur / hauteur fixe : ASPECT ; la taille est fixée avant l'ajout
## à l'arbre.

const MAX_LAT_DEG := 80.0
const GRID_STEP_DEG := 10.0
## Trace au sol dessinée de −TRACK_PAST à +TRACK_AHEAD périodes autour de l'instant présent, un point par TRACK_STEP_S.
const TRACK_PAST := 0.5
const TRACK_AHEAD := 1.5
const TRACK_STEP_S := 20.0

const COLOR_BACKGROUND := Color.BLACK
const COLOR_LAND := Color(1, 1, 1, 0.85)
const COLOR_GRID := Color(0.5, 0.5, 0.5, 0.35)
const COLOR_EQUATOR := Color(0.6, 0.6, 0.6, 0.9)
const COLOR_TRACK := Color(0.2, 1.0, 0.35)
const COLOR_TRACK_PAST := Color(0.15, 0.55, 0.22)
const COLOR_STATION := Color(1.0, 0.95, 0.4)

## Rapport largeur / hauteur de la carte : 360° de longitude sur ±MAX_LAT_DEG en Mercator.
static var ASPECT := TAU / (2.0 * mercator(MAX_LAT_DEG))

var orbit: OrbitSimulation

var _base: Control
var _overlay: Control


func _ready() -> void:
	clip_contents = true
	var base_viewport := SubViewport.new()
	base_viewport.size = Vector2i(size)
	base_viewport.disable_3d = true
	base_viewport.msaa_2d = Viewport.MSAA_4X
	base_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(base_viewport)
	_base = Control.new()
	_base.size = size
	base_viewport.add_child(_base)
	_base.draw.connect(_draw_base)
	var base_image := TextureRect.new()
	base_image.texture = base_viewport.get_texture()
	base_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base_image)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func _process(_delta: float) -> void:
	_overlay.queue_redraw()


## Ordonnée de Mercator (sans unité) d'une latitude en degrés.
static func mercator(lat_deg: float) -> float:
	return log(tan(PI / 4.0 + deg_to_rad(clampf(lat_deg, -89.0, 89.0)) / 2.0))


## Point de la carte (pixels locaux) d'une position (latitude, longitude) en degrés.
func project(lat_deg: float, lon_deg: float) -> Vector2:
	return Vector2((lon_deg + 180.0) / 360.0 * size.x,
			size.y * 0.5 * (1.0 - mercator(lat_deg) / mercator(MAX_LAT_DEG)))


func _draw_base() -> void:
	_base.draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	var lon := -180.0
	while lon <= 180.0:
		var x := project(0.0, lon).x
		_base.draw_line(Vector2(x, 0.0), Vector2(x, size.y), COLOR_GRID, 1.0)
		lon += GRID_STEP_DEG
	var lat := -MAX_LAT_DEG
	while lat <= MAX_LAT_DEG:
		var y := project(lat, 0.0).y
		var color := COLOR_EQUATOR if is_zero_approx(lat) else COLOR_GRID
		_base.draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 2.0 if is_zero_approx(lat) else 1.0)
		lat += GRID_STEP_DEG
	# Tous les contours en un seul appel de dessin (segments indépendants, extrémités par paires).
	var lines := WorldMapLines.get_lines()
	if lines == null:
		return
	var segments := PackedVector2Array()
	for r in lines.ring_count():
		var ring := lines.ring(r)
		var previous := project(ring[0].y, ring[0].x)
		for k in range(1, ring.size()):
			var point := project(ring[k].y, ring[k].x)
			segments.append(previous)
			segments.append(point)
			previous = point
	_base.draw_multiline(segments, COLOR_LAND, 1.2, true)


func _draw_overlay() -> void:
	if orbit == null:
		return
	var now := orbit.sim_time_s
	var period := orbit.get_period_s()
	_draw_track(_overlay, orbit.get_subsatellite_point, now - TRACK_PAST * period, now, COLOR_TRACK_PAST, 2.0)
	_draw_track(_overlay, orbit.get_subsatellite_point, now, now + TRACK_AHEAD * period, COLOR_TRACK, 2.5)
	_draw_station(_overlay)


## Trace au sol de point_at(t) -> Vector2(lat, lon) entre from_s et to_s, coupée au passage de l'antiméridien.
func _draw_track(layer: Control, point_at: Callable, from_s: float, to_s: float, color: Color, width: float) -> void:
	var segment := PackedVector2Array()
	var previous := Vector2(NAN, NAN)
	var t := from_s
	while true:
		var point: Vector2 = point_at.call(minf(t, to_s))
		if not is_nan(previous.y) and absf(point.y - previous.y) > 180.0:
			# Passage de l'antiméridien : le segment s'arrête au bord et reprend de l'autre côté (pas de quelques
			# dizaines de km : la latitude au bord est prise à mi-chemin).
			var edge := 180.0 if previous.y > 0.0 else -180.0
			var lat_edge := (previous.x + point.x) * 0.5
			segment.append(project(lat_edge, edge))
			if segment.size() >= 2:
				layer.draw_polyline(segment, color, width, true)
			segment = PackedVector2Array([project(lat_edge, -edge)])
		segment.append(project(point.x, point.y))
		previous = point
		if t >= to_s:
			break
		t += TRACK_STEP_S
	if segment.size() >= 2:
		layer.draw_polyline(segment, color, width, true)


func _draw_station(layer: Control) -> void:
	var now := orbit.sim_time_s
	var point := orbit.get_subsatellite_point(now)
	var ahead := orbit.get_subsatellite_point(now + 30.0)
	var at := project(point.x, point.y)
	# Longitude d'arrivée dépliée (antiméridien entre les deux points).
	var heading := project(ahead.x, point.y + wrapf(ahead.y - point.y, -180.0, 180.0)) - at
	heading = heading.normalized() if heading.length() > 1e-3 else Vector2.RIGHT
	var side := heading.orthogonal()
	var size_px := 14.0
	layer.draw_colored_polygon(PackedVector2Array([at + heading * size_px * 1.4, at + side * size_px * 0.7 - heading * size_px * 0.6,
			at - side * size_px * 0.7 - heading * size_px * 0.6]), COLOR_STATION)
	layer.draw_arc(at, size_px * 1.8, 0.0, TAU, 32, COLOR_STATION, 2.0, true)
