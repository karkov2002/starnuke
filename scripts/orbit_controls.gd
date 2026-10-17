extends CanvasLayer
## Panneau de contrôle de la cupola, en bas au centre de l'écran : date et heure UTC (champ date, ±1 jour, curseur
## d'heure), vitesse du temps (pause, x1 à x16), redémarrage au-dessus de l'Europe à midi / minuit, commande de
## poussée de la manœuvre prévue au poste de pilotage (BurnControl : compte à rebours du nœud, BURN, jauge) et tir
## (nuke/launch_control.gd). L'orbite ne s'y règle plus : elle se pilote au poste de pilotage (PilotConsole) ;
## altitude et inclinaison directes restent dans le panneau de debug (F4, outil de développement).

## Le panneau (et le réticule de tir) n'apparaît que quand l'observateur est dans la cupola (Station.is_in_cupola) :
## fondu d'apparition et de disparition en FADE_S.

const TIME_SCALES := [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]
const DAY_S := 86400.0
const FADE_S := 0.5

@export var orbit_path: NodePath = ^"../Orbit"
@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var flight_computer_path: NodePath = ^"../FlightComputer"

var _orbit: OrbitSimulation
var _dragging_hour := false
var _time_buttons: Array[Button] = []
var _date_edit: LineEdit
var _hour_slider: HSlider
var _station: Station
var _in_cupola := true
var _fade: Tween

@onready var _panel: PanelContainer = $Panel
@onready var _time_label: Label = $Panel/Row/Time/TimeLabel
@onready var _time_buttons_box: HBoxContainer = $Panel/Row/Time/TimeButtons


func _ready() -> void:
	_orbit = get_node(orbit_path) as OrbitSimulation
	_station = get_node_or_null(station_path) as Station
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	$Panel/Row.add_theme_constant_override("separation", 32)
	# Largeur fixe : le panneau ne doit pas changer de taille quand les valeurs affichées changent.
	$Panel/Row/Time.custom_minimum_size.x = 380.0
	_time_label.clip_text = true
	# Texte composé à chaque image (tr() + format) : pas de traduction automatique.
	_time_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_time_buttons_box.add_theme_constant_override("separation", 4)

	$Panel/Row/Restart/RestartButtons.add_theme_constant_override("separation", 4)
	$Panel/Row/Restart/RestartButtons/DayButton.pressed.connect(func() -> void: _orbit.restart(12.0))
	$Panel/Row/Restart/RestartButtons/NightButton.pressed.connect(func() -> void: _orbit.restart(0.0))

	_build_date_row()

	var computer := get_node_or_null(flight_computer_path) as FlightComputer
	if computer:
		var burn := BurnControl.new()
		burn.flight_computer = computer
		burn.custom_minimum_size.x = 250.0
		$Panel/Row.add_child(burn)
		$Panel/Row.move_child(burn, $Panel/Row/Restart.get_index() + 1)

	var group := ButtonGroup.new()
	for factor: float in TIME_SCALES:
		var button := Button.new()
		button.text = "HUD_PAUSE" if factor == 0.0 else "x%d" % int(factor)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(52, 0)
		button.pressed.connect(func() -> void: _orbit.time_scale = factor)
		_time_buttons_box.add_child(button)
		_time_buttons.append(button)


func _process(_delta: float) -> void:
	_update_visibility()
	for i in TIME_SCALES.size():
		_time_buttons[i].set_pressed_no_signal(is_equal_approx(_orbit.time_scale, TIME_SCALES[i]))

	var point: Vector2 = _orbit.get_subsatellite_point()

	var now := _orbit.get_utc_datetime()
	var date := tr("HUD_DATE").format({"day": "%02d" % now.day, "month": "%02d" % now.month, "year": now.year})
	_time_label.text = tr("HUD_TIME").format({"date": date,
			"time": "%02d:%02d:%02d" % [now.hour, now.minute, now.second],
			"solar": _format_hour(_orbit.get_local_solar_hour(point.y))})
	if not _date_edit.has_focus():
		_date_edit.text = "%04d-%02d-%02d" % [now.year, now.month, now.day]
	if not _dragging_hour:
		_hour_slider.set_value_no_signal((_orbit.get_utc_unix_s() - _day_start_unix()) / 3600.0)


