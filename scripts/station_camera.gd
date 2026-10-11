class_name StationCamera
extends Camera3D
## Caméra « tête » de l'observateur, enfant du corps Observer (scripts/observer.gd, déplacement) : orientation
## seulement, libre comme en apesanteur (pas de « haut » imposé, pas de limite de tangage) : chaque rotation se fait
## autour des axes de la tête.
## - Souris : le curseur est libre par défaut (pour interagir avec l'interface) ; la vue ne pivote que tant que le
##   bouton droit est maintenu (lacet et tangage), le curseur est alors masqué puis replacé là où le clic a commencé.
## - Clavier : roulis autour de l'axe du regard (actions roll_left, roll_right : A / E en AZERTY, Q / E en QWERTY).

@export var mouse_sensitivity := 0.0025
## Lissage de la souris (s) : la vue rattrape le mouvement de la souris avec un léger retard (inertie de la tête).
@export var look_smoothing_s := 0.08
## Vitesse de roulis au clavier (degrés par seconde).
@export var roll_speed_deg := 60.0
## Inertie du roulis (s) : mise en rotation et arrêt progressifs (voir smooth_toward).
@export var roll_smoothing_s := 0.2

var _looking := false
var _cursor_restore := Vector2.ZERO
var _look_pending := Vector2.ZERO
var _roll_drive := 0.0
var _roll_rate := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var roll := 0.0 if is_typing(self) else Input.get_axis(&"roll_right", &"roll_left")
	# Double lissage (commande lissée, puis vitesse lissée vers la commande) : courbe en S, sans à-coup au départ ni à
	# l'arrêt.
	_roll_drive = smooth_toward(_roll_drive, roll, delta, roll_smoothing_s)
	_roll_rate = smooth_toward(_roll_rate, _roll_drive * deg_to_rad(roll_speed_deg), delta, roll_smoothing_s)
	if absf(_roll_rate) > 1e-4:
		# Rotation positive autour de +Z local : la droite de la vue monte, la tête penche à gauche.
		_rotate_local(Vector3.BACK, _roll_rate * delta)
	else:
		_roll_rate = 0.0

	if _look_pending != Vector2.ZERO:
		var step := _look_pending * (1.0 - exp(-delta / look_smoothing_s))
		if _look_pending.length() < 1e-4:
			step = _look_pending
		_look_pending -= step
		_rotate_local(Vector3.UP, -step.x)
		_rotate_local(Vector3.RIGHT, -step.y)


## Rapproche value de target avec la constante de temps tau (s), indépendamment de la cadence d'images.
static func smooth_toward(value: Variant, target: Variant, delta: float, tau: float) -> Variant:
	return lerp(value, target, 1.0 - exp(-delta / maxf(tau, 0.001)))


## Un champ de texte de l'interface a le focus (date du panneau…) : les touches lui sont destinées.
static func is_typing(node: Node) -> bool:
	return node.get_viewport().gui_get_focus_owner() is LineEdit


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_set_looking(event.pressed)
	elif event is InputEventMouseMotion and _looking:
		_look_pending += event.relative * mouse_sensitivity


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
