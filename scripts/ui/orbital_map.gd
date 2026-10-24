class_name OrbitalMap
extends Control
## Carte du monde de l'écran de pilotage (scripts/ui/pilot_display.gd) et de la tablette, en projection de Mercator de
## max_lat_deg nord à max_lat_deg sud (80°, au poste comme sur la tablette) : contours des pays en lignes
## blanches sur fond noir (WorldMapLines, Natural Earth), méridiens et parallèles tous les 10° et équateur en gris,
## trace au sol de l'orbite, position de la station, prochain nœud (passage à l'équateur, losange cyan) et, si une
## manœuvre est prévue, trace au sol de l'orbite fantôme en pointillés cyan (FlightComputer), sur une période à partir
## du nœud.
##
## Trace au sol : la demi-orbite passée (gris-vert, fine), l'orbite en cours (une période à partir de maintenant, vert
## très clair) et les orbites_ahead orbites suivantes (0 à MAX_ORBITS_AHEAD, 1 par défaut), d'un vert de plus en plus
## sombre (la dernière vert sombre, toujours bien visible).
##
## Cibles au sol (GroundTarget, jusqu'à 5, une couleur chacune) : icône de cible dans sa couleur avec ses
## coordonnées, la cible choisie en trait épais. Carte modifiable (targets_editable : celle du poste de pilotage
## seulement, règle de jeu) : menu des cibles en haut à gauche — un bouton par cible portant son icône dans sa couleur
## (pâle tant qu'elle n'est pas posée ; le bouton de la cible choisie en surbrillance), corbeille (effacer) ; les cibles se
## placent à la main (pas de saisie de coordonnées) : un clic (sans glisser) sur la carte place la cible choisie au
## point cliqué, un clic sur une cible la choisit. Ailleurs (tablette), les cibles sont seulement affichées. Au
## survol, les coordonnées du point sous le pointeur le suivent.
##
## Rapporteur (BearingTool) : relevés de cap pour trianguler une source radar, en traits de grand cercle (BearingLog).
## Carte modifiable : boutons du rapporteur et sa corbeille en haut à droite, clic pour poser le
## centre puis pour valider, clic sur un relevé pour le choisir. Toutes les cartes affichent les relevés.
##
## Navigation, à la manière d'une carte en ligne : molette = zoom centré sur le curseur ; glisser (bouton gauche
## maintenu, au-delà de CLICK_SLOP px) = déplacer la carte dans le sens de la souris ; boutons en bas : « − » / « + » (zoom centré sur le
## centre de la carte) et le nombre d'orbites à venir (0 à 4). Zoom de 1 (monde entier) à MAX_ZOOM ; le monde se
## répète d'est en ouest (on fait le tour sans fin), et la carte ne dépasse pas ±max_lat_deg en latitude.
##
## Deux calques : le fond (grille, pays : ~85 000 segments), rendu dans la texture d'un SubViewport seulement quand la
## vue a changé et ne bouge plus depuis REDRAW_IDLE_S (redessiner autant de lignes lissées à chaque image coûtait ~20 ms
## de CPU) ; entre-temps, l'ancienne image est déplacée et mise à l'échelle pour suivre la vue. Le calque mobile (traces,
## station) est redessiné à chaque image. Rapport largeur / hauteur fixe : aspect_for(max_lat_deg) ; la taille et
## max_lat_deg sont fixées avant l'ajout à l'arbre.

signal orbits_ahead_changed(count: int)

const MAX_LAT_DEG := 80.0
const GRID_STEP_DEG := 10.0
## Demi-orbite passée dessinée derrière la station ; un point de trace par TRACK_STEP_S.
const TRACK_PAST := 0.5
const TRACK_STEP_S := 20.0
const MAX_ORBITS_AHEAD := 4
const MAX_ZOOM := 32.0
## Facteur de zoom d'un cran de molette et d'un clic sur « + » / « − ».
const WHEEL_ZOOM := 1.25
const BUTTON_ZOOM := 1.6
## Délai (s) sans mouvement de la vue avant de redessiner le fond net.
const REDRAW_IDLE_S := 0.15

