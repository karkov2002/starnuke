class_name Station
extends Node3D
## Station spatiale (racine de scenes/station_spatiale.tscn, scène héritée du modèle Blender
## assets/station/station_spatiale.glb). API de pilotage : écoutilles, trappes des silos, lancement des missiles,
## radiateurs et jauge de chaleur.
##
## Tout est lu dans le modèle, rien n'est codé en dur (le .glb est réexporté depuis Blender avec les mêmes noms) :
## - objets « Interactif_* » : métadonnée « extras » (propriétés Blender) : type (ecoutille, trappe_silo, trappe), id,
##   charniere, silo, tube, ouvrable ;
## - angles et durées : ceux des animations Blender, rejouées par StationAnim (scripts/station/station_anim.gd : un
##   AnimationPlayer par animation pour les groupes, pistes rejouées par Tween pour un objet seul).
## États au repos (modèle) : écoutilles ouvertes, trappes des silos fermées, radiateurs déployés. Au démarrage du jeu,
## les écoutilles ouvrables sont fermées (start_hatches_closed) ; le joueur les ouvre d'un clic (scripts/hatch_interaction.gd).
##
## Trappes des silos, gyrophare du tube choisi et lancement des missiles (copie du missile modèle, animation
## Lancement_Missile jusqu'au relais missile_released vers scripts/missile_flight.gd) : StationSilos.
##
## Chaleur (préparation d'une jauge) : heat (0 à 1) monte quand les radiateurs sont repliés (mode furtif : pas de
## rayonnement infrarouge) et redescend quand ils sont déployés, en proportion des radiateurs déployés.

signal hatch_changed(id: String, open: bool)
## Une écoutille commence à s'ouvrir (open) ou à se fermer (dès la demande ; hatch_changed : à la fin du mouvement).
signal hatch_moving(id: String, open: bool)
signal curtain_changed(id: String, closed: bool)
signal silo_door_changed(silo: int, tube: int, open: bool)
signal radiator_changed(id: String, deployed: bool)
signal missile_ignited(silo: int, tube: int)
## Fin de l'animation Blender (ligne droite, ~30 m sous la station) : le récepteur prend en charge le missile (nœud,
## avec sa propulsion allumée) et sa vitesse (monde, m/s) pour la suite du vol (scripts/missile_flight.gd), et le
## libère ensuite. Sans récepteur connecté, la station le masque.
signal missile_released(silo: int, tube: int, missile: Node3D, velocity: Vector3)
signal heat_changed(heat: float)
## Combinaison du sas enfilée (true) ou rangée sur son support (false).
signal suit_changed(worn: bool)
## Fin d'une vidange (false) ou d'un remplissage (true) du sas de sortie.
signal airlock_changed(pressurized: bool)
## Fin de la séparation (false) ou du réamarrage (true) du vaisseau cargo.
signal cargo_changed(docked: bool)
## Niveau d'alerte changé (set_alert) : sirènes (AlertSirens), tablette.
signal alert_changed(level: int)

## Groupe de la station (pour la retrouver depuis l'interface).
const GROUP := &"station"
const ANIM_HATCHES := &"Fermeture_Ecoutilles"
const ANIM_SILO_DOORS := &"Ouverture_Trappes"
const ANIM_LAUNCH := &"Lancement_Missile"
const ANIM_RADIATORS := &"Retraction_Radiateurs"
const ANIM_PANELS := &"Rotation_Panneaux"
const ANIM_ANTENNAS := &"Balayage_Antennes"
const ANIM_CARGO := &"Separation_Cargo"
const MODEL_MISSILE := "Missile_Balistique_1_12"
const MODEL_SILO := 1
const MODEL_TUBE := 12
const RADIATOR_IDS: Array[String] = ["Radiateur_D15", "Radiateur_D21", "Radiateur_G15", "Radiateur_G21"]
## Calque des surfaces intérieures (bit 11), seul éclairé par les lampes intérieures.
const INTERIOR_LAYER := 1 << 10
## Calque de collision (bit 20) des zones de clic des rideaux (Area3D, ni corps ni collision avec l'observateur).
const CURTAIN_LAYER := 1 << 19
## Épaisseur (m) de la zone de clic d'un rideau.
const CURTAIN_PICK_DEPTH := 0.06
## Matériaux intérieurs (préfixes des noms Blender) ; tous les autres sont extérieurs. Les vitrages et hublots se
## voient des deux côtés : ils sont des deux calques.
const INTERIOR_MATERIALS: Array[String] = ["Int_", "Ecran_"]
const BOTH_SIDES_MATERIALS: Array[String] = ["Hublot", "Vitrage"]
## Surface masquée : rejetée avant tout calcul de pixel (sommets hors du volume de vue).
const HIDDEN_SHADER := "shader_type spatial;\nrender_mode unshaded, skip_vertex_transform;\nvoid vertex() {\n\tPOSITION = vec4(0.0, 0.0, 2.0, 1.0);\n}\n"

