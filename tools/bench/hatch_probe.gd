extends Node
## Coût de l'animation des écoutilles : contenu des charnières, puis temps CPU (process, physique, image) pendant
## l'ouverture des écoutilles, collisions des portes actives puis coupées. Usage :
##   godot --path . res://tools/bench/hatch_probe.tscn

const HATCHES: Array[String] = ["Ecoutille_Habitation_AR", "Ecoutille_Arrimage_AV", "Ecoutille_Missile_1",
		"Ecoutille_Missile_2"]


func _ready() -> void:
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	var station := view.get_node("Station/StationSpatiale") as Station
	await get_tree().create_timer(3.0).timeout
	for id in HATCHES:
		var hinge: Node3D = station._hatches[id].hinge
		var counts := {}
		for node in hinge.find_children("*", "", true, false):
			counts[node.get_class()] = counts.get(node.get_class(), 0) + 1
		print("%s : charnière %s, %s" % [id, hinge.name, counts])
	print("repos : ", await _measure(1.0))
	for id in HATCHES:
		station.set_hatch_open(id, true)
	print("ouverture, collisions actives : ", await _measure(2.0))
	await get_tree().create_timer(1.5).timeout
	for id in HATCHES:
		for body: CollisionObject3D in (station._hatches[id].hinge as Node).find_children("*", "CollisionObject3D", true, false):
			body.process_mode = Node.PROCESS_MODE_DISABLED
	for id in HATCHES:
		station.set_hatch_open(id, false)
	print("fermeture, collisions coupées : ", await _measure(2.0))
	get_tree().quit()


## Moyennes (ms) sur seconds : image, process, physique.
func _measure(seconds: float) -> String:
	var frames := 0
	var process := 0.0
	var physics := 0.0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < seconds * 1e6:
		await get_tree().process_frame
		frames += 1
		process += Performance.get_monitor(Performance.TIME_PROCESS)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var frame_ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
	return "image %.1f ms, process %.1f ms, physique %.1f ms" % [frame_ms, process / frames * 1000.0,
			physics / frames * 1000.0]
