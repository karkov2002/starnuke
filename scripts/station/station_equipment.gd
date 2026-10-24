class_name StationEquipment
extends Node
## Équipement extérieur de la station (caméra de photographie, antenne radio…), créé et déclaré par
## StationEquipments. Règle de jeu commune : un équipement ne fonctionne que s'il est **allumé** (bouton ON / OFF de
## son panneau de maintenance, accessible seulement en sortie extravéhiculaire) et **pas en panne** ; une panne
## (événement : debug, campagne) ne se répare que sur place, au panneau (pour l'instant d'un clic ; plus tard des
## mini-jeux). Les consommateurs (tablette, radio) interrogent is_operational() ou suivent changed.

signal changed

## Identifiant (clé de sauvegarde, StationEquipments.find).
var equipment_id := &""
## Clé de langue du nom de l'équipement, et nom du programme de son panneau (affiché tel quel, style MS-DOS).
var name_key := ""
var program := ""
## Allumé (bouton du panneau) ; en panne.
var powered := true
var failed := false


func is_operational() -> bool:
	return powered and not failed


func set_powered(on: bool) -> void:
	if on != powered:
		powered = on
		changed.emit()


## Panne : l'équipement cesse de fonctionner jusqu'à repair().
func fail() -> void:
	if not failed:
		failed = true
		changed.emit()


func repair() -> void:
	if failed:
		failed = false
		changed.emit()


func to_save() -> Dictionary:
	return {"powered": powered, "failed": failed}


func restore(saved: Dictionary) -> void:
	powered = bool(saved.get("powered", true))
	failed = bool(saved.get("failed", false))
	changed.emit()
