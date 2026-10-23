class_name DebugUi
extends RefCounted
## Petits contrôles des panneaux de debug (outils de développement, textes en français) : boutons, curseurs (avec
## la marque « dragging » pendant la manipulation, pour ne pas écraser la valeur affichée), champs numériques,
## style du panneau et durées lisibles.


static func button(text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(action)
	return control


static func slider(min_value: float, max_value: float, step: float, action: Callable) -> HSlider:
	var control := HSlider.new()
	control.min_value = min_value
	control.max_value = max_value
	control.step = step
	control.focus_mode = Control.FOCUS_NONE
	control.value_changed.connect(action)
	control.drag_started.connect(func() -> void: control.set_meta(&"dragging", true))
	control.drag_ended.connect(func(_changed: bool) -> void: control.remove_meta(&"dragging"))
	return control


## Le curseur est-il en cours de manipulation ? (Hors manipulation, il affiche la valeur réellement appliquée.)
static func is_dragging(control: HSlider) -> bool:
	return control.has_meta(&"dragging")


static func spin(min_value: float, max_value: float, value: float, prefix: String) -> SpinBox:
	var control := SpinBox.new()
	control.min_value = min_value
	control.max_value = max_value
	control.step = 0.01
	control.value = value
	control.prefix = prefix
	control.suffix = "°"
	control.custom_minimum_size.x = 120.0
	return control


static func row(parent: Control, separation := 6) -> HBoxContainer:
	var control := HBoxContainer.new()
	control.add_theme_constant_override("separation", separation)
	parent.add_child(control)
	return control


static func panel_style() -> StyleBoxFlat:
	return UiKit.flat_box(Color(0.1, 0.05, 0.05, 0.75), Color(0.9, 0.4, 0.3, 0.4), 1, 10, 14.0)


static func format_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%.1f s" % seconds
	var s := int(seconds)
	if seconds < 3600.0:
		return "%d min %02d s" % [floori(s / 60.0), s % 60]
	if seconds < 86400.0:
		return "%d h %02d min" % [floori(s / 3600.0), floori(s / 60.0) % 60]
	return "%d j %02d h" % [floori(s / 86400.0), floori(s / 3600.0) % 24]
