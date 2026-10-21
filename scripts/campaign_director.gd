class_name CampaignDirector
extends Node
## Déroulement d'une campagne (nœud CampaignDirector de scenes/orbit_view.tscn), actif seulement en mode campagne
## (Campaigns.mode, choisi à l'écran de démarrage) ; en mode libre, il ne fait rien. Règles de jeu :
## - début de journée : départ appliqué (CampaignData.start_of_day) : avec orbit, heure UTC et position exactes
##   (altitude, inclinaison, point survolé, sens de passage, OrbitSimulation.place) ; sans orbit, saut dans le temps
##   jusqu'à cette date, la station continuant son orbite (ignoré si la date est déjà passée). La manœuvre en
##   préparation est annulée ; les explosions vieillissent d'autant (NukeClock). Puis la première mission dont la
##   condition est vraie est programmée ;
## - briefing : il arrive à l'heure de la mission (briefing_utc, sinon briefing_delay_minutes après le réveil ou la fin
##   de la précédente : CampaignData.briefing_unix) ; avant, aucune mission n'est en cours (promenade libre). À cette
##   heure, le sol l'envoie : message radio (RadioComms.post ; expéditeur et canal de la mission, sinon defaults) au
##   gabarit BRIEFING_BODY (mission, objectif, texte, cibles, durée avant échec), qui n'arrive qu'avec la liaison
##   (station au sol en vue, bon canal). À sa réception : appel prioritaire (PriorityCall : sonnerie, luminaires
##   orange, bandeau) jusqu'à sa lecture, temps ramené à ×1, et **le chrono de la mission part** ;
## - temps de référence (par_hours, sinon calculé à l'arrivée du briefing, MissionPlanner) : passage le plus tôt
##   possible pour tous les objectifs, manœuvres comprises, plus une orbite ; au plus l'échéance (mission impossible
##   à temps : pas de pénalité de temps) ;
## - objectifs : une photo (PhotoArchive.photo_taken : point sous la station) ou un impact (NukeLauncher.detonated)
##   à moins de la tolérance d'une cible de la mission remplit son objectif (le premier objectif encore ouvert de ce
##   type, dont l'objectif préalable « after » est rempli), avec la précision obtenue (MissionScoring) ; plus loin, il
##   ne compte pas ;
## - fin de mission : tous les objectifs remplis, ou échéance (deadline_hours après l'arrivée du briefing) : note =
##   précision pondérée × facteur temps (MissionScoring), réussite si ≥ success_score ; résultat retenu (Campaigns.results,
##   moyenne globale) et message radio de résultat (message « result » de la mission choisi selon la note, sinon
##   RESULT_DEFAULT_*), puis la mission suivante de la journée dont la condition est vraie est programmée ;
## - fin de journée (plus de mission) : note de la journée retenue, message « debrief » de la journée (selon les
##   notes) ; à la dernière journée, message de fin de campagne (« ending », selon la moyenne globale) ;
## - après la fin de journée, promenade libre : la couchette (Interactif_Couchette) devient cliquable, « Dormir »
##   (HatchInteraction, can_sleep) : fondu au noir (WakeUp.fall_asleep), réveil dans la couchette (Observer, point
##   de départ) au départ de la journée suivante : le sien s'il est défini, sinon la station a continué son orbite
##   jusqu'à l'heure de réveil (wake_up_utc, le lendemain si elle est passée ; sans heure de réveil,
##   CampaignData.NIGHT_HOURS de sommeil) ; « Jour n », date, heure UTC et point survolé (day_heading), puis
##   ouverture des paupières (WakeUp.play ; au lancement, WakeUp joue lui-même le réveil).
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
## Mission en cours : identifiant, départ du chrono (heure UTC, s), temps de référence (s, depuis le départ du chrono),
## passage le plus tôt possible (s, depuis l'arrivée du briefing ; INF : impossible à temps), précisions des
## objectifs (NAN : pas rempli).
var _mission_id := ""
var _briefing_id := ""
var _started_unix := 0.0
var _par := 0.0
var _earliest := INF
var _precisions: Array = []
## Journal de partie (scripts/campaign_journal.gd) ; partie reprise d'une sauvegarde (« Continuer »), journal
## commencé (événement session, à la première journée, une fois l'orbite en place).
var _journal: CampaignJournal
var _continued := false
var _session_logged := false
## Mission programmée (briefing pas encore arrivé, "" : aucune) et heure d'arrivée de son briefing (UTC, s).
var _scheduled_id := ""
var _briefing_unix := 0.0
## Appel prioritaire à l'arrivée d'un briefing.
var _call: PriorityCall
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
	_journal = CampaignJournal.new(Campaigns.current_id)
	_continued = not Campaigns.pending_world.is_empty()
	_call = PriorityCall.new()
	_call.name = "PriorityCall"
	add_child(_call)
	if _radio:
		_radio.message_read.connect(_on_message_read)
		_radio.message_received.connect(_on_message_received)
	if _flight_computer:
		_flight_computer.burn_finished.connect(func(quality: int, ratio: float) -> void:
			_journal.write("burn", _now(), {"mission": _mission_id,
					"quality": FlightComputer.BurnQuality.keys()[quality].to_lower(), "ratio": ratio,
					"auto": _flight_computer.mode == FlightComputer.Mode.AUTO}))
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
## première mission programmée.
func start_day(day_index: int) -> void:
	if not is_active() or day_index < 0 or day_index >= Campaigns.current.days().size():
		return
	Campaigns.day_index = day_index
	var start := Campaigns.current.start_of_day(day_index)
	# Première journée sans orbite propre : départ de la campagne, puis saut à sa date.
	if day_index == 0 and not start.has("orbit"):
		apply_start(Campaigns.current.data.get("start", {}))
	apply_start(start)
	_next_entry = 0
	_day_over = false
	if not _session_logged:
		_session_logged = true
		_journal.write("session", _now(), {"campaign": Campaigns.current_id, "day_index": day_index,
				"continued": _continued})
	_journal.write("day_start", _now(), {"day": _day().id, "day_index": day_index})
	day_started.emit(day_index)
	_next_mission()


