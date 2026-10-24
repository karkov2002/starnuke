class_name FroggerView
extends Control
## Dessin du mini-jeu de réparation (RepairFrogger) dans le panneau de maintenance (enfant d'EquipmentDisplay, même
## taille, par-dessus pendant la partie) : basse résolution, très schématique, monochrome noir et blanc comme le
## programme du panneau. Grenouille : gros carré creux à point central, cerné de noir (visible sur un tronc) ;
## objets en code hexadécimal (ambiance de débogage) : troncs = blocs mémoire en vidéo inverse (rectangle blanc,
## chiffres noirs), voitures = chiffres blancs bruts ; un chiffre par objet change toutes les GLITCH_S
## (scintillement) ; eau : pointillés gris ; route : noire, sans marquage ; talus et départ : gris foncé ; arrivée :
## mur gris percé de trois baies. Positions arrondies à PIXEL pixels (mouvement saccadé de vieil écran). En haut :
## niveau, baies remplies, chrono (clignotant dans les 10 dernières secondes) ; en bas : touches.

const FONTS: PackedStringArray = ["Consolas", "Lucida Console", "Courier New", "monospace"]
const INK := Color(0.86, 0.86, 0.86)
const BRIGHT := Color(1.0, 1.0, 1.0)
const DIM := Color(0.42, 0.42, 0.42)
const DARK := Color(0.16, 0.16, 0.16)
const PAPER := Color(0.0, 0.0, 0.0)
## Pas des positions à l'écran (px du viewport).
const PIXEL := 4.0
const HEADER_H := 48.0
const FOOTER_H := 48.0
const FONT_SIZE := 20
## Taille des chiffres hexadécimaux des objets, et période du scintillement (s).
const HEX_SIZE := 22
const GLITCH_S := 0.35
const HEX_DIGITS := "0123456789ABCDEF"

var game: RepairFrogger

var _font: SystemFont
var _cell := 32.0
var _origin := Vector2.ZERO
var _hex_font: SystemFont
var _hex_w := 12.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = FONTS
	_hex_font = SystemFont.new()
	_hex_font.font_names = FONTS
	_hex_font.font_weight = 700
	_hex_w = _hex_font.get_char_size("0".unicode_at(0), HEX_SIZE).x


func _process(delta: float) -> void:
	_time += delta
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if game == null:
		return
	var field_h := size.y - HEADER_H - FOOTER_H
	_cell = floorf(minf(size.x / RepairFrogger.COLS, field_h / RepairFrogger.ROWS))
	_origin = Vector2(floorf((size.x - _cell * RepairFrogger.COLS) * 0.5),
			HEADER_H + floorf((field_h - _cell * RepairFrogger.ROWS) * 0.5))
	_draw_header()
	for row in RepairFrogger.ROWS:
		_draw_row(row)
	_draw_frog()
	var keys := tr("EQUIP_GAME_KEYS")
	draw_string(_font, Vector2(16, size.y - 16), keys, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, FONT_SIZE, DIM)


