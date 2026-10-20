class_name CampaignDirector
extends Node
## Déroulement d'une campagne (nœud CampaignDirector de scenes/orbit_view.tscn), actif seulement en mode campagne
## (Campaigns.mode, choisi à l'écran de démarrage) ; en mode libre, il ne fait rien. Règles de jeu :
## - début de journée : départ appliqué (CampaignData.start_of_day : heure UTC, altitude, inclinaison, point survolé,
##   sens de passage, OrbitSimulation.place ; la manœuvre en préparation est annulée), puis briefing de la première
##   mission dont la condition est vraie ;
## - briefing : message radio (RadioComms.post ; expéditeur et canal de la mission, sinon defaults) au gabarit
##   BRIEFING_BODY : mission, objectif, texte, cibles (type et coordonnées), durée avant échec. Le chrono de la mission
##   part quand le briefing est lu (écran de communication) ;
## - objectifs : une photo (PhotoArchive.photo_taken : point sous la station) ou un impact (NukeLauncher.detonated)
##   à moins de la tolérance d'une cible de la mission remplit son objectif (le premier objectif encore ouvert de ce
##   type, dont l'objectif préalable « after » est rempli), avec la précision obtenue (MissionScoring) ; plus loin, il
##   ne compte pas ;
## - fin de mission : tous les objectifs remplis, ou échéance (deadline_hours après la lecture) : note = précision
##   pondérée × facteur temps (MissionScoring), réussite si ≥ success_score ; résultat retenu (Campaigns.results,
##   moyenne globale) et message radio de résultat (message « result » de la mission choisi selon la note, sinon
##   RESULT_DEFAULT_*), puis briefing de la mission suivante de la journée dont la condition est vraie ;
## - fin de journée (plus de mission) : note de la journée retenue, message « debrief » de la journée (selon les
##   notes) ; à la dernière journée, message de fin de campagne (« ending », selon la moyenne globale) ;
## - après la fin de journée, promenade libre : la couchette (Interactif_Couchette) devient cliquable, « Dormir »
##   (HatchInteraction, can_sleep) : fondu au noir (FADE_S), titre de la journée suivante (DAY_TITLE), réveil dans la
##   couchette (Observer, point de départ) au départ de la journée suivante : le sien s'il est défini, sinon la station
##   a continué son orbite jusqu'à l'heure de réveil (wake_up_utc, le lendemain si elle est passée ; sans heure de
##   réveil, NIGHT_HOURS de sommeil) ; réveil par ouverture des paupières (_wake_up, aussi au lancement de la
##   campagne). Après la dernière journée, dormir termine la campagne : retour
##   à l'écran de démarrage (fin de campagne détaillée : étape 7). Sauvegarde au coucher : étape 6.

signal day_started(day_index: int)
signal mission_started(mission_id: String)
signal mission_finished(mission_id: String, result: Dictionary)
signal day_finished(day_index: int)

const GROUP := &"campaign_director"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
## Fondu au noir et retour (s), titre affiché (s) ; sommeil sans heure de réveil (h).
const FADE_S := 1.5
const TITLE_S := 2.5
const NIGHT_HOURS := 8.0
const EYELIDS_SHADER := preload("res://shaders/eyelids.gdshader")
## Ouverture des yeux au réveil : (fermeture visée de 1 à 0, durée en s) — entrouverts, refermés, rouverts, ouverts.
const WAKE_STEPS: Array[Vector2] = [Vector2(0.62, 0.9), Vector2(0.95, 0.35), Vector2(0.4, 1.0), Vector2(0.72, 0.3),
		Vector2(0.0, 1.4)]

@export var orbit_path: NodePath = ^"../Orbit"
@export var flight_computer_path: NodePath = ^"../FlightComputer"
@export var radio_path: NodePath = ^"../Radio"
@export var photos_path: NodePath = ^"../Photos"
@export var launcher_path: NodePath = ^"../NukeLauncher"

