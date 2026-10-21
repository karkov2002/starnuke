class_name TargetMarker
extends Control
## Cibles au sol (GroundTarget, jusqu'à 5) en surimpression sur la Terre, chacune de sa couleur (GroundTarget.COLORS),
## dans la cupola en mode « HUD : On » (calque du Hud) :
## - chaque cible posée à l'horizontale sur la Terre, qui en épouse la courbure : trois anneaux concentriques et une
##   croix (RINGS_KM, ARMS_KM), tracés sur la sphère (distances le long du sol depuis le point visé) dans un maillage
##   enfant du nœud Earth (il tourne avec la planète ; une surface par cible) ; la cible choisie pleine, les autres
##   plus pâles (OTHER_ALPHA) ; matériau sans éclairage, dessiné après les nuages (tri) avec test de profondeur
##   (cachée par la station, pas par les nuages qui n'écrivent pas de profondeur), reconstruit quand les cibles
##   changent ;
## - une flèche au bord de l'écran (calque 2D), dans sa couleur, quand la cible choisie est hors champ. Pas de
##   coordonnées dans le HUD (elles masqueraient la vue) : elles sont sur les cartes.
## Rien n'est affiché pour un point sous l'horizon (face cachée de la Terre) ou derrière la caméra.

## Anneaux : distance au centre et largeur (km, le long du sol).
const RINGS_KM: Array[Vector2] = [Vector2(40.0, 8.0), Vector2(80.0, 7.0), Vector2(120.0, 6.0)]
## Branches de la croix : du centre (km) à l'extrémité, largeur.
const ARMS_KM := Vector3(132.0, 185.0, 7.0)
const CENTER_KM := 10.0
## Hauteur au-dessus du sol (km).
const LIFT_KM := 2.0
const SEGMENTS := 96
const EDGE_MARGIN := 36.0
## Opacité des cibles non choisies.
const OTHER_ALPHA := 0.45

var earth: Node3D
## Affichée (Hud : cupola et overlay_enabled).
var shown := false:
	set(value):
		shown = value
		queue_redraw()

var _target: GroundTarget
var _mesh: MeshInstance3D
## Matériaux par cible : Vector2i(emplacement, choisie) -> StandardMaterial3D.
var _materials := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if earth:
		_mesh = MeshInstance3D.new()
		_mesh.name = "GroundTargetMarker"
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.visible = false
		# Tri des objets transparents : après les nuages et l'atmosphère (qui sinon la recouvrent).
		_mesh.sorting_offset = 100000.0
		earth.add_child.call_deferred(_mesh)


func _exit_tree() -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.queue_free()


## Matériau d'une cible : sa couleur, pleine si elle est choisie, pâle sinon (créé une fois).
func _material(slot: int, chosen: bool) -> StandardMaterial3D:
	var key := Vector2i(slot, int(chosen))
	if _materials.has(key):
		return _materials[key]
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Couleur de la cible, saturée (au-delà de 1, le tonemapping la blanchirait sur les nuages).
	marker_material.albedo_color = Color(GroundTarget.color_of(slot), 0.95 if chosen else OTHER_ALPHA)
	# Test de profondeur gardé : la station (structure de la cupola) la cache ; les nuages et l'atmosphère
	# n'écrivent pas de profondeur, ils ne la cachent pas.
	marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker_material.render_priority = 10
	_materials[key] = marker_material
	return marker_material


func _process(_delta: float) -> void:
	var target := _get_target()
	var any_visible := false
	if shown and target:
		for slot in target.active_slots():
			if _screen_point(target.get_target(slot)) != Vector2.INF:
				any_visible = true
				break
	if _mesh:
		_mesh.visible = any_visible
	if shown:
		queue_redraw()


func _get_target() -> GroundTarget:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
		if _target:
			_target.changed.connect(_rebuild)
			_rebuild()
	return _target


## Position à l'écran d'une cible (latitude, longitude) visible de la caméra : devant elle et au-dessus de l'horizon ;
## Vector2.INF sinon (y compris hors de l'écran, voir _draw pour la flèche).
func _screen_point(point: Vector2) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null or earth == null:
		return Vector2.INF
	var world := earth.global_transform * (GeoMath.lat_lon_to_mesh(point.x, point.y) * OrbitSimulation.EARTH_RADIUS_UNITS)
	if (camera.global_position - world).dot(world - earth.global_position) <= 0.0 or camera.is_position_behind(world):
		return Vector2.INF
	return camera.unproject_position(world)


## Maillage des cibles, sur la sphère (repère du nœud Earth) : une surface par cible, dans sa couleur.
func _rebuild() -> void:
	if _mesh == null or _target == null:
		return
	var mesh := ArrayMesh.new()
	for slot in _target.active_slots():
		var point := _target.get_target(slot)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _target_vertices(point.x, point.y)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(slot, slot == _target.selected))
	_mesh.mesh = mesh


## Triangles d'une cible (anneaux, croix, centre) autour de (lat, lon).
func _target_vertices(lat_deg: float, lon_deg: float) -> PackedVector3Array:
	var up := GeoMath.lat_lon_to_mesh(lat_deg, lon_deg)
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
	return vertices


func _draw() -> void:
	if not shown or earth == null:
		return
	var target := _get_target()
	if target == null:
		return
	if not target.has_target(target.selected):
		return
	var at := _screen_point(target.get_target(target.selected))
	var screen := get_viewport_rect().size
	if at == Vector2.INF or Rect2(Vector2.ZERO, screen).grow(-EDGE_MARGIN).has_point(at):
		return
	# Cible choisie hors champ : flèche au bord de l'écran, vers elle, dans sa couleur.
	var middle := screen * 0.5
	var direction := (at - middle).normalized()
	var edge := middle + direction * minf((screen.x * 0.5 - EDGE_MARGIN) / maxf(absf(direction.x), 1e-3),
			(screen.y * 0.5 - EDGE_MARGIN) / maxf(absf(direction.y), 1e-3))
	var side := direction.orthogonal() * 9.0
	draw_colored_polygon(PackedVector2Array([edge + direction * 14.0, edge + side, edge - side]),
			GroundTarget.color_of(target.selected))
