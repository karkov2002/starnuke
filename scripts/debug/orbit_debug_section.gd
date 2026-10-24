class_name OrbitDebugSection
extends VBoxContainer
## Section « orbite et temps » du panneau de debug (scripts/debug/debug_panel.gd), partie en cours seulement :
## - altitude (200–800 km) et inclinaison (0–80°) appliquées directement au nœud Orbit, au point courant, sans
##   manœuvre (outil de développement : en jeu, l'orbite se pilote au poste de pilotage) ; sans manœuvre prévue, la
##   cible de l'ordinateur de vol suit (pas d'orbite fantôme affichée). L'inclinaison est bornée par
##   la latitude courante ;
## - date et heure UTC (champ date AAAA-MM-JJ validé par Entrée, −1 j / +1 j, curseur de l'heure du jour : la station
##   reste au-dessus du même point, Orbit.set_utc_unix_s) et redémarrage au-dessus de l'Europe de jour / de nuit
##   (Orbit.restart).

const DAY_S := 86400.0

var _orbit_label: Label
var _altitude: HSlider
var _inclination: HSlider
var _date_edit: LineEdit
var _hour: HSlider


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_orbit_label = Label.new()
	add_child(_orbit_label)
	_altitude = DebugUi.slider(OrbitSimulation.MIN_ALTITUDE_KM, OrbitSimulation.MAX_ALTITUDE_KM, 1.0,
			func(value: float) -> void: _set_orbit(func(orbit: OrbitSimulation) -> void: orbit.altitude_km = value))
	add_child(_altitude)
	_inclination = DebugUi.slider(0.0, OrbitSimulation.MAX_INCLINATION_DEG, 0.1,
			func(value: float) -> void: _set_orbit(func(orbit: OrbitSimulation) -> void: orbit.inclination_deg = value))
	add_child(_inclination)

	var row := DebugUi.row(self, 4)
	row.add_child(DebugUi.button("−1 j", func() -> void: _shift_time(-DAY_S)))
	_date_edit = LineEdit.new()
	_date_edit.custom_minimum_size.x = 112.0
	_date_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_edit.max_length = 10
	_date_edit.tooltip_text = "Date UTC (AAAA-MM-JJ), valider par Entrée"
	_date_edit.text_submitted.connect(_on_date_submitted)
	row.add_child(_date_edit)
	row.add_child(DebugUi.button("+1 j", func() -> void: _shift_time(DAY_S)))
	var label := Label.new()
	label.text = "Heure UTC"
	row.add_child(label)
	_hour = DebugUi.slider(0.0, 24.0, 1.0 / 60.0, func(value: float) -> void:
		var orbit := _get_orbit()
		orbit.set_utc_unix_s(_day_start_unix(orbit) + minf(value * 3600.0, DAY_S - 1.0)))
	add_child(_hour)
	var restart := DebugUi.row(self)
	var title := Label.new()
	title.text = "Redémarrer (Europe)"
	restart.add_child(title)
	restart.add_child(DebugUi.button("De jour", func() -> void: _get_orbit().restart(12.0)))
	restart.add_child(DebugUi.button("De nuit", func() -> void: _get_orbit().restart(0.0)))


func _process(_delta: float) -> void:
	var orbit := _get_orbit()
	if orbit == null:
		return
	_orbit_label.text = "Orbite : altitude %d km · inclinaison %.1f°" % [roundi(orbit.altitude_km), orbit.inclination_deg]
	# Hors manipulation, les curseurs affichent les valeurs réellement appliquées.
	var hour := (orbit.get_utc_unix_s() - _day_start_unix(orbit)) / 3600.0
	for pair: Array in [[_altitude, orbit.altitude_km], [_inclination, orbit.inclination_deg], [_hour, hour]]:
		var slider: HSlider = pair[0]
		if not DebugUi.is_dragging(slider):
			slider.set_value_no_signal(pair[1])
	if not _date_edit.has_focus():
		var now := orbit.get_utc_datetime()
		_date_edit.text = "%04d-%02d-%02d" % [now.year, now.month, now.day]


func _shift_time(seconds: float) -> void:
	var orbit := _get_orbit()
	orbit.set_utc_unix_s(orbit.get_utc_unix_s() + seconds)


func _day_start_unix(orbit: OrbitSimulation) -> float:
	return floorf(orbit.get_utc_unix_s() / DAY_S) * DAY_S


func _on_date_submitted(text: String) -> void:
	_date_edit.release_focus()
	var date := text.strip_edges()
	if RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(date) == null:
		return
	var day := float(Time.get_unix_time_from_datetime_string(date + "T00:00:00"))
	# Rejette les dates impossibles (ex. 2035-02-30), que Time accepte en les décalant.
	if Time.get_date_string_from_unix_time(int(day)) != date:
		return
	var orbit := _get_orbit()
	orbit.set_utc_unix_s(day + orbit.get_utc_unix_s() - _day_start_unix(orbit))


func _get_orbit() -> OrbitSimulation:
	return get_tree().get_first_node_in_group(OrbitSimulation.GROUP) as OrbitSimulation


## Change l'orbite réelle (change : Callable(orbit)) ; sans manœuvre prévue, la cible de l'ordinateur de vol suit
## (sinon l'écart passait pour une manœuvre : orbite fantôme affichée).
func _set_orbit(change: Callable) -> void:
	var orbit := _get_orbit()
	if orbit == null:
		return
	var computer := get_tree().get_first_node_in_group(FlightComputer.GROUP) as FlightComputer
	var planned := computer != null and computer.has_plan()
	change.call(orbit)
	if computer and not planned:
		computer.reset_target()
