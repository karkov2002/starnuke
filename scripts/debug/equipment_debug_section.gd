class_name EquipmentDebugSection
extends VBoxContainer
## Section « Pannes » du panneau de debug (scripts/debug/debug_panel.gd), seulement si la scène a des équipements
## extérieurs (StationEquipments) : une ligne par équipement, son état (en service, arrêté, en panne) et les
## boutons « Panne » (StationEquipment.fail : il faut alors sortir le réparer à son panneau) et « Réparer ».

var _states := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Pannes"
	add_child(title)
	var equipments := get_tree().get_first_node_in_group(StationEquipments.GROUP) as StationEquipments
	for equipment: StationEquipment in equipments.all():
		var row := DebugUi.row(self)
		var state := Label.new()
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(state)
		row.add_child(DebugUi.button("Panne", equipment.fail))
		row.add_child(DebugUi.button("Réparer", equipment.repair))
		_states[equipment] = state
		equipment.changed.connect(_show.bind(equipment))
		_show(equipment)


func _show(equipment: StationEquipment) -> void:
	var state := "en panne" if equipment.failed else ("en service" if equipment.powered else "arrêté")
	(_states[equipment] as Label).text = "%s : %s" % [equipment.program, state]
