class_name Hud
extends CanvasLayer
## Interface à l'écran de la partie (nœud Hud de scenes/orbit_view.tscn, construite en code) :
## - barre de vitesse du temps (TimeBar), toujours visible, en haut au centre ;
## - réticule de tir (nuke/aim_reticle.gd) au centre, seulement dans la cupola (Station.is_in_cupola), avec un fondu
##   de FADE_S : hors de la cupola, on ne peut pas tirer ;
## - chronomètres des missiles (ImpactTimers, ajoutés par LaunchControl), en bas à droite.
## Affichage en surimpression dans la cupola (overlay_enabled, bouton « HUD : On / Off » de la tablette, désactivé au
## départ) : éléments 3D vus à travers les vitres, comme l'anneau de l'orbite visée (GhostTrack), et les cibles au sol
## posées sur la carte du poste (TargetMarker, chacune de sa couleur) et le cône de tir (FiringConeMarker : secteur au
## sol devant la station où l'on peut viser, FiringCone) ; masqués si désactivé.
## Le reste des commandes (date, carte, silos, tir, BURN) est sur la tablette (scripts/tablet.gd, touche Tab).

signal overlay_changed(enabled: bool)

const GROUP := &"hud"
const FADE_S := 0.5
const AimReticleScript := preload("res://nuke/aim_reticle.gd")

@export var orbit_path: NodePath = ^"../Orbit"
@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var earth_path: NodePath = ^"../Earth"

var _station: Station
var _reticle: Control
var _target_marker: TargetMarker
var _cone_marker: FiringConeMarker
var _time_bar: TimeBar
var _in_cupola := true
var _fade: Tween
## Surimpression dans la cupola (voir en tête).
var overlay_enabled := false


func _ready() -> void:
	add_to_group(GROUP)
	_station = get_node_or_null(station_path) as Station
	_reticle = AimReticleScript.new()
	_reticle.name = "AimReticle"
	add_child(_reticle)
	_target_marker = TargetMarker.new()
	_target_marker.name = "TargetMarker"
	_target_marker.earth = get_node_or_null(earth_path) as Node3D
	add_child(_target_marker)
	_target_marker.shown = overlay_enabled and _in_cupola
	_cone_marker = FiringConeMarker.new()
	_cone_marker.name = "FiringConeMarker"
	_cone_marker.earth = _target_marker.earth
	_cone_marker.orbit = get_node(orbit_path) as OrbitSimulation
	add_child(_cone_marker)
	_cone_marker.shown = overlay_enabled and _in_cupola
	_time_bar = TimeBar.new()
	_time_bar.orbit = _cone_marker.orbit
	add_child(_time_bar)
	_time_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_time_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if _station == null or camera == null:
		return
	var inside := _station.is_in_cupola(camera.global_position)
	if inside == _in_cupola:
		return
	_in_cupola = inside
	_target_marker.shown = overlay_enabled and inside
	_cone_marker.shown = overlay_enabled and inside
	if _fade:
		_fade.kill()
	if inside:
		_reticle.visible = true
	_fade = create_tween()
	_fade.tween_property(_reticle, "modulate:a", 1.0 if inside else 0.0, FADE_S)
	if not inside:
		_fade.tween_callback(func() -> void: _reticle.visible = false)


func set_overlay_enabled(enabled: bool) -> void:
	if enabled == overlay_enabled:
		return
	overlay_enabled = enabled
	if _target_marker:
		_target_marker.shown = enabled and _in_cupola
	if _cone_marker:
		_cone_marker.shown = enabled and _in_cupola
	overlay_changed.emit(enabled)


## La position (repère de l'écran) est-elle sur la barre du temps ? (Le poste de pilotage lui laisse la souris.)
func is_over_controls(screen_position: Vector2) -> bool:
	return _time_bar.get_global_rect().has_point(screen_position)


## Style des panneaux de l'interface à l'écran.
static func panel_style() -> StyleBoxFlat:
	return UiKit.flat_box(Color(0.05, 0.07, 0.1, 0.72), Color(0.55, 0.7, 0.9, 0.35), 1, 10, 6.0)
