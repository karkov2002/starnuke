class_name TabletDisplay
extends Control
## Interface de l'écran de la tablette (scripts/tablet.gd), dessinée dans son SubViewport, construite en code :
## - en haut, une barre d'onglets cliquables (Pilotage, Photographie, Tir de missile, Alertes) et, à droite, le bouton
##   « HUD : On / Off » (affichage en surimpression dans la cupola, Hud.overlay_enabled) ; dessous, la date et l'heure
##   UTC et l'heure solaire du point survolé ;
## - onglet Pilotage : la carte du poste de pilotage en réduit (OrbitalMap : trace au sol, station, point de manœuvre
##   et trace fantôme), de MAP_MAX_LAT_DEG nord à sud (comme au poste), et, dans une colonne à droite, la commande
##   de poussée (BurnControl en colonne : compte à rebours, gros bouton BURN bleu, jauge verticale) ;
## - onglet Photographie : la vue au nadir en temps réel (texture nadir_texture, rendue par la tablette seulement
##   quand l'onglet est affiché), le bouton « Photo » (flash ; la tablette prend la photo, PhotoArchive) et la
##   galerie des photos prises (◀ ▶, légende : date, point survolé, altitude, emprise au sol) ;
## - onglet Tir de missile : la commande de tir (LaunchControl : 48 silos, puissance, gros bouton rouge), agrandie
##   pour occuper la page (ses boutons ont une taille fixe en pixels) ;
## - onglet Alertes : la tablette est le récepteur des appels prioritaires (PriorityCall), comme un téléphone. En
##   haut (~80 %), l'écran de réception : l'appel en cours (expéditeur, objet, heure de réception ; le message se lit
##   au poste COMM), sinon « Aucune alerte » ; au-dessus des boutons, le bandeau clignotant PRIORITY_CALL_BANNER
##   pendant l'appel ; en bas, les 5 gros boutons du niveau d'alerte de la station (Station.set_alert : Normal,
##   Jaune, Orange, Rouge, Tout éteindre = « plus de lumière »), dessinés comme le bouton de tir ou BURN
##   (BigRedButton), de la couleur de l'alerte ; le niveau en cours est marqué. À l'arrivée d'un appel, la tablette
##   passe sur cet onglet (call_started).
## Taille : celle du SubViewport (proportions de la dalle de la tablette).

signal tab_changed(tab: int)
## Bouton Photo pressé : la tablette prend la photo (scripts/tablet.gd).
signal photo_requested

enum Tab { PILOT, PHOTO, MISSILE, ALERTS }

const MARGIN := 18.0
const FONT_SIZE := 22
const MAP_MAX_LAT_DEG := 80.0
## Largeur réservée à la colonne BURN, à droite de la carte, et à celle du bouton Photo (pixels).
const SIDE_WIDTH := 210.0
## Marge supplémentaire à droite (pixels) : le pouce de la main qui tient la tablette, posé sur la bordure de
## droite, mord sur le bord de l'écran.
const THUMB_PADDING := 30.0
## Hauteur de la barre d'onglets et de la ligne de l'horloge (pixels), espacement de la colonne.
const BAR_HEIGHT := 44.0
const CLOCK_HEIGHT := 30.0
const SPACING := 8.0
const TAB_KEYS: Array[String] = ["TABLET_TAB_PILOT", "TABLET_TAB_PHOTO", "TABLET_TAB_MISSILE", "TABLET_TAB_ALERTS"]
## Boutons du niveau d'alerte, dans l'ordre de Station.Alert : texte et couleur du capuchon (celle de l'éclairage ;
## noir pour « Tout éteindre »).
const ALERT_KEYS: Array[String] = ["TABLET_ALERT_NONE", "TABLET_ALERT_YELLOW", "TABLET_ALERT_ORANGE",
		"TABLET_ALERT_RED", "TABLET_ALERT_BLACKOUT"]
const ALERT_CAPS: Array[Color] = [Color(0.86, 0.87, 0.88), Color(0.95, 0.78, 0.18), Color(0.95, 0.5, 0.1),
		Color(0.8, 0.07, 0.04), Color(0.1, 0.1, 0.11)]
