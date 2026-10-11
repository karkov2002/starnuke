extends CanvasLayer
## Pause en jeu (nœud PauseMenu de scenes/orbit_view.tscn) : la touche Espace (action pause) fige le jeu
## (SceneTree.paused : orbite, missiles en vol, explosions, animations) et ouvre l'écran des paramètres
## (scenes/ui/settings_menu.tscn) par-dessus la vue, avec le bouton supplémentaire « Retour au menu ». « Retour » (ou
## Échap) ferme l'écran et reprend la partie ; « Retour au menu » revient à l'écran de démarrage (la partie est
## perdue). Ce nœud et l'écran tournent pendant la pause (PROCESS_MODE_ALWAYS). Espace est ignoré pendant la saisie
## d'un champ texte (date du panneau).

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

var _settings: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10


func _unhandled_input(event: InputEvent) -> void:
	if _settings == null and event.is_action_pressed(&"pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		open()


func open() -> void:
	get_tree().paused = true
	_settings = SETTINGS_SCENE.instantiate()
	_settings.set("in_game", true)
	_settings.closed.connect(_resume)
	_settings.main_menu_requested.connect(_back_to_menu)
	add_child(_settings)


func _resume() -> void:
	if _settings:
		_settings.queue_free()
		_settings = null
	get_tree().paused = false


func _back_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
