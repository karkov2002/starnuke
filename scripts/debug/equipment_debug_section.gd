class_name EquipmentDebugSection
extends VBoxContainer
## Section « Pannes » du panneau de debug (scripts/debug/debug_panel.gd), seulement si la scène a des équipements
## extérieurs (StationEquipments) : une ligne par équipement, son état (en service, arrêté, en panne) et les
## boutons « Panne » (StationEquipment.fail : il faut alors sortir le réparer à son panneau), « Réparer » et « Y aller »
## (combinaison enfilée, observateur posé dehors face au panneau de maintenance, à VISIT_DISTANCE_M : comme sorti
## par le sas, AirlockHazard.place_outside).

## Distance (m) entre l'œil et le centre de l'écran du panneau, avec « Y aller ».
const VISIT_DISTANCE_M := 1.4

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
		row.add_child(DebugUi.button("Y aller", _visit.bind(equipments.get_panel(equipment.equipment_id))))
		_states[equipment] = state
		equipment.changed.connect(_show.bind(equipment))
		_show(equipment)


func _show(equipment: StationEquipment) -> void:
	var state := "en panne" if equipment.failed else ("en service" if equipment.powered else "arrêté")
	(_states[equipment] as Label).text = "%s : %s" % [equipment.program, state]


## « Y aller » : face au panneau, dehors, en combinaison (sinon on meurt dans le vide).
func _visit(panel: EquipmentPanel) -> void:
	var station := get_tree().get_first_node_in_group(Station.GROUP) as Station
	var hazard := get_tree().get_first_node_in_group(AirlockHazard.GROUP) as AirlockHazard
	var observer := hazard.get_node_or_null(hazard.observer_path) as Observer if hazard else null
	if panel == null or station == null or observer == null or ScreenSeatConsole.any_seated(get_tree()):
		return
	var camera := observer.get_node(^"Camera") as Camera3D
	station.set_suit_worn(true)
	var pose := panel.front_pose(VISIT_DISTANCE_M)
	observer.global_position += (pose.eye as Vector3) - camera.global_position
	observer.velocity = Vector3.ZERO
	camera.quaternion = (observer.global_basis.inverse() * (pose.look as Basis)).get_rotation_quaternion()
	hazard.place_outside()
