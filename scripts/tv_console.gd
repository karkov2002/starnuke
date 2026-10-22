class_name TvConsole
extends ScreenSeatConsole
## Télévision du module Commande (nœud TvConsole de scenes/orbit_view.tscn) : l'écran SCREEN_NODE (réservé, retiré
## des écrans d'ambiance TechScreens) diffuse les chaînes d'information du monde entier (TvDisplay, dans un
## SubViewport). Survol, vue TV, souris transmise à l'interface (bouton « Chaînes », guide des chaînes), clic droit
## pour quitter (la télévision reste sur la chaîne choisie), garde de distance (lecture suspendue au loin) :
## ScreenSeatConsole.
## - Chaînes : une par pays souverain (assets/tv/channels.csv : code ISO, nom de la chaîne, inventé, capitale).
##   Règle de jeu : un pays dont la capitale est touchée (au moins OFF_AIR_PSI de surpression d'une explosion) ne
##   diffuse plus : sa chaîne passe sur la mire « Pas de signal ». Les explosions persistent : l'état est recalculé à
##   chaque tir et toutes les CHECK_S secondes.
##   Règle de jeu : après une explosion, toutes les chaînes encore à l'antenne passent en édition spéciale « Alerte
##   info » pendant ALERT_HOURS heures de jeu (horloge UTC d'Orbit) après la dernière, puis reviennent à l'édition normale.

const SCREEN_NODE := "Interactif_Ecran_03"
const CHANNELS_PATH := "res://assets/tv/channels.csv"
const VIEWPORT_HEIGHT := 640
const OFF_AIR_PSI := 5.0
const CHECK_S := 2.0
const ALERT_HOURS := 24.0
const DEFAULT_CHANNEL := "FRA"

@export var launcher_path: NodePath = ^"../NukeLauncher"
@export var orbit_path: NodePath = ^"../Orbit"

var _launcher: NukeLauncher
var _orbit: OrbitSimulation
## Heure UTC (s) de la dernière explosion (-INF : aucune) ; édition spéciale en cours.
var _last_detonation_unix := -INF
var _alert := false
var _display: TvDisplay
## Code -> {name, lat, lon} ; codes hors d'antenne.
var _channels := {}
var _off_air := {}
var _check := 0.0


func _screen_node() -> String:
	return SCREEN_NODE


func _prepare() -> bool:
	_launcher = get_node_or_null(launcher_path) as NukeLauncher
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_load_channels()
	return true


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT, true)


func _create_display(into: SubViewport) -> void:
	_display = TvDisplay.new()
	_display.name = "Display"
	_display.console = self
	_display.channel = DEFAULT_CHANNEL if _channels.has(DEFAULT_CHANNEL) else ""
	_display.size = Vector2(into.size)
	_display.channel_selected.connect(func(code: String) -> void: _display.show_channel(code))
	into.add_child(_display)
	if _launcher:
		_launcher.detonated.connect(func(effect: NukeEffect) -> void:
			# Explosion recréée (sauvegarde) : l'édition spéciale suit son heure réelle, pas le chargement.
			var at := effect.params.detonation_utc_s if effect.params and effect.params.detonation_utc_s >= 0.0 \
					else (_orbit.get_utc_unix_s() if _orbit else -INF)
			_last_detonation_unix = maxf(_last_detonation_unix, at)
			_update_off_air()
			# Nouveau tir : le bandeau repart tout de suite avec le nouveau bilan (après le calcul des pertes).
			_display.restart_ticker.call_deferred())
	_update_off_air()


func _scan_depth() -> float:
	return 0.05


func _on_near_changed(near_now: bool) -> void:
	_display.set_playing(near_now)


func _update_screen(delta: float, _near_now: bool) -> void:
	_check += delta
	if _check >= CHECK_S:
		_update_off_air()


func _hover_key() -> String:
	return "TV_HOVER"


func _exit_key() -> String:
	return "TV_EXIT_HINT"


# --- Chaînes --------------------------------------------------------------------------------------------------------

func channel_codes() -> Array[String]:
	var codes: Array[String] = []
	codes.assign(_channels.keys())
	return codes


func channel_name(code: String) -> String:
	return String(_channels.get(code, {}).get("name", ""))


## Langue de diffusion de la chaîne (colonne lang de channels.csv).
func channel_lang(code: String) -> String:
	return String(_channels.get(code, {}).get("lang", "en"))


## Aperçu du bandeau d'une chaîne (mise au point, MCP / console).
func news_preview(code: String) -> String:
	var rng := RandomNumberGenerator.new()
	return news_text(code, rng)


## Texte du bandeau de la chaîne (TvNews) : explosions, ou infos ordinaires (bourse, météo de la capitale, sport) tant
## qu'il n'y en a eu aucune.
func news_text(code: String, rng: RandomNumberGenerator) -> String:
	var effects: Array[NukeEffect] = []
	if _launcher:
		effects = _launcher.get_effects()
	var off_air: Array[String] = []
	off_air.assign(_off_air.keys())
	return TvNews.compose(code, channel_lang(code),
			{"effects": effects, "tally": NukeTally.compute(effects), "off_air": off_air, "alert": _alert,
			"utc_unix": _orbit.get_utc_unix_s() if _orbit else 0.0, "channels": channel_codes(),
			"capital": Vector2(_channels.get(code, {}).get("lat", 0.0), _channels.get(code, {}).get("lon", 0.0))}, rng)


func is_alert() -> bool:
	return _alert


func is_off_air(code: String) -> bool:
	return _off_air.has(code)


func _load_channels() -> void:
	var file := FileAccess.open(CHANNELS_PATH, FileAccess.READ)
	if file == null:
		push_error("TvConsole : %s illisible" % CHANNELS_PATH)
		return
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 5:
			continue
		_channels[row[0]] = {"name": row[1], "lat": float(row[2]), "lon": float(row[3]), "lang": row[4]}


## Pays dont la capitale est sous au moins OFF_AIR_PSI d'une explosion.
func _update_off_air() -> void:
	_check = 0.0
	if _launcher == null:
		return
	var off := {}
	for effect in _launcher.get_effects():
		var p := effect.params
		if p == null:
			continue
		var radius := NukeScaling.overpressure_range_km(p.yield_kt, OFF_AIR_PSI, p.burst_height_km)
		for code: String in _channels:
			var c: Dictionary = _channels[code]
			if GeoMath.distance_km(p.latitude_deg, p.longitude_deg, c.lat, c.lon) <= radius:
				off[code] = true
	var since := _orbit.get_utc_unix_s() - _last_detonation_unix if _orbit else INF
	var alert := since >= 0.0 and since < ALERT_HOURS * 3600.0
	if off.hash() != _off_air.hash() or alert != _alert:
		_alert = alert
		_off_air = off
		if _display:
			_display.refresh()
