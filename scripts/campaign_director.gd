class_name CampaignDirector
extends Node
## Déroulement d'une campagne (nœud CampaignDirector de scenes/orbit_view.tscn), actif seulement en mode campagne
## (Campaigns.mode, choisi à l'écran de démarrage) ; en mode libre, il ne fait rien. Règles de jeu :
## - début de journée : départ appliqué (CampaignData.start_of_day : heure UTC, altitude, inclinaison, point survolé,
##   sens de passage, OrbitSimulation.place ; la manœuvre en préparation est annulée), puis briefing de la première
##   mission dont la condition est vraie ;
## - briefing : message radio (RadioComms.post ; expéditeur et canal de la mission, sinon defaults) au gabarit
##   BRIEFING_BODY : mission, objectif, texte, cibles (type et coordonnées), durée avant échec. Le chrono de la mission
##   part MissionScoring.START_GRACE_S (10 min de jeu) après l'arrivée du briefing, lu ou non : au réveil pour la
##   première mission de la journée, à la fin de la précédente pour les suivantes (le temps de se promener un peu) ;
## - temps de référence (par_hours, sinon calculé à l'arrivée du briefing, MissionPlanner) : passage le plus tôt
##   possible pour tous les objectifs, manœuvres comprises, compté depuis le départ du chrono, plus une orbite ; au plus
##   l'échéance (mission impossible à temps : pas de pénalité de temps) ;
## - objectifs : une photo (PhotoArchive.photo_taken : point sous la station) ou un impact (NukeLauncher.detonated)
##   à moins de la tolérance d'une cible de la mission remplit son objectif (le premier objectif encore ouvert de ce
##   type, dont l'objectif préalable « after » est rempli), avec la précision obtenue (MissionScoring) ; plus loin, il
##   ne compte pas ;
## - fin de mission : tous les objectifs remplis, ou échéance (deadline_hours après le départ du chrono) : note =
##   précision pondérée × facteur temps (MissionScoring), réussite si ≥ success_score ; résultat retenu (Campaigns.results,
##   moyenne globale) et message radio de résultat (message « result » de la mission choisi selon la note, sinon
##   RESULT_DEFAULT_*), puis briefing de la mission suivante de la journée dont la condition est vraie ;
## - fin de journée (plus de mission) : note de la journée retenue, message « debrief » de la journée (selon les
##   notes) ; à la dernière journée, message de fin de campagne (« ending », selon la moyenne globale) ;
## - après la fin de journée, promenade libre : la couchette (Interactif_Couchette) devient cliquable, « Dormir »
##   (HatchInteraction, can_sleep) : fondu au noir (WakeUp.fall_asleep), réveil dans la couchette (Observer, point
##   de départ) au départ de la journée suivante : le sien s'il est défini, sinon la station a continué son orbite
##   jusqu'à l'heure de réveil (wake_up_utc, le lendemain si elle est passée ; sans heure de réveil,
##   CampaignData.NIGHT_HOURS de sommeil) ; « Jour n » et ouverture des paupières (WakeUp.play ; au lancement, WakeUp joue lui-même le réveil).
##   Après la dernière journée, dormir termine la campagne : sauvegarde effacée, écran de fin de campagne
##   (scenes/ui/campaign_end_screen.tscn : message de fin, moyenne globale, notes par journée et par mission), puis
##   écran de démarrage. Sauvegarde au coucher (Campaigns.save).

signal day_started(day_index: int)
signal mission_started(mission_id: String)
signal mission_finished(mission_id: String, result: Dictionary)
signal day_finished(day_index: int)

const GROUP := &"campaign_director"
const END_SCENE := "res://scenes/ui/campaign_end_screen.tscn"

@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"
@export var radio_path: NodePath = ^"../Radio"
@export var photos_path: NodePath = ^"../Photos"
@export var launcher_path: NodePath = ^"../NukeLauncher"

var _orbit: OrbitSimulation
var _flight_computer: FlightComputer
var _radio: RadioComms
## Mission en cours : identifiant, départ du chrono (heure UTC, s), temps de référence (s), précisions des objectifs
## (NAN : pas rempli).
var _mission_id := ""
var _started_unix := 0.0
var _par := 0.0
var _precisions: Array = []
## Prochaine entrée à examiner dans la liste des missions de la journée.
var _next_entry := 0
## Journée terminée (couchette cliquable) ; sommeil en cours (fondu).
var _day_over := false
var _sleeping := false


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_flight_computer = get_node_or_null(flight_computer_path) as FlightComputer
	_radio = get_node_or_null(radio_path) as RadioComms
	if not is_active():
		set_process(false)
		return
	var photos := get_node_or_null(photos_path) as PhotoArchive
	if photos:
		photos.photo_taken.connect(func(photo: Dictionary) -> void:
			_record("photo", float(photo.lat), float(photo.lon)))
	var launcher := get_node_or_null(launcher_path) as NukeLauncher
	if launcher:
		launcher.detonated.connect(func(effect: NukeEffect) -> void:
			# Une explosion recréée au chargement n'est pas un tir : elle ne remplit aucun objectif.
			if effect.params and not effect.params.restored:
				_record("strike", effect.params.latitude_deg, effect.params.longitude_deg))
	# Après la mise en place de l'orbite (son _ready) : monde d'une sauvegarde recréé (« Continuer »), puis journée.
	if not Campaigns.pending_world.is_empty():
		_restore_world.call_deferred(Campaigns.pending_world)
		Campaigns.pending_world = {}
	start_day.call_deferred(Campaigns.day_index)


