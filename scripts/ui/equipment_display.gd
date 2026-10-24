class_name EquipmentDisplay
extends Control
## Programme de maintenance d'un équipement extérieur (EquipmentPanel, dans un SubViewport) : interface « MS-DOS »
## en mode texte, monochrome noir et blanc (grille COLS × ROWS d'une police à chasse fixe, barres en vidéo inverse,
## curseur clignotant). Affiche le nom de l'équipement (StationEquipment), son état (EN SERVICE, ARRÊTÉ, EN PANNE
## clignotant), les boutons [ ON ] [ OFF ] (celui de l'état actuel en vidéo inverse) et, en panne, [ RÉPARER ] (pour
## l'instant une réparation directe ; plus tard des mini-jeux). Clavier : Entrée allume / éteint, R répare, F10
## quitte la vue (quit_requested). Tous les libellés sont des clés des fichiers de langue.

signal quit_requested

const COLS := 40
const ROWS := 15
const BLINK_S := 0.5
const FONTS: PackedStringArray = ["Consolas", "Lucida Console", "Courier New", "monospace"]
const INK := Color(0.86, 0.86, 0.86)
const BRIGHT := Color(1.0, 1.0, 1.0)
const DIM := Color(0.5, 0.5, 0.5)
const PAPER := Color(0.0, 0.0, 0.0)

var equipment: StationEquipment

var _font: SystemFont
var _font_size := 20
var _cell := Vector2(16.0, 32.0)
var _ascent := 24.0
## Tampon : caractère et vidéo inverse de chaque case, couleur du texte.
var _chars := PackedStringArray()
var _inverse := PackedByteArray()
var _ink: Array[Color] = []
## Zones cliquables : [Rect2i (cases), Callable].
var _zones: Array = []
var _clock := 0.0
var _blink := true
## Message après la dernière action (réparation) ; vide sinon.
var _notice := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = SystemFont.new()
	_font.font_names = FONTS
	_cell = size / Vector2(COLS, ROWS)
	var probe := _font.get_char_size("M".unicode_at(0), 20).x
	_font_size = maxi(8, floori(20.0 * _cell.x / maxf(probe, 1.0)))
	_ascent = (_cell.y - _font.get_height(_font_size)) * 0.5 + _font.get_ascent(_font_size)
	_chars.resize(COLS * ROWS)
	_inverse.resize(COLS * ROWS)
	_ink.resize(COLS * ROWS)
	if equipment:
		equipment.changed.connect(queue_redraw)


func _process(delta: float) -> void:
	_clock += delta
	var blink := fmod(_clock, BLINK_S * 2.0) < BLINK_S
	if blink != _blink:
		_blink = blink
		queue_redraw()


func _draw() -> void:
	if equipment == null:
		return
	_compose()
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	for i in COLS * ROWS:
		if _inverse[i]:
			draw_rect(Rect2(Vector2(i % COLS, floori(float(i) / COLS)) * _cell, _cell), _ink[i])
	for i in COLS * ROWS:
		var c := _chars[i]
		if c != " " and c != "":
			var at := Vector2(i % COLS, floori(float(i) / COLS)) * _cell + Vector2(0.0, _ascent)
			draw_char(_font, at, c, _font_size, PAPER if _inverse[i] else _ink[i])


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := Vector2i((click.position / _cell).floor())
	for k in range(_zones.size() - 1, -1, -1):
		var zone: Array = _zones[k]
		if (zone[0] as Rect2i).has_point(cell):
			(zone[1] as Callable).call()
			queue_redraw()
			accept_event()
			return


## Touche transmise par EquipmentPanel en vue assise ; vrai si elle est utilisée.
func handle_key(key: InputEventKey) -> bool:
	if not key.pressed or equipment == null:
		return false
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_set_power(not equipment.powered)
		KEY_R:
			_repair()
		KEY_F10:
			quit_requested.emit()
		_:
			return false
	queue_redraw()
	return true