const COLOR_BACKGROUND := Color.BLACK
const COLOR_LAND := Color(1, 1, 1, 0.85)
const COLOR_GRID := Color(0.5, 0.5, 0.5, 0.35)
const COLOR_EQUATOR := Color(0.6, 0.6, 0.6, 0.9)
## Orbite en cours (vert très clair) et dernière orbite à venir (vert sombre) ; dégradé entre les deux.
const COLOR_TRACK := Color(0.62, 1.0, 0.66)
const COLOR_TRACK_LAST := Color(0.1, 0.45, 0.17)
const COLOR_TRACK_PAST := Color(0.4, 0.5, 0.43, 0.8)
const COLOR_STATION := Color(1.0, 0.95, 0.4)
const COLOR_GHOST := ScreenPalette.GHOST
const COLOR_PANEL := ScreenPalette.PANEL
const COLOR_PANEL_ACTIVE := ScreenPalette.PANEL_ACTIVE
const COLOR_PANEL_TEXT := ScreenPalette.TEXT
const COLOR_PANEL_DIM := ScreenPalette.DIM
## Pointillés de la trace fantôme : DASH pas de la trace tracés, puis DASH pas vides.
const DASH := 2
## Déplacement maximal (px) entre l'appui et le relâchement pour un clic (au-delà : la carte a été glissée).
const CLICK_SLOP := 5.0
## Rayon (px) autour d'une cible où un clic la choisit.
const TARGET_PICK := 14.0
const COLOR_HOVER := ScreenPalette.TEXT

## Rapport largeur / hauteur de la carte du poste (±MAX_LAT_DEG).
static var ASPECT := aspect_for(MAX_LAT_DEG)

## Latitude des bords haut et bas (degrés).
var max_lat_deg := MAX_LAT_DEG
var orbit: OrbitSimulation
var flight_computer: FlightComputer
## Nombre d'orbites à venir dessinées après l'orbite en cours (0 à MAX_ORBITS_AHEAD).
var orbits_ahead := 1
## Cibles modifiables (menu des cibles, clic qui les place) : carte du poste de pilotage seulement. Fixé avant l'ajout
## à l'arbre.
var targets_editable := false
## Latitude et longitude sous le pointeur au survol (désactivé sur la tablette, où elles masqueraient la petite carte).
var show_hover_coordinates := true

## Vue : centre (coordonnées du monde u = longitude, v = Mercator, de 0 à 1 ; u croît vers l'est, v vers le sud) et
## zoom (1 : le monde entier à la largeur de la carte).
var _center := Vector2(0.5, 0.5)
var _zoom := 1.0
## Vue du fond actuellement rendu (pour déplacer son image en attendant le prochain rendu).
var _base_center := Vector2(0.5, 0.5)
var _base_zoom := 1.0
var _idle := 0.0
var _base_dirty := false
var _dragging := false
## Clic ou glisser : position de l'appui et distance parcourue depuis (sous CLICK_SLOP px : un clic, qui pose la cible).
var _press_position := Vector2.ZERO
var _drag_distance := 0.0
## Position du pointeur sur la carte (INF : hors de la carte) : ses coordonnées le suivent.
var _hover := Vector2.INF
var _target: GroundTarget
var _base_viewport: SubViewport
var _base: Control
var _base_image: TextureRect
var _overlay: Control
var _orbit_buttons: Array[Button] = []
## Menu des cibles (carte modifiable) : un bouton par cible.
var _slot_buttons: Array[Button] = []
## Rapporteur (relevés de cap, BearingTool) et ses boutons (carte modifiable) : rapporteur et corbeille (icônes).
var _bearing_tool: BearingTool
var _bearing_button: Button
var _bearing_erase: Button


func _ready() -> void:
	name = "Map"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_base_viewport = SubViewport.new()
	_base_viewport.size = Vector2i(size)
	_base_viewport.disable_3d = true
	_base_viewport.msaa_2d = Viewport.MSAA_4X
	_base_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_base_viewport)
	_base = Control.new()
	_base.size = size
	_base_viewport.add_child(_base)
	_base.draw.connect(_draw_base)
	_base_image = TextureRect.new()
	_base_image.texture = _base_viewport.get_texture()
	_base_image.size = size
	_base_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base_image)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_bearing_tool = BearingTool.new(self)
	_build_controls()


func _process(delta: float) -> void:
	# Carte non affichée (onglet caché, tablette rangée : son SubViewport n'est plus rendu) : rien à dessiner.
	var viewport := get_viewport() as SubViewport
	if not is_visible_in_tree() or (viewport and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED):
		return
	_overlay.queue_redraw()
	_refresh_bearing_menu()
	if _base_dirty:
		_idle += delta
		if _idle >= REDRAW_IDLE_S and not _dragging:
			_render_base()


## Rapport largeur / hauteur d'une carte de Mercator de 360° de longitude sur ±max_lat (degrés).
static func aspect_for(max_lat: float) -> float:
	return TAU / (2.0 * mercator(max_lat))


