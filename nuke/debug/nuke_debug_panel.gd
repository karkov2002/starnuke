extends CanvasLayer
## Panneau de debug des explosions (scène nuke/debug/nuke_debug.tscn), en haut à gauche :
## - puissance sur une échelle logarithmique (10 kt à 50 Mt), avec les tailles calculées par NukeScaling ;
## - latitude / longitude de la cible (« Point visé » recopie le centre de la vue), bouton « Tirer » ;
## - scrubber du temps physique de la dernière explosion : « Rejouer » fige toutes les explosions au temps du
##   curseur (time_override_s), sinon le curseur suit le temps réel de l'effet ;
## - « Effacer » supprime toutes les explosions ; « Marqueurs » affiche les marqueurs de taille (NukeEffect).

const SCRUB_MAX_S := 21600.0
## Le curseur va jusqu'à 6 h (dissipation du champignon) et n'est pas linéaire (t = SCRUB_MAX_S · v⁵) : les 3 premières
## secondes (flash) occupent 17 % de sa course, les 10 premières minutes (montée du champignon) la moitié.
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

	_on_yield_changed(_yield_slider.value)


func _process(_delta: float) -> void:
	if not is_instance_valid(_last):
		_last = null
	if _last and not _replay.button_pressed:
		_scrub.set_value_no_signal(pow(minf(_last.get_time_s() / SCRUB_MAX_S, 1.0), 1.0 / SCRUB_POWER))
	_scrub_label.text = "t = %s" % _format_duration(_scrub_time()) if _last else "t = —"


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
	return "%d h %02d min" % [floori(s / 3600.0), floori(s / 60.0) % 60]


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
