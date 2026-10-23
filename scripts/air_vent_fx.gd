class_name AirVentFx
extends Node3D
## Fuite d'air par la porte extérieure du sas (nœud AirVentFx de scenes/orbit_view.tscn) : tant que la porte est
## ouverte et qu'il reste de l'air dans le sas (et dans ce qui communique avec lui, StationAtmosphere), l'air jaillit
## vers l'espace. L'air qui se détend dans le vide se refroidit brutalement : son humidité se condense en cristaux de
## glace, d'où un brouillard blanc, visible là où il est éclairé (lampes du sas, soleil dehors ; la nuit, à peine).
## - Dans le sas : brouillard aspiré vers la porte (accéléré vers elle, resserré sur son centre), éclairé par les
##   lampes intérieures (calque Station.INTERIOR_LAYER).
## - Dehors : panache qui jaillit de la porte comme d'un pot d'échappement (jet étroit et rapide qui s'élargit en
##   cône et se dissipe en quelques mètres), éclairé par le soleil.
## - Son : souffle (bruit généré au démarrage : sifflement et grondement, en boucle), à la porte, côté intérieur, sur
##   le bus SFX ; il ne porte que dans l'air : nul pour un auditeur dans le vide (pression de son volume).
## Intensité : pression du sas, porte extérieure ouverte (bouffée violente à l'ouverture, puis le jet faiblit à mesure
## que l'air s'épuise ; bien plus long si toute la station communique avec le sas). Rien n'est émis porte fermée.
## Le nœud se place lui-même à la porte, +Y vers l'espace.

@export var atmosphere_path: NodePath = ^"../StationAir"
## Intensité en dessous de laquelle plus rien n'est émis.
@export var min_level := 0.02
## Panache extérieur : vitesse (m/s), demi-angle du cône (degrés), durée de vie (s), nombre de particules.
@export var plume_speed := Vector2(16.0, 34.0)
@export var plume_spread_deg := 16.0
@export var plume_lifetime := 0.7
@export var plume_amount := 700
## Brouillard intérieur : durée de vie (s), nombre de particules, accélération vers la porte (m/s²).
@export var mist_lifetime := 1.1
@export var mist_amount := 450
@export var mist_accel := 9.0
## Son : volume à pleine intensité (dB), hauteur (à vide, à plein).
@export var sound_db := -4.0
@export var sound_pitch := Vector2(0.75, 1.15)

const HATCH := "Ecoutille_Sas_Bas"
const SOUND_RATE := 32000
const SOUND_S := 3.0
const SOUND_FADE_S := 0.25

var _atmosphere: StationAtmosphere
var _station: Station
var _plume: GPUParticles3D
var _mist: GPUParticles3D
var _sound: AudioStreamPlayer3D
var _placed := false
## Jets allumés à la dernière image (porte fermée et jets éteints : rien à refaire).
var _was_on := false


func _ready() -> void:
	_atmosphere = get_node_or_null(atmosphere_path) as StationAtmosphere
	_plume = _build_plume()
	_mist = _build_mist()
	_sound = _build_sound()


func _process(_delta: float) -> void:
	if _atmosphere == null:
		return
	if not _placed and not _place():
		return
	var level := 0.0
	if _station.is_hatch_opening(_station.airlock_outer_hatch):
		level = _atmosphere.pressure_of(StationAtmosphere.SAS)
	var on := level > min_level
	# Porte fermée et jets déjà éteints (le cas courant) : rien à faire.
	if not on and not _was_on:
		return
	_was_on = on
	for particles: GPUParticles3D in [_plume, _mist]:
		particles.emitting = on
		if on:
			particles.amount_ratio = clampf(level * 1.3, 0.15, 1.0)
			particles.speed_scale = lerpf(0.45, 1.0, level)
	_update_sound(level if on else 0.0)


