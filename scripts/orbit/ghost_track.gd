class_name GhostTrack
extends MeshInstance3D
## Anneau 3D en pointillés de l'orbite fantôme (FlightComputer.get_ghost) autour de la Terre : visible tant qu'une
## manœuvre est prévue. Le maillage (ImmediateMesh, lignes) est construit dans le repère inertiel ECI pour Ω = 0, à
## l'échelle de la scène, et reconstruit quand le rayon ou l'inclinaison changent ; à chaque image, après Orbit
## (process_priority), il est placé au centre de la Terre, tourné de Ω (qui dérive lentement : précession J2) puis
## du repère ECI vers la scène : l'anneau reste fixe dans l'espace pendant que la Terre tourne dessous, et sa trace
## au sol reste cohérente.

const SEGMENTS := 720
## Pointillés : DASH_ON segments tracés, puis DASH_OFF segments vides (1 segment = 0,5° d'orbite, ~60 km).
const DASH_ON := 2
const DASH_OFF := 2

@export var flight_computer_path: NodePath = ^"../FlightComputer"
@export var earth_path: NodePath = ^"../Earth"
@export var color := Color(0.3, 0.85, 1.0)
## Luminosité (rendu non éclairé, au-delà de 1 en HDR pour rester visible sur la Terre éclairée ; à 3, l'exposition
## automatique de nuit, qui remonte l'image, faisait baver les tirets en halos).
@export var energy := 1.5

var _computer: FlightComputer
var _earth: Node3D
var _immediate := ImmediateMesh.new()
## Éléments de l'anneau dessiné (rayon, inclinaison) : reconstruit seulement s'ils changent.
var _built := Vector2(-1.0, -1.0)
var _hud: Hud


func _ready() -> void:
	_computer = get_node(flight_computer_path) as FlightComputer
	_earth = get_node(earth_path) as Node3D
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = Hud.OVERLAY_LAYER
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy)
	material_override = material
	# Après Orbit, qui place la Terre à chaque image.
	process_priority = 10
	visible = false


func _process(_delta: float) -> void:
	# Surimpression : masquée si le HUD de la tablette est sur Off (Hud cherché à la volée : il peut être prêt après).
	if _hud == null:
		_hud = get_tree().get_first_node_in_group(Hud.GROUP) as Hud
	visible = _computer.has_plan() and (_hud == null or _hud.overlay_enabled)
	if not visible:
		return
	var ghost := _computer.get_ghost()
	var key := Vector2(ghost.radius_km, ghost.inclination)
	if not key.is_equal_approx(_built):
		_build(ghost)
		_built = key
	var orbit := _computer.get_orbit()
	var raan := FlightComputer.ghost_raan(ghost, orbit.sim_time_s)
	global_transform = Transform3D(orbit.get_eci_to_world() * Basis(Vector3.BACK, raan), _earth.global_position)


func _build(ghost: Dictionary) -> void:
	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	var radius: float = ghost.radius_km * OrbitSimulation.SCENE_UNITS_PER_KM
	for k in SEGMENTS:
		if k % (DASH_ON + DASH_OFF) >= DASH_ON:
			continue
		for arg_lat in [TAU * k / SEGMENTS, TAU * (k + 1) / SEGMENTS]:
			_immediate.surface_add_vertex(OrbitSimulation.circular_position_eci(radius, ghost.inclination, 0.0, arg_lat))
	_immediate.surface_end()
	# Anneau de ~1 400 unités : boîte englobante large pour ne pas être écarté par le frustum.
	custom_aabb = AABB(Vector3.ONE * -radius, Vector3.ONE * 2.0 * radius)