func _set_power(on: bool) -> void:
	_notice = ""
	equipment.set_powered(on)


func _repair() -> void:
	if equipment.failed:
		equipment.repair()
		_notice = tr("EQUIP_REPAIRED")


# --- Composition ----------------------------------------------------------------------------------------------------

func _compose() -> void:
	_zones.clear()
	for i in COLS * ROWS:
		_chars[i] = " "
		_inverse[i] = 0
		_ink[i] = INK
	# Barre de titre en vidéo inverse : programme, puis « MAINTENANCE » à droite.
	_fill_row(0, true)
	_put(1, 0, equipment.program, INK, true)
	var title := tr("EQUIP_PANEL_TITLE").to_upper()
	_put(COLS - 1 - title.length(), 0, title, INK, true)
	_put(1, 2, _fit("%s : %s" % [tr("EQUIP_PANEL_EQUIPMENT"), tr(equipment.name_key)], COLS - 2), INK)
	var state_label := tr("EQUIP_PANEL_STATE") + " : "
	_put(1, 3, state_label, INK)
	var x := 1 + state_label.length()
	if equipment.failed:
		_put(x, 3, _fit(tr("EQUIP_STATE_FAILED"), COLS - 1 - x), BRIGHT, _blink)
	else:
		_put(x, 3, _fit(tr("EQUIP_STATE_RUNNING" if equipment.powered else "EQUIP_STATE_OFF"), COLS - 1 - x),
				BRIGHT if equipment.powered else DIM)
	_put(0, 5, "─".repeat(COLS), DIM)
	# Interrupteur : [ ON ] [ OFF ], la position actuelle en vidéo inverse.
	var power := tr("EQUIP_PANEL_POWER") + " :"
	_put(1, 7, power, INK)
	x = 3 + power.length()
	for on: bool in [true, false]:
		var label := "[ %s ]" % tr("EQUIP_ON" if on else "EQUIP_OFF")
		_put(x, 7, label, BRIGHT, equipment.powered == on)
		_zones.append([Rect2i(x, 7, label.length(), 1), _set_power.bind(on)])
		x += label.length() + 2
	if equipment.failed:
		var row := 9
		for line in _wrap(tr("EQUIP_FAULT"), COLS - 2):
			_put(1, row, line, BRIGHT)
			row += 1
		var repair := "[ %s ]" % tr("EQUIP_REPAIR").to_upper()
		var rx := floori((COLS - repair.length()) * 0.5)
		_put(rx, 11, repair, BRIGHT, true)
		_zones.append([Rect2i(rx, 11, repair.length(), 1), _repair])
	elif _notice != "":
		_put(1, 9, _fit(_notice, COLS - 2), INK)
	_put(0, 13, "═".repeat(COLS), DIM)
	_put(1, 14, _fit(tr("EQUIP_PANEL_KEYS"), COLS - 2), DIM)
	# Curseur clignotant en bas à droite.
	if _blink:
		_put(COLS - 2, 14, "_", INK)


func _put(x: int, y: int, text: String, ink: Color, inverse := false) -> void:
	if y < 0 or y >= ROWS:
		return
	for k in text.length():
		var col := x + k
		if col < 0 or col >= COLS:
			continue
		var i := y * COLS + col
		_chars[i] = text[k]
		_ink[i] = ink
		_inverse[i] = 1 if inverse else 0


func _fill_row(y: int, inverse: bool) -> void:
	for col in COLS:
		_inverse[y * COLS + col] = 1 if inverse else 0
		_ink[y * COLS + col] = INK


static func _fit(text: String, width: int) -> String:
	return text if text.length() <= width else text.substr(0, maxi(width - 1, 0)) + "…"


static func _wrap(text: String, width: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		if line == "":
			line = word
		elif line.length() + 1 + word.length() <= width:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if line != "":
		lines.append(line)
	return lines
