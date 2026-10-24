class_name ShutterOverlay
extends Control
## Obturateur à iris dessiné par-dessus la vue au nadir de la tablette (PhotoPage) à chaque photo : BLADES lames
## sombres se referment en tournant jusqu'à masquer l'image (CLOSE_S), restent fermées (HOLD_S) puis se rouvrent
## (OPEN_S). Pur effet d'interface : la photo est rendue par NadirCamera, sans lui.

const BLADES := 6
const CLOSE_S := 0.07
const HOLD_S := 0.04
const OPEN_S := 0.12
## Rotation de l'iris (radians) entre ouvert et fermé : les lames glissent en tournant.
const TWIST := 0.6
const BLADE_COLOR := Color(0.07, 0.075, 0.085)
const EDGE_COLOR := Color(0.32, 0.34, 0.37)

## Fermeture de l'iris : 0 ouvert (rien n'est dessiné), 1 fermé.
var closure := 0.0:
	set(value):
		closure = value
		queue_redraw()

var _tween: Tween


func _init() -> void:
	name = "Shutter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Un déclenchement : fermeture, pause, réouverture.
func trigger() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "closure", 1.0, CLOSE_S).set_ease(Tween.EASE_IN)
	_tween.tween_interval(HOLD_S)
	_tween.tween_property(self, "closure", 0.0, OPEN_S).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if closure <= 0.0:
		return
	var center := size * 0.5
	# Ouvert : l'ouverture hexagonale contient tout le cadre (demi-diagonale / cos 30°).
	var open_radius := center.length() / cos(PI / BLADES)
	var radius := open_radius * (1.0 - closure)
	var far := center.length() * 4.0
	var turn := TWIST * closure
	var hole := PackedVector2Array()
	for i in BLADES:
		hole.append(center + Vector2.from_angle(TAU * i / BLADES + turn) * radius)
	# Chaque lame : un côté de l'ouverture prolongé loin hors du cadre (les lames se recouvrent un peu).
	for i in BLADES:
		var a := hole[i]
		var b := hole[(i + 1) % BLADES]
		var blade := PackedVector2Array([a, b, b + (b - center).normalized().rotated(0.5) * far,
				a + (a - center).normalized().rotated(0.5) * far])
		if radius < 1.0:
			blade = PackedVector2Array([center, center + Vector2.from_angle(TAU * i / BLADES + turn) * far,
					center + Vector2.from_angle(TAU * (i + 1.5) / BLADES + turn) * far])
		draw_colored_polygon(blade, BLADE_COLOR)
	for i in BLADES:
		var a := hole[i]
		draw_line(a, a + (a - center).normalized().rotated(0.5) * far, EDGE_COLOR, 2.0, true)
