class_name TabletDisplay
extends Control
## Interface de l'écran de la tablette (scripts/tablet.gd), dessinée dans son SubViewport, construite en code :
## - en haut, une barre d'onglets cliquables (Pilotage, Photographie, Tir de missile, Alertes) et, à droite, le bouton
##   « HUD : On / Off » (affichage en surimpression dans la cupola, Hud.overlay_enabled) ; dessous, la date et l'heure
##   UTC et l'heure solaire du point survolé ;
## - onglet Pilotage : la carte du poste de pilotage en réduit (OrbitalMap : trace au sol, station, point de manœuvre
##   et trace fantôme), de MAP_MAX_LAT_DEG nord à sud (comme au poste), et, dans une colonne à droite, la commande
##   de poussée (BurnControl en colonne : compte à rebours, gros bouton BURN bleu, jauge verticale) ;
## - onglet Photographie : PhotoPage (vue au nadir en direct, bouton Photo, galerie) ;
## - onglet Tir de missile : la commande de tir (LaunchControl : 48 silos, puissance, gros bouton rouge), agrandie
##   pour occuper la page (ses boutons ont une taille fixe en pixels) ;
## - onglet Alertes : AlertsPage (récepteur des appels prioritaires, boutons du niveau d'alerte) ; à l'arrivée d'un
##   appel, la tablette passe sur cet onglet.
## Taille : celle du SubViewport (proportions de la dalle de la tablette).

signal tab_changed(tab: int)
## Bouton Photo pressé : la tablette prend la photo (scripts/tablet.gd).
signal photo_requested
## Capteur de la page Photographie : infrarouge (vrai) ou visible (PhotoPage.infrared_changed).
signal infrared_changed(infrared: bool)

enum Tab { PILOT, PHOTO, MISSILE, ALERTS }

const MARGIN := 18.0
const FONT_SIZE := 22
const MAP_MAX_LAT_DEG := OrbitalMap.MAX_LAT_DEG
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

var orbit: OrbitSimulation
var flight_computer: FlightComputer
## Image de la vue au nadir (NadirCamera), fixée avant l'ajout à l'arbre.
var nadir_texture: Texture2D
## Photos prises (galerie de l'onglet Photographie) ; réglé par la tablette, relayé à la page.
var archive: PhotoArchive:
	set(value):
		archive = value
		if _photo_page:
			_photo_page.archive = value
var current_tab := Tab.PILOT

var _clock: Label
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _hud_button: Button
var _photo_page: PhotoPage
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
	_clock.add_theme_color_override("font_color", ScreenPalette.TEXT)
	column.add_child(_clock)

	# Pages (une seule visible), dans la hauteur restante (calculée : un conteneur grandit pour loger son contenu,
	# sa taille courante ne compte pas).
	var page_size := Vector2(column_size.x, column_size.y - BAR_HEIGHT - CLOCK_HEIGHT - 2.0 * SPACING)
	var stack := Control.new()
	stack.custom_minimum_size = page_size
	stack.clip_contents = true
	column.add_child(stack)
	_photo_page = PhotoPage.new(page_size, SIDE_WIDTH)
	_photo_page.nadir_texture = nadir_texture
	_photo_page.archive = archive
	_photo_page.photo_requested.connect(photo_requested.emit)
	_photo_page.infrared_changed.connect(infrared_changed.emit)
	var alerts := AlertsPage.new()
	alerts.call_started.connect(func() -> void: show_tab(Tab.ALERTS))
	_pages.append(_build_pilot_page(page_size))
	_pages.append(_photo_page)
	_pages.append(_build_missile_page(page_size))
	_pages.append(alerts)
	for page in _pages:
		page.size = page_size
		stack.add_child(page)
	show_tab(current_tab)


## Caméra extérieure en état de marche (StationEquipments) : sinon « HORS LIGNE » sur la page Photographie.
func set_camera_online(online: bool) -> void:
	if _photo_page:
		_photo_page.camera_online = online


func show_tab(tab: int) -> void:
	current_tab = tab as Tab
	for i in _pages.size():
		_pages[i].visible = i == tab
		_tab_buttons[i].set_pressed_no_signal(i == tab)
		_style_tab(_tab_buttons[i], i == tab)
	tab_changed.emit(tab)


## Horloge et état du HUD rafraîchis à refresh_hz (textes formatés : inutile à chaque image).
@export var refresh_hz := 5.0
var _since := INF
var _hud_node: Hud


func _process(delta: float) -> void:
	_since += delta
	if _since < 1.0 / refresh_hz:
		return
	_since = 0.0
	if _hud_node == null:
		_hud_node = _hud()
	var on := _hud_node == null or _hud_node.overlay_enabled
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
	map.show_hover_coordinates = false
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
	var style := UiKit.flat_box(ScreenPalette.TAB_ACTIVE if active else ScreenPalette.TAB,
			ScreenPalette.TEXT if active else ScreenPalette.FRAME, 2 if active else 1, 6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	var text_color := ScreenPalette.TEXT if active else ScreenPalette.DIM
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, text_color)


func _hud() -> Hud:
	return get_tree().get_first_node_in_group(Hud.GROUP) as Hud if is_inside_tree() else null
