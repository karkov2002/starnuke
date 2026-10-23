class_name MissileExhaust
extends Node3D
## Propulsion du missile (scenes/effects/missile_exhaust.tscn), enfant de Point_Tuyere_1_12 dans
## scenes/station_spatiale.tscn (et donc de chaque copie du missile, cf. Station.launch_missile).
##
## Moteur à propergol solide (missile balistique de type mer-sol) dans le vide :
## - cœur : cône additif éblouissant à la sortie de la tuyère, blanc-jaune, qui s'élargit et s'éteint en quelques
##   mètres (shaders/missile_exhaust_core.gdshader) ;
## - panache : sans air pour le confiner, le gaz se détend largement (~40° de demi-angle) ; particules additives, nées
##   petites juste derrière la tuyère,
##   rapides (35 à 70 m/s par rapport au missile) qui grossissent et deviennent transparentes en ~0,35 s
##   (shaders/missile_exhaust_particle.gdshader). Pas de traînée de fumée : rien ne freine ni ne retient le gaz ;
## - lumière : OmniLight3D orange qui vacille, avec ombres (quelques secondes seulement), sur le dessous de la station ;
##   elle n'éclaire pas les surfaces intérieures (calque Station.INTERIOR_LAYER : sans ombre sur elles, elle
##   traverserait la coque).
## Allumage : échelle du parent Point_Tuyere (0 = éteint, 1 = allumé), animée par Lancement_Missile ; l'effet hérite
## de cette échelle (il naît à la taille zéro). Direction du jet : à l'opposé du déplacement du missile (repli : +Y du
## parent, opposé à la pointe du missile), quelle que soit l'orientation du repère dans Blender.
## En vol (enter_flight, appelé par MissileFlight quand le missile quitte l'animation Blender) : la direction du jet est
## imposée (jet_direction, à l'opposé de la pointe), le panache passe en coordonnées locales (il suit le missile et
## rétrécit avec lui quand le rendu le rapproche à l'échelle, cf. scripts/missile_flight.gd) et la lumière est
## atténuée par light_scale (distance réelle).

## Direction du jet (monde) imposée en vol ; nulle : d'après le déplacement.
var jet_direction := Vector3.ZERO
## Facteur de la lumière (0 à 1), réglé en vol selon la distance réelle du missile.
var light_scale := 1.0
## Poussée (0 à 1) : extinction du moteur en vol (MissileFlight), sans toucher à l'échelle de la tuyère (un repère
## d'échelle nulle n'est pas inversible : particules et ombres en souffrent).
var throttle := 1.0

@export var core_length := 2.6
@export var core_nozzle_radius := 0.32
@export var core_end_radius := 0.95
@export var plume_speed := Vector2(35.0, 70.0)
## Demi-angle du cône du panache (degrés) : assez ouvert pour un jet dans le vide, sans que le gaz semble jaillir
## des flancs du missile (65° lui faisait envelopper la coque).
@export var plume_spread_deg := 40.0
@export var plume_lifetime := 0.4
## Nombreuses particules larges et peu opaques : elles se fondent en un voile de gaz continu (pas des étincelles).
@export var plume_amount := 900
@export var light_energy := 6.0
@export var light_range := 40.0
## Vacillement de la lumière et du cœur (part de l'intensité).
@export var flicker := 0.25
## Vitesse minimale (m/s) pour orienter le jet d'après le déplacement.
@export var min_speed_for_direction := 0.5

var _core: MeshInstance3D
var _core_material: ShaderMaterial
var _particles: GPUParticles3D
var _flight_particles: GPUParticles3D
var _particle_material: ShaderMaterial
var _light: OmniLight3D
var _last_position := Vector3.ZERO
var _has_last := false
var _time := 0.0


func _ready() -> void:
	_build_core()
	_build_plume()
	_build_light()


func _process(delta: float) -> void:
	var parent := get_parent() as Node3D
	var level := (parent.scale.x if parent else 1.0) * throttle
	var on := level > 0.02
	_core.visible = on
	_particles.emitting = on and _flight_particles == null
	if _flight_particles:
		_flight_particles.emitting = on
	_light.visible = on and light_scale > 0.01
	if not on:
		_has_last = false
		return
	# Orientation seulement allumé : éteint, le repère du parent est d'échelle nulle (non inversible).
	_orient(delta)
	_time += delta
	# Vacillement : deux sinus incommensurables + bruit, comme la combustion irrégulière d'un bloc de propergol.
	var wobble := 1.0 + flicker * (0.5 * sin(_time * 37.0) + 0.3 * sin(_time * 91.0 + 1.3) + 0.2 * (randf() * 2.0 - 1.0))
	_light.light_energy = light_energy * level * wobble * light_scale
	_core_material.set_shader_parameter("intensity", clampf(wobble, 0.5, 1.5) * minf(throttle, 1.0))
	_particle_material.set_shader_parameter("intensity", clampf(level, 0.0, 1.0))


