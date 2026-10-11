class_name ReentryStreak
extends Node3D
## Rentrée atmosphérique d'une tête de missile vue depuis l'orbite (créée par MissileFlight pour la fin du vol) :
## tête incandescente (halo blanc-bleuté, shaders/missile_glow.gdshader) et traînée de plasma qui se refroidit en
## s'éloignant de la tête (shaders/reentry_streak.gdshader). Positions en coordonnées de la scène, à l'échelle de la
## Terre (1 unité = 10 km) : update() à chaque image.

## Demi-largeur réelle de la traînée (m) et largeur minimale à l'écran (pixels) ; tête : rayon réel (m), minimum (px).
var trail_half_width_m := 600.0
var trail_min_pixels := 3.0
var head_radius_m := 1500.0
var head_min_pixels := 6.0
## Luminance (HDR) : bien au-dessus du seuil du halo de l'environnement (glow_hdr_threshold 0,9), pour que la tête
## et la traînée débordent en halo même devant des nuages blancs en plein jour.
var head_brightness := 4.0
var trail_brightness := 1.5

var _trail: MeshInstance3D
var _trail_material: ShaderMaterial
var _head: MeshInstance3D
var _head_material: ShaderMaterial


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.subdivide_width = 32
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = preload("res://shaders/reentry_streak.gdshader")
	_trail_material.set_shader_parameter("seed", randf() * 100.0)
	_trail_material.set_shader_parameter("half_width",
			trail_half_width_m * OrbitSimulation.SCENE_UNITS_PER_KM / 1000.0)
	_trail_material.set_shader_parameter("min_pixels", trail_min_pixels)
	quad.material = _trail_material
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.mesh = quad
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sommets placés par le shader : jamais éliminée par la boîte englobante.
	_trail.custom_aabb = AABB(Vector3.ONE * -5000.0, Vector3.ONE * 10000.0)
	add_child(_trail)

	var head_quad := QuadMesh.new()
	head_quad.size = Vector2(2.0, 2.0)
	_head_material = ShaderMaterial.new()
	_head_material.shader = preload("res://shaders/missile_glow.gdshader")
	_head_material.set_shader_parameter("core_color", Color(0.85, 0.92, 1.0))
	_head_material.set_shader_parameter("halo_color", Color(1.0, 0.6, 0.25))
	head_quad.material = _head_material
	_head = MeshInstance3D.new()
	_head.name = "Head"
	_head.mesh = head_quad
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head.extra_cull_margin = 4.0
	add_child(_head)
	update(Vector3.ZERO, Vector3.ZERO, 0.0)


## head, tail : positions de la tête et du bout de la traînée (scène) ; intensity : éclat (0 à 1).
func update(head: Vector3, tail: Vector3, intensity: float) -> void:
	visible = intensity > 0.002
	if not visible:
		return
	var camera := get_viewport().get_camera_3d()
	var pixel_angle := 0.0007
	if camera:
		pixel_angle = 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / maxf(get_viewport().get_visible_rect().size.y, 1.0)
	_trail_material.set_shader_parameter("head", head)
	_trail_material.set_shader_parameter("tail", tail)
	_trail_material.set_shader_parameter("pixel_angle", pixel_angle)
	# Traînée : intensity (0 à 1) règle l'opacité, trail_brightness la luminance (HDR).
	_trail_material.set_shader_parameter("intensity", intensity * trail_brightness)
	var distance := camera.global_position.distance_to(head) if camera else 40.0
	var radius := maxf(head_radius_m * OrbitSimulation.SCENE_UNITS_PER_KM / 1000.0,
			head_min_pixels * pixel_angle * distance)
	_head.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), head)
	_head_material.set_shader_parameter("intensity", intensity * head_brightness)
