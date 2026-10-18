extends Node
## Lecteur de musique (autoload Music) : joue en boucle tous les morceaux de la playlist choisie
## (GameSettings.playlist), sur le bus « Music » (volume : GameSettings.music_volume).
##
## Playlists : un sous-dossier de res://playlist/ par playlist (le nom du dossier est celui de la playlist) ; tous les
## fichiers .mp3, .ogg et .wav qu'il contient sont joués dans l'ordre alphabétique, puis on recommence. Playlist par
## défaut : « starnuke ». Pour en ajouter une : créer le dossier, y déposer les morceaux, rescan dans l'éditeur.
## La musique joue pendant la partie (scène GAME_SCENE, pause comprise) et s'arrête hors partie (écran de démarrage).
## Changer de playlist dans les paramètres en cours de partie lance aussitôt la nouvelle.

const ROOT := "res://playlist/"
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


## Noms des playlists disponibles (sous-dossiers de ROOT contenant au moins un morceau), triés.
func playlists() -> Array[String]:
	var names: Array[String] = []
	for dir in DirAccess.get_directories_at(ROOT):
		if not tracks_of(dir).is_empty():
			names.append(dir)
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return names


## Morceaux d'une playlist (chemins res://), dans l'ordre alphabétique. ResourceLoader.list_directory voit aussi
## les fichiers importés d'un jeu exporté (où seuls les .import et le cache sont présents).
func tracks_of(playlist_name: String) -> Array[String]:
	var tracks: Array[String] = []
	var dir := ROOT + playlist_name + "/"
	for file in ResourceLoader.list_directory(dir):
		if file.get_extension().to_lower() in EXTENSIONS:
			tracks.append(dir + file)
	tracks.sort_custom(func(a: String, b: String) -> bool:
		return a.get_basename().naturalnocasecmp_to(b.get_basename()) < 0)
	return tracks


func is_playing() -> bool:
	return _playing_list != ""


func play_playlist(playlist_name: String) -> void:
	_tracks = tracks_of(playlist_name)
	if _tracks.is_empty():
		var available := playlists()
		if available.is_empty():
			push_warning("Music : aucune playlist dans %s" % ROOT)
			stop()
			return
		playlist_name = available[0]
		_tracks = tracks_of(playlist_name)
	_playing_list = playlist_name
	_index = -1
	# Une ligne au lancement de la playlist (journal : vérifie aussi la version exportée).
	print("Music : playlist « %s », %d morceau(x)" % [playlist_name, _tracks.size()])
	_next()


func stop() -> void:
	_playing_list = ""
	_tracks.clear()
	_player.stop()


func _next() -> void:
	if _tracks.is_empty():
		return
	_index = (_index + 1) % _tracks.size()
	_player.stream = load(_tracks[_index]) as AudioStream
	_player.play()


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var in_game := scene != null and scene.scene_file_path == GAME_SCENE
	if in_game and not is_playing():
		play_playlist(GameSettings.playlist)
	elif not in_game and is_playing():
		stop()
