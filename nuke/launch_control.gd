class_name LaunchControl
extends HBoxContainer
## Colonne « missile » du panneau de contrôle : à gauche les 48 tubes de lancement (SiloPanel) et, en dessous, le choix
## de la puissance ; à droite le gros bouton rouge de tir.
##
## Tir : on choisit un tube (vert) puis on appuie sur le bouton rouge. Le point visé (centre de la vue, cf.
## NukeLauncher.get_aim) et la puissance sont figés à l'appui ; le missile du tube sort par l'animation de lancement
## (Station.launch_missile), le tube passe au gris (vide). À la fin de l'animation (Station.missile_released), le
## missile vole vers le point visé (MissileFlight) et l'explosion a lieu à son arrivée. Durée du vol (temps de jeu) :
## proportionnelle à la distance de la cible, de flight_time_range.x quand on vise le nadir (distance = altitude) à
## flight_time_range.y quand on vise l'horizon (√((R + h)² − R²), ~2 290 km à 400 km). Un chronomètre par missile
## (ImpactTimers) décompte jusqu'à l'impact.
## Rien ne se passe sans tube choisi, ni si la vue ne vise pas la Terre (le missile reste dans son tube). 48 missiles en
## tout, un par tube : un tube vide ne se recharge pas.

@export var default_yield_kt := 1000.0
## Durée du vol (s, temps de jeu) : visée au nadir, visée à l'horizon (règle de jeu : plus rapide que la réalité, où
## une frappe depuis l'orbite prend plusieurs minutes, pour garder la tension d'une attente de torpille).
@export var flight_time_range := Vector2(20.0, 120.0)

var _yield_kt := 1000.0
var _silos: SiloPanel
var _station: Station
## Tube choisi (vert) : trappe ouverte, gyrophare allumé.
var _armed := SiloPanel.NONE
## Vector2i(silo, tube) -> {latitude, longitude, yield_kt} : missiles lancés, en attente de leur sortie de la station.
var _pending := {}
var _timers: ImpactTimers


func _ready() -> void:
	_yield_kt = default_yield_kt
	_timers = ImpactTimers.new()
	_timers.name = "ImpactTimers"
	_add_timers.call_deferred()
	add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	_silos = SiloPanel.new()
	_silos.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_silos)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	left.add_child(row)
	var group := ButtonGroup.new()
	for kt: float in NukeLauncher.YIELDS_KT:
		var choice := Button.new()
		choice.text = NukeScaling.format_yield(kt)
		choice.toggle_mode = true
		choice.button_group = group
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size.x = 56.0
		choice.button_pressed = is_equal_approx(kt, _yield_kt)
		choice.pressed.connect(func() -> void: _yield_kt = kt)
		row.add_child(choice)

	var button := BigRedButton.new()
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = "HUD_LAUNCH_TOOLTIP"
	button.pressed.connect(_on_fire)
	add_child(button)

	# La station peut être prête après ce panneau (ordre de l'arbre) : construction différée.
	_connect_station.call_deferred()


## Chronomètres en bas à droite de l'écran, au-dessus du panneau, dans la couche d'interface du panneau.
func _add_timers() -> void:
	var layer: Node = get_parent()
	while layer and not layer is CanvasLayer:
		layer = layer.get_parent()
	(layer if layer else get_tree().current_scene).add_child(_timers)
	_timers.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_timers.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timers.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_timers.offset_right = -60.0
	_timers.offset_bottom = -180.0


## Durée du vol (s, temps de jeu) vers un point de la scène, proportionnelle à sa distance (du nadir à l'horizon).
func _flight_time(target_scene: Vector3) -> float:
	var camera := get_viewport().get_camera_3d()
	var orbit := NukeClock.orbit
	if camera == null or orbit == null:
		return flight_time_range.x
	var distance_km := camera.global_position.distance_to(target_scene) / OrbitSimulation.SCENE_UNITS_PER_KM
	var altitude := orbit.altitude_km
	var radius := OrbitSimulation.EARTH_RADIUS_KM
	var horizon := sqrt((radius + altitude) * (radius + altitude) - radius * radius)
	var share := clampf(inverse_lerp(altitude, horizon, distance_km), 0.0, 1.0)
	return lerpf(flight_time_range.x, flight_time_range.y, share)


