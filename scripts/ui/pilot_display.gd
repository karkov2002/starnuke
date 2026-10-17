class_name PilotDisplay
extends Control
## Interface du grand écran du poste de pilotage, dessinée dans le SubViewport de PilotConsole
## (scripts/pilot_console.gd) : carte du monde en Mercator (OrbitalMap) à gauche ; à droite, l'orbite actuelle, puis
## la manœuvre : curseurs de l'inclinaison et de l'altitude visées (FlightComputer, trace fantôme), Δv, bouton
## « Annuler » (cible ramenée sur l'orbite actuelle), mode Auto / Manuel et commande de poussée (BurnControl :
## compte à rebours du nœud, bouton BURN, jauge). Construite en code ; taille : celle du SubViewport (proportions de
## la dalle).

const MARGIN := 24.0
const FONT_SIZE := 30
const COLOR_TEXT := Color(0.85, 1.0, 0.88)
const COLOR_DIM := Color(0.45, 0.6, 0.5)
const COLOR_FRAME := Color(0.35, 0.5, 0.4)
const COLOR_GHOST := OrbitalMap.COLOR_GHOST

var orbit: OrbitSimulation
var flight_computer: FlightComputer

var _map: OrbitalMap
var _values := {}
var _inclination_slider: HSlider
var _altitude_slider: HSlider
var _target_inclination: Label
var _target_altitude: Label
var _delta_v: Label
var _mode_buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var map_height := size.y - 2.0 * MARGIN
	_map = OrbitalMap.new()
	_map.orbit = orbit
	_map.flight_computer = flight_computer
	_map.position = Vector2(MARGIN, MARGIN)
	_map.size = Vector2(map_height * OrbitalMap.ASPECT, map_height)
	add_child(_map)
	var frame := Panel.new()
	frame.position = _map.position
	frame.size = _map.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _frame_style())
	add_child(frame)

	var column := VBoxContainer.new()
	column.position = Vector2(_map.position.x + _map.size.x + MARGIN, MARGIN)
	column.size = Vector2(size.x - column.position.x - MARGIN, map_height)
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_make_label("PILOT_TITLE", COLOR_TEXT, 40))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
	for key: String in ["PILOT_UTC", "PILOT_POSITION", "PILOT_ALTITUDE", "PILOT_INCLINATION", "PILOT_PERIOD", "PILOT_SPEED"]:
		grid.add_child(_make_label(key, COLOR_DIM))
		_values[key] = _make_value(COLOR_TEXT)
		grid.add_child(_values[key])

	column.add_child(HSeparator.new())
	column.add_child(_make_label("PILOT_MANEUVER", COLOR_GHOST, 34))
	_target_inclination = _add_target_row(column, "PILOT_TARGET_INCLINATION")
	_inclination_slider = _make_slider(0.0, OrbitSimulation.MAX_INCLINATION_DEG, 0.1)
	column.add_child(_inclination_slider)
	_target_altitude = _add_target_row(column, "PILOT_TARGET_ALTITUDE")
	_altitude_slider = _make_slider(FlightComputer.MIN_TARGET_ALTITUDE_KM, FlightComputer.MAX_TARGET_ALTITUDE_KM, 1.0)
	column.add_child(_altitude_slider)
	_inclination_slider.value_changed.connect(func(value: float) -> void:
		flight_computer.set_target(value, flight_computer.target_altitude_km))
	_altitude_slider.value_changed.connect(func(value: float) -> void:
		flight_computer.set_target(flight_computer.target_inclination_deg, value))

	var delta_row := HBoxContainer.new()
	column.add_child(delta_row)
	delta_row.add_child(_make_label("PILOT_DELTA_V", COLOR_DIM))
	_delta_v = _make_value(COLOR_TEXT)
	_delta_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delta_row.add_child(_delta_v)
	var cancel := Button.new()
	cancel.text = "PILOT_CANCEL"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: flight_computer.reset_target())
	delta_row.add_child(cancel)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	column.add_child(modes)
	var group := ButtonGroup.new()
	for entry: Array in [[FlightComputer.Mode.AUTO, "PILOT_MODE_AUTO"], [FlightComputer.Mode.MANUAL, "PILOT_MODE_MANUAL"]]:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: flight_computer.set_mode(entry[0]))
		button.set_meta(&"mode", entry[0])
		modes.add_child(button)
		_mode_buttons.append(button)

	var burn := BurnControl.new()
	burn.flight_computer = flight_computer
	burn.large = true
	column.add_child(burn)


