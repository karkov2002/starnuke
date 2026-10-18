extends Control
## Écran des paramètres (scenes/ui/settings_menu.tscn), ouvert par l'écran de démarrage. Onglets « Vidéo », « Audio »,
## « Commandes » et « Jeu » ; Commandes est à venir (onglet désactivé). Chaque choix est appliqué et sauvé
## aussitôt par l'autoload GameSettings. Émet closed au clic sur « Retour » (ou Échap).
## En jeu (in_game, ouvert par la pause, scripts/ui/pause_menu.gd) : fond translucide sur la vue figée et bouton
## supplémentaire « Quitter la partie », avec confirmation Oui / Non (main_menu_requested : retour à l'écran de
## démarrage).

signal main_menu_requested

## Ouvert depuis la partie (pause) : à fixer avant l'ajout à l'arbre.
var in_game := false
## Textes : clés des fichiers de langue (locale/strings.csv) ; les textes composés (résolutions, note) sont refaits
## quand la langue change.

signal closed

const PANEL_SIZE := Vector2(980.0, 560.0)
const TABS: Array[String] = ["TAB_VIDEO", "TAB_AUDIO", "TAB_CONTROL", "TAB_GAME"]
const DISABLED_TABS: Array[String] = ["TAB_CONTROL"]

var _tabs: TabContainer
var _mode: OptionButton
var _resolution: OptionButton
var _resolution_note: Label
var _brightness: HSlider
var _brightness_value: Label
var _interior_light: HSlider
var _interior_light_value: Label
var _language: OptionButton
var _music_volume: HSlider
var _music_volume_value: Label
var _sfx_volume: HSlider
var _sfx_volume_value: Label
var _music_mute: Button
var _sfx_mute: Button
var _playlist: OptionButton
var _back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	# Fond translucide : la vue 3D (décor du menu ou partie figée) reste visible, pour juger la luminosité.
	background.color = Color(0.0, 0.0, 0.0, 0.6)
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
	_build_audio(pages.TAB_AUDIO)
	_build_game(pages.TAB_GAME)

	_back = Button.new()
	_back.text = "SETTINGS_BACK"
	_back.custom_minimum_size = Vector2(220.0, 52.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.add_theme_font_size_override("font_size", 22)
	_back.pressed.connect(func() -> void: closed.emit())
	if in_game:
		var buttons := HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons.add_theme_constant_override("separation", 24)
		column.add_child(buttons)
		buttons.add_child(_back)
		var main_menu := Button.new()
		main_menu.text = "SETTINGS_QUIT_GAME"
		main_menu.custom_minimum_size = Vector2(220.0, 52.0)
		main_menu.add_theme_font_size_override("font_size", 22)
		main_menu.pressed.connect(_confirm_quit_game)
		buttons.add_child(main_menu)
	else:
		column.add_child(_back)

	_refresh()
	GameSettings.changed.connect(_refresh)
	_mode.grab_focus.call_deferred()


## « Quitter la partie » : confirmation Oui / Non (la partie en cours est perdue).
func _confirm_quit_game() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("SETTINGS_QUIT_GAME")
	dialog.dialog_text = tr("SETTINGS_QUIT_GAME_CONFIRM")
	dialog.ok_button_text = tr("DIALOG_YES")
	dialog.cancel_button_text = tr("DIALOG_NO")
	dialog.confirmed.connect(func() -> void: main_menu_requested.emit())
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
	dialog.get_cancel_button().grab_focus.call_deferred()


## Échap ferme l'écran, quel que soit le contrôle qui a le focus (un menu déroulant ou une fenêtre de confirmation
## ouverts reçoivent Échap avant, dans leur propre fenêtre, et se ferment seuls).
func _input(event: InputEvent) -> void:
	if (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")) and not event.is_echo():
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
	# Luminosité : curseur de 25 à 150 % (facteur d'exposition, GameSettings.brightness).
	var label := Label.new()
	label.text = "VIDEO_BRIGHTNESS"
	label.add_theme_font_size_override("font_size", 20)
	grid.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	grid.add_child(row)
	_brightness = HSlider.new()
	_brightness.min_value = GameSettings.BRIGHTNESS_RANGE.x * 100.0
	_brightness.max_value = GameSettings.BRIGHTNESS_RANGE.y * 100.0
	_brightness.step = 5.0
	_brightness.custom_minimum_size = Vector2(360.0, 44.0)
	_brightness.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_brightness)
	_brightness_value = Label.new()
	_brightness_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_brightness_value.add_theme_font_size_override("font_size", 20)
	row.add_child(_brightness_value)
	_brightness.value_changed.connect(func(value: float) -> void:
		_brightness_value.text = "%d %%" % roundi(value)
		GameSettings.set_brightness(value / 100.0))
	# Éclairage intérieur : curseur de 10 à 150 % (puissance des lampes de la station, GameSettings.interior_light).
	var light_label := Label.new()
	light_label.text = "VIDEO_INTERIOR_LIGHT"
	light_label.add_theme_font_size_override("font_size", 20)
	grid.add_child(light_label)
	var light_row := HBoxContainer.new()
	light_row.add_theme_constant_override("separation", 12)
	grid.add_child(light_row)
	_interior_light = HSlider.new()
	_interior_light.min_value = GameSettings.INTERIOR_LIGHT_RANGE.x * 100.0
	_interior_light.max_value = GameSettings.INTERIOR_LIGHT_RANGE.y * 100.0
	_interior_light.step = 5.0
	_interior_light.custom_minimum_size = Vector2(360.0, 44.0)
	_interior_light.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	light_row.add_child(_interior_light)
	_interior_light_value = Label.new()
	_interior_light_value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_interior_light_value.add_theme_font_size_override("font_size", 20)
	light_row.add_child(_interior_light_value)
	_interior_light.value_changed.connect(func(value: float) -> void:
		_interior_light_value.text = "%d %%" % roundi(value)
		GameSettings.set_interior_light(value / 100.0))
	_resolution_note = _add_note(page, "")
	_resolution_note.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## Onglet Audio : volume de la musique et des effets sonores (0 à 100 %, bouton « Muet » à côté de chaque curseur :
## coupure totale, curseur désactivé et grisé), playlist jouée en partie (sous-dossiers
## de res://playlist/, autoload Music ; noms de dossiers, jamais traduits).
func _build_audio(page: VBoxContainer) -> void:
	var grid := _make_grid(page)
	var music := _add_percent_slider(grid, "AUDIO_MUSIC_VOLUME", func(value: float) -> void:
		GameSettings.set_music_volume(value / 100.0))
	_music_volume = music[0]
	_music_volume_value = music[1]
	_music_mute = _add_mute_button(music[2], GameSettings.set_music_muted)
	var sfx := _add_percent_slider(grid, "AUDIO_SFX_VOLUME", func(value: float) -> void:
		GameSettings.set_sfx_volume(value / 100.0))
	_sfx_volume = sfx[0]
	_sfx_volume_value = sfx[1]
	_sfx_mute = _add_mute_button(sfx[2], GameSettings.set_sfx_muted)
	_playlist = _add_option(grid, "AUDIO_PLAYLIST")
	_playlist.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_playlist.item_selected.connect(func(index: int) -> void:
		GameSettings.set_playlist(_playlist.get_item_text(index)))
	_add_note(page, "AUDIO_PLAYLIST_NOTE")


## Bouton bascule « Muet » au bout de la ligne d'un curseur : coupe le son (on_toggle) ; le curseur est alors
## désactivé (_refresh).
func _add_mute_button(row: HBoxContainer, on_toggle: Callable) -> Button:
	var button := SpeakerButton.new()
	button.toggle_mode = true
	button.tooltip_text = "AUDIO_MUTE"
	button.custom_minimum_size = Vector2(52.0, 44.0)
	button.toggled.connect(func(pressed: bool) -> void:
		button.queue_redraw()
		on_toggle.call(pressed))
	row.add_child(button)
	return button


## Bouton « Muet » à icône : haut-parleur avec ses ondes ; enfoncé (son coupé), ondes retirées et haut-parleur barré
## en rouge.
class SpeakerButton extends Button:
	func _draw() -> void:
		var muted := button_pressed
		var color := Color(0.62, 0.66, 0.72) if muted else Color(0.92, 0.94, 0.97)
		if is_hovered():
			color = color.lightened(0.25)
		var c := size * 0.5 - Vector2(4.0, 0.0)
		var s := minf(size.x, size.y) * 0.22
		# Corps (rectangle) et pavillon (trapèze).
		draw_colored_polygon(PackedVector2Array([c + Vector2(-1.6, -0.55) * s, c + Vector2(-0.6, -0.55) * s,
				c + Vector2(0.5, -1.25) * s, c + Vector2(0.5, 1.25) * s, c + Vector2(-0.6, 0.55) * s,
				c + Vector2(-1.6, 0.55) * s]), color)
		if muted:
			var red := Color(1.0, 0.32, 0.28)
			draw_line(c + Vector2(-1.9, -1.5) * s, c + Vector2(2.3, 1.5) * s, Color(0.1, 0.11, 0.14), 5.0, true)
			draw_line(c + Vector2(-1.9, -1.5) * s, c + Vector2(2.3, 1.5) * s, red, 3.0, true)
		else:
			for i in 2:
				var radius := (1.0 + 0.7 * i) * s
				draw_arc(c + Vector2(0.4, 0.0) * s, radius, -PI / 3.5, PI / 3.5, 16, color, 2.0, true)


## Curseur de 0 à 100 % et sa valeur affichée ; rend [curseur, étiquette, ligne].
func _add_percent_slider(grid: GridContainer, key: String, on_change: Callable) -> Array:
	var label := Label.new()
	label.text = key
	label.add_theme_font_size_override("font_size", 20)
	grid.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	grid.add_child(row)
	var slider := HSlider.new()
	slider.max_value = 100.0
	slider.step = 5.0
	slider.custom_minimum_size = Vector2(360.0, 44.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	value_label.add_theme_font_size_override("font_size", 20)
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = "%d %%" % roundi(value)
		on_change.call(value))
	value_label.custom_minimum_size.x = 70.0
	return [slider, value_label, row]


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
	_brightness.set_value_no_signal(GameSettings.brightness * 100.0)
	_brightness_value.text = "%d %%" % roundi(GameSettings.brightness * 100.0)
	_interior_light.set_value_no_signal(GameSettings.interior_light * 100.0)
	_interior_light_value.text = "%d %%" % roundi(GameSettings.interior_light * 100.0)
	_music_volume.set_value_no_signal(GameSettings.music_volume * 100.0)
	_music_volume_value.text = "%d %%" % roundi(GameSettings.music_volume * 100.0)
	_sfx_volume.set_value_no_signal(GameSettings.sfx_volume * 100.0)
	_sfx_volume_value.text = "%d %%" % roundi(GameSettings.sfx_volume * 100.0)
	for pair in [[_music_mute, _music_volume, _music_volume_value, GameSettings.music_muted],
			[_sfx_mute, _sfx_volume, _sfx_volume_value, GameSettings.sfx_muted]]:
		pair[0].set_pressed_no_signal(pair[3])
		pair[0].queue_redraw()
		pair[1].editable = not pair[3]
		pair[1].modulate.a = 0.4 if pair[3] else 1.0
		pair[2].modulate.a = 0.4 if pair[3] else 1.0
	_playlist.clear()
	for playlist_name in Music.playlists():
		_playlist.add_item(playlist_name)
		if playlist_name == GameSettings.playlist:
			_playlist.select(_playlist.item_count - 1)


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