func _connect_station() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return
	_silos.setup(_station)
	_silos.selection_changed.connect(_on_selection_changed)
	_station.missile_released.connect(_on_missile_released)


## Tube choisi : sa trappe s'ouvre (animation Blender) et son gyrophare clignote ; le tube choisi auparavant (s'il n'a
## pas tiré) referme sa trappe et éteint son gyrophare.
func _on_selection_changed(key: Vector2i) -> void:
	if _armed != SiloPanel.NONE and not _pending.has(_armed):
		_station.close_silo_door(_armed.x, _armed.y)
		_station.set_silo_beacon(_armed.x, _armed.y, false)
	_armed = key
	if key != SiloPanel.NONE:
		_station.open_silo_door(key.x, key.y)
		_station.set_silo_beacon(key.x, key.y, true)


func _on_fire() -> void:
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if launcher:
		fire_tube(_silos.selected, launcher.get_aim(), _yield_kt)


## Tire le missile du tube key sur le point aim ({local, latitude, longitude}, cf. NukeLauncher.get_aim et aim_at)
## avec la puissance yield_kt. Faux (et rien ne se passe) sans tube, sans point visé, ou si le tube ne peut pas tirer.
## Aussi utilisé par le banc de mesure (tools/bench).
func fire_tube(key: Vector2i, aim: Dictionary, yield_kt: float) -> bool:
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if key == SiloPanel.NONE or aim.is_empty() or launcher == null or _station == null:
		return false
	if not _station.launch_missile(key.x, key.y):
		return false
	var flight_time := _flight_time(launcher.get_earth().global_transform * (aim.local as Vector3))
	var shot := {"latitude": aim.latitude, "longitude": aim.longitude, "local": aim.local, "yield_kt": yield_kt,
			"flight_time": flight_time}
	_pending[key] = shot
	_silos.mark_empty(key)
	# Chronomètre : animation de sortie (temps réel) puis vol (temps de jeu, MissileFlight.time_left).
	var fired_at := Time.get_ticks_msec() / 1000.0
	var handoff := _station.launch_handoff_s()
	_timers.add_timer(_silos.number_of(key), func() -> float:
		if shot.has("flight"):
			# Vol terminé : le nœud est libéré (tester avant toute affectation typée).
			if not is_instance_valid(shot.flight):
				return 0.0
			return (shot.flight as MissileFlight).time_left()
		return maxf(handoff - (Time.get_ticks_msec() / 1000.0 - fired_at), 0.0) + flight_time)
	return true


func _on_missile_released(silo: int, tube: int, missile: Node3D, velocity: Vector3) -> void:
	var key := Vector2i(silo, tube)
	# Le missile a quitté le tube : gyrophare éteint, trappe refermée (station furtive).
	_station.set_silo_beacon(silo, tube, false)
	_station.close_silo_door(silo, tube)
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if not _pending.has(key) or launcher == null:
		missile.queue_free()
		return
	var shot: Dictionary = _pending[key]
	_pending.erase(key)
	var flight := MissileFlight.new()
	flight.name = "MissileFlight_%d_%02d" % [silo, tube]
	flight.flight_time_s = shot.flight_time
	shot.flight = flight
	get_tree().current_scene.add_child(flight)
	flight.setup(missile, velocity, _station, launcher.get_earth(), shot.local, NukeScaling.DEFAULT_BURST_HEIGHT_KM)
	flight.arrived.connect(func() -> void: launcher.launch_at(shot.latitude, shot.longitude, shot.yield_kt))