## Panneaux solaires (pivots Pivot_Panneau_*, rotation autour de l'axe Z du modèle, cellules du côté +Y) orientés vers
## le soleil à chaque image, sans jamais tourner leur face vers le sol (station furtive : une face éclairée tournée vers
## la Terre la rendrait visible) ; l'animation Blender Rotation_Panneaux (rotation continue) n'est plus jouée.
@export var track_sun_panels := true
## Écoutilles ouvrables fermées au démarrage (règle de jeu) ; sinon, état du modèle (ouvertes).
@export var start_hatches_closed := true
## Écoutilles laissées ouvertes au démarrage (règle de jeu) : le passage Habitation – Commande (poste de pilotage).
@export var start_open_hatches: Array[String] = ["Ecoutille_Habitation_AV", "Ecoutille_Commande_AR"]
## Rideaux fermés au démarrage (règle de jeu).
@export var start_curtains_closed := true
## Durée (s) de la fermeture ou de l'ouverture complète d'un rideau.
@export var curtain_duration_s := 0.9
## Volant de verrouillage d'une écoutille (extras volant, volant_tours) : durée de ses tours, avant l'ouverture et
## après la fermeture.
@export var hatch_wheel_s := 0.9
## Lumière du soleil et Terre de la scène (direction du soleil, verticale locale). Sans Terre : +Y de la station.
@export var sun_path: NodePath = ^"../../Sun"
@export var earth_path: NodePath = ^"../../Earth"
## Orbite (ensoleillement de la station, pour le mode nuit des luminaires).
@export var orbit_path: NodePath = ^"../../Orbit"
## Environnement (sa lumière ambiante n'éclaire que la station : elle suit l'extinction « plus de lumière »).
@export var world_environment_path: NodePath = ^"../../WorldEnvironment"
## Vitesse maximale des panneaux (degrés par seconde) : le suivi normal est bien plus lent (un tour par orbite) ; la
## limite évite un saut quand la date ou l'heure change.
@export var panel_max_speed_deg := 6.0
## Marge (degrés) au-dessus de l'horizon local pour la face des cellules.
@export var panel_horizon_margin_deg := 2.0

@export_group("Gyrophare des silos")
## Clignotement (période en s, part allumée) et lumière (énergie, portée en m) du gyrophare du tube choisi.
@export var beacon_period_s := 0.9
@export_range(0.05, 1.0) var beacon_duty := 0.35
@export var beacon_energy := 4.0
@export var beacon_range := 6.0
## Décalage depuis le repère Point_Lancement du tube (m) : x vers l'extérieur de la rangée, y sous la coque.
@export var beacon_offset := Vector3(0.75, -0.12, 0.0)
@export_group("")
@export var animate_antennas := true

## Rayon (m) de la zone de la cupola autour du repère Point_Vue_Cupola (is_in_cupola : la barre de contrôle et le tir ne
## sont disponibles que là).
@export var cupola_zone_radius := 1.6
## Recul de la propulsion au-delà de l'arrière du maillage du missile (m) : l'arrière est à 3 m du centre, la
## propulsion part à 3,5 m (réglage visuel).
@export var nozzle_offset_m := 0.5

@export_group("Sas de sortie")
## Écoutille intérieure (plancher de l'Arrimage) et porte extérieure (vers la Terre) du sas.
@export var airlock_inner_hatch := "Ecoutille_Sas_Haut"
@export var airlock_outer_hatch := "Ecoutille_Sas_Bas"
## Émission des voyants allumés de la valve (vert : plein, rouge : vide ; le rouge clignote pendant un cycle).
@export var indicator_energy := 8.0
@export var indicator_blink_s := 0.8
@export_group("")
@export_group("Éclairage intérieur")
## 28 lampes ponctuelles du modèle (Lum_*), recalibrées au démarrage : ambiance ISS (luminaires LED en mode jour,
## ~4 500 K), sans ombres. Elles n'éclairent que les surfaces intérieures (calque INTERIOR_LAYER) : sans ombres, elles
## traverseraient sinon la coque et l'éclaireraient de l'extérieur.
@export var interior_light_energy := 1.2
## Mode nuit des luminaires : part du réglage « Éclairage intérieur » quand la station est dans l'ombre de la Terre
## (Orbit.get_sunlight_fraction, pénombre comprise) : 40 % de jour → 30 % de nuit, comme l'ISS tamise la nuit.
@export var night_light_ratio := 0.75
## Niveau d'alerte de la station (set_alert) : les luminaires blancs passent en jaune, orange ou rouge (lumière
## projetée et émission des bandeaux), fondu en alert_fade_s ; en alerte rouge, pulsation lente d'amplitude
## red_alert_pulse (part de la puissance) et de période red_alert_period_s. Les déclencheurs (situations critiques)
## sont à définir par le jeu ; le panneau de debug (nuke/debug) permet de les essayer.
@export var alert_colors: Array[Color] = [Color.WHITE, Color(1.0, 0.85, 0.3), Color(1.0, 0.55, 0.15),
		Color(1.0, 0.15, 0.08)]
