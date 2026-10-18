class_name Station
extends Node3D
## Station spatiale (racine de scenes/station_spatiale.tscn, scène héritée du modèle Blender
## assets/station/station_spatiale.glb). API de pilotage : écoutilles, trappes des silos, lancement des missiles,
## radiateurs et jauge de chaleur.
##
## Tout est lu dans le modèle, rien n'est codé en dur (le .glb est réexporté depuis Blender avec les mêmes noms) :
## - objets « Interactif_* » : métadonnée « extras » (propriétés Blender) : type (ecoutille, trappe_silo, trappe), id,
##   charniere, silo, tube, ouvrable ;
## - angles et durées : ceux des animations Blender. Pour piloter un objet seul, ses pistes sont rejouées par un Tween
##   (_play_tracks) ; pour un groupe dans le même état (toutes les écoutilles…), l'animation complète est jouée par un
##   AnimationPlayer. Chaque animation a son propre AnimationPlayer (créé ici, bibliothèque partagée) : elles peuvent
##   tourner en même temps (panneaux et antennes en boucle, trappes, radiateurs).
## États au repos (modèle) : écoutilles ouvertes, trappes des silos fermées, radiateurs déployés. Au démarrage du jeu,
## les écoutilles ouvrables sont fermées (start_hatches_closed) ; le joueur les ouvre d'un clic (scripts/hatch_interaction.gd).
##
## Missiles : un seul est modélisé (Missile_Balistique_1_12, tube 1_12). Pour un autre tube, il est copié et placé à
## l'identique par rapport au Point_Lancement du tube ; le lancement rejoue l'animation Lancement_Missile : ouverture
## de la trappe, descente, allumage de la tuyère (Point_Tuyere : échelle 0 = éteint, 1 = allumé), jusqu'à ~30 m sous
## la station ; missile_released passe alors le missile au vol vers la cible (scripts/missile_flight.gd).
##
## Chaleur (préparation d'une jauge) : heat (0 à 1) monte quand les radiateurs sont repliés (mode furtif : pas de
## rayonnement infrarouge) et redescend quand ils sont déployés, en proportion des radiateurs déployés.

signal hatch_changed(id: String, open: bool)
signal silo_door_changed(silo: int, tube: int, open: bool)
signal radiator_changed(id: String, deployed: bool)
signal missile_ignited(silo: int, tube: int)
## Fin de l'animation Blender (ligne droite, ~30 m sous la station) : le récepteur prend en charge le missile (nœud,
## avec sa propulsion allumée) et sa vitesse (monde, m/s) pour la suite du vol (scripts/missile_flight.gd), et le
## libère ensuite. Sans récepteur connecté, la station le masque.
signal missile_released(silo: int, tube: int, missile: Node3D, velocity: Vector3)
signal heat_changed(heat: float)

## Groupe de la station (pour la retrouver depuis l'interface).
const GROUP := &"station"
const ANIM_HATCHES := &"Fermeture_Ecoutilles"
const ANIM_SILO_DOORS := &"Ouverture_Trappes"
const ANIM_LAUNCH := &"Lancement_Missile"
const ANIM_RADIATORS := &"Retraction_Radiateurs"
const ANIM_PANELS := &"Rotation_Panneaux"
const ANIM_ANTENNAS := &"Balayage_Antennes"
const MODEL_MISSILE := "Missile_Balistique_1_12"
const MODEL_SILO := 1
const MODEL_TUBE := 12
const RADIATOR_IDS: Array[String] = ["Radiateur_D15", "Radiateur_D21", "Radiateur_G15", "Radiateur_G21"]
## Calque des surfaces intérieures (bit 11), seul éclairé par les lampes intérieures.
const INTERIOR_LAYER := 1 << 10
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

## id -> {node, hinge, open, closed : Quaternion, duration, track, is_open, ouvrable, tween}
var _hatches := {}
## Vector2i(silo, tube) -> {node, hinge, closed, open, track, duration, is_open, ouvrable, tween, launch_point, fired}
var _silo_doors := {}
## id -> {tracks : Array[int], is_deployed, tween}
var _radiators := {}
var _players := {}
var _library: AnimationLibrary
## Copie intacte du missile modèle (prise au démarrage) : celui du tube 1_12 disparaît après son lancement.
var _missile_pristine: Node3D
var _panel_pivots: Array[Node3D] = []
## Vector2i(silo, tube) -> gyrophare (Node3D : Lampe, Lumiere)
var _beacons := {}
var _orbit: OrbitSimulation
var _environment: Environment
## Luminaires intérieurs (lampes Lum_* et matériaux Int_Lumiere*), listés une fois, et facteur appliqué.
var _interior_lights: Array[OmniLight3D] = []
var _lamp_materials: Array[BaseMaterial3D] = []
## Écrans (matériaux Ecran_*, émissifs) : éteints avec « plus de lumière ».
var _screen_materials: Array[BaseMaterial3D] = []
var _light_factor := -1.0
## Alerte : niveau courant, teinte appliquée (fondue) et horloge de la pulsation.
var _alert := Alert.NONE
var _alert_tint := Color.WHITE
var _alert_time := 0.0
## Part de l'extinction (0 : luminaires normaux, 1 : « plus de lumière »), fondue.
var _dark := 0.0
## Dernières valeurs appliquées aux lumières et matériaux.
var _applied_factor := -1.0
var _applied_tint := Color.BLACK
var _applied_dark := -1.0

