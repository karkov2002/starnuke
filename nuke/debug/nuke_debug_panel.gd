extends CanvasLayer
## Panneau de debug des explosions (scène nuke/debug/nuke_debug.tscn), en haut à gauche :
## - puissance sur une échelle logarithmique (10 kt à 50 Mt), avec les tailles calculées par NukeScaling ;
## - latitude / longitude de la cible (« Point visé » recopie le centre de la vue), bouton « Tirer » ;
## - scrubber du temps physique de la dernière explosion : « Rejouer » fige toutes les explosions au temps du
##   curseur (time_override_s), sinon le curseur suit le temps réel de l'effet ;
## - « Effacer » supprime toutes les explosions ; « Marqueurs » affiche les marqueurs de taille (NukeEffect) ;
## - menu « Alerte » : niveau d'alerte de la station (couleur des luminaires intérieurs, Station.set_alert) ;
## - orbite (partie en cours seulement) : altitude (200–800 km) et inclinaison (0–80°) appliquées directement au
##   nœud Orbit, au point courant, sans manœuvre (outil de développement : en jeu, l'orbite se pilote au poste de
##   pilotage). L'inclinaison est bornée par la latitude courante ;
## - date et heure UTC (champ date AAAA-MM-JJ validé par Entrée, −1 j / +1 j, curseur de l'heure du jour : la station
##   reste au-dessus du même point, Orbit.set_utc_unix_s) et redémarrage au-dessus de l'Europe de jour / de nuit
##   (Orbit.restart).

const SCRUB_MAX_S := 432000.0
## Le curseur va jusqu'à 5 jours (incendies, qui s'étendent sur plusieurs jours) et n'est pas linéaire (t = SCRUB_MAX_S · v⁵) :
## les 10 premières minutes (montée du champignon) occupent le premier quart de sa course, les 6 premières heures la moitié.
const SCRUB_POWER := 5.0

var _yield_kt := 1000.0
var _yield_slider: HSlider
var _yield_label: Label
var _sizes_label: Label
var _lat: SpinBox
var _lon: SpinBox
var _scrub: HSlider
var _scrub_label: Label
var _replay: CheckBox
var _markers: CheckBox
var _last: NukeEffect
var _orbit_label: Label
var _altitude: HSlider
var _inclination: HSlider
var _date_edit: LineEdit
var _hour: HSlider


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 24.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360.0
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Debug explosions"
	box.add_child(title)

	_yield_label = Label.new()
	box.add_child(_yield_label)
	_yield_slider = HSlider.new()
	_yield_slider.min_value = log(NukeScaling.MIN_YIELD_KT) / log(10.0)
	_yield_slider.max_value = log(NukeScaling.MAX_YIELD_KT) / log(10.0)
	_yield_slider.step = 0.0
	_yield_slider.focus_mode = Control.FOCUS_NONE
	_yield_slider.value = log(_yield_kt) / log(10.0)
	_yield_slider.value_changed.connect(_on_yield_changed)
	box.add_child(_yield_slider)
	_sizes_label = Label.new()
	_sizes_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_sizes_label)

	var coords := HBoxContainer.new()
	coords.add_theme_constant_override("separation", 6)
	box.add_child(coords)
	_lat = _make_spin(-90.0, 90.0, 40.4, "Lat ")
	_lon = _make_spin(-180.0, 180.0, -3.7, "Lon ")
	coords.add_child(_lat)
	coords.add_child(_lon)
	coords.add_child(_make_button("Point visé", _on_use_aim))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	var fire := _make_button("Tirer", _on_fire)
	fire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(fire)
	actions.add_child(_make_button("Effacer", _on_clear))
	_markers = CheckBox.new()
	_markers.text = "Marqueurs"
	_markers.focus_mode = Control.FOCUS_NONE
	_markers.toggled.connect(_on_markers_toggled)
	actions.add_child(_markers)
	# Niveau d'alerte de la station (couleur des luminaires intérieurs, Station.set_alert).
	var alert := OptionButton.new()
	alert.focus_mode = Control.FOCUS_NONE
	for level in ["Alerte : aucune", "Alerte jaune", "Alerte orange", "Alerte rouge", "Plus de lumière"]:
		alert.add_item(level)
	alert.item_selected.connect(func(index: int) -> void:
		var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
		if station:
			station.set_alert(index as Station.Alert))
	actions.add_child(alert)

	var scrub_row := HBoxContainer.new()
	scrub_row.add_theme_constant_override("separation", 6)
	box.add_child(scrub_row)
	_replay = CheckBox.new()
	_replay.text = "Rejouer"
	_replay.focus_mode = Control.FOCUS_NONE
	_replay.toggled.connect(func(_on: bool) -> void: _apply_override())
	scrub_row.add_child(_replay)
	_scrub_label = Label.new()
	scrub_row.add_child(_scrub_label)
	_scrub = HSlider.new()
	_scrub.max_value = 1.0
	_scrub.step = 0.0
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.value_changed.connect(func(_v: float) -> void: _apply_override())
	_scrub.drag_started.connect(func() -> void: _replay.button_pressed = true)
	box.add_child(_scrub)

	if _get_orbit():
		box.add_child(HSeparator.new())
		_orbit_label = Label.new()
		box.add_child(_orbit_label)
		_altitude = _make_slider(OrbitSimulation.MIN_ALTITUDE_KM, OrbitSimulation.MAX_ALTITUDE_KM, 1.0,
				func(value: float) -> void: _get_orbit().altitude_km = value)
		box.add_child(_altitude)
		_inclination = _make_slider(0.0, OrbitSimulation.MAX_INCLINATION_DEG, 0.1,
				func(value: float) -> void: _get_orbit().inclination_deg = value)
		box.add_child(_inclination)
		_build_time_rows(box)

	_on_yield_changed(_yield_slider.value)


