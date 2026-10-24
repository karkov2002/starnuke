class_name EquipmentPanel
extends ScreenSeatConsole
## Panneau de maintenance d'un équipement extérieur (créé par StationEquipments, un par équipement) : la dalle de
## l'objet screen_node du modèle (Interactif_Panneau_*) affiche son programme (EquipmentDisplay : état, ON / OFF,
## réparation). Règle de jeu : **utilisable seulement en sortie extravéhiculaire** (Station.observer_outside) ;
## survol, vue assise, souris transmise, clic droit pour quitter : ScreenSeatConsole ; le clavier va aussi à
## l'interface (Entrée, R, F10).

const VIEWPORT_HEIGHT := 480

## Équipement piloté et objet du panneau dans le modèle, fixés avant l'ajout à l'arbre.
var equipment: StationEquipment
var screen_node := ""

var _display: EquipmentDisplay


## Pose face à l'écran, à distance mètres de son centre (panneau de debug : aller à l'équipement) : {eye, look}
## (base globale de la vue, comme StationScreen.seat_pose).
func front_pose(distance: float) -> Dictionary:
	var pose := _screen.seat_pose(_camera, 1.0, 1.0)
	var center := _screen.center_global()
	return {"eye": center + ((pose.eye as Vector3) - center).normalized() * distance, "look": pose.look}


func _screen_node() -> String:
	return screen_node


func _prepare() -> bool:
	return equipment != null


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT)


func _create_display(into: SubViewport) -> void:
	_display = EquipmentDisplay.new()
	_display.name = "Display"
	_display.equipment = equipment
	_display.size = Vector2(into.size)
	_display.quit_requested.connect(stand_up)
	into.add_child(_display)


func _scan_depth() -> float:
	return 0.1


func _can_use() -> bool:
	return _station.observer_outside


func _on_near_changed(near_now: bool) -> void:
	_display.set_process(near_now)


func _hover_key() -> String:
	return "EQUIP_HOVER"


func _exit_key() -> String:
	return "EQUIP_EXIT_HINT"


func _handle_key(key: InputEventKey) -> bool:
	return _display.handle_key(key)
