class_name CommConsole
extends ScreenSeatConsole
## Écran de communication radio du module Commande (nœud CommConsole de scenes/orbit_view.tscn) : l'écran SCREEN_NODE
## (retiré des écrans d'ambiance TechScreens) affiche le programme COMM.EXE (CommDisplay, dans un SubViewport), façade
## de la radio de la station (RadioComms : canaux, liaison, messages). Survol, vue radio, souris transmise à
## l'interface, clic droit pour quitter, garde de distance : ScreenSeatConsole. Propre à la radio : le clavier va
## aussi à l'interface (touches de fonction, flèches, chiffres, Entrée ; F10 quitte la vue), et s'installer devant
## l'écran marque le message affiché comme lu.

const SCREEN_NODE := "Interactif_Ecran_08"
const VIEWPORT_HEIGHT := 600

@export var radio_path: NodePath = ^"../Radio"

var _radio: RadioComms
var _display: CommDisplay


func _screen_node() -> String:
	return SCREEN_NODE


func _prepare() -> bool:
	_radio = get_node_or_null(radio_path) as RadioComms
	return _radio != null


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT)


func _create_display(into: SubViewport) -> void:
	_display = CommDisplay.new()
	_display.name = "Display"
	_display.radio = _radio
	_display.size = Vector2(into.size)
	_display.quit_requested.connect(stand_up)
	into.add_child(_display)


func _scan_depth() -> float:
	return 0.08


func _on_near_changed(near_now: bool) -> void:
	_display.set_process(near_now)


func _hover_key() -> String:
	return "COMM_HOVER"


func _exit_key() -> String:
	return "COMM_EXIT_HINT"


func _on_seated() -> void:
	_display.mark_shown()


func _handle_key(key: InputEventKey) -> bool:
	return _display.handle_key(key)