## Panneau et réticule visibles seulement dans la cupola, avec un fondu (masqués : plus de clics ni de tir).
func _update_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	if _station == null or camera == null:
		return
	var inside := _station.is_in_cupola(camera.global_position)
	if inside == _in_cupola:
		return
	_in_cupola = inside
	if _fade:
		_fade.kill()
	var targets: Array[CanvasItem] = [_panel, $AimReticle]
	_fade = create_tween().set_parallel()
	for item in targets:
		if inside:
			item.visible = true
		_fade.tween_property(item, "modulate:a", 1.0 if inside else 0.0, FADE_S)
	if not inside:
		_fade.chain().tween_callback(func() -> void:
			for item in targets:
				item.visible = false)
	if not inside and _date_edit.has_focus():
		_date_edit.release_focus()


# Ligne date / heure (UTC) : champ date (AAAA-MM-JJ, validé par Entrée), boutons −1 / +1 jour, curseur de l'heure
# du jour. Changer la date ou l'heure laisse la station au-dessus du même point (voir Orbit.set_utc_unix_s).
func _build_date_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	$Panel/Row/Time.add_child(row)
	$Panel/Row/Time.move_child(row, _time_label.get_index() + 1)

	var previous := _make_small_button("HUD_DAY_BACK", func() -> void: _shift_time(-DAY_S))
	_date_edit = LineEdit.new()
	_date_edit.custom_minimum_size.x = 112.0
	_date_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_edit.max_length = 10
	_date_edit.focus_mode = Control.FOCUS_CLICK
	_date_edit.tooltip_text = "HUD_DATE_TOOLTIP"
	_date_edit.text_submitted.connect(_on_date_submitted)
	var next := _make_small_button("HUD_DAY_FORWARD", func() -> void: _shift_time(DAY_S))

	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0.0
	_hour_slider.max_value = 24.0
	_hour_slider.step = 1.0 / 60.0
	_hour_slider.focus_mode = Control.FOCUS_NONE
	_hour_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hour_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hour_slider.tooltip_text = "HUD_HOUR_TOOLTIP"
	_hour_slider.value_changed.connect(_on_hour_changed)
	_hour_slider.drag_started.connect(func() -> void: _dragging_hour = true)
	_hour_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging_hour = false)

	for control: Control in [previous, _date_edit, next, _hour_slider]:
		row.add_child(control)


func _make_small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.x = 44.0
	button.pressed.connect(action)
	return button


func _shift_time(seconds: float) -> void:
	_orbit.set_utc_unix_s(_orbit.get_utc_unix_s() + seconds)


func _day_start_unix() -> float:
	return floorf(_orbit.get_utc_unix_s() / DAY_S) * DAY_S


func _on_hour_changed(hour: float) -> void:
	_orbit.set_utc_unix_s(_day_start_unix() + minf(hour * 3600.0, DAY_S - 1.0))


func _on_date_submitted(text: String) -> void:
	_date_edit.release_focus()
	var date := text.strip_edges()
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(date) == null:
		return
	var day := float(Time.get_unix_time_from_datetime_string(date + "T00:00:00"))
	# Rejette les dates impossibles (ex. 2035-02-30), que Time accepte en les décalant.
	if Time.get_date_string_from_unix_time(int(day)) != date:
		return
	_orbit.set_utc_unix_s(day + _orbit.get_utc_unix_s() - _day_start_unix())


func _format_hour(hour: float) -> String:
	var minutes := int(hour * 60.0) % 1440
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.72)
	style.border_color = Color(0.55, 0.7, 0.9, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	return style
