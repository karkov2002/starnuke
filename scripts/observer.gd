class_name Observer
extends CharacterBody3D
## Corps de l'observateur dans la station (nœud Observer de scenes/orbit_view.tscn), parent de la caméra
## (scripts/station_camera.gd, orientation). Déplacement en apesanteur : mode « flottant » (ni gravité ni sol),
## collision sphérique contre les parois de la station et les objets intérieurs (collisions générées à l'import et
## par Station au démarrage).
## - avancer / reculer dans la direction du regard (y compris vers le haut ou le bas) : move_forward, move_back
##   (Z / S en AZERTY, W / S en QWERTY, flèches haut / bas) ;
## - déplacement latéral : move_left, move_right (Q / D en AZERTY, A / D en QWERTY, flèches gauche / droite).
## Inertie d'apesanteur : double lissage (commande lissée, puis vitesse lissée vers la commande), soit une courbe en S
## sans à-coup au démarrage ni à l'arrivée (~1 s pour atteindre la vitesse de croisière ou s'arrêter) ; contre une
## paroi, le mouvement glisse le long d'elle.

@export var camera_path: NodePath = ^"Camera"
## Vitesse de croisière (m/s) : un astronaute se déplace à ~0,5–1,5 m/s dans l'ISS.
@export var speed := 1.5
## Constante de temps de l'inertie (s).
@export var smoothing_s := 0.25

var _drive := Vector3.ZERO

@onready var _camera: Camera3D = get_node(camera_path)


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not StationCamera.is_typing(self):
		input = Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_back", &"move_forward"))
	var view := _camera.global_basis.orthonormalized()
	var wish := (-view.z * input.y + view.x * input.x)
	if wish.length() > 1.0:
		wish = wish.normalized()
	_drive = StationCamera.smooth_toward(_drive, wish * speed, delta, smoothing_s)
	velocity = StationCamera.smooth_toward(velocity, _drive, delta, smoothing_s)
	if velocity.length() < 1e-3 and _drive.length() < 1e-3:
		velocity = Vector3.ZERO
		_drive = Vector3.ZERO
		return
	move_and_slide()
