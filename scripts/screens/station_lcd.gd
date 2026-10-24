class_name StationLcd
extends Node
## Base des afficheurs muraux à cristaux liquides de la station (modèle : tools/blender/build_station_clock.py) :
## toutes les dalles des objets dont le nom commence par mesh_prefix() partagent un seul SubViewport 2D (même
## affichage partout), redessiné seulement quand le contenu (_content(), une chaîne) change, au plus refresh_hz fois
## par seconde. Éteints avec « plus de lumière » (Station.get_blackout). Sous-classes : StationClocks (date et heure
## UTC), StationPosition (latitude et longitude de la station). Dessin : SegmentDisplay.

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var orbit_path: NodePath = ^"../Orbit"
@export var screen_energy := 1.2
@export var refresh_hz := 10.0

var _station: Station
var _orbit: OrbitSimulation
var _viewport: SubViewport
var _canvas: LcdCanvas
var _screens: Array[StationScreen] = []
var _shown := ""
var _since := INF


## Préfixe des objets du modèle (ex. « Interactif_Horloge_ »).
func mesh_prefix() -> String:
	return ""


## Contenu à afficher, résumé en une chaîne : le dessin n'est refait que s'il change.
func _content() -> String:
	return ""


## Dessin de l'affichage sur canvas (fond déjà effacé) ; content : la chaîne de _content().
func _paint(_canvas_item: CanvasItem, _content_text: String) -> void:
	pass


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	if _station == null or _orbit == null:
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "Lcd"
	_viewport.size = SegmentDisplay.SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_canvas = LcdCanvas.new()
	_canvas.size = Vector2(SegmentDisplay.SIZE)
	_canvas.painter = _paint
	_viewport.add_child(_canvas)
	for mesh: MeshInstance3D in _station.find_children(mesh_prefix() + "*", "MeshInstance3D", true, false):
		var screen := StationScreen.find(_station, mesh.name)
		if screen == null:
			continue
		screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(),
				{"energy": screen_energy, "scan_depth": 0.0})
		_screens.append(screen)
	if _screens.is_empty():
		push_error("%s : aucun afficheur (%s*) dans le modèle de la station" % [name, mesh_prefix()])
		set_process(false)


func _process(delta: float) -> void:
	var energy := screen_energy * (1.0 - _station.get_blackout())
	for screen in _screens:
		screen.set_energy(energy)
	_since += delta
	if _since < 1.0 / refresh_hz:
		return
	var content := _content()
	if content == _shown:
		return
	_since = 0.0
	_shown = content
	_canvas.content = content
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


class LcdCanvas:
	extends Control

	var painter: Callable
	var content := ""

	func _draw() -> void:
		SegmentDisplay.clear(self)
		if not content.is_empty():
			painter.call(self, content)
