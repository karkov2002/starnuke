class_name ScreenSeat
extends RefCounted
## Postes « assis » devant un écran (poste de pilotage, télévision) : chacun est dans le groupe GROUP et expose
## is_seated() et le signal seated_changed(seated). La tablette se range et les écoutilles ne se cliquent plus tant
## que l'un d'eux est occupé.

const GROUP := &"screen_seat"


## Souris sur l'écran d'un SubViewport affiché comme texture (poste, télévision, tablette) : un tel viewport ne reçoit
## jamais l'entrée de la souris de lui-même, et sans elle Godot ne lui donne que les clics et les glisser, pas le simple
## survol (coordonnées sous le pointeur de la carte, survol des boutons). Envoie l'entrée ou la sortie quand l'état
## change ; rend le nouvel état.
static func set_mouse_inside(viewport: Viewport, inside: bool, was_inside: bool) -> bool:
	if viewport and inside != was_inside:
		viewport.notification(Node.NOTIFICATION_VP_MOUSE_ENTER if inside else Node.NOTIFICATION_VP_MOUSE_EXIT)
	return inside


static func any_seated(tree: SceneTree) -> bool:
	for seat in tree.get_nodes_in_group(GROUP):
		if seat.is_seated():
			return true
	return false
