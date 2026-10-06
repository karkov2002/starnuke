class_name NukeFlashFX
extends Node
## Effets globaux des flashs nucléaires, créé par NukeLauncher. À chaque image, il additionne les flashs actifs
## (NukeFlash des NukeEffect) et pilote :
## - les uniforms nuke_flash_* des matériaux de la Terre qui les déclarent (sol et nuages, cf.
##   nuke/shaders/nuke_flash.gdshaderinc) : les NUKE_MAX_FLASHES plus intenses ;
## - une DirectionalLight3D qui n'éclaire que la station (calque STATION_LIGHT_LAYER, ajouté à ses maillages) : à
##   400 km la source est à l'infini pour la station. Énergie = flux reçu × énergie d'un soleil (celle du nœud Sun),
##   ombres portées (montants de la Cupola) ;
## - l'éblouissement : glow (intensité, bloom) de l'Environment et multiplicateur d'exposition de la caméra, relevés
##   selon g = flux / (flux + screen_flux_half), puis rendus à leurs valeurs d'origine quand le flash s'éteint.
##   L'exposition automatique réagit ensuite d'elle-même (l'image s'assombrit puis récupère).

const MAX_FLASHES := 4
const STATION_LIGHT_LAYER := 1 << 19

## Flux reçu (soleils) donnant la moitié de l'effet d'écran.
@export var screen_flux_half := 0.2
@export var glow_gain := 2.0
@export var bloom_gain := 0.5
@export var exposure_gain := 2.5
## Énergie de la lumière pour un flux de 1 soleil (= light_energy du nœud Sun).
@export var station_light_energy_per_sun := 2.0

var _launcher: NukeLauncher
var _environment: Environment
var _camera_attributes: CameraAttributes
var _base_glow := 0.0
var _base_bloom := 0.0
var _base_exposure := 1.0
var _materials: Array[ShaderMaterial] = []
var _light: DirectionalLight3D
var _was_active := false


func setup(launcher: NukeLauncher, world_environment: WorldEnvironment, earth: Node3D, station: Node3D) -> void:
	_launcher = launcher
	if world_environment:
		_environment = world_environment.environment
		_camera_attributes = world_environment.camera_attributes
	if _environment:
		_base_glow = _environment.glow_intensity
		_base_bloom = _environment.glow_bloom
	if _camera_attributes:
		_base_exposure = _camera_attributes.exposure_multiplier
	for child in earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			var material := geometry.material_override as ShaderMaterial
			if material.shader and material.shader.get_shader_uniform_list().any(
					func(u: Dictionary) -> bool: return u.name == "nuke_flash_count"):
				_materials.append(material)
	if station:
		for node in station.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).layers |= STATION_LIGHT_LAYER
	_light = DirectionalLight3D.new()
	_light.name = "FlashLight"
	_light.light_cull_mask = STATION_LIGHT_LAYER
	_light.light_color = Color(1.0, 0.9, 0.78)
	_light.shadow_enabled = true
	_light.directional_shadow_max_distance = 15.0
	_light.visible = false
	add_child(_light)


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var flashes: Array[NukeFlash] = []
	for effect in _launcher.get_effects():
		var flash := effect.get_flash()
		if flash and flash.flux_ref > 0.0:
			flashes.append(flash)
	if flashes.is_empty() and not _was_active:
		return
	_was_active = not flashes.is_empty()
	flashes.sort_custom(func(a: NukeFlash, b: NukeFlash) -> bool: return a.flux_ref > b.flux_ref)

	var positions := PackedVector3Array()
	var fluxes := PackedFloat32Array()
	positions.resize(MAX_FLASHES)
	fluxes.resize(MAX_FLASHES)
	var count := mini(flashes.size(), MAX_FLASHES)
	for i in count:
		var flash := flashes[i]
		var effect := flash.get_parent() as Node3D
		# Repère de l'effet (km) -> repère de la Terre (unités) -> km.
		positions[i] = (effect.transform * flash.transform * flash.get_light_position()) / OrbitSimulation.SCENE_UNITS_PER_KM
		fluxes[i] = flash.flux_ref
	for material in _materials:
		material.set_shader_parameter("nuke_flash_count", count)
		material.set_shader_parameter("nuke_flash_pos_km", positions)
		material.set_shader_parameter("nuke_flash_flux", fluxes)

	var camera := get_viewport().get_camera_3d()
	var received := 0.0
	var brightest := 0.0
	var direction := Vector3.DOWN
	if camera:
		for flash in flashes:
			var f := flash.received_flux(camera.global_position)
			received += f
			if f > brightest:
				brightest = f
				direction = (flash.global_transform * flash.get_light_position() - camera.global_position).normalized()
	_light.visible = received > 1e-4
	if _light.visible:
		var hint := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
		_light.global_basis = Basis.looking_at(-direction, hint)
		_light.light_energy = received * station_light_energy_per_sun

	var g := received / (received + screen_flux_half)
	if _environment:
		_environment.glow_intensity = _base_glow + glow_gain * g
		_environment.glow_bloom = _base_bloom + bloom_gain * g
	if _camera_attributes:
		_camera_attributes.exposure_multiplier = _base_exposure * (1.0 + exposure_gain * g)
