class_name NukeCellIndex
extends RefCounted
## Maille de 1° en longitude × latitude (CELLS_X × CELLS_Y, ligne 0 au nord) qui, pour chaque maille, liste les
## événements (explosions, panaches) dont un disque la touche, transmise aux shaders du sol par deux textures
## (nuke/shaders/nuke_ground.gdshaderinc) : cells (RGF : début, nombre dans la liste) et index (RF, INDEX_WIDTH de
## large : les identifiants, mailles à la suite). Un pixel du sol ne teste ainsi que les événements proches.
## Construction : clear, add_disc pour chaque disque, upload.

const INDEX_WIDTH := 4096
const CELLS_X := 360
const CELLS_Y := 180

var cells_texture := ImageTexture.new()
var index_texture := ImageTexture.new()
## maille -> PackedInt32Array des événements qui la touchent (ordre d'ajout).
var _lists := {}


func clear() -> void:
	_lists = {}


## Ajoute l'événement event à toutes les mailles que touche le disque de rayon radius_km centré en (latitude,
## longitude).
func add_disc(latitude_deg: float, longitude_deg: float, radius_km: float, event: int) -> void:
	for cell in cells_within(latitude_deg, longitude_deg, radius_km):
		if not _lists.has(cell):
			_lists[cell] = PackedInt32Array()
		var ids: PackedInt32Array = _lists[cell]
		if ids.is_empty() or ids[-1] != event:
			ids.append(event)
			_lists[cell] = ids


## Envoie la maille (début, nombre) et les listes dans les deux textures.
func upload() -> void:
	var cells := PackedFloat32Array()
	cells.resize(CELLS_X * CELLS_Y * 2)
	var index := PackedFloat32Array()
	for cell: int in _lists:
		var ids: PackedInt32Array = _lists[cell]
		cells[cell * 2] = index.size()
		cells[cell * 2 + 1] = ids.size()
		for id in ids:
			index.append(id)
	var rows := maxi(ceili(index.size() / float(INDEX_WIDTH)), 1)
	index.resize(rows * INDEX_WIDTH)
	cells_texture.set_image(Image.create_from_data(CELLS_X, CELLS_Y, false, Image.FORMAT_RGF, cells.to_byte_array()))
	index_texture.set_image(Image.create_from_data(INDEX_WIDTH, rows, false, Image.FORMAT_RF, index.to_byte_array()))


## Mailles (indice ligne × CELLS_X + colonne ; ligne 0 au nord) que touche le disque de rayon radius_km centré en
## (latitude, longitude) : bande de latitudes, et longitudes de la calotte sphérique (asin(sin α / cos φ)).
static func cells_within(latitude_deg: float, longitude_deg: float, radius_km: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var alpha := radius_km / OrbitSimulation.EARTH_RADIUS_KM
	var alpha_deg := rad_to_deg(alpha)
	var first_row := clampi(floori(90.0 - (latitude_deg + alpha_deg)), 0, CELLS_Y - 1)
	var last_row := clampi(floori(90.0 - (latitude_deg - alpha_deg)), 0, CELLS_Y - 1)
	var first_col := 0
	var last_col := CELLS_X - 1
	var cos_lat := cos(deg_to_rad(latitude_deg))
	if latitude_deg + alpha_deg < 90.0 and latitude_deg - alpha_deg > -90.0 and sin(alpha) < cos_lat:
		var dlon := rad_to_deg(asin(sin(alpha) / cos_lat))
		var lon := wrapf(longitude_deg, -180.0, 180.0) + 180.0
		first_col = floori(lon - dlon)
		last_col = floori(lon + dlon)
	for row in range(first_row, last_row + 1):
		for col in range(first_col, last_col + 1):
			result.append(row * CELLS_X + posmod(col, CELLS_X))
	return result
