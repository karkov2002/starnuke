class_name ScreenSeat
extends RefCounted
## Postes « assis » devant un écran (poste de pilotage, télévision) : chacun est dans le groupe GROUP et expose
## is_seated() et le signal seated_changed(seated). La tablette se range et les écoutilles ne se cliquent plus tant
## que l'un d'eux est occupé.

const GROUP := &"screen_seat"


static func any_seated(tree: SceneTree) -> bool:
	for seat in tree.get_nodes_in_group(GROUP):
		if seat.is_seated():
			return true
	return false