@export var alert_fade_s := 0.8
@export var red_alert_pulse := 0.3
@export var red_alert_period_s := 1.4
## « Plus de lumière » (Alert.BLACKOUT) : bandeaux et lampes éteints, sauf une lampe sur emergency_light_every
## (LED de secours) à emergency_light_energy, teinte emergency_light_color, qui éclairent très faiblement les modules ;
## les voyants du modèle (Int_Voyant_*, émissifs) restent allumés. Fondu en alert_fade_s.
@export var emergency_light_every := 4
@export var emergency_light_energy := 0.06
@export var emergency_light_color := Color(0.55, 0.75, 1.0)
@export var interior_light_range := 5.5
@export var interior_light_attenuation := 1.3
@export var interior_light_temperature := 4500.0
@export var interior_light_specular := 0.4
@export var interior_shadows := false
## Chaleur : montée par seconde radiateurs tous repliés, descente par seconde radiateurs tous déployés
## (valeurs provisoires, à régler avec la jauge).
@export var heat_rise_per_s := 0.01
@export var heat_fall_per_s := 0.02

## Chaleur accumulée (0 à 1).
var heat := 0.0

## Écoutilles, trappes verrouillées et rideaux : StationHatches.
var _hatches: StationHatches
## Trappes des silos, gyrophares et lancement des missiles : StationSilos.
var _silos: StationSilos
## id -> {tracks : Array[int], is_deployed, tween}
var _radiators := {}
## Animations du modèle (bibliothèque, lecteurs, pistes rejouées) : StationAnim.
var _anim: StationAnim
## Panneaux solaires (suivi du soleil) : StationSolarPanels.
var _solar: StationSolarPanels
var _orbit: OrbitSimulation
## Éclairage intérieur, alerte et black-out : StationLighting.
var _lighting: StationLighting

enum Alert { NONE, YELLOW, ORANGE, RED, BLACKOUT }
## Sas de sortie : combinaison et son support (extras type « combinaison », « porte_combinaison »).
var _suit: Node3D
var _suit_rack: Node3D
var _suit_worn := false
## Valve du sas (extras type « valve_sas ») : {node, anim, tracks, targets, time, tween, target_full, curve, green, red}.
var _valve := {}
var _indicator_time := 0.0
## L'observateur est sorti de la station (éjection, scripts/death_sequence.gd) : il voit les flashs nucléaires
## (NukeFlashFX), qui ne l'éblouissent sinon que dans la cupola.
var observer_outside := false
var _cargo_docked := true
var _cargo_busy := false


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_anim = StationAnim.from_model(self)
	if _anim == null:
		push_error("Station : pas d'AnimationPlayer dans le modèle")
		return
	_hatches = StationHatches.new(self, _anim)
	_silos = StationSilos.new(self, _anim)
	_collect_radiators()
	_split_interior_layers()
	var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
	_lighting = StationLighting.new(self, _orbit, world_environment.environment if world_environment else null)
	_collect_airlock()
	_add_interior_collisions()
	_solar = StationSolarPanels.new(self, get_node_or_null(sun_path) as Node3D, get_node_or_null(earth_path) as Node3D)
	if animate_antennas:
		_anim.play(ANIM_ANTENNAS)


func _exit_tree() -> void:
	if _silos:
		_silos.dispose()


func _process(delta: float) -> void:
	if _lighting:
		_lighting.update(delta)
	if track_sun_panels and _solar:
		_solar.update(delta)
	if _silos:
		_silos.update(delta)
	if not _valve.is_empty():
		_update_airlock_indicators(delta)
	if _radiators.is_empty():
		return
	var deployed := 0.0
	for id: String in _radiators:
		deployed += 1.0 if _radiators[id].is_deployed else 0.0
	var share := deployed / _radiators.size()
	var rate := heat_rise_per_s * (1.0 - share) - heat_fall_per_s * share
	var value := clampf(heat + rate * delta, 0.0, 1.0)
	if not is_equal_approx(value, heat):
		heat = value
		heat_changed.emit(heat)


