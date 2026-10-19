class_name DeathSequence
extends CanvasLayer
## Séquence de mort du joueur (créée par scripts/airlock_hazard.gd, enfant de la scène du jeu) : les commandes sont
## coupées (observateur, regard, interactions, tablette), puis la vue se ferme comme des yeux qui se ferment
## (shaders/eyelids.gdshader : paupières noires et floues arrivant du haut et du bas, vue qui se brouille), avec un
## dernier effort pour les rouvrir. Écran noir : écran « Vous êtes mort » (scenes/ui/death_screen.tscn).
## Éjection (start avec eject_from) : l'observateur est aspiré vers la porte extérieure du sas, puis projeté dans le vide
## en s'éloignant de plus en plus vite, la caméra tournée vers la station qui s'éloigne et qui tourne lentement.

const DEATH_SCREEN := "res://scenes/ui/death_screen.tscn"
const EYELIDS_SHADER := preload("res://shaders/eyelids.gdshader")

## Fermeture des yeux : (instant, fermeture 0–1) ; un dernier effort les rouvre un peu avant la fin.
const CLOSING := [Vector2(0.0, 0.0), Vector2(1.4, 0.62), Vector2(1.9, 0.38), Vector2(3.4, 1.0)]
## Délai avant la fermeture des yeux : sans éjection (asphyxie) et avec éjection (on voit la station s'éloigner).
const DELAY_ASPHYXIA_S := 1.2
const DELAY_EJECTION_S := 3.5
## Éjection : vitesse de sortie (m/s) et accélération (m/s², souffle continu) par défaut (toute la station se vide par
## le sas), rotation sur soi (rad/s). Aspiration jusqu'à la porte : SUCTION_DISTANCE_S / vitesse, bornée (0,35 s à
## pleine vitesse, plus lente pour un faible souffle). Plus la vitesse est faible, plus on voit longtemps la station
## s'éloigner avant que les yeux se ferment (jusqu'à SLOW_EXTRA_DELAY_S de plus).
const EJECT_SPEED := 9.0
const EJECT_ACCEL := 5.0
const TUMBLE_RAD_S := 0.45
const SUCTION_DISTANCE_S := 3.2
const SUCTION_RANGE_S := Vector2(0.35, 2.5)
const SLOW_EXTRA_DELAY_S := 3.0

var _observer: Node3D
var _camera: Camera3D
var _eyelids: ShaderMaterial
var _time := 0.0
var _delay := DELAY_ASPHYXIA_S
var _ejecting := false
var _start := Vector3.ZERO
var _door := Vector3.ZERO
var _out := Vector3.DOWN
var _look_target := Vector3.ZERO
var _look_up := Vector3.RIGHT
var _start_basis := Basis.IDENTITY
var _speed := EJECT_SPEED
var _accel := EJECT_ACCEL
var _suction_s := SUCTION_RANGE_S.x
var _done := false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_eyelids = ShaderMaterial.new()
	_eyelids.shader = EYELIDS_SHADER
	rect.material = _eyelids
	add_child(rect)


## Lance la séquence. observer : corps de l'observateur (sa caméra est l'enfant « Camera ») ; disabled : nœuds à
## couper (interactions…). eject vrai : éjection par eject_door (position monde de la porte extérieure), le long de
## eject_out (direction de sortie), le regard sur look_target (point de la station), look_up : haut de la vue, à la
## vitesse speed (m/s) puis avec l'accélération accel (m/s²).
func start(observer: Node3D, disabled: Array[Node], eject := false, eject_door := Vector3.ZERO,
		eject_out := Vector3.DOWN, look_target := Vector3.ZERO, look_up := Vector3.RIGHT, speed := EJECT_SPEED,
		accel := EJECT_ACCEL) -> void:
	_observer = observer
	_camera = observer.get_node_or_null("Camera") as Camera3D
	for node in disabled + [observer as Node, _camera as Node]:
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var tablet := _camera.get_node_or_null("Tablet") as Node3D if _camera else null
	if tablet:
		tablet.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ejecting = eject
	if eject:
		_speed = maxf(speed, 0.05)
		_accel = accel
		_suction_s = clampf(SUCTION_DISTANCE_S / _speed, SUCTION_RANGE_S.x, SUCTION_RANGE_S.y)
		_delay = DELAY_EJECTION_S + SLOW_EXTRA_DELAY_S * (1.0 - clampf(_speed / EJECT_SPEED, 0.0, 1.0))
		_start = observer.global_position
		_door = eject_door
		_out = eject_out.normalized()
		_look_target = look_target
		_look_up = look_up.normalized()
		_start_basis = _camera.global_basis.orthonormalized() if _camera else Basis.IDENTITY
		# Dehors : les flashs nucléaires l'atteignent (NukeFlashFX).
		var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
		if station:
			station.observer_outside = true
		# Le corps ne doit plus heurter la station : il est déplacé à la main.
		for shape: CollisionShape3D in observer.find_children("*", "CollisionShape3D", false, false):
			shape.disabled = true


func _process(delta: float) -> void:
	if _observer == null or _done:
		return
	_time += delta
	if _ejecting:
		_eject()
	var t := _time - _delay
	_eyelids.set_shader_parameter("closure", _closure(t))
	if t >= CLOSING[CLOSING.size() - 1].x + 0.4:
		_done = true
		get_tree().change_scene_to_file(DEATH_SCREEN)


func _closure(t: float) -> float:
	if t <= 0.0:
		return 0.0
	for i in range(1, CLOSING.size()):
		var a: Vector2 = CLOSING[i - 1]
		var b: Vector2 = CLOSING[i]
		if t <= b.x:
			return lerpf(a.y, b.y, smoothstep(0.0, 1.0, (t - a.x) / (b.x - a.x)))
	return 1.0


## Aspiré vers la porte (courbe en douceur), puis projeté le long de la direction de sortie, la caméra tournée vers la
## station, qui tourne lentement (on roule sur soi-même).
func _eject() -> void:
	var position: Vector3
	if _time < _suction_s:
		position = _start.lerp(_door, smoothstep(0.0, 1.0, _time / _suction_s))
	else:
		var s := _time - _suction_s
		position = _door + _out * (_speed * s + 0.5 * _accel * s * s)
	_observer.global_position = position
	if _camera == null:
		return
	var to_target := _look_target - _camera.global_position
	if to_target.length() < 0.01:
		return
	var up := _look_up.rotated(to_target.normalized(), TUMBLE_RAD_S * _time)
	if absf(up.dot(to_target.normalized())) > 0.98:
		up = _out.cross(_look_up)
	# Le regard se tourne vers la station pendant l'aspiration (pas de saut de caméra).
	var w := smoothstep(0.0, 1.0, _time / (_suction_s + 0.4))
	_camera.global_basis = _start_basis.slerp(Basis.looking_at(to_target, up), w)
