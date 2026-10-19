class_name StationAtmosphere
extends Node
## Air de la station (nœud StationAir de scenes/orbit_view.tscn) : pression (relative, 0–1) de chaque volume (modules,
## jonctions, sas). Deux volumes **communiquent** quand l'écoutille qui les relie est ouverte (état visé : une écoutille
## qui commence à s'ouvrir communique déjà, une écoutille qui commence à se fermer isole déjà). Règles de jeu :
## - des volumes qui communiquent s'équilibrent (moyenne pondérée par les volumes d'air, constante equalize_s) ;
## - la valve du sas vide **tout l'ensemble qui communique avec le sas**, en suivant la courbe de son manomètre (20 s
##   pour le sas seul), ou le remplit à débit constant (valve_fill_s, 8 s pour le sas seul ; réserve d'oxygène
##   illimitée, porte extérieure fermée : sinon, l'air repart dans l'espace) ; toute la station : station_valve_s
##   (35 s) dans les deux sens (_valve_duration) ;
## - porte extérieure ouverte : tout l'ensemble qui communique avec l'espace se vide (door_vent_s pour le sas seul) et
##   un courant d'air y porte vers la sortie (flow_at), d'autant plus fort que la pression et le nombre de modules
##   reliés sont grands : de flow_speed_sas (sas seul, plein) à flow_speed_max (tous les modules reliés).
## Porte extérieure : durée × racine du volume d'air rapporté à celui du sas (toute la station : ~8 fois plus long).
## - **alerte rouge** automatique dès que les deux portes du sas sont ouvertes en même temps, levée quand la porte
##   extérieure est fermée et que la pression est revenue à 80 % dans le sas et ce qui communique avec lui
##   (_update_alert) ;
## Volumes et écoutilles : tables ZONES et HATCHES (coordonnées Blender du modèle, converties dans le repère de la
## station : x, z, −y). La valve et son manomètre : Station (get_airlock_valve_mode, airlock_step, set_airlock_gauge).

const SPACE := "Espace"
const SAS := "Sas"
## Volumes : boîtes [xmin, xmax, ymin, ymax, zmin, zmax] (coordonnées Blender), volume d'air (m³), modules comptés
## (jonctions et sas : 0). Boîte secondaire (recoin : cupola) : point de passage vers le reste du volume, que le courant
## vise d'abord (7e élément). Ordre de recherche : le sas avant l'Arrimage, dont il perce le plancher.
const ZONES := {
	"Sas": [[[-11.3, -8.9, -1.3, 1.3, -6.0, -1.25]], 18.0, 0],
	"Arrimage": [[[-16.2, -7.0, -1.45, 1.45, -1.45, 1.45]], 45.0, 1],
	"Jonction_AR": [[[-7.0, -4.6, -2.1, 2.1, -2.1, 2.1]], 10.0, 0],
	"Habitation": [[[-4.6, 4.6, -1.45, 1.45, -1.45, 1.45], [-1.6, 1.6, -2.5, 2.5, -1.6, 1.6]], 48.0, 1],
	"Missile_1": [[[-3.9, 3.9, 2.5, 23.0, -3.9, 3.9]], 500.0, 1],
	"Missile_2": [[[-3.9, 3.9, -23.0, -2.5, -3.9, 3.9]], 500.0, 1],
	"Jonction_AV": [[[4.6, 7.0, -2.1, 2.1, -2.1, 2.1]], 10.0, 0],
	"Commande": [[[7.0, 16.2, -1.45, 1.45, -1.45, 1.45], [10.0, 13.2, -1.6, 1.6, -4.9, -1.4, Vector3(11.6, 0.0, -0.4)]], 55.0, 1],
}
## Écoutilles : volumes reliés (SPACE : l'espace), centre du passage et axe (coordonnées Blender).
const HATCHES := {
	"Ecoutille_Sas_Bas": ["Sas", SPACE, Vector3(-10.1, 0.0, -5.9), Vector3(0, 0, 1)],
	"Ecoutille_Sas_Haut": ["Arrimage", "Sas", Vector3(-10.1, 0.0, -1.25), Vector3(0, 0, 1)],
	"Ecoutille_Arrimage_AV": ["Arrimage", "Jonction_AR", Vector3(-7.0, 0.0, 0.0), Vector3(1, 0, 0)],
	"Ecoutille_Habitation_AR": ["Jonction_AR", "Habitation", Vector3(-4.6, 0.0, 0.0), Vector3(1, 0, 0)],
	"Ecoutille_Missile_1": ["Habitation", "Missile_1", Vector3(0.0, 2.5, 0.0), Vector3(0, 1, 0)],
	"Ecoutille_Missile_2": ["Habitation", "Missile_2", Vector3(0.0, -2.5, 0.0), Vector3(0, 1, 0)],
	"Ecoutille_Habitation_AV": ["Habitation", "Jonction_AV", Vector3(4.6, 0.0, 0.0), Vector3(1, 0, 0)],
	"Ecoutille_Commande_AR": ["Jonction_AV", "Commande", Vector3(7.0, 0.0, 0.0), Vector3(1, 0, 0)],
}
## Le courant vise un point au-delà du passage (m), pour le franchir sans s'arrêter au cadre.
const BEYOND_M := 0.8

