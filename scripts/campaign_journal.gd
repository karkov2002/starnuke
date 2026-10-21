class_name CampaignJournal
extends RefCounted
## Journal de partie d'une campagne (CampaignDirector) : un fichier JSON Lines par partie lancée (nouvelle campagne ou
## « Continuer »), user://logs/<campagne>_<date et heure réelles>.jsonl, une ligne par événement :
## {"event", "real" (heure réelle locale), "utc" (heure du jeu, ISO), "unix" (heure du jeu, s), …champs de
## l'événement}. Il sert à régler les profils du banc d'équilibrage (tools/balance_campaign.gd) d'après de vraies
## parties : retards sur le passage le plus tôt possible, distances des photos et des tirs, qualité des poussées.
## Événements : session, day_start, mission_start, burn, shot, mission_end, day_end, sleep, campaign_end (champs :
## voir CampaignDirector). Le fichier est vidé sur le disque à chaque ligne : rien n'est perdu si le jeu s'arrête.

const FOLDER := "user://logs"

var path := ""
var _file: FileAccess


## Ouvre un nouveau journal pour la campagne campaign_id ; sans effet (journal muet) si le fichier ne s'ouvre pas.
func _init(campaign_id: String) -> void:
	if DirAccess.make_dir_recursive_absolute(FOLDER) != OK:
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	path = FOLDER.path_join("%s_%s.jsonl" % [campaign_id, stamp])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("CampaignJournal : %s impossible à ouvrir" % path)


## Ajoute un événement à l'heure du jeu game_unix (s).
func write(event: String, game_unix: float, data := {}) -> void:
	if _file == null:
		return
	var line := {"event": event, "real": Time.get_datetime_string_from_system(),
			"utc": Time.get_datetime_string_from_unix_time(int(game_unix)) + "Z", "unix": game_unix}
	line.merge(data)
	_file.store_line(JSON.stringify(line))
	_file.flush()
