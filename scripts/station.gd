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
## Chaleur de la station (0 à 1), tenue par StationThermal.
var heat: float:
	get:
		return _thermal.heat if _thermal else 0.0

## Écoutilles, trappes verrouillées et rideaux : StationHatches.
var _hatches: StationHatches
## Trappes des silos, gyrophares et lancement des missiles : StationSilos.
var _silos: StationSilos
## Radiateurs et chaleur : StationThermal.
var _thermal: StationThermal
## Animations du modèle (bibliothèque, lecteurs, pistes rejouées) : StationAnim.
var _anim: StationAnim
## Panneaux solaires (suivi du soleil) : StationSolarPanels.
var _solar: StationSolarPanels
var _orbit: OrbitSimulation
## Éclairage intérieur, alerte et black-out : StationLighting.
var _lighting: StationLighting

enum Alert { NONE, YELLOW, ORANGE, RED, BLACKOUT }
## Sas de sortie (combinaison, valve, voyants) : StationAirlock.
var _airlock: StationAirlock
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
	_thermal = StationThermal.new(self, _anim)
	StationModelSetup.prepare(self)
	var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
	_lighting = StationLighting.new(self, _orbit, world_environment.environment if world_environment else null)
	_airlock = StationAirlock.new(self, _anim)
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
	if _airlock:
		_airlock.update(delta)
	if _thermal:
		_thermal.update(delta)


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


# --- Sas de sortie (StationAirlock) ----------------------------------------------------------------------------------
# Combinaison et valve de dépressurisation ; les pressions sont calculées par StationAtmosphere, qui fait suivre la
# pression du sas à l'aiguille (set_airlock_gauge). Aucun verrouillage (conséquences : scripts/airlock_hazard.gd).

func is_suit_worn() -> bool:
	return _airlock != null and _airlock.is_suit_worn()


## Enfile (combinaison masquée, sans collision) ou range la combinaison. Faux sans combinaison dans le modèle.
func set_suit_worn(worn: bool) -> bool:
	return _airlock != null and _airlock.set_suit_worn(worn)


## Pièce du sas à laquelle appartient node, quand un clic y a un effet : « combinaison » (à enfiler), « porte » (le
## support, pour la ranger), « valve » ; "" sinon.
func airlock_part_for(node: Node) -> String:
	return _airlock.part_for(node) if _airlock else ""


## Pression du sas (1 : plein, 0 : vide), affichée par l'aiguille du manomètre (calculée par StationAtmosphere).
func get_airlock_pressure() -> float:
	return _airlock.pressure() if _airlock else 1.0


func is_airlock_cycling() -> bool:
	return _airlock != null and _airlock.is_cycling()


## Sens de la valve : −1 vidange, +1 remplissage, 0 fermée.
func get_airlock_valve_mode() -> int:
	return _airlock.valve_mode() if _airlock else 0


## État visé de la valve : vrai si elle remplit, ou si, fermée, le sas est plutôt plein.
func is_airlock_filling() -> bool:
	return _airlock != null and _airlock.is_filling()


## Ouvre la valve pour remplir (full) ou vider le sas, et avec lui tout ce qui communique avec lui
## (StationAtmosphere) ; elle se referme d'elle-même une fois la pression visée atteinte. Une demande inverse pendant
## un cycle l'inverse. Faux sans valve dans le modèle.
func set_airlock_pressurized(full: bool) -> bool:
	return _airlock != null and _airlock.set_pressurized(full)


func toggle_airlock_pressure() -> bool:
	return _airlock != null and _airlock.toggle_pressure()


## Durée (s) d'une vidange complète du sas seul par la valve.
func get_airlock_valve_s() -> float:
	return _airlock.valve_s() if _airlock else 20.0


## Pression après seconds de vidange du sas seul par la valve (seconds < 0 : remplissage), sur la courbe du manomètre.
func airlock_step(pressure: float, seconds: float) -> float:
	return _airlock.step(pressure, seconds) if _airlock else clampf(pressure - seconds / 20.0, 0.0, 1.0)


## Pression du sas (StationAtmosphere, à chaque image) : aiguille du manomètre, fin de cycle de la valve.
func set_airlock_gauge(pressure: float) -> void:
	if _airlock:
		_airlock.set_gauge(pressure)


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


# --- Radiateurs et chaleur (StationThermal) --------------------------------------------------------------------------

func radiator_ids() -> Array[String]:
	return _thermal.radiator_ids() if _thermal else []


func is_radiator_deployed(id: String) -> bool:
	return _thermal != null and _thermal.is_radiator_deployed(id)


## Déploie ou replie un radiateur (ses trois articulations, rejouées depuis Retraction_Radiateurs).
func set_radiator_deployed(id: String, deployed: bool) -> bool:
	return _thermal != null and _thermal.set_radiator_deployed(id, deployed)


## Tous les radiateurs : animation complète s'ils sont tous dans le même état, sinon un par un.
func set_all_radiators_deployed(deployed: bool) -> void:
	if _thermal:
		_thermal.set_all_radiators_deployed(deployed)


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


# --- Alerte (StationLighting) ---------------------------------------------------------------------------------------

## Niveau d'alerte de la station (couleur des luminaires, voir alert_colors ; StationLighting).
func set_alert(level: Alert) -> void:
	if _lighting and _lighting.set_alert(level):
		alert_changed.emit(level)


func get_alert() -> Alert:
	return _lighting.alert if _lighting else Alert.NONE
