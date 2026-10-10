class_name DraggableWindow
extends PanelContainer
## Fenêtre flottante réutilisable, comme sous Windows : barre de titre qui sert de poignée (clic gauche maintenu,
## bornée à l'écran), bouton « — » / « + » qui replie le contenu. Le contenu se place dans body. Construite en code ;
## à ajouter sous un CanvasLayer.

## Marge minimale entre la fenêtre et le bord de l'écran quand on la déplace.
const SCREEN_MARGIN := 8.0

## Contenu de la fenêtre (sous la barre de titre).
var body: VBoxContainer

var _title_bar: PanelContainer
var _collapse: Button
var _dragging := false


func _init(title: String, width: float) -> void:
	custom_minimum_size.x = width
	add_theme_stylebox_override("panel", _make_style(Color(0.05, 0.07, 0.1, 0.82), 0.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	_title_bar = PanelContainer.new()
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_bar.add_theme_stylebox_override("panel", _make_style(Color(0.35, 0.08, 0.06, 0.95), 8.0))
	_title_bar.gui_input.connect(_on_title_input)
	column.add_child(_title_bar)
	var title_row := HBoxContainer.new()
	_title_bar.add_child(title_row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(label)
	_collapse = Button.new()
	_collapse.text = "—"
	_collapse.flat = true
	_collapse.focus_mode = Control.FOCUS_NONE
	_collapse.tooltip_text = "Replier / déplier"
	_collapse.pressed.connect(_toggle_collapsed)
	title_row.add_child(_collapse)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	column.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)


## Place la fenêtre en haut à droite de l'écran (après le calcul de sa taille).
func place_top_right(offset := Vector2(24.0, 24.0)) -> void:
	reset_size()
	var screen := get_viewport_rect().size
	position = _clamp_to_screen(Vector2(screen.x - size.x - offset.x, offset.y))


func _toggle_collapsed() -> void:
	body.get_parent().visible = not body.get_parent().visible
	_collapse.text = "—" if body.get_parent().visible else "+"
	reset_size()


func _on_title_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		_title_bar.accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion and _dragging:
		position = _clamp_to_screen(position + motion.relative)
		_title_bar.accept_event()


func _clamp_to_screen(pos: Vector2) -> Vector2:
	var screen := get_viewport_rect().size
	return Vector2(clampf(pos.x, SCREEN_MARGIN, maxf(screen.x - size.x - SCREEN_MARGIN, SCREEN_MARGIN)),
			clampf(pos.y, SCREEN_MARGIN, maxf(screen.y - size.y - SCREEN_MARGIN, SCREEN_MARGIN)))


## Fond arrondi ; title_margin > 0 : barre de titre (coins du bas carrés, collée au contenu).
func _make_style(color: Color, title_margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.55, 0.7, 0.9, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	if title_margin > 0.0:
		style.corner_radius_bottom_left = 0
		style.corner_radius_bottom_right = 0
		style.set_content_margin_all(title_margin)
		style.content_margin_left = 12.0
	return style
