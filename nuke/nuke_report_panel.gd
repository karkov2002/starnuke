class_name NukeReportPanel
extends CanvasLayer
## Fenêtre « Bilan des explosions » (nœud NukeReport de scenes/orbit_view.tscn) : affichage seulement. Le bilan
## (pertes cumulées par pays, à l'instant présent de chaque explosion, et projection) vient de NukeTally ; la fenêtre
## déplaçable de DraggableWindow. Rafraîchie toutes les REFRESH_S. Elle apparaît au premier tir, en haut à droite, et
## disparaît quand il n'y a plus d'explosion (« Effacer » du panneau de debug) ; une fois déplacée, elle garde sa place.

const WIDTH := 560.0
## Colonnes : titre et largeur minimale (0 : la colonne du nom prend la place restante ; les autres sont alignées à
## droite).
const COLUMNS: Array[Dictionary] = [
	{"title": "REPORT_COUNTRY", "width": 0.0},
	{"title": "REPORT_EXPLOSIONS", "width": 44.0},
	{"title": "REPORT_KILLED", "width": 92.0},
	{"title": "REPORT_INJURED", "width": 92.0},
	{"title": "REPORT_POPULATION", "width": 92.0},
]
const COLORS: Array[Color] = [Color(0.92, 0.94, 0.97), Color(0.95, 0.95, 1.0), Color(1.0, 0.55, 0.5),
		Color(0.95, 0.8, 0.55), Color(0.8, 0.85, 0.9)]
const BLACKOUT_COLOR := Color(1.0, 0.85, 0.5)
const LIST_HEIGHT := 260.0
const REFRESH_S := 0.5

@export var launcher_path: NodePath = ^"../NukeLauncher"

var _launcher: NukeLauncher
var _window: DraggableWindow
var _summary: Label
var _projection: Label
var _rows: GridContainer
var _placed := false
var _refresh_left := 0.0
## Lignes affichées (codes des pays, dans l'ordre) et leurs étiquettes : mises à jour sur place tant que l'ordre ne
## change pas (pas de reconstruction à chaque rafraîchissement : les infobulles et le défilement restent stables).
var _row_order: Array[String] = []
var _row_labels := {}
## Code de l'État souverain de chaque pays (CountryMask), rempli au premier besoin.
var _sovereigns := {}


func _ready() -> void:
	_launcher = get_node_or_null(launcher_path) as NukeLauncher
	_build()
	_window.visible = false
	if _launcher:
		_launcher.detonated.connect(func(_effect: NukeEffect) -> void: _refresh_left = 0.0)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0 or _launcher == null:
		return
	_refresh_left = REFRESH_S
	var effects := _launcher.get_effects()
	_window.visible = not effects.is_empty()
	if not _window.visible:
		return
	_show(NukeTally.compute(effects))
	# Position de départ au premier affichage seulement.
	if not _placed:
		_placed = true
		_window.place_top_right.call_deferred() # après le recalcul de la taille


## Contenu : résumé, projection, en-tête des colonnes, liste défilante, note sur le modèle.
func _build() -> void:
	_window = DraggableWindow.new("REPORT_TITLE", WIDTH)
	_window.name = "Window"
	add_child(_window)
	var body := _window.body
	# Textes composés (tr() + format) : pas de traduction automatique.
	_summary = Label.new()
	_summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	body.add_child(_summary)
	_projection = Label.new()
	_projection.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_projection.add_theme_font_size_override("font_size", 13)
	_projection.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	body.add_child(_projection)

	var header := _make_grid()
	for column_def: Dictionary in COLUMNS:
		var heading := _make_cell(column_def.title, column_def.width, Color(0.65, 0.75, 0.9), true)
		if column_def.title == "REPORT_EXPLOSIONS":
			heading.tooltip_text = "REPORT_EXPLOSIONS_TOOLTIP"
			heading.mouse_filter = Control.MOUSE_FILTER_PASS
		header.add_child(heading)
	body.add_child(header)
	body.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = _make_grid()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var note := Label.new()
	note.text = "REPORT_NOTE"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Largeur imposée : sans elle, le retour à la ligne est calculé sur une largeur nulle et la fenêtre s'étire.
	note.custom_minimum_size.x = WIDTH - 24.0
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	body.add_child(note)


func _show(tally: Dictionary) -> void:
	var count: int = tally.count
	var style := NukeReportText.number_style(TranslationServer.get_locale())
	_summary.text = tr("REPORT_SUMMARY_ONE" if count == 1 else "REPORT_SUMMARY_MANY").format({"count": count,
			"killed": NukeReportText.count(tally.killed, style.thousands),
			"injured": NukeReportText.count(tally.injured, style.thousands)})
	_projection.text = tr("REPORT_PROJECTION").format({"days": roundi(NukeFallout.HORIZON_H / 24.0),
			"killed": NukeReportText.count(tally.final_killed, style.thousands)})
	if tally.pending > 0:
		_projection.text += " " + tr("REPORT_PENDING")
	var codes: Array[String] = []
	for entry: Dictionary in tally.countries:
		codes.append(entry.code)
	if codes != _row_order:
		_rebuild_rows(codes)
	for entry: Dictionary in tally.countries:
		var labels: Array = _row_labels[entry.code]
		labels[0].text = _country_name(entry.code, entry.label) + ("  ⚡" if entry.blackout else "")
		labels[0].add_theme_color_override("font_color", BLACKOUT_COLOR if entry.blackout else COLORS[0])
		labels[0].tooltip_text = tr("REPORT_BLACKOUT_TOOLTIP") if entry.blackout else ""
		labels[1].text = str(entry.explosions) if entry.explosions > 0 else "—"
		labels[2].text = NukeReportText.count(entry.killed, style.thousands)
		labels[3].text = NukeReportText.count(entry.injured, style.thousands)
		labels[4].text = NukeReportText.share(entry.killed, entry.pop_est, style)


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
func _rebuild_rows(codes: Array[String]) -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_labels.clear()
	_row_order = codes.duplicate()
	if codes.is_empty():
		_rows.add_child(_make_cell("REPORT_NO_COUNTRY", COLUMNS[0].width, Color(0.7, 0.75, 0.8), true))
	for code in codes:
		var labels := []
		for i in COLUMNS.size():
			var cell := _make_cell("", COLUMNS[i].width, COLORS[i])
			if i == 0:
				cell.mouse_filter = Control.MOUSE_FILTER_PASS
			_rows.add_child(cell)
			labels.append(cell)
		_row_labels[code] = labels
	_window.reset_size.call_deferred()


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## Cellule : width > 0 = colonne de chiffres alignée à droite ; 0 = colonne du nom (extensible, texte tronqué).
## translate : text est une clé de langue (titres) ; sinon texte composé, sans traduction automatique.
func _make_cell(text: String, width: float, color: Color, translate := false) -> Label:
	var label := Label.new()
	label.text = text
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	if width > 0.0:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size.x = width
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 150.0
	return label
