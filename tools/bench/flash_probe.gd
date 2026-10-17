extends Node
## Sonde du flash (scène tools/bench/flash_probe.tscn, fenêtre 1920 × 1080, éditeur fermé) : tire 10 × 50 Mt et, à
## chaque instant de TIMES_S (figés ; le flash d'un 50 Mt dure ~24 s joués), mesure le temps GPU en A/B dans le même
## état, en coupant tour à tour : la lumière du flash dans les nuages (nuke_flash_count du matériau des nuages), au
## sol (matériau de la surface), les deux ; la lumière directionnelle sur la station (FlashFX/FlashLight) ;
## l'éblouissement (Flare) ; la boule de feu (Fireball) ; le champignon ; l'onde de choc. Les nœuds NukeFlash et
## NukeFlashFX réécrivent visibilité et uniforms à chaque image : leur traitement est suspendu pendant la mesure.
## Une capture par instant dans user://bench_shots/flash_<t>s.png. Usage :
##   godot --path . res://tools/bench/flash_probe.tscn

const YIELD_KT := 50000.0
const TIMES_S: Array[float] = [3.0]

var _launcher: NukeLauncher
var _earth: Node3D
var _rid: RID


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(Vector2i.ZERO)
	get_tree().root.scaling_3d_scale = 1.0
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	_launcher = view.get_node("NukeLauncher") as NukeLauncher
	_earth = view.get_node("Earth")
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	# Exposition automatique coupée : sinon elle suit la luminance moyenne (temps réel) et décale toute l'image entre
	# deux variantes, ce qui domine le PSNR.
	var attributes := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
	if attributes:
		attributes.auto_exposure_enabled = false
	await _frames(60)
	orbit.restart(12.0)
	orbit.time_scale = 0.0
	await _frames(10)
	# Témoin sans explosion : l'exposition agit-elle ?
	var attr0 := (view.get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
	var expo0: Node = view.get_node("Exposure")
	expo0.process_mode = Node.PROCESS_MODE_DISABLED
	for mult: float in [0.5, 0.05]:
		attr0.exposure_multiplier = mult
		await _frames(5)
		_shot("temoin_expo_%.3f.png" % mult)
	# Variante : exposition automatique activée, même multiplicateur.
	attr0.auto_exposure_enabled = true
	for mult: float in [0.5, 0.05]:
		attr0.exposure_multiplier = mult
		await _frames(60)
		_shot("temoin_auto_%.3f.png" % mult)
	attr0.auto_exposure_enabled = false
	# Variante : attributs posés sur la caméra.
	var cam0 := get_viewport().get_camera_3d()
	cam0.attributes = attr0
	for mult: float in [0.5, 0.05]:
		attr0.exposure_multiplier = mult
		await _frames(5)
		_shot("temoin_cam_%.3f.png" % mult)
	cam0.attributes = null
	expo0.process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().quit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var aim := _launcher.get_aim()
	for i in 10:
		_launcher.launch_at(aim.latitude + rng.randf_range(-2.0, 2.0), aim.longitude + rng.randf_range(-2.5, 2.5), YIELD_KT)
	await _frames(120)
	var surface := _earth.get_node("Surface").material_override as ShaderMaterial
	var clouds := _earth.get_node("CloudLayer").material_override as ShaderMaterial
	var flash_fx := _launcher.get_node("FlashFX")
	var light := flash_fx.get_node("FlashLight") as DirectionalLight3D
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
	for t in TIMES_S:
		for effect in _launcher.get_effects():
			effect.time_override_s = t
		await _frames(10)
		get_viewport().get_texture().get_image().save_png("user://bench_shots/flash_%ds.png" % int(t))
		print("=== t = %.0f s ===" % t)
		var all := await _gpu()
		# Flash dans les nuages / au sol / les deux : FlashFX suspendu, compte forcé à 0 sur le matériau.
		flash_fx.process_mode = Node.PROCESS_MODE_DISABLED
		clouds.set_shader_parameter("nuke_flash_count", 0)
		var no_clouds := await _gpu()
		_shot("flash_%ds_sans_nuages.png" % int(t))
		flash_fx.process_mode = Node.PROCESS_MODE_INHERIT
		await _frames(2)
		flash_fx.process_mode = Node.PROCESS_MODE_DISABLED
		surface.set_shader_parameter("nuke_flash_count", 0)
		var no_ground := await _gpu()
		_shot("flash_%ds_sans_sol.png" % int(t))
		clouds.set_shader_parameter("nuke_flash_count", 0)
		var no_both := await _gpu()
		_shot("flash_%ds_sans_les_deux.png" % int(t))
		flash_fx.process_mode = Node.PROCESS_MODE_INHERIT
		await _frames(2)
		flash_fx.process_mode = Node.PROCESS_MODE_DISABLED
		light.visible = false
		var no_light := await _gpu()
		_shot("flash_%ds_sans_lumiere.png" % int(t))
		light.visible = true
		var cam_attributes := (_earth.get_parent().get_node("WorldEnvironment") as WorldEnvironment).camera_attributes as CameraAttributesPractical
		var expo_node: Node = _earth.get_parent().get_node("Exposure")
		expo_node.process_mode = Node.PROCESS_MODE_DISABLED
		flash_fx.process_mode = Node.PROCESS_MODE_DISABLED
		for mult: float in [0.5, 0.0005, 0.00005]:
			cam_attributes.exposure_multiplier = mult
			await _frames(5)
			print("multiplicateur forcé %.3f (lu %.3f)" % [mult, cam_attributes.exposure_multiplier])
			_shot("flash_%ds_expo_%.3f.png" % [int(t), mult])
		flash_fx.process_mode = Node.PROCESS_MODE_INHERIT
		expo_node.process_mode = Node.PROCESS_MODE_INHERIT
		flash_fx.process_mode = Node.PROCESS_MODE_INHERIT
		await _frames(2)
		# Élimination sur toute la scène : chaque nœud masqué tour à tour, capture.
		var scene_root: Node = _earth.get_parent()
		for path: String in ["Station", "Earth/CloudLayer", "Earth/Surface", "Earth/AtmosphereSky", "Earth/AtmosphereGround", "Sun", "Hud", "NukeReport", "FpsOverlay"]:
			var node: Node = scene_root.get_node(path)
			node.set(&"visible", false)
			await _frames(5)
			_shot("flash_%ds_cache_%s.png" % [int(t), path.replace("/", "_")])
			node.set(&"visible", true)
		for effect in _launcher.get_effects():
			effect.visible = false
		await _frames(5)
		_shot("flash_%ds_cache_effets.png" % int(t))
		for effect in _launcher.get_effects():
			effect.visible = true
		print("GPU : tout %.2f ms | flash nuages coupé %.2f | flash sol coupé %.2f | les deux %.2f | lumière station coupée %.2f"
				% [all, no_clouds, no_ground, no_both, no_light])
		# Nœuds des explosions.
		var parts := {}
		for part in ["Flash/Flare", "Flash/Fireball", "Flash", "Mushroom", "Shock"]:
			_toggle(part, false)
			parts[part] = await _gpu()
			_shot("flash_%ds_sans_%s.png" % [int(t), part.replace("/", "_")])
			_toggle(part, true)
		print("GPU sans : Flare %.2f | Fireball %.2f | Flash entier %.2f | Mushroom %.2f | Shock %.2f" % [parts["Flash/Flare"],
				parts["Flash/Fireball"], parts["Flash"], parts["Mushroom"], parts["Shock"]])
		# Boucles internes de nuke_flash_volume (nuages) : partage de l'auto-ombrage entre flashs proches (cos minimal,
		# −1 = jamais), pas d'auto-ombrage, pas d'air.
		# FlashFX suspendu (uniforms figés, plus d'adaptation d'exposition en temps réel) : seul l'ombrage change.
		flash_fx.process_mode = Node.PROCESS_MODE_DISABLED
		var inner := {}
		for variant: Array in [[true, 4, 8], [false, 4, 8], [false, 2, 8], [false, 0, 8], [false, 4, 2]]:
			clouds.set_shader_parameter("nuke_flash_shadow_shared", variant[0])
			clouds.set_shader_parameter("nuke_flash_shadow_steps", variant[1])
			clouds.set_shader_parameter("nuke_flash_air_steps", variant[2])
			inner[variant] = await _gpu()
			get_viewport().get_texture().get_image().save_png("user://bench_shots/flash_%ds_%s_s%d_a%d.png" % [int(t),
					"shared" if variant[0] else "each", variant[1], variant[2]])
		clouds.set_shader_parameter("nuke_flash_shadow_shared", true)
		clouds.set_shader_parameter("nuke_flash_shadow_steps", 4)
		clouds.set_shader_parameter("nuke_flash_air_steps", 8)
		flash_fx.process_mode = Node.PROCESS_MODE_INHERIT
		print("GPU nuages (ombrage partagé | par flash : pas d'ombrage, pas d'air) : partagé %.2f | (4, 8) %.2f | (2, 8) %.2f | (0, 8) %.2f | (4, 2) %.2f"
				% [inner[[true, 4, 8]], inner[[false, 4, 8]], inner[[false, 2, 8]], inner[[false, 0, 8]], inner[[false, 4, 2]]])
	while _launcher.get_effects().any(func(e: NukeEffect) -> bool: return e.impact_pending or e.fallout_pending):
		await _frames(10)
	get_tree().quit()


## Masque un nœud de chaque explosion (le nœud Flash ou son parent est suspendu pour qu'il ne le réaffiche pas).
func _toggle(part: String, on: bool) -> void:
	for effect in _launcher.get_effects():
		var node := effect.get_node(part) as Node3D
		node.visible = on
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if part.begins_with("Flash/"):
			effect.get_node("Flash").process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://bench_shots/" + name)


func _gpu() -> float:
	await _frames(20)
	var sum := 0.0
	for i in 60:
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	return sum / 60.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
