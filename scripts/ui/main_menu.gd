extends Control
## Écran de démarrage (scène principale scenes/ui/main_menu.tscn) : titre provisoire et boutons à droite
## (« Commencer la partie », « Paramètres » : écran scenes/ui/settings_menu.tscn par-dessus, « Quitter ») ; à gauche,
## la station vue de l'extérieur au-dessus de la Terre qui défile. Tous les textes sont des clés des fichiers de
## langue (locale/strings.csv), traduites automatiquement.
##
## Décor : la scène du jeu elle-même (Terre, nuages, atmosphère, station), chargée en tâche de fond dès l'ouverture
## du menu puis affichée en fondu, sans son interface ni le tir (Hud, NukeReport, NukeLauncher, PilotConsole, tablette retirés),
## observateur désactivé, filmée par une caméra extérieure (BACKDROP_CAMERA_*), en temps réel (BACKDROP_TIME_SCALE).
## Le même chargement sert au lancement de la partie : « Commencer la partie » n'attend plus que la fin du chargement
## s'il n'est pas terminé.

const GAME_SCENE := "res://scenes/orbit_view.tscn"
const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const BUTTON_SIZE := Vector2(380.0, 60.0)
## Caméra du décor (repère de la scène du jeu : station à l'origine, avant −Z, Terre en bas) : position, point visé,
## décalage horizontal (positif : station et Terre à gauche de l'écran), champ.
const BACKDROP_CAMERA_POSITION := Vector3(58.0, 22.0, 45.0)
const BACKDROP_CAMERA_TARGET := Vector3(0.0, -6.0, 0.0)
const BACKDROP_CAMERA_H_OFFSET := 0.38
const BACKDROP_CAMERA_FOV := 55.0
const BACKDROP_TIME_SCALE := 1.0
const BACKDROP_FADE_S := 2.0
## Nœuds de la scène du jeu retirés du décor (interface, tir).
const BACKDROP_REMOVED: Array[String] = ["Hud", "NukeReport", "NukeLauncher", "PauseMenu", "PilotConsole",
		"Observer/Camera/Tablet"]

var _menu: Control
var _start_button: Button
var _veil: ColorRect
var _game_scene: PackedScene
var _load_failed := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Voile noir : fond tant que le décor charge, puis s'efface en fondu.
	_veil = ColorRect.new()
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	_load_failed = ResourceLoader.load_threaded_request(GAME_SCENE) != OK

	# Boutons dans la moitié droite de l'écran.
	_menu = CenterContainer.new()
	_menu.anchor_left = 0.5
	_menu.anchor_right = 1.0
	_menu.anchor_bottom = 1.0
	add_child(_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_menu.add_child(column)

	# Titre lumineux : halo et couleur de corps noir qui va et vient du noir au blanc (scripts/ui/title_glow.gd).
	var title := TitleGlow.new()
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8.0
	column.add_child(spacer)

	_start_button = _add_button(column, "MENU_START", _on_start)
	_add_button(column, "MENU_SETTINGS", _on_settings)
	_add_button(column, "MENU_QUIT", func() -> void: get_tree().quit())
	_start_button.grab_focus.call_deferred()


func _process(_delta: float) -> void:
	if _game_scene or _load_failed:
		set_process(false)
		return
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_game_scene = ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
		_build_backdrop()
	elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_load_failed = true


## Décor : scène du jeu sans interface ni tir, caméra extérieure, temps accéléré, apparition en fondu.
func _build_backdrop() -> void:
	var backdrop := _game_scene.instantiate()
	for removed in BACKDROP_REMOVED:
		var node := backdrop.get_node_or_null(removed)
		if node:
			node.get_parent().remove_child(node)
			node.free()
	var observer := backdrop.get_node_or_null("Observer")
	if observer:
		observer.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = BACKDROP_CAMERA_FOV
	camera.far = 3000.0
	camera.h_offset = BACKDROP_CAMERA_H_OFFSET * 2.0 * tan(deg_to_rad(BACKDROP_CAMERA_FOV) * 0.5) \
			* BACKDROP_CAMERA_POSITION.distance_to(BACKDROP_CAMERA_TARGET)
	backdrop.add_child(camera)
	add_child(backdrop)
	move_child(backdrop, 0)
	camera.look_at_from_position(BACKDROP_CAMERA_POSITION, BACKDROP_CAMERA_TARGET)
	camera.make_current()
	var orbit := backdrop.get_node_or_null("Orbit")
	if orbit:
		orbit.set("time_scale", BACKDROP_TIME_SCALE)
	create_tween().tween_property(_veil, "color:a", 0.0, BACKDROP_FADE_S)


func _add_button(parent: Control, key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## La scène du jeu est chargée en tâche de fond depuis l'ouverture du menu : le menu laisse place à « Chargement en
## cours… » (points animés, pourcentage) jusqu'à la fin du chargement, puis la scène remplace le menu. Le dernier
## message reste affiché pendant la mise en place de la scène (_ready des nœuds), qui se fait sur le fil principal.
func _on_start() -> void:
	if _load_failed:
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
	while _game_scene == null:
		if _load_failed:
			get_tree().change_scene_to_file(GAME_SCENE)
			return
		ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
		dots = (dots + 1) % 30
		loading.text = tr("MENU_LOADING").format({"dots": ".".repeat(1 + floori(dots / 10.0)),
				"percent": roundi(100.0 * float(progress[0]) if not progress.is_empty() else 0.0)})
		await get_tree().process_frame
	loading.text = tr("MENU_LOADING").format({"dots": "...", "percent": 100})
	# Deux images : le texte final est affiché avant la mise en place de la scène, qui fige l'écran un instant.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_packed(_game_scene)


func _on_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	_menu.visible = false
	settings.closed.connect(func() -> void:
		settings.queue_free()
		_menu.visible = true
		_start_button.grab_focus())
	add_child(settings)
