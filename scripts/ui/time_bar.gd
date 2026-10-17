class_name TimeBar
extends PanelContainer
## Barre de vitesse du temps, toujours visible en haut au centre de l'écran (créée par Hud, scripts/ui/hud.gd) :
## pause puis ×1, ×2, ×4, ×8, ×16, en icônes dessinées (deux barres pour la pause, puis 1 à 5 flèches) ; le bouton
## de la vitesse en cours est allumé, l'infobulle donne le facteur. Agit sur Orbit.time_scale (et suit ses changements :
## le poste de pilotage et le BURN ramènent le temps à ×1).

const TIME_SCALES := [0.0, 1.0, 2.0, 4.0, 8.0, 16.0]
const ICON_COLOR := Color(0.85, 0.92, 1.0)
const ACTIVE_COLOR := Color(0.45, 0.85, 1.0)

var orbit: OrbitSimulation

var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var group := ButtonGroup.new()
	for index in TIME_SCALES.size():
		var factor: float = TIME_SCALES[index]
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(46.0 + 9.0 * maxi(index - 1, 0), 30.0)
		if factor == 0.0:
			button.tooltip_text = "HUD_PAUSE"
		else:
			button.tooltip_text = tr("HUD_SPEED_TOOLTIP").format({"factor": int(factor)})
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.pressed.connect(func() -> void: orbit.time_scale = factor)
		button.draw.connect(_draw_icon.bind(button, index))
		row.add_child(button)
		_buttons.append(button)


func _process(_delta: float) -> void:
	if orbit == null:
		return
	for index in TIME_SCALES.size():
		var pressed := is_equal_approx(orbit.time_scale, TIME_SCALES[index])
		if _buttons[index].button_pressed != pressed:
			_buttons[index].set_pressed_no_signal(pressed)
			_buttons[index].queue_redraw()


## Icône : deux barres (pause) ou index flèches pleines (×1 à ×16), centrées dans le bouton.
func _draw_icon(button: Button, index: int) -> void:
	var color := ACTIVE_COLOR if button.button_pressed else ICON_COLOR
	var center := button.size * 0.5
	var h := 7.0
	if index == 0:
		for x: float in [-4.0, 2.0]:
			button.draw_rect(Rect2(center.x + x, center.y - h, 3.0, 2.0 * h), color)
		return
	var step := 9.0
	var start := center.x - step * index * 0.5
	for k in index:
		var x := start + k * step
		button.draw_colored_polygon(PackedVector2Array([Vector2(x, center.y - h), Vector2(x + 10.0, center.y),
				Vector2(x, center.y + h)]), color)
