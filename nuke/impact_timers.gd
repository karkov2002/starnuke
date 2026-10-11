class_name ImpactTimers
extends VBoxContainer
## Chronomètres des missiles en vol (au-dessus du panneau de contrôle, à droite ; créés par nuke/launch_control.gd) :
## une ligne par missile, « Silo 7 · impact dans 0:43 », du tir jusqu'à l'impact, comme le temps de course d'une
## torpille. Les 10 dernières secondes, la ligne passe au rouge et clignote ; à l'impact, « Silo 7 · impact » reste
## affiché IMPACT_HOLD_S puis disparaît. Toujours visibles, même hors de la cupola.

const WARNING_S := 10.0
const IMPACT_HOLD_S := 3.0
const NORMAL_COLOR := Color(1.0, 0.82, 0.55)
const WARNING_COLOR := Color(1.0, 0.25, 0.18)

## Lignes : {label, silo, remaining : Callable → secondes restantes, done_at}
var _lines: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Ajoute un chronomètre : silo = numéro affiché, remaining = secondes restantes avant l'impact (≤ 0 : impact).
func add_timer(silo: int, remaining: Callable) -> void:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	_lines.append({"label": label, "silo": silo, "remaining": remaining, "done_at": -1.0})


func _process(delta: float) -> void:
	_time += delta
	for line in _lines.duplicate():
		var label: Label = line.label
		var left: float = line.remaining.call()
		if left <= 0.0:
			if line.done_at < 0.0:
				line.done_at = _time
				label.text = tr("HUD_IMPACT_NOW").format({"silo": line.silo})
				label.add_theme_color_override("font_color", WARNING_COLOR)
				label.modulate.a = 1.0
			elif _time - line.done_at > IMPACT_HOLD_S:
				label.queue_free()
				_lines.erase(line)
			continue
		var seconds := ceili(left)
		@warning_ignore("integer_division")
		var clock := "%d:%02d" % [seconds / 60, seconds % 60]
		label.text = tr("HUD_IMPACT_TIMER").format({"silo": line.silo, "time": clock})
		var warning := left <= WARNING_S
		label.add_theme_color_override("font_color", WARNING_COLOR if warning else NORMAL_COLOR)
		# Clignotement des 10 dernières secondes : deux éclats par seconde.
		label.modulate.a = (0.35 if fmod(_time, 0.5) > 0.3 else 1.0) if warning else 1.0