## Ordonnée de Mercator (sans unité) d'une latitude en degrés.
static func mercator(lat_deg: float) -> float:
	return log(tan(PI / 4.0 + deg_to_rad(clampf(lat_deg, -89.0, 89.0)) / 2.0))


## Coordonnées du monde (0–1) d'une position (latitude, longitude) en degrés.
func world_of(lat_deg: float, lon_deg: float) -> Vector2:
	return Vector2((lon_deg + 180.0) / 360.0, 0.5 * (1.0 - mercator(lat_deg) / mercator(max_lat_deg)))


## Point de la carte (pixels locaux) d'un point du monde, dans la copie copy du monde (−1, 0, 1 : à l'ouest, au
## centre, à l'est), pour la vue (center, zoom).
func to_screen(world: Vector2, copy := 0, center := _center, zoom := _zoom) -> Vector2:
	return (world + Vector2(copy, 0.0) - center) * size * zoom + size * 0.5


## Point de la carte (pixels locaux) d'une position (latitude, longitude) en degrés, dans la vue courante.
func project(lat_deg: float, lon_deg: float, copy := 0) -> Vector2:
	return to_screen(world_of(lat_deg, lon_deg), copy)


func get_zoom() -> float:
	return _zoom


func set_orbits_ahead(count: int) -> void:
	orbits_ahead = clampi(count, 0, MAX_ORBITS_AHEAD)
	for i in _orbit_buttons.size():
		_style_button(_orbit_buttons[i], i == orbits_ahead)
	orbits_ahead_changed.emit(orbits_ahead)


# --- Vue ------------------------------------------------------------------------------------------------------------

## Zoom de facteur factor autour du point de la carte anchor (pixels locaux), qui reste sous le curseur.
func zoom_at(anchor: Vector2, factor: float) -> void:
	var before := (anchor - size * 0.5) / (size * _zoom) + _center
	_zoom = clampf(_zoom * factor, 1.0, MAX_ZOOM)
	_center = before - (anchor - size * 0.5) / (size * _zoom)
	_apply_view()


## Déplacement de la vue de offset pixels (le contenu suit la souris).
func pan(offset: Vector2) -> void:
	_center -= offset / (size * _zoom)
	_apply_view()


func _apply_view() -> void:
	# Longitude : le monde se répète, le centre reste dans [0, 1[ ; latitude : pas au-delà des bords.
	_center.x = fposmod(_center.x, 1.0)
	var half := 0.5 / _zoom
	_center.y = clampf(_center.y, half, 1.0 - half)
	# Image du fond rendue pour l'ancienne vue : déplacée et mise à l'échelle en attendant le nouveau rendu.
	var ratio := _zoom / _base_zoom
	var shift := _base_center - _center
	shift.x = wrapf(shift.x, -0.5, 0.5)
	_base_image.scale = Vector2.ONE * ratio
	_base_image.position = -size * 0.5 * ratio + shift * size * _zoom + size * 0.5
	_base_dirty = true
	_idle = 0.0


func _render_base() -> void:
	_base_dirty = false
	var center := _center
	var zoom := _zoom
	_base.queue_redraw()
	_base_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# L'image déplacée reste en place jusqu'à ce que le nouveau fond soit dessiné (sinon, une image décalée).
	RenderingServer.frame_post_draw.connect(func() -> void:
		_base_center = center
		_base_zoom = zoom
		if not _base_dirty:
			_base_image.scale = Vector2.ONE
			_base_image.position = Vector2.ZERO
		else:
			_apply_view(), CONNECT_ONE_SHOT)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(button.position, WHEEL_ZOOM)
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(button.position, 1.0 / WHEEL_ZOOM)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_press_position = button.position
				_drag_distance = 0.0
			elif _dragging and _drag_distance < CLICK_SLOP:
				_click(button.position)
			_dragging = button.pressed
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragging and _drag_distance >= CLICK_SLOP \
					else _idle_cursor()
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion:
		_hover = motion.position
		_bearing_tool.pointer = motion.position
		if _dragging:
			_drag_distance = maxf(_drag_distance, motion.position.distance_to(_press_position))
			if _drag_distance >= CLICK_SLOP:
				mouse_default_cursor_shape = Control.CURSOR_DRAG
				pan(motion.relative)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2.INF
		if _bearing_tool:
			_bearing_tool.pointer = Vector2.INF


