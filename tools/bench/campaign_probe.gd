extends Node
## Sonde de la campagne (lot 2, étape 5 de l'audit : la découpe de CampaignDirector ne doit rien y changer) : joue
## la campagne officielle de bout en bout en headless, par l'API du jeu et le temps de l'orbite :
## - journée 1 : départ appliqué (orbite, heure), briefing à son heure et reçu avec la liaison radio, appel
##   prioritaire, lecture du briefing, tir hors objectif, cible au sol, photo prise (ne compte pas), photo envoyée trop
##   loin (invalide), photo envoyée sur l'objectif (valide), fin de mission (réussite),
##   fin de journée (débriefing), sommeil : sauvegarde (monde : orbite, explosion, cibles), journée suivante ;
## - « Continuer » : la scène est rechargée depuis la sauvegarde (monde recréé, journée 2 à sa date) ;
## - journée 2 : briefing après le délai, photo envoyée manquée, échéance dépassée (échec, 0/20), fin de campagne (message de fin
##   selon la moyenne), sommeil : sauvegarde effacée, écran de fin.
## Les journaux de partie (user://logs) des deux parties sont vérifiés (suite des événements) puis supprimés ; la
## sauvegarde est écrite à part (CampaignSession.save_path), la vraie n'est pas touchée. Usage :
##   godot --headless --path . res://tools/bench/campaign_probe.tscn        (code 0 si tout passe)

const VIEW := "res://scenes/orbit_view.tscn"
const SAVE := "user://saves/campaign_probe.json"
const CAMPAIGN := "starnuke"
const RIVNE := Vector2(50.62, 26.25)
const KOUROU := Vector2(5.24, -52.77)
const TOULOUSE := Vector2(43.6, 1.44)

var _failures := 0
var _journals: Array[String] = []


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