# --- Écoutilles et rideaux (StationHatches) --------------------------------------------------------------------------

func hatch_ids() -> Array[String]:
	return _hatches.hatch_ids() if _hatches else []


func is_hatch_open(id: String) -> bool:
	return _hatches != null and _hatches.is_hatch_open(id)


func is_hatch_openable(id: String) -> bool:
	return _hatches != null and _hatches.is_hatch_openable(id)


## Ouvre ou ferme une écoutille (Tween, durée de l'animation Blender). Faux si elle est verrouillée ou inconnue.
func set_hatch_open(id: String, open: bool) -> bool:
	return _hatches != null and _hatches.set_hatch_open(id, open)


func open_hatch(id: String) -> bool:
	return set_hatch_open(id, true)


func close_hatch(id: String) -> bool:
	return set_hatch_open(id, false)


## État visé d'une écoutille (celui vers lequel elle bouge, ou son état au repos).
func is_hatch_opening(id: String) -> bool:
	return _hatches != null and _hatches.is_hatch_opening(id)


## Ouvre l'écoutille fermée (ou qui se ferme), ferme l'écoutille ouverte (ou qui s'ouvre).
func toggle_hatch(id: String) -> bool:
	return _hatches != null and _hatches.toggle_hatch(id)


## Identifiant de l'écoutille ouvrable à laquelle appartient node (la porte, ou un de ses descendants comme son corps
## de collision), "" sinon.
func hatch_id_for(node: Node) -> String:
	return _hatches.hatch_id_for(node) if _hatches else ""


## Charnière de l'écoutille (sondes), ou null.
func hatch_hinge(id: String) -> Node3D:
	return _hatches.hatch_hinge(id) if _hatches else null


## Toutes les écoutilles ouvrables, chacune par son Tween.
func set_all_hatches_open(open: bool) -> void:
	if _hatches:
		_hatches.set_all_hatches_open(open)


func curtain_ids() -> Array[String]:
	return _hatches.curtain_ids() if _hatches else []


## État visé d'un rideau (celui vers lequel il bouge, ou son état au repos).
func is_curtain_closing(id: String) -> bool:
	return _hatches != null and _hatches.is_curtain_closing(id)


func set_curtain_closed(id: String, closed: bool) -> bool:
	return _hatches != null and _hatches.set_curtain_closed(id, closed)


func toggle_curtain(id: String) -> bool:
	return _hatches != null and _hatches.toggle_curtain(id)


## Identifiant du rideau auquel appartient node (sa zone de clic), "" sinon.
func curtain_id_for(node: Node) -> String:
	return _hatches.curtain_id_for(node) if _hatches else ""


# --- Sas de sortie --------------------------------------------------------------------------------------------------
# Combinaison (clic : on l'enfile, elle disparaît ; clic sur son support : elle y revient) et valve de
# dépressurisation (animation Blender Depressurisation_Sas : la manette s'ouvre (début), l'aiguille du manomètre
# descend de 1 à 0 bar (courbe de vidange)). La valve est un robinet (vidange, remplissage, fermée) ; les pressions
# sont calculées par StationAtmosphere (scripts/station_atmosphere.gd), qui fait suivre la pression du sas à
# l'aiguille. Aucun verrouillage : la sécurité est l'affaire du joueur (conséquences : scripts/airlock_hazard.gd).

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
	suit_changed.emit(worn)
	return true


## Pièce du sas à laquelle appartient node, quand un clic y a un effet : « combinaison » (à enfiler), « porte » (le
## support, pour la ranger), « valve » ; "" sinon.
func airlock_part_for(node: Node) -> String:
	while node and node != self:
		if node == _suit:
			return "" if _suit_worn else "combinaison"
		if node == _suit_rack:
			return "porte" if _suit_worn else ""
		if not _valve.is_empty() and node == _valve.node:
			return "valve"
		node = node.get_parent()
	return ""


## Pression du sas (1 : plein, 0 : vide), affichée par l'aiguille du manomètre (calculée par StationAtmosphere).
func get_airlock_pressure() -> float:
	return float(_valve.get("pressure", 1.0))


func is_airlock_cycling() -> bool:
	return get_airlock_valve_mode() != 0


## Sens de la valve : −1 vidange, +1 remplissage, 0 fermée.
func get_airlock_valve_mode() -> int:
	return int(_valve.get("mode", 0))


## État visé de la valve : vrai si elle remplit, ou si, fermée, le sas est plutôt plein.
func is_airlock_filling() -> bool:
	var mode := get_airlock_valve_mode()
	return mode > 0 or (mode == 0 and get_airlock_pressure() >= 0.5)