## Clic (sans glisser) sur la carte modifiable : choisit la cible cliquée, sinon place la cible choisie au point cliqué.
func _click(at: Vector2) -> void:
	if targets_editable and _bearing_tool.click(at):
		return
	var target := _get_target()
	if target == null or not targets_editable:
		return
	for slot in target.active_slots():
		var point := target.get_target(slot)
		for copy in _visible_copies():
			if project(point.x, point.y, copy).distance_to(at) <= TARGET_PICK:
				target.select(slot)
				return
	var clicked := lat_lon_at(at)
	target.set_target(target.selected, clicked.x, clicked.y)


func _get_target() -> GroundTarget:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
		if _target and targets_editable:
			_target.changed.connect(_refresh_target_menu)
			_refresh_target_menu()
	return _target


## (latitude, longitude) en degrés du point de la carte at (pixels locaux) : inverse de project.
func lat_lon_at(at: Vector2) -> Vector2:
	var world := (at - size * 0.5) / (size * _zoom) + _center
	var y := (1.0 - 2.0 * world.y) * mercator(max_lat_deg)
	var lat := rad_to_deg(2.0 * atan(exp(y)) - PI / 2.0)
	return Vector2(clampf(lat, -max_lat_deg, max_lat_deg), wrapf(world.x * 360.0 - 180.0, -180.0, 180.0))


## Copies du monde (−1, 0, 1) visibles dans la vue courante.
func _visible_copies() -> Array[int]:
	var copies: Array[int] = []
	for copy in [-1, 0, 1]:
		var left := to_screen(Vector2(0.0, 0.0), copy).x
		var right := to_screen(Vector2(1.0, 0.0), copy).x
		# Strict : une copie qui touche seulement le bord n'est pas dessinée (au zoom 1, sinon trois fois tout).
		if right > 0.5 and left < size.x - 0.5:
			copies.append(copy)
	return copies


# --- Dessin ---------------------------------------------------------------------------------------------------------

func _draw_base() -> void:
	_base.draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	var lines := WorldMapLines.get_lines()
	var segments := PackedVector2Array()
	for copy in _visible_copies():
		var lon := -180.0
		while lon <= 180.0:
			var x := project(0.0, lon, copy).x
			if x >= -1.0 and x <= size.x + 1.0:
				_base.draw_line(Vector2(x, 0.0), Vector2(x, size.y), COLOR_GRID, 1.0)
			lon += GRID_STEP_DEG
		var west := maxf(0.0, project(0.0, -180.0, copy).x)
		var east := minf(size.x, project(0.0, 180.0, copy).x)
		var lat := -max_lat_deg
		while lat <= max_lat_deg:
			var y := project(lat, 0.0).y
			var equator := is_zero_approx(lat)
			_base.draw_line(Vector2(west, y), Vector2(east, y), COLOR_EQUATOR if equator else COLOR_GRID,
					2.0 if equator else 1.0)
			lat += GRID_STEP_DEG
		if lines == null:
			continue
		# Tous les contours en un seul appel de dessin (segments indépendants, extrémités par paires) ; anneaux hors
		# de la vue ignorés.
		var view := Rect2(Vector2.ZERO, size).grow(2.0)
		for r in lines.ring_count():
			var ring := lines.ring(r)
			var previous := project(ring[0].y, ring[0].x, copy)
			for k in range(1, ring.size()):
				var point := project(ring[k].y, ring[k].x, copy)
				if view.has_point(point) or view.has_point(previous):
					segments.append(previous)
					segments.append(point)
				previous = point
	if not segments.is_empty():
		_base.draw_multiline(segments, COLOR_LAND, 1.2, true)


func _draw_overlay() -> void:
	if orbit == null:
		return
	var now := orbit.sim_time_s
	var period := orbit.get_period_s()
	var copies := _visible_copies()
	var track_at := func(t: float) -> Vector2: return orbit.get_subsatellite_point(t)
	_check_cache(&"orbit", track_at, now)
	_draw_track(_overlay, &"orbit", track_at, now - TRACK_PAST * period, now, COLOR_TRACK_PAST, 1.5, copies)
	# Des orbites les plus lointaines (sombres) à l'orbite en cours (claire, dessinée par-dessus).
	for k in range(orbits_ahead, -1, -1):
		var share := float(k) / float(MAX_ORBITS_AHEAD)
		_draw_track(_overlay, &"orbit", track_at, now + k * period, now + (k + 1) * period,
				COLOR_TRACK.lerp(COLOR_TRACK_LAST, share), 2.5 if k == 0 else 2.0, copies)
	_prune_cache(&"orbit", now - TRACK_PAST * period)
	if flight_computer:
		if flight_computer.has_plan():
			var ghost := flight_computer.get_ghost()
			var ghost_at := func(t: float) -> Vector2: return flight_computer.ghost_ground_point(ghost, t)
			_check_cache(&"ghost", ghost_at, ghost.node_time_s)
			_draw_track(_overlay, &"ghost", ghost_at, ghost.node_time_s, ghost.node_time_s + TAU / ghost.mean_motion,
					COLOR_GHOST, 2.5, copies, true)
			_prune_cache(&"ghost", ghost.node_time_s)
		else:
			_track_cache.erase(&"ghost")
		var node := orbit.get_subsatellite_point(flight_computer.get_node_time_s())
		for copy in copies:
			var at := project(node.x, node.y, copy)
			var r := 11.0
			_overlay.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0),
					at + Vector2(0, r), at + Vector2(-r, 0)]), COLOR_GHOST)
	_bearing_tool.draw(_overlay, copies, get_theme_default_font(), _label_size())
	for copy in copies:
		_draw_station(_overlay, copy)
	_draw_target(copies)
	_draw_hover()