func is_active() -> bool:
	return Campaigns.mode == Campaigns.Mode.CAMPAIGN and Campaigns.current != null


## Mission en cours ("" : aucune).
func current_mission() -> String:
	return _mission_id


## Commence la journée day_index : départ appliqué s'il est défini (sinon, la station reste où elle est), puis
## première mission.
func start_day(day_index: int) -> void:
	if not is_active() or day_index < 0 or day_index >= Campaigns.current.days().size():
		return
	Campaigns.day_index = day_index
	apply_start(Campaigns.current.start_of_day(day_index))
	_next_entry = 0
	_day_over = false
	day_started.emit(day_index)
	_next_mission()


## Place la station selon un départ (format de CampaignData) ; rien si start est vide.
func apply_start(start: Dictionary) -> void:
	if start.is_empty() or _orbit == null:
		return
	var orbit: Dictionary = start.orbit
	var over: Dictionary = orbit.over
	_orbit.place(CampaignData.parse_utc(str(start.utc)), float(orbit.altitude_km), float(orbit.inclination_deg),
			float(over.lat), float(over.lon), bool(orbit.get("ascending", true)))
	if _flight_computer:
		_flight_computer.reset_target()


func _process(_delta: float) -> void:
	if _mission_id.is_empty() or _orbit == null:
		return
	if _orbit.get_utc_unix_s() - _started_unix >= _deadline_s(_mission()):
		_finish_mission()


# --- Missions -------------------------------------------------------------------------------------------------------

## Mission suivante de la journée dont la condition est vraie, sinon fin de journée.
func _next_mission() -> void:
	var day := _day()
	var entries: Array = day.get("missions", [])
	while _next_entry < entries.size():
		var entry: Dictionary = entries[_next_entry]
		_next_entry += 1
		if CampaignData.check(entry.get("when", {}), Campaigns.scores(day.id, "")):
			_start_mission(str(entry.mission))
			return
	_finish_day()


func _start_mission(id: String) -> void:
	_mission_id = id
	var mission := _mission()
	_started_unix = (_orbit.get_utc_unix_s() if _orbit else 0.0) + MissionScoring.START_GRACE_S
	_par = _par_s(mission)
	_precisions = []
	for _objective in mission.objectives:
		_precisions.append(NAN)
	_post(mission, tr("BRIEFING_SUBJECT").format({"title": _text(mission, "title")}), _briefing_body(mission))
	mission_started.emit(id)


## Photo ou impact en (lat, lon) : remplit le premier objectif ouvert de ce type à portée (son préalable rempli).
## Pendant le délai avant le chrono aussi.
func _record(type: String, lat: float, lon: float) -> void:
	if _mission_id.is_empty():
		return
	var objectives: Array = _mission().objectives
	for k in objectives.size():
		var objective: Dictionary = objectives[k]
		if objective.type != type or not is_nan(_precisions[k]):
			continue
		if objective.has("after") and is_nan(_precisions[int(objective.after)]):
			continue
		var d := MissionScoring.distance_km(lat, lon, float(objective.target.lat), float(objective.target.lon))
		var tolerance := _tolerance_km(objective)
		if d < tolerance:
			_precisions[k] = MissionScoring.precision(d, tolerance)
			break
	if not _precisions.any(func(p: float) -> bool: return is_nan(p)):
		_finish_mission()


