class_name TvConsole
extends Node
## Télévision du module Commande (nœud TvConsole de scenes/orbit_view.tscn) : l'écran SCREEN_NODE (réservé, retiré
## des écrans d'ambiance TechScreens) diffuse les chaînes d'information du monde entier (TvDisplay, dans un
## SubViewport).
## - Survol de l'écran à portée (reach_m) : bulle « Télévision » ; clic gauche : « vue TV » (la vue se cadre face à
##   l'écran, comme au poste de pilotage ; déplacements et tête suspendus) ; la souris est alors transmise à
##   l'interface (bouton « Chaînes », liste des pays). Clic droit : on quitte la vue ; la télévision reste sur la
##   chaîne choisie.
## - Chaînes : une par pays souverain (assets/tv/channels.csv : code ISO, nom de la chaîne, inventé, capitale).
##   Règle de jeu : un pays dont la capitale est touchée (au moins OFF_AIR_PSI de surpression d'une explosion) ne
##   diffuse plus : sa chaîne passe sur la mire « Pas de signal ». Les explosions persistent : l'état est recalculé à
##   chaque tir et toutes les CHECK_S secondes.
##   Règle de jeu : après une explosion, toutes les chaînes encore à l'antenne passent en édition spéciale « Alerte
##   info » pendant ALERT_HOURS heures de jeu (horloge UTC d'Orbit) après la dernière, puis reviennent à l'édition normale.
## Groupe ScreenSeat.GROUP (comme le poste de pilotage) : la tablette se range et les écoutilles ne se cliquent plus
## pendant la vue TV. Dalle, viewport, souris et bulles : StationScreen, ScreenInputForwarder, HoverBubble
## (scripts/screens/). L'image n'est rendue qu'à moins de RENDER_DISTANCE.

signal seated_changed(seated: bool)

const SCREEN_NODE := "Interactif_Ecran_03"
const CHANNELS_PATH := "res://assets/tv/channels.csv"
const VIEWPORT_HEIGHT := 640
const RENDER_DISTANCE := 12.0
const OFF_AIR_PSI := 5.0
const CHECK_S := 2.0
const ALERT_HOURS := 24.0
const DEFAULT_CHANNEL := "FRA"

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
@export var launcher_path: NodePath = ^"../NukeLauncher"
@export var orbit_path: NodePath = ^"../Orbit"
@export var reach_m := 2.5
@export_range(0.5, 1.0) var screen_fill := 0.9
@export var transition_s := 0.6
@export var screen_energy := 1.1

var _observer: Node3D
var _camera: Camera3D
var _station: Station
var _launcher: NukeLauncher
var _orbit: OrbitSimulation
## Heure UTC (s) de la dernière explosion (-INF : aucune) ; édition spéciale en cours.
var _last_detonation_unix := -INF
var _alert := false
var _screen: StationScreen
var _viewport: SubViewport
var _display: TvDisplay
var _input_forwarder: ScreenInputForwarder
var _bubble: HoverBubble
var _hud: Hud
var _seated := false
var _moving := false
var _mouse_position := Vector2.ZERO
var _return_position := Vector3.ZERO
var _return_rotation := Quaternion.IDENTITY
var _tween: Tween
## Code -> {name, lat, lon} ; codes hors d'antenne.
var _channels := {}
var _off_air := {}
var _check := 0.0


func _ready() -> void:
	add_to_group(ScreenSeat.GROUP)
	_observer = get_node(observer_path)
	_camera = _observer.get_node("Camera") as Camera3D
	_station = get_node(station_path) as Station
	_launcher = get_node_or_null(launcher_path) as NukeLauncher
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_load_channels()
	_screen = StationScreen.find(_station, SCREEN_NODE)
	if _screen == null:
		push_error("TvConsole : écran %s introuvable" % SCREEN_NODE)
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return
	_viewport = _screen.make_viewport(VIEWPORT_HEIGHT, true)
	add_child(_viewport)
	_input_forwarder = ScreenInputForwarder.new(_viewport)
	_display = TvDisplay.new()
	_display.name = "Display"
	_display.console = self
	_display.channel = DEFAULT_CHANNEL if _channels.has(DEFAULT_CHANNEL) else ""
	_display.size = Vector2(_viewport.size)
	_display.channel_selected.connect(func(code: String) -> void: _display.show_channel(code))
	_viewport.add_child(_display)
	_screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(), {"scan_depth": 0.05})
	_bubble = HoverBubble.new("TV_HOVER", "TV_EXIT_HINT")
	add_child(_bubble)
	_hud = get_tree().get_first_node_in_group(Hud.GROUP) as Hud
	if _launcher:
		_launcher.detonated.connect(func(effect: NukeEffect) -> void:
			# Explosion recréée (sauvegarde) : l'édition spéciale suit son heure réelle, pas le chargement.
			var at := effect.params.detonation_utc_s if effect.params and effect.params.detonation_utc_s >= 0.0 \
					else (_orbit.get_utc_unix_s() if _orbit else -INF)
			_last_detonation_unix = maxf(_last_detonation_unix, at)
			_update_off_air()
			# Nouveau tir : le bandeau repart tout de suite avec le nouveau bilan (après le calcul des pertes).
			if _display:
				_display.restart_ticker.call_deferred())
	_update_off_air()


func is_seated() -> bool:
	return _seated


func channel_codes() -> Array[String]:
	var codes: Array[String] = []
	codes.assign(_channels.keys())
	return codes


