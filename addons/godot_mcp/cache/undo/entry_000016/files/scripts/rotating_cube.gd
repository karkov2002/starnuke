extends MeshInstance3D

## Vitesse de rotation en radians par seconde.
@export var rotation_speed: float = 2.0
## Vitesse verticale initiale du saut (m/s).
@export var jump_velocity: float = 5.0
## Gravité appliquée pendant le saut (m/s²).
@export var gravity: float = 15.0
## Facteur appliqué à l'échelle à chaque cran de molette.
@export var scale_step: float = 1.1
@export var min_scale: float = 0.25
@export var max_scale: float = 2.0

var _rest_y: float
var _vertical_velocity: float = 0.0
var _is_jumping: bool = false


func _ready() -> void:
	_rest_y = position.y


func _process(delta: float) -> void:
	_handle_rotation(delta)
	_handle_jump(delta)


func _handle_rotation(delta: float) -> void:
	var yaw := Input.get_axis("rotate_left", "rotate_right")
	var pitch := Input.get_axis("rotate_up", "rotate_down")
	# Axes du parent (monde) pour que les flèches restent intuitives quelle que soit l'orientation du cube.
	if yaw != 0.0:
		rotate(Vector3.UP, yaw * rotation_speed * delta)
	if pitch != 0.0:
		rotate(Vector3.RIGHT, pitch * rotation_speed * delta)


func _handle_jump(delta: float) -> void:
	if not _is_jumping and Input.is_action_just_pressed("jump"):
		_is_jumping = true
		_vertical_velocity = jump_velocity

	if _is_jumping:
		_vertical_velocity -= gravity * delta
		position.y += _vertical_velocity * delta
		if position.y <= _rest_y:
			position.y = _rest_y
			_vertical_velocity = 0.0
			_is_jumping = false
