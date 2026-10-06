extends Control
## Réticule au centre de l'écran : la direction de tir du missile. Rouge, avec les coordonnées du point visé,
## quand la vue vise la Terre ; gris et discret sinon (un tir ne ferait rien).

const GAP := 5.0
const ARM := 9.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	var aim := launcher.get_aim() if launcher else {}
	var color := Color(1.0, 0.3, 0.22, 0.9) if not aim.is_empty() else Color(1.0, 1.0, 1.0, 0.3)
	var c := size * 0.5
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * GAP, c + d * (GAP + ARM), color, 1.5, true)
	if not aim.is_empty():
		var text := "%s  %s" % [_format_angle(aim.latitude, "N", "S"), _format_angle(aim.longitude, "E", "O")]
		var at := c + Vector2(GAP + ARM + 6.0, -6.0)
		var font := get_theme_default_font()
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, 4, Color(0.0, 0.0, 0.0, 0.7))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)


func _format_angle(value: float, positive: String, negative: String) -> String:
	return "%.2f° %s" % [absf(value), positive if value >= 0.0 else negative]