func _finish_mission() -> void:
	var mission := _mission()
	var defaults := Campaigns.current.defaults()
	var weights: Array = mission.objectives.map(func(o: Dictionary) -> float: return float(o.get("weight", 1.0)))
	var precision := MissionScoring.mission_precision(_precisions, weights)
	var elapsed := _orbit.get_utc_unix_s() - _started_unix
	var factor := MissionScoring.time_factor(elapsed, _par, _deadline_s(mission),
			float(defaults.get("time_floor", 0.6)))
	var score := precision * factor
	var success := score >= float(defaults.get("success_score", 10.0))
	var day_id: String = _day().id
	var result := {"score": score, "success": success, "precision": precision, "time_factor": factor, "day": day_id}
	var id := _mission_id
	Campaigns.results[id] = result
	_mission_id = ""
	var message := CampaignData.pick_message(mission.get("result", []), Campaigns.scores(day_id, id))
	var verdict := tr("RESULT_SUCCESS") if success else tr("RESULT_FAILURE")
	var text := Campaigns.text_of(message, "body") if not message.is_empty() \
			else tr("RESULT_DEFAULT_SUCCESS" if success else "RESULT_DEFAULT_FAILURE")
	_post(mission, tr("RESULT_SUBJECT").format({"title": _text(mission, "title")}),
			tr("RESULT_BODY").format({"message": text, "score": "%.1f" % score, "verdict": verdict,
			"precision": "%.1f" % precision, "time": "%.2f" % factor}))
	mission_finished.emit(id, result)
	_next_mission()


func _finish_day() -> void:
	var day := _day()
	var scores := Campaigns.scores(day.id, "")
	if scores.day_score != null:
		Campaigns.day_scores[day.id] = scores.day_score
	var debrief := CampaignData.pick_message(day.get("debrief", []), scores)
	if not debrief.is_empty():
		_post({}, Campaigns.text_of(debrief, "subject", "BRIEFING_DEBRIEF"), Campaigns.text_of(debrief, "body"))
	if Campaigns.day_index == Campaigns.current.days().size() - 1:
		var ending := CampaignData.pick_message(Campaigns.current.data.get("ending", []), scores)
		if not ending.is_empty():
			_post({}, Campaigns.text_of(ending, "subject", "BRIEFING_DEBRIEF"), Campaigns.text_of(ending, "body"))
	_day_over = true
	day_finished.emit(Campaigns.day_index)


# --- Sommeil --------------------------------------------------------------------------------------------------------

## La couchette est-elle cliquable (« Dormir ») ? Journée terminée, pas déjà en train de dormir.
func can_sleep() -> bool:
	return is_active() and _day_over and not _sleeping


## Dormir : fondu au noir (WakeUp), journée suivante, réveil dans la couchette (WakeUp.play, titre « Jour n ») ;
## après la dernière, écran de fin de campagne (il vide les notes de Campaigns au retour au menu).
func sleep() -> void:
	if not can_sleep():
		return
	_sleeping = true
	var wake := _wake_up()
	if wake:
		await wake.fall_asleep()
	var next := Campaigns.day_index + 1
	if next >= Campaigns.current.days().size():
		Campaigns.delete_save()
		get_tree().change_scene_to_file(END_SCENE)
		return
	_advance_to_wake_up(next)
	# Sauvegarde au coucher (règle de jeu) : journée à venir, notes, monde au réveil.
	Campaigns.day_index = next
	Campaigns.save(_capture_world())
	start_day(next)
	var observer := get_tree().current_scene.get_node_or_null("Observer")
	if observer and observer.has_method(&"_place_at_start"):
		observer.call(&"_place_at_start")
	if wake:
		await wake.play(tr("DAY_TITLE").format({"n": next + 1}))
	_sleeping = false


func _wake_up() -> WakeUp:
	return get_tree().get_first_node_in_group(WakeUp.GROUP) as WakeUp


## Monde à sauvegarder : orbite au réveil (heure UTC, altitude, inclinaison, point survolé, sens de passage),
## explosions (point, puissance, âge sur l'horloge des explosions, heure UTC), photos, cibles.
func _capture_world() -> Dictionary:
	var world := {}
	if _orbit:
		var point := _orbit.get_subsatellite_point()
		world.orbit = {"utc": _orbit.get_utc_unix_s(), "altitude_km": _orbit.altitude_km,
				"inclination_deg": _orbit.inclination_deg, "lat": point.x, "lon": point.y,
				"ascending": _orbit.is_ascending()}
	var launcher := get_node_or_null(launcher_path) as NukeLauncher
	if launcher:
		world.detonations = []
		for effect in launcher.get_effects():
			var p := effect.params
			if p:
				world.detonations.append({"lat": p.latitude_deg, "lon": p.longitude_deg, "yield_kt": p.yield_kt,
						"clock_age_s": NukeClock.time_s - p.start_time_s, "utc": p.detonation_utc_s})
	var photos := get_node_or_null(photos_path) as PhotoArchive
	if photos:
		world.photos = photos.to_save()
	var targets := get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
	if targets:
		world.targets = targets.to_save()
	return world


