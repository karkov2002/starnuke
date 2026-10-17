extends GPUParticles3D
## Poussière en suspension dans l'habitacle (nœud Dust, enfant de l'observateur dans orbit_view.tscn) : amount grains
## de 3 à 8 mm dans un cube de 2 × box_m de côté autour de l'observateur, qui dérivent lentement en apesanteur
## (vitesse aléatoire, sans gravité) et vivent lifetime s. Les grains sont dans le repère de la scène (la station y est
## fixe) : l'observateur se déplace parmi eux. Billboards éclairés par les lumières (diffus), sans ombre portée : à
## peine visibles sous l'éclairage normal, ils scintillent dans le faisceau de la lampe torche.

## Demi-côté du volume d'émission (m), centré sur l'observateur.
@export var box_m := 1.8
@export var dust_color := Color(0.9, 0.87, 0.8, 0.45)
@export var grain_min_m := 0.003
@export var grain_max_m := 0.008
@export var speed_min_m_s := 0.01
@export var speed_max_m_s := 0.05


func _ready() -> void:
	local_coords = false
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	visibility_aabb = AABB(Vector3.ONE * -2.0 * box_m, Vector3.ONE * 4.0 * box_m)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3.ONE * box_m
	process.direction = Vector3.UP
	process.spread = 180.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = speed_min_m_s
	process.initial_velocity_max = speed_max_m_s
	process.scale_min = grain_min_m
	process.scale_max = grain_max_m
	process.color = dust_color
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.1, 0.9, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	process_material = process
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Un grain trop près de l'objectif (grossi, saturé) s'estompe : fondu inversé entre 0,5 et 0,15 m.
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = 0.5
	material.distance_fade_max_distance = 0.15
	# Disque doux : dégradé radial.
	var disc := GradientTexture2D.new()
	disc.fill = GradientTexture2D.FILL_RADIAL
	disc.fill_from = Vector2(0.5, 0.5)
	disc.fill_to = Vector2(0.5, 1.0)
	disc.width = 32
	disc.height = 32
	var alpha := Gradient.new()
	alpha.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	alpha.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	disc.gradient = alpha
	material.albedo_texture = disc
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	draw_pass_1 = quad
	emitting = true
