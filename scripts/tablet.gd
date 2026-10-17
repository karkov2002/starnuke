class_name Tablet
extends Node3D
## Tablette de l'observateur (nœud Observer/Camera/Tablet de scenes/orbit_view.tscn) : modèle Blender
## assets/tablet/tablet.glb (tools/blender/build_tablet.py), tenu en bas à droite de la vue, écran tourné vers l'œil,
## comme dans la main. Son écran (objet Ecran_Tablette, UV 0–1) affiche l'interface TabletDisplay, dessinée dans un
## SubViewport : date et heure, carte réduite, BURN, silos et tir.
## - Touche Tab (action tablet) : la main amène la tablette devant les yeux (ARRIVE_S) ou la range (STOW_S) ; rangée,
##   elle est masquée. Ignorée pendant la saisie d'un texte et au poste de pilotage (la tablette s'y range d'elle-même).
## - Mouvement de la main : la tablette arrive du bas à droite en décrivant une boucle (courbe de Bézier : elle monte
##   sur le côté, dépasse un peu sa place puis s'y pose), en se redressant (inclinée, tournée vers la droite au
##   départ) ; rangée par le chemin inverse. Sortie, elle respire légèrement (balancement lent de quelques
##   millimètres) et suit la tête avec un temps de retard (elle traîne un peu quand on tourne la vue, puis rattrape).
## - Sortie, les clics et mouvements de la souris sur son écran sont transmis à l'interface (rayon de la caméra par le
##   curseur, intersecté avec la dalle) ; ailleurs, la souris garde son rôle (clic droit : tourner la tête).
## Position : écran occupant view_fill de la hauteur de la vue (selon le champ de la caméra), son bord droit à
## right_margin du bord droit de la vue, son bord bas à bottom_margin du bas, tourné vers l'œil. Éclairée par les
## lampes intérieures (calque Station.INTERIOR_LAYER) comme le reste de l'habitacle.

const MODEL := preload("res://assets/tablet/tablet.glb")
const SCREEN_NODE := "Ecran_Tablette"
const BODY_NODE := "Tablette_Coque"
## Hauteur de l'image de l'interface (pixels) : proche de la taille affichée, pour garder un texte lisible.
const VIEWPORT_HEIGHT := 560
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
## Part de la hauteur de la vue occupée par la tablette sortie.
## (Le haut de la tablette reste sous le centre de la vue : le réticule de tir reste visible.)
@export_range(0.2, 0.9) var view_fill := 0.38
## Marge entre le bas de la tablette et le bas de la vue (part de la hauteur de la vue).
@export var bottom_margin := 0.05
## Marge entre le bord droit de la tablette et celui de la vue (part de la largeur de la vue).
@export var right_margin := 0.07
## Luminosité de l'écran (émission).
@export var screen_energy := 1.0

