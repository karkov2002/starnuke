class_name Torch
extends SpotLight3D
## Lampe torche de l'observateur (nœud Torch, enfant de la caméra dans orbit_view.tscn) : allumée ou éteinte par
## l'action « torch » (touche physique L). Tenue légèrement en dessous et à droite du regard, elle éclaire devant
## (cône spot_angle, portée spot_range), avec ombres portées : la lumière ne traverse pas les parois. Utile quand la
## station est éteinte (« plus de lumière », Station.Alert.BLACKOUT).

const ACTION := &"torch"

## Allumée au départ ?
@export var on_at_start := false


func _ready() -> void:
	visible = on_at_start


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		visible = not visible
		get_viewport().set_input_as_handled()
