class_name TvDisplay
extends Control
## Interface de l'écran de télévision du module Commande (scripts/tv_console.gd), dessinée dans son SubViewport :
## - la chaîne en cours : vidéo du plateau en boucle (deux présentateurs), édition normale ou, après une explosion
##   (TvChannels.is_alert), édition spéciale (présentateurs agités, explosion sur le mur vidéo) avec le bandeau rouge
##   « Alerte info » ; bandeau défilant (TvNews) dans les deux éditions, rouge en alerte, bleu nuit sinon ; vidéos assets/tv/video/<CODE>/<normal|alert>.ogv si le pays a les siennes, sinon
##   assets/tv/video/<normal|alert>.ogv (tools/build_tv_videos.ps1). Nom de la chaîne en haut à droite (logo),
##   bandeau « En direct » et pays en bas ; ou la mire « Pas de signal » (barres de couleur) si la capitale du pays a
##   été touchée (TvChannels.is_off_air) ;
## - en haut à gauche, le bouton « Chaînes », qui ouvre la liste des pays (ordre alphabétique du nom traduit, avec
##   le nom de leur chaîne d'information, inventé ; pays hors d'antenne signalés) : un clic choisit la chaîne.
## L'interface ne réagit qu'en position « vue TV » (TvConsole transmet alors la souris).

signal channel_selected(code: String)

const VIDEO_DIR := "res://assets/tv/video/"
const COLOR_TEXT := Color(0.95, 0.96, 0.98)
const COLOR_PANEL := Color(0.03, 0.05, 0.09, 0.94)
const COLOR_ACCENT := Color(0.85, 0.12, 0.1)
const COLOR_OFF := Color(0.6, 0.6, 0.62)
## Fond du bandeau défilant : rouge en édition spéciale, bleu nuit en temps normal.
const TICKER_ALERT := Color(0.45, 0.03, 0.03, 0.92)
const TICKER_NORMAL := Color(0.03, 0.09, 0.22, 0.92)

## Chaînes et règles de jeu (hors d'antenne, édition spéciale), tenues par TvConsole.
var channels: TvChannels
## Pays de la chaîne affichée ("" : aucune).
var channel := ""

