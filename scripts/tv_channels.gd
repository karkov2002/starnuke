class_name TvChannels
extends RefCounted
## Modèle des chaînes de télévision (une par pays souverain, assets/tv/channels.csv : code ISO, nom de la chaîne,
## inventé, capitale, langue) et des deux règles de jeu de la télévision, tenu par TvConsole et lu par TvDisplay :
## - un pays dont la capitale est touchée (au moins OFF_AIR_PSI de surpression d'une explosion) ne diffuse plus,
##   définitivement (les explosions persistent) : sa chaîne est « hors d'antenne » (mire « Pas de signal ») ;
## - après une explosion, toutes les chaînes encore à l'antenne passent en édition spéciale « Alerte info » pendant
##   ALERT_HOURS heures de jeu après la dernière, puis reviennent à l'édition normale.
## L'état (hors d'antenne, alerte) est recalculé par update() à partir de la liste des explosions et de l'heure UTC du
## jeu, que la console lui passe à chaque tir et toutes les CHECK_S secondes ; changed est émis quand il change. Le
## texte des bandeaux (TvNews) part des mêmes explosions et de la même heure (à CHECK_S près).

signal changed

const CHANNELS_PATH := "res://assets/tv/channels.csv"
const OFF_AIR_PSI := 5.0
const CHECK_S := 2.0
const ALERT_HOURS := 24.0

## Code -> {name, lat, lon, lang}.
var _channels := {}
## Codes hors d'antenne.
var _off_air := {}
var _alert := false
## Heure UTC (s) de la dernière explosion (-INF : aucune).
var _last_detonation_unix := -INF
## Explosions et heure UTC (s) du dernier update().
var _effects: Array[NukeEffect] = []
var _utc_unix := 0.0


func _init(path := CHANNELS_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TvChannels : %s illisible" % path)
		return
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 5:
			continue
		_channels[row[0]] = {"name": row[1], "lat": float(row[2]), "lon": float(row[3]), "lang": row[4]}


func has(code: String) -> bool:
	return _channels.has(code)


func codes() -> Array[String]:
	var result: Array[String] = []
	result.assign(_channels.keys())
	return result


func name_of(code: String) -> String:
	return String(_channels.get(code, {}).get("name", ""))


## Langue de diffusion de la chaîne (colonne lang de channels.csv).
func lang_of(code: String) -> String:
	return String(_channels.get(code, {}).get("lang", "en"))


## Capitale (latitude, longitude en degrés) du pays de la chaîne.
func capital_of(code: String) -> Vector2:
	return Vector2(_channels.get(code, {}).get("lat", 0.0), _channels.get(code, {}).get("lon", 0.0))


func is_off_air(code: String) -> bool:
	return _off_air.has(code)


func is_alert() -> bool:
	return _alert


## Une explosion vient d'avoir lieu (ou est recréée d'une sauvegarde) à l'heure UTC donnée.
func record_detonation(utc_unix: float) -> void:
	_last_detonation_unix = maxf(_last_detonation_unix, utc_unix)


## Recalcule les chaînes hors d'antenne et l'édition spéciale d'après les explosions et l'heure UTC du jeu ; vrai (et
## changed émis) si l'état a changé.
func update(effects: Array[NukeEffect], utc_unix: float) -> bool:
	_effects = effects
	_utc_unix = utc_unix
	var off := {}
	for effect in effects:
		var p := effect.params
		if p == null:
			continue
		var radius := NukeScaling.overpressure_range_km(p.yield_kt, OFF_AIR_PSI, p.burst_height_km)
		for code: String in _channels:
			var c: Dictionary = _channels[code]
			if GeoMath.distance_km(p.latitude_deg, p.longitude_deg, c.lat, c.lon) <= radius:
				off[code] = true
	var since := utc_unix - _last_detonation_unix
	var alert := since >= 0.0 and since < ALERT_HOURS * 3600.0
	if off.hash() == _off_air.hash() and alert == _alert:
		return false
	_alert = alert
	_off_air = off
	changed.emit()
	return true


## Texte du bandeau de la chaîne (TvNews) : explosions, ou infos ordinaires (bourse, météo de la capitale, sport) tant
## qu'il n'y en a eu aucune.
func news_text(code: String, rng: RandomNumberGenerator) -> String:
	var off_air: Array[String] = []
	off_air.assign(_off_air.keys())
	return TvNews.compose(code, lang_of(code),
			{"effects": _effects, "tally": NukeTally.compute(_effects), "off_air": off_air, "alert": _alert,
			"utc_unix": _utc_unix, "channels": codes(), "capital": capital_of(code)}, rng)


## Aperçu du bandeau d'une chaîne (mise au point).
func news_preview(code: String) -> String:
	return news_text(code, RandomNumberGenerator.new())
