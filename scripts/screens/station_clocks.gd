class_name StationClocks
extends StationLcd
## Horloges murales de la station (objets Interactif_Horloge_* : couchette, cuisine, poste de pilotage, sas ; nœud
## StationClocks de scenes/orbit_view.tscn) : date ISO 8601 et heure UTC du jeu (Orbit), redessinées quand la seconde
## affichée change. Disposition (cotes de SegmentDisplay, identiques à la texture de démonstration Blender) : date en
## petit en haut à gauche, « UTC » en haut à droite, heure en grands chiffres en bas. Textes : chiffres et « UTC »
## (aucune langue) : hors fichiers de langue.


func mesh_prefix() -> String:
	return "Interactif_Horloge_"


func _content() -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(floorf(_orbit.get_utc_unix_s())))
	return "%04d-%02d-%02d|%02d:%02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


func _paint(canvas: CanvasItem, content: String) -> void:
	var parts := content.split("|")
	var date: String = parts[0]
	var time: String = parts[1]
	SegmentDisplay.draw_digits(canvas, date, -0.022 - SegmentDisplay.text_width(date, 0.0105) / 2.0, 0.0170, 0.0150,
			0.0105)
	SegmentDisplay.draw_digits(canvas, time, -SegmentDisplay.text_width(time, 0.0198) / 2.0, -0.0110, 0.0290, 0.0198)
	SegmentDisplay.draw_label(canvas, "UTC", SegmentDisplay.GLASS_W / 2.0 - 0.010, 0.0170, 0.0115, true)
