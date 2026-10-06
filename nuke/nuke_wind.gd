class_name NukeWind
extends RefCounted
## Vent réel au point d'une explosion : la même carte que l'advection des nuages (assets/textures/cloud_wind.exr,
## vent moyen GFS du 15/07/2023 à 850/700/500 hPa, soit ~1,5 à 5,5 km d'altitude, cf. tools/build_wind_field.ps1).
## 720 x 360 (0,5°), R = vent vers l'est, G = vent vers le nord (m/s) ; colonne 0 = 180° O, ligne 0 = 90° N, texels
## centrés.

const WIND_TEXTURE := "res://assets/textures/cloud_wind.exr"

static var _image: Image


## Vent (m/s, x = vers l'est, y = vers le nord) à la latitude / longitude données, interpolé. Vector2.ZERO si la carte
## manque.
static func sample(latitude_deg: float, longitude_deg: float) -> Vector2:
	if _image == null:
		var texture := load(WIND_TEXTURE) as Texture2D
		if texture == null:
			return Vector2.ZERO
		_image = texture.get_image()
		if _image == null:
			return Vector2.ZERO
	var w := _image.get_width()
	var h := _image.get_height()
	var x := (longitude_deg + 180.0) / 360.0 * w - 0.5
	var y := clampf((90.0 - latitude_deg) / 180.0 * h - 0.5, 0.0, h - 1.0)
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var y1 := mini(y0 + 1, h - 1)
	var top := _texel(x0, y0, w).lerp(_texel(x0 + 1, y0, w), fx)
	var bottom := _texel(x0, y1, w).lerp(_texel(x0 + 1, y1, w), fx)
	return top.lerp(bottom, fy)


## Direction d'où vient le vent (convention météo, degrés : 0 = du nord, 90 = d'est).
static func from_direction_deg(wind: Vector2) -> float:
	return fposmod(rad_to_deg(atan2(-wind.x, -wind.y)), 360.0)


static func _texel(x: int, y: int, width: int) -> Vector2:
	var c := _image.get_pixel(posmod(x, width), y)
	return Vector2(c.r, c.g)
