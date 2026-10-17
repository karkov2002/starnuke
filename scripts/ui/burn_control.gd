class_name BurnControl
extends VBoxContainer
## Commande de poussée, partagée par l'écran du poste de pilotage (PilotDisplay) et le panneau de la cupola
## (OrbitControls) : nœud de la manœuvre et compte à rebours, gros bouton BURN bleu (BigRedButton maintenu, même
## dessin que le bouton de tir), jauge de la poussée et message d'état. Logique : FlightComputer.
## Jauge : de 0 à 150 % de la durée requise ; zone verte de la poussée parfaite (95 à 105 %) ; remplissage bleu,
## orange au-delà de la zone verte.

const COLOR_BURN := Color(0.12, 0.38, 0.95)
const COLOR_GHOST := Color(0.3, 0.85, 1.0)
const COLOR_DIM := Color(0.55, 0.65, 0.6)
const COLOR_GOOD := Color(0.3, 1.0, 0.4)
const COLOR_BAD := Color(1.0, 0.55, 0.15)
## Durée d'affichage (s réelles) du résultat de la dernière poussée.
const RESULT_S := 6.0

var flight_computer: FlightComputer
## Grand format (écran du poste) ou compact (panneau de la cupola) : fixé avant l'ajout à l'arbre.
var large := false

var _node_label: Label
var _countdown: Label
var _button: BigRedButton
var _gauge: Control
var _status: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6 if large else 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	_node_label = _make_label(COLOR_DIM, 0)
	info.add_child(_node_label)
	_countdown = _make_label(COLOR_GHOST, 60 if large else 26)
	info.add_child(_countdown)
	_button = BigRedButton.new()
	_button.cap_color = COLOR_BURN
	_button.hold = true
	_button.tooltip_text = "PILOT_BURN_TOOLTIP"
	if large:
		_button.custom_minimum_size = Vector2(130.0, 122.0)
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(func() -> void:
		if not flight_computer.start_burn():
			_button.release())
	_button.released.connect(func() -> void: flight_computer.end_burn())
	row.add_child(_button)
	_gauge = Control.new()
	_gauge.custom_minimum_size = Vector2(0.0, 26.0 if large else 12.0)
	_gauge.draw.connect(_draw_gauge)
	add_child(_gauge)
	_status = _make_label(COLOR_DIM, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)


func _process(_delta: float) -> void:
	if flight_computer == null:
		return
	var computer := flight_computer
	# Poussée arrêtée d'elle-même (150 %) ou mode changé : le bouton remonte.
	if _button.is_held() and not computer.burning:
		_button.release()
	_button.disabled = not computer.can_burn() and not computer.burning
	if computer.is_burn_at_node():
		_node_label.text = tr("PILOT_NODE_ASCENDING" if computer.is_node_ascending() else "PILOT_NODE_DESCENDING")
	else:
		_node_label.text = tr("PILOT_BURN_POINT")
	_countdown.text = _format_countdown(computer.get_countdown_s())
	_countdown.add_theme_color_override("font_color", COLOR_GOOD if computer.is_in_window() else COLOR_GHOST)
	var status := _status_text(computer)
	_status.text = status[0]
	_status.add_theme_color_override("font_color", status[1])
	_gauge.queue_redraw()


## [texte, couleur] du message d'état.
func _status_text(computer: FlightComputer) -> Array:
	if computer.burning:
		return [tr("PILOT_BURNING").format({"percent": roundi(100.0 * computer.burn_hold_s / computer.burn_required_s)}),
				COLOR_GHOST]
	if not computer.last_burn.is_empty() and Time.get_ticks_msec() - int(computer.last_burn.ticks_ms) < RESULT_S * 1000.0:
		var percent := roundi(100.0 * (float(computer.last_burn.ratio) - 1.0))
		match int(computer.last_burn.quality):
			FlightComputer.BurnQuality.PERFECT:
				return [tr("PILOT_BURN_PERFECT"), COLOR_GOOD]
			FlightComputer.BurnQuality.UNDER:
				return [tr("PILOT_BURN_UNDER").format({"percent": percent}), COLOR_BAD]
			_:
				return [tr("PILOT_BURN_OVER").format({"percent": "+%d" % percent}), COLOR_BAD]
	if not computer.has_plan():
		return [tr("PILOT_NO_PLAN"), COLOR_DIM]
	if computer.mode == FlightComputer.Mode.AUTO:
		return [tr("PILOT_AUTO_ARMED"), COLOR_GHOST]
	if computer.is_in_window():
		return [tr("PILOT_BURN_READY").format({"seconds": "%.1f" % FlightComputer.required_hold_s(computer.get_delta_v_km_s())}),
				COLOR_GOOD]
	return [tr("PILOT_BURN_WAIT"), COLOR_DIM]


func _draw_gauge() -> void:
	var rect := Rect2(Vector2.ZERO, _gauge.size)
	var scale_x := rect.size.x / FlightComputer.MAX_BURN_RATIO
	_gauge.draw_rect(rect, Color(0.08, 0.1, 0.14))
	var perfect := Rect2((1.0 - FlightComputer.PERFECT_TOLERANCE) * scale_x, 0.0,
			2.0 * FlightComputer.PERFECT_TOLERANCE * scale_x, rect.size.y)
	_gauge.draw_rect(perfect, Color(COLOR_GOOD, 0.45))
	var computer := flight_computer
	var ratio := 0.0
	if computer.burning:
		ratio = computer.burn_hold_s / computer.burn_required_s
	elif not computer.last_burn.is_empty() and Time.get_ticks_msec() - int(computer.last_burn.ticks_ms) < RESULT_S * 1000.0:
		ratio = computer.last_burn.ratio
	if ratio > 0.0:
		var color := COLOR_BAD if ratio > 1.0 + FlightComputer.PERFECT_TOLERANCE else COLOR_BURN.lightened(0.25)
		var inset := rect.size.y * 0.2
		_gauge.draw_rect(Rect2(0.0, inset, minf(ratio, FlightComputer.MAX_BURN_RATIO) * scale_x, rect.size.y - 2.0 * inset), color)
	_gauge.draw_line(Vector2(scale_x, 0.0), Vector2(scale_x, rect.size.y), Color.WHITE, 2.0)
	_gauge.draw_rect(rect, Color(0.4, 0.5, 0.6), false, 1.0)


func _make_label(color: Color, font_size: int) -> Label:
	var label := Label.new()
	# Textes composés à chaque image : pas de traduction automatique.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override("font_color", color)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label


## « 12:34 » (minutes:secondes de temps de jeu), « 1:02:03 » au-delà d'une heure ; 00:00 dans la fenêtre passée.
static func _format_countdown(seconds: float) -> String:
	var s := maxf(ceilf(seconds), 0.0)
	if s >= 3600.0:
		return "%d:%02d:%02d" % [floori(s / 3600.0), floori(s / 60.0) % 60, int(s) % 60]
	return "%02d:%02d" % [floori(s / 60.0), int(s) % 60]
