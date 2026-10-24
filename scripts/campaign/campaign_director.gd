class_name CampaignDirector
extends Node
## Déroulement d'une campagne (nœud CampaignDirector de scenes/orbit_view.tscn), actif seulement en mode campagne
## (CampaignSession.mode, choisi à l'écran de démarrage) ; en mode libre, il ne fait rien. Règles de jeu :
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
## - objectifs : un impact (NukeLauncher.detonated) à moins de la tolérance d'une cible de la mission remplit son
##   objectif (le premier objectif encore ouvert de ce type, dont l'objectif préalable « after » est rempli), avec la
##   précision obtenue (MissionScoring) ; plus loin, il ne compte pas. Une photo ne compte pas quand on la prend :
##   il faut l'envoyer au sol depuis la galerie de l'écran de communication (send_photo, liaison radio requise) ;
##   « Photo bien reçue… évaluation en cours… » (photo_received), puis PHOTO_EVALUATION_S secondes plus tard sa note
##   sur 20 (précision au point sous la station à la prise de vue, photo_evaluated) : photo valide si elle atteint
##   success_score (l'objectif est rempli), sinon invalide : on peut en envoyer une autre, ou attendre un autre
##   passage pour la reprendre ;
## - fin de mission : tous les objectifs remplis : note = précision pondérée × facteur temps (MissionScoring),
##   réussite si ≥ success_score ; échéance (deadline_hours après l'arrivée du briefing) avant : mission échouée,
##   note 0 ; résultat retenu (CampaignSession.results,
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
##   écran de démarrage. Sauvegarde au coucher (CampaignSession.save).

## Déroulement (le journal de partie, CampaignJournal, y est abonné ; la tablette et l'écran de communication aussi
## pour ce qui les concerne) : journée commencée (départ appliqué) ; mission programmée (heure d'arrivée de son
## briefing, UTC, s) ; briefing envoyé par le sol ; mission commencée (briefing reçu, chrono parti : mission_run() ;
## émis avant le retour du temps à ×1) ; briefing lu (temps écoulé depuis le départ du chrono, s) ; photo ou impact
## enregistré ({mission, type, lat, lon, nearest_km, objective, precision, elapsed_s}, MissionRun.record) ; mission
## finie (result : note retenue (score, success, precision, time_factor, day) et détail (elapsed_s, par_s,
## deadline_s, complete, precisions), MissionRun.result et report) ; journée finie ; endormi (journée suivante) ;
## campagne finie (dernière nuit : écran de fin).
signal day_started(day_index: int)
signal mission_scheduled(mission_id: String, briefing_unix: float)
signal briefing_sent(mission_id: String)
signal mission_started(mission_id: String)
signal briefing_read(mission_id: String, elapsed_s: float)
signal shot_recorded(shot: Dictionary)
## Photo envoyée au sol (send_photo), puis sa note PHOTO_EVALUATION_S secondes plus tard : {photo_id, score (sur 20),
## valid (objectif rempli), complete (mission finie), expired (mission finie ou changée entre-temps : pas de note)}.
signal photo_received(photo_id: int)
signal photo_evaluated(evaluation: Dictionary)
signal mission_finished(mission_id: String, result: Dictionary)
signal day_finished(day_index: int)
signal fell_asleep(next_day_index: int)
signal campaign_finished

const GROUP := &"campaign_director"
const END_SCENE := "res://scenes/ui/campaign_end_screen.tscn"
## Délai (s, temps réel) entre la réception d'une photo par le sol et sa note.
const PHOTO_EVALUATION_S := 4.0

@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"
@export var radio_path: NodePath = ^"../Radio"
@export var photos_path: NodePath = ^"../Photos"
@export var launcher_path: NodePath = ^"../NukeLauncher"
## Observateur, replacé dans la couchette à chaque réveil (Observer.place_at_start).
@export var observer_path: NodePath = ^"../Observer"

