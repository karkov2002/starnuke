class_name FiringConeMarker
extends Node
## Cône de tir (FiringCone) dessiné sur la Terre dans la cupola en mode « HUD : On » (Hud) : secteur au sol devant
## la station, posé sur la sphère dont il épouse la courbure, en vert :
## - deux bords le long des grands cercles qui partent du point survolé à ± la demi-ouverture de la trace, gradués
##   vers l'intérieur (traits courts tous les TICK_KM, longs tous les MAJOR_TICK_KM) ;
## - l'arc de portée (FiringCone.range_km) qui les relie ;
## - l'axe (la trace) en pointillés, barré tous les AXIS_BAR_KM.
## Épaisseur des traits à peu près constante à l'écran : au sol, elle croît avec la distance à la station (en travers)
## et, dans le sens de la visée, aussi avec l'incidence rasante (sinon l'arc de portée, vu presque à l'horizontale,
## disparaissait).
## Maillage enfant du nœud Earth construit dans un repère type (sommet en +Y, axe vers +X), reconstruit seulement quand
## l'altitude change ; à chaque image, sa transformation le pose sur le point survolé, axe sur la trace. Matériau sans
## éclairage, dessiné après les nuages avec test de profondeur (comme les cibles, TargetMarker : la structure de la
## cupola le cache).

const COLOR := Color(0.3, 1.0, 0.35, 0.8)
## Largeur des traits (km, au sol) vus à la verticale, à la distance de l'altitude.
const LINE_KM := 5.0
## Incidence minimale prise en compte (sinus) : borne l'élargissement des traits proches de l'horizon.
const MIN_GRAZING := 0.2
## Les bords partent à START_KM du point survolé (sous la station : pas de fouillis au sommet).
const START_KM := 40.0
## Graduations des bords : pas et longueur (km), courtes puis longues.
const TICK_KM := 100.0
const TICK_LENGTH_KM := 30.0
const MAJOR_TICK_KM := 500.0
const MAJOR_TICK_LENGTH_KM := 70.0
## Axe : points tous les AXIS_DOT_KM (côté AXIS_DOT_SIZE_KM vu à la verticale), barres de AXIS_BAR_LENGTH_KM tous les
## AXIS_BAR_KM.
const AXIS_DOT_KM := 50.0
const AXIS_DOT_SIZE_KM := 8.0
const AXIS_BAR_KM := 250.0
const AXIS_BAR_LENGTH_KM := 50.0
## Hauteur au-dessus du sol (km) et finesse de l'arc et des bords.
const LIFT_KM := 2.0
const STEP_KM := 25.0
## Reconstruit quand l'altitude change de plus de REBUILD_KM.
const REBUILD_KM := 0.5

var earth: Node3D
var orbit: OrbitSimulation
## Affiché (Hud : cupola et overlay_enabled).
var shown := false:
	set(value):
		shown = value
		if _mesh:
			_mesh.visible = value

var _mesh: MeshInstance3D
var _built_altitude := -INF


func _ready() -> void:
	if earth == null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "FiringConeMarker"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = shown
	# Tri des objets transparents : après les nuages et l'atmosphère (qui sinon le recouvrent).
	_mesh.sorting_offset = 100000.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 10
	_mesh.material_override = material
	earth.add_child.call_deferred(_mesh)


func _exit_tree() -> void:
	if _mesh and is_instance_valid(_mesh):
		_mesh.queue_free()


func _process(_delta: float) -> void:
	if not shown or _mesh == null or orbit == null:
		return
	if absf(orbit.altitude_km - _built_altitude) > REBUILD_KM:
		_built_altitude = orbit.altitude_km
		_mesh.mesh = build(_built_altitude)
	var frame := FiringCone.frame(orbit)
	var up: Vector3 = frame.apex
	var forward: Vector3 = frame.forward
	_mesh.transform = Transform3D(Basis(forward, up, forward.cross(up)), Vector3.ZERO)