func _draw_header() -> void:
	draw_rect(Rect2(0, 0, size.x, HEADER_H - 12), INK)
	var title := "%s · %s" % [tr("EQUIP_REPAIR").to_upper(), tr("EQUIP_LEVEL").format({"n": game.level})]
	draw_string(_font, Vector2(12, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PAPER)
	# Baies : un carré plein par baie remplie.
	for i in game.bays_filled.size():
		var r := Rect2(size.x * 0.5 - 40 + i * 28, 8, 20, 20)
		if game.bays_filled[i]:
			draw_rect(r, PAPER)
		else:
			draw_rect(r, PAPER, false, 2.0)
	var t := ceili(game.time_left)
	var clock := tr("EQUIP_TIME").format({"t": "%d:%02d" % [t / 60, t % 60]})
	if game.time_left > 10.0 or fmod(game.time_left, 0.5) > 0.2:
		var w := _font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(_font, Vector2(size.x - 12 - w, 26), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PAPER)


func _row_rect(row: int) -> Rect2:
	return Rect2(_origin + Vector2(0, row * _cell), Vector2(_cell * RepairFrogger.COLS, _cell))


func _draw_row(row: int) -> void:
	var rect := _row_rect(row)
	if row == RepairFrogger.HOME_ROW:
		draw_rect(rect, DIM)
		for i in RepairFrogger.BAYS.size():
			var bay := Rect2(_origin + Vector2(RepairFrogger.BAYS[i] * _cell, 0),
					Vector2(RepairFrogger.BAY_WIDTH * _cell, _cell))
			draw_rect(bay, PAPER)
			if game.bays_filled[i]:
				_draw_frog_at(bay.position + Vector2((bay.size.x - _cell) * 0.5, 0))
		return
	var lane := game.lane_at(row)
	if lane.is_empty():
		draw_rect(rect, DARK)
		return
	if lane["log"]:
		# Eau : pointillés, décalés d'une rangée à l'autre.
		var y := rect.position.y + _cell * 0.5
		var x := rect.position.x + (row % 2) * 8.0
		while x < rect.end.x:
			draw_rect(Rect2(x, y, PIXEL, PIXEL), DIM)
			x += 16.0
	var is_log: bool = lane["log"]
	var objects := game.lane_objects(lane)
	for k in objects.size():
		_draw_hex_object(rect, row, k, objects[k], is_log)


## Objet d'une voie en chiffres hexadécimaux : tronc = bloc en vidéo inverse, voiture = chiffres blancs ; coupé aux
## bords de l'écran, chiffre par chiffre.
func _draw_hex_object(rect: Rect2, row: int, k: int, o: Vector2, is_log: bool) -> void:
	var left := rect.position.x + _snap(o.x * _cell)
	var width := o.y * _cell
	if is_log:
		var x0 := maxf(left + 1.0, rect.position.x)
		var x1 := minf(left + width - 1.0, rect.end.x)
		if x1 > x0:
			draw_rect(Rect2(x0, rect.position.y + 3.0, x1 - x0, _cell - 6.0), BRIGHT)
	var count := maxi(int((width - 4.0) / _hex_w), 1)
	var start := left + (width - count * _hex_w) * 0.5
	var baseline := rect.position.y + _cell * 0.5 + _hex_font.get_ascent(HEX_SIZE) * 0.38
	var tick := int(_time / GLITCH_S)
	for c in count:
		var x := start + c * _hex_w
		if x < rect.position.x or x + _hex_w > rect.end.x:
			continue
		# Chiffres stables par objet ; un seul, à tour de rôle, change à chaque scintillement.
		var salt := tick if c == tick % count else 0
		var digit := HEX_DIGITS[absi(hash([row, k, c, salt])) % 16]
		draw_char(_hex_font, Vector2(x, baseline), digit, HEX_SIZE, PAPER if is_log else BRIGHT)


func _draw_frog() -> void:
	# Mort : clignote jusqu'au retour au départ.
	if game.state != RepairFrogger.State.PLAYING or (game.dead_s > 0.0 and fmod(game.dead_s, 0.2) < 0.1):
		return
	_draw_frog_at(_origin + Vector2(_snap(game.frog.x * _cell), game.frog.y * _cell))


## Grenouille : carré creux blanc à point central, cerné de noir (distincte des voitures pleines, visible sur un tronc).
func _draw_frog_at(top_left: Vector2) -> void:
	var s := _cell
	draw_rect(Rect2(top_left, Vector2(s, s)), PAPER)
	draw_rect(Rect2(top_left + Vector2(4, 4), Vector2(s - 8, s - 8)), BRIGHT)
	draw_rect(Rect2(top_left + Vector2(8, 8), Vector2(s - 16, s - 16)), PAPER)
	draw_rect(Rect2(top_left + Vector2(12, 12), Vector2(s - 24, s - 24)), BRIGHT)


static func _snap(px: float) -> float:
	return roundf(px / PIXEL) * PIXEL
