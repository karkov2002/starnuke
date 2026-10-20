class_name PhotoArchive
extends Node
## Photos satellites de la partie (nœud Photos de scenes/orbit_view.tscn, groupe GROUP) : prises depuis l'onglet
## Photographie de la tablette (vue au nadir, scripts/tablet.gd), elles sont gardées ici pour la galerie de la tablette
## et, plus tard, pour les objectifs « photo » des missions de campagne (signal photo_taken).
## Chaque photo : image de la galerie (THUMB_WIDTH au plus), point survolé à la prise de vue (latitude, longitude
## du point sous la station : c'est lui qui compte pour la précision d'une photo de mission), heure UTC du jeu,
## altitude, emprise au sol (largeur × hauteur de l'image, km), fichier PNG pleine résolution enregistré dans
## user://photos/ (le joueur garde ses photos).

signal photo_taken(photo: Dictionary)
## Photos remplacées par celles d'une sauvegarde (restore).
signal restored

const GROUP := &"photo_archive"
const FOLDER := "user://photos"
## Vignettes de la galerie (rendu de la vue en direct), pour les recharger avec une sauvegarde de campagne.
const THUMBS := "user://photos/thumbs"
const THUMB_WIDTH := 600

## Photos, dans l'ordre de prise : {id, texture, lat, lon, utc_unix, altitude_km, footprint_km (Vector2), path}.
var photos: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)


## Ajoute une photo prise au-dessus de (lat, lon) : image pleine résolution (rendu final, enregistrée en PNG) et image
## pour l'écran de la tablette (rendu de la vue en direct, cf. Tablet._take_photo) ; rend sa description.
func add(image: Image, screen_image: Image, lat_deg: float, lon_deg: float, utc_unix: float, altitude_km: float,
		footprint_km: Vector2) -> Dictionary:
	var path := _save(image, lat_deg, lon_deg, utc_unix)
	var thumb := screen_image.duplicate() as Image
	if thumb.get_width() > THUMB_WIDTH:
		thumb.resize(THUMB_WIDTH, roundi(THUMB_WIDTH * float(thumb.get_height()) / thumb.get_width()),
				Image.INTERPOLATE_LANCZOS)
	var thumb_path := ""
	if not path.is_empty() and DirAccess.make_dir_recursive_absolute(THUMBS) == OK:
		thumb_path = THUMBS.path_join(path.get_file())
		if thumb.save_png(thumb_path) != OK:
			thumb_path = ""
	var photo := {"id": photos.size() + 1, "texture": ImageTexture.create_from_image(thumb), "lat": lat_deg,
			"lon": lon_deg, "utc_unix": utc_unix, "altitude_km": altitude_km, "footprint_km": footprint_km,
			"path": path, "thumb_path": thumb_path}
	photos.append(photo)
	photo_taken.emit(photo)
	return photo


## Photos pour une sauvegarde (sans les images : fichiers PNG de user://photos/ et de ses vignettes).
func to_save() -> Array:
	return photos.map(func(p: Dictionary) -> Dictionary:
		return {"lat": p.lat, "lon": p.lon, "utc_unix": p.utc_unix, "altitude_km": p.altitude_km,
				"footprint_km": [p.footprint_km.x, p.footprint_km.y], "path": p.path, "thumb_path": p.thumb_path})


## Photos d'une sauvegarde (to_save) : vignette relue (sinon la photo pleine résolution) ; une photo dont les
## fichiers ont disparu est ignorée. Pas de photo_taken (ce ne sont pas de nouvelles prises de vue).
func restore(saved: Array) -> void:
	photos.clear()
	for entry: Dictionary in saved:
		var image := Image.load_from_file(str(entry.thumb_path)) if FileAccess.file_exists(str(entry.thumb_path)) \
				else (Image.load_from_file(str(entry.path)) if FileAccess.file_exists(str(entry.path)) else null)
		if image == null:
			continue
		var footprint: Array = entry.footprint_km
		photos.append({"id": photos.size() + 1, "texture": ImageTexture.create_from_image(image), "lat": entry.lat,
				"lon": entry.lon, "utc_unix": entry.utc_unix, "altitude_km": entry.altitude_km,
				"footprint_km": Vector2(footprint[0], footprint[1]), "path": entry.path,
				"thumb_path": entry.thumb_path})
	restored.emit()


## PNG dans user://photos/ (date et heure du jeu, point survolé dans le nom) ; "" en cas d'échec.
func _save(image: Image, lat_deg: float, lon_deg: float, utc_unix: float) -> String:
	if DirAccess.make_dir_recursive_absolute(FOLDER) != OK:
		return ""
	var stamp := Time.get_datetime_string_from_unix_time(int(utc_unix)).replace(":", "-")
	var path := FOLDER.path_join("%s_%+.2f_%+.2f.png" % [stamp, lat_deg, lon_deg])
	if image.save_png(path) != OK:
		push_warning("PhotoArchive : %s non enregistrée" % path)
		return ""
	return path
