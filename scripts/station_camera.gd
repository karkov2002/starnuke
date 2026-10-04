extends Camera3D
## Caméra « tête » de l'observateur : orientation à la souris uniquement (pas de déplacement).
## Le curseur est libre par défaut (pour interagir avec l'interface) ; la vue ne pivote que tant que
## le bouton droit est maintenu. Le curseur est alors masqué puis replacé là où le clic a commencé.

@export var mouse_sensitivity := 0.0025
@export_range(0.0, 89.0) var max_pitch_deg := 80.0

var _yaw := 0.0
var _pitch := 0.0
var _looking := false
var _cursor_restore := Vector2.ZERO


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		var limit := deg_to_rad(max_pitch_deg)
		_pitch = clampf(_pitch, -limit, limit)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _looking:
		_set_looking(false)


func _set_looking(active: bool) -> void:
	if active == _looking:
		return
	_looking = active
	if active:
		_cursor_restore = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(_cursor_restore)
