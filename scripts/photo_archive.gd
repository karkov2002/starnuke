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

const GROUP := &"photo_archive"
const FOLDER := "user://photos"
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
	var photo := {"id": photos.size() + 1, "texture": ImageTexture.create_from_image(thumb), "lat": lat_deg,
			"lon": lon_deg, "utc_unix": utc_unix, "altitude_km": altitude_km, "footprint_km": footprint_km,
			"path": path}
	photos.append(photo)
	photo_taken.emit(photo)
	return photo


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