## Recrée le monde d'une sauvegarde (_capture_world) : orbite, explosions avec leur âge, photos, cibles.
func _restore_world(world: Dictionary) -> void:
	var orbit: Dictionary = world.get("orbit", {})
	if _orbit and not orbit.is_empty():
		_orbit.place(float(orbit.utc), float(orbit.altitude_km), float(orbit.inclination_deg), float(orbit.lat),
				float(orbit.lon), bool(orbit.ascending))
	var launcher := get_node_or_null(launcher_path) as NukeLauncher
	if launcher:
		for d: Dictionary in world.get("detonations", []):
			launcher.restore_at(float(d.lat), float(d.lon), float(d.yield_kt), float(d.clock_age_s), float(d.utc))
	var photos := get_node_or_null(photos_path) as PhotoArchive
	if photos and world.has("photos"):
		photos.restore(world.photos)
	var targets := get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
	if targets and world.has("targets"):
		targets.restore(world.targets)


## Nuit : sans départ propre, la station continue son orbite jusqu'au réveil (wake_up_utc de la journée suivante, le
## lendemain si l'heure est passée ; sinon CampaignData.NIGHT_HOURS).
func _advance_to_wake_up(day_index: int) -> void:
	var day: Dictionary = Campaigns.current.days()[day_index]
	if day.has("start") or _orbit == null:
		return
	var now := _orbit.get_utc_unix_s()
	var sleep_s := CampaignData.NIGHT_HOURS * 3600.0
	if day.has("wake_up_utc"):
		var parts := str(day.wake_up_utc).split(":")
		var wake := floorf(now / 86400.0) * 86400.0 + int(parts[0]) * 3600.0 + int(parts[1]) * 60.0
		if wake <= now:
			wake += 86400.0
		sleep_s = wake - now
	_orbit.sim_time_s += sleep_s
	# Les explosions vieillissent aussi pendant la nuit (incendies, fumées).
	NukeClock.time_s += sleep_s



# --- Messages -------------------------------------------------------------------------------------------------------

## Briefing selon le gabarit : mission, objectif, texte, cibles (type et coordonnées), durée avant échec.
func _briefing_body(mission: Dictionary) -> String:
	var targets := PackedStringArray()
	for objective: Dictionary in mission.objectives:
		var kind := tr("OBJECTIVE_PHOTO" if objective.type == "photo" else "OBJECTIVE_STRIKE")
		targets.append("  %s : %s" % [kind, GroundTarget.format(float(objective.target.lat),
				float(objective.target.lon))])
	# Durée avant échec, toujours avec les minutes : « 6 h 00 min », « 5 h 30 min ».
	var minutes := roundi(_deadline_s(mission) / 60.0)
	var duration := "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]
	return tr("BRIEFING_BODY").format({"title": _text(mission, "title"), "objective": _text(mission, "objective"),
			"description": _text(mission, "description"), "targets": "\n".join(targets), "duration": duration,
			"grace": roundi(MissionScoring.START_GRACE_S / 60.0)})


## Message radio de la campagne (expéditeur et canal de la mission, sinon defaults) ; rend son identifiant.
func _post(mission: Dictionary, subject: String, body: String) -> String:
	if _radio == null:
		return ""
	var defaults := Campaigns.current.defaults()
	return _radio.post({"from": mission.get("from", defaults.get("from", "COMM_FROM_GROUND")), "subject": subject,
			"body": body, "channel": int(mission.get("channel", defaults.get("channel", -1)))})


func _text(mission: Dictionary, field: String) -> String:
	return Campaigns.text_of(mission, field)


func _day() -> Dictionary:
	return Campaigns.current.days()[Campaigns.day_index]


func _mission() -> Dictionary:
	return Campaigns.current.mission(_mission_id)


func _tolerance_km(objective: Dictionary) -> float:
	var defaults: Dictionary = Campaigns.current.defaults().get("tolerance_km", {})
	var fallback := 40.0 if objective.type == "photo" else 15.0
	return float(objective.get("tolerance_km", defaults.get(objective.type, fallback)))


## Échéance (s) : deadline_hours et deadline_minutes (facultatif) additionnés.
func _deadline_s(mission: Dictionary) -> float:
	return float(mission.get("deadline_hours", 0.0)) * 3600.0 + float(mission.get("deadline_minutes", 0.0)) * 60.0


## Temps de référence (s, depuis le départ du chrono) : par_hours, sinon passage le plus tôt possible depuis
## maintenant (arrivée du briefing, MissionPlanner) plus une orbite ; au plus l'échéance.
func _par_s(mission: Dictionary) -> float:
	var deadline := _deadline_s(mission)
	var par: Variant = mission.get("par_hours", null)
	if par != null:
		return float(par) * 3600.0
	if _orbit == null:
		return deadline
	var state := MissionPlanner.state_of(_orbit)
	var plan := MissionPlanner.earliest(state, mission.objectives, 0.0, MissionScoring.START_GRACE_S + deadline)
	if plan.time == INF:
		return deadline
	return minf(maxf(plan.time - MissionScoring.START_GRACE_S, 0.0) + MissionPlanner.period_s(state), deadline)
