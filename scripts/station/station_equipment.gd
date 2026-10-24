class_name StationEquipment
extends Node
## Équipement extérieur de la station (caméra de photographie, antenne radio…), créé et déclaré par
## StationEquipments. Règle de jeu commune : un équipement ne fonctionne que s'il est **allumé** (bouton ON / OFF de
## son panneau de maintenance, accessible seulement en sortie extravéhiculaire) et **pas en panne** ; une panne
## (événement : debug, campagne ; niveau 1 à 3, repair_level) ne se répare que sur place, au panneau, en gagnant le
## mini-jeu de réparation (RepairFrogger, à ce niveau). Échec ou abandon : nouvel essai seulement après
## RETRY_COOLDOWN_S (retry_in_s, temps réel). Les consommateurs (tablette, radio, console radar) interrogent
## is_operational() ou suivent changed.

signal changed

## Délai (s) avant de pouvoir relancer la réparation après un échec ou un abandon.
const RETRY_COOLDOWN_S := 30.0

## Identifiant (clé de sauvegarde, StationEquipments.find).
var equipment_id := &""
## Clé de langue du nom de l'équipement, et nom du programme de son panneau (affiché tel quel, style MS-DOS).
var name_key := ""
var program := ""
## Allumé (bouton du panneau) ; en panne.
var powered := true
var failed := false
## Difficulté de la réparation de la panne en cours (1 à 3).
var repair_level := 1
## Temps (s) avant de pouvoir relancer la réparation (0 : possible).
var retry_in_s := 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	retry_in_s = maxf(retry_in_s - delta, 0.0)
	if retry_in_s <= 0.0:
		set_process(false)
		changed.emit()


func is_operational() -> bool:
	return powered and not failed


func set_powered(on: bool) -> void:
	if on != powered:
		powered = on
		changed.emit()


## Panne de niveau level (difficulté de la réparation, 1 à 3) : l'équipement cesse de fonctionner jusqu'à repair().
func fail(level := 1) -> void:
	if not failed:
		failed = true
		repair_level = clampi(level, 1, RepairFrogger.LEVELS.size())
		retry_in_s = 0.0
		changed.emit()


## Réparation ratée ou abandonnée : nouvel essai dans RETRY_COOLDOWN_S.
func start_cooldown() -> void:
	retry_in_s = RETRY_COOLDOWN_S
	set_process(true)
	changed.emit()


func repair() -> void:
	if failed:
		failed = false
		retry_in_s = 0.0
		changed.emit()


func to_save() -> Dictionary:
	return {"powered": powered, "failed": failed, "level": repair_level}


func restore(saved: Dictionary) -> void:
	powered = bool(saved.get("powered", true))
	failed = bool(saved.get("failed", false))
	repair_level = int(saved.get("level", 1))
	changed.emit()
