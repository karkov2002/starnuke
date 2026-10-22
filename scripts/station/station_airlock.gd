class_name StationAirlock
extends RefCounted
## Sas de sortie (composant de Station, scripts/station.gd, qui garde les signaux suit_changed, airlock_changed et
## les réglages exportés) : combinaison (clic : on l'enfile, elle disparaît ; clic sur son support : elle y revient)
## et valve de dépressurisation (animation Blender extras.animation, Depressurisation_Sas : la manette s'ouvre
## (début), l'aiguille du manomètre descend de 1 à 0 bar (courbe de vidange)). La valve est un robinet (vidange,
## remplissage, fermée) ; les pressions sont calculées par StationAtmosphere (scripts/station_atmosphere.gd), qui fait
## suivre la pression du sas à l'aiguille (set_gauge). Voyants : vert allumé sas plein, rouge allumé sas vide ;
## pendant un cycle, le vert s'éteint et le rouge clignote. Aucun verrouillage : la sécurité est l'affaire du joueur
## (conséquences : scripts/airlock_hazard.gd).

## Valve du sas (objet Interactif_* d'extras type « valve_sas ») : pistes de rotation de son animation (manette,
## aiguille), courbe de l'aiguille, robinet et voyants.
class Valve:
	var node: MeshInstance3D
	var anim: Animation
	var tracks: Array[int] = []
	var targets: Array[Node3D] = []
	## Rotation cumulée de l'aiguille le long de l'animation (241 échantillons), piste de l'aiguille.
	var curve := PackedFloat32Array()
	var needle := -1
	## Descente de l'aiguille : t0 (manette ouverte) – t1 (sas vide, avant que la manette se referme).
	var t0 := 0.0
	var t1 := 20.0
	## Sens du robinet : −1 vidange, +1 remplissage, 0 fermée.
	var mode := 0
	var pressure := 1.0
	## Manette : 0 fermée, 1 ouverte.
	var lever := 0.0
	var lever_tween: Tween
	var green: BaseMaterial3D
	var red: BaseMaterial3D

var _station: Station
var _suit: Node3D
var _suit_rack: Node3D
var _suit_worn := false
var _valve: Valve
var _indicator_time := 0.0