## Cibles au sol (GroundTarget) : icône de chaque cible dans sa couleur, coordonnées à côté ; la cible choisie en
## trait épais, les autres plus fines et un peu transparentes.
func _draw_target(copies: Array[int]) -> void:
	var target := _get_target()
	if target == null:
		return
	var font := get_theme_default_font()
	var font_size := _label_size()
	for slot in target.active_slots():
		var point := target.get_target(slot)
		var chosen := slot == target.selected
		var color := GroundTarget.color_of(slot)
		if not chosen:
			color.a = 0.8
		var text := GeoMath.format_lat_lon(point.x, point.y)
		for copy in copies:
			var at := project(point.x, point.y, copy)
			GroundTarget.draw_icon(_overlay, at, 18.0, color, 2.5 if chosen else 1.5)
			_draw_label(at + Vector2(22.0, -10.0), text, font, font_size, color)


## Coordonnées sous le pointeur (au survol de la carte, hors glisser).
func _draw_hover() -> void:
	if not show_hover_coordinates or _hover == Vector2.INF or (_dragging and _drag_distance >= CLICK_SLOP) \
			or not Rect2(Vector2.ZERO, size).has_point(_hover):
		return
	var point := lat_lon_at(_hover)
	_draw_label(_hover + Vector2(18.0, 22.0), GeoMath.format_lat_lon(point.x, point.y), get_theme_default_font(),
			_label_size(), COLOR_HOVER)


