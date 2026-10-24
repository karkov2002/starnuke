class_name StationEquipments
extends Node
## Équipements extérieurs réparables de la station (nœud Equipment de scenes/orbit_view.tscn). Chaque entrée de
## EQUIPMENT donne un StationEquipment (état : allumé, en panne) et le panneau de maintenance qui le pilote
## (EquipmentPanel, objet Interactif_Panneau_* du modèle, accessible seulement dehors). Ajouter un équipement : son
## modèle et son panneau dans Blender (tools/blender/build_eva_equipment.py), une ligne ici, puis brancher son effet
## sur ce qu'il alimente (StationEquipments.find(tree, id).is_operational()).
## Effets actuels : caméra -> vue au nadir et photos de la tablette (Tablet) ; antenne -> liaison radio (RadioComms).
## Sauvegardé avec le monde de la campagne (WorldSnapshot : to_save, restore).

const GROUP := &"station_equipments"
const CAMERA := &"camera"
const ANTENNA := &"antenna"
## id -> nom (clé de langue), programme du panneau, objet du panneau dans le modèle.
const EQUIPMENT := {
	CAMERA: {"name": "EQUIP_CAMERA", "program": "CAMERA.EXE", "panel": "Interactif_Panneau_Camera"},
	ANTENNA: {"name": "EQUIP_ANTENNA", "program": "ANTENNA.EXE", "panel": "Interactif_Panneau_Antenne"},
}

## Chemins des nœuds de la vue orbitale, vus depuis ce nœud (transmis aux panneaux).
@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var observer_path: NodePath = ^"../Observer"

var _equipment := {}
var _panels := {}


func _ready() -> void:
	add_to_group(GROUP)
	for id: StringName in EQUIPMENT:
		var info: Dictionary = EQUIPMENT[id]
		var equipment := StationEquipment.new()
		equipment.name = String(id).capitalize()
		equipment.equipment_id = id
		equipment.name_key = info.name
		equipment.program = info.program
		add_child(equipment)
		_equipment[id] = equipment
		var panel := EquipmentPanel.new()
		panel.name = equipment.name + "Panel"
		panel.equipment = equipment
		panel.screen_node = info.panel
		# Les panneaux sont des enfants : chemins rallongés d'un niveau.
		panel.station_path = NodePath("../" + String(station_path))
		panel.observer_path = NodePath("../" + String(observer_path))
		add_child(panel)
		_panels[id] = panel


## Équipement id de la scène (null si absent : menu, bancs d'essai).
static func find(tree: SceneTree, id: StringName) -> StationEquipment:
	var equipments := tree.get_first_node_in_group(GROUP) as StationEquipments if tree else null
	return equipments.get_equipment(id) if equipments else null


func get_equipment(id: StringName) -> StationEquipment:
	return _equipment.get(id)


## Panneau de maintenance de l'équipement id.
func get_panel(id: StringName) -> EquipmentPanel:
	return _panels.get(id)


func all() -> Array:
	return _equipment.values()


## {id: {powered, failed}}.
func to_save() -> Dictionary:
	var saved := {}
	for id: StringName in _equipment:
		saved[String(id)] = (_equipment[id] as StationEquipment).to_save()
	return saved


func restore(saved: Dictionary) -> void:
	for id: StringName in _equipment:
		if saved.has(String(id)):
			(_equipment[id] as StationEquipment).restore(saved[String(id)])