func _init(station: Station, anim: StationAnim) -> void:
	_station = station
	for node: MeshInstance3D in station.find_children("Interactif_*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta("extras", {})
		match String(extras.get("type", "")):
			"combinaison":
				_suit = node
			"porte_combinaison":
				_suit_rack = node
			"valve_sas":
				_setup_valve(node, extras, anim)


func is_suit_worn() -> bool:
	return _suit_worn


## Enfile (combinaison masquée, sans collision) ou range la combinaison. Faux sans combinaison dans le modèle.
func set_suit_worn(worn: bool) -> bool:
	if _suit == null:
		return false
	if worn == _suit_worn:
		return true
	_suit_worn = worn
	_suit.visible = not worn
	for body: CollisionObject3D in _suit.find_children("*", "CollisionObject3D", true, false):
		body.process_mode = Node.PROCESS_MODE_DISABLED if worn else Node.PROCESS_MODE_INHERIT
	_station.suit_changed.emit(worn)
	return true


## Pièce du sas à laquelle appartient node, quand un clic y a un effet : « combinaison » (à enfiler), « porte » (le
## support, pour la ranger), « valve » ; "" sinon.
func part_for(node: Node) -> String:
	while node and node != _station:
		if node == _suit:
			return "" if _suit_worn else "combinaison"
		if node == _suit_rack:
			return "porte" if _suit_worn else ""
		if _valve and node == _valve.node:
			return "valve"
		node = node.get_parent()
	return ""


## Pression du sas (1 : plein, 0 : vide), affichée par l'aiguille du manomètre (calculée par StationAtmosphere).
func pressure() -> float:
	return _valve.pressure if _valve else 1.0


func is_cycling() -> bool:
	return valve_mode() != 0


## Sens de la valve : −1 vidange, +1 remplissage, 0 fermée.
func valve_mode() -> int:
	return _valve.mode if _valve else 0


## État visé de la valve : vrai si elle remplit, ou si, fermée, le sas est plutôt plein.
func is_filling() -> bool:
	var mode := valve_mode()
	return mode > 0 or (mode == 0 and pressure() >= 0.5)


## Ouvre la valve pour remplir (full) ou vider le sas, et avec lui tout ce qui communique avec lui
## (StationAtmosphere) ; elle se referme d'elle-même une fois la pression visée atteinte. Une demande inverse pendant
## un cycle l'inverse. Faux sans valve dans le modèle.
func set_pressurized(full: bool) -> bool:
	if _valve == null:
		return false
	var p := pressure()
	if (full and p >= 0.998) or (not full and p <= 0.002):
		_valve.mode = 0
		_move_lever(0.0)
		return true
	_valve.mode = 1 if full else -1
	_move_lever(1.0)
	return true


func toggle_pressure() -> bool:
	return set_pressurized(not is_filling())


## Durée (s) d'une vidange complète du sas seul par la valve (descente de l'aiguille dans l'animation).
func valve_s() -> float:
	return maxf(_valve.t1 - _valve.t0, 0.01) if _valve else 20.0


## Pression après seconds de vidange du sas seul par la valve (seconds < 0 : remplissage), sur la courbe du manomètre
## (exponentielle adoucie : plus rapide aux faibles pressions qu'une exponentielle pure).
func step(p: float, seconds: float) -> float:
	if _valve == null:
		return clampf(p - seconds / 20.0, 0.0, 1.0)
	var t := clampf(_time_for(p, seconds < 0.0) + seconds, _valve.t0, _valve.t1)
	return _pressure_at(t)


## Pression du sas (StationAtmosphere, à chaque image) : aiguille du manomètre, fin de cycle de la valve.
func set_gauge(p: float) -> void:
	if _valve == null:
		return
	_valve.pressure = p
	var node := _valve.targets[_valve.tracks.find(_valve.needle)]
	if node:
		StationAnim.apply_track(_valve.anim, _valve.needle, node, _time_for(p, false))
	var mode := _valve.mode
	if (mode < 0 and p <= 0.002) or (mode > 0 and p >= 0.998):
		_valve.mode = 0
		_move_lever(0.0)
		_station.airlock_changed.emit(mode > 0)


## Voyants, à chaque image.
func update(delta: float) -> void:
	if _valve == null:
		return
	var blink_s := _station.indicator_blink_s
	_indicator_time = fmod(_indicator_time + delta, blink_s)
	var p := pressure()
	var cycling := is_cycling()
	var blink := _indicator_time < blink_s * 0.5
	var energy := _station.indicator_energy
	if _valve.green:
		_valve.green.emission_energy_multiplier = energy if not cycling and p >= 0.99 else 0.0
	if _valve.red:
		_valve.red.emission_energy_multiplier = energy if (cycling and blink) or (not cycling and p <= 0.01) else 0.0


## Manette : 0 fermée (début de l'animation), 1 ouverte (quand l'aiguille commence à descendre), à la vitesse de
## l'animation.
func _move_lever(open: float) -> void:
	if _valve.lever_tween:
		_valve.lever_tween.kill()
	var t0 := _valve.t0
	var duration := absf(open - _valve.lever) * t0
	if duration <= 0.0:
		return
	_valve.lever_tween = _station.create_tween()
	_valve.lever_tween.tween_method(func(u: float) -> void:
		_valve.lever = u
		for i in _valve.tracks.size():
			if _valve.tracks[i] != _valve.needle and _valve.targets[i]:
				StationAnim.apply_track(_valve.anim, _valve.tracks[i], _valve.targets[i], u * t0), _valve.lever, open, duration)


## Pression au temps time de l'animation : 1 − rotation cumulée de l'aiguille / rotation totale. L'aiguille est la
## piste qui tourne le plus (225°, la manette 90°) ; rotation cumulée par petits pas (sans ambiguïté de signe).
func _pressure_at(time: float) -> float:
	var curve := _valve.curve
	var last := curve.size() - 1
	if last < 1 or curve[last] <= 0.0:
		return 1.0
	var x := clampf(time / _valve.anim.length, 0.0, 1.0) * last
	var i := mini(int(x), last - 1)
	return 1.0 - lerpf(curve[i], curve[i + 1], x - i) / curve[last]


## Temps de l'animation où l'aiguille indique p (réciproque de _pressure_at), dans sa descente (t0–t1) : au début
## (early, sens du remplissage) ou à la fin des paliers.
func _time_for(p: float, early: bool) -> float:
	var curve := _valve.curve
	var last := curve.size() - 1
	if last < 1 or curve[last] <= 0.0:
		return 0.0
	var c := (1.0 - clampf(p, 0.0, 1.0)) * curve[last]
	# Segment [i, i + 1] qui contient c (curve[i] ≤ c), au début (early) ou à la fin d'un palier.
	var i := curve.bsearch(c, early)
	if i > last or curve[i] > c:
		i -= 1
	i = clampi(i, 0, last)
	var x := float(i)
	if i < last and curve[i + 1] > curve[i] and c > curve[i]:
		x += minf((c - curve[i]) / (curve[i + 1] - curve[i]), 1.0)
	return clampf(x / last * _valve.anim.length, _valve.t0, _valve.t1)


func _setup_valve(node: MeshInstance3D, extras: Dictionary, anim: StationAnim) -> void:
	var animation := anim.animation(StringName(String(extras.get("animation", ""))))
	if animation == null:
		push_error("Station : animation %s de la valve absente" % String(extras.get("animation", "")))
		return
	var valve := Valve.new()
	valve.node = node
	valve.anim = animation
	var needle_curve := PackedFloat32Array()
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		valve.tracks.append(t)
		valve.targets.append(anim.track_target(animation, t))
		var curve := PackedFloat32Array([0.0])
		var previous := animation.rotation_track_interpolate(t, 0.0)
		for k in range(1, 241):
			var q := animation.rotation_track_interpolate(t, animation.length * k / 240.0)
			curve.append(curve[k - 1] + previous.angle_to(q))
			previous = q
		if valve.needle < 0 or curve[240] > needle_curve[240]:
			valve.needle = t
			needle_curve = curve
	valve.curve = needle_curve
	# Descente de l'aiguille : t0 (manette ouverte) – t1 (sas vide, avant que la manette se referme).
	var last := needle_curve.size() - 1
	var first_move := 0
	while first_move < last and needle_curve[first_move + 1] <= 1e-4:
		first_move += 1
	var at_end := last
	while at_end > 0 and needle_curve[at_end - 1] >= needle_curve[last] - 1e-4:
		at_end -= 1
	valve.t0 = animation.length * first_move / last
	valve.t1 = animation.length * at_end / last
	valve.green = _indicator_material(node, String(extras.get("voyant_plein", "")))
	valve.red = _indicator_material(node, String(extras.get("voyant_vide", "")))
	for i in valve.tracks.size():
		if valve.targets[i]:
			StationAnim.apply_track(animation, valve.tracks[i], valve.targets[i], 0.0)
	_valve = valve


## Copie émissive (posée en surcharge) du matériau de voyant material_name du maillage, ou null.
static func _indicator_material(node: MeshInstance3D, material_name: String) -> BaseMaterial3D:
	for s in node.mesh.get_surface_count():
		var material := node.mesh.surface_get_material(s) as BaseMaterial3D
		if material and material.resource_name == material_name:
			var lit := material.duplicate() as BaseMaterial3D
			lit.emission_enabled = true
			lit.emission = material.albedo_color
			lit.emission_energy_multiplier = 0.0
			node.set_surface_override_material(s, lit)
			return lit
	return null