func _process(_delta: float) -> void:
	if orbit == null or flight_computer == null:
		return
	var now := orbit.get_utc_datetime()
	var point := orbit.get_subsatellite_point()
	_values.PILOT_UTC.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
	_values.PILOT_POSITION.text = "%s  %s" % [_format_angle(point.x, "DIR_N", "DIR_S"), _format_angle(point.y, "DIR_E", "DIR_W")]
	_values.PILOT_ALTITUDE.text = "%d km" % roundi(orbit.altitude_km)
	_values.PILOT_INCLINATION.text = "%.1f°" % orbit.inclination_deg
	_values.PILOT_PERIOD.text = "%.1f min" % (orbit.get_period_s() / 60.0)
	_values.PILOT_SPEED.text = "%.2f km/s" % orbit.get_orbital_speed_km_s()

	_inclination_slider.set_value_no_signal(flight_computer.target_inclination_deg)
	_altitude_slider.set_value_no_signal(flight_computer.target_altitude_km)
	_target_inclination.text = "%.1f°" % flight_computer.target_inclination_deg
	_target_altitude.text = "%d km" % roundi(flight_computer.target_altitude_km)
	_delta_v.text = "%d m/s" % roundi(flight_computer.get_delta_v_km_s() * 1000.0) if flight_computer.has_plan() else "—"
	for button in _mode_buttons:
		button.set_pressed_no_signal(button.get_meta(&"mode") == flight_computer.mode)


## Ligne « nom … valeur » d'une cible ; renvoie le label de la valeur.
func _add_target_row(parent: Control, key: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := _make_label(key, COLOR_DIM)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := _make_value(COLOR_GHOST)
	row.add_child(value)
	return value


func _make_label(key: String, color: Color, font_size := 0) -> Label:
	var label := Label.new()
	label.text = key
	label.add_theme_color_override("font_color", color)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


## Label de valeur composée à chaque image : pas de traduction automatique.
func _make_value(color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	return label


func _make_slider(min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.y = 44.0
	return slider


## « 42.0° N » : positive et negative sont les clés de langue des directions (DIR_N, DIR_S…).
func _format_angle(value: float, positive: String, negative: String) -> String:
	return "%.1f° %s" % [absf(value), tr(positive if value >= 0.0 else negative)]


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = COLOR_FRAME
	style.set_border_width_all(2)
	return style


## Thème de l'écran : gros caractères, curseurs et boutons verts lisibles de loin (la dalle fait 1,6 m).
func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = FONT_SIZE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.2, 0.14)
	track.set_corner_radius_all(4)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	result.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = COLOR_GHOST.darkened(0.3)
	result.set_stylebox("grabber_area", "HSlider", filled)
	result.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var grabber := _disc_texture(30, COLOR_GHOST)
	result.set_icon("grabber", "HSlider", grabber)
	result.set_icon("grabber_highlight", "HSlider", _disc_texture(30, Color.WHITE))
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {"normal": Color(0.08, 0.16, 0.1), "hover": Color(0.12, 0.26, 0.16),
				"pressed": Color(0.2, 0.4, 0.25), "disabled": Color(0.06, 0.06, 0.06)}[state]
		box.border_color = COLOR_FRAME
		box.set_border_width_all(2)
		box.set_corner_radius_all(6)
		box.set_content_margin_all(10)
		result.set_stylebox(state, "Button", box)
	result.set_color("font_color", "Button", COLOR_TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("separator", "HSeparator", COLOR_FRAME)
	return result


static func _disc_texture(diameter: int, color: Color) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var center := (diameter - 1) * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x - center, y - center).length()
			image.set_pixel(x, y, Color(color, clampf(center + 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
