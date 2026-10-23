class_name CampaignSession
extends RefCounted
## Partie en cours (variables statiques, retenues le temps de la session, d'une scène à l'autre) : mode de jeu choisi
## à l'écran de démarrage (scripts/ui/main_menu.gd), libre (le jeu tel quel) ou campagne ; en campagne, la campagne
## (identifiant et contenu vérifié, catalogue : Campaigns), la journée en cours, les notes des missions et des
## journées, et la sauvegarde (un seul emplacement : la campagne en cours, écrite au coucher par CampaignDirector,
## reprise par « Continuer »).

enum Mode { FREE, CAMPAIGN }

## Sauvegarde de la campagne en cours (un seul emplacement ; les bancs de mesure la redirigent) et version de son format.
static var save_path := "user://saves/campaign.json"
const SAVE_FORMAT := 1

## Mode de la partie en cours (ou de la dernière lancée).
static var mode := Mode.FREE
## Campagne en cours : identifiant (nom du dossier), contenu vérifié de son campaign.json et journée en cours
## (indice) ; vides en mode libre.
static var current_id := ""
static var current: CampaignData
static var day_index := 0
## Résultats des missions jouées : identifiant -> {score, success, precision, time_factor, day} (notes sur 20), et
## note de chaque journée terminée : identifiant -> note.
static var results := {}
static var day_scores := {}
## Monde d'une sauvegarde à recréer au lancement (continue_saved ; pris par CampaignDirector, take_pending_world).
static var pending_world := {}


## Moyenne globale de la campagne (toutes les missions jouées, échecs compris) ; null avant la première.
static func global_score() -> Variant:
	if results.is_empty():
		return null
	var total := 0.0
	for id: String in results:
		total += float(results[id].score)
	return total / results.size()


## Notes connues, pour les conditions de CampaignData (global_score, day_score, mission_score, of) : day_id et
## mission_id désignent la journée et la mission en cours ("" : aucune).
static func scores(day_id: String, mission_id: String) -> Dictionary:
	var of := {}
	for id: String in results:
		of[id] = float(results[id].score)
	var day_total := 0.0
	var day_count := 0
	for id: String in results:
		if results[id].day == day_id:
			day_total += float(results[id].score)
			day_count += 1
	var day_score: Variant = null
	if day_count > 0:
		day_score = day_total / day_count
	return {"global_score": global_score(), "day_score": day_score,
			"mission_score": of.get(mission_id, null), "of": of}


## Monde à recréer d'une sauvegarde reprise ({} s'il n'y en a pas), rendu une seule fois.
static func take_pending_world() -> Dictionary:
	var world := pending_world
	pending_world = {}
	return world


## Une campagne en cours peut-elle être continuée ? Sauvegarde présente et lisible, campagne toujours là et valide.
static func has_saved() -> bool:
	var saved := _read_save()
	return not saved.is_empty() and CampaignData.parse(Campaigns.read(str(saved.get("campaign", "")))).is_valid()


## Sauvegarde de la campagne en cours (au coucher, CampaignDirector) : campagne, journée à venir, notes (missions,
## journées, moyenne globale) et monde (world : WorldSnapshot.capture). Rend vrai si le fichier est écrit.
static func save(world: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(save_path.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("CampaignSession : sauvegarde impossible (%s)" % save_path)
		return false
	file.store_string(JSON.stringify({"format": SAVE_FORMAT, "campaign": current_id, "day_index": day_index,
			"results": results, "day_scores": day_scores, "global_score": global_score(), "world": world}, "\t"))
	return true


## Reprend la campagne sauvegardée : mode campagne, journée, notes ; le monde à recréer est gardé dans pending_world
## (take_pending_world, CampaignDirector). Faux si la sauvegarde ou la campagne manque ou n'est plus valide.
static func continue_saved() -> bool:
	var saved := _read_save()
	if saved.is_empty() or not start_campaign(str(saved.get("campaign", ""))):
		return false
	day_index = clampi(int(saved.get("day_index", 0)), 0, current.days().size() - 1)
	results = saved.get("results", {})
	day_scores = saved.get("day_scores", {})
	pending_world = saved.get("world", {})
	return true


## Campagne terminée : plus rien à continuer.
static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


static func _read_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return parsed if parsed is Dictionary and int(parsed.get("format", 0)) == SAVE_FORMAT else {}


static func start_free() -> void:
	mode = Mode.FREE
	current_id = ""
	current = null
	day_index = 0
	results = {}
	day_scores = {}
	pending_world = {}


## Nouvelle campagne id (dossier de campaign/, Campaigns), à sa première journée. Faux si elle est introuvable,
## illisible ou a des erreurs (détail dans la console).
static func start_campaign(id: String) -> bool:
	var data := Campaigns.read(id)
	if data.is_empty():
		return false
	var campaign := CampaignData.parse(data)
	if not campaign.is_valid():
		push_warning("CampaignSession : %s a %d erreur(s) :\n%s" % [id, campaign.errors.size(),
				"\n".join(campaign.errors)])
		return false
	mode = Mode.CAMPAIGN
	current_id = id
	current = campaign
	day_index = 0
	results = {}
	day_scores = {}
	pending_world = {}
	return true
