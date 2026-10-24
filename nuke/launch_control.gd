class_name LaunchControl
extends HBoxContainer
## Commande de tir de la tablette (scripts/ui/tablet_display.gd) : à gauche les 48 tubes de lancement (SiloPanel) et,
## en dessous, le choix de la puissance ; à droite le gros bouton rouge de tir. On ne tire que depuis la cupola
## (Station.is_in_cupola, là où le réticule est affiché) : ailleurs, le bouton rouge est grisé, avec « Actif uniquement
## dans la coupole » écrit dessus.
##
## Tir : on choisit un tube (vert) puis on appuie sur le bouton rouge ; le tube choisi a sa trappe ouverte et son
## gyrophare allumé. La séquence elle-même (point visé et puissance figés, sortie du missile par l'animation de la
## station, vol vers la cible, explosion à l'arrivée, durée du vol) est LaunchSequencer ; ici : le tube passe au gris
## (vide) et un chronomètre par missile (ImpactTimers) décompte jusqu'à l'impact.

@export var default_yield_kt := 1000.0
## Boutons de puissance réduits (tablette) : petits caractères, sans largeur minimale. Fixé avant l'ajout à l'arbre.
## (À terme, chaque silo aura sa bombe et sa puissance : ce choix disparaîtra.)
var compact_yields := false
## Durée du vol (s, temps de jeu) : visée au nadir, visée à l'horizon (LaunchSequencer.flight_time_range).
@export var flight_time_range := Vector2(20.0, 120.0)

var _yield_kt := 1000.0
var _silos: SiloPanel
var _station: Station
var _sequencer: LaunchSequencer
## Tube choisi (vert) : trappe ouverte, gyrophare allumé.
var _armed := SiloPanel.NONE
var _timers: ImpactTimers
var _button: BigRedButton
## Raison du refus affichée sur le bouton (clé de langue ; "" : tir permis).
var _refusal := "-"


func _ready() -> void:
	_yield_kt = default_yield_kt
	_timers = ImpactTimers.new()
	_timers.name = "ImpactTimers"
	_add_timers.call_deferred()
	add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	_silos = SiloPanel.new()
	_silos.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(_silos)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	left.add_child(row)
	var group := ButtonGroup.new()
	for kt: float in NukeLauncher.YIELDS_KT:
		var choice := Button.new()
		choice.text = NukeScaling.format_yield(kt)
		choice.toggle_mode = true
		choice.button_group = group
		choice.focus_mode = Control.FOCUS_NONE
		choice.button_pressed = is_equal_approx(kt, _yield_kt)
		choice.pressed.connect(func() -> void: _yield_kt = kt)
		row.add_child(choice)
		if compact_yields:
			# Styles du thème hérité (lus une fois le bouton dans l'arbre), marges réduites.
			choice.add_theme_font_size_override("font_size", 10)
			for state: String in ["normal", "hover", "pressed", "disabled"]:
				var box := choice.get_theme_stylebox(state).duplicate() as StyleBox
				box.content_margin_left = 4.0
				box.content_margin_right = 4.0
				box.content_margin_top = 1.0
				box.content_margin_bottom = 1.0
				choice.add_theme_stylebox_override(state, box)
		else:
			choice.custom_minimum_size.x = 56.0

	_button = BigRedButton.new()
	_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button.tooltip_text = "HUD_LAUNCH_TOOLTIP"
	_button.pressed.connect(_on_fire)
	add_child(_button)

	# La station peut être prête après ce panneau (ordre de l'arbre) : construction différée.
	_connect_station.call_deferred()


## Bouton rouge actif seulement dans la cupola et quand le point visé est dans le cône de tir (FiringCone) ; sinon
## grisé, avec la raison écrite dessus : « Actif uniquement dans la coupole », cible hors du cône, hors de portée.
func _process(_delta: float) -> void:
	var key := _refusal_key()
	if key == _refusal:
		return
	_refusal = key
	_button.disabled = not key.is_empty()
	_button.disabled_message = tr(key) if not key.is_empty() else ""
	_button.tooltip_text = key if not key.is_empty() else "HUD_LAUNCH_TOOLTIP"


## Raison du refus de tir (clé de langue ; "" : tir permis).
func _refusal_key() -> String:
	var camera := get_tree().root.get_camera_3d()
	if _station and camera and not _station.is_in_cupola(camera.global_position):
		return "LAUNCH_CUPOLA_ONLY"
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	return FiringCone.refusal_key(FiringCone.aim_status(launcher.get_aim())) if launcher else ""


## Chronomètres en bas à droite de l'écran, dans l'interface à l'écran (Hud ; à défaut, la couche d'interface du
## panneau ou la scène).
func _add_timers() -> void:
	var layer: Node = get_tree().get_first_node_in_group(Hud.GROUP)
	if layer == null:
		layer = get_parent()
		while layer and not layer is CanvasLayer:
			layer = layer.get_parent()
	(layer if layer else get_tree().current_scene).add_child(_timers)
	_timers.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_timers.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_timers.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_timers.offset_right = -40.0
	_timers.offset_bottom = -40.0


## Station et lanceur résolus une fois ; la séquence de tir s'abonne à la station.
func _connect_station() -> void:
	_station = get_tree().get_first_node_in_group(Station.GROUP) as Station
	if _station == null:
		return
	_silos.setup(_station)
	_silos.selection_changed.connect(_on_selection_changed)
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	_sequencer = LaunchSequencer.new(_station, launcher, get_tree().root, get_tree().current_scene)
	_sequencer.flight_time_range = flight_time_range


## Tube choisi : sa trappe s'ouvre (animation Blender) et son gyrophare clignote ; le tube choisi auparavant (s'il n'a
## pas tiré) referme sa trappe et éteint son gyrophare.
func _on_selection_changed(key: Vector2i) -> void:
	if _armed != SiloPanel.NONE and not (_sequencer and _sequencer.is_pending(_armed)):
		_station.close_silo_door(_armed.x, _armed.y)
		_station.set_silo_beacon(_armed.x, _armed.y, false)
	_armed = key
	if key != SiloPanel.NONE:
		_station.open_silo_door(key.x, key.y)
		_station.set_silo_beacon(key.x, key.y, true)


func _on_fire() -> void:
	if not _refusal_key().is_empty():
		return
	var launcher := get_tree().get_first_node_in_group(NukeLauncher.GROUP) as NukeLauncher
	if launcher:
		fire_tube(_silos.selected, launcher.get_aim(), _yield_kt)


## Tire le missile du tube key sur le point aim avec la puissance yield_kt (LaunchSequencer.fire_tube) ; le tube
## passe au gris et son chronomètre démarre. Faux (et rien ne se passe) si le tir est refusé. Aussi utilisé par le
## banc de mesure (tools/bench).
func fire_tube(key: Vector2i, aim: Dictionary, yield_kt: float) -> bool:
	if _sequencer == null:
		return false
	var shot := _sequencer.fire_tube(key, aim, yield_kt)
	if shot.is_empty():
		return false
	_silos.mark_empty(key)
	_timers.add_timer(_silos.number_of(key), func() -> float: return _sequencer.time_left(shot))
	return true
