class_name AirlockHazard
extends Node
## Conséquences des manœuvres du sas de sortie (nœud AirlockHazard de scenes/orbit_view.tscn). Aucun verrouillage :
## la sécurité est l'affaire du joueur. Règles de jeu :
## - **décompression explosive** (dès que l'une des deux commence à s'ouvrir) : porte extérieure et écoutille
##   intérieure ouvertes en même temps (état visé : une écoutille qui se ferme compte comme fermée) : l'air de la
##   station s'échappe par le sas ; l'observateur, s'il est dans le sas (puits compris) ou dans l'Arrimage, est éjecté
##   dans le vide et meurt, combinaison ou non ;
## - **asphyxie** (à chaque image) : observateur dans le sas sans combinaison quand la pression y passe sous
##   death_pressure : vidange par la valve, ou porte extérieure ouverte (l'air du sas s'échappe : Station._vent_airlock).
##   Il meurt sur place, sans éjection.
## Volumes : boîtes des maillages du sas (sas_mesh, puits compris) et du couloir de l'Arrimage (module_mesh), dans le
## repère de la station. Mort : scripts/death_sequence.gd.

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"
## Nœuds coupés pendant la séquence de mort (interactions, poste de pilotage).
@export var disabled_paths: Array[NodePath] = [^"../HatchInteraction"]
## Maillage du sas (parois, puits compris) et du module relié par l'écoutille intérieure.
@export var sas_mesh := "Sas_Paroi*"
@export var module_mesh := "Arrimage_Couloir*"
## Pression (relative, 0–1) sous laquelle on perd connaissance sans combinaison (~0,3 bar).
@export var death_pressure := 0.3

var _station: Station
var _observer: Node3D
var _sas_box: AABB
var _module_box: AABB
var _dead := false


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	_observer = get_node_or_null(observer_path) as Node3D
	if _station == null or _observer == null:
		set_process(false)
		return
	_sas_box = _box_of(sas_mesh)
	_module_box = _box_of(module_mesh)
	_station.hatch_moving.connect(_on_hatch_moving)


func _process(_delta: float) -> void:
	if _dead or _station.is_suit_worn():
		return
	if _air_pressure() < death_pressure and _sas_box.has_point(_station.to_local(_eye())):
		_die(false)


## Pression dans le sas : celle de la station si l'écoutille intérieure est ouverte, sinon celle du manomètre (qui
## tombe à 0 quand la porte extérieure s'ouvre).
func _air_pressure() -> float:
	if _station.is_hatch_opening(_station.airlock_inner_hatch):
		return 1.0
	return _station.get_airlock_pressure()


func _on_hatch_moving(id: String, open: bool) -> void:
	if _dead or not open or (id != _station.airlock_outer_hatch and id != _station.airlock_inner_hatch):
		return
	if not (_station.is_hatch_opening(_station.airlock_outer_hatch)
			and _station.is_hatch_opening(_station.airlock_inner_hatch)):
		return
	var where := _station.to_local(_eye())
	if _sas_box.has_point(where) or _module_box.has_point(where):
		_die(true)


func _die(eject: bool) -> void:
	_dead = true
	var disabled: Array[Node] = []
	for path in disabled_paths:
		var node := get_node_or_null(path)
		if node:
			disabled.append(node)
	var sequence := DeathSequence.new()
	get_tree().current_scene.add_child(sequence)
	# Porte extérieure : bas du sas, sur son axe ; sortie vers le bas du sas (vers la Terre).
	var box := _sas_box
	var door := _station.to_global(Vector3(box.get_center().x, box.position.y, box.get_center().z))
	var out := -_station.global_basis.y.normalized()
	var target := _station.to_global(box.get_center())
	sequence.start(_observer, disabled, eject, door, out, target, _station.global_basis.x)


func _eye() -> Vector3:
	var camera := _observer.get_node_or_null("Camera") as Node3D
	return camera.global_position if camera else _observer.global_position


## Boîte (repère de la station) du premier maillage du modèle dont le nom suit le motif pattern, vide s'il n'y en a pas.
func _box_of(pattern: String) -> AABB:
	var found := _station.find_children(pattern, "MeshInstance3D", true, false)
	if found.is_empty():
		push_warning("AirlockHazard : maillage %s introuvable" % pattern)
		return AABB()
	var mesh := found[0] as MeshInstance3D
	return _station.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
