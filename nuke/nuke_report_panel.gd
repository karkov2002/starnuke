class_name NukeReportPanel
extends CanvasLayer
## « Bilan des explosions » (nœud NukeReport de scenes/orbit_view.tscn) : affiché sur l'écran mural SCREEN_NODE du
## module Commande (en face de la télévision), dessiné dans un SubViewport appliqué à la dalle (shader des écrans
## d'ambiance, shaders/tech_screen.gdshader). Affichage seulement : le bilan (pertes cumulées par pays, à l'instant
## présent de chaque explosion, et projection) vient de NukeTally. Rafraîchi toutes les REFRESH_S.
## Contenu : titre, résumé (explosions, morts, blessés), projection, tableau par pays (pays, explosions, morts,
## blessés, part de la population ; ⚡ et couleur ambre : black-out national), note sur le modèle. Sans explosion :
## « Aucune explosion ». Quand la liste déborde, elle défile seule (pas de souris sur un écran mural) : descente lente,
## pause en bas, retour en haut.
## L'image n'est rendue que si la caméra est à moins de RENDER_DISTANCE ; écran éteint avec « plus de lumière »
## (Station.get_blackout). (Ancienne fenêtre déplaçable à l'écran : remplacée par cet écran.)

const SCREEN_NODE := "Interactif_Ecran_02"
const VIEWPORT_SIZE := Vector2i(1280, 800)
const RENDER_DISTANCE := 12.0
## Colonnes : titre et largeur minimale (0 : la colonne du nom prend la place restante ; les autres sont alignées à
## droite).
const COLUMNS: Array[Dictionary] = [
	{"title": "REPORT_COUNTRY", "width": 0.0},
	{"title": "REPORT_EXPLOSIONS", "width": 90.0},
	{"title": "REPORT_KILLED", "width": 210.0},
	{"title": "REPORT_INJURED", "width": 210.0},
	{"title": "REPORT_POPULATION", "width": 170.0},
]
const COLORS: Array[Color] = [Color(0.85, 0.95, 0.88), Color(0.85, 0.95, 0.88), Color(1.0, 0.45, 0.4),
		Color(0.98, 0.78, 0.45), Color(0.6, 0.9, 0.75)]
const TITLE_COLOR := Color(0.35, 1.0, 0.6)
const DIM_COLOR := Color(0.45, 0.65, 0.55)
const BLACKOUT_COLOR := Color(1.0, 0.85, 0.5)
const FONT_SIZE := 38
const REFRESH_S := 0.5
## Défilement de la liste (px/s) et pauses en haut et en bas (s).
const SCROLL_SPEED := 30.0
const SCROLL_PAUSE_S := 3.0

@export var launcher_path: NodePath = ^"../NukeLauncher"
@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var screen_energy := 1.1

var _launcher: NukeLauncher
var _station: Station
## Dalle de l'écran mural (StationScreen : matériau d'affichage, luminosité).
var _screen: StationScreen
var _viewport: SubViewport
var _summary: Label
var _projection: Label
var _scroll: ScrollContainer
var _rows: GridContainer
var _refresh_left := 0.0
var _scroll_pos := 0.0
var _scroll_wait := SCROLL_PAUSE_S
## Lignes affichées (codes des pays, dans l'ordre) et leurs étiquettes : mises à jour sur place tant que l'ordre ne
## change pas.
var _row_order: Array[String] = []
var _row_labels := {}
## Dernier état affiché (1 : aucune explosion, 0 : bilan, -1 : rien encore).
var _shown_none := -1
## Code de l'État souverain de chaque pays (CountryMask), rempli au premier besoin.
var _sovereigns := {}


func _ready() -> void:
	_launcher = get_node_or_null(launcher_path) as NukeLauncher
	_station = get_node_or_null(station_path) as Station
	if _launcher:
		_launcher.detonated.connect(func(_effect: NukeEffect) -> void: _refresh_left = 0.0)
	_screen = StationScreen.find(_station, SCREEN_NODE) if _station else null
	if _screen == null:
		push_error("NukeReportPanel : écran %s (ou sa dalle) introuvable" % SCREEN_NODE)
		set_process(false)
		return
	# Image de taille fixe (mise en page en pixels), étirée sur la dalle.
	_viewport = SubViewport.new()
	_viewport.name = "Screen"
	_viewport.size = VIEWPORT_SIZE
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_build()
	_screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(), {"scan_depth": 0.06})


func _process(delta: float) -> void:
	_screen.set_energy(screen_energy * (1.0 - _station.get_blackout()))
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and camera.global_position.distance_to(_screen.global_position()) < RENDER_DISTANCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
	if not near:
		return
	_auto_scroll(delta)
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_S
	var effects: Array[NukeEffect] = _launcher.get_effects() if _launcher else []
	_show(NukeTally.compute(effects), effects.is_empty())


