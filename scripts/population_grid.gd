class_name PopulationGrid
extends RefCounted
## Grille mondiale de population (assets/population_2030.bin, générée par tools/build_population.ps1 à partir de
## GHS-POP R2023A, JRC / Commission européenne, époque 2030, licence CC BY 4.0) : habitants par cellule de 1/120°
## (~0,9 km), ligne 0 = 90° N, colonne 0 = 180° O, même découpage en lignes que OceanMask et CountryMask.
##
## Le fichier est découpé en tuiles de 5° (600 x 600 cellules, compressées) ; seules les tuiles utiles sont lues et
## gardées en mémoire (MAX_CACHED_TILES, ~1,4 Mo chacune). Chaque cellule est stockée sur 16 bits :
## habitants = (q / quant)².

const PATH := "res://assets/population_2030.bin"
const CELLS_PER_DEGREE := 120
const MAX_CACHED_TILES := 24

static var _file: FileAccess
static var _tiles_x := 0
static var _tiles_y := 0
static var _tile_cells := 0
static var _quant := 1.0
static var _offsets := PackedInt64Array()
static var _sizes := PackedInt32Array()
static var _sums := PackedFloat64Array()
static var _cache := {} # indice de tuile -> PackedByteArray (cellules quantifiées, 16 bits)
static var _cache_order: Array[int] = []
static var _mutex := Mutex.new()
static var _open_failed := false


## Le fichier est-il disponible ?
static func is_available() -> bool:
	_mutex.lock()
	var ok := _open()
	_mutex.unlock()
	return ok


static func row_count() -> int:
	return 180 * CELLS_PER_DEGREE


static func col_count() -> int:
	return 360 * CELLS_PER_DEGREE


static func row_of(latitude_deg: float) -> int:
	return clampi(int(floor((90.0 - latitude_deg) * CELLS_PER_DEGREE)), 0, row_count() - 1)


static func col_of(longitude_deg: float) -> int:
	return posmod(int(floor((wrapf(longitude_deg, -180.0, 180.0) + 180.0) * CELLS_PER_DEGREE)), col_count())


## Latitude et longitude (degrés) du centre d'une cellule.
static func cell_latitude(row: int) -> float:
	return 90.0 - (row + 0.5) / CELLS_PER_DEGREE


static func cell_longitude(col: int) -> float:
	return -180.0 + (posmod(col, col_count()) + 0.5) / CELLS_PER_DEGREE


## Habitants de la cellule (ligne, colonne ; la colonne fait le tour du globe). Sûr depuis un autre thread.
static func cell_population(row: int, col: int) -> float:
	if row < 0 or row >= row_count():
		return 0.0
	col = posmod(col, col_count())
	_mutex.lock()
	@warning_ignore("integer_division")
	var tile := _get_tile(row / _tile_cells, col / _tile_cells) if _open() else PackedByteArray()
	_mutex.unlock()
	if tile.is_empty():
		return 0.0
	var q := tile.decode_u16(((row % _tile_cells) * _tile_cells + col % _tile_cells) * 2) / _quant
	return q * q


## Population totale de la grille (somme des tuiles, avant quantification).
static func world_population() -> float:
	_mutex.lock()
	var total := 0.0
	if _open():
		for s in _sums:
			total += s
	_mutex.unlock()
	return total


static func _open() -> bool:
	if _file != null:
		return true
	if _open_failed:
		return false
	_file = FileAccess.open(PATH, FileAccess.READ) if FileAccess.file_exists(PATH) else null
	if _file == null or _file.get_buffer(8).get_string_from_ascii() != "SNPOP001":
		push_warning("PopulationGrid : %s introuvable ou invalide (tools/build_population.ps1)" % PATH)
		_file = null
		_open_failed = true
		return false
	_tiles_x = _file.get_32()
	_tiles_y = _file.get_32()
	_tile_cells = _file.get_32()
	_quant = _file.get_float()
	var count := _tiles_x * _tiles_y
	_offsets.resize(count)
	_sizes.resize(count)
	_sums.resize(count)
	for i in count:
		_offsets[i] = _file.get_64()
		_sizes[i] = _file.get_32()
		_sums[i] = _file.get_double()
	return true


## Tuile décompressée (cellules quantifiées ; vide si inhabitée), avec un petit cache (la plus ancienne est retirée).
## Appelée sous _mutex.
static func _get_tile(ty: int, tx: int) -> PackedByteArray:
	var index := ty * _tiles_x + tx
	if _cache.has(index):
		return _cache[index]
	var cells := PackedByteArray()
	if _offsets[index] > 0:
		_file.seek(_offsets[index])
		cells = _file.get_buffer(_sizes[index]).decompress(_tile_cells * _tile_cells * 2, FileAccess.COMPRESSION_DEFLATE)
	_cache[index] = cells
	_cache_order.append(index)
	if _cache_order.size() > MAX_CACHED_TILES:
		_cache.erase(_cache_order.pop_front())
	return cells
