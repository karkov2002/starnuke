class_name Campaigns
extends RefCounted
## Catalogue des campagnes (sur le disque) et textes de campaign.json. La partie en cours (mode de jeu, campagne
## choisie, journée, notes, sauvegarde) est dans CampaignSession (scripts/campaign/campaign_session.gd).
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

const FOLDER := "campaign"
const FILE := "campaign.json"
const OFFICIAL := "starnuke"


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


## Texte d'un champ de campaign.json (name, description, title, body…) : clé de langue ou texte, ou dictionnaire
## par langue.
static func text_of(data: Dictionary, field: String, fallback := "") -> String:
	var value: Variant = data.get(field, fallback)
	if value is Dictionary:
		var by_language: Dictionary = value
		if by_language.is_empty():
			return fallback
		var language := TranslationServer.get_locale().get_slice("_", 0)
		return str(by_language.get(language, by_language.get("en", by_language.values()[0])))
	return TranslationServer.translate(str(value))
