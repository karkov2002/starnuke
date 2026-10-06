extends VBoxContainer
## Colonne « missile » du panneau de debug : gros bouton rouge de tir et, en dessous, choix de la puissance.
## Le tir vise le centre de la vue (cf. NukeLauncher) ; s'il ne vise pas la Terre, rien ne se passe.

@export var default_yield_kt := 1000.0

var _yield_kt := 1000.0


func _ready() -> void:
	_yield_kt = default_yield_kt
	add_theme_constant_override("separation", 4)

	var button := BigRedButton.new()
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = "Lancer un missile sur le point visé (centre de la vue)"
	button.pressed.connect(_on_fire)
	add_child(button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var group := ButtonGroup.new()
	for kt: float in NukeLauncher.YIELDS_KT:
		var choice := Button.new()
		choice.text = NukeLauncher.format_yield(kt)
		choice.toggle_mode = true
		choice.button_group = group
		choice.focus_mode = Control.FOCUS_NONE
		choice.custom_minimum_size.x = 56.0
		choice.button_pressed = is_equal_approx(kt, _yield_kt)
		choice.pressed.connect(func() -> void: _yield_kt = kt)
		row.add_child(choice)


func _on_fire() -> void:
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if launcher:
		launcher.launch(_yield_kt)