## Texte sur un fond sombre, gardé dans la carte (à gauche du point s'il déborderait à droite).
func _draw_label(at: Vector2, text: String, font: Font, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(at - Vector2(6.0, text_size.y * 0.8), text_size + Vector2(12.0, 6.0))
	if box.end.x > size.x:
		box.position.x -= box.size.x + 40.0
	box.position.y = clampf(box.position.y, 0.0, size.y - box.size.y)
	_overlay.draw_rect(box, Color(0.0, 0.0, 0.0, 0.7))
	_overlay.draw_string(font, box.position + Vector2(6.0, text_size.y * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)


func _label_size() -> int:
	return clampi(roundi(size.y * 0.022), 11, 22)


## Points de trace en cache, par source (&"orbit", &"ghost") : indice k de la grille t = k·TRACK_STEP_S -> (lat, lon).
## Une trace se recalculait en entier à chaque image (~1 250 points à 4 orbites, ~3,5 ms par carte) ; seuls les
## points nouveaux le sont désormais.
var _track_cache := {}


## Vide le cache d'une source si son point témoin a changé : orbite modifiée (manœuvre, date, altitude…), orbite
## visée modifiée (inclinaison, altitude, décalage du nœud). Un seul calcul par image. Point témoin : le premier
## point de grille après t, que _draw_track met en cache pour toute trace qui commence à t (le point de grille sous t
## ne l'est pas quand la trace commence à t : la trace fantôme, qui part du nœud, n'aurait jamais été vidée).
func _check_cache(source: StringName, point_at: Callable, t: float) -> void:
	var cache: Dictionary = _track_cache.get_or_add(source, {})
	var k := floori(t / TRACK_STEP_S) + 1
	if cache.has(k):
		var fresh: Vector2 = point_at.call(k * TRACK_STEP_S)
		if not fresh.is_equal_approx(cache[k]):
			cache.clear()


func _prune_cache(source: StringName, from_s: float) -> void:
	var cache: Dictionary = _track_cache.get(source, {})
	var first := floori(from_s / TRACK_STEP_S)
	for k in cache.keys():
		if k < first:
			cache.erase(k)


## Trace au sol de point_at(t) -> Vector2(lat, lon) entre from_s et to_s, dans chaque copie visible du monde, coupée
## au passage de l'antiméridien, pleine ou en pointillés. Points intermédiaires sur la grille de TRACK_STEP_S (en cache,
## source), extrémités exactes.
func _draw_track(layer: Control, source: StringName, point_at: Callable, from_s: float, to_s: float, color: Color,
		width: float, copies: Array[int], dashed := false) -> void:
	var cache: Dictionary = _track_cache.get_or_add(source, {})
	var points: Array[Vector2] = [point_at.call(from_s)]
	for k in range(floori(from_s / TRACK_STEP_S) + 1, ceili(to_s / TRACK_STEP_S)):
		if not cache.has(k):
			cache[k] = point_at.call(k * TRACK_STEP_S)
		points.append(cache[k])
	points.append(point_at.call(to_s))
	for copy in copies:
		var segment := PackedVector2Array()
		var previous := Vector2(NAN, NAN)
		for point in points:
			if not is_nan(previous.y) and absf(point.y - previous.y) > 180.0:
				# Passage de l'antiméridien : le segment s'arrête au bord et reprend de l'autre côté (pas de quelques
				# dizaines de km : la latitude au bord est prise à mi-chemin).
				var edge := 180.0 if previous.y > 0.0 else -180.0
				var lat_edge := (previous.x + point.x) * 0.5
				segment.append(project(lat_edge, edge, copy))
				_stroke(layer, segment, color, width, dashed)
				segment = PackedVector2Array([project(lat_edge, -edge, copy)])
			segment.append(project(point.x, point.y, copy))
			previous = point
		_stroke(layer, segment, color, width, dashed)


func _stroke(layer: Control, points: PackedVector2Array, color: Color, width: float, dashed: bool) -> void:
	if points.size() < 2:
		return
	if not dashed:
		layer.draw_polyline(points, color, width, true)
		return
	var dashes := PackedVector2Array()
	for k in points.size() - 1:
		@warning_ignore("integer_division")
		if (k / DASH) % 2 == 0:
			dashes.append(points[k])
			dashes.append(points[k + 1])
	if not dashes.is_empty():
		layer.draw_multiline(dashes, color, width, true)


func _draw_station(layer: Control, copy: int) -> void:
	var now := orbit.sim_time_s
	var point := orbit.get_subsatellite_point(now)
	var ahead := orbit.get_subsatellite_point(now + 30.0)
	var at := project(point.x, point.y, copy)
	# Longitude d'arrivée dépliée (antiméridien entre les deux points).
	var heading := project(ahead.x, point.y + wrapf(ahead.y - point.y, -180.0, 180.0), copy) - at
	heading = heading.normalized() if heading.length() > 1e-3 else Vector2.RIGHT
	var side := heading.orthogonal()
	var size_px := 14.0
	layer.draw_colored_polygon(PackedVector2Array([at + heading * size_px * 1.4, at + side * size_px * 0.7 - heading * size_px * 0.6,
			at - side * size_px * 0.7 - heading * size_px * 0.6]), COLOR_STATION)
	layer.draw_arc(at, size_px * 1.8, 0.0, TAU, 32, COLOR_STATION, 2.0, true)


# --- Commandes ------------------------------------------------------------------------------------------------------

## Barre en bas de la carte : zoom « − » / « + » à gauche, orbites à venir (0 à 4) à droite. Taille des boutons
## proportionnelle à la hauteur de la carte (lisible au poste comme sur la tablette).
func _build_controls() -> void:
	var height := clampf(size.y * 0.11, 34.0, 48.0)
	var font := int(height * 0.55)
	var margin := height * 0.3
	var zoom_bar := HBoxContainer.new()
	zoom_bar.add_theme_constant_override("separation", 4)
	zoom_bar.position = Vector2(margin, size.y - height - margin)
	add_child(zoom_bar)
	for spec in [["−", "MAP_ZOOM_OUT", 1.0 / BUTTON_ZOOM], ["+", "MAP_ZOOM_IN", BUTTON_ZOOM]]:
		var zoom_button := _make_button(spec[0], height, int(font * 1.5))
		zoom_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		zoom_button.tooltip_text = tr(spec[1])
		var factor: float = spec[2]
		zoom_button.pressed.connect(func() -> void: zoom_at(size * 0.5, factor))
		zoom_bar.add_child(zoom_button)
	var orbit_bar := HBoxContainer.new()
	orbit_bar.add_theme_constant_override("separation", 4)
	add_child(orbit_bar)
	# Icône « orbites à venir » (planète, orbite inclinée et flèche du sens de parcours) ; nom en info-bulle.
	var orbit_icon := Control.new()
	orbit_icon.custom_minimum_size = Vector2(height * 1.5, height)
	orbit_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	orbit_icon.tooltip_text = tr("MAP_ORBITS_AHEAD")
	orbit_icon.draw.connect(func() -> void:
		_draw_orbits_icon(orbit_icon, orbit_icon.size * 0.5, orbit_icon.size.y * 0.62))
	orbit_bar.add_child(orbit_icon)
	for count in MAX_ORBITS_AHEAD + 1:
		var orbit_button := _make_button(str(count), height, font)
		orbit_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		orbit_button.pressed.connect(func() -> void: set_orbits_ahead(count))
		orbit_bar.add_child(orbit_button)
		_orbit_buttons.append(orbit_button)
	set_orbits_ahead(orbits_ahead)
	# À droite : position après calcul de la largeur de la barre.
	var place := func() -> void:
		orbit_bar.position = Vector2(size.x - orbit_bar.size.x - margin, size.y - height - margin)
	orbit_bar.resized.connect(place)
	place.call_deferred()
	if targets_editable:
		_build_target_menu(height, font, margin)
		_build_bearing_menu(height, font, margin)


## Menu des cibles (en haut à gauche) : un bouton par cible (la choisir), corbeille (efface la cible choisie).
func _build_target_menu(height: float, font: int, margin: float) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.position = Vector2(margin, margin)
	add_child(bar)
	for slot in GroundTarget.MAX_TARGETS:
		# Icône de la cible dans sa couleur (pâle tant qu'elle n'est pas posée), dessinée sur le bouton.
		var slot_button := _make_button("", height, font)
		slot_button.pressed.connect(func() -> void:
			var target := _get_target()
			if target:
				target.select(slot))
		slot_button.draw.connect(func() -> void:
			var target := _target
			var placed := target != null and target.has_target(slot)
			var color := GroundTarget.color_of(slot)
			GroundTarget.draw_icon(slot_button, slot_button.size * 0.5, slot_button.size.y * 0.36,
					color if placed else Color(color, 0.35), 2.5 if placed else 2.0))
		bar.add_child(slot_button)
		_slot_buttons.append(slot_button)
	var erase := _make_icon_button("MAP_TARGET_CLEAR", height, _draw_erase_icon)
	erase.pressed.connect(func() -> void:
		var target := _get_target()
		if target:
			target.clear_target(target.selected))
	bar.add_child(erase)
	_get_target()


## Icône des orbites à venir : planète, orbite inclinée (ellipse) et flèche du sens de parcours ;
## sous-couche sombre pour rester lisible sur la carte.
func _draw_orbits_icon(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var orbit := PackedVector2Array()
	var tilt := deg_to_rad(-22.0)
	for k in 41:
		var a := TAU * k / 40.0
		orbit.append(center + Vector2(cos(a) * radius, sin(a) * radius * 0.36).rotated(tilt))
	var tip := center + Vector2(cos(0.5) * radius, sin(0.5) * radius * 0.36).rotated(tilt)
	var ahead := (center + Vector2(cos(0.75) * radius, sin(0.75) * radius * 0.36).rotated(tilt) - tip).normalized()
	var side := ahead.orthogonal() * radius * 0.2
	var head := PackedVector2Array([tip + ahead * radius * 0.38, tip + side, tip - side])
	for pass_index in 2:
		var shadow := pass_index == 0
		var color := Color(0, 0, 0, 0.85) if shadow else COLOR_PANEL_TEXT
		var extra := 3.0 if shadow else 0.0
		canvas.draw_arc(center, radius * 0.36, 0.0, TAU, 32, color, 2.5 + extra, true)
		canvas.draw_polyline(orbit, color, 2.5 + extra, true)
		canvas.draw_polyline(head + PackedVector2Array([head[0]]), color, 1.0 + extra, true)
		canvas.draw_colored_polygon(head, color)


## Rapporteur (en haut à droite, sur la ligne du menu des cibles) : icône du rapporteur (démarrer ou annuler un relevé,
## en surbrillance pendant le relevé), corbeille (efface le relevé choisi ; pâle sans relevé choisi).
func _build_bearing_menu(height: float, font: int, margin: float) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	# Icône du rapporteur (dessinée), nom de l'outil en info-bulle.
	_bearing_button = _make_button("", height, font)
	_bearing_button.custom_minimum_size.x = height * 1.3
	_bearing_button.tooltip_text = tr("MAP_BEARING_TOOL")
	_bearing_button.draw.connect(func() -> void:
		BearingTool.draw_icon(_bearing_button, _bearing_button.size * 0.5, _bearing_button.size.y * 0.36,
				COLOR_PANEL_TEXT, 2.0))
	_bearing_button.pressed.connect(func() -> void: _bearing_tool.toggle())
	bar.add_child(_bearing_button)
	_bearing_erase = _make_icon_button("MAP_BEARING_CLEAR", height, _draw_erase_icon)
	_bearing_erase.pressed.connect(func() -> void:
		var bearing_log := _bearing_tool.get_log()
		if bearing_log:
			bearing_log.remove(bearing_log.selected))
	bar.add_child(_bearing_erase)
	var place := func() -> void:
		bar.position = Vector2(size.x - bar.size.x - margin, margin)
	bar.resized.connect(place)
	place.call_deferred()


## Style des boutons du rapporteur d'après l'état de l'outil (appliqué seulement quand il change).
var _bearing_menu_state := -1

func _refresh_bearing_menu() -> void:
	if _bearing_button == null:
		return
	var bearing_log := _bearing_tool.get_log()
	var has_selection := bearing_log != null and bearing_log.selected >= 0
	var state := int(_bearing_tool.mode != BearingTool.Mode.OFF) + 2 * int(has_selection)
	if state == _bearing_menu_state:
		return
	_bearing_menu_state = state
	_style_button(_bearing_button, _bearing_tool.mode != BearingTool.Mode.OFF)
	mouse_default_cursor_shape = _idle_cursor()
	_bearing_erase.modulate.a = 1.0 if has_selection else 0.5


## Menu des cibles : bouton de la cible choisie en surbrillance ; icônes redessinées (posées : couleur vive).
func _refresh_target_menu() -> void:
	var target := _target
	if target == null or _slot_buttons.is_empty():
		return
	for slot in _slot_buttons.size():
		_style_button(_slot_buttons[slot], slot == target.selected)
		_slot_buttons[slot].queue_redraw()


## Bouton carré à icône dessinée (draw_icon(canvas, centre, rayon)), nom de l'action en info-bulle.
func _make_icon_button(tooltip_key: String, height: float, draw_icon: Callable) -> Button:
	var button := _make_button("", height, int(height * 0.55))
	button.tooltip_text = tr(tooltip_key)
	button.draw.connect(func() -> void: draw_icon.call(button, button.size * 0.5, button.size.y * 0.32))
	return button


## Icône « effacer » : corbeille (couvercle et poignée, cuve évasée rayée).
func _draw_erase_icon(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	var color := COLOR_PANEL_TEXT
	var top := center.y - radius * 0.62
	canvas.draw_line(Vector2(center.x - radius * 0.85, top), Vector2(center.x + radius * 0.85, top), color, 2.0, true)
	canvas.draw_polyline(PackedVector2Array([Vector2(center.x - radius * 0.28, top), Vector2(center.x - radius * 0.28,
			top - radius * 0.3), Vector2(center.x + radius * 0.28, top - radius * 0.3),
			Vector2(center.x + radius * 0.28, top)]), color, 2.0, true)
	var bottom := center.y + radius
	canvas.draw_polyline(PackedVector2Array([Vector2(center.x - radius * 0.65, top + radius * 0.2),
			Vector2(center.x - radius * 0.5, bottom), Vector2(center.x + radius * 0.5, bottom),
			Vector2(center.x + radius * 0.65, top + radius * 0.2)]), color, 2.0, true)
	for k: int in [-1, 0, 1]:
		var x := center.x + k * radius * 0.25
		canvas.draw_line(Vector2(x, top + radius * 0.45), Vector2(x, bottom - radius * 0.25), color, 1.5, true)


func _make_button(text: String, height: float, font: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(height, height)
	button.add_theme_font_size_override("font_size", font)
	_style_button(button, false)
	return button


func _style_button(button: Button, active: bool) -> void:
	var style := UiKit.flat_box(COLOR_PANEL_ACTIVE if active else COLOR_PANEL,
			COLOR_PANEL_TEXT if active else COLOR_PANEL_DIM, 2 if active else 1, 5)
	style.content_margin_left = 6
	style.content_margin_right = 6
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.border_color = COLOR_PANEL_TEXT
	button.add_theme_stylebox_override("hover", hover)
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, COLOR_PANEL_TEXT if active else COLOR_PANEL_DIM)


## Curseur hors glisser : en croix pendant un relevé au rapporteur.
func _idle_cursor() -> Control.CursorShape:
	return Control.CURSOR_CROSS if _bearing_tool and _bearing_tool.mode != BearingTool.Mode.OFF \
			else Control.CURSOR_ARROW