## Attend que pred soit vraie (une image à la fois), au plus timeout_s ; rend son dernier état.
func _until(pred: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


## Fait avancer le temps du jeu par pas de step_s (orbite et radio mises à jour à chaque pas), jusqu'à ce que pred
## soit vraie ou que max_s secondes de jeu soient passées ; rend l'état de pred.
func _advance_until(view: Node, pred: Callable, step_s: float, max_s: float) -> bool:
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var radio := view.get_node("Radio") as RadioComms
	var elapsed := 0.0
	while elapsed < max_s:
		if pred.call():
			return true
		orbit.sim_time_s += step_s
		elapsed += step_s
		radio.call("_process", 1.0)
		await get_tree().process_frame
	return pred.call()


func _load_view() -> Node:
	var view: Node = load(VIEW).instantiate()
	add_child(view)
	for i in 30:
		await get_tree().process_frame
	return view


func _utc(text: String) -> float:
	return CampaignData.parse_utc(text)


func _ready() -> void:
	CampaignSession.save_path = SAVE
	CampaignSession.delete_save()
	_check(CampaignSession.start_campaign(CAMPAIGN), "campagne %s lancée" % CAMPAIGN)
	print("- Journée 1")
	var view := await _load_view()
	await _play_day_1(view)
	print("- Continuer")
	view.queue_free()
	await get_tree().process_frame
	_check(CampaignSession.has_saved(), "sauvegarde lisible")
	_check(CampaignSession.continue_saved(), "campagne reprise")
	_check(CampaignSession.day_index == 1 and CampaignSession.results.has("test_rivne"), "journée 2, résultat de la mission 1 gardé")
	_check(not CampaignSession.pending_world.is_empty(), "monde à recréer")
	view = await _load_view()
	await _play_day_2(view)
	print("- Journaux")
	_check_journals()
	CampaignSession.delete_save()
	CampaignSession.start_free()
	print("=== %d échec(s) au total" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _play_day_1(view: Node) -> void:
	var director := view.get_node("CampaignDirector") as CampaignDirector
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var radio := view.get_node("Radio") as RadioComms
	var photos := view.get_node("Photos") as PhotoArchive
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	var targets := get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
	var events: Array[String] = []
	director.day_started.connect(func(i: int) -> void: events.append("day_started:%d" % i))
	director.mission_started.connect(func(id: String) -> void: events.append("mission_started:" + id))
	director.mission_finished.connect(func(id: String, _r: Dictionary) -> void: events.append("mission_finished:" + id))
	director.day_finished.connect(func(i: int) -> void: events.append("day_finished:%d" % i))
	_journals.append(director.get("_journal").path)
	_check(director.is_active(), "directeur actif")
	_check(CampaignSession.day_index == 0, "journée 1")
	_check(is_equal_approx(orbit.get_utc_unix_s(), _utc("2035-07-15T06:00:00Z")), "départ : 15/07/2035 06:00 UTC")
	var point := orbit.get_subsatellite_point()
	_check(absf(point.x - 40.4) < 0.1 and absf(point.y + 3.7) < 0.1, "départ : au-dessus de Madrid (%.2f, %.2f)" % [point.x, point.y])
	_check(is_equal_approx(orbit.altitude_km, 400.0) and is_equal_approx(orbit.inclination_deg, 51.6), "départ : 400 km, 51,6°")
	_check(director.current_mission() == "", "pas de mission avant le briefing")
	_check(not director.can_sleep(), "couchette fermée")
	_check(director.day_heading().contains("2035"), "ligne du réveil : " + director.day_heading())
	# Briefing à 06:00:30, reçu avec la liaison radio : appel prioritaire, chrono.
	director.photo_evaluation_s = 0.05
	var call := get_tree().get_first_node_in_group(PriorityCall.GROUP) as PriorityCall
	var ok := await _advance_until(view, func() -> bool: return director.current_mission() != "", 5.0, 600.0)
	_check(ok, "briefing reçu : mission %s (%s UTC)" % [director.current_mission(), Time.get_datetime_string_from_unix_time(int(orbit.get_utc_unix_s()))])
	_check(orbit.get_utc_unix_s() >= _utc("2035-07-15T06:00:30Z") and orbit.get_utc_unix_s() < _utc("2035-07-15T06:01:00Z"),
			"30 s après le départ")
	_check(radio.inbox.size() == 1 and radio.inbox[0].subject.contains(tr("CAMPAIGN_STARNUKE_M_TEST_TITLE")), "briefing dans la boîte")
	_check(radio.inbox[0].body.contains("6 h 00 min"), "durée avant échec dans le briefing")
	_check(call != null and call.is_ringing(), "appel prioritaire")
	_check(is_equal_approx(orbit.time_scale, 1.0), "temps ×1")
	radio.mark_read(radio.inbox[0].id)
	_check(not call.is_ringing(), "appel terminé à la lecture")
	# Tir hors objectif (journal : aucun objectif rempli), cible au sol : tous deux sauvés au coucher.
	launcher.launch_at(48.86, 2.35, 20.0)
	_check(launcher.get_effects().size() == 1 and director.current_mission() == "test_rivne", "tir hors objectif : mission en cours")
	targets.set_target(0, TOULOUSE.x, TOULOUSE.y)
	# Photo prise sur l'objectif : ne compte pas tant qu'elle n'est pas envoyée.
	photos.photo_taken.emit({"id": 1, "lat": RIVNE.x, "lon": RIVNE.y})
	_check(director.current_mission() == "test_rivne" and director.can_send_photo(), "photo prise : mission en cours, envoi possible")
	# Photo envoyée à 30 km (précision 6,7 < 10) : reçue, puis invalide ; la mission continue.
	var evaluations: Array[Dictionary] = []
	var received: Array[int] = []
	director.photo_received.connect(func(id: int) -> void: received.append(id))
	director.photo_evaluated.connect(func(e: Dictionary) -> void: evaluations.append(e))
	director.send_photo({"id": 2, "lat": RIVNE.x + 0.27, "lon": RIVNE.y})
	_check(received == [2] and not director.can_send_photo(), "photo reçue, évaluation en cours (pas d'autre envoi)")
	ok = await _until(func() -> bool: return evaluations.size() == 1, 3.0)
	_check(ok and not evaluations[0].valid and float(evaluations[0].score) > 0.0 and float(evaluations[0].score) < 10.0,
			"photo invalide (%.1f/20)" % float(evaluations[0].get("score", -1.0)) if ok else "photo invalide")
	_check(director.current_mission() == "test_rivne" and director.can_send_photo(), "mission en cours, nouvel envoi possible")
	# Photo envoyée à 1 km : valide, mission accomplie.
	director.send_photo({"id": 3, "lat": RIVNE.x + 0.009, "lon": RIVNE.y})
	ok = await _until(func() -> bool: return evaluations.size() == 2, 3.0)
	_check(ok and evaluations[1].valid and evaluations[1].complete and is_equal_approx(float(evaluations[1].score), 20.0),
			"photo valide 20/20, mission accomplie")
	_check(director.current_mission() == "", "mission terminée après la photo valide")
	var result: Dictionary = CampaignSession.results.get("test_rivne", {})
	_check(result.get("success", false) and is_equal_approx(float(result.get("precision", 0.0)), 20.0), "réussite, précision 20 (note %.1f)" % float(result.get("score", 0.0)))
	_check(radio.inbox.size() == 3, "résultat et débriefing reçus (%d messages)" % radio.inbox.size())
	_check(director.can_sleep(), "couchette ouverte")
	# day_started(0) est émis au chargement (start_day différé), avant le branchement de la sonde.
	_check(events == ["mission_started:test_rivne", "mission_finished:test_rivne", "day_finished:0"], "signaux : " + str(events))
	# Coucher : sauvegarde (monde au réveil), journée 2 à sa date.
	var bedtime := orbit.get_utc_unix_s()
	await director.sleep()
	_check(FileAccess.file_exists(SAVE), "sauvegarde écrite")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	var world: Dictionary = saved.get("world", {})
	_check(int(saved.get("day_index", -1)) == 1, "sauvegarde : journée 2")
	# La journée 2 a son propre départ : pas de nuit, l'orbite est sauvée au coucher (le saut se fait au réveil).
	_check(is_equal_approx(float(world.get("orbit", {}).get("utc", 0.0)), bedtime), "sauvegarde : orbite au coucher")
	_check(world.get("detonations", []).size() == 1 and is_equal_approx(float(world.detonations[0].lat), 48.86), "sauvegarde : l'explosion")
	_check(world.get("targets", {}).get("targets", [null])[0] != null, "sauvegarde : la cible")
	_check(CampaignSession.day_index == 1 and is_equal_approx(orbit.get_utc_unix_s(), _utc("2035-07-18T11:15:00Z")), "journée 2 : saut au 18/07/2035 11:15 UTC")
	_check(events.size() == 4 and events[3] == "day_started:1", "signal day_started:1")


func _play_day_2(view: Node) -> void:
	var director := view.get_node("CampaignDirector") as CampaignDirector
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var radio := view.get_node("Radio") as RadioComms
	var photos := view.get_node("Photos") as PhotoArchive
	var launcher := view.get_node("NukeLauncher") as NukeLauncher
	var targets := get_tree().get_first_node_in_group(GroundTarget.GROUP) as GroundTarget
	_journals.append(director.get("_journal").path)
	_check(CampaignSession.pending_world.is_empty(), "monde recréé")
	_check(launcher.get_effects().size() == 1 and launcher.get_effects()[0].params.restored, "explosion recréée (restored)")
	_check(targets.has_target(0), "cible recréée")
	_check(CampaignSession.day_index == 1 and is_equal_approx(orbit.get_utc_unix_s(), _utc("2035-07-18T11:15:00Z")), "journée 2 reprise à sa date")
	_check(director.current_mission() == "", "pas de mission avant le briefing")
	# Briefing 30 min après le réveil (délai par défaut), reçu avec la liaison.
	var ok := await _advance_until(view, func() -> bool: return director.current_mission() != "", 60.0, 4.0 * 3600.0)
	_check(ok and director.current_mission() == "test_toulouse", "briefing reçu : mission %s" % director.current_mission())
	_check(orbit.get_utc_unix_s() >= _utc("2035-07-18T11:45:00Z"), "pas avant 11:45")
	# Photo envoyée loin de l'objectif : note 0, invalide ; puis l'échéance (5 h 30) passe : échec, 0/20.
	director.photo_evaluation_s = 0.05
	var evaluations: Array[Dictionary] = []
	director.photo_evaluated.connect(func(e: Dictionary) -> void: evaluations.append(e))
	director.send_photo({"id": 1, "lat": KOUROU.x, "lon": KOUROU.y})
	ok = await _until(func() -> bool: return evaluations.size() == 1, 3.0)
	_check(ok and not evaluations[0].valid and is_zero_approx(float(evaluations[0].score)), "photo manquée : 0/20, invalide")
	_check(director.current_mission() == "test_toulouse", "mission toujours en cours")
	orbit.sim_time_s += 5.5 * 3600.0 + 1.0
	await get_tree().process_frame
	_check(director.current_mission() == "", "échéance dépassée : mission terminée")
	var result: Dictionary = CampaignSession.results.get("test_toulouse", {})
	_check(not result.get("success", true) and is_zero_approx(float(result.get("score", 1.0))) and result.get("expired", false),
			"échec, note 0 (échéance)")
	var global: Variant = CampaignSession.global_score()
	_check(global != null and is_equal_approx(float(global), 10.0), "moyenne globale %.1f (20 et 0)" % float(global))
	# Journée et campagne finies : résultat, débriefing, message de fin (moyenne ≥ 10 : le bon), reçus avec la liaison.
	ok = await _advance_until(view, func() -> bool: return radio.inbox.size() >= 4, 60.0, 4.0 * 3600.0)
	_check(ok and radio.inbox.size() == 4, "résultat, débriefing et fin reçus (%d messages)" % radio.inbox.size())
	_check(radio.inbox[-1].body == tr("CAMPAIGN_STARNUKE_END_GOOD"), "message de fin selon la moyenne")
	_check(radio.inbox[1].body.contains(tr("RESULT_EXPIRED")), "résultat : délai dépassé, mission échouée")
	_check(director.can_sleep(), "couchette ouverte")
	# Dernier coucher : fin de campagne. La scène courante est remplacée par l'écran de fin : un nœud jetable prend
	# sa place pour que la sonde survive.
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	var dummy_id := dummy.get_instance_id()
	await director.sleep()
	ok = await _until(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.get_instance_id() != dummy_id, 3.0)
	_check(ok and get_tree().current_scene.scene_file_path == CampaignDirector.END_SCENE, "écran de fin de campagne")
	_check(not FileAccess.file_exists(SAVE), "sauvegarde effacée")
	view.queue_free()


## Journaux des deux parties : suite des événements attendue, puis fichiers supprimés.
func _check_journals() -> void:
	var expected := [
		["session", "day_start", "mission_scheduled", "briefing_sent", "mission_start", "briefing_read", "shot", "shot",
				"shot", "mission_end", "day_end", "sleep", "day_start", "mission_scheduled"],
		["session", "day_start", "mission_scheduled", "briefing_sent", "mission_start", "shot", "mission_end",
				"day_end", "sleep", "campaign_end"],
	]
	for i in _journals.size():
		var path := _journals[i]
		var events := PackedStringArray()
		var lines: Array[Dictionary] = []
		for line in FileAccess.get_file_as_string(path).split("\n", false):
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				lines.append(parsed)
				events.append(str(parsed.event))
		_check(Array(events) == expected[i], "journal %d : %s" % [i + 1, ", ".join(events)])
		if i == 0 and lines.size() >= 8:
			_check(bool(lines[0].get("continued", true)) == false, "journal 1 : nouvelle partie")
			_check(int(lines[6].get("objective", 0)) == -1 and int(lines[7].get("objective", 0)) == -1
					and int(lines[8].get("objective", -1)) == 0, "journal 1 : tir hors objectif, photo invalide, photo valide")
			_check(float(lines[4].get("earliest_s", -1.0)) > 0.0 and float(lines[4].get("par_s", 0.0)) > 0.0, "journal 1 : passage au plus tôt et temps de référence")
		if i == 1 and lines.size() >= 7:
			_check(bool(lines[0].get("continued", false)) == true, "journal 2 : partie continuée")
			_check(bool(lines[6].get("complete", true)) == false, "journal 2 : mission incomplète à l'échéance")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