func _process(_delta: float) -> void:
	if not is_instance_valid(_last):
		_last = null
	if _last and not _replay.button_pressed:
		_scrub.set_value_no_signal(pow(minf(_last.get_time_s() / SCRUB_MAX_S, 1.0), 1.0 / SCRUB_POWER))
	_scrub_label.text = "t = %s" % _format_duration(_scrub_time()) if _last else "t = —"
	var orbit := _get_orbit()
	if orbit and _orbit_label:
		_orbit_label.text = "Orbite : altitude %d km · inclinaison %.1f°" % [roundi(orbit.altitude_km), orbit.inclination_deg]
		# Hors manipulation, les curseurs affichent les valeurs réellement appliquées.
		var hour := (orbit.get_utc_unix_s() - _day_start_unix(orbit)) / 3600.0
		for pair: Array in [[_altitude, orbit.altitude_km], [_inclination, orbit.inclination_deg], [_hour, hour]]:
			var slider: HSlider = pair[0]
			if not slider.has_meta(&"dragging"):
				slider.set_value_no_signal(pair[1])
		if not _date_edit.has_focus():
			var now := orbit.get_utc_datetime()
			_date_edit.text = "%04d-%02d-%02d" % [now.year, now.month, now.day]


# Date et heure UTC, redémarrage.
func _build_time_rows(box: VBoxContainer) -> void:
	var day_s := 86400.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	row.add_child(_make_button("−1 j", func() -> void: _shift_time(-day_s)))
	_date_edit = LineEdit.new()
	_date_edit.custom_minimum_size.x = 112.0
	_date_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_edit.max_length = 10
	_date_edit.tooltip_text = "Date UTC (AAAA-MM-JJ), valider par Entrée"
	_date_edit.text_submitted.connect(_on_date_submitted)
	row.add_child(_date_edit)
	row.add_child(_make_button("+1 j", func() -> void: _shift_time(day_s)))
	var label := Label.new()
	label.text = "Heure UTC"
	row.add_child(label)
	_hour = _make_slider(0.0, 24.0, 1.0 / 60.0, func(value: float) -> void:
		var orbit := _get_orbit()
		orbit.set_utc_unix_s(_day_start_unix(orbit) + minf(value * 3600.0, day_s - 1.0)))
	box.add_child(_hour)
	var restart := HBoxContainer.new()
	restart.add_theme_constant_override("separation", 6)
	box.add_child(restart)
	var title := Label.new()
	title.text = "Redémarrer (Europe)"
	restart.add_child(title)
	restart.add_child(_make_button("De jour", func() -> void: _get_orbit().restart(12.0)))
	restart.add_child(_make_button("De nuit", func() -> void: _get_orbit().restart(0.0)))


