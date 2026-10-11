extends Control
## Écran des paramètres (scenes/ui/settings_menu.tscn), ouvert par l'écran de démarrage. Onglets « Vidéo », « Audio »,
## « Commandes » et « Jeu » ; Audio et Commandes sont à venir (onglets désactivés). Chaque choix est appliqué et sauvé
## aussitôt par l'autoload GameSettings. Émet closed au clic sur « Retour » (ou Échap).
## Textes : clés des fichiers de langue (locale/strings.csv) ; les textes composés (résolutions, note) sont refaits
## quand la langue change.

signal closed

const PANEL_SIZE := Vector2(980.0, 560.0)
const TABS: Array[String] = ["TAB_VIDEO", "TAB_AUDIO", "TAB_CONTROL", "TAB_GAME"]
const DISABLED_TABS: Array[String] = ["TAB_AUDIO", "TAB_CONTROL"]

var _tabs: TabContainer
var _mode: OptionButton
var _resolution: OptionButton
var _resolution_note: Label
var _language: OptionButton
var _back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "SETTINGS_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = PANEL_SIZE
	_tabs.add_theme_font_size_override("font_size", 22)
	column.add_child(_tabs)
	var pages := {}
	for key in TABS:
		var margin := MarginContainer.new()
		margin.name = key
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 28)
		_tabs.add_child(margin)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 20)
		margin.add_child(page)
		pages[key] = page
		var index := _tabs.get_tab_count() - 1
		_tabs.set_tab_title(index, key)
		if key in DISABLED_TABS:
			_tabs.set_tab_disabled(index, true)
			_tabs.get_tab_bar().set_tab_tooltip(index, "TAB_COMING_SOON")
			_add_note(page, "TAB_COMING_SOON")
	_build_video(pages.TAB_VIDEO)
	_build_game(pages.TAB_GAME)

	_back = Button.new()
	_back.text = "SETTINGS_BACK"
	_back.custom_minimum_size = Vector2(220.0, 52.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.add_theme_font_size_override("font_size", 22)
	_back.pressed.connect(func() -> void: closed.emit())
	column.add_child(_back)

	_refresh()
	GameSettings.changed.connect(_refresh)
	_mode.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


## Onglet Vidéo : mode d'affichage, résolution, note sur le sens de la résolution selon le mode.
func _build_video(page: VBoxContainer) -> void:
	var grid := _make_grid(page)
	_mode = _add_option(grid, "VIDEO_DISPLAY_MODE")
	_mode.add_item("VIDEO_WINDOWED", GameSettings.WindowMode.WINDOWED)
	_mode.add_item("VIDEO_FULLSCREEN", GameSettings.WindowMode.FULLSCREEN)
	_mode.item_selected.connect(func(index: int) -> void:
		GameSettings.set_window_mode(_mode.get_item_id(index) as GameSettings.WindowMode))
	_resolution = _add_option(grid, "VIDEO_RESOLUTION")
	# Les libellés sont composés (dimensions, format, « native ») : pas de traduction automatique.
	_resolution.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_resolution.item_selected.connect(func(index: int) -> void:
		GameSettings.set_resolution(_resolution.get_item_metadata(index)))
	_resolution_note = _add_note(page, "")
	_resolution_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## Onglet Jeu : langue (noms des langues dans leur propre langue, jamais traduits).
func _build_game(page: VBoxContainer) -> void:
	var grid := _make_grid(page)
	_language = _add_option(grid, "GAME_LANGUAGE")
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for code in GameSettings.LOCALES:
		_language.add_item(GameSettings.LOCALE_NAMES[code])
		_language.set_item_metadata(_language.item_count - 1, code)
	_language.item_selected.connect(func(index: int) -> void:
		GameSettings.set_locale(_language.get_item_metadata(index)))


## Valeurs affichées : celles de GameSettings (après un changement, ou un changement de langue).
func _refresh() -> void:
	_mode.select(_mode.get_item_index(GameSettings.window_mode))
	_resolution.clear()
	var current := GameSettings.effective_resolution()
	for r in GameSettings.available_resolutions():
		_resolution.add_item(GameSettings.describe_resolution(r))
		_resolution.set_item_metadata(_resolution.item_count - 1, r)
		if r == current:
			_resolution.select(_resolution.item_count - 1)
	_resolution_note.text = tr("VIDEO_RESOLUTION_NOTE_FULLSCREEN"
			if GameSettings.window_mode == GameSettings.WindowMode.FULLSCREEN else "VIDEO_RESOLUTION_NOTE_WINDOWED")
	if not GameSettings.can_change_display():
		_resolution_note.text += "\n\n" + tr("VIDEO_EMBEDDED_NOTE")
	_language.select(GameSettings.LOCALES.find(GameSettings.locale))


func _make_grid(page: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 16)
	page.add_child(grid)
	return grid


func _add_option(grid: GridContainer, key: String) -> OptionButton:
	var label := Label.new()
	label.text = key
	label.custom_minimum_size.x = 280.0
	label.add_theme_font_size_override("font_size", 20)
	grid.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(440.0, 44.0)
	option.add_theme_font_size_override("font_size", 20)
	grid.add_child(option)
	return option


func _add_note(page: VBoxContainer, key: String) -> Label:
	var note := Label.new()
	note.text = key
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = PANEL_SIZE.x - 60.0
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	page.add_child(note)
	return note