## Ouvre la valve pour remplir (full) ou vider le sas, et avec lui tout ce qui communique avec lui
## (StationAtmosphere) ; elle se referme d'elle-même une fois la pression visée atteinte. Une demande inverse pendant
## un cycle l'inverse. Faux sans valve dans le modèle.
func set_airlock_pressurized(full: bool) -> bool:
	if _valve.is_empty():
		return false
	var pressure := get_airlock_pressure()
	if (full and pressure >= 0.998) or (not full and pressure <= 0.002):
		_valve.mode = 0
		_move_lever(0.0)
		return true
	_valve.mode = 1 if full else -1
	_move_lever(1.0)
	return true


func toggle_airlock_pressure() -> bool:
	return set_airlock_pressurized(not is_airlock_filling())


## Durée (s) d'une vidange complète du sas seul par la valve (descente de l'aiguille dans Depressurisation_Sas).
func get_airlock_valve_s() -> float:
	return maxf(float(_valve.get("t1", 20.0)) - float(_valve.get("t0", 0.0)), 0.01)


## Pression après seconds de vidange du sas seul par la valve (seconds < 0 : remplissage), sur la courbe du manomètre
## (exponentielle adoucie : plus rapide aux faibles pressions qu'une exponentielle pure).
func airlock_step(pressure: float, seconds: float) -> float:
	if _valve.is_empty():
		return clampf(pressure - seconds / 20.0, 0.0, 1.0)
	var t := clampf(_time_for(pressure, seconds < 0.0) + seconds, float(_valve.t0), float(_valve.t1))
	return _pressure_at(t)


## Pression du sas (StationAtmosphere, à chaque image) : aiguille du manomètre, fin de cycle de la valve.
func set_airlock_gauge(pressure: float) -> void:
	if _valve.is_empty():
		return
	_valve.pressure = pressure
	var needle: int = _valve.needle
	var node: Node3D = _valve.targets[_valve.tracks.find(needle)]
	if node:
		StationAnim.apply_track(_valve.anim, needle, node, _time_for(pressure, false))
	var mode: int = _valve.mode
	if (mode < 0 and pressure <= 0.002) or (mode > 0 and pressure >= 0.998):
		_valve.mode = 0
		_move_lever(0.0)
		airlock_changed.emit(mode > 0)


## Manette : 0 fermée (début de l'animation), 1 ouverte (quand l'aiguille commence à descendre), à la vitesse de
## l'animation.
func _move_lever(open: float) -> void:
	if _valve.lever_tween:
		(_valve.lever_tween as Tween).kill()
	var t0: float = _valve.t0
	var duration := absf(open - float(_valve.lever)) * t0
	if duration <= 0.0:
		return
	_valve.lever_tween = create_tween()
	_valve.lever_tween.tween_method(func(u: float) -> void:
		_valve.lever = u
		for i in _valve.tracks.size():
			if _valve.tracks[i] != _valve.needle and _valve.targets[i]:
				StationAnim.apply_track(_valve.anim, _valve.tracks[i], _valve.targets[i], u * t0), _valve.lever, open, duration)


## Pression au temps time de l'animation : 1 − rotation cumulée de l'aiguille / rotation totale. L'aiguille est la
## piste qui tourne le plus (225°, la manette 90°) ; rotation cumulée par petits pas (sans ambiguïté de signe).
func _pressure_at(time: float) -> float:
	var curve: PackedFloat32Array = _valve.curve
	var last := curve.size() - 1
	if last < 1 or curve[last] <= 0.0:
		return 1.0
	var x := clampf(time / (_valve.anim as Animation).length, 0.0, 1.0) * last
	var i := mini(int(x), last - 1)
	return 1.0 - lerpf(curve[i], curve[i + 1], x - i) / curve[last]


## Temps de l'animation où l'aiguille indique pressure (réciproque de _pressure_at), dans sa descente (t0–t1) : au
## début (early, sens du remplissage) ou à la fin des paliers.
func _time_for(pressure: float, early: bool) -> float:
	var curve: PackedFloat32Array = _valve.curve
	var last := curve.size() - 1
	if last < 1 or curve[last] <= 0.0:
		return 0.0
	var c := (1.0 - clampf(pressure, 0.0, 1.0)) * curve[last]
	# Segment [i, i + 1] qui contient c (curve[i] ≤ c), au début (early) ou à la fin d'un palier.
	var i := curve.bsearch(c, early)
	if i > last or curve[i] > c:
		i -= 1
	i = clampi(i, 0, last)
	var x := float(i)
	if i < last and curve[i + 1] > curve[i] and c > curve[i]:
		x += minf((c - curve[i]) / (curve[i + 1] - curve[i]), 1.0)
	var length: float = (_valve.anim as Animation).length
	return clampf(x / last * length, float(_valve.t0), float(_valve.t1))


