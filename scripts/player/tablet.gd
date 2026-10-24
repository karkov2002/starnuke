class_name Tablet
extends Node3D
## Tablette de l'observateur (nœud Observer/Camera/Tablet de scenes/orbit_view.tscn) : modèle Blender
## assets/tablet/tablet.glb (tools/blender/build_tablet.py), tenu en bas à droite de la vue, écran tourné vers l'œil,
## par la main droite modélisée avec elle (Main_Droite, Manche : elle arrive avec la tablette ; sortie, seul le pouce,
## posé sur la bordure de droite, reste dans le champ). Son écran (objet Ecran_Tablette, UV 0–1) affiche l'interface TabletDisplay, dessinée dans un
## SubViewport : date et heure, carte réduite, BURN, silos et tir.
## - Touche Tab (action tablet) : la main amène la tablette devant les yeux (ARRIVE_S) ou la range (STOW_S) ; rangée,
##   elle est masquée. Ignorée pendant la saisie d'un texte et au poste de pilotage (la tablette s'y range d'elle-même).
## - Mouvement de la main : la tablette arrive du bas à droite en décrivant une boucle (courbe de Bézier : elle monte
##   sur le côté, dépasse un peu sa place puis s'y pose), en se redressant (inclinée, tournée vers la droite au
##   départ) ; rangée par le chemin inverse. Sortie, elle respire légèrement (balancement lent de quelques
##   millimètres) et suit la tête avec un temps de retard (elle traîne un peu quand on tourne la vue, puis rattrape).
## - Sortie, elle est prioritaire et exclusive sur la souris : sous sa coque (covers), rien derrière elle n'a de bulle ni
##   de clic. Les clics et mouvements de la souris sur son écran sont transmis à l'interface (rayon de la caméra par le
##   curseur, intersecté avec la dalle : StationScreen, ScreenInputForwarder) ; ailleurs, la souris garde son rôle
##   (clic droit : tourner la tête).
## - Vue au nadir et photos satellites : NadirCamera (scripts/nadir_camera.gd), créée ici ; la tablette ne fait que
##   l'activer sur l'onglet Photographie et relayer le bouton Photo vers l'archive (PhotoArchive).
## Position : écran occupant view_fill de la hauteur de la vue (selon le champ de la caméra), son bord droit à
## right_margin du bord droit de la vue, son bord bas à bottom_margin du bas, tourné vers l'œil. Éclairée par les
## lampes intérieures (calque Station.INTERIOR_LAYER) comme le reste de l'habitacle.

const GROUP := &"tablet"
const MODEL := preload("res://assets/tablet/tablet.glb")
const SCREEN_NODE := "Ecran_Tablette"
const BODY_NODE := "Tablette_Coque"
## Main qui tient la tablette : nue (combinaison de vol) ou gantée quand la combinaison du sas est portée
## (Station.suit_changed) : gant blanc, bague de poignet et manche de la combinaison (tools/blender/build_tablet.py).
const BARE_HAND_NODES: Array[String] = ["Main_Droite", "Manche"]
const GLOVED_HAND_NODES: Array[String] = ["Gant_Droit", "Gant_Bague", "Manche_Combinaison"]
## Hauteur de l'image de l'interface (pixels) : proche de la taille affichée, pour garder un texte lisible.
const VIEWPORT_HEIGHT := 560
## Échelle de la tablette (et de sa distance à l'œil) : voir _update_pose.
const NEAR_SCALE := 0.4
## Part de la rotation vers l'œil à l'arrivée (1 : face à l'œil, 0 : parallèle au plan de la vue).
const FACING_SHARE := 0.5
const ARRIVE_S := 0.6
const STOW_S := 0.4
## Orientation de départ (main baissée sur le côté) : inclinaison (roulis), tournée vers la droite (lacet), penchée
## vers l'avant (tangage), en degrés.
const START_ROLL_DEG := -32.0
const START_YAW_DEG := 40.0
const START_PITCH_DEG := 25.0
## Respiration : amplitude (m, degrés) et périodes (s).
const BREATH_M := 0.0018
const BREATH_DEG := 0.35
## Retard sur la tête : part de la rotation de la vue rendue (la tablette traîne), constante de retour (s), maximum.
const LAG_GAIN := 0.5
const LAG_TAU_S := 0.16
const LAG_MAX_RAD := 0.06