const ALERT_BUTTON_SIZE := Vector2(80.0, 74.0)
const COLOR_CALL := Color(1.0, 0.62, 0.18)
const BLINK_S := 0.5
const COLOR_TAB := Color(0.06, 0.09, 0.08)
const COLOR_TAB_ACTIVE := Color(0.12, 0.3, 0.2)
const FLASH_S := 0.35

var orbit: OrbitSimulation
var flight_computer: FlightComputer
## Image de la vue au nadir (SubViewport de la tablette).
var nadir_texture: Texture2D
## Photos prises (galerie de l'onglet Photographie) ; réglé par la tablette.
var archive: PhotoArchive:
	set(value):
		archive = value
		if archive:
			archive.photo_taken.connect(func(_photo: Dictionary) -> void: _show_photo(_photo_index))
			archive.restored.connect(func() -> void: _show_photo(-1))
		if _gallery_button:
			_show_photo(_photo_index)
var current_tab := Tab.PILOT

var _clock: Label
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _hud_button: Button
var _flash: ColorRect
var _photo_view: TextureRect
var _photo_caption: Label
var _gallery_button: Button
var _previous_button: Button
var _next_button: Button
## Photo affichée dans la galerie (−1 : vue en direct).
var _photo_index := -1
## Onglet Alertes : appel prioritaire suivi (trouvé à la première image où il existe), écran de réception (appel en
## cours, ou « Aucune alerte »), bandeau, étiquettes des boutons de niveau, horloge du clignotement.
var _call: PriorityCall
var _call_idle: Label
var _call_box: VBoxContainer
var _call_from: Label
var _call_subject: Label
var _call_time: Label
var _call_banner: PanelContainer
var _alert_labels: Array[Label] = []
var _shown_alert := -1
var _blink := 0.0
## État du HUD affiché sur le bouton (null avant la première image).
var _hud_shown = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = PilotDisplay.make_theme(FONT_SIZE)
	var background := ColorRect.new()
	background.color = Color(0.015, 0.02, 0.03)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.position = Vector2(MARGIN, MARGIN * 0.6)
	var column_size := size - Vector2(2.0 * MARGIN + THUMB_PADDING, 1.6 * MARGIN)
	column.size = column_size
	column.add_theme_constant_override("separation", int(SPACING))
	add_child(column)

	# Barre d'onglets et bouton HUD.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	column.add_child(bar)
	var group := ButtonGroup.new()
	for i in TAB_KEYS.size():
		var button := _make_tab_button(TAB_KEYS[i])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == current_tab
		button.pressed.connect(func() -> void: show_tab(i))
		bar.add_child(button)
		_tab_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_hud_button = _make_tab_button("TABLET_HUD_ON")
	_hud_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hud_button.pressed.connect(func() -> void:
		var hud := _hud()
		if hud:
			hud.set_overlay_enabled(not hud.overlay_enabled))
	bar.add_child(_hud_button)

	_clock = Label.new()
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_clock.custom_minimum_size = Vector2(0.0, CLOCK_HEIGHT)
	_clock.add_theme_font_size_override("font_size", 22)
	_clock.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	column.add_child(_clock)

	# Pages (une seule visible), dans la hauteur restante (calculée : un conteneur grandit pour loger son contenu,
	# sa taille courante ne compte pas).
	var page_size := Vector2(column_size.x, column_size.y - BAR_HEIGHT - CLOCK_HEIGHT - 2.0 * SPACING)
	var stack := Control.new()
	stack.custom_minimum_size = page_size
	stack.clip_contents = true
	column.add_child(stack)
	_pages.append(_build_pilot_page(page_size))
	_pages.append(_build_photo_page(page_size))
	_pages.append(_build_missile_page(page_size))
	_pages.append(_build_alerts_page(page_size))
	for page in _pages:
		page.size = page_size
		stack.add_child(page)
	show_tab(current_tab)


func show_tab(tab: int) -> void:
	current_tab = tab as Tab
	for i in _pages.size():
		_pages[i].visible = i == tab
		_tab_buttons[i].set_pressed_no_signal(i == tab)
		_style_tab(_tab_buttons[i], i == tab)
	tab_changed.emit(tab)


