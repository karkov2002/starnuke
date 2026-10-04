extends MeshInstance3D
## Streaming des tuiles haute résolution (500 m/pixel) autour du point survolé. Trois jeux de tuiles au même
## découpage : jour (Blue Marble NG), nuit (Black Marble 2016) et couverture nuageuse (VIIRS, cf.
## tools/build_cloud_tiles.ps1).
##
## La surface est découpée en tuiles de 5° (72 colonnes x 36 lignes). Une fenêtre de WINDOW x WINDOW tuiles centrée
## sous l'observateur est gardée en mémoire vidéo, un Texture2DArray par jeu, tous avec la même attribution de
## couches. Les shaders (surface et nuages, cf. shaders/detail_window.gdshaderinc) les utilisent à la place des
## textures globales (16K) dans cette zone. Quand le point survolé change de tuile, seules les tuiles entrantes sont
## chargées (en tâche de fond) puis copiées dans les couches libérées.

const GRID_COLS := 72
const GRID_ROWS := 36
const WINDOW := 5
const TILE_SIZE := 1200

## Jeux de tuiles : dossier, extension, paramètres de shader (Texture2DArray, booléen « prêt »), format en mémoire.
const TILE_SETS := [
	{"dir": "res://assets/earth_tiles", "ext": "jpg", "param": "detail_tiles", "ready": "", "format": Image.FORMAT_RGB8},
	{"dir": "res://assets/earth_night_tiles", "ext": "jpg", "param": "night_tiles", "ready": "night_detail_ready", "format": Image.FORMAT_RGB8},
	{"dir": "res://assets/earth_cloud_tiles", "ext": "webp", "param": "cloud_tiles", "ready": "cloud_detail_ready", "format": Image.FORMAT_L8},
]

## Point de vue autour duquel charger les tuiles ; par défaut la caméra active.
@export var observer_path: NodePath
## Autres maillages dont le ShaderMaterial utilise les tuiles (couche nuageuse).
@export var extra_material_paths: Array[NodePath] = [^"../CloudLayer"]
## Compresse les tuiles couleur en BC1 (VRAM / 8) : nettement plus lent à charger (compression CPU), et le
## compresseur n'existe que dans l'éditeur. Sans compression, les fenêtres occupent ~430 Mo de VRAM.
@export var compress_tiles := false

var _observer: Node3D
var _materials: Array[ShaderMaterial] = []
var _sets: Array[Dictionary] = [] # jeux disponibles (dont les tuiles existent)
var _arrays: Array[Texture2DArray] = []
var _use_compression := false
var _origin := Vector2i(-1, -1)
var _layer_of_tile := {} # Vector2i (col, row) -> couche des Texture2DArray

var _task_id := -1
var _pending_origin := Vector2i.ZERO
var _pending_tiles: Array[Vector2i] = []
var _pending_images: Array = [] # [jeu][tuile] -> Image
var _mutex := Mutex.new()


func _ready() -> void:
	_observer = get_node_or_null(observer_path) as Node3D
	if _observer == null:
		_observer = get_viewport().get_camera_3d()
	if material_override is ShaderMaterial:
		_materials.append(material_override)
	for path in extra_material_paths:
		var geometry := get_node_or_null(path) as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			_materials.append(geometry.material_override)
	for tile_set: Dictionary in TILE_SETS:
		if FileAccess.file_exists(_tile_path(tile_set, Vector2i.ZERO)):
			_sets.append(tile_set)
	if _observer == null or _materials.is_empty() or _sets.is_empty() or _sets[0] != TILE_SETS[0]:
		push_warning("earth_detail_tiles : observateur, matériau ou tuiles de jour manquants (tools/build_earth_tiles.ps1), tuiles HD désactivées")
		set_process(false)
		return
	# Le compresseur BC1 n'existe pas dans tous les exécutables (absent des modèles d'export) : on le teste.
	var probe := Image.create_empty(8, 8, false, Image.FORMAT_RGB8)
	_use_compression = compress_tiles and probe.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB) == OK
	_set_param("detail_ready", false)
	for tile_set in _sets:
		if tile_set.ready != "":
			_set_param(tile_set.ready, false)


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_task_id)


