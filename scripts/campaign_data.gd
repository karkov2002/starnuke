class_name CampaignData
extends RefCounted
## Contenu d'un campaign.json au format 2 (scripts/campaigns.gd : dossier campaign/), lu et vérifié : journées,
## missions, messages de fin, départ (heure et position de la station). Les erreurs (errors) sont pour les auteurs de
## campagnes : outil de développement, en français (tools/check_campaign.gd les affiche ; le menu ne montre que leur
## nombre). Une campagne avec des erreurs ne se lance pas.
##
## Format 2 (README, « Campagnes ») :
## {
##   "format": 2, "name": TEXTE, "description": TEXTE,
##   "start": DÉPART,                       départ de la campagne (et de la 1re journée sans départ propre)
##   "defaults": {"from": TEXTE, "channel": -1, "success_score": 10,
##                "tolerance_km": {"photo": 40, "strike": 15}, "time_floor": 0.6},
##   "days": [ {"id": "d1", "start": DÉPART (facultatif), "wake_up_utc": "06:00" (facultatif),
##              "missions": [ {"mission": ID, "when": CONDITION (facultatif)} … ],
##              "debrief": [ MESSAGE … ] (facultatif) } … ],
##   "missions": { ID: {"title", "objective", "description": TEXTE, "from": TEXTE (facultatif),
##                      "channel": entier (facultatif), "deadline_hours": >= 0, "deadline_minutes": 0–59 (facultatif ; total > 0),
##                      "par_hours": > 0 ou null,
##                      "objectives": [ {"type": "photo" | "strike", "target": {"lat", "lon"},
##                                       "tolerance_km" (facultatif), "weight" (1), "yield_kt" (tir, facultatif),
##                                       "after": indice d'un objectif précédent (facultatif)} … ],
##                      "result": [ MESSAGE … ] (facultatif)} … },
##   "ending": [ MESSAGE … ]
## }
## DÉPART : {"utc": "2035-07-15T06:00:00Z", "orbit": {"altitude_km": 200–800, "inclination_deg": 0–80,
##           "over": {"lat", "lon"}, "ascending": true}} (|lat| ≤ inclinaison).
## TEXTE : clé des fichiers de langue, texte, ou dictionnaire par langue {"en": …, "fr": …} (Campaigns.text_of).
## MESSAGE : {"when": CONDITION (facultatif), "subject": TEXTE, "body": TEXTE} : le premier dont la condition est
##           vraie est retenu (le dernier, sans condition, sert de message par défaut).
## CONDITION : {"global_score" | "day_score" | "mission_score": {"min": x, "max": y}, "score_of": {"id": ID,
##             "min": x, "max": y}} : toutes vraies (min inclus, max exclu ; notes sur 20). Une note encore inconnue
##             (aucune mission jouée…) rend la condition fausse.

const FORMAT := 2
const OBJECTIVE_TYPES: Array[String] = ["photo", "strike"]
const SCORE_KEYS: Array[String] = ["global_score", "day_score", "mission_score"]
const MAX_SCORE := 20.0
## Sommeil (h) avant une journée sans départ ni heure de réveil.
const NIGHT_HOURS := 8.0

## Contenu brut (campaign.json) et erreurs trouvées.
var data := {}
var errors := PackedStringArray()


## Lit et vérifie un campaign.json déjà décodé.
static func parse(raw: Dictionary) -> CampaignData:
	var campaign := CampaignData.new()
	campaign.data = raw
	campaign._validate()
	return campaign


func is_valid() -> bool:
	return errors.is_empty()


func days() -> Array:
	return data.get("days", [])


func mission(id: String) -> Dictionary:
	return (data.get("missions", {}) as Dictionary).get(id, {})


func defaults() -> Dictionary:
	return data.get("defaults", {})


## Départ de la journée day_index : le sien, sinon celui de la campagne pour la première journée ; {} sinon (la
## journée reprend là où la précédente s'est arrêtée).
func start_of_day(day_index: int) -> Dictionary:
	var day: Dictionary = days()[day_index]
	if day.has("start"):
		return day.start
	return data.get("start", {}) if day_index == 0 else {}


## Missions de la journée day_index dont la condition est vraie, dans l'ordre (identifiants).
func missions_of_day(day_index: int, scores: Dictionary) -> PackedStringArray:
	var ids := PackedStringArray()
	for entry: Dictionary in days()[day_index].get("missions", []):
		if check(entry.get("when", {}), scores):
			ids.append(entry.mission)
	return ids


## Premier message de la liste dont la condition est vraie ({} si aucun).
static func pick_message(messages: Array, scores: Dictionary) -> Dictionary:
	for message: Dictionary in messages:
		if check(message.get("when", {}), scores):
			return message
	return {}