func _process(delta: float) -> void:
	_update_alerts(delta)
	var hud := _hud()
	var on := hud == null or hud.overlay_enabled
	if on != _hud_shown:
		_hud_shown = on
		_hud_button.text = tr("TABLET_HUD_ON" if on else "TABLET_HUD_OFF")
		_style_tab(_hud_button, on)
	if orbit == null:
		return
	var now := orbit.get_utc_datetime()
	var point := orbit.get_subsatellite_point()
	var date := tr("HUD_DATE").format({"day": "%02d" % now.day, "month": "%02d" % now.month, "year": now.year})
	var solar := orbit.get_local_solar_hour(point.y)
	_clock.text = tr("HUD_TIME").format({"date": date, "time": "%02d:%02d:%02d" % [now.hour, now.minute, now.second],
			"solar": "%02d:%02d" % [floori(solar), floori(solar * 60.0) % 60]})


# --- Pages ----------------------------------------------------------------------------------------------------------

## Carte (aussi grande que la page le permet, à côté de la colonne BURN) et commande de poussée.
func _build_pilot_page(page_size: Vector2) -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	var aspect := OrbitalMap.aspect_for(MAP_MAX_LAT_DEG)
	var map_height := minf(page_size.y, (page_size.x - SIDE_WIDTH - 16.0) / aspect)
	var map := OrbitalMap.new()
	map.orbit = orbit
	map.flight_computer = flight_computer
	map.max_lat_deg = MAP_MAX_LAT_DEG
	map.size = Vector2(map_height * aspect, map_height)
	map.custom_minimum_size = map.size
	map.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.add_child(map)
	var burn := BurnControl.new()
	burn.flight_computer = flight_computer
	burn.large = true
	burn.column_layout = true
	burn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	burn.alignment = BoxContainer.ALIGNMENT_CENTER
	page.add_child(burn)
	return page


## Vue au nadir en temps réel (légende en incrustation), bouton Photo et galerie des photos prises (PhotoArchive) :
## « Galerie » remplace la vue en direct par la dernière photo (◀ ▶ : précédente, suivante ; légende : numéro, date,
## point survolé, altitude, emprise), « Vue en direct » y revient ; le bouton Photo revient aussi à la vue en direct.
func _build_photo_page(page_size: Vector2) -> Control:
	var page := HBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	_photo_view = TextureRect.new()
	_photo_view.texture = nadir_texture
	_photo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_view.custom_minimum_size = Vector2(page_size.x - SIDE_WIDTH - 16.0, page_size.y)
	_photo_view.clip_contents = true
	page.add_child(_photo_view)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo_view.add_child(_flash)
	_photo_caption = Label.new()
	_photo_caption.text = "TABLET_NADIR"
	_photo_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_photo_caption.add_theme_font_size_override("font_size", 20)
	_photo_caption.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	_photo_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	# Fond sombre : légende lisible sur une photo claire (nuages, désert).
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	caption_style.set_corner_radius_all(4)
	caption_style.set_content_margin_all(6)
	_photo_caption.add_theme_stylebox_override("normal", caption_style)
	_photo_caption.position = Vector2(8, 6)
	_photo_view.add_child(_photo_caption)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 10)
	page.add_child(side)
	var shutter := BigRedButton.new()
	shutter.cap_color = Color(0.82, 0.84, 0.86)
	shutter.custom_minimum_size = Vector2(120.0, 112.0)
	shutter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shutter.tooltip_text = "TABLET_PHOTO"
	shutter.pressed.connect(_take_photo)
	side.add_child(shutter)
	var label := Label.new()
	label.text = "TABLET_PHOTO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	side.add_child(label)
	side.add_child(HSeparator.new())
	_gallery_button = Button.new()
	_gallery_button.focus_mode = Control.FOCUS_NONE
	_gallery_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_gallery_button.pressed.connect(func() -> void: _show_photo(-1 if _photo_index >= 0 else _photo_count() - 1))
	side.add_child(_gallery_button)
	var browse := HBoxContainer.new()
	browse.alignment = BoxContainer.ALIGNMENT_CENTER
	browse.add_theme_constant_override("separation", 10)
	side.add_child(browse)
	_previous_button = _make_arrow_button("◀", func() -> void: _show_photo(maxi(_photo_index - 1, 0)))
	_next_button = _make_arrow_button("▶", func() -> void: _show_photo(mini(_photo_index + 1, _photo_count() - 1)))
	browse.add_child(_previous_button)
	browse.add_child(_next_button)
	_show_photo(-1)
	return page


