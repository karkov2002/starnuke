class_name StationLayout
extends RefCounted
## Géométrie de la station en coordonnées Blender du modèle (assets/station/station_spatiale.glb), partagée par l'air
## de la station (StationAtmosphere), les témoins de pression (PressureGauges) et les écrans d'ambiance (TechScreens) :
## volumes (modules, jonctions, sas), écoutilles qui les relient, emplacements des témoins, modules à écrans. Une seule
## table de chaque, et une seule conversion entre le repère Blender (Z vers le haut) et celui de la station dans Godot
## (Y vers le haut) : (x, y, z) Blender → (x, z, −y). À terme, ces tables pourront être exportées par
## tools/blender/export_station.py avec le modèle.

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
## Témoins de pression : module → position et normale de la paroi (coordonnées Blender), relevées par lancer de
## rayons dans le modèle : panneau de paroi à 30° au-dessus de l'horizontale (sous les tuyaux et les luminaires),
## libre d'équipements, ou cloison de l'écoutille (modules de missiles, côté opposé au battant).
const GAUGES := {
	"Commande": [Vector3(7.9, 1.167, 0.674), Vector3(0.0, -0.882, -0.471)],
	"Habitation": [Vector3(-3.7, -1.167, 0.674), Vector3(0.0, 0.882, -0.471)],
	"Arrimage": [Vector3(-7.9, 1.167, 0.674), Vector3(0.0, -0.882, -0.471)],
	"Missile_1": [Vector3(1.15, 2.49, 0.0), Vector3(0.0, 1.0, 0.0)],
	"Missile_2": [Vector3(-1.15, -2.49, 0.0), Vector3(0.0, -1.0, 0.0)],
}
## Modules qui ont des écrans d'ambiance animés (TechScreens).
const SCREEN_MODULES: Array[String] = ["Commande", "Arrimage"]


## Repère Blender (Z vers le haut) → repère de la station dans Godot (Y vers le haut).
static func to_godot(blender: Vector3) -> Vector3:
	return Vector3(blender.x, blender.z, -blender.y)


## Repère de la station dans Godot → repère Blender.
static func to_blender(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)


## Volume (clé de ZONES) qui contient le point (coordonnées Blender), boîtes élargies de margin (m) ; "" hors de tous.
static func zone_at(blender_point: Vector3, margin := 0.0) -> String:
	for zone: String in ZONES:
		for box: Array in ZONES[zone][0]:
			if in_box(blender_point, box, margin):
				return zone
	return ""


## Le point (coordonnées Blender) est-il dans une des boîtes du volume zone, élargies de margin (m) ?
static func is_in_zone(blender_point: Vector3, zone: String, margin := 0.0) -> bool:
	for box: Array in ZONES[zone][0]:
		if in_box(blender_point, box, margin):
			return true
	return false


static func in_box(b: Vector3, box: Array, margin := 0.0) -> bool:
	return b.x >= box[0] - margin and b.x <= box[1] + margin and b.y >= box[2] - margin and b.y <= box[3] + margin \
			and b.z >= box[4] - margin and b.z <= box[5] + margin


## Centre (coordonnées Blender) de la boîte principale d'un volume.
static func zone_center(zone: String) -> Vector3:
	var box: Array = ZONES[zone][0][0]
	return Vector3((box[0] + box[1]) * 0.5, (box[2] + box[3]) * 0.5, (box[4] + box[5]) * 0.5)


## Volume d'air (m³) et nombre de modules comptés d'un volume.
static func air_volume(zone: String) -> float:
	return float(ZONES[zone][1])


static func module_count(zone: String) -> int:
	return int(ZONES[zone][2])
