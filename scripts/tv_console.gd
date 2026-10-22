class_name TvConsole
extends ScreenSeatConsole
## Télévision du module Commande (nœud TvConsole de scenes/orbit_view.tscn) : l'écran SCREEN_NODE (réservé, retiré
## des écrans d'ambiance TechScreens) diffuse les chaînes d'information du monde entier (TvDisplay, dans un
## SubViewport). Survol, vue TV, souris transmise à l'interface (bouton « Chaînes », guide des chaînes), clic droit
## pour quitter (la télévision reste sur la chaîne choisie), garde de distance (lecture suspendue au loin) :
## ScreenSeatConsole. Chaînes et règles de jeu (hors d'antenne, édition spéciale) : TvChannels, tenu à jour ici
## d'après les explosions (NukeLauncher) et l'heure UTC du jeu (Orbit), à chaque tir et toutes les TvChannels.CHECK_S.

const SCREEN_NODE := "Interactif_Ecran_03"
const VIEWPORT_HEIGHT := 640
const DEFAULT_CHANNEL := "FRA"

@export var launcher_path: NodePath = ^"../NukeLauncher"
@export var orbit_path: NodePath = ^"../Orbit"

var _launcher: NukeLauncher
var _orbit: OrbitSimulation
var _channels: TvChannels
var _display: TvDisplay
var _check := 0.0


func _screen_node() -> String:
	return SCREEN_NODE


func _prepare() -> bool:
	_launcher = get_node_or_null(launcher_path) as NukeLauncher
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_channels = TvChannels.new()
	return true


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT, true)


func _create_display(into: SubViewport) -> void:
	_display = TvDisplay.new()
	_display.name = "Display"
	_display.channels = _channels
	_display.channel = DEFAULT_CHANNEL if _channels.has(DEFAULT_CHANNEL) else ""
	_display.size = Vector2(into.size)
	_display.channel_selected.connect(func(code: String) -> void: _display.show_channel(code))
	_channels.changed.connect(func() -> void: _display.refresh())
	into.add_child(_display)
	if _launcher:
		_launcher.detonated.connect(func(effect: NukeEffect) -> void:
			# Explosion recréée (sauvegarde) : l'édition spéciale suit son heure réelle, pas le chargement.
			var at := effect.params.detonation_utc_s if effect.params and effect.params.detonation_utc_s >= 0.0 \
					else _utc_unix()
			_channels.record_detonation(at)
			_update_channels()
			# Nouveau tir : le bandeau repart tout de suite avec le nouveau bilan (après le calcul des pertes).
			_display.restart_ticker.call_deferred())
	_update_channels()


func _scan_depth() -> float:
	return 0.05


func _on_near_changed(near_now: bool) -> void:
	_display.set_playing(near_now)


func _update_screen(delta: float, _near_now: bool) -> void:
	_check += delta
	if _check >= TvChannels.CHECK_S:
		_update_channels()


func _hover_key() -> String:
	return "TV_HOVER"


func _exit_key() -> String:
	return "TV_EXIT_HINT"


## Aperçu du bandeau d'une chaîne (mise au point, MCP / console).
func news_preview(code: String) -> String:
	return _channels.news_preview(code)


func _utc_unix() -> float:
	return _orbit.get_utc_unix_s() if _orbit else -INF


## État des chaînes recalculé d'après les explosions présentes et l'heure du jeu.
func _update_channels() -> void:
	_check = 0.0
	# Sans lanceur (décor du menu de démarrage) : aucune explosion ; le tableau doit rester typé.
	var effects: Array[NukeEffect] = []
	if _launcher:
		effects = _launcher.get_effects()
	_channels.update(effects, _utc_unix())