## Place le nœud à la porte extérieure, +Y vers l'espace (une fois la station prête).
func _place() -> bool:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return false
	var out := _atmosphere.hatch_axis_from(HATCH, StationAtmosphere.SAS)
	var side := out.cross(Vector3.FORWARD if absf(out.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	global_transform = Transform3D(Basis(side, out, side.cross(out)).orthonormalized(), _atmosphere.hatch_center(HATCH))
	(_mist.process_material as ParticleProcessMaterial).gravity = out * mist_accel * 0.7
	_placed = true
	return true


## Souffle : audible là où il y a de l'air (pression du volume de l'auditeur), plus fort et plus aigu à forte pression.
func _update_sound(level: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var hearing := 0.0
	if camera:
		hearing = _atmosphere.pressure_of(_atmosphere.zone_at(camera.global_position))
	var loudness := level * sqrt(hearing)
	if loudness < 0.003:
		if _sound.playing:
			_sound.stop()
		return
	_sound.volume_db = sound_db + linear_to_db(loudness)
	_sound.pitch_scale = lerpf(sound_pitch.x, sound_pitch.y, level)
	if not _sound.playing:
		_sound.play(randf() * SOUND_S * 0.8)


func _build_plume() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = plume_spread_deg
	process.initial_velocity_min = plume_speed.x
	process.initial_velocity_max = plume_speed.y
	process.gravity = Vector3.ZERO
	# Sortie : le passage de la porte (Ø 1 m), au ras de son plan.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 0.42
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 0.1
	process.emission_shape_offset = Vector3(0.0, 0.15, 0.0)
	process.scale_min = 0.8
	process.scale_max = 1.3
	# Taille : ~35 cm à la sortie, le gaz se détend jusqu'à ~4 m en fin de vie.
	process.scale_curve = _curve_texture([Vector2(0.0, 0.35), Vector2(0.2, 1.2), Vector2(1.0, 4.0)], 4.0)
	# Densité : forte à la sortie, puis chute vite (détente).
	process.color_ramp = _gradient_texture({0.0: Color(0.95, 0.97, 1.0, 0.45), 0.25: Color(0.92, 0.95, 1.0, 0.18),
			0.6: Color(0.9, 0.93, 1.0, 0.05), 1.0: Color(0.9, 0.93, 1.0, 0.0)})
	var particles := _make_particles("Panache", process, plume_amount, plume_lifetime)
	particles.visibility_aabb = AABB(Vector3(-12.0, -2.0, -12.0), Vector3(24.0, 30.0, 24.0))
	return particles


func _build_mist() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	# Repère du nœud : la porte à l'origine, l'intérieur du sas vers −Y.
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	process.emission_ring_axis = Vector3.UP
	process.emission_ring_radius = 1.0
	process.emission_ring_inner_radius = 0.0
	process.emission_ring_height = 2.4
	process.emission_shape_offset = Vector3(0.0, -1.5, 0.0)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 2.0
	# Aspiré vers la porte : accélération radiale vers l'origine (le centre du passage), et poussée vers l'espace
	# (gravité, en repère global : réglée au placement, _place) qui lui fait franchir la porte.
	process.radial_accel_min = -mist_accel
	process.radial_accel_max = -mist_accel * 0.6
	process.gravity = Vector3.ZERO
	process.scale_min = 0.8
	process.scale_max = 1.4
	process.scale_curve = _curve_texture([Vector2(0.0, 0.5), Vector2(0.5, 1.0), Vector2(1.0, 1.6)], 2.0)
	process.color_ramp = _gradient_texture({0.0: Color(0.95, 0.97, 1.0, 0.0), 0.2: Color(0.95, 0.97, 1.0, 0.13),
			0.75: Color(0.95, 0.97, 1.0, 0.08), 1.0: Color(0.95, 0.97, 1.0, 0.0)})
	var particles := _make_particles("Brouillard", process, mist_amount, mist_lifetime)
	particles.layers |= Station.INTERIOR_LAYER
	particles.visibility_aabb = AABB(Vector3(-2.0, -4.5, -2.0), Vector3(4.0, 7.0, 4.0))
	return particles


func _make_particles(part_name: String, process: ParticleProcessMaterial, amount: int,
		lifetime: float) -> GPUParticles3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _puff_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var particles := GPUParticles3D.new()
	particles.name = part_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


## Bouffée : disque flou (blanc, opacité en cloche).
static func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	return texture


static func _curve_texture(points: Array, max_value: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = max_value
	for point: Vector2 in points:
		curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _gradient_texture(stops: Dictionary) -> GradientTexture1D:
	var gradient := Gradient.new()
	var offsets := stops.keys()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(offsets.map(func(o: float) -> Color: return stops[o]))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Souffle en boucle, généré une fois : sifflement (bruit blanc passé en passe-haut) et grondement (bruit brun), fin
## raccordée au début par un fondu (pas de clic à la boucle).
func _build_sound() -> AudioStreamPlayer3D:
	var count := int(SOUND_RATE * SOUND_S)
	var fade := int(SOUND_RATE * SOUND_FADE_S)
	var samples := PackedFloat32Array()
	samples.resize(count + fade)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var previous := 0.0
	var brown := 0.0
	for i in count + fade:
		var white := rng.randf() * 2.0 - 1.0
		var hiss := white - previous   # passe-haut
		previous = white
		brown = clampf(brown * 0.995 + white * 0.04, -1.0, 1.0)
		samples[i] = 0.32 * hiss + 0.9 * brown
	for i in fade:
		var t := float(i) / fade
		samples[i] = samples[i] * t + samples[count + i] * (1.0 - t)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SOUND_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	var player := AudioStreamPlayer3D.new()
	player.name = "Souffle"
	player.stream = stream
	player.bus = &"SFX"
	# Côté intérieur de la porte : on l'entend dans le sas et, plus faible, dans les modules qui communiquent.
	player.position = Vector3(0.0, -0.8, 0.0)
	player.unit_size = 4.0
	player.max_distance = 40.0
	add_child(player)
	return player