## Condition vraie pour les notes connues (scores : global_score, day_score, mission_score, et "of" : {id: note}).
static func check(when: Dictionary, scores: Dictionary) -> bool:
	for key: String in when:
		var bounds: Dictionary = when[key]
		var value: Variant = scores.get("of", {}).get(bounds.get("id", ""), null) if key == "score_of" \
				else scores.get(key, null)
		if value == null:
			return false
		if bounds.has("min") and float(value) < float(bounds.min):
			return false
		if bounds.has("max") and float(value) >= float(bounds.max):
			return false
	return true


## Instant UTC (secondes Unix) d'une date ISO 8601 (« 2035-07-15T06:00:00Z ») ; NAN si illisible.
static func parse_utc(text: String) -> float:
	var clean := text.strip_edges().trim_suffix("Z")
	# Forme vérifiée d'abord : Time signale lui-même (erreur moteur) une date qu'il ne sait pas lire.
	var pattern := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2}(:\\d{2})?)?$")
	if pattern.search(clean) == null:
		return NAN
	var unix := Time.get_unix_time_from_datetime_string(clean)
	# Une date illisible donne 0 (1970) : refusée, le jeu se passe bien après.
	return float(unix) if unix > 0 else NAN


# --- Vérification ---------------------------------------------------------------------------------------------------

func _validate() -> void:
	errors.clear()
	if int(data.get("format", 0)) != FORMAT:
		_error("format : %d attendu (trouvé : %s)" % [FORMAT, str(data.get("format", "absent"))])
		return
	_check_text(data, "name", "campagne")
	if data.has("description"):
		_check_text(data, "description", "campagne")
	_check_start(data.get("start", null), "start")
	var missions: Variant = data.get("missions", null)
	if not missions is Dictionary or (missions as Dictionary).is_empty():
		_error("missions : dictionnaire de missions attendu, non vide")
		missions = {}
	for id: String in missions:
		_check_mission(id, missions[id])
	var day_list: Variant = data.get("days", null)
	if not day_list is Array or (day_list as Array).is_empty():
		_error("days : liste de journées attendue, non vide")
		return
	var seen := {}
	for k in (day_list as Array).size():
		var day: Variant = day_list[k]
		var where := "days[%d]" % k
		if not day is Dictionary:
			_error("%s : objet attendu" % where)
			continue
		var id := str(day.get("id", ""))
		if id.is_empty() or seen.has(id):
			_error("%s : identifiant (id) manquant ou en double" % where)
		seen[id] = true
		if day.has("start"):
			_check_start(day.start, where + ".start")
		elif k == 0 and not data.has("start"):
			_error("%s : pas de départ (ni start de la campagne, ni start de la journée)" % where)
		if day.has("wake_up_utc") and not _is_clock(str(day.wake_up_utc)):
			_error("%s.wake_up_utc : heure « HH:MM » attendue" % where)
		var entries: Variant = day.get("missions", null)
		if not entries is Array or (entries as Array).is_empty():
			_error("%s.missions : liste attendue, non vide" % where)
		else:
			for m in (entries as Array).size():
				var entry: Variant = entries[m]
				if not entry is Dictionary or not (missions as Dictionary).has(str(entry.get("mission", ""))):
					_error("%s.missions[%d] : mission inconnue" % [where, m])
				elif entry.has("when"):
					_check_condition(entry.when, "%s.missions[%d].when" % [where, m])
		_check_messages(day.get("debrief", []), where + ".debrief")
	_check_messages(data.get("ending", []), "ending")


func _check_start(start: Variant, where: String) -> void:
	if start == null:
		return
	if not start is Dictionary:
		_error("%s : objet attendu" % where)
		return
	if is_nan(parse_utc(str(start.get("utc", "")))):
		_error("%s.utc : date « AAAA-MM-JJTHH:MM:SSZ » attendue" % where)
	var orbit: Variant = start.get("orbit", null)
	if not orbit is Dictionary:
		_error("%s.orbit : objet attendu" % where)
		return
	var altitude := float(orbit.get("altitude_km", -1.0))
	if altitude < OrbitSimulation.MIN_ALTITUDE_KM or altitude > OrbitSimulation.MAX_ALTITUDE_KM:
		_error("%s.orbit.altitude_km : de %d à %d km" % [where, OrbitSimulation.MIN_ALTITUDE_KM,
				OrbitSimulation.MAX_ALTITUDE_KM])
	var inclination := float(orbit.get("inclination_deg", -1.0))
	if inclination < 0.0 or inclination > OrbitSimulation.MAX_INCLINATION_DEG:
		_error("%s.orbit.inclination_deg : de 0 à %d°" % [where, OrbitSimulation.MAX_INCLINATION_DEG])
	var over: Variant = orbit.get("over", null)
	if _check_point(over, where + ".orbit.over") and absf(float(over.lat)) > inclination:
		_error("%s.orbit.over.lat : latitude au-delà de l'inclinaison (|lat| ≤ inclinaison)" % where)


