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
## Courant d'air (règle de jeu, StationAtmosphere : porte extérieure du sas ouverte) : une poussée s'ajoute au
## déplacement (set_air_flow : elle rejoint le courant en air_response_s) ; le joueur garde ses commandes. Dans le vide,
## plus d'air : la poussée garde son élan ; combinaison enfilée, son propulseur dorsal (SAFER) l'amortit.
## Départ (règle de jeu) : allongé dans la couchette de l'Habitation, le regard vers ses pieds : la caméra prend la
## position et l'orientation du repère start_marker du modèle de la station (Point_Vue_Couchette).

@export var camera_path: NodePath = ^"Camera"
## Repère de départ (enfant de la station ; base d'une Camera3D : −Z regard, +Y haut). Vide : position de la scène.
@export var start_marker := "Point_Vue_Couchette"
## Vitesse de croisière (m/s) : un astronaute se déplace à ~0,5–1,5 m/s dans l'ISS.
@export var speed := 1.5
## Constante de temps de l'inertie (s).
@export var smoothing_s := 0.25

## Commandes du joueur (coupées par la séquence de mort : le corps reste porté par le courant).
var controls_enabled := true
var _drive := Vector3.ZERO
## Vitesse propre (commandes) et poussée du courant d'air.
var _own := Vector3.ZERO
var _blast := Vector3.ZERO
var _flow := Vector3.ZERO
var _flow_response_s := INF

@onready var _camera: Camera3D = get_node(camera_path)


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_place_at_start.call_deferred()


## Corps au repère de départ (orientation neutre), caméra orientée comme lui. Seulement en partie (scène du jeu
## courante) : le décor du menu et les bancs de mesure (tools/bench, scène du jeu instanciée sous la leur) gardent la
## position de la scène, dans la cupola.
func _place_at_start() -> void:
	if owner == null or owner != get_tree().current_scene:
		return
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Node3D
	var marker := station.find_child(start_marker, true, false) as Node3D if station and start_marker != "" else null
	if marker == null:
		return
	global_transform = Transform3D(Basis.IDENTITY, marker.global_position - _camera.position)
	_camera.global_basis = marker.global_basis.orthonormalized()


## Courant d'air au point de l'observateur (vitesse visée, m/s, repère global) et temps de réponse de la poussée (s ;
## INF : elle garde son élan).
func set_air_flow(flow: Vector3, response_s: float) -> void:
	_flow = flow
	_flow_response_s = response_s


## Poussée actuelle du courant d'air (m/s, repère global).
func get_blast() -> Vector3:
	return _blast


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled and not StationCamera.is_typing(self):
		input = Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_back", &"move_forward"))
	var view := _camera.global_basis.orthonormalized()
	var wish := (-view.z * input.y + view.x * input.x)
	if wish.length() > 1.0:
		wish = wish.normalized()
	_drive = StationCamera.smooth_toward(_drive, wish * speed, delta, smoothing_s)
	_own = StationCamera.smooth_toward(_own, _drive, delta, smoothing_s)
	if is_finite(_flow_response_s):
		_blast = StationCamera.smooth_toward(_blast, _flow, delta, _flow_response_s)
	velocity = _own + _blast
	if velocity.length() < 1e-3 and _drive.length() < 1e-3:
		velocity = Vector3.ZERO
		_drive = Vector3.ZERO
		_own = Vector3.ZERO
		_blast = Vector3.ZERO
		return
	move_and_slide()
	# Contre une paroi, le mouvement glisse le long d'elle (vitesse propre comme poussée).
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if _own.dot(normal) < 0.0:
			_own = _own.slide(normal)
		if _blast.dot(normal) < 0.0:
			_blast = _blast.slide(normal)
