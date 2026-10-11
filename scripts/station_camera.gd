class_name StationCamera
extends Camera3D
## Caméra « tête » de l'observateur, enfant du corps Observer (scripts/observer.gd, déplacement) : orientation
## seulement, libre comme en apesanteur (pas de « haut » imposé, pas de limite de tangage) : chaque rotation se fait
## autour des axes de la tête.
## - Souris : le curseur est libre par défaut (pour interagir avec l'interface) ; la vue ne pivote que tant que le
##   bouton droit est maintenu (lacet et tangage), le curseur est alors masqué puis replacé là où le clic a commencé.
## - Clavier : roulis autour de l'axe du regard (actions roll_left, roll_right : A / E en AZERTY, Q / E en QWERTY).

@export var mouse_sensitivity := 0.0025
## Vitesse de roulis au clavier (degrés par seconde).
@export var roll_speed_deg := 90.0

var _looking := false
var _cursor_restore := Vector2.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if is_typing(self):
		return
	var roll := Input.get_axis(&"roll_right", &"roll_left")
	if roll != 0.0:
		# Rotation positive autour de +Z local : la droite de la vue monte, la tête penche à gauche.
		_rotate_local(Vector3.BACK, roll * deg_to_rad(roll_speed_deg) * delta)


## Un champ de texte de l'interface a le focus (date du panneau…) : les touches lui sont destinées.
static func is_typing(node: Node) -> bool:
	return node.get_viewport().gui_get_focus_owner() is LineEdit


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
	elif event is InputEventMouseMotion and _looking:
		_rotate_local(Vector3.UP, -event.relative.x * mouse_sensitivity)
		_rotate_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)


func _rotate_local(axis: Vector3, angle: float) -> void:
	basis = (basis * Basis(axis, angle)).orthonormalized()


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