func _process(_delta: float) -> void:
	if _task_id != -1:
		if WorkerThreadPool.is_group_task_completed(_task_id):
			WorkerThreadPool.wait_for_group_task_completion(_task_id)
			_task_id = -1
			_apply_pending()
		return
	var wanted := _wanted_origin()
	if wanted != _origin:
		_start_loading(wanted)


## Origine (colonne, ligne) de la fenêtre centrée sur la tuile survolée.
func _wanted_origin() -> Vector2i:
	# Même convention que les UV de SphereMesh : u = 0 vers +Z, croissant vers +X ; v = 0 au pôle nord.
	var p := to_local(_observer.global_position).normalized()
	var u := fposmod(atan2(p.x, p.z) / TAU, 1.0)
	var v := acos(clampf(p.y, -1.0, 1.0)) / PI
	var col := int(u * GRID_COLS) % GRID_COLS
	var row := clampi(int(v * GRID_ROWS), 0, GRID_ROWS - 1)
	var half := WINDOW >> 1
	return Vector2i(posmod(col - half, GRID_COLS), clampi(row - half, 0, GRID_ROWS - WINDOW))


func _window_tiles(origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dr in WINDOW:
		for dc in WINDOW:
			tiles.append(Vector2i(posmod(origin.x + dc, GRID_COLS), origin.y + dr))
	return tiles


func _start_loading(origin: Vector2i) -> void:
	_pending_origin = origin
	_pending_tiles.clear()
	for tile in _window_tiles(origin):
		if _arrays.is_empty() or not _layer_of_tile.has(tile):
			_pending_tiles.append(tile)
	_pending_images.clear()
	for s in _sets.size():
		var images: Array[Image] = []
		images.resize(_pending_tiles.size())
		_pending_images.append(images)
	if _pending_tiles.is_empty():
		_apply_pending()
		return
	_task_id = WorkerThreadPool.add_group_task(_load_tile_task, _pending_tiles.size(), -1, false,
			"Chargement tuiles Terre HD")


func _load_tile_task(index: int) -> void:
	var tile := _pending_tiles[index]
	var loaded: Array[Image] = []
	for tile_set in _sets:
		loaded.append(_load_image(_tile_path(tile_set, tile), tile_set.format))
	_mutex.lock()
	for s in _sets.size():
		_pending_images[s][index] = loaded[s]
	_mutex.unlock()


func _load_image(path: String, format: Image.Format) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	var error := ERR_FILE_NOT_FOUND
	if not bytes.is_empty():
		error = image.load_webp_from_buffer(bytes) if path.ends_with(".webp") else image.load_jpg_from_buffer(bytes)
	if error != OK:
		image = Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGB8)
	image.convert(format)
	image.generate_mipmaps()
	if _use_compression and format == Image.FORMAT_RGB8:
		image.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
	return image


func _apply_pending() -> void:
	var window := _window_tiles(_pending_origin)
	if _arrays.is_empty():
		for s in _sets.size():
			var array := Texture2DArray.new()
			array.create_from_images(_pending_images[s])
			_arrays.append(array)
		_layer_of_tile.clear()
		for i in _pending_tiles.size():
			_layer_of_tile[_pending_tiles[i]] = i
	else:
		var free_layers: Array[int] = []
		for tile in _layer_of_tile.keys():
			if not window.has(tile):
				free_layers.append(_layer_of_tile[tile])
				_layer_of_tile.erase(tile)
		for i in _pending_tiles.size():
			var layer: int = free_layers.pop_back()
			for s in _sets.size():
				_arrays[s].update_layer(_pending_images[s][i], layer)
			_layer_of_tile[_pending_tiles[i]] = layer
	_pending_images.clear()

	var layer_map := PackedInt32Array()
	for tile in window:
		layer_map.append(_layer_of_tile[tile])
	_origin = _pending_origin
	for s in _sets.size():
		_set_param(_sets[s].param, _arrays[s])
		if _sets[s].ready != "":
			_set_param(_sets[s].ready, true)
	_set_param("detail_layer_map", layer_map)
	_set_param("detail_origin", _origin)
	_set_param("detail_ready", true)


func _set_param(param: String, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(param, value)


func _tile_path(tile_set: Dictionary, tile: Vector2i) -> String:
	return (tile_set.dir as String).path_join("r%02d_c%02d.%s" % [tile.y, tile.x, tile_set.ext])