var _camera: Camera3D
var _model: Node3D
var _screen: MeshInstance3D
var _viewport: SubViewport
var _console: PilotConsole
## Dalle dans le repère du maillage de l'écran : coin haut gauche, côté vers la droite, côté vers le bas.
var _top_left := Vector3.ZERO
var _axis_u := Vector3.ZERO
var _axis_v := Vector3.ZERO
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
## Bouton gauche tenu après un clic sur l'écran : le relâchement lui est transmis même hors de l'écran.
var _pressing := false
var _last_uv := Vector2(0.5, 0.5)


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera:
		_previous_view = _camera.global_basis.orthonormalized()
	_console = get_node_or_null(pilot_console_path) as PilotConsole
	if _console:
		_console.seated_changed.connect(func(seated: bool) -> void:
			if seated:
				_set_wanted(false))
	_model = MODEL.instantiate()
	add_child(_model)
	for mesh_instance: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance.layers |= Station.INTERIOR_LAYER
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := _model.find_child(BODY_NODE, true, false) as MeshInstance3D
	if body:
		_height = body.get_aabb().size.y
		_width = body.get_aabb().size.x
	_screen = _model.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	if _screen == null or not _measure_screen():
		push_error("Tablet : écran %s introuvable dans %s" % [SCREEN_NODE, MODEL.resource_path])
		return
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = Vector2i(roundi(VIEWPORT_HEIGHT * _axis_u.length() / _axis_v.length()), VIEWPORT_HEIGHT)
	_viewport.disable_3d = true
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var display := TabletDisplay.new()
	display.size = Vector2(_viewport.size)
	display.orbit = get_node(orbit_path) as OrbitSimulation
	display.flight_computer = get_node(flight_computer_path) as FlightComputer
	_viewport.add_child(display)
	# Même shader que l'écran du poste de pilotage : émission brute (un StandardMaterial3D émet en nits avec les
	# unités de lumière physiques du projet, 1 000 par défaut : écran tout blanc).
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/pilot_screen.gdshader")
	material.set_shader_parameter("screen_texture", _viewport.get_texture())
	material.set_shader_parameter("top_left", _top_left)
	material.set_shader_parameter("axis_u", _axis_u)
	material.set_shader_parameter("axis_v", _axis_v)
	material.set_shader_parameter("energy", screen_energy)
	_screen.material_override = material
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"tablet") and not event.is_echo() and not StationCamera.is_typing(self) \
			and not (_console and _console.is_seated()):
		get_viewport().set_input_as_handled()
		_set_wanted(not _wanted)


func is_out() -> bool:
	return _wanted


# Tablette sortie : la souris sur son écran est pour l'interface.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null or _viewport == null or not visible or _out < 1.0 or Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		return
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		return
	var uv := _screen_uv(mouse.position)
	if uv == Vector2(-1, -1):
		if not (_pressing and button and not button.pressed):
			return
		uv = _last_uv
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_pressing = button.pressed
	_last_uv = uv
	get_viewport().set_input_as_handled()
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = uv * Vector2(_viewport.size)
	forwarded.global_position = forwarded.position
	_viewport.push_input(forwarded)


func _set_wanted(out: bool) -> void:
	if out == _wanted:
		return
	_wanted = out
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
	transform = Transform3D(lag, Vector3.ZERO) * Transform3D(rotation_now * sway, position_now + breath)


static func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t


## Point de l'écran (0–1) sous le curseur, (-1, -1) hors de l'écran.
func _screen_uv(mouse_position: Vector2) -> Vector2:
	var origin := _camera.project_ray_origin(mouse_position)
	var direction := _camera.project_ray_normal(mouse_position)
	var to_world := _screen.global_transform
	var top_left := to_world * _top_left
	var u := to_world.basis * _axis_u
	var v := to_world.basis * _axis_v
	var normal := u.cross(v).normalized()
	var facing := direction.dot(normal)
	if absf(facing) < 1e-4:
		return Vector2(-1, -1)
	var distance := (top_left - origin).dot(normal) / facing
	if distance <= 0.0:
		return Vector2(-1, -1)
	var offset := origin + direction * distance - top_left
	var uv := Vector2(offset.dot(u) / u.length_squared(), offset.dot(v) / v.length_squared())
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv


## Rectangle de la dalle d'après ses UV : coin (0, 0) en haut à gauche, (1, 0) en haut à droite, (0, 1) en bas à
## gauche.
func _measure_screen() -> bool:
	var arrays := _screen.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var corners := {}
	for k in vertices.size():
		corners[Vector2i(roundi(uvs[k].x), roundi(uvs[k].y))] = vertices[k]
	if not (corners.has(Vector2i(0, 0)) and corners.has(Vector2i(1, 0)) and corners.has(Vector2i(0, 1))):
		return false
	_top_left = corners[Vector2i(0, 0)]
	_axis_u = corners[Vector2i(1, 0)] - _top_left
	_axis_v = corners[Vector2i(0, 1)] - _top_left
	return true
