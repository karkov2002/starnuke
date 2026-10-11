extends Control
## Écran de démarrage (scène principale scenes/ui/main_menu.tscn) : fond noir, titre provisoire, boutons
## « Commencer la partie » (scène du jeu), « Paramètres » (écran scenes/ui/settings_menu.tscn, par-dessus) et
## « Quitter ». Tous les textes sont des clés des fichiers de langue (locale/strings.csv), traduites automatiquement.

const GAME_SCENE := "res://scenes/orbit_view.tscn"
const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const BUTTON_SIZE := Vector2(380.0, 60.0)

var _menu: Control
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_menu = CenterContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_menu.add_child(column)

	var title := Label.new()
	title.text = "GAME_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 112)
	title.add_theme_color_override("font_color", Color(0.95, 0.42, 0.25))
	column.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 48.0
	column.add_child(spacer)

	_start_button = _add_button(column, "MENU_START", _on_start)
	_add_button(column, "MENU_SETTINGS", _on_settings)
	_add_button(column, "MENU_QUIT", func() -> void: get_tree().quit())
	_start_button.grab_focus.call_deferred()


func _add_button(parent: Control, key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _on_start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	_menu.visible = false
	settings.closed.connect(func() -> void:
		settings.queue_free()
		_menu.visible = true
		_start_button.grab_focus())
	add_child(settings)
