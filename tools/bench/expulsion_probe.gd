extends Node
## Simulation d'expulsion depuis la cupola (règles du sas, scripts/station_atmosphere.gd et airlock_hazard.gd),
## enregistrée en vidéo par le Movie Maker de Godot : départ dans la cupola, toutes les écoutilles ouvertes (porte
## extérieure du sas comprise) au bout de START_S ; le regard suit le mouvement, comme un joueur qui regarde où il va ;
## dehors, avec la combinaison, il se tourne vers la station. Sans combinaison : séquence de mort et écran de mort.
## Usage (combinaison : argument utilisateur --suit) :
##   godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie <fichier.avi> --quit-after 720
##         res://tools/bench/expulsion_probe.tscn [-- --suit]

const START_S := 3.0
## Temps pour tourner le regard (s).
const LOOK_S := 0.35
## Hors enregistrement : temps d'image (moyen et pire, ms) écrit en console chaque demi-seconde.
const LOG_S := 0.5

var _station: Station
var _observer: Observer
var _camera: Camera3D
var _sas_center := Vector3.ZERO
var _time := 0.0
var _opened := false
var _log_frames := 0
var _log_sum := 0.0
var _log_worst := 0.0
var _log_time := 0.0


func _log_frame_time(delta: float) -> void:
	if OS.get_cmdline_args().has("--write-movie"):
		return
	_log_frames += 1
	_log_sum += delta
	_log_worst = maxf(_log_worst, delta)
	_log_time += delta
	if _log_time >= LOG_S:
		var zone := (get_node("OrbitView/StationAir") as StationAtmosphere).zone_at(_camera.global_position)
		print("t %.1f s  %s  moyenne %.1f ms  pire %.1f ms" % [_time, zone if zone != "" else "dehors",
				_log_sum / _log_frames * 1000.0, _log_worst * 1000.0])
		_log_frames = 0
		_log_sum = 0.0
		_log_worst = 0.0
		_log_time = 0.0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	_station = view.get_node("Station/StationSpatiale") as Station
	_observer = view.get_node("Observer") as Observer
	_camera = view.get_node("Observer/Camera") as Camera3D
	_sas_center = (view.get_node("StationAir") as StationAtmosphere).zone_center(StationAtmosphere.SAS)
	if OS.get_cmdline_user_args().has("--suit"):
		_station.set_suit_worn.call_deferred(true)


func _process(delta: float) -> void:
	if _station == null or not is_instance_valid(_station):
		return
	_time += delta
	_log_frame_time(delta)
	if not _opened and _time >= START_S:
		_opened = true
		_station.set_all_hatches_open(true)
	var dead := not _observer.controls_enabled
	var target := Vector3.ZERO
	if _station.observer_outside:
		if dead:
			return
		target = _sas_center - _camera.global_position
	else:
		var velocity := _observer.get_real_velocity()
		if velocity.length() < 0.5:
			return
		target = velocity
	var up := _camera.global_basis.y
	if absf(target.normalized().dot(up.normalized())) > 0.95:
		up = _camera.global_basis.z
	var wanted := Basis.looking_at(target, up)
	_camera.global_basis = _camera.global_basis.orthonormalized().slerp(wanted, 1.0 - exp(-delta / LOOK_S))
