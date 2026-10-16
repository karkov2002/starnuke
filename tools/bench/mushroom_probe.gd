extends Node
## Sonde des champignons (scène tools/bench/mushroom_probe.tscn, fenêtre 1920 × 1080, éditeur fermé) : tire 10 × 50 Mt
## et, à chaque instant de TIMES_S (figés), écrit pour chaque champignon sa boîte englobante en km, sa couverture
## écran et sa densité, puis mesure le temps GPU en A/B dans le même état : saut du vide avec / sans, 5 / 3 / 0 pas de
## lumière, 64 / 48 / 32 pas de marche, boîte cœur vide (coût du rejet), tous les volumes / un seul / aucun / sans
## nœud Mushroom. Une capture par variante dans user://bench_shots/probe_*.png (à comparer par PSNR, cf. README
## « Performances »). Note : NukeMushroom._update réécrit les uniforms et la visibilité à chaque image, d'où les
## suspensions de process_mode. Usage : godot --path . res://tools/bench/mushroom_probe.tscn

const YIELD_KT := 50000.0
const TIMES_S: Array[float] = [60.0, 1800.0, 7200.0, 21600.0]


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
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	await _frames(60)
	orbit.restart(12.0)
	orbit.time_scale = 0.0
	await _frames(10)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var aim := launcher.get_aim()
	for i in 10:
		launcher.launch_at(aim.latitude + rng.randf_range(-2.0, 2.0), aim.longitude + rng.randf_range(-2.5, 2.5), YIELD_KT)
	await _frames(120)
	var camera := get_viewport().get_camera_3d()
	var screen := get_viewport().get_visible_rect().size
	for t in TIMES_S:
		for effect in launcher.get_effects():
			effect.time_override_s = t
		await _frames(10)
		print("=== t = %.0f s ===" % t)
		var effects := launcher.get_effects()
		for i in effects.size():
			var mushroom := effects[i].get_node("Mushroom") as NukeMushroom
			var volume := mushroom.get_node("Volume") as MeshInstance3D
			var m := volume.material_override as ShaderMaterial
			var box_min: Vector3 = m.get_shader_parameter("box_min")
			var box_max: Vector3 = m.get_shader_parameter("box_max")
			var top_km := NukeScaling.cloud_top_km(YIELD_KT)
			var size_km := (box_max - box_min) * top_km
			# Rectangle écran des 8 coins.
			var rect := Rect2()
			var first := true
			var behind := 0
			for cx in [box_min.x, box_max.x]:
				for cy in [box_min.y, box_max.y]:
					for cz in [box_min.z, box_max.z]:
						var world := mushroom.global_transform * Vector3(cx, cy, cz)
						if camera.is_position_behind(world):
							behind += 1
						var p := camera.unproject_position(world)
						if first:
							rect = Rect2(p, Vector2.ZERO)
							first = false
						else:
							rect = rect.expand(p)
			var on_screen := rect.intersection(Rect2(Vector2.ZERO, screen))
			print("#%d visible=%s fade=%.3f breakup=%.2f cap_r=%.2f cap_half=%.3f box km=(%.0f, %.0f, %.0f) écran=%.0f×%.0f px (%.0f %% de l'écran)" % [
					i, mushroom.visible, m.get_shader_parameter("fade"), m.get_shader_parameter("breakup"),
					m.get_shader_parameter("cap_radius"), m.get_shader_parameter("cap_half"), size_km.x, size_km.y, size_km.z,
					on_screen.size.x, on_screen.size.y, 100.0 * on_screen.get_area() / (screen.x * screen.y)])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bench_shots"))
		# A/B du saut du vide dans le même état : temps GPU et capture avec et sans.
		var ab := {}
		for skip in [true, false]:
			for effect in effects:
				((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
						.set_shader_parameter("skip_empty", skip)
			ab[skip] = await _gpu(rid)
			get_viewport().get_texture().get_image().save_png("user://bench_shots/probe_%s_%ds.png" % [
					"skip" if skip else "noskip", int(t)])
		print("Saut du vide : avec %.2f ms, sans %.2f ms" % [ab[true], ab[false]])
		for effect in effects:
			((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
					.set_shader_parameter("skip_empty", true)
		# Part de la marche vers le soleil : 5 (défaut), 3 et 0 pas.
		var light := {}
		for steps in [5, 3, 0]:
			for effect in effects:
				((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
						.set_shader_parameter("light_steps", steps)
			light[steps] = await _gpu(rid)
			get_viewport().get_texture().get_image().save_png("user://bench_shots/probe_light%d_%ds.png" % [steps, int(t)])
		for effect in effects:
			((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
					.set_shader_parameter("light_steps", 5)
		print("Pas de lumière : 5 → %.2f ms, 3 → %.2f ms, 0 → %.2f ms" % [light[5], light[3], light[0]])
		# Nombre de pas de la marche : 64 (défaut), 48, 32.
		var march := {}
		for steps in [64, 48, 32]:
			for effect in effects:
				((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
						.set_shader_parameter("max_steps", steps)
			march[steps] = await _gpu(rid)
			get_viewport().get_texture().get_image().save_png("user://bench_shots/probe_steps%d_%ds.png" % [steps, int(t)])
		for effect in effects:
			((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
					.set_shader_parameter("max_steps", 64)
		print("Pas de marche : 64 → %.2f ms, 48 → %.2f ms, 32 → %.2f ms" % [march[64], march[48], march[32]])
		# Coût du vide : boîte cœur vide → chaque pixel des boîtes englobantes est rejeté après core_interval.
		for effect in effects:
			var mushroom := effect.get_node("Mushroom") as NukeMushroom
			mushroom.process_mode = Node.PROCESS_MODE_DISABLED
			(mushroom.get_node("Volume") as MeshInstance3D).material_override.set_shader_parameter("core_min",
					Vector3(9.0, 9.0, 9.0))
		var empty := await _gpu(rid)
		for effect in effects:
			(effect.get_node("Mushroom") as NukeMushroom).process_mode = Node.PROCESS_MODE_INHERIT
		await _frames(2)
		print("Coût du vide (tout rejeté) : %.2f ms" % empty)
		for effect in effects:
			((effect.get_node("Mushroom") as NukeMushroom).get_node("Volume") as MeshInstance3D).material_override \
					.set_shader_parameter("skip_empty", true)
		# GPU : tous, puis un seul volume (le premier), puis aucun volume, puis sans le nœud Mushroom entier.
		# _update remet Volume.visible à chaque image : le traitement du nœud est suspendu pendant la mesure.
		var all := await _gpu(rid)
		for i in effects.size():
			var mushroom := effects[i].get_node("Mushroom") as NukeMushroom
			mushroom.process_mode = Node.PROCESS_MODE_DISABLED
			mushroom.get_node("Volume").visible = i == 0
		var one := await _gpu(rid)
		for i in effects.size():
			(effects[i].get_node("Mushroom") as NukeMushroom).get_node("Volume").visible = false
		var none := await _gpu(rid)
		for i in effects.size():
			(effects[i].get_node("Mushroom") as NukeMushroom).visible = false
		var hidden := await _gpu(rid)
		for i in effects.size():
			var mushroom := effects[i].get_node("Mushroom") as NukeMushroom
			mushroom.visible = true
			mushroom.get_node("Volume").visible = true
			mushroom.process_mode = Node.PROCESS_MODE_INHERIT
		print("GPU : tous %.2f ms, un seul volume %.2f ms, aucun volume %.2f ms, sans nœud Mushroom %.2f ms"
				% [all, one, none, hidden])
	# Quitter pendant le calcul du bilan (threads) bloque ou plante la sortie : attendre la fin.
	while launcher.get_effects().any(func(e: NukeEffect) -> bool: return e.impact_pending or e.fallout_pending):
		await _frames(10)
	get_tree().quit()


func _gpu(rid: RID) -> float:
	await _frames(20)
	var sum := 0.0
	for i in 60:
		await get_tree().process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return sum / 60.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
