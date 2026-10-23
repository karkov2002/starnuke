class_name DeathSequence
extends CanvasLayer
## Séquence de mort du joueur (créée par scripts/airlock_hazard.gd, enfant de la scène du jeu) : les commandes sont
## coupées (déplacements, regard, interactions, tablette), puis la vue se ferme comme des yeux qui se ferment
## (shaders/eyelids.gdshader : paupières noires et floues arrivant du haut et du bas, vue qui se brouille), avec un
## dernier effort pour les rouvrir. Écran noir : écran « Vous êtes mort » (scenes/ui/death_screen.tscn).
## Le corps reste porté par le courant d'air (Observer) : expulsé, il traverse la station et sort ; dehors, il dérive
## sur son élan, le regard tourné vers la station qui s'éloigne et qui tourne lentement (on roule sur soi-même).

const DEATH_SCREEN := "res://scenes/ui/death_screen.tscn"
const EYELIDS_SHADER := preload("res://shaders/eyelids.gdshader")

## Fermeture des yeux : (instant, fermeture 0–1) ; un dernier effort les rouvre un peu avant la fin.
const CLOSING := [Vector2(0.0, 0.0), Vector2(1.4, 0.62), Vector2(1.9, 0.38), Vector2(3.4, 1.0)]
## Délai avant la fermeture des yeux : sur place (asphyxie), et emporté par le courant ou dehors (on voit la station
## s'éloigner) ; plus on s'éloigne lentement, plus on la voit longtemps (jusqu'à SLOW_EXTRA_DELAY_S de plus, sous
## FAST_SPEED).
const DELAY_ASPHYXIA_S := 1.2
const DELAY_EJECTION_S := 3.5
const SLOW_EXTRA_DELAY_S := 3.0
const FAST_SPEED := 9.0
## Vitesse (m/s) au-dessus de laquelle on est emporté.
const CARRIED_SPEED := 1.0
## Rotation sur soi dehors (rad/s) et temps pour tourner le regard vers la station (s).
const TUMBLE_RAD_S := 0.45
const TURN_S := 0.8

var _observer: Observer
var _camera: Camera3D
var _station: Station
var _eyelids: ShaderMaterial
var _time := 0.0
var _delay := DELAY_ASPHYXIA_S
var _look_target := Vector3.ZERO
var _look_up := Vector3.RIGHT
var _outside_time := -1.0
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
## couper (interactions…) ; station (observer_outside : dehors) ; look_target : point de la station à regarder dehors,
## look_up : haut de la vue.
func start(observer: Observer, disabled: Array[Node], station: Station, look_target: Vector3,
		look_up := Vector3.RIGHT) -> void:
	_observer = observer
	_station = station
	_camera = observer.get_node_or_null("Camera") as Camera3D
	observer.controls_enabled = false
	for node in disabled + [_camera as Node]:
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var tablet := _camera.get_node_or_null("Tablet") as Node3D if _camera else null
	if tablet:
		tablet.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_look_target = look_target
	_look_up = look_up.normalized()
	var speed := observer.get_blast().length()
	if station.observer_outside or speed > CARRIED_SPEED:
		_delay = DELAY_EJECTION_S + SLOW_EXTRA_DELAY_S * (1.0 - clampf(speed / FAST_SPEED, 0.0, 1.0))


func _process(delta: float) -> void:
	if _observer == null or _done:
		return
	_time += delta
	if _station.observer_outside:
		_look_at_station(delta)
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


## Dehors : le regard se tourne (sans saut) vers la station, qui tourne lentement.
func _look_at_station(delta: float) -> void:
	if _camera == null:
		return
	if _outside_time < 0.0:
		_outside_time = 0.0
	_outside_time += delta
	var to_target := _look_target - _camera.global_position
	if to_target.length() < 0.01:
		return
	var dir := to_target.normalized()
	var up := _look_up.rotated(dir, TUMBLE_RAD_S * _outside_time)
	if absf(up.dot(dir)) > 0.98:
		up = dir.cross(Vector3.RIGHT).normalized()
	var w := 1.0 - exp(-delta / TURN_S)
	_camera.global_basis = _camera.global_basis.orthonormalized().slerp(Basis.looking_at(to_target, up), w)