@export var orbit_path: NodePath = ^"../../../Orbit"
@export var flight_computer_path: NodePath = ^"../../../FlightComputer"
@export var pilot_console_path: NodePath = ^"../../../PilotConsole"
@export var earth_path: NodePath = ^"../../../Earth"
@export var world_environment_path: NodePath = ^"../../../WorldEnvironment"
## Vue au nadir (onglet Photographie) : champ de la caméra (degrés), distance sous la station (m, sous la coque).
@export var nadir_fov_deg := 22.0
@export var nadir_offset_m := 15.0
## Part de la hauteur de la vue occupée par la tablette sortie.
## (Le haut de la tablette reste sous le centre de la vue : le réticule de tir reste visible.)
@export_range(0.2, 0.9) var view_fill := 0.42
## Marge entre le bas de la tablette et le bas de la vue (part de la hauteur de la vue, avant l'inclinaison vers
## l'œil, qui abaisse le bord bas) : le bord bas reste un peu au-dessus du bas de la vue (à 0,035, la dernière
## rangée de silos et le bouton de tir sortaient de l'écran, surtout si la barre des tâches mord sur la fenêtre) ; la main et le bras, dessous et
## derrière, sont hors du champ (seul le pouce, sur la bordure de droite, reste visible ; l'écran reste entier).
@export var bottom_margin := 0.08
## Marge entre le bord droit de la tablette et celui de la vue (part de la largeur de la vue, avant la perspective, qui
## fait dépasser le coin inférieur droit) : le pouce, sur la bordure de droite, reste dans le champ.
@export var right_margin := 0.1
## Luminosité de l'écran (émission).
@export var screen_energy := 1.0

var _camera: Camera3D
var _model: Node3D
## Dalle de l'écran (StationScreen : point sous le curseur, matériau d'affichage) et transfert de la souris.
var _screen: StationScreen
## Coque (son contour couvre ce qui est derrière elle : voir covers).
var _body: MeshInstance3D
var _viewport: SubViewport
var _input_forwarder: ScreenInputForwarder
var _display: TabletDisplay
## Vue au nadir : rendue seulement quand la tablette est sortie sur l'onglet Photographie.
var _nadir: NadirCamera
var _console: PilotConsole
## Dimensions de la coque (m), pour le cadrage.
var _height := 0.19
var _width := 0.28
## Retard sur la tête (lacet, tangage en radians) et orientation de la caméra à l'image précédente.
var _lag := Vector2.ZERO
var _previous_view := Basis.IDENTITY
var _time := 0.0
## 0 : rangée (masquée), 1 : sortie.
var _out := 0.0
var _wanted := false
var _tween: Tween


func _ready() -> void:
	# Indépendante de l'observateur (désactivé au poste de pilotage) : sinon son rangement s'y figeait, tablette
	# restée sortie devant l'écran du poste ; elle s'arrête toujours avec la pause du jeu.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(GROUP)
	_camera = get_parent() as Camera3D
	if _camera:
		_previous_view = _camera.global_basis.orthonormalized()
	_console = get_node_or_null(pilot_console_path) as PilotConsole
	_connect_seats.call_deferred()
	_connect_suit.call_deferred()
	_model = MODEL.instantiate()
	add_child(_model)
	for mesh_instance: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.layers |= Station.INTERIOR_LAYER
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_gloved(false)
	var body := _model.find_child(BODY_NODE, true, false) as MeshInstance3D
	_body = body
	if body:
		_height = body.get_aabb().size.y
		_width = body.get_aabb().size.x
	_screen = StationScreen.of_mesh(_model.find_child(SCREEN_NODE, true, false) as MeshInstance3D)
	if _screen == null:
		push_error("Tablet : écran %s introuvable dans %s" % [SCREEN_NODE, MODEL.resource_path])
		return
	_viewport = _screen.make_viewport(VIEWPORT_HEIGHT, true)
	add_child(_viewport)
	_input_forwarder = ScreenInputForwarder.new(_viewport)
	_nadir = NadirCamera.new(_camera, get_node_or_null(earth_path) as Node3D,
			get_node_or_null(world_environment_path) as WorldEnvironment, nadir_fov_deg, nadir_offset_m)
	add_child(_nadir)
	var display := TabletDisplay.new()
	_display = display
	display.name = "Display"
	display.size = Vector2(_viewport.size)
	display.nadir_texture = _nadir.get_texture()
	display.orbit = get_node(orbit_path) as OrbitSimulation
	display.flight_computer = get_node(flight_computer_path) as FlightComputer
	display.photo_requested.connect(_take_photo)
	_viewport.add_child(display)
	_connect_archive.call_deferred()
	# Même shader que l'écran du poste de pilotage : émission brute (un StandardMaterial3D émet en nits avec les
	# unités de lumière physiques du projet, 1 000 par défaut : écran tout blanc).
	_screen.apply_shader(PilotConsole.SCREEN_SHADER, _viewport.get_texture(), {"top_left": _screen.top_left,
			"axis_u": _screen.axis_u, "axis_v": _screen.axis_v, "energy": screen_energy})
	visible = false
	_update_pose()


