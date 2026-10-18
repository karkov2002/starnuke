class_name BigRedButton
extends Control
## Gros bouton dessiné à la main : un capuchon de couleur (rouge par défaut ; bleu pour le BURN du poste de pilotage,
## scripts/ui/burn_control.gd) sur un socle sombre. Au clic (bouton gauche, sur le capuchon), le capuchon s'enfonce
## et pressed est émis ; il reste un instant en bas puis remonte avec un léger rebond. En mode maintenu (hold), il
## reste enfoncé tant que le bouton de la souris est tenu, et released est émis au relâchement. Inactif (disabled) :
## capuchon terne, sans effet, avec disabled_message écrit dessus s'il est donné.

signal pressed
signal released

const DEPTH := 9.0 # course du capuchon (px)
const HOUSING := 6.0 # largeur de la collerette du socle (px)

## Couleur du dessus du capuchon (le flanc et le survol en sont déduits).
var cap_color := Color(0.8, 0.07, 0.04):
	set(value):
		cap_color = value
		queue_redraw()
## Bouton maintenu : enfoncé tant qu'on tient le clic, released au relâchement.
var hold := false
var disabled := false:
	set(value):
		disabled = value
		mouse_default_cursor_shape = Control.CURSOR_ARROW if value else Control.CURSOR_POINTING_HAND
		queue_redraw()

## Message écrit sur le capuchon quand le bouton est inactif (texte déjà traduit ; vide : aucun).
var disabled_message := "":
	set(value):
		if value != disabled_message:
			disabled_message = value
			queue_redraw()

var _sink := 0.0 # 0 = relevé, 1 = enfoncé
var _hover := false
var _held := false
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(96.0, 88.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed and not disabled and click.position.distance_to(_cap_center()) <= _radius() + HOUSING:
		accept_event()
		_press()
	elif not click.pressed and _held:
		accept_event()
		release()


func is_held() -> bool:
	return _held


## Relâche un bouton maintenu (aussi appelé de l'extérieur : fin forcée).
func release() -> void:
	if not _held:
		return
	_held = false
	_animate([[1.0, 0.0, 0.3, true]])
	released.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hover = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _press() -> void:
	if hold:
		_held = true
		_animate([[_sink, 1.0, 0.06, false]])
	else:
		_animate([[_sink, 1.0, 0.06, false], [1.0, 1.0, 0.12, false], [1.0, 0.0, 0.3, true]])
	pressed.emit()


# Étapes [de, à, durée, rebond] de l'enfoncement du capuchon.
func _animate(steps: Array) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	for step: Array in steps:
		if step[0] == step[1]:
			_tween.tween_interval(step[2])
			continue
		var tweener := _tween.tween_method(_set_sink, step[0], step[1], step[2])
		if step[3]:
			tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	var color := cap_color.lerp(Color(0.32, 0.32, 0.34), 0.9) if disabled else cap_color
	# Collerette du socle, puis flanc du capuchon (du capuchon jusqu'au socle), puis le dessus.
	draw_circle(base, r + HOUSING, Color(0.13, 0.13, 0.15), true, -1.0, true)
	draw_circle(rest + Vector2(0.0, DEPTH * 0.5), r + HOUSING, Color(0.22, 0.22, 0.25), true, -1.0, true)
	var side := color.darkened(0.45)
	draw_circle(base, r, side, true, -1.0, true)
	draw_rect(Rect2(cap.x - r, cap.y, 2.0 * r, base.y - cap.y), side)
	var top := Color(minf(color.r * 1.15, 1.0), minf(color.g * 1.15, 1.0), minf(color.b * 1.15, 1.0)) \
			if _hover and not disabled else color
	draw_circle(cap, r, top, true, -1.0, true)
	draw_circle(cap, r * 0.82, top.lightened(0.08), true, -1.0, true)
	draw_circle(cap + Vector2(-0.3, -0.35) * r, r * 0.26, Color(1.0, 1.0, 1.0, 0.22), true, -1.0, true)
	if disabled and disabled_message != "":
		# Message centré sur le capuchon, en plusieurs lignes, réduit pour tenir dans le cercle.
		var font := get_theme_default_font()
		var width := r * 1.7
		var font_size := 12
		while font_size > 7 and font.get_multiline_string_size(disabled_message, HORIZONTAL_ALIGNMENT_CENTER, width,
				font_size).y > r * 1.4:
			font_size -= 1
		var text_size := font.get_multiline_string_size(disabled_message, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
		var origin := cap - Vector2(width * 0.5, text_size.y * 0.5) + Vector2(0.0, font.get_ascent(font_size))
		draw_multiline_string(font, origin, disabled_message, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, -1,
				Color(1.0, 1.0, 1.0, 0.92))
