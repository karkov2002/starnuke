class_name CloudWeather
extends RefCounted
## Météo d'un point de la Terre, côté CPU (bandeau de la télévision, TvNews) : la même que celle qu'on voit depuis la
## station.
## - Couverture nuageuse (0 à 1) : carte réduite de l'instantané VIIRS (assets/cloud_cover.res, 0,25°,
##   tools/build_cloud_cover.gd), lue au point d'où vient l'air à l'heure UTC donnée : comme le shader des nuages
##   (shaders/cloud_density.gdshaderinc), on remonte le vent réel du jour (assets/textures/cloud_wind.exr, Runge-Kutta 2)
##   depuis l'heure du passage du satellite (13 h 30 solaire locale), écart ramené dans [−12 h, +12 h]. Moyenne sur
##   ~50 km autour du point.
## - Température (°C) : modèle simple et plausible (pas de données) : moyenne annuelle selon la latitude, saison selon
##   l'hémisphère et le jour de l'année, cycle du jour (maximum vers 15 h solaire) atténué par les nuages.
## Conventions des cartes : colonne 0 = 180° O, ligne 0 = 90° N, texels centrés.

const COVER_PATH := "res://assets/cloud_cover.res"
const WIND_PATH := "res://assets/textures/cloud_wind.exr"
const SNAPSHOT_LOCAL_HOUR := 13.5
const STEPS := 6

static var _cover: Image
static var _wind: Image
static var _loaded := false


## Couverture nuageuse (0 à 1) au point (degrés) à l'instant utc_unix_s.
static func cloud_cover(lat_deg: float, lon_deg: float, utc_unix_s: float) -> float:
	_load()
	if _cover == null:
		return 0.5
	var day_s := fposmod(utc_unix_s, 86400.0)
	var snapshot_utc_s := (SNAPSHOT_LOCAL_HOUR - lon_deg / 15.0) * 3600.0
	var dt := fposmod(day_s - snapshot_utc_s + 43200.0, 86400.0) - 43200.0
	var origin := _backtrace(Vector2(lat_deg, lon_deg), dt)
	var total := 0.0
	for dy in [-0.25, 0.0, 0.25]:
		for dx in [-0.25, 0.0, 0.25]:
			total += _sample(_cover, origin.x + dy, origin.y + dx).r
	return total / 9.0


## Température plausible (°C) au point, au jour de l'année et à l'heure solaire locale donnés, sous cette couverture.
static func temperature(lat_deg: float, day_of_year: int, local_solar_hour: float, cover: float) -> float:
	var lat := deg_to_rad(lat_deg)
	var annual := 30.0 * pow(cos(lat), 1.2) - 4.0
	# Été (jour 196, mi-juillet) au nord, hiver au sud.
	var season := 13.0 * sin(lat) * cos(TAU * (day_of_year - 196) / 365.25)
	var daily := 5.5 * (1.0 - 0.6 * cover) * cos(TAU * (local_solar_hour - 15.0) / 24.0)
	return annual + season + daily


## Position (lat, lon) dans l'instantané de l'air qui se trouve en point après dt secondes.
static func _backtrace(point: Vector2, dt: float) -> Vector2:
	if _wind == null:
		return point
	var h := dt / STEPS
	for i in STEPS:
		var mid := _move(point, _wind_at(point), -0.5 * h)
		point = _move(point, _wind_at(mid), -h)
	return point


## Vent (m/s : est, nord) au point (lat, lon).
static func _wind_at(point: Vector2) -> Vector2:
	var c := _sample(_wind, point.x, point.y)
	return Vector2(c.r, c.g)


static func _move(point: Vector2, wind: Vector2, dt: float) -> Vector2:
	var lat := point.x + rad_to_deg(wind.y * dt / GeoMath.EARTH_RADIUS_M)
	var lon := point.y + rad_to_deg(wind.x * dt / (GeoMath.EARTH_RADIUS_M * maxf(cos(deg_to_rad(point.x)), 0.05)))
	return Vector2(clampf(lat, -89.9, 89.9), wrapf(lon, -180.0, 180.0))


## Lecture bilinéaire d'une carte équirectangulaire (texels centrés), longitude qui boucle.
static func _sample(image: Image, lat_deg: float, lon_deg: float) -> Color:
	var w := image.get_width()
	var h := image.get_height()
	var x := (wrapf(lon_deg, -180.0, 180.0) + 180.0) / 360.0 * w - 0.5
	var y := clampf((90.0 - lat_deg) / 180.0 * h - 0.5, 0.0, h - 1.0)
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var y1 := mini(y0 + 1, h - 1)
	var a := image.get_pixel(posmod(x0, w), y0).lerp(image.get_pixel(posmod(x0 + 1, w), y0), fx)
	var b := image.get_pixel(posmod(x0, w), y1).lerp(image.get_pixel(posmod(x0 + 1, w), y1), fx)
	return a.lerp(b, fy)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cover = load(COVER_PATH) as Image
	var wind := load(WIND_PATH) as Texture2D
	_wind = wind.get_image() if wind else null
	if _wind and _wind.is_compressed():
		_wind.decompress()
	if _cover == null:
		push_warning("CloudWeather : %s manquant (tools/build_cloud_cover.gd)" % COVER_PATH)
