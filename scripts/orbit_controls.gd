extends CanvasLayer
## Panneau de contrôle de l'orbite, en bas au centre de l'écran : altitude (200–800 km), inclinaison (0–70°),
## vitesse du temps (pause, x1 à x16) et redémarrage au-dessus de l'Europe à midi / minuit. Les curseurs pilotent
## le nœud Orbit en direct ; hors manipulation,
## ils affichent les valeurs réellement appliquées (l'inclinaison est bornée par la latitude courante).

const TIME_SCALES := [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]

@export var orbit_path: NodePath = ^"../Orbit"

var _orbit: OrbitSimulation
var _dragging_altitude := false
var _dragging_inclination := false
var _time_buttons: Array[Button] = []

@onready var _panel: PanelContainer = $Panel
@onready var _altitude_label: Label = $Panel/Row/Altitude/AltitudeLabel
@onready var _altitude_slider: HSlider = $Panel/Row/Altitude/AltitudeSlider
@onready var _inclination_label: Label = $Panel/Row/Inclination/InclinationLabel
@onready var _inclination_slider: HSlider = $Panel/Row/Inclination/InclinationSlider
@onready var _time_label: Label = $Panel/Row/Time/TimeLabel
@onready var _time_buttons_box: HBoxContainer = $Panel/Row/Time/TimeButtons


func _ready() -> void:
	_orbit = get_node(orbit_path) as OrbitSimulation
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	$Panel/Row.add_theme_constant_override("separation", 32)
	# Largeurs fixes : le panneau ne doit pas changer de taille quand les valeurs affichées changent.
	for column: Control in [$Panel/Row/Altitude, $Panel/Row/Inclination]:
		column.custom_minimum_size.x = 330.0
	for label: Label in [_altitude_label, _inclination_label, _time_label]:
		label.clip_text = true
	_time_buttons_box.add_theme_constant_override("separation", 4)

	_altitude_slider.min_value = OrbitSimulation.MIN_ALTITUDE_KM
	_altitude_slider.max_value = OrbitSimulation.MAX_ALTITUDE_KM
	_altitude_slider.value_changed.connect(func(value: float) -> void: _orbit.altitude_km = value)
	_altitude_slider.drag_started.connect(func() -> void: _dragging_altitude = true)
	_altitude_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging_altitude = false)

	_inclination_slider.min_value = 0.0
	_inclination_slider.max_value = OrbitSimulation.MAX_INCLINATION_DEG
	_inclination_slider.value_changed.connect(func(value: float) -> void: _orbit.inclination_deg = value)
	_inclination_slider.drag_started.connect(func() -> void: _dragging_inclination = true)
	_inclination_slider.drag_ended.connect(func(_changed: bool) -> void: _dragging_inclination = false)

	$Panel/Row/Restart/RestartButtons.add_theme_constant_override("separation", 4)
	$Panel/Row/Restart/RestartButtons/DayButton.pressed.connect(func() -> void: _orbit.restart(12.0))
	$Panel/Row/Restart/RestartButtons/NightButton.pressed.connect(func() -> void: _orbit.restart(0.0))

	var group := ButtonGroup.new()
	for factor: float in TIME_SCALES:
		var button := Button.new()
		button.text = "Pause" if factor == 0.0 else "x%d" % int(factor)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(52, 0)
		button.pressed.connect(func() -> void: _orbit.time_scale = factor)
		_time_buttons_box.add_child(button)
		_time_buttons.append(button)


func _process(_delta: float) -> void:
	if not _dragging_altitude:
		_altitude_slider.set_value_no_signal(_orbit.altitude_km)
	if not _dragging_inclination:
		_inclination_slider.set_value_no_signal(_orbit.inclination_deg)
	for i in TIME_SCALES.size():
		_time_buttons[i].set_pressed_no_signal(is_equal_approx(_orbit.time_scale, TIME_SCALES[i]))

	var point: Vector2 = _orbit.get_subsatellite_point()
	_altitude_label.text = "Altitude : %d km  ·  période %.1f min" % [roundi(_orbit.altitude_km), _orbit.get_period_s() / 60.0]
	_inclination_label.text = "Inclinaison : %.1f°  ·  %s %s" % [_orbit.inclination_deg,
			_format_angle(point.x, "N", "S"), _format_angle(point.y, "E", "O")]
	var t := int(_orbit.sim_time_s)
	@warning_ignore("integer_division")
	_time_label.text = "Temps  ·  T+%02d:%02d:%02d" % [t / 3600, t / 60 % 60, t % 60]


func _format_angle(value: float, positive: String, negative: String) -> String:
	return "%.1f° %s" % [absf(value), positive if value >= 0.0 else negative]


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.72)
	style.border_color = Color(0.55, 0.7, 0.9, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	return style
