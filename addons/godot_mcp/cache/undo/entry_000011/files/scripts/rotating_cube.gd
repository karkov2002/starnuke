extends MeshInstance3D

## Vitesse de rotation en radians par seconde, par axe.
@export var rotation_speed: Vector3 = Vector3(0.5, 1.0, 0.0)


func _process(delta: float) -> void:
	rotate_x(rotation_speed.x * delta)
	rotate_y(rotation_speed.y * delta)
	rotate_z(rotation_speed.z * delta)
