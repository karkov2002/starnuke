class_name NukeWind
extends RefCounted
## Vent réel au point d'une explosion (cartes construites par tools/build_wind_field.ps1, GFS du 15/07/2023, moyenne
## des 4 analyses du jour) :
## - sample() : la même carte que l'advection des nuages (assets/textures/cloud_wind.exr, vent moyen à
##   850/700/500 hPa, soit ~1,5 à 5,5 km d'altitude). 720 x 360 (0,5°), R = vent vers l'est, G = vent vers le nord
##   (m/s) ; colonne 0 = 180° O, ligne 0 = 90° N, texels centrés ;
## - sample_profile() : le profil vertical (assets/textures/wind_profile.exr), 14 niveaux de pression de 850 à
##   0,1 hPa (~1,5 à ~64 km), empilés du plus bas au plus haut, chacun sur 360 x 180 texels (1°, mêmes conventions) ;
##   R, G = vent (m/s), B = altitude géopotentielle du niveau (km).

const WIND_TEXTURE := "res://assets/textures/cloud_wind.exr"
const PROFILE_TEXTURE := "res://assets/textures/wind_profile.exr"

static var _image: Image
static var _profile: Image


## Vent (m/s, x = vers l'est, y = vers le nord) à la latitude / longitude données, interpolé. Vector2.ZERO si la carte
## manque.
static func sample(latitude_deg: float, longitude_deg: float) -> Vector2:
	if _image == null:
		_image = _load(WIND_TEXTURE)
		if _image == null:
			return Vector2.ZERO
	var c := _bilinear(_image, _image.get_width(), _image.get_height(), 0, latitude_deg, longitude_deg)
	return Vector2(c.r, c.g)


## Profil vertical du vent au point donné : un Vector3(altitude km, vent vers l'est, vent vers le nord en m/s) par
## niveau, d'altitude croissante. Vide si la carte manque.
static func sample_profile(latitude_deg: float, longitude_deg: float) -> PackedVector3Array:
	var profile := PackedVector3Array()
	if _profile == null:
		_profile = _load(PROFILE_TEXTURE)
		if _profile == null:
			return profile
	var w := _profile.get_width()
	var h := w >> 1
	@warning_ignore("integer_division")
	var levels := _profile.get_height() / h
	for level in levels:
		var c := _bilinear(_profile, w, h, level * h, latitude_deg, longitude_deg)
		profile.append(Vector3(c.b, c.r, c.g))
	return profile


## Direction d'où vient le vent (convention météo, degrés : 0 = du nord, 90 = d'est).
static func from_direction_deg(wind: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(-wind.x, -wind.y)), 360.0)


static func _load(path: String) -> Image:
	var texture := load(path) as Texture2D
	return texture.get_image() if texture else null


## Interpolation bilinéaire dans la carte globale w x h dont la première ligne est row0.
static func _bilinear(image: Image, w: int, h: int, row0: int, latitude_deg: float, longitude_deg: float) -> Color:
	var x := (longitude_deg + 180.0) / 360.0 * w - 0.5
	var y := clampf((90.0 - latitude_deg) / 180.0 * h - 0.5, 0.0, h - 1.0)
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var y1 := mini(y0 + 1, h - 1)
	var top := _texel(image, x0, row0 + y0, w).lerp(_texel(image, x0 + 1, row0 + y0, w), fx)
	var bottom := _texel(image, x0, row0 + y1, w).lerp(_texel(image, x0 + 1, row0 + y1, w), fx)
	return top.lerp(bottom, fy)


static func _texel(image: Image, x: int, y: int, width: int) -> Color:
	return image.get_pixel(posmod(x, width), y)
