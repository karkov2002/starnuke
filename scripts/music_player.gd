extends Node
## Lecteur de musique (autoload Music) : joue en boucle tous les morceaux de la playlist choisie
## (GameSettings.playlist), sur le bus « Music » (volume : GameSettings.music_volume).
##
## Playlists : un sous-dossier du dossier « playlist » par playlist (le nom du dossier est celui de la playlist) ;
## tous les fichiers .mp3, .ogg et .wav qu'il contient sont joués dans l'ordre alphabétique, puis on recommence.
## Le dossier est lu sur le disque, jamais importé ni mis dans le .pck (.gdignore) : dans le jeu exporté, c'est le
## dossier playlist/ à côté de l'exécutable (copié par tools/package_game.ps1), où le joueur ajoute les siennes ;
## dans l'éditeur, playlist/ du projet. La liste est relue à chaque ouverture des paramètres et au lancement d'une
## partie (une playlist ajoutée pendant que le jeu tourne apparaît sans le relancer). Playlist par défaut :
## « starnuke ».
## La musique joue pendant la partie (scène GAME_SCENE, pause comprise) et s'arrête hors partie (écran de démarrage).
## Changer de playlist dans les paramètres en cours de partie lance aussitôt la nouvelle.

const FOLDER := "playlist"
const GAME_SCENE := "res://scenes/orbit_view.tscn"
const EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
const BUS := &"Music"

var _player: AudioStreamPlayer
var _tracks: Array[String] = []
var _index := -1
var _playing_list := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = BUS
	_player.finished.connect(_next)
	add_child(_player)
	get_tree().scene_changed.connect(_on_scene_changed)
	GameSettings.changed.connect(func() -> void:
		if is_playing() and GameSettings.playlist != _playing_list:
			play_playlist(GameSettings.playlist))
	_on_scene_changed.call_deferred()


## Dossier des playlists (chemin absolu) : à côté de l'exécutable dans le jeu exporté, celui du projet sinon.
func root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + FOLDER)
	return OS.get_executable_path().get_base_dir().path_join(FOLDER)


## Noms des playlists disponibles (sous-dossiers contenant au moins un morceau), triés.
func playlists() -> Array[String]:
	var names: Array[String] = []
	for dir in DirAccess.get_directories_at(root()):
		if not tracks_of(dir).is_empty():
			names.append(dir)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


## Morceaux d'une playlist (chemins absolus), dans l'ordre alphabétique des noms.
func tracks_of(playlist_name: String) -> Array[String]:
	var tracks: Array[String] = []
	var dir := root().path_join(playlist_name)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			tracks.append(dir.path_join(file))
	tracks.sort_custom(func(a: String, b: String) -> bool:
		return a.get_file().get_basename().naturalnocasecmp_to(b.get_file().get_basename()) < 0)
	return tracks


func is_playing() -> bool:
	return _playing_list != ""


func play_playlist(playlist_name: String) -> void:
	_tracks = tracks_of(playlist_name)
	if _tracks.is_empty():
		var available := playlists()
		if available.is_empty():
			push_warning("Music : aucune playlist dans %s" % root())
			stop()
			return
		playlist_name = available[0]
		_tracks = tracks_of(playlist_name)
	_playing_list = playlist_name
	_index = -1
	# Une ligne au lancement de la playlist (journal : vérifie aussi la version exportée).
	print("Music : playlist « %s », %d morceau(x) (%s)" % [playlist_name, _tracks.size(), root()])
	_next()


func stop() -> void:
	_playing_list = ""
	_tracks.clear()
	_player.stop()


## Morceau suivant (le premier après le dernier) ; un fichier illisible est sauté.
func _next() -> void:
	for attempt in _tracks.size():
		_index = (_index + 1) % _tracks.size()
		var stream := _load(_tracks[_index])
		if stream:
			_player.stream = stream
			_player.play()
			return
		push_warning("Music : morceau illisible %s" % _tracks[_index])
	stop()


## Fichier audio lu sur le disque (pas d'import : le joueur dépose ses fichiers tels quels).
static func _load(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var in_game := scene != null and scene.scene_file_path == GAME_SCENE
	if in_game and not is_playing():
		play_playlist(GameSettings.playlist)
	elif not in_game and is_playing():
		stop()
