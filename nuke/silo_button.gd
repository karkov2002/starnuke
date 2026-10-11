class_name SiloButton
extends Control
## Bouton rond lumineux d'un tube de lancement (panneau des silos, nuke/silo_panel.gd), avec son numéro :
## orange = missile prêt, vert = tube choisi pour le prochain tir, gris = tube vide (missile tiré, plus de clic).

signal pressed

enum State { READY, ARMED, EMPTY }

const DIAMETER := 19.0
const COLORS := {
	State.READY: Color(1.0, 0.55, 0.08),
	State.ARMED: Color(0.2, 0.95, 0.3),
	State.EMPTY: Color(0.32, 0.33, 0.36),
}

var number := 0
var state := State.READY:
	set(value):
		state = value
		mouse_default_cursor_shape = Control.CURSOR_ARROW if value == State.EMPTY else Control.CURSOR_POINTING_HAND
		queue_redraw()

var _hover := false


func _init() -> void:
	custom_minimum_size = Vector2(DIAMETER + 1.0, DIAMETER + 1.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and click.pressed and state != State.EMPTY:
		accept_event()
		pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var r := DIAMETER * 0.5
	var color: Color = COLORS[state]
	var lit := state != State.EMPTY
	if lit:
		# Halo : le voyant éclaire autour de lui.
		draw_circle(center, r + 1.0, Color(color, 0.35), true, -1.0, true)
		if _hover:
			color = color.lightened(0.25)
	draw_circle(center, r - 1.0, Color(0.08, 0.08, 0.1), true, -1.0, true)
	draw_circle(center, r - 2.0, color, true, -1.0, true)
	if lit:
		draw_circle(center, r * 0.55, color.lightened(0.35), true, -1.0, true)
		draw_circle(center + Vector2(-0.3, -0.35) * r, r * 0.22, Color(1.0, 1.0, 1.0, 0.35), true, -1.0, true)
	var font := get_theme_default_font()
	var font_size := 9
	var text := str(number)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center + Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.5 - 1.0)
	var ink := Color(0.1, 0.07, 0.04) if lit else Color(0.62, 0.63, 0.66)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