enum Alert { NONE, YELLOW, ORANGE, RED, BLACKOUT }
var _beacon_time := 0.0
## Angle courant des panneaux (radians autour de Z) ; NAN avant la première image (placement direct).
var _panel_angle := NAN


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	var world_environment := get_node_or_null(world_environment_path) as WorldEnvironment
	if world_environment and world_environment.environment:
		_environment = world_environment.environment
		# Ressource partagée d'une partie à l'autre : l'ambiance d'origine est gardée en métadonnée.
		if not _environment.has_meta(&"base_ambient_energy"):
			_environment.set_meta(&"base_ambient_energy", _environment.ambient_light_energy)
	var imported := find_children("*", "AnimationPlayer", true, false)
	if imported.is_empty():
		push_error("Station : pas d'AnimationPlayer dans le modèle")
		return
	_library = (imported[0] as AnimationPlayer).get_animation_library(&"")
	for anim_name in _library.get_animation_list():
		var player := AnimationPlayer.new()
		player.name = "Player_" + anim_name
		add_child(player)
		player.root_node = player.get_path_to(self)
		player.add_animation_library(&"", _library)
		_players[anim_name] = player
	_collect_interactives()
	_collect_radiators()
	_setup_interior_lighting()
	_add_interior_collisions()
	var model := _missile_template()
	if model:
		_missile_pristine = model.duplicate() as Node3D
	_panel_pivots.assign(find_children("Pivot_Panneau_*", "Node3D", false, false))
	if animate_antennas and _players.has(ANIM_ANTENNAS):
		_players[ANIM_ANTENNAS].play(ANIM_ANTENNAS)


func _exit_tree() -> void:
	if _missile_pristine:
		_missile_pristine.free()
		_missile_pristine = null


func _process(delta: float) -> void:
	_update_interior_light(delta)
	if track_sun_panels:
		_track_sun(delta)
	if not _beacons.is_empty():
		_blink_beacons(delta)
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


# --- Écoutilles ---------------------------------------------------------------------------------------------------

func hatch_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_hatches.keys())
	return ids


func is_hatch_open(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].is_open


func is_hatch_openable(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].ouvrable


## Ouvre ou ferme une écoutille (Tween, durée de l'animation Blender). Faux si elle est verrouillée ou inconnue.
func set_hatch_open(id: String, open: bool) -> bool:
	if not is_hatch_openable(id):
		return false
	var hatch: Dictionary = _hatches[id]
	# État visé (et non l'état atteint) : une demande inverse en cours de mouvement repart de la position actuelle.
	if hatch.get("target", hatch.is_open) == open:
		return true
	hatch.target = open
	# Fermeture_Ecoutilles : début = ouverte, fin = fermée.
	_tween_hinge(hatch, hatch.closed if not open else hatch.open, func() -> void:
		hatch.is_open = open
		hatch_changed.emit(id, open))
	return true


func open_hatch(id: String) -> bool:
	return set_hatch_open(id, true)


func close_hatch(id: String) -> bool:
	return set_hatch_open(id, false)


## État visé d'une écoutille (celui vers lequel elle bouge, ou son état au repos).
func is_hatch_opening(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].get("target", _hatches[id].is_open)


## Ouvre l'écoutille fermée (ou qui se ferme), ferme l'écoutille ouverte (ou qui s'ouvre).
func toggle_hatch(id: String) -> bool:
	return set_hatch_open(id, not is_hatch_opening(id))


## Identifiant de l'écoutille ouvrable à laquelle appartient node (la porte, ou un de ses descendants comme son corps
## de collision), "" sinon.
func hatch_id_for(node: Node) -> String:
	while node and node != self:
		for id: String in _hatches:
			if _hatches[id].node == node:
				return id if _hatches[id].ouvrable else ""
		node = node.get_parent()
	return ""


