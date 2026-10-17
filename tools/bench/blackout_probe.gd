extends Node
## Vérifie l'extinction « plus de lumière » : après 3 s en Alert.BLACKOUT, liste les matériaux émissifs encore
## allumés (émission > 0,01 ou albédo clair). Usage : godot --path . res://tools/bench/blackout_probe.tscn

func _ready() -> void:
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var station := view.get_node("Station/StationSpatiale") as Station
	await get_tree().create_timer(2.0).timeout
	station.set_alert(Station.Alert.BLACKOUT)
	await get_tree().create_timer(3.0).timeout
	var seen := {}
	for mesh_instance: MeshInstance3D in station.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var m := mesh_instance.get_active_material(s) as BaseMaterial3D
			if m == null or not m.emission_enabled or seen.has(m):
				continue
			seen[m] = true
			var lit := m.emission_energy_multiplier > 0.01 or m.albedo_color.get_luminance() > 0.1
			print("%s « %s » (%s) : émission × %.2f, albédo lum %.2f, override %s" % ["ALLUMÉ" if lit else "éteint",
					m.resource_name, mesh_instance.name, m.emission_energy_multiplier, m.albedo_color.get_luminance(),
					mesh_instance.get_surface_override_material(s) != null])
	get_tree().quit()
