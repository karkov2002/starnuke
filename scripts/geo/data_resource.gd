class_name DataResource
extends RefCounted
## Chargement unique des ressources de données générées par les outils (masques, centrales, contours) : une
## ressource par chemin, gardée pour toute la durée du jeu ; un fichier manquant n'est cherché qu'une fois (avertissement
## qui nomme l'outil qui le produit). Sûr depuis un autre thread (les bilans des explosions lisent les masques).

static var _cache := {}
static var _failed := {}
static var _mutex := Mutex.new()


## Ressource du chemin (chargée à la première demande, puis la même), null si le fichier manque ; builder : outil qui
## le produit et conséquence, pour l'avertissement (« tools/build_country_mask.gd, aucun pays détecté »).
static func cached(path: String, builder: String) -> Resource:
	_mutex.lock()
	var resource: Resource = _cache.get(path)
	if resource == null and not _failed.has(path):
		resource = load(path) if ResourceLoader.exists(path) else null
		if resource:
			_cache[path] = resource
		else:
			_failed[path] = true
			push_warning("%s introuvable (%s)" % [path, builder])
	_mutex.unlock()
	return resource
