extends CanvasLayer
## Bilan des explosions (nœud NukeReport de scenes/orbit_view.tscn) : fenêtre déplaçable par sa barre de titre,
## comme sous Windows, avec la liste défilante des pays touchés et de leurs pertes cumulées sur toutes les explosions
## en cours, **à l'instant présent** (NukeCasualties.snapshot au temps de chaque explosion : flash, onde de choc,
## décès des blessés, puis retombées radioactives sur plusieurs jours, NukeFallout), rafraîchies toutes les REFRESH_S,
## et la projection finale. Pays sous black-out national (NukeEffect.blackout)
## signalés. La fenêtre apparaît au premier tir et disparaît quand il n'y a plus d'explosion (« Effacer » du panneau
## de debug) ; le bouton « — » de la barre de titre la replie.

const WIDTH := 560.0
## Colonnes : titre et largeur minimale (0 : la colonne du nom prend la place restante ; les autres sont alignées à
## droite).
const COLUMNS: Array[Dictionary] = [
	{"title": "Pays", "width": 0.0},
	{"title": "Expl.", "width": 44.0},
	{"title": "Morts", "width": 92.0},
	{"title": "Blessés", "width": 92.0},
	{"title": "Population", "width": 92.0},
]
const LIST_HEIGHT := 260.0
## Marge minimale entre la fenêtre et le bord de l'écran quand on la déplace.
const SCREEN_MARGIN := 8.0
const REFRESH_S := 0.5

@export var launcher_path: NodePath = ^"../NukeLauncher"

var _launcher: NukeLauncher
var _window: PanelContainer
var _title_bar: PanelContainer
var _summary: Label
var _projection: Label
var _body: VBoxContainer
var _rows: GridContainer
var _collapse: Button
var _dragging := false
var _placed := false
var _signature := ""
var _refresh_left := 0.0
## Lignes affichées (codes des pays, dans l'ordre) et leurs étiquettes : mises à jour sur place tant que l'ordre ne
## change pas (pas de reconstruction à chaque rafraîchissement : les infobulles et le défilement restent stables).
var _row_order: Array[String] = []
var _row_labels := {}


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
	# Les pertes évoluent avec le temps de chaque explosion : rafraîchissement continu ; la signature (liste des
	# explosions) ne sert qu'à afficher ou masquer la fenêtre.
	var ids: Array[String] = []
	for effect in effects:
		ids.append(str(effect.get_instance_id()))
	var signature := ",".join(ids)
	if signature != _signature:
		_signature = signature
		_window.visible = not effects.is_empty()
	if _window.visible:
		_fill(effects)
	# Position de départ au premier affichage seulement : ensuite, la fenêtre reste où on l'a posée.
	if not _placed and _window.visible:
		_placed = true
		_place_default.call_deferred() # après le recalcul de la taille (_fill)


