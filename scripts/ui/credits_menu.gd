extends Control
## Écran des crédits (scenes/ui/credits_menu.tscn), ouvert par l'écran de démarrage (bouton « Crédits »), comme les
## paramètres : fond translucide sur le décor, titre, deux onglets, bouton « Retour » (ou Échap) qui émet closed.
## - Références : la bibliographie du projet (README, « Bibliographie ») par rubrique ;
## - Crédits : auteurs, moteur et outils, données et images importées avec leur licence et l'attribution demandée.
## Textes : fichier de langue locale/credits.csv (5 langues ; les références gardent leur titre d'origine, seul leur
## usage est traduit). Chaque page est un texte défilant (RichTextLabel, BBCode des traductions) ; les liens s'ouvrent
## dans le navigateur.

signal closed

const PANEL_SIZE := Vector2(1100.0, 600.0)
## Rubriques : [clé du titre, [clés des entrées]].
const REFERENCES: Array[Array] = [
	["CREDITS_REF_NUKE", ["CREDITS_REF_GLASSTONE", "CREDITS_REF_ADAMSKY", "CREDITS_REF_HAWTHORNE", "CREDITS_REF_OTA",
			"CREDITS_REF_BRODE", "CREDITS_REF_HANIFEN", "CREDITS_REF_WAY", "CREDITS_REF_POSTOL", "CREDITS_REF_TOON",
			"CREDITS_REF_ANDREAE", "CREDITS_REF_WERF"]],
	["CREDITS_REF_GRID", ["CREDITS_REF_GPPD", "CREDITS_REF_BYERS", "CREDITS_REF_BLACKOUT_2003",
			"CREDITS_REF_BLACKOUT_2025"]],
	["CREDITS_REF_SKY", ["CREDITS_REF_BRUNETON", "CREDITS_REF_HILLAIRE", "CREDITS_REF_HENYEY", "CREDITS_REF_WRENNINGE",
			"CREDITS_REF_BEER"]],
	["CREDITS_REF_ORBIT", ["CREDITS_REF_ALMANAC", "CREDITS_REF_CAPITAINE", "CREDITS_REF_IERS", "CREDITS_REF_WGS84",
			"CREDITS_REF_VALLADO"]],
	["CREDITS_REF_EARTH", ["CREDITS_REF_BLUE_MARBLE", "CREDITS_REF_BLACK_MARBLE", "CREDITS_REF_VIIRS",
			"CREDITS_REF_CLOUDS", "CREDITS_REF_STARS", "CREDITS_REF_GFS", "CREDITS_REF_GRIB", "CREDITS_REF_NE_OCEAN",
			"CREDITS_REF_GHS_POP", "CREDITS_REF_NE_COUNTRIES", "CREDITS_REF_MAKEHUMAN", "CREDITS_REF_NE_MAP"]],
]
## Rubriques des crédits, même forme.
const CREDITS: Array[Array] = [
	["CREDITS_AUTHORS", ["CREDITS_AUTHORS_TEXT"]],
	["CREDITS_TOOLS", ["CREDITS_TOOL_GODOT", "CREDITS_TOOL_JOLT", "CREDITS_TOOL_GLASSTONE", "CREDITS_TOOL_BLENDER",
			"CREDITS_TOOL_MPFB", "CREDITS_TOOL_FFMPEG"]],
	["CREDITS_DATA", ["CREDITS_DATA_NASA", "CREDITS_DATA_GIBS", "CREDITS_DATA_STARS", "CREDITS_DATA_NOAA",
			"CREDITS_DATA_NATURAL_EARTH", "CREDITS_DATA_GHS_POP", "CREDITS_DATA_GPPD", "CREDITS_DATA_WIKIDATA",
			"CREDITS_DATA_CLDR", "CREDITS_DATA_FLAGS"]],
	["CREDITS_ASSETS", ["CREDITS_ASSET_AMBIENTCG", "CREDITS_ASSET_MAKEHUMAN", "CREDITS_ASSET_MUSIC",
			"CREDITS_ASSET_OWN"]],
	["CREDITS_NOTICE", ["CREDITS_NOTICE_TEXT"]],
]
const COLOR_HEADING := Color(0.45, 0.72, 1.0)

var _pages: Array[RichTextLabel] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.75)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = "CREDITS_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = PANEL_SIZE
	tabs.add_theme_font_size_override("font_size", 22)
	column.add_child(tabs)
	for key in ["CREDITS_TAB_REFERENCES", "CREDITS_TAB_CREDITS"]:
		var margin := MarginContainer.new()
		margin.name = key
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 24)
		tabs.add_child(margin)
		tabs.set_tab_title(tabs.get_tab_count() - 1, key)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.selection_enabled = true
		text.scroll_active = true
		text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		text.add_theme_font_size_override("normal_font_size", 17)
		text.add_theme_font_size_override("bold_font_size", 17)
		text.add_theme_font_size_override("italics_font_size", 17)
		text.add_theme_color_override("default_color", Color(0.85, 0.87, 0.9))
		text.add_theme_constant_override("paragraph_separation", 9)
		text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
		margin.add_child(text)
		_pages.append(text)
	_fill()

	var back := Button.new()
	back.text = "SETTINGS_BACK"
	back.custom_minimum_size = Vector2(220.0, 52.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func() -> void: closed.emit())
	column.add_child(back)
	back.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_fill()


## Texte des deux pages dans la langue du jeu : titre de rubrique, puis ses entrées.
func _fill() -> void:
	for page in 2:
		var sections: Array[Array] = REFERENCES if page == 0 else CREDITS
		var text := PackedStringArray()
		for section: Array in sections:
			text.append("[font_size=24][color=#%s][b]%s[/b][/color][/font_size]" % [COLOR_HEADING.to_html(false),
					tr(section[0])])
			for key: String in section[1]:
				text.append("[indent]%s[/indent]" % tr(key))
			text.append("")
		_pages[page].text = "\n".join(text)
