extends HBoxContainer
## Colonne « missile » du panneau de contrôle : à gauche les 48 tubes de lancement (SiloPanel) et, en dessous, le choix
## de la puissance ; à droite le gros bouton rouge de tir.
##
## Tir : on choisit un tube (vert) puis on appuie sur le bouton rouge. Le point visé (centre de la vue, cf.
## NukeLauncher.get_aim) et la puissance sont figés à l'appui ; le missile du tube sort par l'animation de lancement
## (Station.launch_missile), le tube passe au gris (vide), puis l'explosion a lieu flight_delay_s après que le missile
## a quitté la station (Station.missile_released). Rien ne se passe sans tube choisi, ni si la vue ne vise pas la
## Terre (le missile reste dans son tube). 48 missiles en tout, un par tube : un tube vide ne se recharge pas.

@export var default_yield_kt := 1000.0
## Délai entre la sortie du missile et l'explosion (s) : provisoire, en attendant une durée de vol réaliste.
@export var flight_delay_s := 10.0

var _yield_kt := 1000.0
var _silos: SiloPanel
var _station: Station
## Vector2i(silo, tube) -> {latitude, longitude, yield_kt} : missiles lancés, en attente de leur sortie de la station.
var _pending := {}


func _ready() -> void:
	_yield_kt = default_yield_kt
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


func _connect_station() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return
	_silos.setup(_station)
	_station.missile_released.connect(_on_missile_released)


func _on_fire() -> void:
	var key := _silos.selected
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if key == SiloPanel.NONE or launcher == null or _station == null:
		return
	var aim := launcher.get_aim()
	if aim.is_empty() or not _station.launch_missile(key.x, key.y):
		return
	_pending[key] = {"latitude": aim.latitude, "longitude": aim.longitude, "yield_kt": _yield_kt}
	_silos.mark_empty(key)


func _on_missile_released(silo: int, tube: int, _world_transform: Transform3D) -> void:
	var key := Vector2i(silo, tube)
	if not _pending.has(key):
		return
	var shot: Dictionary = _pending[key]
	_pending.erase(key)
	await get_tree().create_timer(flight_delay_s).timeout
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if launcher:
		launcher.launch_at(shot.latitude, shot.longitude, shot.yield_kt)