func _make_arrow_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size = Vector2(64.0, 44.0)
	button.pressed.connect(action)
	return button


func _photo_count() -> int:
	return archive.photos.size() if archive else 0


## Affiche la photo index de la galerie, ou la vue en direct (index −1).
func _show_photo(index: int) -> void:
	_photo_index = index if index >= 0 and index < _photo_count() else -1
	var count := _photo_count()
	if _photo_index < 0:
		_photo_view.texture = nadir_texture
		_photo_caption.text = tr("TABLET_NADIR")
	else:
		var photo: Dictionary = archive.photos[_photo_index]
		var footprint: Vector2 = photo.footprint_km
		_photo_view.texture = photo.texture
		_photo_caption.text = tr("TABLET_PHOTO_CAPTION").format({"n": _photo_index + 1, "count": count,
				"date": Time.get_datetime_string_from_unix_time(int(photo.utc_unix), true).substr(0, 16),
				"place": GeoMath.format_lat_lon(photo.lat, photo.lon), "altitude": roundi(photo.altitude_km),
				"width": roundi(footprint.x), "height": roundi(footprint.y)})
	_gallery_button.text = tr("TABLET_LIVE") if _photo_index >= 0 else tr("TABLET_GALLERY").format({"count": count})
	_gallery_button.disabled = count == 0 and _photo_index < 0
	_previous_button.disabled = _photo_index <= 0
	_next_button.disabled = _photo_index < 0 or _photo_index >= count - 1


## Commande de tir, mise à l'échelle pour occuper la page (centrée).
func _build_missile_page(page_size: Vector2) -> Control:
	var page := CenterContainer.new()
	var launch := LaunchControl.new()
	launch.name = "Launch"
	launch.compact_yields = true
	var holder := Control.new()
	holder.add_child(launch)
	page.add_child(holder)
	launch.resized.connect(func() -> void:
		var fit := minf(page_size.x / maxf(launch.size.x, 1.0), page_size.y / maxf(launch.size.y, 1.0))
		launch.scale = Vector2.ONE * fit
		holder.custom_minimum_size = launch.size * fit)
	return page


## Écran de réception (appel prioritaire en cours ou « Aucune alerte »), bandeau au-dessus des boutons, et les 5
## boutons du niveau d'alerte de la station.
func _build_alerts_page(page_size: Vector2) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var screen := PanelContainer.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var screen_style := StyleBoxFlat.new()
	screen_style.bg_color = Color(0.02, 0.035, 0.03)
	screen_style.border_color = PilotDisplay.COLOR_FRAME
	screen_style.set_border_width_all(1)
	screen_style.set_corner_radius_all(6)
	screen_style.set_content_margin_all(16)
	screen.add_theme_stylebox_override("panel", screen_style)
	page.add_child(screen)
	var center := CenterContainer.new()
	screen.add_child(center)
	_call_idle = _make_alert_label("TABLET_ALERT_IDLE", 26, PilotDisplay.COLOR_DIM)
	center.add_child(_call_idle)
	_call_box = VBoxContainer.new()
	_call_box.add_theme_constant_override("separation", 10)
	center.add_child(_call_box)
	_call_box.add_child(_make_alert_label("TABLET_CALL_TITLE", 34, COLOR_CALL))
	_call_from = _make_alert_label("", 24, PilotDisplay.COLOR_TEXT)
	_call_subject = _make_alert_label("", 24, PilotDisplay.COLOR_TEXT)
	_call_time = _make_alert_label("", 22, PilotDisplay.COLOR_DIM)
	for label in [_call_from, _call_subject, _call_time]:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_call_box.add_child(label)
	# Bandeau de l'appel, au-dessus des boutons : orange sur fond sombre, clignotant.
	_call_banner = PanelContainer.new()
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = Color(0.08, 0.04, 0.02)
	banner_style.border_color = COLOR_CALL
	banner_style.set_border_width_all(2)
	banner_style.set_corner_radius_all(4)
	banner_style.set_content_margin_all(6)
	_call_banner.add_theme_stylebox_override("panel", banner_style)
	var banner_text := _make_alert_label("PRIORITY_CALL_BANNER", 17, COLOR_CALL)
	# Texte coupé plutôt que page élargie (traductions longues).
	banner_text.clip_text = true
	banner_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_call_banner.add_child(banner_text)
	page.add_child(_call_banner)
	# Boutons du niveau d'alerte (Station.Alert), répartis sur la largeur.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	page.add_child(buttons)
	for level in ALERT_KEYS.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 1.0
		cell.add_theme_constant_override("separation", 2)
		buttons.add_child(cell)
		var button := BigRedButton.new()
		button.cap_color = ALERT_CAPS[level]
		button.custom_minimum_size = ALERT_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void:
			var station := _station()
			if station:
				station.set_alert(level as Station.Alert))
		cell.add_child(button)
		# Texte traduit dès le départ (la clé brute, plus large, élargirait la page pour de bon).
		var label := _make_alert_label(tr(ALERT_KEYS[level]), 18, PilotDisplay.COLOR_DIM)
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cell.add_child(label)
		_alert_labels.append(label)
	_show_call({})
	return page