var _orbit: OrbitSimulation
var _flight_computer: FlightComputer
var _radio: RadioComms
## Mission en cours : identifiant, briefing (identifiant du message), heure de lecture (−1 : pas encore lu),
## précisions des objectifs (NAN : pas rempli).
var _mission_id := ""
var _briefing_id := ""
var _started_unix := -1.0
var _precisions: Array = []
## Prochaine entrée à examiner dans la liste des missions de la journée.
var _next_entry := 0
## Journée terminée (couchette cliquable) ; sommeil en cours (fondu).
var _day_over := false
var _sleeping := false
var _veil: ColorRect
var _title: Label
var _eyelids_rect: ColorRect
var _eyelids: ShaderMaterial


func _ready() -> void:
	add_to_group(GROUP)
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	_flight_computer = get_node_or_null(flight_computer_path) as FlightComputer
	_radio = get_node_or_null(radio_path) as RadioComms
	if not is_active():
		set_process(false)
		return
	if _radio:
		_radio.message_read.connect(_on_message_read)
	var photos := get_node_or_null(photos_path) as PhotoArchive
	if photos:
		photos.photo_taken.connect(func(photo: Dictionary) -> void:
			_record("photo", float(photo.lat), float(photo.lon)))
	var launcher := get_node_or_null(launcher_path) as NukeLauncher
	if launcher:
		launcher.detonated.connect(func(effect: NukeEffect) -> void:
			if effect.params:
				_record("strike", effect.params.latitude_deg, effect.params.longitude_deg))
	# Après la mise en place de l'orbite (son _ready).
	start_day.call_deferred(Campaigns.day_index)
	_wake_up.call_deferred(Campaigns.day_index)


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
	if _mission_id.is_empty() or _started_unix < 0.0 or _orbit == null:
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
	_started_unix = -1.0
	_precisions = []
	for _objective in mission.objectives:
		_precisions.append(NAN)
	_briefing_id = _post(mission, tr("BRIEFING_SUBJECT").format({"title": _text(mission, "title")}),
			_briefing_body(mission))
	mission_started.emit(id)


func _on_message_read(message_id: String) -> void:
	if message_id == _briefing_id and _started_unix < 0.0 and _orbit:
		_started_unix = _orbit.get_utc_unix_s()


## Photo ou impact en (lat, lon) : remplit le premier objectif ouvert de ce type à portée (son préalable rempli).
func _record(type: String, lat: float, lon: float) -> void:
	if _mission_id.is_empty() or _started_unix < 0.0:
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
	var factor := MissionScoring.time_factor(elapsed, _par_s(mission), _deadline_s(mission),
			float(defaults.get("time_floor", 0.6)))
	var score := precision * factor
	var success := score >= float(defaults.get("success_score", 10.0))
	var day_id: String = _day().id
	var result := {"score": score, "success": success, "precision": precision, "time_factor": factor, "day": day_id}
	var id := _mission_id
	Campaigns.results[id] = result
	_mission_id = ""
	_briefing_id = ""
	_started_unix = -1.0
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


## Dormir : fondu au noir, journée suivante (ou fin de campagne après la dernière), réveil dans la couchette.
func sleep() -> void:
	if not can_sleep():
		return
	_sleeping = true
	_build_veil()
	await create_tween().tween_property(_veil, "color:a", 1.0, FADE_S).finished
	var next := Campaigns.day_index + 1
	if next >= Campaigns.current.days().size():
		Campaigns.start_free()
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	_advance_to_wake_up(next)
	start_day(next)
	var observer := get_tree().current_scene.get_node_or_null("Observer")
	if observer and observer.has_method(&"_place_at_start"):
		observer.call(&"_place_at_start")
	await _wake_up(next)


