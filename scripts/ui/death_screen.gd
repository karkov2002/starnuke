extends Control
## Écran de mort (scenes/ui/death_screen.tscn), après la séquence de mort (scripts/death_sequence.gd) : « Vous êtes
## mort » et le bouton « Retour au menu » (écran de démarrage) sur fond noir. Le nœud Backdrop (vide pour l'instant)
## accueillera une animation en arrière-plan, comme le décor de l'écran de démarrage. Textes : clés des fichiers de
## langue (DEATH_TITLE, DEATH_BACK_TO_MENU).

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const FADE_IN_S := 1.5


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var backdrop := Control.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 48)
	center.add_child(column)
	column.add_child(UiKit.label("DEATH_TITLE", 72, Color(0.78, 0.08, 0.06), true, HORIZONTAL_ALIGNMENT_CENTER))
	var back := UiKit.menu_button("DEATH_BACK_TO_MENU", func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(back)

	center.modulate.a = 0.0
	create_tween().tween_property(center, "modulate:a", 1.0, FADE_IN_S)
	back.grab_focus()