@export var station_path: NodePath = ^"../Station/StationSpatiale"
## Équilibrage entre volumes qui communiquent (s).
@export var equalize_s := 0.5
## Remplissage du sas seul par la valve, de vide à plein (s) : débit constant, réserve d'oxygène illimitée.
@export var valve_fill_s := 8.0
## Toute la station ouverte : durée d'une vidange ou d'un remplissage complet par la valve (s).
@export var station_valve_s := 35.0
## Vidange d'un sas plein par la porte extérieure (s).
@export var door_vent_s := 1.5
## Courant d'air vers la sortie (m/s, × pression) : sas seul, et tous les modules reliés.
@export var flow_speed_sas := 3.0
@export var flow_speed_max := 12.0
## Alerte de dépressurisation levée quand la porte extérieure est fermée et que le sas et ce qui communique avec lui
## sont revenus à cette pression.
@export var alert_clear_pressure := 0.8

## Pression de chaque volume (1 : pleine).
var pressures := {}
var _station: Station
## Volume → écoutille suivante vers l'espace (volumes qui communiquent avec l'espace), et vitesse du courant (m/s).
var _next := {}
var _flow_speed := {}
var _modules_total := 0
var _volume_total := 0.0
## Alerte rouge de dépressurisation en cours, et niveau d'alerte d'avant (rétabli à la levée).
var _alert_raised := false
var _alert_before := Station.Alert.NONE


func _ready() -> void:
	for zone: String in ZONES:
		pressures[zone] = 1.0
		_modules_total += int(ZONES[zone][2])
		_volume_total += float(ZONES[zone][1])
	_station = get_node_or_null(station_path) as Station
	if _station == null:
		set_process(false)


func _process(delta: float) -> void:
	var groups := _groups()
	var valve := _station.get_airlock_valve_mode()
	_next.clear()
	_flow_speed.clear()
	for zones: Array in groups:
		var volume := 0.0
		var mean := 0.0
		var modules := 0
		for zone: String in zones:
			if zone != SPACE:
				volume += float(ZONES[zone][1])
				mean += float(pressures[zone]) * float(ZONES[zone][1])
				modules += int(ZONES[zone][2])
		if volume <= 0.0:
			continue
		mean /= volume
		var scale := sqrt(volume / float(ZONES[SAS][1]))
		var target := mean
		if zones.has(SPACE):
			target = _station.airlock_step(mean, delta * _station.get_airlock_valve_s() / door_vent_s / scale)
		elif zones.has(SAS) and valve < 0:
			var valve_s := _station.get_airlock_valve_s()
			target = _station.airlock_step(mean, delta * valve_s / _valve_duration(volume, valve_s))
		elif zones.has(SAS) and valve > 0:
			target = minf(mean + delta / _valve_duration(volume, valve_fill_s), 1.0)
		var w := 1.0 - exp(-delta / equalize_s)
		for zone: String in zones:
			if zone != SPACE:
				pressures[zone] = clampf(lerpf(float(pressures[zone]) + target - mean, target, w), 0.0, 1.0)
		if zones.has(SPACE):
			var speed := target * lerpf(flow_speed_sas, flow_speed_max, float(modules) / maxf(_modules_total, 1))
			_route(zones, speed)
	_station.set_airlock_gauge(float(pressures[SAS]))
	_update_alert()


## Alerte rouge automatique (règle de jeu) : dès que les deux portes du sas sont ouvertes en même temps (état visé :
## dès le clic) ; levée dès que la porte extérieure est fermée et que la pression est revenue à alert_clear_pressure
## dans le sas et dans tout ce qui communique avec lui (pression arrondie au centième, comme sur les témoins) : un
## module isolé reste à sa pression, sans retenir l'alerte. L'alerte d'avant est rétablie, sauf si le joueur a
## changé d'alerte entre-temps.
## Pas d'alerte sans courant (Station.Alert.BLACKOUT, « plus de lumière »).
func _update_alert() -> void:
	var outer := _station.is_hatch_opening(_station.airlock_outer_hatch)
	if not _alert_raised:
		if outer and _station.is_hatch_opening(_station.airlock_inner_hatch) \
				and _station.get_alert() != Station.Alert.BLACKOUT:
			_alert_raised = true
			_alert_before = _station.get_alert()
			_station.set_alert(Station.Alert.RED)
		return
	if outer:
		return
	for zones: Array in _groups():
		if zones.has(SAS):
			for zone: String in zones:
				if snappedf(float(pressures[zone]), 0.01) < alert_clear_pressure:
					return
	_alert_raised = false
	if _station.get_alert() == Station.Alert.RED:
		_station.set_alert(_alert_before)


