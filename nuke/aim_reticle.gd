extends Control
## Réticule au centre de l'écran : la direction de tir du missile. Rouge, avec les coordonnées du point visé,
## quand la vue vise la Terre ; gris et discret sinon (un tir ne ferait rien). Point visé hors du cône de tir ou hors
## de portée (FiringCone) : orangé pâle, la raison écrite sous les coordonnées (le bouton de tir est alors grisé).

const GAP := 5.0
const ARM := 9.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Point visé affiché (texte, "" : la vue ne vise pas la Terre) : redessiné seulement quand il change.
var _text := ""
## Raison du refus de tir (clé de langue, "" : tir permis).
var _refusal := ""
var _launcher: NukeLauncher


func _process(_delta: float) -> void:
	if _launcher == null:
		_launcher = get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	var aim := _launcher.get_aim() if _launcher else {}
	var text := GeoMath.format_lat_lon(aim.latitude, aim.longitude) if not aim.is_empty() else ""
	var refusal := FiringCone.refusal_key(FiringCone.aim_status(aim))
	if text != _text or refusal != _refusal:
		_text = text
		_refusal = refusal
		queue_redraw()


func _draw() -> void:
	var aiming := not _text.is_empty()
	var color := Color(1.0, 1.0, 1.0, 0.3)
	if aiming:
		color = Color(1.0, 0.3, 0.22, 0.9) if _refusal.is_empty() else Color(1.0, 0.7, 0.45, 0.6)
	var c := size * 0.5
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * GAP, c + d * (GAP + ARM), color, 1.5, true)
	if aiming:
		var at := c + Vector2(GAP + ARM + 6.0, -6.0)
		var font := get_theme_default_font()
		draw_string_outline(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, 4, Color(0.0, 0.0, 0.0, 0.7))
		draw_string(font, at, _text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, color)
		if not _refusal.is_empty():
			var below := at + Vector2(0.0, 17.0)
			draw_string_outline(font, below, tr(_refusal), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, 4,
					Color(0.0, 0.0, 0.0, 0.7))
			draw_string(font, below, tr(_refusal), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, color)
