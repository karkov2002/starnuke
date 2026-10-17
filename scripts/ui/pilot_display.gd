class_name PilotDisplay
extends Control
## Interface du grand écran du poste de pilotage, dessinée dans le SubViewport de PilotConsole
## (scripts/pilot_console.gd) : carte du monde en Mercator (OrbitalMap) à gauche, colonne d'informations à droite.
## Construite en code ; taille : celle du SubViewport (proportions de la dalle).

const MARGIN := 24.0
const FONT_SIZE := 30
const COLOR_TEXT := Color(0.85, 1.0, 0.88)
const COLOR_DIM := Color(0.45, 0.6, 0.5)
const COLOR_FRAME := Color(0.35, 0.5, 0.4)

var orbit: OrbitSimulation:
	set(value):
		orbit = value
		if _map:
			_map.orbit = value

var _map: OrbitalMap
var _values := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font_size = FONT_SIZE
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var map_height := size.y - 2.0 * MARGIN
	_map = OrbitalMap.new()
	_map.orbit = orbit
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
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var title := Label.new()
	title.text = "PILOT_TITLE"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)
	for key: String in ["PILOT_UTC", "PILOT_POSITION", "PILOT_ALTITUDE", "PILOT_INCLINATION", "PILOT_PERIOD", "PILOT_SPEED"]:
		var name_label := Label.new()
		name_label.text = key
		name_label.add_theme_color_override("font_color", COLOR_DIM)
		grid.add_child(name_label)
		var value := Label.new()
		# Valeurs composées à chaque image : pas de traduction automatique.
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		value.add_theme_color_override("font_color", COLOR_TEXT)
		grid.add_child(value)
		_values[key] = value


func _process(_delta: float) -> void:
	if orbit == null:
		return
	var now := orbit.get_utc_datetime()
	var point := orbit.get_subsatellite_point()
	_values.PILOT_UTC.text = "%02d:%02d:%02d" % [now.hour, now.minute, now.second]
	_values.PILOT_POSITION.text = "%s  %s" % [_format_angle(point.x, "DIR_N", "DIR_S"), _format_angle(point.y, "DIR_E", "DIR_W")]
	_values.PILOT_ALTITUDE.text = "%d km" % roundi(orbit.altitude_km)
	_values.PILOT_INCLINATION.text = "%.1f°" % orbit.inclination_deg
	_values.PILOT_PERIOD.text = "%.1f min" % (orbit.get_period_s() / 60.0)
	_values.PILOT_SPEED.text = "%.2f km/s" % orbit.get_orbital_speed_km_s()


## « 42.0° N » : positive et negative sont les clés de langue des directions (DIR_N, DIR_S…).
func _format_angle(value: float, positive: String, negative: String) -> String:
	return "%.1f° %s" % [absf(value), tr(positive if value >= 0.0 else negative)]


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = COLOR_FRAME
	style.set_border_width_all(2)
	return style