## Toutes les écoutilles ouvrables : animation complète si elles sont toutes dans le même état, sinon une par une.
func set_all_hatches_open(open: bool) -> void:
	var targets := _hatches.keys().filter(func(id: String) -> bool: return _hatches[id].ouvrable)
	var group := targets.all(func(id: String) -> bool: return _hatches[id].is_open != open and _hatches[id].tween == null)
	if group and targets.size() == _animated_count(ANIM_HATCHES):
		for id: String in targets:
			_hatches[id].target = open
		_play_group(ANIM_HATCHES, not open, func() -> void:
			for id: String in targets:
				_hatches[id].is_open = open
				hatch_changed.emit(id, open))
	else:
		for id: String in targets:
			set_hatch_open(id, open)


# --- Trappes des silos ----------------------------------------------------------------------------------------------

func is_silo_door_open(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	return _silo_doors.has(key) and _silo_doors[key].is_open


func set_silo_door_open(silo: int, tube: int, open: bool) -> bool:
	var key := Vector2i(silo, tube)
	if not _silo_doors.has(key) or not _silo_doors[key].ouvrable:
		return false
	var door: Dictionary = _silo_doors[key]
	# État visé (et non l'état atteint) : une demande inverse en cours de mouvement repart de la position actuelle.
	if door.get("target", door.is_open) == open:
		return true
	door.target = open
	_tween_hinge(door, door.open if open else door.closed, func() -> void:
		door.is_open = open
		silo_door_changed.emit(silo, tube, open))
	return true


func open_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, true)


func close_silo_door(silo: int, tube: int) -> bool:
	return set_silo_door_open(silo, tube, false)


## Toutes les trappes d'un silo (silo = 0 : les deux) : vague de l'animation si les 48 sont dans le même état.
func set_all_silo_doors_open(open: bool, silo := 0) -> void:
	var keys := _silo_doors.keys().filter(func(k: Vector2i) -> bool:
		return (silo == 0 or k.x == silo) and _silo_doors[k].ouvrable)
	var group := silo == 0 and keys.all(func(k: Vector2i) -> bool:
		return _silo_doors[k].is_open != open and _silo_doors[k].tween == null)
	if group and keys.size() == _animated_count(ANIM_SILO_DOORS):
		_play_group(ANIM_SILO_DOORS, not open, func() -> void:
			for k: Vector2i in keys:
				_silo_doors[k].is_open = open
				_silo_doors[k].target = open
				silo_door_changed.emit(k.x, k.y, open))
	else:
		for k: Vector2i in keys:
			set_silo_door_open(k.x, k.y, open)


# --- Missiles -------------------------------------------------------------------------------------------------------

## Gyrophare rouge à côté de la trappe du tube (tube choisi pour le tir) : petite lampe émissive et lumière rouge
## clignotante (beacon_period_s), qui éclaire la trappe et le dessous de la coque pour qu'on voie la trappe s'ouvrir.
func set_silo_beacon(silo: int, tube: int, on: bool) -> void:
	var key := Vector2i(silo, tube)
	if not on:
		if _beacons.has(key):
			(_beacons[key] as Node3D).queue_free()
			_beacons.erase(key)
		return
	if _beacons.has(key) or not _silo_doors.has(key) or _silo_doors[key].launch_point == null:
		return
	var point := to_local((_silo_doors[key].launch_point as Node3D).global_position)
	var beacon := Node3D.new()
	beacon.name = "Gyrophare_%d_%02d" % [silo, tube]
	# Juste sous la coque, décalé vers l'extérieur de la rangée de tubes (avant/arrière), entre deux trappes.
	var side := signf(point.x) if absf(point.x) > 0.1 else 1.0
	beacon.position = point + Vector3(beacon_offset.x * side, beacon_offset.y, beacon_offset.z)
	var lamp := MeshInstance3D.new()
	lamp.name = "Lampe"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.0, 0.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.05, 0.02)
	material.emission_energy_multiplier = 0.0
	sphere.material = material
	lamp.mesh = sphere
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.add_child(lamp)
	var light := OmniLight3D.new()
	light.name = "Lumiere"
	light.light_color = Color(1.0, 0.08, 0.04)
	light.omni_range = beacon_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.light_cull_mask = 0xFFFFF & ~INTERIOR_LAYER
	light.position = Vector3(0.0, -0.1, 0.0)
	beacon.add_child(light)
	add_child(beacon)
	_beacons[key] = beacon


## Tous les tubes de lancement, triés (silo, puis tube).
func tube_ids() -> Array[Vector2i]:
	var tubes: Array[Vector2i] = []
	tubes.assign(_silo_doors.keys())
	tubes.sort()
	return tubes


