class_name Observer
extends CharacterBody3D
## Corps de l'observateur dans la station (nœud Observer de scenes/orbit_view.tscn), parent de la caméra
## (scripts/station_camera.gd, orientation). Déplacement en apesanteur : mode « flottant » (ni gravité ni sol),
## collision sphérique contre les parois de la station et les objets intérieurs (collisions générées à l'import et
## par Station au démarrage).
## - avancer / reculer dans la direction du regard (y compris vers le haut ou le bas) : move_forward, move_back
##   (Z / S en AZERTY, W / S en QWERTY, flèches haut / bas) ;
## - déplacement latéral : move_left, move_right (Q / D en AZERTY, A / D en QWERTY, flèches gauche / droite).
## Accélération et freinage progressifs (on se pousse sur les mains courantes, on se freine) ; contre une paroi, le
## mouvement glisse le long d'elle.

@export var camera_path: NodePath = ^"Camera"
## Vitesse de croisière (m/s) : un astronaute se déplace à ~0,5–1,5 m/s dans l'ISS.
@export var speed := 1.5
@export var acceleration := 3.0
@export var braking := 4.0

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
	var target := wish * speed
	var rate := acceleration if wish.length() > 0.0 else braking
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
