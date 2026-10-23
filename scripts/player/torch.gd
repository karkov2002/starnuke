class_name Torch
extends SpotLight3D
## Lampe torche de l'observateur (nœud Torch, enfant de la caméra dans orbit_view.tscn) : allumée ou éteinte par
## l'action « torch » (touche physique L). Tenue légèrement en dessous et à droite du regard, elle éclaire devant
## (cône spot_angle, portée spot_range), avec ombres portées : la lumière ne traverse pas les parois. Utile quand la
## station est éteinte (« plus de lumière », Station.Alert.BLACKOUT). Léger tremblement de la main qui la tient :
## le faisceau dévie de shake_deg au plus (bruit lisse, shake_hz), avec un peu plus de sursauts dès qu'on se déplace
## (vitesse de l'observateur).

const ACTION := &"torch"

## Allumée au départ ?
@export var on_at_start := false
@export_group("Tremblement")
## Amplitude angulaire du tremblement (degrés), sa fréquence (Hz) et son amplification en mouvement (par m/s).
@export var shake_deg := 0.7
@export var shake_hz := 1.6
@export var shake_per_m_s := 0.6

var _noise := FastNoiseLite.new()
var _time := 0.0
var _rest: Basis


func _ready() -> void:
	visible = on_at_start
	_rest = basis
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 7


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta * shake_hz
	var body := get_parent().get_parent() as CharacterBody3D
	var speed := body.velocity.length() if body else 0.0
	var amplitude := deg_to_rad(shake_deg) * (1.0 + shake_per_m_s * speed)
	var yaw := _noise.get_noise_2d(_time, 0.0) * amplitude
	var pitch := _noise.get_noise_2d(0.0, _time + 37.0) * amplitude
	basis = _rest * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION) and not event.is_echo():
		visible = not visible
		get_viewport().set_input_as_handled()