var _orbit: OrbitSimulation
var _flight_computer: FlightComputer
var _radio: RadioComms
## Monde à sauvegarder et à recréer (WorldSnapshot), construit à la première demande (les cibles au sol sont
## trouvées par groupe, une fois toute la scène prête).
var _world: WorldSnapshot
## Mission en cours (MissionRun : chrono, objectifs, note ; null : aucune) et identifiant du message de briefing
## attendu ou pas encore lu.
var _run: MissionRun
var _briefing_id := ""
## Journal de partie (scripts/campaign_journal.gd), abonné aux signaux.
var _journal: CampaignJournal
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
## Photo envoyée en cours d'évaluation (id, 0 : aucune).
var _evaluating := 0
## Délai de la note d'une photo envoyée (s ; PHOTO_EVALUATION_S, raccourci par les sondes).
var photo_evaluation_s := PHOTO_EVALUATION_S
## Photos déjà envoyées au sol : id → évaluation (photo_evaluated) ; une photo ne s'envoie qu'une fois. Pas sauvegardé.
var sent_photos := {}


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_flight_computer = get_node_or_null(flight_computer_path) as FlightComputer
	_radio = get_node_or_null(radio_path) as RadioComms
	if not is_active():
		set_process(false)
		return
	var pending := CampaignSession.take_pending_world()
	_journal = CampaignJournal.new(CampaignSession.current_id, not pending.is_empty())
	_journal.attach(self, _orbit, _flight_computer)
	_call = PriorityCall.new()
	_call.name = "PriorityCall"
	add_child(_call)
	if _radio:
		_radio.message_read.connect(_on_message_read)
		_radio.message_received.connect(_on_message_received)
	var launcher := get_node_or_null(launcher_path) as NukeLauncher
	if launcher:
		launcher.detonated.connect(func(effect: NukeEffect) -> void:
			# Une explosion recréée au chargement n'est pas un tir : elle ne remplit aucun objectif.
			if effect.params and not effect.params.restored:
				_record("strike", effect.params.latitude_deg, effect.params.longitude_deg))
	# Après la mise en place de l'orbite (son _ready) : monde d'une sauvegarde recréé (« Continuer »), puis journée.
	if not pending.is_empty():
		_restore_world.call_deferred(pending)
	start_day.call_deferred(CampaignSession.day_index)


func is_active() -> bool:
	return CampaignSession.mode == CampaignSession.Mode.CAMPAIGN and CampaignSession.current != null


## Mission en cours ("" : aucune).
func current_mission() -> String:
	return _run.id if _run else ""


## Mission en cours (null : aucune) : chrono, objectifs, note.
func mission_run() -> MissionRun:
	return _run


## Commence la journée day_index : départ appliqué s'il est défini (sinon, la station reste où elle est), puis
## première mission programmée.
func start_day(day_index: int) -> void:
	if not is_active() or day_index < 0 or day_index >= CampaignSession.current.days().size():
		return
	CampaignSession.day_index = day_index
	var start := CampaignSession.current.start_of_day(day_index)
	# Première journée sans orbite propre : départ de la campagne, puis saut à sa date.
	if day_index == 0 and not start.has("orbit"):
		apply_start(CampaignSession.current.data.get("start", {}))
	apply_start(start)
	_next_entry = 0
	_day_over = false
	day_started.emit(day_index)
	_next_mission()


## Applique un départ (format de CampaignData) ; rien si start est vide. Avec orbit : station placée à l'heure et à la
## position données ; sans : saut dans le temps jusqu'à la date (orbite poursuivie), ignoré si elle est passée. Les
## explosions vieillissent du temps sauté.
func apply_start(start: Dictionary) -> void:
	if start.is_empty() or _orbit == null:
		return
	var utc := CampaignData.parse_utc(str(start.utc))
	var jump := CampaignData.time_jump_s(start, _orbit.get_utc_unix_s())
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
	if _run and _run.is_due(_now()):
		_finish_mission()


## Ligne du réveil : date, heure UTC et point survolé (« 24 octobre 2035 — 11 h 15 UTC — 40.40° N  3.70° O »).
func day_heading() -> String:
	if _orbit == null:
		return ""
	var now := _orbit.get_utc_datetime()
	var point := _orbit.get_subsatellite_point()
	return tr("WAKE_HEADING").format({"day": now.day, "month": tr("MONTH_%d" % now.month), "year": now.year,
			"hour": "%02d" % now.hour, "minute": "%02d" % now.minute,
			"position": GeoMath.format_lat_lon(point.x, point.y)})


# --- Missions -------------------------------------------------------------------------------------------------------