func _check_mission(id: String, mission_data: Variant) -> void:
	var where := "missions.%s" % id
	if not mission_data is Dictionary:
		_error("%s : objet attendu" % where)
		return
	for field in ["title", "objective", "description"]:
		_check_text(mission_data, field, where)
	var hours := float(mission_data.get("deadline_hours", -1.0))
	var minutes := float(mission_data.get("deadline_minutes", 0.0))
	if hours < 0.0 or minutes < 0.0 or minutes >= 60.0 or hours * 60.0 + minutes <= 0.0:
		_error("%s.deadline_hours / deadline_minutes : durée positive attendue (heures, minutes de 0 à 59)" % where)
	if mission_data.get("par_hours", null) != null and float(mission_data.par_hours) <= 0.0:
		_error("%s.par_hours : durée (heures) positive, ou null" % where)
	var objectives: Variant = mission_data.get("objectives", null)
	if not objectives is Array or (objectives as Array).is_empty():
		_error("%s.objectives : liste attendue, non vide" % where)
		return
	for k in (objectives as Array).size():
		var objective: Variant = objectives[k]
		var at := "%s.objectives[%d]" % [where, k]
		if not objective is Dictionary:
			_error("%s : objet attendu" % at)
			continue
		if not str(objective.get("type", "")) in OBJECTIVE_TYPES:
			_error("%s.type : « photo » ou « strike »" % at)
		_check_point(objective.get("target", null), at + ".target")
		if objective.has("tolerance_km") and float(objective.tolerance_km) <= 0.0:
			_error("%s.tolerance_km : positive" % at)
		if objective.has("weight") and float(objective.weight) <= 0.0:
			_error("%s.weight : positif" % at)
		if objective.has("yield_kt") and (float(objective.yield_kt) < NukeScaling.MIN_YIELD_KT
				or float(objective.yield_kt) > NukeScaling.MAX_YIELD_KT):
			_error("%s.yield_kt : de %d à %d kt" % [at, NukeScaling.MIN_YIELD_KT, NukeScaling.MAX_YIELD_KT])
		if objective.has("after") and (int(objective.after) < 0 or int(objective.after) >= k):
			_error("%s.after : indice d'un objectif précédent" % at)
	_check_messages(mission_data.get("result", []), where + ".result")


func _check_messages(messages: Variant, where: String) -> void:
	if not messages is Array:
		_error("%s : liste de messages attendue" % where)
		return
	for k in (messages as Array).size():
		var message: Variant = messages[k]
		var at := "%s[%d]" % [where, k]
		if not message is Dictionary:
			_error("%s : objet attendu" % at)
			continue
		_check_text(message, "body", at)
		if message.has("subject"):
			_check_text(message, "subject", at)
		if message.has("when"):
			_check_condition(message.when, at + ".when")


func _check_condition(when: Variant, where: String) -> void:
	if not when is Dictionary:
		_error("%s : objet attendu" % where)
		return
	for key: String in when:
		var bounds: Variant = when[key]
		if not key in SCORE_KEYS and key != "score_of":
			_error("%s : condition inconnue « %s »" % [where, key])
			continue
		if not bounds is Dictionary or not (bounds.has("min") or bounds.has("max")):
			_error("%s.%s : {\"min\": …, \"max\": …} attendu" % [where, key])
			continue
		for bound in ["min", "max"]:
			if bounds.has(bound) and (float(bounds[bound]) < 0.0 or float(bounds[bound]) > MAX_SCORE):
				_error("%s.%s.%s : note de 0 à 20" % [where, key, bound])
		if key == "score_of" and mission(str(bounds.get("id", ""))).is_empty():
			_error("%s.score_of.id : mission inconnue" % where)


## Point {lat, lon} valide ; faux (avec une erreur) sinon.
func _check_point(point: Variant, where: String) -> bool:
	if not point is Dictionary or not point.has("lat") or not point.has("lon"):
		_error("%s : {\"lat\": …, \"lon\": …} attendu" % where)
		return false
	if absf(float(point.lat)) > 90.0 or absf(float(point.lon)) > 180.0:
		_error("%s : latitude de -90 à 90, longitude de -180 à 180" % where)
		return false
	return true


func _check_text(owner: Dictionary, field: String, where: String) -> void:
	var value: Variant = owner.get(field, null)
	if value is String and not (value as String).is_empty():
		return
	if value is Dictionary and not (value as Dictionary).is_empty():
		return
	_error("%s.%s : texte (clé de langue, texte ou dictionnaire par langue) attendu" % [where, field])


static func _is_clock(text: String) -> bool:
	var parts := text.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() \
			and int(parts[0]) >= 0 and int(parts[0]) < 24 and int(parts[1]) >= 0 and int(parts[1]) < 60


func _error(message: String) -> void:
	errors.append(message)