func _collect_airlock() -> void:
	for node: MeshInstance3D in find_children("Interactif_*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta("extras", {})
		match String(extras.get("type", "")):
			"combinaison":
				_suit = node
			"porte_combinaison":
				_suit_rack = node
			"valve_sas":
				_setup_valve(node, extras)


func _setup_valve(node: MeshInstance3D, extras: Dictionary) -> void:
	var anim_name := StringName(String(extras.get("animation", "")))
	if not _anim.has(anim_name):
		push_error("Station : animation %s de la valve absente" % anim_name)
		return
	var anim := _anim.animation(anim_name)
	var tracks: Array[int] = []
	var targets: Array[Node3D] = []
	var needle := -1
	var needle_curve := PackedFloat32Array()
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		tracks.append(t)
		targets.append(get_node_or_null(anim.track_get_path(t)) as Node3D)
		var curve := PackedFloat32Array([0.0])
		var previous := anim.rotation_track_interpolate(t, 0.0)
		for k in range(1, 241):
			var q := anim.rotation_track_interpolate(t, anim.length * k / 240.0)
			curve.append(curve[k - 1] + previous.angle_to(q))
			previous = q
		if needle < 0 or curve[240] > needle_curve[240]:
			needle = t
			needle_curve = curve
	# Descente de l'aiguille : t0 (manette ouverte) – t1 (sas vide, avant que la manette se referme).
	var last := needle_curve.size() - 1
	var first_move := 0
	while first_move < last and needle_curve[first_move + 1] <= 1e-4:
		first_move += 1
	var at_end := last
	while at_end > 0 and needle_curve[at_end - 1] >= needle_curve[last] - 1e-4:
		at_end -= 1
	_valve = {"node": node, "anim": anim, "tracks": tracks, "targets": targets, "curve": needle_curve,
			"needle": needle, "t0": anim.length * first_move / last, "t1": anim.length * at_end / last,
			"mode": 0, "pressure": 1.0, "lever": 0.0, "lever_tween": null,
			"green": _indicator_material(node, String(extras.get("voyant_plein", ""))),
			"red": _indicator_material(node, String(extras.get("voyant_vide", "")))}
	for i in tracks.size():
		if targets[i]:
			StationAnim.apply_track(anim, tracks[i], targets[i], 0.0)


## Copie émissive (posée en surcharge) du matériau de voyant material_name du maillage, ou null.
func _indicator_material(node: MeshInstance3D, material_name: String) -> BaseMaterial3D:
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


## Voyants : vert allumé sas plein, rouge allumé sas vide ; pendant un cycle, le vert s'éteint et le rouge clignote.
func _update_airlock_indicators(delta: float) -> void:
	_indicator_time = fmod(_indicator_time + delta, indicator_blink_s)
	var pressure := get_airlock_pressure()
	var cycling := is_airlock_cycling()
	var blink := _indicator_time < indicator_blink_s * 0.5
	if _valve.green:
		(_valve.green as BaseMaterial3D).emission_energy_multiplier = \
				indicator_energy if not cycling and pressure >= 0.99 else 0.0
	if _valve.red:
		(_valve.red as BaseMaterial3D).emission_energy_multiplier = \
				indicator_energy if (cycling and blink) or (not cycling and pressure <= 0.01) else 0.0


# --- Vaisseau cargo -------------------------------------------------------------------------------------------------
# Animation Blender Separation_Cargo : le pivot Pivot_Cargo (parent des Cargo_*) recule de 10 m selon l'axe des
# modules en 30 s ; à l'envers : réamarrage.

func is_cargo_docked() -> bool:
	return _cargo_docked


func is_cargo_moving() -> bool:
	return _cargo_busy


## Sépare (docked faux) ou réamarre le cargo. Faux s'il est déjà en mouvement ou sans animation.
func set_cargo_docked(docked: bool) -> bool:
	if not _anim.has(ANIM_CARGO) or _cargo_busy:
		return false
	if docked == _cargo_docked:
		return true
	_cargo_busy = true
	_anim.play_group(ANIM_CARGO, docked, func() -> void:
		_cargo_busy = false
		_cargo_docked = docked
		cargo_changed.emit(docked))
	return true


# --- Trappes des silos et missiles (StationSilos) -------------------------------------------------------------------

func is_silo_door_open(silo: int, tube: int) -> bool:
	return _silos != null and _silos.is_door_open(silo, tube)


func set_silo_door_open(silo: int, tube: int, open: bool) -> bool:
	return _silos != null and _silos.set_door_open(silo, tube, open)


func open_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, true)