## Contenu : titre, résumé, projection, en-tête des colonnes, liste défilante, note sur le modèle.
func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.01, 0.03, 0.025)
	background.size = Vector2(VIEWPORT_SIZE)
	_viewport.add_child(background)
	var margin := MarginContainer.new()
	margin.size = Vector2(VIEWPORT_SIZE)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	_viewport.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	var title := _label("REPORT_TITLE", 50, TITLE_COLOR, true)
	title.uppercase = true
	body.add_child(title)
	var rule := ColorRect.new()
	rule.color = TITLE_COLOR.darkened(0.4)
	rule.custom_minimum_size.y = 2.0
	body.add_child(rule)
	# Textes composés (tr() + format) : pas de traduction automatique.
	_summary = _label("", 42, COLORS[0])
	body.add_child(_summary)
	_projection = _label("", 30, DIM_COLOR)
	body.add_child(_projection)
	var header := _make_grid()
	for column_def: Dictionary in COLUMNS:
		header.add_child(_make_cell(column_def.title, column_def.width, TITLE_COLOR.darkened(0.15), true))
	body.add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body.add_child(_scroll)
	_rows = _make_grid()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	var note := _label("REPORT_NOTE", 22, DIM_COLOR, true)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = VIEWPORT_SIZE.x - 72.0
	body.add_child(note)




func _show(tally: Dictionary, none: bool) -> void:
	var count: int = tally.count
	var style := NukeReportText.number_style(TranslationServer.get_locale())
	if none:
		_summary.text = tr("REPORT_NONE")
		_projection.text = ""
	else:
		_summary.text = tr("REPORT_SUMMARY_ONE" if count == 1 else "REPORT_SUMMARY_MANY").format({"count": count,
				"killed": NumberFormat.count(tally.killed, style.thousands),
				"injured": NumberFormat.count(tally.injured, style.thousands)})
		_projection.text = tr("REPORT_PROJECTION").format({"days": roundi(NukeFallout.HORIZON_H / 24.0),
				"killed": NumberFormat.count(tally.final_killed, style.thousands)})
		if tally.pending > 0:
			_projection.text += " " + tr("REPORT_PENDING")
	var codes: Array[String] = []
	for entry: Dictionary in tally.countries:
		codes.append(entry.code)
	if codes != _row_order or int(none) != _shown_none:
		_shown_none = int(none)
		_rebuild_rows(codes, none)
	for entry: Dictionary in tally.countries:
		var labels: Array = _row_labels[entry.code]
		labels[0].text = _country_name(entry.code, entry.label) + ("  ⚡" if entry.blackout else "")
		labels[0].add_theme_color_override("font_color", BLACKOUT_COLOR if entry.blackout else COLORS[0])
		labels[1].text = str(entry.explosions) if entry.explosions > 0 else "—"
		labels[2].text = NumberFormat.count(entry.killed, style.thousands)
		labels[3].text = NumberFormat.count(entry.injured, style.thousands)
		labels[4].text = NukeReportText.share(entry.killed, entry.pop_est, style)


## Liste trop longue pour l'écran : descente lente, pause en bas, retour en haut, pause.
func _auto_scroll(delta: float) -> void:
	var overflow := _rows.size.y - _scroll.size.y
	if overflow <= 0.0:
		_scroll_pos = 0.0
		_scroll.scroll_vertical = 0
		return
	_scroll_wait -= delta
	if _scroll_wait > 0.0:
		return
	_scroll_pos += SCROLL_SPEED * delta
	if _scroll_pos >= overflow:
		_scroll_pos = overflow
		_scroll.scroll_vertical = roundi(_scroll_pos)
		_scroll_pos = -1.0 # retour en haut après la pause
		_scroll_wait = SCROLL_PAUSE_S
		return
	if _scroll_pos < 0.0:
		_scroll_pos = 0.0
		_scroll_wait = SCROLL_PAUSE_S
	_scroll.scroll_vertical = roundi(_scroll_pos)


## Nom du pays dans la langue du jeu (locale/countries.csv : COUNTRY_<code>), suivi de son État souverain s'il en
## dépend (SOVEREIGN_<code>) ; « hors pays » sans code ; fallback (nom français des données) si la clé manque.
func _country_name(code: String, fallback: String) -> String:
	if code.is_empty():
		return tr("REPORT_OFFSHORE")
	var key := "COUNTRY_" + code
	var label := tr(key)
	if label == key:
		return fallback
	if _sovereigns.is_empty() and CountryMask.get_mask():
		for c: Dictionary in CountryMask.get_mask().countries:
			_sovereigns[c.code] = c.sovereign_code
	var sovereign_key := "SOVEREIGN_" + String(_sovereigns.get(code, ""))
	var sovereign := tr(sovereign_key)
	if sovereign != sovereign_key and sovereign != label:
		label += " (%s)" % sovereign
	return label


## Recrée les lignes (une par pays, dans l'ordre donné) ; leurs textes sont posés par _show.
func _rebuild_rows(codes: Array[String], none: bool) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_labels.clear()
	_row_order = codes.duplicate()
	_scroll_pos = 0.0
	_scroll_wait = SCROLL_PAUSE_S
	if codes.is_empty() and not none:
		_rows.add_child(_make_cell("REPORT_NO_COUNTRY", COLUMNS[0].width, DIM_COLOR, true))
	for code in codes:
		var labels := []
		for i in COLUMNS.size():
			var cell := _make_cell("", COLUMNS[i].width, COLORS[i])
			_rows.add_child(cell)
			labels.append(cell)
		_row_labels[code] = labels


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## Cellule : width > 0 = colonne de chiffres alignée à droite ; 0 = colonne du nom (extensible, texte tronqué).
## translate : text est une clé de langue (titres) ; sinon texte composé, sans traduction automatique.
func _make_cell(text: String, width: float, color: Color, translate := false) -> Label:
	var label := _label(text, FONT_SIZE, color, translate)
	if width > 0.0:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = width
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 330.0
	return label


func _label(text: String, font_size: int, color: Color, translate := false) -> Label:
	var label := Label.new()
	label.text = text
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
