class_name FroggerView
extends Control
## Dessin du mini-jeu de réparation (RepairFrogger) dans le panneau de maintenance (enfant d'EquipmentDisplay, même
## taille, par-dessus pendant la partie) : basse résolution, très schématique, monochrome noir et blanc comme le
## programme du panneau. Grenouille : gros carré creux à point central, cerné de noir (visible sur un tronc) ;
## voitures et troncs : rectangles blancs pleins ; eau : pointillés gris ; talus et départ : gris foncé ; arrivée : mur gris percé de
## trois baies. Positions arrondies à PIXEL pixels (mouvement saccadé de vieil écran). En haut : niveau, baies
## remplies, chrono (clignotant dans les 10 dernières secondes) ; en bas : touches.

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

var game: RepairFrogger

var _font: SystemFont
var _cell := 32.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = FONTS


func _process(_delta: float) -> void:
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
	else:
		# Route : marquage en tirets en bas de la voie.
		var x := rect.position.x
		while x < rect.end.x:
			draw_rect(Rect2(x, rect.end.y - PIXEL * 0.5, 12, PIXEL * 0.5), DARK)
			x += 24.0
	var inset := 3.0 if lane["log"] else 6.0
	for o in game.lane_objects(lane):
		var x0 := maxf(_snap(o.x * _cell), 0.0)
		var x1 := minf(_snap((o.x + o.y) * _cell), rect.size.x)
		if x1 > x0:
			draw_rect(Rect2(rect.position.x + x0 + 1, rect.position.y + inset, x1 - x0 - 2, _cell - inset * 2), BRIGHT)


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