## Réveil (début de chaque journée, la première comprise) : titre « Jour n » sur le noir, puis ouverture des
## paupières (shaders/eyelids.gdshader, comme la séquence de mort mais à l'envers) : elles s'entrouvrent, se
## referment, se rouvrent davantage puis s'ouvrent tout à fait (WAKE_STEPS) ; la vue, d'abord floue, devient nette.
func _wake_up(day_index: int) -> void:
	_sleeping = true
	_build_veil()
	_veil.color.a = 1.0
	_title.text = tr("DAY_TITLE").format({"n": day_index + 1})
	await create_tween().tween_property(_title, "modulate:a", 1.0, 0.5).finished
	await get_tree().create_timer(TITLE_S).timeout
	await create_tween().tween_property(_title, "modulate:a", 0.0, 0.8).finished
	# Paupières closes (noir complet) à la place du voile, puis ouverture.
	_eyelids.set_shader_parameter("closure", 1.0)
	_eyelids_rect.visible = true
	_veil.color.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := 1.0
	for step: Vector2 in WAKE_STEPS:
		tween.tween_method(func(c: float) -> void: _eyelids.set_shader_parameter("closure", c), from, step.x, step.y)
		from = step.x
	await tween.finished
	_eyelids_rect.visible = false
	# Le voile prend la souris (pas de clic pendant le sommeil) : masqué une fois réveillé, sinon il garde tous les
	# clics, dont le clic droit qui tourne la tête.
	_veil.visible = false
	_sleeping = false


## Nuit : sans départ propre, la station continue son orbite jusqu'au réveil (wake_up_utc de la journée suivante, le
## lendemain si l'heure est passée ; sinon NIGHT_HOURS).
func _advance_to_wake_up(day_index: int) -> void:
	var day: Dictionary = Campaigns.current.days()[day_index]
	if day.has("start") or _orbit == null:
		return
	var now := _orbit.get_utc_unix_s()
	var sleep_s := NIGHT_HOURS * 3600.0
	if day.has("wake_up_utc"):
		var parts := str(day.wake_up_utc).split(":")
		var wake := floorf(now / 86400.0) * 86400.0 + int(parts[0]) * 3600.0 + int(parts[1]) * 60.0
		if wake <= now:
			wake += 86400.0
		sleep_s = wake - now
	_orbit.sim_time_s += sleep_s


## Voile noir, titre et paupières (créés une fois) ; le voile est rendu visible.
func _build_veil() -> void:
	if _veil:
		_veil.visible = true
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_veil)
	# Paupières (réveil) : visibles seulement pendant l'ouverture (elles lisent l'image de l'écran).
	_eyelids = ShaderMaterial.new()
	_eyelids.shader = EYELIDS_SHADER
	_eyelids_rect = ColorRect.new()
	_eyelids_rect.material = _eyelids
	_eyelids_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_eyelids_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_eyelids_rect.visible = false
	layer.add_child(_eyelids_rect)
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	_title.modulate.a = 0.0
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_title)


# --- Messages -------------------------------------------------------------------------------------------------------

## Briefing selon le gabarit : mission, objectif, texte, cibles (type et coordonnées), durée avant échec.
func _briefing_body(mission: Dictionary) -> String:
	var targets := PackedStringArray()
	for objective: Dictionary in mission.objectives:
		var kind := tr("OBJECTIVE_PHOTO" if objective.type == "photo" else "OBJECTIVE_STRIKE")
		targets.append("  %s : %s" % [kind, GroundTarget.format(float(objective.target.lat),
				float(objective.target.lon))])
	# Durée avant échec : « 6 h », « 5 h 30 min ».
	var minutes := roundi(float(mission.deadline_hours) * 60.0)
	var hours := floori(minutes / 60.0)
	var duration := "%d h" % hours if minutes % 60 == 0 else "%d h %02d min" % [hours, minutes % 60]
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
	var defaults: Dictionary = Campaigns.current.defaults().get("tolerance_km", {})
	var fallback := 40.0 if objective.type == "photo" else 15.0
	return float(objective.get("tolerance_km", defaults.get(objective.type, fallback)))


func _deadline_s(mission: Dictionary) -> float:
	return float(mission.deadline_hours) * 3600.0


func _par_s(mission: Dictionary) -> float:
	var par: Variant = mission.get("par_hours", null)
	return float(par) * 3600.0 if par != null else _deadline_s(mission) * MissionScoring.DEFAULT_PAR_SHARE