## Fenêtre : barre de titre (déplacement, repli), résumé, en-tête des colonnes, liste défilante.
func _build() -> void:
	_window = PanelContainer.new()
	_window.name = "Window"
	_window.custom_minimum_size.x = WIDTH
	_window.add_theme_stylebox_override("panel", _make_style(Color(0.05, 0.07, 0.1, 0.82), 0))
	add_child(_window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_window.add_child(column)

	_title_bar = PanelContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.add_theme_stylebox_override("panel", _make_style(Color(0.35, 0.08, 0.06, 0.95), 8))
	_title_bar.gui_input.connect(_on_title_input)
	column.add_child(_title_bar)
	var title_row := HBoxContainer.new()
	_title_bar.add_child(title_row)
	var title := Label.new()
	title.text = "Bilan des explosions"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)
	_collapse = Button.new()
	_collapse.text = "—"
	_collapse.flat = true
	_collapse.focus_mode = Control.FOCUS_NONE
	_collapse.tooltip_text = "Replier / déplier"
	_collapse.pressed.connect(func() -> void:
		_body.visible = not _body.visible
		_collapse.text = "—" if _body.visible else "+"
		_window.reset_size())
	title_row.add_child(_collapse)

	var body_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 12)
	column.add_child(body_margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	body_margin.add_child(_body)
	_summary = Label.new()
	_body.add_child(_summary)
	_projection = Label.new()
	_projection.add_theme_font_size_override("font_size", 13)
	_projection.add_theme_color_override("font_color", Color(0.75, 0.8, 0.88))
	_body.add_child(_projection)

	var header := _make_grid()
	for column_def: Dictionary in COLUMNS:
		var heading := _make_cell(column_def.title, column_def.width, Color(0.65, 0.75, 0.9))
		if column_def.title == "Expl.":
			heading.tooltip_text = "Explosions dont le point zéro est sur le territoire du pays"
			heading.mouse_filter = Control.MOUSE_FILTER_PASS
		header.add_child(heading)
	_body.add_child(header)
	_body.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = LIST_HEIGHT
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_rows = _make_grid()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var note := Label.new()
	note.text = "Pertes immédiates (souffle, chaleur, rayonnement initial ; OTA 1979, population 2030). " \
			+ "Retombées non comptées."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Largeur imposée : sans elle, le retour à la ligne est calculé sur une largeur nulle et la fenêtre s'étire.
	note.custom_minimum_size.x = WIDTH - 24.0
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	_body.add_child(note)


## Cumul par pays sur toutes les explosions, à l'instant présent, trié par morts décroissants. Colonne « Expl. » :
## explosions dont le point zéro est sur le territoire du pays (une explosion frontalière fait aussi des victimes chez
## le voisin).
func _fill(effects: Array[NukeEffect]) -> void:
	var by_country := {} # code du pays -> {label, killed, injured, explosions, pop_est, blackout}
	var killed := 0.0
	var injured := 0.0
	var final_killed := 0.0
	var pending := 0
	var mask := CountryMask.get_mask()
	for effect in effects:
		var ground_zero := effect.params.get_country()
		if not ground_zero.is_empty():
			_entry(by_country, ground_zero).explosions += 1
		if not effect.blackout.is_empty() and effect.blackout.national >= 0 and mask:
			_entry(by_country, mask.countries[effect.blackout.national]).blackout = true
		if effect.fallout_pending:
			pending += 1
		var now := NukeCasualties.snapshot(effect.casualties, effect.fallout, effect.get_time_s())
		killed += now.killed
		injured += now.injured
		final_killed += now.final_killed
		for c: Dictionary in now.countries:
			var entry := _entry(by_country, c)
			entry.killed += c.killed
			entry.injured += c.injured

	var count := effects.size()
	_summary.text = "%d explosion%s · %s morts · %s blessés" % [count, "s" if count > 1 else "",
			NukeCasualties.format_count(killed), NukeCasualties.format_count(injured)]
	_projection.text = "Projection à %d jours : %s morts%s" % [roundi(NukeFallout.HORIZON_H / 24.0),
			NukeCasualties.format_count(final_killed), " (retombées : calcul en cours…)" if pending > 0 else ""]

	var codes: Array[String] = []
	for code: String in by_country:
		var entry: Dictionary = by_country[code]
		if entry.killed + entry.injured >= 1.0 or entry.blackout or entry.explosions > 0:
			codes.append(code)
	codes.sort_custom(func(a: String, b: String) -> bool:
		return by_country[a].killed > by_country[b].killed if by_country[a].killed != by_country[b].killed \
				else by_country[a].explosions > by_country[b].explosions)
	if codes != _row_order:
		_rebuild_rows(codes)
	for code in codes:
		var entry: Dictionary = by_country[code]
		var labels: Array = _row_labels[code]
		var share := "—"
		if entry.pop_est > 0:
			var percent: float = 100.0 * entry.killed / entry.pop_est
			if entry.killed < 0.5:
				share = "0 %"
			else:
				share = "< 0,01 %" if percent < 0.01 else ("%.2f %%" % percent).replace(".", ",")
		labels[0].text = entry.label + ("  ⚡" if entry.blackout else "")
		labels[0].add_theme_color_override("font_color",
				Color(1.0, 0.85, 0.5) if entry.blackout else Color(0.92, 0.94, 0.97))
		labels[0].tooltip_text = "Black-out national : une centrale majeure a été détruite." if entry.blackout else ""
		labels[1].text = str(entry.explosions) if entry.explosions > 0 else "—"
		labels[2].text = NukeCasualties.format_count(entry.killed)
		labels[3].text = NukeCasualties.format_count(entry.injured)
		labels[4].text = share


## Recrée les lignes (une par pays, dans l'ordre donné) ; leurs textes sont posés par _fill.
func _rebuild_rows(codes: Array[String]) -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_labels.clear()
	_row_order = codes.duplicate()
	if codes.is_empty():
		_rows.add_child(_make_cell("Aucun pays touché", COLUMNS[0].width, Color(0.7, 0.75, 0.8)))
	var colors := [Color(0.92, 0.94, 0.97), Color(0.95, 0.95, 1.0), Color(1.0, 0.55, 0.5), Color(0.95, 0.8, 0.55),
			Color(0.8, 0.85, 0.9)]
	for code in codes:
		var labels := []
		for i in COLUMNS.size():
			var cell := _make_cell("", COLUMNS[i].width, colors[i])
			if i == 0:
				cell.mouse_filter = Control.MOUSE_FILTER_PASS
			_rows.add_child(cell)
			labels.append(cell)
		_row_labels[code] = labels
	_window.reset_size.call_deferred()


## Ligne d'un pays (créée au besoin) à partir d'une fiche CountryMask ou d'un pays de NukeCasualties.
func _entry(by_country: Dictionary, country: Dictionary) -> Dictionary:
	var code: String = country.code
	if not by_country.has(code):
		var label: String = country.name_fr
		if not country.sovereign_fr.is_empty() and country.sovereign_fr != country.name_fr:
			label += " (%s)" % country.sovereign_fr
		by_country[code] = {"label": label, "killed": 0.0, "injured": 0.0, "explosions": 0,
				"pop_est": country.pop_est, "blackout": false}
	return by_country[code]


## Déplacement à la souris par la barre de titre, borné à l'écran.
func _on_title_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		_title_bar.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		_window.position = _clamp_to_screen(_window.position + motion.relative)
		_title_bar.accept_event()


func _clamp_to_screen(pos: Vector2) -> Vector2:
	var screen := _window.get_viewport_rect().size
	var size := _window.size
	return Vector2(clampf(pos.x, SCREEN_MARGIN, maxf(screen.x - size.x - SCREEN_MARGIN, SCREEN_MARGIN)),
			clampf(pos.y, SCREEN_MARGIN, maxf(screen.y - size.y - SCREEN_MARGIN, SCREEN_MARGIN)))


## Position de départ : en haut à droite.
func _place_default() -> void:
	_window.reset_size()
	var screen := _window.get_viewport_rect().size
	_window.position = _clamp_to_screen(Vector2(screen.x - _window.size.x - 24.0, 24.0))


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


## Cellule : width > 0 = colonne de chiffres alignée à droite ; 0 = colonne du nom (extensible, texte tronqué).
func _make_cell(text: String, width: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
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


## Fond arrondi ; corner_bottom = 0 pour la barre de titre collée au contenu.
func _make_style(color: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.55, 0.7, 0.9, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	if margin > 0.0:
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.set_content_margin_all(margin)
		style.content_margin_left = 12.0
	return style