## Le missile quitte l'animation Blender : panache attaché au missile (coordonnées locales) à la place du panache en
## coordonnées du monde, qui s'éteint de lui-même (durée de vie des particules) : pas de saut visible.
func enter_flight() -> void:
	if _flight_particles:
		return
	_flight_particles = _particles.duplicate() as GPUParticles3D
	_flight_particles.name = "FlightPlume"
	_flight_particles.local_coords = true
	add_child(_flight_particles)


## Jet à l'opposé du déplacement du missile, ou selon jet_direction (dans le repère du parent, pour garder son échelle).
func _orient(delta: float) -> void:
	var position_now := global_position
	var direction := jet_direction
	if direction.is_zero_approx() and _has_last and delta > 0.0:
		var velocity := (position_now - _last_position) / delta
		if velocity.length() > min_speed_for_direction:
			direction = -velocity
	var parent := get_parent() as Node3D
	if not direction.is_zero_approx() and parent and absf(parent.global_basis.determinant()) > 1e-15:
		var local_dir := parent.global_basis.orthonormalized().inverse() * direction.normalized()
		if not local_dir.is_zero_approx():
			quaternion = Quaternion(Vector3.UP, local_dir.normalized())
	_last_position = position_now
	_has_last = true


func _build_core() -> void:
	var mesh := CylinderMesh.new()
	mesh.height = core_length
	mesh.bottom_radius = core_nozzle_radius
	mesh.top_radius = core_end_radius
	mesh.radial_segments = 24
	mesh.rings = 6
	mesh.cap_top = false
	mesh.cap_bottom = false
	_core_material = ShaderMaterial.new()
	_core_material.shader = preload("res://shaders/missile_exhaust_core.gdshader")
	_core_material.set_shader_parameter("length_m", core_length)
	mesh.material = _core_material
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = mesh
	_core.position = Vector3(0.0, core_length * 0.5, 0.0)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)


func _build_plume() -> void:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = plume_spread_deg
	process.initial_velocity_min = plume_speed.x
	process.initial_velocity_max = plume_speed.y
	process.gravity = Vector3.ZERO
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = core_nozzle_radius
	process.scale_min = 1.0
	process.scale_max = 1.6
	# Taille : ~25 cm à la sortie (plus petit que la tuyère : le panache naît d'elle, pas de la coque), puis le gaz se
	# détend en s'éloignant, jusqu'à ~8 m en fin de vie.
	var growth := Curve.new()
	growth.max_value = 8.0
	growth.add_point(Vector2(0.0, 0.2))
	growth.add_point(Vector2(0.15, 1.2))
	growth.add_point(Vector2(1.0, 5.0))
	var growth_texture := CurveTexture.new()
	growth_texture.curve = growth
	process.scale_curve = growth_texture
	# Opacité : la densité du gaz détendu chute en 1/r² : éclatant au ras de la tuyère, vite translucide.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.85, 0.16))
	ramp.set_color(1, Color(0.8, 0.3, 0.1, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.78, 0.45, 0.05))
	ramp.add_point(0.45, Color(0.95, 0.5, 0.2, 0.012))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_particle_material = ShaderMaterial.new()
	_particle_material.shader = preload("res://shaders/missile_exhaust_particle.gdshader")
	quad.material = _particle_material

	_particles = GPUParticles3D.new()
	_particles.name = "Plume"
	_particles.amount = plume_amount
	_particles.lifetime = plume_lifetime
	_particles.local_coords = false
	_particles.process_material = process
	_particles.draw_pass_1 = quad
	_particles.emitting = false
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Le panache s'étend sur ~25 m : boîte de visibilité large, sinon il disparaît dès que l'émetteur sort du champ.
	_particles.visibility_aabb = AABB(Vector3(-20.0, -5.0, -20.0), Vector3(40.0, 40.0, 40.0))
	# Émission juste derrière la sortie de la tuyère (et non sur son plan) : aucune particule ne naît sur la coque.
	_particles.position = Vector3(0.0, core_nozzle_radius, 0.0)
	add_child(_particles)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0.0, 1.0, 0.0)
	_light.light_color = Color(1.0, 0.72, 0.42)
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.omni_attenuation = 1.5
	_light.shadow_enabled = true
	_light.light_cull_mask = 0xFFFFF & ~Station.INTERIOR_LAYER
	_light.visible = false
	add_child(_light)
