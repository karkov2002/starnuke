extends Node
## Inventaire des matériaux émissifs de la station (console) : nom du maillage, surface, matériau, émission.
## Usage : godot --path . --headless res://tools/bench/material_probe.tscn

func _ready() -> void:
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	var station: Node = view.get_node("Station/StationSpatiale")
	var seen := {}
	for mesh_instance: MeshInstance3D in station.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(s)
			if material is BaseMaterial3D and (material as BaseMaterial3D).emission_enabled:
				var m := material as BaseMaterial3D
				var key := "%s|%s" % [m.resource_name, m.emission_energy_multiplier]
				if seen.has(key):
					seen[key] += 1
					continue
				seen[key] = 1
				print("émissif : %s / surface %d / matériau « %s » : émission %s × %.2f, albédo %s" % [mesh_instance.name,
						s, m.resource_name, m.emission, m.emission_energy_multiplier, m.albedo_color])
	for key in seen:
		print("  %s : %d maillage(s)" % [key, seen[key]])
	get_tree().quit()