## Position du tube (repère Point_Lancement) dans le repère de la station : +X vers l'avant, +Z vers la droite.
func tube_position(silo: int, tube: int) -> Vector3:
	var key := Vector2i(silo, tube)
	if not _silo_doors.has(key) or _silo_doors[key].launch_point == null:
		return Vector3.ZERO
	return global_transform.affine_inverse() * (_silo_doors[key].launch_point as Node3D).global_position


## Durée de l'animation de lancement jusqu'au relais vers le vol (s) : missile_released arrive autant après
## launch_missile.
func launch_handoff_s() -> float:
	if _library == null or not _library.has_animation(ANIM_LAUNCH):
		return 0.0
	var anim := _library.get_animation(ANIM_LAUNCH)
	return _handoff_time(anim, _track_for(anim, MODEL_MISSILE, Animation.TYPE_SCALE_3D))


## Tubes d'où un missile peut partir (trappe ouvrable, pas encore tiré).
func available_tubes() -> Array[Vector2i]:
	var tubes: Array[Vector2i] = []
	for key: Vector2i in _silo_doors:
		if can_launch(key.x, key.y):
			tubes.append(key)
	tubes.sort()
	return tubes


func can_launch(silo: int, tube: int) -> bool:
	var key := Vector2i(silo, tube)
	return _silo_doors.has(key) and _silo_doors[key].ouvrable and not _silo_doors[key].fired \
			and _silo_doors[key].launch_point != null and _missile_pristine != null


