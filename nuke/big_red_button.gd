class_name BigRedButton
extends Control
## Gros bouton rouge dessiné à la main : un capuchon rouge sur un socle sombre. Au clic (bouton gauche, sur le
## capuchon), le capuchon s'enfonce, reste un instant en bas puis remonte avec un léger rebond, et pressed est émis.

signal pressed

const DEPTH := 9.0 # course du capuchon (px)
const HOUSING := 6.0 # largeur de la collerette du socle (px)

var _sink := 0.0 # 0 = relevé, 1 = enfoncé
var _hover := false
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(96.0, 88.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.button_index == MOUSE_BUTTON_LEFT and click.pressed \
			and click.position.distance_to(_cap_center()) <= _radius() + HOUSING:
		accept_event()
		_press()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _press() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_sink, _sink, 1.0, 0.06)
	_tween.tween_interval(0.12)
	_tween.tween_method(_set_sink, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pressed.emit()


func _set_sink(value: float) -> void:
	_sink = value
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y - DEPTH) * 0.5 - HOUSING


# Centre du capuchon au repos ; le socle est DEPTH plus bas.
func _cap_center() -> Vector2:
	return Vector2(size.x * 0.5, (size.y - DEPTH) * 0.5)


func _draw() -> void:
	var r := _radius()
	var rest := _cap_center()
	var base := rest + Vector2(0.0, DEPTH)
	var cap := rest + Vector2(0.0, _sink * DEPTH)
	# Collerette du socle, puis flanc du capuchon (du capuchon jusqu'au socle), puis le dessus.
	draw_circle(base, r + HOUSING, Color(0.13, 0.13, 0.15), true, -1.0, true)
	draw_circle(rest + Vector2(0.0, DEPTH * 0.5), r + HOUSING, Color(0.22, 0.22, 0.25), true, -1.0, true)
	var side := Color(0.45, 0.03, 0.02)
	draw_circle(base, r, side, true, -1.0, true)
	draw_rect(Rect2(cap.x - r, cap.y, 2.0 * r, base.y - cap.y), side)
	var top := Color(0.92, 0.1, 0.06) if _hover else Color(0.8, 0.07, 0.04)
	draw_circle(cap, r, top, true, -1.0, true)
	draw_circle(cap, r * 0.82, top.lightened(0.08), true, -1.0, true)
	draw_circle(cap + Vector2(-0.3, -0.35) * r, r * 0.26, Color(1.0, 1.0, 1.0, 0.22), true, -1.0, true)