func close_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, false)


## Toutes les trappes d'un silo (silo = 0 : les deux) : vague de l'animation si les 48 sont dans le même état.
func set_all_silo_doors_open(open: bool, silo := 0) -> void:
	if _silos:
		_silos.set_all_doors_open(open, silo)


## Gyrophare rouge à côté de la trappe du tube (tube choisi pour le tir).
func set_silo_beacon(silo: int, tube: int, on: bool) -> void:
	if _silos:
		_silos.set_beacon(silo, tube, on)


## Tous les tubes de lancement, triés (silo, puis tube).
func tube_ids() -> Array[Vector2i]:
	return _silos.tube_ids() if _silos else []


## Position du tube (repère Point_Lancement) dans le repère de la station : +X vers l'avant, +Z vers la droite.
func tube_position(silo: int, tube: int) -> Vector3:
	return _silos.tube_position(silo, tube) if _silos else Vector3.ZERO


## Durée de l'animation de lancement jusqu'au relais vers le vol (s) : missile_released arrive autant après
## launch_missile.
func launch_handoff_s() -> float:
	return _silos.launch_handoff_s() if _silos else 0.0


## Tubes d'où un missile peut partir (trappe ouvrable, pas encore tiré).
func available_tubes() -> Array[Vector2i]:
	return _silos.available_tubes() if _silos else []


func can_launch(silo: int, tube: int) -> bool:
	return _silos != null and _silos.can_launch(silo, tube)


## Lance le missile du tube : la trappe s'ouvre (si besoin), le missile descend, s'allume, puis quitte la scène
## (missile_released). Faux si le tube ne peut pas tirer.
func launch_missile(silo: int, tube: int) -> bool:
	return _silos != null and _silos.launch_missile(silo, tube)


# --- Radiateurs -----------------------------------------------------------------------------------------------------

func radiator_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_radiators.keys())
	return ids


func is_radiator_deployed(id: String) -> bool:
	return _radiators.has(id) and _radiators[id].is_deployed


## Déploie ou replie un radiateur (ses trois articulations, rejouées depuis Retraction_Radiateurs).
func set_radiator_deployed(id: String, deployed: bool) -> bool:
	if not _radiators.has(id):
		return false
	var radiator: Dictionary = _radiators[id]
	if radiator.is_deployed == deployed:
		return true
	if radiator.tween:
		radiator.tween.kill()
	var anim := _anim.animation(ANIM_RADIATORS)
	# Retraction_Radiateurs : début = déployé, fin = replié.
	var from := 0.0 if deployed == false else anim.length
	var to := anim.length if deployed == false else 0.0
	radiator.tween = _anim.play_tracks(anim, radiator.tracks, from, to, anim.length)
	radiator.tween.tween_callback(func() -> void:
		radiator.tween = null
		radiator.is_deployed = deployed
		radiator_changed.emit(id, deployed))
	return true


## Tous les radiateurs : animation complète s'ils sont tous dans le même état, sinon un par un.
func set_all_radiators_deployed(deployed: bool) -> void:
	var group := _radiators.keys().all(func(id: String) -> bool:
		return _radiators[id].is_deployed != deployed and _radiators[id].tween == null)
	if group:
		_anim.play_group(ANIM_RADIATORS, deployed, func() -> void:
			for id: String in _radiators:
				_radiators[id].is_deployed = deployed
				radiator_changed.emit(id, deployed))
	else:
		for id: String in _radiators:
			set_radiator_deployed(id, deployed)


## Mode furtif : radiateurs repliés (la chaleur monte).
func set_stealth(enabled: bool) -> void:
	set_all_radiators_deployed(not enabled)


# --- Zones ----------------------------------------------------------------------------------------------------------

## Le point (monde) est-il dans la cupola ? (sphère de cupola_zone_radius autour de Point_Vue_Cupola)
## Part de l'extinction des lumières (0 : normal, 1 : « plus de lumière »), fondue : écrans animés (TechScreens).
func get_blackout() -> float:
	return _lighting.dark if _lighting else 0.0


func is_in_cupola(world_position: Vector3) -> bool:
	var point := get_node_or_null("Point_Vue_Cupola") as Node3D
	return point != null and point.global_position.distance_to(world_position) < cupola_zone_radius


# --- Construction ---------------------------------------------------------------------------------------------------

