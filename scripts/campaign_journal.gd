class_name CampaignJournal
extends RefCounted
## Journal de partie d'une campagne : un fichier JSON Lines par partie lancée (nouvelle campagne ou « Continuer »),
## user://logs/<campagne>_<date et heure réelles>.jsonl, une ligne par événement :
## {"event", "real" (heure réelle locale), "utc" (heure du jeu, ISO), "unix" (heure du jeu, s), …champs de
## l'événement}. Il sert à régler les profils du banc d'équilibrage (tools/balance_campaign.gd) d'après de vraies
## parties : retards sur le passage le plus tôt possible, distances des photos et des tirs, qualité des poussées.
## Abonné aux signaux de CampaignDirector (attach) et de FlightComputer (burn_finished) : le directeur ne sait rien
## du fichier. Événements : session (à la première journée), day_start, mission_scheduled, briefing_sent,
## mission_start, briefing_read, burn, shot, mission_end, day_end, sleep, campaign_end. Le fichier est vidé sur le
## disque à chaque ligne : rien n'est perdu si le jeu s'arrête.

const FOLDER := "user://logs"

var path := ""
var _file: FileAccess
var _campaign_id := ""
var _continued := false
var _session_logged := false
var _director: CampaignDirector
var _orbit: OrbitSimulation
var _flight_computer: FlightComputer


## Ouvre un nouveau journal pour la campagne campaign_id (continued : partie reprise d'une sauvegarde) ; sans effet
## (journal muet) si le fichier ne s'ouvre pas.
func _init(campaign_id: String, continued := false) -> void:
	_campaign_id = campaign_id
	_continued = continued
	if DirAccess.make_dir_recursive_absolute(FOLDER) != OK:
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	path = FOLDER.path_join("%s_%s.jsonl" % [campaign_id, stamp])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("CampaignJournal : %s impossible à ouvrir" % path)


## Branche le journal sur les signaux du directeur, l'horloge de l'orbite (heure du jeu ; null : 0) et les poussées
## de l'ordinateur de vol (null : pas d'événement burn).
func attach(director: CampaignDirector, orbit: OrbitSimulation, flight_computer: FlightComputer) -> void:
	_director = director
	_orbit = orbit
	_flight_computer = flight_computer
	director.day_started.connect(_on_day_started)
	director.mission_scheduled.connect(func(mission_id: String, briefing_unix: float) -> void:
		write("mission_scheduled", {"mission": mission_id, "briefing_unix": briefing_unix}))
	director.briefing_sent.connect(func(mission_id: String) -> void:
		write("briefing_sent", {"mission": mission_id}))
	director.mission_started.connect(_on_mission_started)
	director.briefing_read.connect(func(mission_id: String, elapsed_s: float) -> void:
		write("briefing_read", {"mission": mission_id, "elapsed_s": elapsed_s}))
	director.shot_recorded.connect(func(shot: Dictionary) -> void: write("shot", shot))
	director.mission_finished.connect(func(mission_id: String, result: Dictionary) -> void:
		var line := {"mission": mission_id}
		line.merge(result)
		write("mission_end", line))
	director.day_finished.connect(_on_day_finished)
	director.fell_asleep.connect(func(next_day_index: int) -> void:
		write("sleep", {"next_day_index": next_day_index}))
	director.campaign_finished.connect(func() -> void:
		write("campaign_end", {"global_score": CampaignSession.global_score(), "day_scores": CampaignSession.day_scores}))
	if flight_computer:
		flight_computer.burn_finished.connect(func(quality: int, ratio: float) -> void:
			write("burn", {"mission": director.current_mission(),
					"quality": FlightComputer.BurnQuality.keys()[quality].to_lower(), "ratio": ratio,
					"auto": flight_computer.mode == FlightComputer.Mode.AUTO}))


## Ajoute un événement à l'heure du jeu.
func write(event: String, data := {}) -> void:
	if _file == null:
		return
	var game_unix := _now()
	var line := {"event": event, "real": Time.get_datetime_string_from_system(),
			"utc": Time.get_datetime_string_from_unix_time(int(game_unix)) + "Z", "unix": game_unix}
	line.merge(data)
	_file.store_line(JSON.stringify(line))
	_file.flush()


## Première journée de la partie : événement session (campagne, journée, partie continuée), puis day_start.
func _on_day_started(day_index: int) -> void:
	if not _session_logged:
		_session_logged = true
		write("session", {"campaign": _campaign_id, "day_index": day_index, "continued": _continued})
	write("day_start", {"day": CampaignSession.current.days()[day_index].id, "day_index": day_index})


## Départ du chrono : échéance, temps de référence, passage le plus tôt possible (−1 : impossible à temps), orbite et
## vitesse du temps à l'arrivée du briefing.
func _on_mission_started(mission_id: String) -> void:
	var run := _director.mission_run()
	write("mission_start", {"mission": mission_id, "deadline_s": run.deadline_s if run else 0.0,
			"par_s": run.par_s if run else 0.0,
			"earliest_s": run.earliest_s if run and run.earliest_s < INF else -1.0,
			"altitude_km": _orbit.altitude_km if _orbit else 0.0,
			"inclination_deg": _orbit.inclination_deg if _orbit else 0.0,
			"time_scale": _orbit.time_scale if _orbit else 1.0})


func _on_day_finished(day_index: int) -> void:
	var day_id: String = CampaignSession.current.days()[day_index].id
	var scores := CampaignSession.scores(day_id, "")
	write("day_end", {"day": day_id, "day_score": scores.day_score, "global_score": scores.global_score})


func _now() -> float:
	return _orbit.get_utc_unix_s() if _orbit else 0.0
