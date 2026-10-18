class_name TabletDisplay
extends Control
## Interface de l'écran de la tablette (scripts/tablet.gd), dessinée dans son SubViewport, construite en code :
## - en haut, la date et l'heure UTC et l'heure solaire du point survolé ;
## - au milieu, une copie réduite de la carte du poste de pilotage (OrbitalMap : trace au sol, station, point de
##   manœuvre et trace fantôme), de MAP_MAX_LAT_DEG nord à sud pour être plus large, et, dans une colonne étroite à
##   droite, la commande de poussée de la manœuvre prévue (BurnControl vertical : compte à rebours, gros bouton BURN
##   bleu et jauge verticale) ;
## - en bas, la commande de tir (LaunchControl : 48 silos, petits boutons de puissance, gros bouton rouge), agrandie de
##   LAUNCH_SCALE (ses boutons ont une taille fixe en pixels).
## Taille : celle du SubViewport (proportions de la dalle de la tablette).

const MARGIN := 18.0
const FONT_SIZE := 22
const LAUNCH_SCALE := 1.4
const MAP_MAX_LAT_DEG := 70.0
## Hauteur maximale de la carte (part de la hauteur de l'écran) ; elle est réduite pour laisser toute la commande de
## tir à l'écran.
const MAP_HEIGHT_SHARE := 0.58
## Marge supplémentaire à droite (pixels) : le pouce de la main qui tient la tablette, posé sur la bordure de
## droite, mord sur le bord de l'écran.
const THUMB_PADDING := 30.0

var orbit: OrbitSimulation
var flight_computer: FlightComputer

var _clock: Label


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
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_clock = Label.new()
	_clock.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_clock.add_theme_font_size_override("font_size", 28)
	_clock.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	column.add_child(_clock)

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 16)
	column.add_child(middle)
	var map_height := size.y * MAP_HEIGHT_SHARE
	var map := OrbitalMap.new()
	map.orbit = orbit
	map.flight_computer = flight_computer
	map.max_lat_deg = MAP_MAX_LAT_DEG
	map.size = Vector2(map_height * OrbitalMap.aspect_for(MAP_MAX_LAT_DEG), map_height)
	map.custom_minimum_size = map.size
	middle.add_child(map)
	var burn := BurnControl.new()
	burn.flight_computer = flight_computer
	burn.large = true
	burn.column_layout = true
	burn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	burn.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(burn)

	var separator := HSeparator.new()
	column.add_child(separator)
	# Commande de tir agrandie : un conteneur à sa taille agrandie, le panneau mis à l'échelle dedans.
	var launch := LaunchControl.new()
	launch.name = "Launch"
	launch.compact_yields = true
	launch.scale = Vector2.ONE * LAUNCH_SCALE
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(launch)
	column.add_child(holder)
	# La carte prend la hauteur que laisse la commande de tir (au plus MAP_HEIGHT_SHARE de l'écran) : à hauteur fixe,
	# la commande débordait sous le bas de la dalle (dernière rangée de silos et bouton rouge coupés).
	var fit_map := func() -> void:
		holder.custom_minimum_size = launch.size * LAUNCH_SCALE
		var spacing := float(column.get_theme_constant("separation")) * 3.0
		# Hauteur prévue de la colonne (un conteneur grandit pour loger son contenu : sa taille courante ne compte pas).
		var free := column_size.y - _clock.get_combined_minimum_size().y - holder.custom_minimum_size.y \
				- separator.get_combined_minimum_size().y - spacing
		var height := clampf(free, size.y * 0.3, size.y * MAP_HEIGHT_SHARE)
		map.size = Vector2(height * OrbitalMap.aspect_for(MAP_MAX_LAT_DEG), height)
		map.custom_minimum_size = map.size
		column.size = column_size
	launch.resized.connect(fit_map)
	fit_map.call_deferred()


func _process(_delta: float) -> void:
	if orbit == null:
		return
	var now := orbit.get_utc_datetime()
	var point := orbit.get_subsatellite_point()
	var date := tr("HUD_DATE").format({"day": "%02d" % now.day, "month": "%02d" % now.month, "year": now.year})
	var solar := orbit.get_local_solar_hour(point.y)
	_clock.text = tr("HUD_TIME").format({"date": date, "time": "%02d:%02d:%02d" % [now.hour, now.minute, now.second],
			"solar": "%02d:%02d" % [floori(solar), floori(solar * 60.0) % 60]})
