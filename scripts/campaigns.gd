class_name Campaigns
extends RefCounted
## Modes de jeu et campagnes. Mode de la partie lancée depuis l'écran de démarrage (scripts/ui/main_menu.gd) : libre
## (le jeu tel quel) ou campagne ; il est retenu ici (variables statiques) le temps de la session, d'une scène à
## l'autre.
##
## Campagnes : un sous-dossier du dossier « campaign » par campagne (son nom de dossier est son identifiant), qui
## contient un fichier campaign.json. Comme les playlists (scripts/music_player.gd), le dossier est lu sur le disque,
## jamais importé ni mis dans le .pck (.gdignore) : dans le jeu exporté, c'est le dossier campaign/ à côté de
## l'exécutable (copié par tools/package_game.ps1), où les joueurs ajoutent leurs propres campagnes ; dans l'éditeur,
## campaign/ du projet. Campagne officielle : « starnuke ».
##
## campaign.json : format 2, décrit et vérifié par CampaignData (scripts/campaign_data.gd) ; name et description :
## clé des fichiers de langue (campagne officielle), texte, ou dictionnaire par langue ({"en": "...", "fr": "..."} :
## langue du jeu, sinon l'anglais, sinon la première). Un dossier sans campaign.json lisible (JSON invalide, pas
## d'objet) n'est pas proposé ; une campagne avec des erreurs l'est (grisée, avec leur nombre) mais ne se lance pas.

enum Mode { FREE, CAMPAIGN }

const FOLDER := "campaign"
const FILE := "campaign.json"
const OFFICIAL := "starnuke"

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
	return {"global_score": global_score(), "day_score": day_total / day_count if day_count > 0 else null,
			"mission_score": of.get(mission_id, null), "of": of}


## Dossier des campagnes (chemin absolu) : à côté de l'exécutable dans le jeu exporté, celui du projet sinon.
static func root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + FOLDER)
	return OS.get_executable_path().get_base_dir().path_join(FOLDER)


## Campagnes disponibles : [{id, data, campaign (CampaignData : erreurs)}], la campagne officielle d'abord, puis par
## ordre alphabétique.
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for id in DirAccess.get_directories_at(root()):
		var data := read(id)
		if not data.is_empty():
			found.append({"id": id, "data": data, "campaign": CampaignData.parse(data)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a.id == OFFICIAL) != (b.id == OFFICIAL):
			return a.id == OFFICIAL
		return String(a.id).naturalnocasecmp_to(b.id) < 0)
	return found


## Contenu du campaign.json d'une campagne ; vide s'il manque ou n'est pas un objet JSON.
static func read(id: String) -> Dictionary:
	var path := root().path_join(id).path_join(FILE)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_warning("Campaigns : %s illisible (JSON invalide ou pas un objet)" % path)
	return {}


## Texte d'un champ de campaign.json (name, description) : clé de langue ou texte, ou dictionnaire par langue.
static func text_of(data: Dictionary, field: String, fallback := "") -> String:
	var value: Variant = data.get(field, fallback)
	if value is Dictionary:
		var by_language: Dictionary = value
		if by_language.is_empty():
			return fallback
		var language := TranslationServer.get_locale().get_slice("_", 0)
		return str(by_language.get(language, by_language.get("en", by_language.values()[0])))
	return TranslationServer.translate(str(value))


## Une campagne en cours peut-elle être continuée ? (Pas de sauvegarde de campagne pour le moment.)
static func has_saved() -> bool:
	return false


static func start_free() -> void:
	mode = Mode.FREE
	current_id = ""
	current = null
	day_index = 0
	results = {}
	day_scores = {}


## Nouvelle campagne id (dossier de campaign/), à sa première journée. Faux si elle est introuvable, illisible ou a
## des erreurs (détail dans la console).
static func start_campaign(id: String) -> bool:
	var data := read(id)
	if data.is_empty():
		return false
	var campaign := CampaignData.parse(data)
	if not campaign.is_valid():
		push_warning("Campaigns : %s a %d erreur(s) :\n%s" % [id, campaign.errors.size(), "\n".join(campaign.errors)])
		return false
	mode = Mode.CAMPAIGN
	current_id = id
	current = campaign
	day_index = 0
	results = {}
	day_scores = {}
	return true