## Mission suivante de la journée dont la condition est vraie, programmée à l'heure de son briefing ; sinon fin de
## journée.
func _next_mission() -> void:
	var day := _day()
	var entries: Array = day.get("missions", [])
	while _next_entry < entries.size():
		var entry: Dictionary = entries[_next_entry]
		_next_entry += 1
		if CampaignData.check(entry.get("when", {}), CampaignSession.scores(day.id, "")):
			_scheduled_id = str(entry.mission)
			_briefing_unix = CampaignSession.current.briefing_unix(entry, _now())
			mission_scheduled.emit(_scheduled_id, _briefing_unix)
			return
	_finish_day()


## Heure du briefing : il est envoyé par le sol ; il n'arrive qu'avec la liaison radio (station au sol en vue, canal :
## RadioComms), et c'est à sa réception (message_received, parfois émis pendant post même) que la mission commence.
## L'identifiant du message est réservé avant l'envoi, pour reconnaître cette réception. Sans radio : tout de suite.
func _send_briefing() -> void:
	var mission := CampaignSession.current.mission(_scheduled_id)
	briefing_sent.emit(_scheduled_id)
	if _radio == null:
		_start_mission()
		return
	_briefing_id = _radio.reserve_id()
	_radio.post(CampaignMessages.briefing(mission, _defaults(), _briefing_id))


func _on_message_received(message: Dictionary) -> void:
	if not _scheduled_id.is_empty() and not _briefing_id.is_empty() and message.get("id", "") == _briefing_id:
		_start_mission()


## Réception du briefing : la mission programmée commence (chrono), appel prioritaire, temps ramené à ×1.
func _start_mission() -> void:
	var id := _scheduled_id
	_scheduled_id = ""
	_run = MissionRun.new(id, CampaignSession.current.mission(id), _defaults(), _now())
	_run.plan(_orbit)
	# Émis avant le retour du temps à ×1 (le journal note la vitesse à l'arrivée du briefing).
	mission_started.emit(id)
	if _orbit:
		_orbit.time_scale = 1.0
	_call.ring({"from": CampaignMessages.sender(_run.mission, _defaults()),
			"subject": CampaignMessages.briefing_subject(_run.mission), "received_unix": _now()})


## Briefing lu (écran de communication) : fin de l'appel prioritaire.
func _on_message_read(message_id: String) -> void:
	if message_id.is_empty() or message_id != _briefing_id:
		return
	_briefing_id = ""
	_call.stop()
	briefing_read.emit(current_mission(), _run.elapsed_s(_now()) if _run else 0.0)


## Photo ou impact en (lat, lon) : remplit le premier objectif ouvert de ce type à portée, de précision au moins
## min_precision (MissionRun.record) ; mission finie quand tous le sont. Rend le relevé (vide sans mission), avec
## complete : mission finie par lui.
func _record(type: String, lat: float, lon: float, min_precision := 0.0) -> Dictionary:
	if _run == null:
		return {}
	var shot := _run.record(type, lat, lon, min_precision)
	shot.merge({"mission": _run.id, "type": type, "lat": lat, "lon": lon, "elapsed_s": _run.elapsed_s(_now()),
			"complete": _run.is_complete()})
	shot_recorded.emit(shot)
	if shot.complete:
		_finish_mission()
	return shot


## Peut-on envoyer une photo au sol ? Mission en cours avec un objectif photo ouvert, pas d'évaluation en cours.
func can_send_photo() -> bool:
	return is_active() and _run != null and _run.has_open("photo") and _evaluating == 0


## Photo de la galerie (PhotoArchive.photos) envoyée au sol : reçue tout de suite, notée PHOTO_EVALUATION_S
## secondes plus tard (temps réel) ; valide si sa note atteint success_score. Évaluation : {photo_id, score,
## distance_km (centre de la photo, point survolé, à la cible la plus proche ; -1 : échéance passée), valid, complete,
## expired}. Faux si elle ne peut pas l'être (pas de mission photo, évaluation en cours, photo déjà envoyée).
func send_photo(photo: Dictionary) -> bool:
	if not can_send_photo() or sent_photos.has(int(photo.id)):
		return false
	var mission := _run.id
	_evaluating = int(photo.id)
	photo_received.emit(_evaluating)
	await get_tree().create_timer(photo_evaluation_s, true, false, true).timeout
	var evaluation := {"photo_id": _evaluating, "score": 0.0, "distance_km": -1.0, "valid": false, "complete": false,
			"expired": true}
	_evaluating = 0
	if _run != null and _run.id == mission:
		var shot := _record("photo", float(photo.lat), float(photo.lon),
				float(_defaults().get("success_score", 10.0)))
		evaluation.merge({"score": float(shot.precision), "distance_km": float(shot.nearest_km),
				"valid": int(shot.objective) >= 0,
				"complete": bool(shot.complete), "expired": false}, true)
	sent_photos[int(evaluation.photo_id)] = evaluation
	photo_evaluated.emit(evaluation)
	return true