## Applique un départ (format de CampaignData) ; rien si start est vide. Avec orbit : station placée à l'heure et à la
## position données ; sans : saut dans le temps jusqu'à la date (orbite poursuivie), ignoré si elle est passée. Les
## explosions vieillissent du temps sauté.
func apply_start(start: Dictionary) -> void:
	if start.is_empty() or _orbit == null:
		return
	var utc := CampaignData.parse_utc(str(start.utc))
	var jump := utc - _orbit.get_utc_unix_s()
	if start.has("orbit"):
		var orbit: Dictionary = start.orbit
		var over: Dictionary = orbit.over
		_orbit.place(utc, float(orbit.altitude_km), float(orbit.inclination_deg), float(over.lat), float(over.lon),
				bool(orbit.get("ascending", true)))
		if jump > 0.0:
			NukeClock.time_s += jump
	elif jump > 0.0:
		_advance(jump)
	if _flight_computer:
		_flight_computer.reset_target()


## Le temps passe de seconds secondes d'un coup (nuit, saut dans le temps) : orbite et explosions.
func _advance(seconds: float) -> void:
	_orbit.sim_time_s += seconds
	NukeClock.time_s += seconds


func _process(_delta: float) -> void:
	if _orbit == null:
		return
	if not _scheduled_id.is_empty() and _briefing_id.is_empty() and _now() >= _briefing_unix:
		_send_briefing()
	if not _mission_id.is_empty() and _now() - _started_unix >= _deadline_s(_mission()):
		_finish_mission()


## Ligne du réveil : date, heure UTC et point survolé (« 24 octobre 2035 — 11 h 15 UTC — 40.40° N  3.70° O »).
func day_heading() -> String:
	if _orbit == null:
		return ""
	var now := _orbit.get_utc_datetime()
	var point := _orbit.get_subsatellite_point()
	return tr("WAKE_HEADING").format({"day": now.day, "month": tr("MONTH_%d" % now.month), "year": now.year,
			"hour": "%02d" % now.hour, "minute": "%02d" % now.minute,
			"position": GroundTarget.format(point.x, point.y)})


# --- Missions -------------------------------------------------------------------------------------------------------

## Mission suivante de la journée dont la condition est vraie, programmée à l'heure de son briefing ; sinon fin de
## journée.
func _next_mission() -> void:
	var day := _day()
	var entries: Array = day.get("missions", [])
	while _next_entry < entries.size():
		var entry: Dictionary = entries[_next_entry]
		_next_entry += 1
		if CampaignData.check(entry.get("when", {}), Campaigns.scores(day.id, "")):
			_scheduled_id = str(entry.mission)
			_briefing_unix = Campaigns.current.briefing_unix(entry, _now())
			_journal.write("mission_scheduled", _now(), {"mission": _scheduled_id, "briefing_unix": _briefing_unix})
			return
	_finish_day()


## Heure du briefing : il est envoyé par le sol ; il n'arrive qu'avec la liaison radio (station au sol en vue, canal :
## RadioComms), et c'est à sa réception que la mission commence.
func _send_briefing() -> void:
	var mission := Campaigns.current.mission(_scheduled_id)
	_journal.write("briefing_sent", _now(), {"mission": _scheduled_id})
	_briefing_id = _post(mission, tr("BRIEFING_SUBJECT").format({"title": _text(mission, "title")}),
			_briefing_body(mission))
	# Reçu aussitôt (liaison établie : message_received émis pendant post, avant que l'identifiant soit connu).
	if _radio == null or not _radio.find(_briefing_id).is_empty():
		_start_mission()


func _on_message_received(message: Dictionary) -> void:
	if not _scheduled_id.is_empty() and not _briefing_id.is_empty() and message.get("id", "") == _briefing_id:
		_start_mission()