## Durée (s) d'une vidange ou d'un remplissage complet par la valve d'un ensemble de volume volume (m³) : sas_s pour
## le sas seul, station_valve_s pour toute la station, entre les deux selon la racine de la part du volume ajouté.
func _valve_duration(volume: float, sas_s: float) -> float:
	var sas := float(ZONES[SAS][1])
	var part := clampf((volume - sas) / maxf(_volume_total - sas, 1.0), 0.0, 1.0)
	return lerpf(sas_s, station_valve_s, sqrt(part))


## Volume (clé de ZONES) qui contient le point global, "" hors de tous.
func zone_at(world_position: Vector3) -> String:
	var b := _to_blender(_station.to_local(world_position))
	for zone: String in ZONES:
		for box: Array in ZONES[zone][0]:
			if _in_box(b, box):
				return zone
	return ""


## Pression d'un volume (0 dans l'espace ou hors des volumes).
func pressure_of(zone: String) -> float:
	return float(pressures.get(zone, 0.0))


## Courant d'air (vitesse visée, m/s, repère global) au point global du volume zone : vers l'écoutille suivante sur le
## chemin de la sortie, nul si le volume ne communique pas avec l'espace.
func flow_at(world_position: Vector3, zone: String) -> Vector3:
	if not _next.has(zone):
		return Vector3.ZERO
	var b := _to_blender(_station.to_local(world_position))
	for box: Array in ZONES[zone][0]:
		if box.size() > 6 and _in_box(b, box):
			return (_station.to_global(_from_blender(box[6])) - world_position).normalized() * float(_flow_speed[zone])
	var hatch: Array = HATCHES[_next[zone]]
	var other: String = hatch[1] if hatch[0] == zone else hatch[0]
	var axis: Vector3 = hatch[3]
	var center: Vector3 = hatch[2]
	# Sens de l'axe : vers le volume suivant (l'espace est sous le sas).
	var toward := (_zone_center(other) - center) if other != SPACE else Vector3(0, 0, -1)
	var target := _station.to_global(_from_blender(center + axis * signf(axis.dot(toward)) * BEYOND_M))
	var to_target := target - world_position
	if to_target.length() < 0.01:
		return Vector3.ZERO
	return to_target.normalized() * float(_flow_speed[zone])


## Centre (global) d'un volume.
func zone_center(zone: String) -> Vector3:
	return _station.to_global(_from_blender(_zone_center(zone)))


## Ensembles de volumes qui communiquent (SPACE compris), par union des écoutilles ouvertes.
func _groups() -> Array:
	var parent := {SPACE: SPACE}
	for zone: String in ZONES:
		parent[zone] = zone
	for id: String in HATCHES:
		if _station.is_hatch_opening(id):
			var a := _find(parent, HATCHES[id][0])
			var b := _find(parent, HATCHES[id][1])
			parent[a] = b
	var by_root := {}
	for zone: String in parent:
		var root := _find(parent, zone)
		if not by_root.has(root):
			by_root[root] = []
		by_root[root].append(zone)
	return by_root.values()


func _find(parent: Dictionary, zone: String) -> String:
	while parent[zone] != zone:
		zone = parent[zone]
	return zone


## Parcours en largeur depuis l'espace dans un ensemble qui communique avec lui : écoutille suivante de chaque volume.
func _route(zones: Array, speed: float) -> void:
	var queue: Array[String] = [SPACE]
	var seen := {SPACE: true}
	while not queue.is_empty():
		var here: String = queue.pop_front()
		for id: String in HATCHES:
			var hatch: Array = HATCHES[id]
			if not _station.is_hatch_opening(id) or (hatch[0] != here and hatch[1] != here):
				continue
			var other: String = hatch[1] if hatch[0] == here else hatch[0]
			if seen.has(other) or not zones.has(other):
				continue
			seen[other] = true
			_next[other] = id
			_flow_speed[other] = speed
			queue.append(other)


static func _in_box(b: Vector3, box: Array) -> bool:
	return b.x >= box[0] and b.x <= box[1] and b.y >= box[2] and b.y <= box[3] and b.z >= box[4] and b.z <= box[5]


func _zone_center(zone: String) -> Vector3:
	var box: Array = ZONES[zone][0][0]
	return Vector3((box[0] + box[1]) * 0.5, (box[2] + box[3]) * 0.5, (box[4] + box[5]) * 0.5)


static func _to_blender(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


static func _from_blender(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
