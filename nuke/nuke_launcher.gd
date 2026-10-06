class_name NukeLauncher
extends Node
## Tir d'un missile sur le point de la Terre visé par l'observateur (centre de la vue).
##
## La visée est un rayon partant de la caméra par le centre de l'écran, intersecté avec la sphère terrestre
## (rayon réel × SCENE_UNITS_PER_KM). S'il manque la Terre (ciel, limbe), il ne se passe rien. Le point touché est
## exprimé dans le repère local du nœud Earth (qui tourne avec la planète, cf. scripts/orbit.gd) et en lat/lon.
##
## Pour l'instant l'impact n'est matérialisé que par un marqueur provisoire ; l'explosion viendra le remplacer.

## Émis à chaque tir réussi. local_position : point d'impact dans le repère du nœud Earth (unités de la scène).
signal detonated(latitude_deg: float, longitude_deg: float, yield_kt: float, local_position: Vector3)

const GROUP := &"nuke_launcher"
const YIELDS_KT: Array[float] = [10.0, 100.0, 500.0, 1000.0, 10000.0, 50000.0]

@export var earth_path: NodePath = ^"../Earth"
## Durée d'affichage du marqueur provisoire d'impact (s).
@export var marker_duration_s := 5.0

var _earth: Node3D


func _ready() -> void:
	add_to_group(GROUP)
	_earth = get_node(earth_path)


## Point visé par le centre de la vue : {local (repère de Earth), latitude, longitude} en degrés, ou {} si le
## rayon manque la Terre.
func get_aim() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _earth == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	var oc := origin - _earth.global_position
	var b := oc.dot(direction)
	var discriminant := b * b - (oc.length_squared() - radius * radius)
	if discriminant < 0.0:
		return {}
	var t := -b - sqrt(discriminant)
	if t <= 0.0:
		return {}
	var local := _earth.global_transform.affine_inverse() * (origin + direction * t)
	# Repère du maillage (SphereMesh : +Y = nord, +Z = longitude −180°) vers ECEF, cf. Orbit.mesh_to_ecef.
	var lat_lon := OrbitSimulation.ecef_to_lat_lon(Vector3(-local.z, -local.x, local.y))
	return {"local": local, "latitude": lat_lon.x, "longitude": lat_lon.y}


## Tire sur le point visé. Retourne false (et ne fait rien) si la vue ne vise pas la Terre.
func launch(yield_kt: float) -> bool:
	var aim := get_aim()
	if aim.is_empty():
		return false
	_spawn_marker(aim.local)
	print("NukeLauncher : %s sur %.2f°, %.2f°" % [format_yield(yield_kt), aim.latitude, aim.longitude])
	detonated.emit(aim.latitude, aim.longitude, yield_kt, aim.local)
	return true


static func format_yield(yield_kt: float) -> String:
	return "%d kt" % roundi(yield_kt) if yield_kt < 1000.0 else "%d Mt" % roundi(yield_kt / 1000.0)


# Marqueur provisoire : petite sphère rouge lumineuse (3 km de rayon) posée au point d'impact, enfant de Earth pour
# rester accrochée au sol.
func _spawn_marker(local: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.radial_segments = 16
	mesh.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(6.0, 0.6, 0.2) # HDR : au-dessus du seuil du glow
	# Transparent et rendu après les nuages et l'atmosphère (qui n'écrivent pas la profondeur) : visible même sous
	# un banc nuageux, mais toujours masqué par la station (opaque).
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 2
	mesh.material = material
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_earth.add_child(marker)
	marker.position = local
	get_tree().create_timer(marker_duration_s).timeout.connect(marker.queue_free)
