class_name ScreenInputForwarder
extends RefCounted
## Transfert de la souris vers un SubViewport affiché comme texture sur une dalle (consoles, tablette) : l'événement
## est copié à la position correspondante de l'image. Un tel viewport ne reçoit jamais l'entrée de la souris de
## lui-même, et sans elle Godot ne lui donne que les clics et les glisser, pas le simple survol : l'entrée et la sortie
## du pointeur lui sont notifiées quand l'état change (survol des boutons, coordonnées sous le pointeur de la carte).
## Bouton gauche tenu après un clic sur l'écran (pressing) : son relâchement est transmis même hors de la dalle, au
## dernier point touché, sinon un bouton maintenu (BURN) ou un curseur resterait tenu.

var viewport: SubViewport
var mouse_inside := false
var pressing := false
var last_uv := Vector2(0.5, 0.5)


func _init(target: SubViewport) -> void:
	viewport = target


## Transmet l'événement souris au point uv (0–1) de l'écran ; uv = StationScreen.NONE : pointeur hors de la dalle
## (sortie notifiée), seul un relâchement du bouton gauche tenu est transmis. Rend vrai si l'événement a été transmis.
func forward(mouse: InputEventMouse, uv: Vector2) -> bool:
	var button := mouse as InputEventMouseButton
	if uv == StationScreen.NONE:
		set_inside(false)
		if not (pressing and button and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed):
			return false
		uv = last_uv
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		pressing = button.pressed
	set_inside(true)
	last_uv = uv
	var forwarded := mouse.duplicate() as InputEventMouse
	forwarded.position = uv * Vector2(viewport.size)
	forwarded.global_position = forwarded.position
	viewport.push_input(forwarded)
	return true


## Entrée ou sortie du pointeur, notifiée au viewport quand l'état change.
func set_inside(inside: bool) -> void:
	if viewport and inside != mouse_inside:
		viewport.notification(Node.NOTIFICATION_VP_MOUSE_ENTER if inside else Node.NOTIFICATION_VP_MOUSE_EXIT)
	mouse_inside = inside


## Le pointeur quitte l'écran (on se lève, la tablette se range).
func leave() -> void:
	set_inside(false)
	pressing = false
