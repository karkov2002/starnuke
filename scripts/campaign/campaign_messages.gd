class_name CampaignMessages
extends RefCounted
## Messages radio d'une campagne (CampaignDirector les poste à RadioComms) : gabarits des fichiers de langue
## (BRIEFING_*, RESULT_*, OBJECTIVE_*) remplis avec les textes de campaign.json (Campaigns.text_of). Chaque message
## est un dictionnaire pour RadioComms.post : from et channel de la mission, sinon des defaults de la campagne
## (COMM_FROM_GROUND, tous les canaux), subject, body, et id s'il est réservé d'avance.

const DEFAULT_FROM := "COMM_FROM_GROUND"


## Briefing selon le gabarit : mission, objectif, texte, cibles (type et coordonnées), durée avant échec (toujours
## avec les minutes : « 6 h 00 min », « 5 h 30 min »).
static func briefing(mission: Dictionary, defaults: Dictionary, id := "") -> Dictionary:
	var targets := PackedStringArray()
	for objective: Dictionary in mission.objectives:
		var kind := _tr("OBJECTIVE_PHOTO" if objective.type == "photo" else "OBJECTIVE_STRIKE")
		targets.append("  %s : %s" % [kind, GeoMath.format_lat_lon(float(objective.target.lat),
				float(objective.target.lon))])
	var minutes := roundi(CampaignData.deadline_s(mission) / 60.0)
	var duration := "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]
	var body := _tr("BRIEFING_BODY").format({"title": Campaigns.text_of(mission, "title"),
			"objective": Campaigns.text_of(mission, "objective"),
			"description": Campaigns.text_of(mission, "description"), "targets": "\n".join(targets),
			"duration": duration})
	var message := envelope(mission, defaults, briefing_subject(mission), body)
	if not id.is_empty():
		message.id = id
	return message


## Objet du briefing (aussi affiché par l'appel prioritaire).
static func briefing_subject(mission: Dictionary) -> String:
	return _tr("BRIEFING_SUBJECT").format({"title": Campaigns.text_of(mission, "title")})


## Expéditeur du briefing, traduit (appel prioritaire) : celui de la mission, sinon des defaults.
static func sender(mission: Dictionary, defaults: Dictionary) -> String:
	return Campaigns.text_of(mission if mission.has("from") else defaults, "from", DEFAULT_FROM)


## Résultat d'une mission (result : score, success, precision, time_factor, expired, voir MissionRun) : échéance
## dépassée, RESULT_EXPIRED (mission échouée, 0/20) ; sinon message « result » de la mission choisi selon les notes
## (scores, CampaignData.pick_message), sinon RESULT_DEFAULT_*, avec la note, le verdict, la précision et le facteur
## temps.
static func result(mission: Dictionary, defaults: Dictionary, scores: Dictionary, result: Dictionary) -> Dictionary:
	var success := bool(result.success)
	var message := CampaignData.pick_message(mission.get("result", []), scores)
	var text := Campaigns.text_of(message, "body") if not message.is_empty() \
			else _tr("RESULT_DEFAULT_SUCCESS" if success else "RESULT_DEFAULT_FAILURE")
	if result.get("expired", false):
		text = _tr("RESULT_EXPIRED")
	var body := _tr("RESULT_BODY").format({"message": text, "score": "%.1f" % float(result.score),
			"verdict": _tr("RESULT_SUCCESS" if success else "RESULT_FAILURE"),
			"precision": "%.1f" % float(result.precision), "time": "%.2f" % float(result.time_factor)})
	return envelope(mission, defaults, _tr("RESULT_SUBJECT").format({"title": Campaigns.text_of(mission, "title")}),
			body)


## Débriefing de journée ou message de fin de campagne (message de campaign.json : subject, body) ; expéditeur et
## canal des defaults.
static func debrief(message: Dictionary, defaults: Dictionary) -> Dictionary:
	return envelope({}, defaults, Campaigns.text_of(message, "subject", "BRIEFING_DEBRIEF"),
			Campaigns.text_of(message, "body"))


## Enveloppe d'un message : expéditeur et canal de la mission, sinon des defaults (vide : {} pour la mission).
static func envelope(mission: Dictionary, defaults: Dictionary, subject: String, body: String) -> Dictionary:
	return {"from": mission.get("from", defaults.get("from", DEFAULT_FROM)), "subject": subject, "body": body,
			"channel": int(mission.get("channel", defaults.get("channel", -1)))}


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