## Réception du briefing : la mission programmée commence (chrono), appel prioritaire, temps ramené à ×1.
func _start_mission() -> void:
	var id := _scheduled_id
	_scheduled_id = ""
	_mission_id = id
	var mission := _mission()
	_started_unix = _now()
	_plan(mission)
	_precisions = []
	for _objective in mission.objectives:
		_precisions.append(NAN)
	_journal.write("mission_start", _now(), {"mission": id, "deadline_s": _deadline_s(mission), "par_s": _par,
			"earliest_s": _earliest if _earliest < INF else -1.0,
			"altitude_km": _orbit.altitude_km if _orbit else 0.0,
			"inclination_deg": _orbit.inclination_deg if _orbit else 0.0, "time_scale": _orbit.time_scale})
	if _orbit:
		_orbit.time_scale = 1.0
	_call.ring()
	mission_started.emit(id)


## Briefing lu (écran de communication) : fin de l'appel prioritaire.
func _on_message_read(message_id: String) -> void:
	if message_id.is_empty() or message_id != _briefing_id:
		return
	_briefing_id = ""
	_call.stop()
	_journal.write("briefing_read", _now(), {"mission": _mission_id, "elapsed_s": _now() - _started_unix})


## Photo ou impact en (lat, lon) : remplit le premier objectif ouvert de ce type à portée (son préalable rempli).
func _record(type: String, lat: float, lon: float) -> void:
	if _mission_id.is_empty():
		return
	var objectives: Array = _mission().objectives
	# Journal : distance à la cible de ce type la plus proche, objectif rempli (−1 : aucun).
	var nearest := INF
	var filled := -1
	for k in objectives.size():
		var objective: Dictionary = objectives[k]
		if objective.type != type:
			continue
		var d := MissionScoring.distance_km(lat, lon, float(objective.target.lat), float(objective.target.lon))
		nearest = minf(nearest, d)
		if filled >= 0 or not is_nan(_precisions[k]):
			continue
		if objective.has("after") and is_nan(_precisions[int(objective.after)]):
			continue
		var tolerance := _tolerance_km(objective)
		if d < tolerance:
			_precisions[k] = MissionScoring.precision(d, tolerance)
			filled = k
	_journal.write("shot", _now(), {"mission": _mission_id, "type": type, "lat": lat, "lon": lon,
			"nearest_km": nearest if nearest < INF else -1.0, "objective": filled,
			"precision": _precisions[filled] if filled >= 0 else 0.0, "elapsed_s": _now() - _started_unix})
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
	# Briefing jamais lu : l'appel s'arrête avec la mission.
	_briefing_id = ""
	_call.stop()
	_journal.write("mission_end", _now(), {"mission": id, "score": score, "success": success,
			"precision": precision, "time_factor": factor, "elapsed_s": elapsed, "par_s": _par,
			"deadline_s": _deadline_s(mission), "complete": not _precisions.any(func(p: float) -> bool: return is_nan(p)),
			"precisions": _precisions.map(func(p: float) -> float: return -1.0 if is_nan(p) else p)})
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
	_journal.write("day_end", _now(), {"day": day.id, "day_score": scores.day_score,
			"global_score": scores.global_score})
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
	_journal.write("sleep", _now(), {"next_day_index": next})
	if next >= Campaigns.current.days().size():
		_journal.write("campaign_end", _now(), {"global_score": Campaigns.global_score(),
				"day_scores": Campaigns.day_scores})
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
		await wake.play(tr("DAY_TITLE").format({"n": next + 1}), day_heading())
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
		sleep_s = CampaignData.next_clock_unix(str(day.wake_up_utc), now) - now
	# Les explosions vieillissent aussi pendant la nuit (incendies, fumées).
	_advance(sleep_s)


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
			"description": _text(mission, "description"), "targets": "\n".join(targets), "duration": duration})


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
	return MissionScoring.tolerance_km(objective, Campaigns.current.defaults())


## Échéance (s) : deadline_hours et deadline_minutes (facultatif) additionnés.
func _deadline_s(mission: Dictionary) -> float:
	return float(mission.get("deadline_hours", 0.0)) * 3600.0 + float(mission.get("deadline_minutes", 0.0)) * 60.0


## Passage le plus tôt possible depuis maintenant (arrivée du briefing, départ du chrono, MissionPlanner) et temps de
## référence (s) : par_hours, sinon ce passage plus une orbite ; au plus l'échéance.
func _plan(mission: Dictionary) -> void:
	var deadline := _deadline_s(mission)
	_earliest = INF
	_par = deadline
	if _orbit:
		var state := MissionPlanner.state_of(_orbit)
		_earliest = MissionPlanner.earliest(state, mission.objectives, 0.0, deadline).time
		if _earliest < INF:
			_par = minf(_earliest + MissionPlanner.period_s(state), deadline)
	var par: Variant = mission.get("par_hours", null)
	if par != null:
		_par = float(par) * 3600.0


## Heure du jeu (UTC, s).
func _now() -> float:
	return _orbit.get_utc_unix_s() if _orbit else 0.0
