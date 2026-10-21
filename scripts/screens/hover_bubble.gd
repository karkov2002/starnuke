class_name HoverBubble
extends CanvasLayer
## Bulles d'aide des objets cliquables (écrans, écoutilles, sas) : une bulle de survol qui suit le curseur (clé de
## langue changeable) et, pour les écrans à vue « assise », une indication de sortie en bas de la vue. Masquées en
## pause et quand le nœud est désactivé (sinon elles restaient figées par-dessus le menu). Même style pour toutes.

var _hover: Label
var _exit: Label


## hover_key : texte de la bulle de survol ; exit_key : indication de sortie ("" : aucune).
func _init(hover_key: String, exit_key := "") -> void:
	layer = 5
	_hover = _make_label(hover_key)
	add_child(_hover)
	if not exit_key.is_empty():
		_exit = _make_label(exit_key)
		_exit.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
		_exit.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_exit.grow_vertical = Control.GROW_DIRECTION_BEGIN
		add_child(_exit)


func _notification(what: int) -> void:
	if (what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED) and _hover:
		_hover.visible = false
		if _exit:
			_exit.visible = false


## Bulle de survol affichée (au curseur, à position) ou masquée.
func set_hover(shown: bool, position := Vector2.ZERO) -> void:
	_hover.visible = shown
	if shown:
		_hover.position = position + Vector2(18, 14)
		_hover.reset_size()


## Texte (clé de langue) de la bulle de survol.
func set_hover_text(key: String) -> void:
	_hover.text = key


func set_exit_visible(shown: bool) -> void:
	if _exit:
		_exit.visible = shown


static func _make_label(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_stylebox_override("normal", bubble_style())
	label.visible = false
	return label


## Style des bulles : fond sombre translucide, liseré bleuté (comme les panneaux du Hud, plus opaque).
static func bubble_style() -> StyleBoxFlat:
	return UiKit.flat_box(Color(0.05, 0.07, 0.1, 0.8), Color(0.55, 0.7, 0.9, 0.5), 1, 6, 8.0)
