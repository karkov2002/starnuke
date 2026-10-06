class_name NukeEffect
extends Node3D
## Une explosion (scène nuke/nuke_effect.tscn), enfant du nœud Earth pour rester accrochée au sol.
##
## Repère local de l'effet : origine au point d'impact sur la sphère, Y = verticale locale (normale de la sphère),
## X = est, −Z = nord. Le nœud est mis à l'échelle SCENE_UNITS_PER_KM : ses enfants travaillent directement en km,
## avec des coordonnées petites (précision flottante), quelle que soit la position de la Terre dans la scène.
##
## Phases : flash initial (enfant Flash, nuke/nuke_flash.tscn). Marqueurs de debug optionnels (show_debug_markers)
## aux tailles calculées par NukeScaling : boule de feu (orange), rayon de choc de référence (anneau jaune au sol),
## colonne et chapeau du nuage (cyan).

const MARKER_RENDER_PRIORITY := 2 # après les nuages (0) et l'atmosphère (1), qui n'écrivent pas la profondeur

@export var params: NukeParams
@export var show_debug_markers := false:
	set(value):
		show_debug_markers = value
		if is_node_ready():
			_markers.visible = value
## Temps physique imposé (s), pour rejouer l'effet (scrubber) ; négatif : temps de l'horloge NukeClock.
var time_override_s := -1.0

@onready var _markers: Node3D = $DebugMarkers


func _ready() -> void:
	if params == null:
		params = NukeParams.new()
	place()
	_build_debug_markers()


## Place l'effet au point (latitude, longitude) de params, sur la sphère terrestre du parent (nœud Earth).
func place() -> void:
	var lat := deg_to_rad(params.latitude_deg)
	var lon := deg_to_rad(params.longitude_deg)
	# ECEF (x vers 0°, y vers 90° E, z nord) vers le repère du maillage (SphereMesh : +Y nord, +Z vers −180°).
	var up := Vector3(-cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))
	var east := Vector3(-cos(lon), 0.0, sin(lon))
	var south := east.cross(up)
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	transform = Transform3D(Basis(east, up, south).scaled(Vector3.ONE * OrbitSimulation.SCENE_UNITS_PER_KM),
			up * radius)


## Temps physique (s) écoulé depuis l'explosion.
func get_flash() -> NukeFlash:
	return get_node_or_null(^"Flash") as NukeFlash


func get_time_s() -> float:
	if time_override_s >= 0.0:
		return time_override_s
	return NukeClock.physical_time(params.start_time_s)


func _build_debug_markers() -> void:
	_markers.visible = show_debug_markers
	var w := params.yield_kt
	var fireball := NukeScaling.fireball_radius_km(w)
	var shock := NukeScaling.shock_radius_km(w)
	var top := NukeScaling.cloud_top_km(w)
	var cap := NukeScaling.cloud_cap_radius_km(w)

	var ball := SphereMesh.new()
	ball.radius = fireball
	ball.height = 2.0 * fireball
	_add_marker("Fireball", ball, Color(4.0, 1.4, 0.3, 0.7), Vector3(0.0, params.burst_height_km, 0.0))

	var ring := TorusMesh.new()
	ring.inner_radius = shock * 0.97
	ring.outer_radius = shock * 1.03
	ring.rings = 64
	_add_marker("ShockRing", ring, Color(2.0, 1.8, 0.2, 0.8), Vector3(0.0, 0.1, 0.0))

	var column := CylinderMesh.new()
	column.top_radius = maxf(top * 0.04, 0.3)
	column.bottom_radius = column.top_radius
	column.height = top
	_add_marker("CloudColumn", column, Color(0.25, 0.8, 1.0, 0.3), Vector3(0.0, top * 0.5, 0.0))

	var disc := CylinderMesh.new()
	disc.top_radius = cap
	disc.bottom_radius = cap
	disc.height = maxf(top * 0.03, 0.2)
	disc.radial_segments = 64
	_add_marker("CloudCap", disc, Color(0.25, 0.8, 1.0, 0.3), Vector3(0.0, top, 0.0))


func _add_marker(marker_name: String, mesh: PrimitiveMesh, color: Color, at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color # composantes > 1 : HDR, au-dessus du seuil du glow
	material.render_priority = MARKER_RENDER_PRIORITY
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = marker_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	_markers.add_child(instance)
