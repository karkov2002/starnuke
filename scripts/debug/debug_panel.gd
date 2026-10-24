class_name DebugPanel
extends CanvasLayer
## Panneau de debug du jeu (outil de développement, textes en français), en haut à gauche : en jeu, F4 l'ouvre ou le
## masque (scripts/ui/fps_overlay.gd) ; dans l'éditeur, la scène scenes/debug_scene.tscn (F6) le pose sur la vue
## orbitale. Sections, chacune un nœud : explosions (NukeDebugSection, nuke/debug/), station et radio
## (StationDebugSection), pannes des équipements extérieurs (EquipmentDebugSection, si la scène en a), orbite et
## temps (OrbitDebugSection, seulement si une orbite est en place : pas au décor du menu).


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 24.0)
	panel.add_theme_stylebox_override("panel", DebugUi.panel_style())
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 360.0
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Debug"
	box.add_child(title)
	box.add_child(NukeDebugSection.new())
	box.add_child(HSeparator.new())
	box.add_child(StationDebugSection.new())
	if get_tree().get_first_node_in_group(StationEquipments.GROUP):
		box.add_child(HSeparator.new())
		box.add_child(EquipmentDebugSection.new())
	if get_tree().get_first_node_in_group(OrbitSimulation.GROUP):
		box.add_child(HSeparator.new())
		box.add_child(OrbitDebugSection.new())