## Collisions des objets intérieurs : le modèle n'en génère que pour les parois (« -col ») et les portes
## (« -convcolonly ») ; les objets « Interactif_* » sans collision (tubes des silos, consoles, caisses, couchette…)
## reçoivent une forme convexe simplifiée (StaticBody3D « Collision » enfant), normalement dès l'import
## (tools/import/station_import.gd) : ce calcul coûte ~3,5 s ; il n'est refait ici que pour un objet qui n'en aurait pas.
func _add_interior_collisions() -> void:
	# Parois (« -col », formes concaves) : collision des deux côtés. Par défaut une face ne bloque que du côté où pointe
	# sa normale ; vue de l'intérieur d'une coque (normales vers l'extérieur), on la traverserait.
	for collision: CollisionShape3D in find_children("*", "CollisionShape3D", true, false):
		if collision.shape is ConcavePolygonShape3D:
			(collision.shape as ConcavePolygonShape3D).backface_collision = true
	for mesh_instance: MeshInstance3D in find_children("Interactif_*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null or mesh_instance.get_children().any(func(c: Node) -> bool:
				return c is CollisionObject3D):
			continue
		var shape := mesh_instance.mesh.create_convex_shape(true, true)
		if shape == null:
			continue
		var body := StaticBody3D.new()
		body.name = "Collision"
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		mesh_instance.add_child(body)

## Corps de collision d'une porte (AnimatableBody3D tiré du nœud Blender « -convcolonly », enfant de la porte) : avec
## sync_to_physics, il ne suit que ses propres déplacements, pas ceux de la charnière parente, et restait figé dans la
## pose de l'import (porte fermée traversable, porte ouverte qui bloque encore le passage et le clic). Sans
## sync_to_physics, il suit la porte à chaque image (et pousse toujours l'observateur).
static func fit_door_collision(door: Node) -> void:
	for body in door.get_children():
		if body is AnimatableBody3D:
			(body as AnimatableBody3D).sync_to_physics = false


func _collect_radiators() -> void:
	if not _anim.has(ANIM_RADIATORS):
		return
	var anim := _anim.animation(ANIM_RADIATORS)
	for id in RADIATOR_IDS:
		var tracks: Array[int] = []
		for t in anim.get_track_count():
			if String(anim.track_get_path(t)).begins_with(id + "/"):
				tracks.append(t)
		if not tracks.is_empty():
			_radiators[id] = {"tracks": tracks, "is_deployed": true, "tween": null}


## Calques intérieurs. Un maillage entièrement intérieur passe sur INTERIOR_LAYER ; un maillage mixte (coques : surfaces
## Coque_Silo dehors, Int_Coque dedans) est doublé : l'original ne garde que ses surfaces extérieures, la copie (même
## maillage, LOD compris, sans ombre portée) ses surfaces intérieures, sur INTERIOR_LAYER. (Lampes et luminaires :
## StationLighting.)
func _split_interior_layers() -> void:
	var hidden := ShaderMaterial.new()
	hidden.shader = Shader.new()
	hidden.shader.code = HIDDEN_SHADER
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		var interior: Array[int] = []
		var exterior: Array[int] = []
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(s)
			var material_name := material.resource_name if material else ""
			if _has_prefix(material_name, BOTH_SIDES_MATERIALS):
				if material_name.begins_with("Vitrage") and material is BaseMaterial3D:
					mesh_instance.set_surface_override_material(s, _matte_glass(material as BaseMaterial3D))
				continue
			if _has_prefix(material_name, INTERIOR_MATERIALS):
				interior.append(s)
			else:
				exterior.append(s)
		if exterior.is_empty():
			mesh_instance.layers |= INTERIOR_LAYER
		elif not interior.is_empty():
			var inside := MeshInstance3D.new()
			inside.name = String(mesh_instance.name) + "_Interieur"
			inside.mesh = mesh_instance.mesh
			inside.layers = mesh_instance.layers | INTERIOR_LAYER
			inside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in exterior:
				inside.set_surface_override_material(s, hidden)
			for s in interior:
				mesh_instance.set_surface_override_material(s, hidden)
			mesh_instance.add_child(inside)


## Niveau d'alerte de la station (couleur des luminaires, voir alert_colors ; StationLighting).
func set_alert(level: Alert) -> void:
	if _lighting and _lighting.set_alert(level):
		alert_changed.emit(level)


func get_alert() -> Alert:
	return _lighting.alert if _lighting else Alert.NONE


## Vitrage de la cupola sans reflet spéculaire : le reflet de l'environnement (disque solaire du ciel) ignore l'ombre
## portée de la station, et faisait briller le soleil dans le hublot du nadir alors que la cupola est à l'ombre.
static func _matte_glass(source: BaseMaterial3D) -> BaseMaterial3D:
	var glass := source.duplicate() as BaseMaterial3D
	glass.metallic = 0.0
	glass.metallic_specular = 0.0
	glass.roughness = 1.0
	return glass


static func _has_prefix(text: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if text.begins_with(prefix):
			return true
	return false

