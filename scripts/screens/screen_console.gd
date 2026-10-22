class_name ScreenConsole
extends Node
## Écran de la station piloté par un nœud de la scène : la dalle (StationScreen) d'un écran du modèle reçoit l'image
## d'un SubViewport où la sous-classe dessine son interface. La base tient ce que ces écrans partagent : résolution
## de la station et de la dalle, viewport, matériau d'affichage, luminosité (éteint avec « plus de lumière »,
## Station.get_blackout, envoyée au shader seulement si elle change) et garde de distance : à plus de RENDER_DISTANCE
## entre la caméra et le centre de la dalle, l'image n'est plus rendue et la sous-classe en est avertie
## (_on_near_changed) pour suspendre son interface.
## Sous-classes : NukeReportPanel (écran mural, sans interaction) et, par ScreenSeatConsole (vue « assise », souris
## transmise à l'écran), PilotConsole, CommConsole et TvConsole.
##
## Crochets, dans l'ordre d'appel de _ready : _prepare (dépendances propres ; faux = écran inactif), _find_screen
## (par défaut StationScreen.find sur _screen_node()), _make_viewport, _create_display (interface posée dans le
## viewport), _apply_material (par défaut shader des écrans d'ambiance, lignes de balayage _scan_depth()). Par image :
## _energy (luminosité voulue), _on_near_changed (sur changement), _update_screen.

## Au-delà de cette distance (m) entre la caméra et le centre de la dalle, l'image n'est plus rendue.
const RENDER_DISTANCE := 12.0

@export var station_path: NodePath = ^"../Station/StationSpatiale"
## Luminosité de l'écran (paramètre energy du shader d'affichage).
@export var screen_energy := 1.1

var _station: Station
var _screen: StationScreen
var _viewport: SubViewport
## Caméra à portée de rendu (état appliqué au viewport ; vrai au départ : le viewport est créé rendu).
var _near := true


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	if _station == null or not _prepare():
		_fail("station ou dépendance introuvable")
		return
	_screen = _find_screen()
	if _screen == null:
		_fail("écran %s (ou sa dalle) introuvable" % _screen_node())
		return
	_viewport = _make_viewport()
	add_child(_viewport)
	_create_display(_viewport)
	_apply_material()


func _process(delta: float) -> void:
	_screen.set_energy(_energy())
	var camera := get_viewport().get_camera_3d()
	var near := camera != null and _screen.distance_to(camera.global_position) < RENDER_DISTANCE
	if near != _near:
		_near = near
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if near else SubViewport.UPDATE_DISABLED
		_on_near_changed(near)
	_update_screen(delta, near)


## Caméra à moins de RENDER_DISTANCE de la dalle : image rendue.
func is_near() -> bool:
	return _near


## Écran inactif (dépendance ou dalle manquante) : erreur signalée, plus aucun traitement.
func _fail(why: String) -> void:
	push_error("%s : %s" % [(get_script() as Script).get_global_name(), why])
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)


# --- Crochets ---------------------------------------------------------------------------------------------------------

## Nom du nœud de l'écran dans le modèle (Interactif_Ecran_*).
func _screen_node() -> String:
	return ""


## Dépendances propres à la sous-classe, résolues avant la dalle ; faux si l'une manque.
func _prepare() -> bool:
	return true


## Dalle de l'écran ; null si introuvable ou non mesurable.
func _find_screen() -> StationScreen:
	return StationScreen.find(_station, _screen_node())


## SubViewport de l'image (en général _screen.make_viewport(hauteur)).
func _make_viewport() -> SubViewport:
	return _screen.make_viewport(600)


## Interface de l'écran, ajoutée au viewport.
func _create_display(_into: SubViewport) -> void:
	pass


## Matériau d'affichage posé sur la dalle.
func _apply_material() -> void:
	_screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(), {"scan_depth": _scan_depth()})


## Profondeur des lignes de balayage du shader des écrans d'ambiance.
func _scan_depth() -> float:
	return 0.06


## Luminosité voulue à cette image.
func _energy() -> float:
	return screen_energy * (1.0 - _station.get_blackout())


## La caméra entre à portée de rendu (near) ou en sort : suspendre ou reprendre l'interface.
func _on_near_changed(_near_now: bool) -> void:
	pass


## Traitement par image de la sous-classe, après la garde de distance.
func _update_screen(_delta: float, _near_now: bool) -> void:
	pass
