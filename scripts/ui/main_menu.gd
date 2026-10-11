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


## La scène du jeu est chargée en tâche de fond (quelques secondes) : le menu laisse place à « Chargement en cours… »
## (points animés, pourcentage), puis la scène remplace le menu. Le dernier message reste affiché pendant la mise en
## place de la scène (_ready des nœuds), qui se fait sur le fil principal.
func _on_start() -> void:
	if ResourceLoader.load_threaded_request(GAME_SCENE) != OK:
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	_menu.visible = false
	var loading := Label.new()
	loading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 32)
	loading.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(loading)
	var progress: Array = []
	var dots := 0
	while true:
		var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			get_tree().change_scene_to_file(GAME_SCENE)
			return
		dots = (dots + 1) % 30
		loading.text = tr("MENU_LOADING").format({"dots": ".".repeat(1 + floori(dots / 10.0)),
				"percent": roundi(100.0 * float(progress[0]) if not progress.is_empty() else 0.0)})
		await get_tree().process_frame
	loading.text = tr("MENU_LOADING").format({"dots": "...", "percent": 100})
	# Deux images : le texte final est affiché avant la mise en place de la scène, qui fige l'écran un instant.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene)


func _on_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	_menu.visible = false
	settings.closed.connect(func() -> void:
		settings.queue_free()
		_menu.visible = true
		_start_button.grab_focus())
	add_child(settings)