## Fin de mission (objectifs remplis ou échéance) : note retenue (CampaignSession.results), message de résultat, mission
## suivante.
func _finish_mission() -> void:
	var run := _run
	_run = null
	var day_id: String = _day().id
	var result := run.result(_now(), day_id)
	CampaignSession.results[run.id] = result
	# Briefing jamais lu : l'appel s'arrête avec la mission.
	_briefing_id = ""
	_call.stop()
	_post(CampaignMessages.result(run.mission, _defaults(), CampaignSession.scores(day_id, run.id), result))
	var detail := result.duplicate()
	detail.merge(run.report(_now()))
	mission_finished.emit(run.id, detail)
	_next_mission()


func _finish_day() -> void:
	var day := _day()
	var scores := CampaignSession.scores(day.id, "")
	if scores.day_score != null:
		CampaignSession.day_scores[day.id] = scores.day_score
	var debrief := CampaignData.pick_message(day.get("debrief", []), scores)
	if not debrief.is_empty():
		_post(CampaignMessages.debrief(debrief, _defaults()))
	if CampaignSession.day_index == CampaignSession.current.days().size() - 1:
		var ending := CampaignData.pick_message(CampaignSession.current.data.get("ending", []), scores)
		if not ending.is_empty():
			_post(CampaignMessages.debrief(ending, _defaults()))
	_day_over = true
	day_finished.emit(CampaignSession.day_index)


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
	var next := CampaignSession.day_index + 1
	fell_asleep.emit(next)
	if next >= CampaignSession.current.days().size():
		campaign_finished.emit()
		CampaignSession.delete_save()
		get_tree().change_scene_to_file(END_SCENE)
		return
	_advance_to_wake_up(next)
	# Sauvegarde au coucher (règle de jeu) : journée à venir, notes, monde au réveil.
	CampaignSession.day_index = next
	CampaignSession.save(_snapshot().capture())
	start_day(next)
	var observer := get_node_or_null(observer_path) as Observer
	if observer:
		observer.place_at_start()
	if wake:
		await wake.play(tr("DAY_TITLE").format({"n": next + 1}), day_heading())
	_sleeping = false


func _wake_up() -> WakeUp:
	return get_tree().get_first_node_in_group(WakeUp.GROUP) as WakeUp


## Monde à sauvegarder et à recréer (orbite, explosions, photos, cibles, relevés : WorldSnapshot).
func _snapshot() -> WorldSnapshot:
	if _world == null:
		_world = WorldSnapshot.new(_orbit, get_node_or_null(launcher_path) as NukeLauncher,
				get_node_or_null(photos_path) as PhotoArchive,
				get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget,
				get_tree().get_first_node_in_group(BearingLog.GROUP) as BearingLog)
	return _world


func _restore_world(world: Dictionary) -> void:
	_snapshot().restore(world)


## Nuit : sans départ propre, la station continue son orbite jusqu'au réveil (wake_up_utc de la journée suivante, le
## lendemain si l'heure est passée ; sinon CampaignData.NIGHT_HOURS : CampaignData.night_s).
func _advance_to_wake_up(day_index: int) -> void:
	if _orbit == null:
		return
	var sleep_s := CampaignSession.current.night_s(day_index, _orbit.get_utc_unix_s())
	# Les explosions vieillissent aussi pendant la nuit (incendies, fumées).
	if sleep_s > 0.0:
		_advance(sleep_s)


# --- Messages -------------------------------------------------------------------------------------------------------

## Message radio de la campagne (CampaignMessages), s'il y a une radio.
func _post(message: Dictionary) -> void:
	if _radio:
		_radio.post(message)


func _defaults() -> Dictionary:
	return CampaignSession.current.defaults()


func _day() -> Dictionary:
	return CampaignSession.current.days()[CampaignSession.day_index]


## Heure du jeu (UTC, s).
func _now() -> float:
	return _orbit.get_utc_unix_s() if _orbit else 0.0
