class_name PilotConsole
extends ScreenSeatConsole
## Poste de pilotage du module Commande (nœud PilotConsole de scenes/orbit_view.tscn). Le grand écran de la console
## (Interactif_Ecran_Principal, dalle au matériau Ecran_15) affiche l'interface de pilotage orbital (PilotDisplay,
## dessinée dans un SubViewport, shaders/pilot_screen.gdshader). Survol, vue assise, souris transmise à l'interface,
## clic droit pour quitter, garde de distance : ScreenSeatConsole. Propre au poste : la dalle est mesurée par la
## normale de ses faces (ses UV sont inexploitables), le shader reçoit le rectangle de la dalle, la luminosité suit
## l'émission d'origine du matériau Ecran_15 ; au poste le temps repasse à ×1 (les manœuvres se jouent en temps réel)
## et quitter le poste relâche BURN.

const SCREEN_NODE := "Interactif_Ecran_Principal"
const SCREEN_MATERIAL := "Ecran_15"
const SCREEN_SHADER := preload("res://shaders/pilot_screen.gdshader")
## Hauteur de l'image de l'interface (pixels) ; la largeur suit les proportions de la dalle.
const VIEWPORT_HEIGHT := 1000

@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"

var _orbit: OrbitSimulation
var _flight_computer: FlightComputer
var _display: PilotDisplay
## Luminosité fixe de l'écran : émission d'origine du matériau × screen_energy.
var _base_energy := 1.0


func _init() -> void:
	screen_energy = 1.0


func _screen_node() -> String:
	return SCREEN_NODE


func _prepare() -> bool:
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_flight_computer = get_node_or_null(flight_computer_path) as FlightComputer
	return _orbit != null and _flight_computer != null


## Dalle : faces du matériau Ecran_15 tournées vers l'observateur (normale −X du maillage ; ses UV ne servent pas).
func _find_screen() -> StationScreen:
	var mesh := _station.find_child(SCREEN_NODE, true, false) as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return null
	var screen := StationScreen.new()
	screen.mesh_instance = mesh
	return screen if screen.measure_by_normal(SCREEN_MATERIAL, Vector3.LEFT) else null


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT, true)


func _create_display(into: SubViewport) -> void:
	_display = PilotDisplay.new()
	_display.size = Vector2(into.size)
	_display.orbit = _orbit
	_display.flight_computer = _flight_computer
	into.add_child(_display)


func _apply_material() -> void:
	_base_energy = _screen.base_emission() * screen_energy
	_screen.apply_shader(SCREEN_SHADER, _viewport.get_texture(), {"top_left": _screen.top_left,
			"axis_u": _screen.axis_u, "axis_v": _screen.axis_v, "energy": _base_energy})


func _energy() -> float:
	return _base_energy


func _on_near_changed(near_now: bool) -> void:
	_display.set_process(near_now)


func _hover_key() -> String:
	return "PILOT_HOVER"


func _exit_key() -> String:
	return "PILOT_EXIT_HINT"


func _on_seated() -> void:
	_orbit.time_scale = 1.0


func _on_stood_up() -> void:
	_flight_computer.end_burn()
