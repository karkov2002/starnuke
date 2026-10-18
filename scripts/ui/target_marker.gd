class_name TargetMarker
extends Control
## Cible au sol (GroundTarget) en surimpression jaune sur la Terre, dans la cupola en mode « HUD : On » (calque du
## Hud) :
## - une cible posée à l'horizontale sur la Terre, qui en épouse la courbure : trois anneaux concentriques et une croix
##   (RINGS_KM, ARMS_KM), tracés sur la sphère (distances le long du sol depuis le point visé) dans un maillage enfant
##   du nœud Earth (il tourne avec la planète) ; matériau sans éclairage, toujours visible (surimpression, pas de test
##   de profondeur : par-dessus les nuages), reconstruit quand la cible change ;
## - une flèche au bord de l'écran (calque 2D) quand la cible est hors champ. Pas de coordonnées dans le HUD (elles
##   masqueraient la vue) : elles sont sur les cartes.
## Rien n'est affiché si le point visé est sous l'horizon (face cachée de la Terre) ou derrière la caméra.

## Anneaux : distance au centre et largeur (km, le long du sol).
const RINGS_KM: Array[Vector2] = [Vector2(40.0, 8.0), Vector2(80.0, 7.0), Vector2(120.0, 6.0)]
## Branches de la croix : du centre (km) à l'extrémité, largeur.
const ARMS_KM := Vector3(132.0, 185.0, 7.0)
const CENTER_KM := 10.0
## Hauteur au-dessus du sol (km).
const LIFT_KM := 2.0
const SEGMENTS := 96
const EDGE_MARGIN := 36.0

var earth: Node3D
## Affichée (Hud : cupola et overlay_enabled).
var shown := false:
	set(value):
		shown = value
		queue_redraw()

var _target: GroundTarget
var _mesh: MeshInstance3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if earth:
		_mesh = MeshInstance3D.new()
		_mesh.name = "GroundTargetMarker"
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.visible = false
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Couleur de la cible, saturée (au-delà de 1, le tonemapping la blanchirait sur les nuages).
		material.albedo_color = Color(GroundTarget.COLOR, 0.95)
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.render_priority = 10
		# Tri des objets transparents : après les nuages et l'atmosphère (qui sinon la recouvrent).
		_mesh.sorting_offset = 100000.0
		_mesh.material_override = material
		earth.add_child.call_deferred(_mesh)


func _exit_tree() -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.queue_free()


func _process(_delta: float) -> void:
	var target := _get_target()
	var visible_point := false
	if shown and target and target.active:
		var camera := get_viewport().get_camera_3d()
		if camera:
			var point := earth.global_transform * GroundTarget.earth_local(target.latitude_deg, target.longitude_deg)
			visible_point = (camera.global_position - point).dot(point - earth.global_position) > 0.0 \
					and not camera.is_position_behind(point)
	if _mesh:
		_mesh.visible = visible_point
	if shown:
		queue_redraw()


func _get_target() -> GroundTarget:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
		if _target:
			_target.changed.connect(_rebuild)
			_rebuild()
	return _target


## Maillage de la cible, sur la sphère, autour du point visé (repère du nœud Earth).
func _rebuild() -> void:
	if _mesh == null or _target == null or not _target.active:
		return
	var up := GroundTarget.earth_local(_target.latitude_deg, _target.longitude_deg).normalized()
	var east := Vector3.UP.cross(up)
	if east.length() < 1e-4:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var radius := (OrbitSimulation.EARTH_RADIUS_KM + LIFT_KM) * OrbitSimulation.SCENE_UNITS_PER_KM
	# Point au sol à la distance d (km, le long du grand cercle) dans la direction d'azimut a (rad, depuis l'est).
	var ground := func(d_km: float, a: float) -> Vector3:
		var theta := d_km / OrbitSimulation.EARTH_RADIUS_KM
		return (up * cos(theta) + (east * cos(a) + north * sin(a)) * sin(theta)).normalized() * radius
	var vertices := PackedVector3Array()
	var add_quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	for ring in RINGS_KM:
		for i in SEGMENTS:
			var a0 := TAU * i / SEGMENTS
			var a1 := TAU * (i + 1) / SEGMENTS
			add_quad.call(ground.call(ring.x - ring.y * 0.5, a0), ground.call(ring.x + ring.y * 0.5, a0),
					ground.call(ring.x + ring.y * 0.5, a1), ground.call(ring.x - ring.y * 0.5, a1))
	for k in 4:
		var a := PI * 0.5 * k
		var steps := 6
		for s in steps:
			var d0: float = lerpf(ARMS_KM.x, ARMS_KM.y, float(s) / steps)
			var d1: float = lerpf(ARMS_KM.x, ARMS_KM.y, float(s + 1) / steps)
			var half0 := ARMS_KM.z * 0.5 / d0
			var half1 := ARMS_KM.z * 0.5 / d1
			add_quad.call(ground.call(d0, a - half0), ground.call(d0, a + half0), ground.call(d1, a + half1),
					ground.call(d1, a - half1))
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		vertices.append_array(PackedVector3Array([up * radius, ground.call(CENTER_KM, a0), ground.call(CENTER_KM, a1)]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.mesh = mesh


func _draw() -> void:
	if not shown or earth == null:
		return
	var target := _get_target()
	var camera := get_viewport().get_camera_3d()
	if target == null or not target.active or camera == null:
		return
	var point := earth.global_transform * GroundTarget.earth_local(target.latitude_deg, target.longitude_deg)
	if (camera.global_position - point).dot(point - earth.global_position) <= 0.0 or camera.is_position_behind(point):
		return
	var color := GroundTarget.COLOR
	var screen := get_viewport_rect().size
	var at := camera.unproject_position(point)
	if not Rect2(Vector2.ZERO, screen).grow(-EDGE_MARGIN).has_point(at):
		# Hors champ : flèche au bord de l'écran, vers la cible.
		var middle := screen * 0.5
		var direction := (at - middle).normalized()
		var edge := middle + direction * minf((screen.x * 0.5 - EDGE_MARGIN) / maxf(absf(direction.x), 1e-3),
				(screen.y * 0.5 - EDGE_MARGIN) / maxf(absf(direction.y), 1e-3))
		var side := direction.orthogonal() * 9.0
		draw_colored_polygon(PackedVector2Array([edge + direction * 14.0, edge + side, edge - side]), color)
		return