var _studio: VideoStreamPlayer
## Vidéo en cours (chemin) : la lecture ne repart pas de zéro si rien ne change.
var _video_path := ""
var _alert := false
var _live_label: Label
var _live_box: PanelContainer
## Bandeau défilant de l'édition spéciale (TvNews) : texte recomposé à chaque passage complet (bilan à jour,
## variantes tirées au hasard), défilement vers la gauche (vers la droite pour l'arabe, l'hébreu, le persan, l'ourdou).
var _ticker: Control
var _ticker_band: ColorRect
var _ticker_label: Label
var _ticker_rtl := false
var _ticker_rng := RandomNumberGenerator.new()
var _logo: Label
var _logo_panel: PanelContainer
var _lower_third: PanelContainer
var _country_label: Label
var _no_signal: Control
var _menu_button: Button
var _menu: PanelContainer
var _list: GridContainer
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_studio = VideoStreamPlayer.new()
	_studio.expand = true
	_studio.loop = true
	_studio.set_anchors_preset(Control.PRESET_FULL_RECT)
	_studio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_studio)
	# Logo de la chaîne en haut à droite.
	_logo_panel = PanelContainer.new()
	_logo_panel.add_theme_stylebox_override("panel", _box(Color(0.02, 0.04, 0.1, 0.85), COLOR_ACCENT, 3, 14))
	_logo = Label.new()
	_logo.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_logo.add_theme_font_size_override("font_size", int(size.y * 0.055))
	_logo.add_theme_color_override("font_color", COLOR_TEXT)
	_logo_panel.add_child(_logo)
	add_child(_logo_panel)
	# Bandeau bas : « EN DIRECT » et pays.
	_lower_third = PanelContainer.new()
	_lower_third.add_theme_stylebox_override("panel", _box(Color(0.02, 0.04, 0.1, 0.88), Color(0, 0, 0, 0), 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_lower_third.add_child(row)
	_live_label = Label.new()
	_live_label.text = "TV_LIVE"
	_live_label.add_theme_font_size_override("font_size", int(size.y * 0.045))
	_live_label.add_theme_color_override("font_color", COLOR_TEXT)
	_live_box = PanelContainer.new()
	_live_box.add_theme_stylebox_override("panel", _box(COLOR_ACCENT, Color(0, 0, 0, 0), 0, 8))
	_live_box.add_child(_live_label)
	row.add_child(_live_box)
	_country_label = Label.new()
	_country_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_country_label.add_theme_font_size_override("font_size", int(size.y * 0.045))
	_country_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(_country_label)
	add_child(_lower_third)
	_build_ticker()
	# Mire « pas de signal ».
	_no_signal = Control.new()
	_no_signal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_no_signal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_no_signal.draw.connect(_draw_no_signal)
	add_child(_no_signal)
	# Bouton du menu des chaînes et liste.
	_menu_button = Button.new()
	_menu_button.text = "TV_CHANNELS"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.add_theme_font_size_override("font_size", int(size.y * 0.045))
	for state in ["normal", "hover", "pressed"]:
		_menu_button.add_theme_stylebox_override(state, _box(COLOR_PANEL if state != "hover" else Color(0.1, 0.15, 0.25, 0.95),
				COLOR_TEXT, 2, 12))
	_menu_button.position = Vector2(size.y * 0.04, size.y * 0.04)
	_menu_button.pressed.connect(_toggle_menu)
	add_child(_menu_button)
	_build_menu()
	show_channel(channel)


func _process(delta: float) -> void:
	_time += delta
	if is_off_air():
		_no_signal.queue_redraw()
	else:
		if _alert:
			# Bandeau « Alerte info » qui clignote doucement.
			_live_box.modulate.a = 0.75 + 0.25 * sin(_time * 6.0)
		_scroll_ticker(delta)
	# Placement (tailles connues après la mise en page).
	_logo_panel.position = Vector2(size.x - _logo_panel.size.x - size.y * 0.04, size.y * 0.04)
	var bottom := size.y - (_ticker.size.y if _ticker.visible else 0.0)
	_lower_third.position = Vector2(size.y * 0.04, bottom - _lower_third.size.y - size.y * 0.03)


func is_off_air() -> bool:
	return channel != "" and channels != null and channels.is_off_air(channel)


## Affiche la chaîne du pays code ("" : aucune, mire).
func show_channel(code: String) -> void:
	channel = code
	var off := code == "" or is_off_air()
	_alert = not off and channels != null and channels.is_alert()
	_studio.visible = not off
	_logo_panel.visible = code != ""
	_lower_third.visible = not off
	_no_signal.visible = off
	_live_label.text = "TV_BREAKING" if _alert else "TV_LIVE"
	_live_box.modulate.a = 1.0
	# Bandeau dans les deux éditions ; recomposé au changement de chaîne ou d'édition.
	var edition := "%s/%s" % [code, _alert]
	var new_ticker := not off and (not _ticker.visible or edition != String(_ticker.get_meta("edition", "")))
	_ticker.visible = not off
	_ticker_band.color = TICKER_ALERT if _alert else TICKER_NORMAL
	if new_ticker:
		_ticker.set_meta("edition", edition)
		_ticker_rng.seed = hash(code) ^ int(_time * 1000.0)
		_next_ticker_text()
	if code != "" and channels:
		_logo.text = channels.name_of(code)
		_country_label.text = tr("COUNTRY_" + code)
	_play(_video_for(code, "alert" if _alert else "normal") if not off else "")
	_refresh_menu()


## Lecture suspendue quand l'écran n'est plus rendu (TvConsole : caméra loin).
func set_playing(playing: bool) -> void:
	_studio.paused = not playing


func _video_for(code: String, edition: String) -> String:
	var own := "%s%s/%s.ogv" % [VIDEO_DIR, code, edition]
	return own if ResourceLoader.exists(own) else "%s%s.ogv" % [VIDEO_DIR, edition]


func _play(path: String) -> void:
	if path == _video_path:
		return
	_video_path = path
	_studio.stop()
	_studio.stream = load(path) as VideoStream if path != "" and ResourceLoader.exists(path) else null
	if _studio.stream:
		_studio.play()


func refresh() -> void:
	show_channel(channel)


## Bandeau recomposé et relancé depuis le bord (nouveau tir).
func restart_ticker() -> void:
	if _ticker.visible:
		_next_ticker_text()


func _build_ticker() -> void:
	_ticker = Control.new()
	_ticker.clip_contents = true
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.size = Vector2(size.x, size.y * 0.075)
	_ticker.position = Vector2(0.0, size.y - _ticker.size.y)
	_ticker.visible = false
	_ticker_band = ColorRect.new()
	_ticker_band.color = TICKER_ALERT
	_ticker_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ticker_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker.add_child(_ticker_band)
	_ticker_label = Label.new()
	_ticker_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ticker_label.add_theme_font_size_override("font_size", int(size.y * 0.045))
	_ticker_label.add_theme_color_override("font_color", COLOR_TEXT)
	_ticker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ticker_label.size.y = _ticker.size.y
	_ticker.add_child(_ticker_label)
	add_child(_ticker)


## Nouveau texte (langue de la chaîne), placé à l'entrée du bandeau.
func _next_ticker_text() -> void:
	if channels == null or channel == "":
		return
	var lang := channels.lang_of(channel)
	_ticker_rtl = TvNews.is_rtl(lang)
	_ticker_label.language = lang.replace("zh_TW", "zh_Hant")
	_ticker_label.text_direction = Control.TEXT_DIRECTION_RTL if _ticker_rtl else Control.TEXT_DIRECTION_AUTO
	_ticker_label.text = channels.news_text(channel, _ticker_rng)
	_ticker_label.reset_size()
	_ticker_label.size.y = _ticker.size.y
	_ticker_label.position.x = -_ticker_label.size.x if _ticker_rtl else size.x


func _scroll_ticker(delta: float) -> void:
	var step := size.y * 0.16 * delta
	if _ticker_rtl:
		_ticker_label.position.x += step
		if _ticker_label.position.x > size.x:
			_next_ticker_text()
	else:
		_ticker_label.position.x -= step
		if _ticker_label.position.x < -_ticker_label.size.x:
			_next_ticker_text()


## Mosaïque des chaînes, comme le guide d'une vraie télévision : plein écran, grille défilante (molette) de vignettes
## ChannelTile (logo, numéro, nom de la chaîne, pays), numérotées dans l'ordre alphabétique des pays (langue du
## joueur). Construite une fois, à la première ouverture ; les états (chaîne en cours, hors d'antenne) sont mis à jour
## sans reconstruction.
func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", _box(Color(0.02, 0.03, 0.05), Color(0, 0, 0, 0), 0, 0))
	_menu.position = Vector2.ZERO
	_menu.size = size
	_menu.visible = false
	add_child(_menu)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(size.y * 0.04))
	_menu.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(size.y * 0.025))
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "TV_CHOOSE_CHANNEL"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", int(size.y * 0.05))
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)
	var close := Button.new()
	close.text = "TV_CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", int(size.y * 0.035))
	for state in ["normal", "hover", "pressed"]:
		close.add_theme_stylebox_override(state, _box(Color(0.1, 0.13, 0.2, 0.95) if state != "hover"
				else Color(0.18, 0.24, 0.36, 0.98), Color(1, 1, 1, 0.6), 1, 10))
	close.pressed.connect(func() -> void: _menu.visible = false)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.name = "Scroll"
	column.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 5
	_list.add_theme_constant_override("h_separation", int(size.y * 0.02))
	_list.add_theme_constant_override("v_separation", int(size.y * 0.02))
	scroll.add_child(_list)


