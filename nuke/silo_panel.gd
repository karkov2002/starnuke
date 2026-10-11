class_name SiloPanel
extends HBoxContainer
## Tubes de lancement de la station sur le panneau de contrôle : un bouton lumineux (SiloButton) par tube, numérotés
## de 1 à 48, groupés par silo (2 blocs de 3 rangées × 8) et placés comme sur la station, vue de dessus, l'avant en
## haut : la disposition est lue dans le modèle (Station.tube_position), rien n'est codé en dur. Les numéros suivent
## l'ordre de lecture du panneau (blocs de gauche à droite, rangées de haut en bas, tubes de gauche à droite), pas les
## numéros des tubes du modèle Blender.
## Clic sur un tube prêt (orange) : il devient le tube choisi (vert) ; nouveau clic : choix annulé. Un seul tube
## choisi à la fois. Un tube tiré (mark_empty) passe au gris et ne se choisit plus.

signal selection_changed(key: Vector2i)

const NONE := Vector2i(-1, -1)

var selected := NONE

## Vector2i(silo, tube) -> SiloButton
var _buttons := {}


## Construit les blocs depuis les tubes de la station.
func setup(station: Station) -> void:
	add_theme_constant_override("separation", 8)
	var tubes := station.tube_ids()
	var by_silo := {}
	for key in tubes:
		if not by_silo.has(key.x):
			by_silo[key.x] = []
		by_silo[key.x].append(key)
	# Repère du modèle : +X vers l'avant (en haut du panneau), +Z vers la droite.
	var silos := by_silo.keys()
	silos.sort_custom(func(a: int, b: int) -> bool:
		return _mean_z(station, by_silo[a]) < _mean_z(station, by_silo[b]))
	for silo: int in silos:
		var keys: Array = by_silo[silo]
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var pa := station.tube_position(a.x, a.y)
			var pb := station.tube_position(b.x, b.y)
			if not is_equal_approx(pa.x, pb.x):
				return pa.x > pb.x
			return pa.z < pb.z)
		var grid := GridContainer.new()
		grid.columns = _distinct_z(station, keys)
		grid.add_theme_constant_override("h_separation", 2)
		grid.add_theme_constant_override("v_separation", 2)
		add_child(grid)
		for key: Vector2i in keys:
			var button := SiloButton.new()
			button.number = _buttons.size() + 1
			button.state = SiloButton.State.READY if station.can_launch(key.x, key.y) else SiloButton.State.EMPTY
			button.pressed.connect(_on_pressed.bind(key))
			grid.add_child(button)
			_buttons[key] = button


## Le tube a tiré : gris, plus de choix possible.
func mark_empty(key: Vector2i) -> void:
	if selected == key:
		_select(NONE)
	if _buttons.has(key):
		_buttons[key].state = SiloButton.State.EMPTY


func _on_pressed(key: Vector2i) -> void:
	_select(NONE if selected == key else key)


func _select(key: Vector2i) -> void:
	if _buttons.has(selected) and _buttons[selected].state == SiloButton.State.ARMED:
		_buttons[selected].state = SiloButton.State.READY
	selected = key
	if _buttons.has(key):
		_buttons[key].state = SiloButton.State.ARMED
	selection_changed.emit(key)


static func _mean_z(station: Station, keys: Array) -> float:
	var total := 0.0
	for key: Vector2i in keys:
		total += station.tube_position(key.x, key.y).z
	return total / maxf(keys.size(), 1.0)


static func _distinct_z(station: Station, keys: Array) -> int:
	var values: Array[float] = []
	for key: Vector2i in keys:
		var z := snappedf(station.tube_position(key.x, key.y).z, 0.01)
		if not values.has(z):
			values.append(z)
	return maxi(values.size(), 1)