## Lance le missile du tube : la trappe s'ouvre (si besoin), le missile descend, s'allume, puis quitte la scène
## (missile_released). Faux si le tube ne peut pas tirer.
func launch_missile(silo: int, tube: int) -> bool:
	if not can_launch(silo, tube):
		return false
	var key := Vector2i(silo, tube)
	var door: Dictionary = _silo_doors[key]
	door.fired = true
	var template := _missile_template()
	var missile := template
	if key != Vector2i(MODEL_SILO, MODEL_TUBE):
		missile = _missile_pristine.duplicate() as Node3D
		missile.name = "Missile_Balistique_%d_%02d" % [silo, tube]
		missile.get_child(0).name = "Point_Tuyere_%d_%02d" % [silo, tube]
		add_child(missile)
	var nozzle := missile.get_child(0) as Node3D
	# Repère de la tuyère à l'arrière du missile (bout +Y du maillage, la pointe est en −Y) : dans le modèle
	# réexporté, Point_Tuyere est au centre du missile, et la propulsion semblait sortir du milieu de la coque.
	var hull := (missile as MeshInstance3D).mesh.get_aabb() if missile is MeshInstance3D else AABB()
	if hull.size.y > 0.0:
		nozzle.position = Vector3(0.0, hull.end.y + nozzle_offset_m, 0.0)
	var model_point := get_node_or_null("Point_Lancement_%d_%02d" % [MODEL_SILO, MODEL_TUBE]) as Node3D
	# Missile du tube = repère du tube × (repère du tube modèle)⁻¹ × missile modèle animé.
	var tube_frame: Transform3D = (door.launch_point as Node3D).transform * model_point.transform.affine_inverse()
	var anim := _library.get_animation(ANIM_LAUNCH)
	var position_track := _track_for(anim, MODEL_MISSILE, Animation.TYPE_POSITION_3D)
	var scale_track := _track_for(anim, MODEL_MISSILE, Animation.TYPE_SCALE_3D)
	var nozzle_track := _track_for(anim, MODEL_MISSILE + "/Point_Tuyere_%d_%02d" % [MODEL_SILO, MODEL_TUBE],
			Animation.TYPE_SCALE_3D)
	var model_hinge_track := _track_for(anim, "Charniere_Trappe_Silo_%d_%02d" % [MODEL_SILO, MODEL_TUBE])
	var model_hinge_end: Quaternion = anim.track_get_key_value(model_hinge_track,
			anim.track_get_key_count(model_hinge_track) - 1) if model_hinge_track >= 0 else Quaternion.IDENTITY
	var release_time := _handoff_time(anim, scale_track)
	var state := {"ignited": false}
	var was_open: bool = door.is_open
	# Trappe déjà ouverte ou en mouvement (choix du tube sur le panneau) : l'animation la reprend où elle est.
	if door.tween:
		door.tween.kill()
		door.tween = null
	door.target = true
	var hinge_start: Quaternion = (door.hinge as Node3D).quaternion
	var step := func(t: float) -> void:
		# Trappe du tube : même ouverture que la trappe modèle dans l'animation, transposée sur ses angles.
		if model_hinge_track >= 0:
			var q := anim.rotation_track_interpolate(model_hinge_track, t)
			var weight := q.angle_to(Quaternion.IDENTITY) / maxf(model_hinge_end.angle_to(Quaternion.IDENTITY), 1e-4)
			door.hinge.quaternion = hinge_start.slerp(door.open, clampf(weight, 0.0, 1.0))
		var scale_value := anim.scale_track_interpolate(scale_track, t) if scale_track >= 0 else Vector3.ONE
		var model := Transform3D(Basis.IDENTITY.scaled(scale_value), anim.position_track_interpolate(position_track, t))
		missile.transform = tube_frame * model
		if nozzle_track >= 0:
			nozzle.scale = anim.scale_track_interpolate(nozzle_track, t)
			if not state.ignited and nozzle.scale.x > 0.01:
				state.ignited = true
				missile_ignited.emit(silo, tube)
	var tween := create_tween()
	tween.tween_method(step, 0.0, release_time, release_time)
	tween.tween_callback(func() -> void:
		door.is_open = true
		if not was_open:
			silo_door_changed.emit(silo, tube, true)
		# Vitesse de sortie (monde) : dérivée de la piste de position de l'animation, transposée sur le tube.
		var dt := minf(0.05, release_time)
		var model_velocity := (anim.position_track_interpolate(position_track, release_time)
				- anim.position_track_interpolate(position_track, release_time - dt)) / maxf(dt, 1e-3)
		var velocity := global_basis * (tube_frame.basis * model_velocity)
		if missile_released.get_connections().is_empty():
			missile.visible = false
			if missile != template:
				missile.queue_free()
		else:
			missile_released.emit(silo, tube, missile, velocity))
	return true


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
	var anim := _library.get_animation(ANIM_RADIATORS)
	# Retraction_Radiateurs : début = déployé, fin = replié.
	var from := 0.0 if deployed == false else anim.length
	var to := anim.length if deployed == false else 0.0
	radiator.tween = _play_tracks(anim, radiator.tracks, from, to, anim.length)
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
		_play_group(ANIM_RADIATORS, deployed, func() -> void:
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
func is_in_cupola(world_position: Vector3) -> bool:
	var point := get_node_or_null("Point_Vue_Cupola") as Node3D
	return point != null and point.global_position.distance_to(world_position) < cupola_zone_radius


## Éclat bref puis extinction (gyrophare à éclats), montée et descente rapides pour éviter un clignotement sec.
func _blink_beacons(delta: float) -> void:
	_beacon_time = fmod(_beacon_time + delta, beacon_period_s)
	var phase := _beacon_time / beacon_period_s
	var level := smoothstep(0.0, 0.05, phase) * (1.0 - smoothstep(beacon_duty - 0.05, beacon_duty, phase))
	for beacon: Node3D in _beacons.values():
		var lamp := beacon.get_node("Lampe") as MeshInstance3D
		((lamp.mesh as SphereMesh).material as StandardMaterial3D).emission_energy_multiplier = 8.0 * level
		(beacon.get_node("Lumiere") as OmniLight3D).light_energy = beacon_energy * level


# --- Panneaux solaires ----------------------------------------------------------------------------------------------

## Oriente les panneaux vers le soleil autour de leur axe (Z du modèle). La face des cellules n(θ) = (−sin θ, cos θ)
## dans le plan XY de la station suit la projection du soleil, mais reste au-dessus de l'horizon local (n · zénith ≥
## sin(marge)) : si le soleil est sous l'horizon, elle s'arrête à la limite. Même angle pour les 4 panneaux (même
## axe, même soleil).
func _track_sun(delta: float) -> void:
	var sun := get_node_or_null(sun_path) as Node3D
	if sun == null or _panel_pivots.is_empty():
		return
	var inverse := global_basis.inverse()
	var sun_dir := inverse * sun.global_basis.z
	var earth := get_node_or_null(earth_path) as Node3D
	var zenith := inverse * (global_position - earth.global_position) if earth else Vector3.UP
	var target := Vector2(sun_dir.x, sun_dir.y)
	var up := Vector2(zenith.x, zenith.y)
	if up.length() < 1e-4:
		return
	up = up.normalized()
	if target.length() < 1e-4:
		target = up
	target = target.normalized()
	# Angle limite autour du zénith projeté : la face peut s'écarter de 90° − marge du zénith au plus.
	var max_tilt := deg_to_rad(90.0 - panel_horizon_margin_deg)
	var offset := clampf(up.angle_to(target), -max_tilt, max_tilt)
	var wanted := _normal_angle(up.rotated(offset))
	if is_nan(_panel_angle):
		_panel_angle = wanted
	else:
		var step := deg_to_rad(panel_max_speed_deg) * delta
		_panel_angle += clampf(angle_difference(_panel_angle, wanted), -step, step)
	for pivot in _panel_pivots:
		pivot.quaternion = Quaternion(Vector3.BACK, _panel_angle)


## Angle θ autour de +Z tel que la normale (−sin θ, cos θ) vaut n.
static func _normal_angle(n: Vector2) -> float:
	return atan2(-n.x, n.y)


# --- Construction ---------------------------------------------------------------------------------------------------

## Collisions des objets intérieurs : le modèle n'en génère que pour les parois (« -col ») et les portes
## (« -convcolonly ») ; les objets « Interactif_* » sans collision (tubes des silos, consoles, caisses, couchette…)
## reçoivent une forme convexe simplifiée (StaticBody3D « Collision » enfant).
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

func _collect_interactives() -> void:
	var hatch_anim := _library.get_animation(ANIM_HATCHES) if _library.has_animation(ANIM_HATCHES) else null
	var door_anim := _library.get_animation(ANIM_SILO_DOORS) if _library.has_animation(ANIM_SILO_DOORS) else null
	for node in find_children("Interactif_*", "", true, false):
		# Les corps de collision des portes portent le même nom que leur porte.
		if node is CollisionObject3D:
			continue
		var extras: Dictionary = node.get_meta("extras", {})
		var hinge := get_node_or_null(NodePath(String(extras.get("charniere", "")))) as Node3D \
				if extras.has("charniere") else null
		var ouvrable: bool = extras.get("ouvrable", hinge != null) and hinge != null
		match String(extras.get("type", "")):
			"ecoutille", "trappe":
				# Au repos : écoutilles ouvertes ; trappes verrouillées (sas, nadir) fermées.
				var entry := {"node": node, "hinge": hinge, "ouvrable": ouvrable,
						"is_open": String(extras.get("type")) == "ecoutille", "tween": null}
				if hinge and hatch_anim:
					_fill_hinge(entry, hatch_anim, hinge)
					# Début de Fermeture_Ecoutilles = ouverte.
					entry.open = entry.start
					entry.closed = entry.end
					if start_hatches_closed and entry.ouvrable and entry.is_open:
						hinge.quaternion = entry.closed
						entry.is_open = false
				_fit_door_collision(node)
				_hatches[String(extras.get("id", node.name))] = entry
			"trappe_silo":
				var key := Vector2i(int(extras.get("silo", 0)), int(extras.get("tube", 0)))
				var entry := {"node": node, "hinge": hinge, "ouvrable": ouvrable, "is_open": false, "tween": null,
						"fired": false,
						"launch_point": get_node_or_null("Point_Lancement_%d_%02d" % [key.x, key.y])}
				if hinge and door_anim:
					_fill_hinge(entry, door_anim, hinge)
					entry.closed = entry.start
					entry.open = entry.end
				_fit_door_collision(node)
				_silo_doors[key] = entry


## Corps de collision d'une porte (AnimatableBody3D tiré du nœud Blender « -convcolonly », enfant de la porte) : avec
## sync_to_physics, il ne suit que ses propres déplacements, pas ceux de la charnière parente, et restait figé dans la
## pose de l'import (porte fermée traversable, porte ouverte qui bloque encore le passage et le clic). Sans
## sync_to_physics, il suit la porte à chaque image (et pousse toujours l'observateur).
func _fit_door_collision(door: Node) -> void:
	for body in door.get_children():
		if body is AnimatableBody3D:
			(body as AnimatableBody3D).sync_to_physics = false


## Angles de début et de fin et durée de la piste de rotation de la charnière dans l'animation.
func _fill_hinge(entry: Dictionary, anim: Animation, hinge: Node3D) -> void:
	var track := _track_for(anim, hinge.name)
	if track < 0:
		entry.ouvrable = false
		entry.start = hinge.quaternion
		entry.end = hinge.quaternion
		entry.duration = 0.0
		return
	var keys := anim.track_get_key_count(track)
	entry.start = anim.track_get_key_value(track, 0)
	entry.end = anim.track_get_key_value(track, keys - 1)
	entry.duration = maxf(anim.track_get_key_time(track, keys - 1) - anim.track_get_key_time(track, 0), 0.1)


func _collect_radiators() -> void:
	if not _library.has_animation(ANIM_RADIATORS):
		return
	var anim := _library.get_animation(ANIM_RADIATORS)
	for id in RADIATOR_IDS:
		var tracks: Array[int] = []
		for t in anim.get_track_count():
			if String(anim.track_get_path(t)).begins_with(id + "/"):
				tracks.append(t)
		if not tracks.is_empty():
			_radiators[id] = {"tracks": tracks, "is_deployed": true, "tween": null}


## Calques et lampes intérieures. Un maillage entièrement intérieur passe sur INTERIOR_LAYER ; un maillage mixte (coques :
## surfaces Coque_Silo dehors, Int_Coque dedans) est doublé : l'original ne garde que ses surfaces extérieures, la copie
## (même maillage, LOD compris, sans ombre portée) ses surfaces intérieures, sur INTERIOR_LAYER.
func _setup_interior_lighting() -> void:
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
	for light: OmniLight3D in find_children("Lum_*", "OmniLight3D", true, false):
		light.light_cull_mask = INTERIOR_LAYER
		light.light_energy = interior_light_energy
		light.omni_range = interior_light_range
		light.omni_attenuation = interior_light_attenuation
		light.light_color = Color.WHITE
		light.light_temperature = interior_light_temperature
		light.light_specular = interior_light_specular
		light.shadow_enabled = interior_shadows
		_interior_lights.append(light)
	var done := {}
	for mesh_instance: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(s) as BaseMaterial3D
			if material == null or not material.emission_enabled or done.has(material):
				continue
			var lamp := material.resource_name.begins_with("Int_Lumiere")
			var screen := material.resource_name.begins_with("Ecran_")
			if not lamp and not screen:
				continue
			done[material] = true
			if not material.has_meta(&"base_emission"):
				material.set_meta(&"base_emission", material.emission_energy_multiplier)
				material.set_meta(&"base_emission_color", material.emission)
				material.set_meta(&"base_albedo", material.albedo_color)
			if lamp:
				_lamp_materials.append(material)
			else:
				_screen_materials.append(material)
	_update_interior_light(0.0)


## Niveau d'alerte de la station (couleur des luminaires), voir alert_colors.
func set_alert(level: Alert) -> void:
	_alert = level


func get_alert() -> Alert:
	return _alert


## Puissance des luminaires intérieurs, comme un potentiomètre : réglage du modèle × GameSettings.interior_light
## (paramètre « Éclairage intérieur », valeur de jour) × night_light_ratio dans l'ombre de la Terre (fondu avec
## l'ensoleillement), sur la lumière projetée (Lum_*) et sur l'émission propre des luminaires (matériaux Int_Lumiere*,
## dont le halo de glow suit l'émission). Les matériaux du modèle sont partagés et persistent d'une partie à l'autre :
## l'émission d'origine est gardée en métadonnée. Teinte d'alerte fondue en alert_fade_s, pulsation en alerte rouge.
## Appliquée à chaque image seulement si le facteur ou la teinte a changé.
func _update_interior_light(delta: float) -> void:
	var sunlight := _orbit.get_sunlight_fraction() if _orbit else 1.0
	var factor := GameSettings.interior_light * lerpf(night_light_ratio, 1.0, sunlight)
	# Fondus (teinte, extinction) : l'état avance à chaque image et s'accroche à la cible une fois tout près — sinon,
	# à haute cadence, les petits pas par image bloquaient le fondu à mi-course.
	var target := alert_colors[_alert] if _alert < alert_colors.size() else Color.WHITE
	var blend := 1.0 - exp(-delta / maxf(alert_fade_s, 1e-3)) if delta > 0.0 else 1.0
	_alert_tint = target if _alert_tint.is_equal_approx(target) else _alert_tint.lerp(target, blend)
	if _alert == Alert.RED:
		_alert_time += delta
		factor *= 1.0 - 0.5 * red_alert_pulse * (1.0 - cos(TAU * _alert_time / maxf(red_alert_period_s, 0.1)))
	else:
		_alert_time = 0.0
	# Extinction (« plus de lumière ») : les luminaires s'éteignent pendant que les LED de secours s'allument.
	var dark_target := 1.0 if _alert == Alert.BLACKOUT else 0.0
	_dark = dark_target if absf(_dark - dark_target) < 0.001 else lerpf(_dark, dark_target, blend)
	var tint := _alert_tint
	var dark := _dark
	factor *= 1.0 - dark
	# Application seulement si quelque chose a changé depuis la dernière application.
	if absf(factor - _applied_factor) < 0.001 and tint.is_equal_approx(_applied_tint) and absf(dark - _applied_dark) < 0.001:
		return
	_applied_factor = factor
	_applied_tint = tint
	_applied_dark = dark
	_light_factor = factor
	if _environment:
		_environment.ambient_light_energy = float(_environment.get_meta(&"base_ambient_energy")) * (1.0 - dark)
	for i in _interior_lights.size():
		var light := _interior_lights[i]
		var emergency := dark * emergency_light_energy if i % maxi(emergency_light_every, 1) == 0 else 0.0
		light.light_energy = interior_light_energy * factor + emergency
		light.light_color = tint.lerp(emergency_light_color, dark)
	for material in _lamp_materials:
		material.emission_energy_multiplier = float(material.get_meta(&"base_emission")) * factor
		# Seuls les luminaires blancs changent de couleur (les feux rouges des rails gardent la leur).
		if material.resource_name == "Int_Lumiere":
			material.emission = (material.get_meta(&"base_emission_color") as Color) * tint
		# Éteint, un luminaire est gris sombre (son albédo blanc paraîtrait encore allumé sous les LED de secours).
		material.albedo_color = (material.get_meta(&"base_albedo") as Color).lerp(Color(0.06, 0.06, 0.06), dark)
	for material in _screen_materials:
		material.emission_energy_multiplier = float(material.get_meta(&"base_emission")) * (1.0 - dark)
		material.albedo_color = (material.get_meta(&"base_albedo") as Color).lerp(Color(0.02, 0.02, 0.02), dark)


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


# --- Outils ---------------------------------------------------------------------------------------------------------

## Charnière tournée de son angle courant vers target (durée de l'animation), puis done.
func _tween_hinge(entry: Dictionary, target: Quaternion, done: Callable) -> void:
	if entry.tween:
		entry.tween.kill()
	var hinge: Node3D = entry.hinge
	var start := hinge.quaternion
	entry.tween = create_tween()
	entry.tween.tween_method(func(w: float) -> void: hinge.quaternion = start.slerp(target, w), 0.0, 1.0,
			entry.duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	entry.tween.tween_callback(func() -> void:
		entry.tween = null
		done.call())


## Rejoue les pistes tracks de anim de from_s à to_s (à l'envers si to_s < from_s) en duration secondes.
func _play_tracks(anim: Animation, tracks: Array[int], from_s: float, to_s: float, duration: float) -> Tween:
	var targets: Array[Node3D] = []
	for t in tracks:
		targets.append(get_node_or_null(anim.track_get_path(t)) as Node3D)
	var tween := create_tween()
	tween.tween_method(func(time: float) -> void:
		for i in tracks.size():
			if targets[i]:
				_apply_track(anim, tracks[i], targets[i], time), from_s, to_s, duration)
	return tween


func _apply_track(anim: Animation, track: int, node: Node3D, time: float) -> void:
	match anim.track_get_type(track):
		Animation.TYPE_ROTATION_3D:
			node.quaternion = anim.rotation_track_interpolate(track, time)
		Animation.TYPE_POSITION_3D:
			node.position = anim.position_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			node.scale = anim.scale_track_interpolate(track, time)


## Animation complète (à l'envers si backwards), puis done.
func _play_group(anim_name: StringName, backwards: bool, done: Callable) -> void:
	var player: AnimationPlayer = _players[anim_name]
	if backwards:
		player.play_backwards(anim_name)
	else:
		player.play(anim_name)
	player.animation_finished.connect(func(_name: StringName) -> void: done.call(), CONNECT_ONE_SHOT)


## Nombre de charnières animées par l'animation (pistes de rotation).
func _animated_count(anim_name: StringName) -> int:
	if not _library.has_animation(anim_name):
		return 0
	var anim := _library.get_animation(anim_name)
	var count := 0
	for t in anim.get_track_count():
		count += 1 if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D else 0
	return count


## Piste de l'animation pour le nœud node_path (et du type donné, -1 : n'importe lequel), ou -1.
func _track_for(anim: Animation, node_path: String, type := -1) -> int:
	for t in anim.get_track_count():
		if String(anim.track_get_path(t)) == node_path and (type < 0 or anim.track_get_type(t) == type):
			return t
	return -1


## Instant du relais vers le vol (MissileFlight) dans Lancement_Missile : la dernière clé à pleine échelle avant que
## le missile ne s'annule (fin de la ligne droite Blender, ~30 m sous la station), pour ne jamais le voir rétrécir.
func _handoff_time(anim: Animation, scale_track: int) -> float:
	if scale_track < 0:
		return anim.length
	for k in anim.track_get_key_count(scale_track):
		if (anim.track_get_key_value(scale_track, k) as Vector3).x < 1e-3:
			if k > 0 and (anim.track_get_key_value(scale_track, k - 1) as Vector3).x > 0.999:
				return anim.track_get_key_time(scale_track, k - 1)
			return anim.track_get_key_time(scale_track, k)
	return anim.length


func _missile_template() -> Node3D:
	return get_node_or_null(MODEL_MISSILE) as Node3D