func _toggle_menu() -> void:
	if _list.get_child_count() == 0:
		_fill_menu()
	_menu.visible = not _menu.visible
	if _menu.visible:
		_refresh_menu()
		# La chaîne en cours en vue.
		for tile: ChannelTile in _list.get_children():
			if tile.code == channel:
				(_menu.find_child("Scroll", true, false) as ScrollContainer).ensure_control_visible.call_deferred(tile)


func _fill_menu() -> void:
	var codes := channels.codes()
	codes.sort_custom(func(a: String, b: String) -> bool:
		return tr("COUNTRY_" + a).naturalnocasecmp_to(tr("COUNTRY_" + b)) < 0)
	var tile_width := (size.x - size.y * 0.08 - 4.0 * size.y * 0.02 - 14.0) / 5.0
	for i in codes.size():
		var code := codes[i]
		var tile := ChannelTile.new()
		tile.custom_minimum_size = Vector2(tile_width, tile_width * 0.82)
		tile.setup(code, i + 1, channels.name_of(code), tr("COUNTRY_" + code))
		tile.pressed.connect(func() -> void:
			_menu.visible = false
			channel_selected.emit(code))
		_list.add_child(tile)


## États des vignettes (chaîne en cours, hors d'antenne).
func _refresh_menu() -> void:
	if channels == null or _list == null:
		return
	for tile: ChannelTile in _list.get_children():
		tile.set_state(tile.code == channel, channels.is_off_air(tile.code))


func _draw_no_signal() -> void:
	# Barres de couleur (mire), bruit léger, message au centre.
	var colors := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
			Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	var width := size.x / colors.size()
	for i in colors.size():
		_no_signal.draw_rect(Rect2(Vector2(i * width, 0), Vector2(width + 1, size.y * 0.72)), colors[i])
	_no_signal.draw_rect(Rect2(Vector2(0, size.y * 0.72), Vector2(size.x, size.y * 0.28)), Color(0.06, 0.06, 0.07))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_time * 12.0)
	for k in 160:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		_no_signal.draw_rect(Rect2(p, Vector2(rng.randf_range(2, 9), 2)), Color(1, 1, 1, rng.randf() * 0.25))
	var font := get_theme_default_font()
	var font_size := int(size.y * 0.09)
	var text := tr("TV_NO_SIGNAL")
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var box := Rect2(size * 0.5 - text_size * 0.5 - Vector2(30, 20), text_size + Vector2(60, 40))
	_no_signal.draw_rect(box, Color(0, 0, 0, 0.85))
	_no_signal.draw_string(font, Vector2(box.position.x + 30, box.position.y + 20 + text_size.y * 0.78), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_TEXT)


static func _box(fill: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	return UiKit.flat_box(fill, border, border_width, 6, margin)