func _process(delta: float) -> void:
	_time += delta
	# Retard sur la tête : la rotation de la vue depuis l'image précédente est rendue en partie à la tablette, qui
	# revient ensuite d'elle-même (constante LAG_TAU_S).
	var view := _camera.global_basis.orthonormalized() if _camera else Basis.IDENTITY
	var turn := (_previous_view.inverse() * view).get_euler()
	_previous_view = view
	_lag = (_lag - Vector2(turn.y, turn.x) * LAG_GAIN) * exp(-delta / LAG_TAU_S)
	_lag = _lag.clampf(-LAG_MAX_RAD, LAG_MAX_RAD)
	if visible:
		_update_pose()
	# Rangée, l'interface n'est pas redessinée.
	if _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if _nadir:
		_nadir.active = visible and _display.current_tab == TabletDisplay.Tab.PHOTO


## Onglet affiché par l'interface (TabletDisplay.Tab), même tablette rangée ; -1 avant sa construction.
func current_tab() -> int:
	return _display.current_tab if _display else -1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tablet") and not event.is_echo() and not StationCamera.is_typing(self) \
			and not ScreenSeatConsole.any_seated(get_tree()):
		get_viewport().set_input_as_handled()
		_set_wanted(not _wanted)


## Poste de pilotage, radio, télévision (ScreenSeatConsole) : la tablette se range quand on s'y installe.
func _connect_seats() -> void:
	for seat in get_tree().get_nodes_in_group(ScreenSeatConsole.GROUP):
		seat.seated_changed.connect(func(seated: bool) -> void:
			if seated:
				_set_wanted(false))


func is_out() -> bool:
	return _wanted