func _make_alert_label(key: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = key
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Appel prioritaire (suivi dès qu'il existe : il est créé par le directeur de campagne), clignotement du bandeau et
## niveau d'alerte en cours (étiquette du bouton allumée).
func _update_alerts(delta: float) -> void:
	if _call == null and is_inside_tree():
		_call = get_tree().get_first_node_in_group(PriorityCall.GROUP) as PriorityCall
		if _call:
			_call.call_started.connect(func(call_info: Dictionary) -> void:
				_show_call(call_info)
				show_tab(Tab.ALERTS))
			_call.call_stopped.connect(func() -> void: _show_call({}))
			_show_call(_call.info)
	if current_tab != Tab.ALERTS:
		return
	_blink += delta
	_call_banner.modulate.a = 1.0 if fmod(_blink, BLINK_S * 2.0) < BLINK_S else 0.3
	var station := _station()
	var current := station.get_alert() if station else Station.Alert.NONE
	if current == _shown_alert:
		return
	_shown_alert = current
	for level in _alert_labels.size():
		var label := _alert_labels[level]
		var active := level == current
		label.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT if active else PilotDisplay.COLOR_DIM)
		label.text = ("▲ %s" if active else "%s") % tr(ALERT_KEYS[level])


## Écran de réception : l'appel call_info (from, subject, received_unix), ou « Aucune alerte » s'il est vide.
func _show_call(call_info: Dictionary) -> void:
	var active := not call_info.is_empty()
	_call_idle.visible = not active
	_call_box.visible = active
	_call_banner.visible = active
	if not active:
		return
	_call_from.text = tr("TABLET_CALL_FROM").format({"from": call_info.get("from", "")})
	_call_subject.text = tr("TABLET_CALL_SUBJECT").format({"subject": call_info.get("subject", "")})
	_call_time.text = tr("TABLET_CALL_TIME").format({"time": Time.get_datetime_string_from_unix_time(
			int(call_info.get("received_unix", 0.0))).substr(11, 5)})


func _station() -> Station:
	return get_tree().get_first_node_in_group(Station.GROUP) as Station if is_inside_tree() else null


## Bouton Photo : retour à la vue en direct, flash, et prise de vue par la tablette (photo_requested).
func _take_photo() -> void:
	_show_photo(-1)
	_flash.color.a = 0.9
	create_tween().tween_property(_flash, "color:a", 0.0, FLASH_S)
	photo_requested.emit()


# --- Style ----------------------------------------------------------------------------------------------------------

func _make_tab_button(key: String) -> Button:
	var button := Button.new()
	button.text = key
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	button.add_theme_font_size_override("font_size", 20)
	_style_tab(button, false)
	return button


func _style_tab(button: Button, active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TAB_ACTIVE if active else COLOR_TAB
	style.border_color = PilotDisplay.COLOR_TEXT if active else PilotDisplay.COLOR_FRAME
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	var text_color := PilotDisplay.COLOR_TEXT if active else PilotDisplay.COLOR_DIM
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, text_color)


func _hud() -> Hud:
	return get_tree().get_first_node_in_group(Hud.GROUP) as Hud if is_inside_tree() else null