## Maillage du cône à l'altitude altitude_km, dans le repère type : sommet en +Y (point survolé), axe (trace) vers +X.
static func build(altitude_km: float) -> ArrayMesh:
	var earth_km := OrbitSimulation.EARTH_RADIUS_KM
	var half := deg_to_rad(FiringCone.aperture_deg(altitude_km)) * 0.5
	var range_km := FiringCone.range_km(altitude_km)
	var radius := (earth_km + LIFT_KM) * OrbitSimulation.SCENE_UNITS_PER_KM
	# Point au sol à la distance d (km, le long du grand cercle) et à l'angle a (rad) de l'axe.
	var ground := func(d_km: float, a: float) -> Vector3:
		var theta := d_km / earth_km
		return (Vector3.UP * cos(theta) + (Vector3.RIGHT * cos(a) + Vector3.BACK * sin(a)) * sin(theta)) * radius
	# Angle vu du sommet qui fait la longueur l (km) en travers, à la distance d.
	var across := func(l_km: float, d_km: float) -> float:
		return l_km / (earth_km * sin(maxf(d_km, 1.0) / earth_km))
	# Facteurs d'élargissement à la distance d : en travers (distance à la station rapportée à l'altitude) et dans le
	# sens de la visée (en plus, l'incidence rasante).
	var scale := func(d_km: float) -> Vector2:
		var theta := d_km / earth_km
		var slant := sqrt(earth_km * earth_km + pow(earth_km + altitude_km, 2.0)
				- 2.0 * earth_km * (earth_km + altitude_km) * cos(theta))
		var grazing := maxf(((earth_km + altitude_km) * cos(theta) - earth_km) / slant, MIN_GRAZING)
		return Vector2(slant / altitude_km, slant / altitude_km / grazing)
	var vertices := PackedVector3Array()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		vertices.append_array(PackedVector3Array([a, b, c, a, c, d]))
	# Trait le long d'un rayon (angle a fixe) de d0 à d1, de largeur width_km vue à la verticale.
	var radial := func(a: float, d0: float, d1: float, width_km: float) -> void:
		var steps := maxi(1, ceili((d1 - d0) / STEP_KM))
		for s in steps:
			var p0 := lerpf(d0, d1, float(s) / steps)
			var p1 := lerpf(d0, d1, float(s + 1) / steps)
			var w0: float = across.call(width_km * 0.5 * (scale.call(p0) as Vector2).x, p0)
			var w1: float = across.call(width_km * 0.5 * (scale.call(p1) as Vector2).x, p1)
			quad.call(ground.call(p0, a - w0), ground.call(p0, a + w0), ground.call(p1, a + w1),
					ground.call(p1, a - w1))
	# Trait en travers (distance d fixe) de l'angle a0 à a1.
	var arc := func(d: float, a0: float, a1: float, width_km: float) -> void:
		var w := width_km * 0.5 * (scale.call(d) as Vector2).y
		var length_km := absf(a1 - a0) * earth_km * sin(d / earth_km)
		var steps := maxi(1, ceili(length_km / STEP_KM))
		for s in steps:
			var b0 := lerpf(a0, a1, float(s) / steps)
			var b1 := lerpf(a0, a1, float(s + 1) / steps)
			quad.call(ground.call(d - w, b0), ground.call(d + w, b0), ground.call(d + w, b1), ground.call(d - w, b1))
	for side in [-1.0, 1.0]:
		radial.call(side * half, START_KM, range_km, LINE_KM)
		var tick_km := TICK_KM
		while tick_km < range_km - TICK_KM * 0.5:
			var major := is_zero_approx(fmod(tick_km, MAJOR_TICK_KM))
			var length := MAJOR_TICK_LENGTH_KM if major else TICK_LENGTH_KM
			arc.call(tick_km, side * half, side * (half - across.call(length, tick_km)), LINE_KM)
			tick_km += TICK_KM
	# Arc de portée, prolongé de la demi-largeur des bords (coins fermés).
	var corner: float = across.call(LINE_KM * 0.5 * (scale.call(range_km) as Vector2).x, range_km)
	arc.call(range_km, -half - corner, half + corner, LINE_KM)
	var axis_km := AXIS_DOT_KM
	while axis_km < range_km - AXIS_DOT_KM * 0.5:
		if is_zero_approx(fmod(axis_km, AXIS_BAR_KM)):
			var bar: float = across.call(AXIS_BAR_LENGTH_KM * 0.5, axis_km)
			arc.call(axis_km, -bar, bar, LINE_KM)
		else:
			var depth := AXIS_DOT_SIZE_KM * 0.5 * (scale.call(axis_km) as Vector2).y
			radial.call(0.0, axis_km - depth, axis_km + depth, AXIS_DOT_SIZE_KM)
		axis_km += AXIS_DOT_KM
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
