class_name TargetMarker
extends Control
## Cible au sol (GroundTarget) en surimpression bleue sur la Terre, dans la cupola en mode « HUD : On » (calque du
## Hud) : cercle et croix au point de la Terre projeté à l'écran, ses coordonnées à côté. Masquée si le point est
## sous l'horizon (face cachée de la Terre) ou derrière la caméra ; au bord de l'écran, une flèche indique sa direction.

const RADIUS := 16.0
const EDGE_MARGIN := 36.0

var earth: Node3D
## Affichée (Hud : cupola et overlay_enabled).
var shown := false:
	set(value):
		shown = value
		queue_redraw()

var _target: GroundTarget


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if shown:
		queue_redraw()


func _draw() -> void:
	if not shown or earth == null:
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
	var camera := get_viewport().get_camera_3d()
	if _target == null or not _target.active or camera == null:
		return
	var point := earth.global_transform * GroundTarget.earth_local(_target.latitude_deg, _target.longitude_deg)
	var center := earth.global_position
	# Face visible de la Terre : le point est au-dessus de l'horizon vu de la caméra.
	if (camera.global_position - point).dot(point - center) <= 0.0:
		return
	var color := GroundTarget.COLOR
	var font := get_theme_default_font()
	var text := GroundTarget.format(_target.latitude_deg, _target.longitude_deg)
	var screen := get_viewport_rect().size
	if camera.is_position_behind(point):
		return
	var at := camera.unproject_position(point)
	var inside := Rect2(Vector2.ZERO, screen).grow(-EDGE_MARGIN).has_point(at)
	if not inside:
		# Hors champ : flèche au bord de l'écran, vers la cible.
		var middle := screen * 0.5
		var direction := (at - middle).normalized()
		var edge := middle + direction * minf((screen.x * 0.5 - EDGE_MARGIN) / maxf(absf(direction.x), 1e-3),
				(screen.y * 0.5 - EDGE_MARGIN) / maxf(absf(direction.y), 1e-3))
		var side := direction.orthogonal() * 9.0
		draw_colored_polygon(PackedVector2Array([edge + direction * 14.0, edge + side, edge - side]), color)
		return
	draw_arc(at, RADIUS, 0.0, TAU, 48, color, 2.5, true)
	draw_arc(at, RADIUS + 5.0, 0.0, TAU, 48, Color(color, 0.35), 1.5, true)
	draw_circle(at, 3.0, color, true, -1.0, true)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(at + direction * (RADIUS + 6.0), at + direction * (RADIUS + 16.0), color, 2.0, true)
	var font_size := 18
	var label := tr("MAP_TARGET") + "  " + text
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var box := Rect2(at + Vector2(RADIUS + 22.0, -text_size.y * 0.5 - 4.0), text_size + Vector2(14.0, 8.0))
	draw_rect(box, Color(0.02, 0.05, 0.1, 0.65))
	draw_string(font, box.position + Vector2(7.0, text_size.y * 0.8 + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)