func channel_name(code: String) -> String:
	return String(_channels.get(code, {}).get("name", ""))


## Langue de diffusion de la chaîne (colonne lang de channels.csv).
func channel_lang(code: String) -> String:
	return String(_channels.get(code, {}).get("lang", "en"))


## Aperçu du bandeau d'une chaîne (mise au point, MCP / console).
func news_preview(code: String) -> String:
	var rng := RandomNumberGenerator.new()
	return news_text(code, rng)


## Texte du bandeau de la chaîne (TvNews) : explosions, ou infos ordinaires (bourse, météo de la capitale, sport) tant
## qu'il n'y en a eu aucune.
func news_text(code: String, rng: RandomNumberGenerator) -> String:
	var effects: Array[NukeEffect] = []
	if _launcher:
		effects = _launcher.get_effects()
	var off_air: Array[String] = []
	off_air.assign(_off_air.keys())
	return TvNews.compose(code, channel_lang(code),
			{"effects": effects, "tally": NukeTally.compute(effects), "off_air": off_air, "alert": _alert,
			"utc_unix": _orbit.get_utc_unix_s() if _orbit else 0.0, "channels": channel_codes(),
			"capital": Vector2(_channels.get(code, {}).get("lat", 0.0), _channels.get(code, {}).get("lon", 0.0))}, rng)


func is_alert() -> bool:
	return _alert


func is_off_air(code: String) -> bool:
	return _off_air.has(code)


func _process(delta: float) -> void:
	_screen.set_energy(screen_energy * (1.0 - _station.get_blackout()))
	_check += delta
	if _check >= CHECK_S:
		_update_off_air()
	var hovering := not _seated and not _moving and not ScreenSeat.any_seated(get_tree()) \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _screen.uv_at(_camera, _mouse_position, reach_m) != StationScreen.NONE
	_bubble.set_hover(hovering, _mouse_position)
	_bubble.set_exit_visible(_seated and not _moving)
	# Écran hors du module (loin) : l'image n'est plus rendue.
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and _screen.distance_to(camera.global_position) < RENDER_DISTANCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	_display.set_playing(near)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or _seated or _moving \
			or ScreenSeat.any_seated(get_tree()):
		return
	if _screen.uv_at(_camera, click.position, reach_m) != StationScreen.NONE:
		get_viewport().set_input_as_handled()
		_sit()


# En vue TV, la souris est prise par l'écran : clic droit pour quitter, le reste est transmis à l'interface.
func _input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	_mouse_position = mouse.position
	if not _seated and not _moving:
		return
	if _hud and _hud.is_over_controls(mouse.position):
		return
	get_viewport().set_input_as_handled()
	if _moving:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		_stand_up()
		return
	_input_forwarder.forward(mouse, _screen.uv_at(_camera, mouse.position))


# --- Chaînes --------------------------------------------------------------------------------------------------------

func _load_channels() -> void:
	var file := FileAccess.open(CHANNELS_PATH, FileAccess.READ)
	if file == null:
		push_error("TvConsole : %s illisible" % CHANNELS_PATH)
		return
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 5:
			continue
		_channels[row[0]] = {"name": row[1], "lat": float(row[2]), "lon": float(row[3]), "lang": row[4]}


## Pays dont la capitale est sous au moins OFF_AIR_PSI d'une explosion.
func _update_off_air() -> void:
	_check = 0.0
	if _launcher == null:
		return
	var off := {}
	for effect in _launcher.get_effects():
		var p := effect.params
		if p == null:
			continue
		var radius := NukeScaling.overpressure_range_km(p.yield_kt, OFF_AIR_PSI, p.burst_height_km)
		for code: String in _channels:
			var c: Dictionary = _channels[code]
			if GeoMath.distance_km(p.latitude_deg, p.longitude_deg, c.lat, c.lon) <= radius:
				off[code] = true
	var since := _orbit.get_utc_unix_s() - _last_detonation_unix if _orbit else INF
	var alert := since >= 0.0 and since < ALERT_HOURS * 3600.0
	if off.hash() != _off_air.hash() or alert != _alert:
		_alert = alert
		_off_air = off
		if _display:
			_display.refresh()


# --- Vue TV ---------------------------------------------------------------------------------------------------------

func _sit() -> void:
	_return_position = _observer.global_position
	_return_rotation = _camera.quaternion
	var pose := _screen.seat_pose(_camera, get_viewport().get_visible_rect().size.aspect(), screen_fill)
	var local_rotation := (_observer.global_basis.inverse() * (pose.look as Basis)).get_rotation_quaternion()
	_observer.process_mode = Node.PROCESS_MODE_DISABLED
	_seated = true
	_move_to(pose.eye, local_rotation, func() -> void: _moving = false)
	seated_changed.emit(true)


func _stand_up() -> void:
	_input_forwarder.leave()
	_seated = false
	_move_to(_return_position, _return_rotation, func() -> void:
		_moving = false
		_observer.process_mode = Node.PROCESS_MODE_INHERIT
		(_observer as CharacterBody3D).velocity = Vector3.ZERO)
	seated_changed.emit(false)


func _move_to(eye: Vector3, rotation: Quaternion, done: Callable) -> void:
	if _tween:
		_tween.kill()
	_moving = true
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_observer, "global_position", eye, transition_s)
	_tween.tween_property(_camera, "quaternion", rotation, transition_s)
	_tween.chain().tween_callback(done)