## Vrai si la tablette (affichée, en mouvement compris) est sous le point screen_pos de la vue : coque entière, pas
## seulement l'écran. Elle est alors seule à recevoir la souris : pas de bulle ni de clic pour ce qui est derrière.
func covers(screen_pos: Vector2) -> bool:
	if not visible or _screen == null or _body == null or _camera == null:
		return false
	var uv := _screen.plane_uv_at(_camera, screen_pos)
	if uv == StationScreen.NONE:
		return false
	var aabb := _body.get_aabb()
	var rect := Rect2(_screen.uv_of(_body.global_transform * aabb.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8):
		rect = rect.expand(_screen.uv_of(_body.global_transform * aabb.get_endpoint(i)))
	return rect.has_point(uv)


## Tablette de la scène sous le point screen_pos de la vue (voir covers) ; faux sans tablette.
static func covers_pointer(tree: SceneTree, screen_pos: Vector2) -> bool:
	var tablet := tree.get_first_node_in_group(GROUP) as Tablet
	return tablet != null and tablet.covers(screen_pos)


## Combinaison du sas portée : main gantée.
func _connect_suit() -> void:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	if station:
		station.suit_changed.connect(_set_gloved)
		_set_gloved(station.is_suit_worn())


## Main nue ou gantée (un modèle sans gant, ancien tablet.glb, garde la main nue).
func _set_gloved(gloved: bool) -> void:
	gloved = gloved and _model.find_child(GLOVED_HAND_NODES[0], true, false) != null
	for names: Array[String] in [BARE_HAND_NODES, GLOVED_HAND_NODES]:
		for node_name in names:
			var part := _model.find_child(node_name, true, false) as Node3D
			if part:
				part.visible = gloved == (names == GLOVED_HAND_NODES)


# Tablette sortie : la souris sur son écran est pour l'interface.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null or _viewport == null or not visible or _out < 1.0 or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		return
	if _input_forwarder.forward(mouse, _screen.uv_at(_camera, mouse.position)):
		get_viewport().set_input_as_handled()
	elif button and covers(mouse.position):
		# Clic sur la coque : rien derrière la tablette ne le reçoit.
		get_viewport().set_input_as_handled()


func _set_wanted(out: bool) -> void:
	if out == _wanted:
		return
	_wanted = out
	if not out and _input_forwarder:
		_input_forwarder.leave()
	if _tween:
		_tween.kill()
	visible = true
	# Progression linéaire : l'accélération et la décélération de la main sont dans _update_pose (une même courbe,
	# parcourue à l'envers pour ranger).
	_tween = create_tween()
	var target := 1.0 if out else 0.0
	_tween.tween_method(_set_out, _out, target, (ARRIVE_S if out else STOW_S) * absf(target - _out))
	if not out:
		_tween.tween_callback(func() -> void: visible = false)


func _set_out(value: float) -> void:
	_out = value
	_update_pose()


## Position dans le repère de la caméra : sortie (_out = 1) en bas à droite de la vue, face à l'œil ; rangée
## (_out = 0) sous la vue à droite, main baissée. Entre les deux, la boucle de la main (voir en tête).
func _update_pose() -> void:
	if _camera == null:
		return
	var half_tan := tan(deg_to_rad(_camera.fov) * 0.5)
	var distance := _height / (view_fill * 2.0 * half_tan)
	var view_height := 2.0 * distance * half_tan
	var view_width := view_height * get_viewport().get_visible_rect().size.aspect()
	var shown := Vector3((0.5 - right_margin) * view_width - _width * 0.5,
			(-0.5 + bottom_margin + view_fill * 0.5) * view_height, -distance)
	# Boucle : départ sous la vue à droite et plus près, montée sur le côté droit, léger dépassement vers la gauche
	# et le haut, puis la place. Décélération de la main à l'arrivée (cubique).
	var start := shown + Vector3(0.45 * view_width, -0.75 * view_height, 0.25 * distance)
	var side := shown + Vector3(0.4 * view_width, -0.05 * view_height, 0.1 * distance)
	var overshoot := shown + Vector3(-0.05 * view_width, 0.04 * view_height, 0.0)
	var progress := 1.0 - pow(1.0 - _out, 3.0)
	var position_now := _bezier(start, side, overshoot, shown, progress)
	# Écran (+Z du modèle) à moitié tourné vers l'œil à l'arrivée (tout à fait, en bord de vue, il paraissait de
	# biais : une tablette tenue sur le côté reste presque parallèle au visage) ; au départ, incliné et tourné vers la
	# droite.
	var final_basis := Basis(Quaternion.IDENTITY.slerp(Basis.looking_at(shown, Vector3.UP).get_rotation_quaternion(),
			FACING_SHARE))
	var start_basis := final_basis * Basis.from_euler(Vector3(deg_to_rad(START_PITCH_DEG), deg_to_rad(START_YAW_DEG),
			deg_to_rad(START_ROLL_DEG)))
	var rotation_now := Basis(start_basis.get_rotation_quaternion().slerp(final_basis.get_rotation_quaternion(),
			smoothstep(0.0, 0.85, _out)))
	# Respiration, à pleine sortie.
	var breath := Vector3(sin(_time * 0.9 + 1.0), sin(_time * 1.3), 0.0) * BREATH_M * _out
	var sway := Basis(Vector3.BACK, deg_to_rad(BREATH_DEG) * sin(_time * 0.7) * _out)
	# Retard sur la tête : rotation autour de l'œil.
	var lag := Basis(Vector3.UP, _lag.x) * Basis(Vector3.RIGHT, _lag.y)
	# Réduite de NEAR_SCALE et rapprochée de l'œil d'autant (homothétie de centre l'œil) : même image à l'écran, mais
	# à ~12 cm de l'œil, plus près que tout obstacle (sphère de collision de l'observateur : 0,3 m) ; à taille réelle
	# (~30 cm), les barreaux de la cupola passaient devant elle.
	transform = Transform3D(lag, Vector3.ZERO) * Transform3D((rotation_now * sway).scaled_local(Vector3.ONE * NEAR_SCALE),
			(position_now + breath) * NEAR_SCALE)


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## Galerie de la tablette : photos de PhotoArchive.
func _connect_archive() -> void:
	_display.archive = get_tree().get_first_node_in_group(PhotoArchive.GROUP) as PhotoArchive


## Photo satellite (bouton Photo) : capture de la vue au nadir (NadirCamera.capture_photo), enregistrée avec le point
## survolé, l'heure, l'altitude et son emprise au sol au moment du déclenchement (PhotoArchive).
func _take_photo() -> void:
	var archive := get_tree().get_first_node_in_group(PhotoArchive.GROUP) as PhotoArchive
	var orbit := get_node_or_null(orbit_path) as OrbitSimulation
	if archive == null or orbit == null or _nadir == null:
		return
	var point := orbit.get_subsatellite_point()
	var utc := orbit.get_utc_unix_s()
	var altitude := orbit.altitude_km
	var shot: Dictionary = await _nadir.capture_photo()
	if shot.is_empty():
		return
	archive.add(shot.image, shot.screen_image, point.x, point.y, utc, altitude, _nadir.footprint_km(altitude))