func _shift_time(seconds: float) -> void:
	var orbit := _get_orbit()
	orbit.set_utc_unix_s(orbit.get_utc_unix_s() + seconds)


func _day_start_unix(orbit: OrbitSimulation) -> float:
	return floorf(orbit.get_utc_unix_s() / 86400.0) * 86400.0


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


func _make_slider(min_value: float, max_value: float, step: float, action: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(action)
	slider.drag_started.connect(func() -> void: slider.set_meta(&"dragging", true))
	slider.drag_ended.connect(func(_changed: bool) -> void: slider.remove_meta(&"dragging"))
	return slider


func _launcher() -> NukeLauncher:
	return get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher


func _on_yield_changed(value: float) -> void:
	_yield_kt = pow(10.0, value)
	_yield_label.text = "Puissance : %s" % NukeScaling.format_yield(_yield_kt)
	_sizes_label.text = "Boule de feu %.2f km · choc %.1f km\nSommet du nuage %.1f km · chapeau %.1f km (rayons)" % [
			NukeScaling.fireball_radius_km(_yield_kt), NukeScaling.shock_radius_km(_yield_kt),
			NukeScaling.cloud_top_km(_yield_kt), NukeScaling.cloud_cap_radius_km(_yield_kt)]


func _on_use_aim() -> void:
	var launcher := _launcher()
	var aim := launcher.get_aim() if launcher else {}
	if not aim.is_empty():
		_lat.value = aim.latitude
		_lon.value = aim.longitude


func _on_fire() -> void:
	var launcher := _launcher()
	if launcher:
		_last = launcher.launch_at(_lat.value, _lon.value, _yield_kt)
		_last.show_debug_markers = _markers.button_pressed
		_replay.button_pressed = false


func _on_markers_toggled(on: bool) -> void:
	var launcher := _launcher()
	if launcher:
		for effect in launcher.get_effects():
			effect.show_debug_markers = on


func _on_clear() -> void:
	var launcher := _launcher()
	if launcher:
		launcher.clear_effects()
	_last = null


func _apply_override() -> void:
	var launcher := _launcher()
	if launcher == null:
		return
	for effect in launcher.get_effects():
		effect.time_override_s = _scrub_time() if _replay.button_pressed else -1.0


func _make_spin(min_value: float, max_value: float, value: float, prefix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 0.01
	spin.value = value
	spin.prefix = prefix
	spin.suffix = "°"
	spin.custom_minimum_size.x = 120.0
	return spin


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button


func _format_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%.1f s" % seconds
	var s := int(seconds)
	if seconds < 3600.0:
		return "%d min %02d s" % [floori(s / 60.0), s % 60]
	if seconds < 86400.0:
		return "%d h %02d min" % [floori(s / 3600.0), floori(s / 60.0) % 60]
	return "%d j %02d h" % [floori(s / 86400.0), floori(s / 3600.0) % 24]


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.05, 0.05, 0.75)
	style.border_color = Color(0.9, 0.4, 0.3, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	return style


func _scrub_time() -> float:
	return SCRUB_MAX_S * pow(_scrub.value, SCRUB_POWER)
