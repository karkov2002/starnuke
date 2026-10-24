class_name StationPosition
extends StationLcd
## Afficheur de position de la station (objet Interactif_Position_Couchette, à droite de l'horloge au pied de la
## couchette ; nœud StationPosition de scenes/orbit_view.tscn) : latitude et longitude du point survolé
## (Orbit.get_subsatellite_point) en degrés décimaux à trois décimales, en temps réel (refresh_hz). Au réveil, un joueur
## doué en géographie devine où il se trouve. Disposition (cotes de SegmentDisplay, identiques à la texture de
## démonstration Blender) : lettre de l'hémisphère à gauche (clés DIR_N, DIR_S, DIR_E, DIR_W : O pour Ouest en
## français, O pour Ost en allemand), latitude en haut (« 48.857° »), longitude en bas sur trois chiffres
## (« 002.352° »). Redessiné aussi au changement de langue (la langue fait partie du contenu).


func mesh_prefix() -> String:
	return "Interactif_Position_"


func _content() -> String:
	var point := _orbit.get_subsatellite_point()
	return "%s|%s|%s|%s" % [tr("DIR_N") if point.x >= 0.0 else tr("DIR_S"), "%7.3f°" % absf(point.x),
			tr("DIR_E") if point.y >= 0.0 else tr("DIR_W"), "%07.3f°" % absf(point.y)]


func _paint(canvas: CanvasItem, content: String) -> void:
	var parts := content.split("|")
	for row in 2:
		var cz := 0.0150 if row == 0 else -0.0165
		SegmentDisplay.draw_label(canvas, parts[row * 2], -0.078, cz, 0.0170)
		SegmentDisplay.draw_digits(canvas, parts[row * 2 + 1], -0.052, cz, 0.0260, 0.0168)
