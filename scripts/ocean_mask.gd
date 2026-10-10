class_name OceanMask
extends Resource
## Masque mers et océans (assets/ocean_mask.res, généré par tools/build_ocean_mask.gd à partir du trait de côte
## Natural Earth 1:10 M, couche « ocean » : océans et mers reliées, Caspienne comprise ; les lacs comptent comme terre).
##
## Stockage par lignes de latitude (ROWS_PER_DEGREE par degré, ~0,9 km) : pour chaque ligne, les longitudes
## (exactes, en degrés) où elle traverse le trait de côte, triées. Un point est en mer si un nombre impair de ces
## traversées est à sa gauche (règle pair-impair). Précision : celle du trait de côte (quelques centaines de
## mètres) en longitude, ~0,5 km en latitude.

const PATH := "res://assets/ocean_mask.res"
const ROWS_PER_DEGREE := 120
const KM_PER_DEGREE := 111.195

## Longitudes des traversées, ligne après ligne (ligne 0 = 90° N).
@export var crossings := PackedFloat32Array()
## Début des traversées de chaque ligne dans crossings (taille : nombre de lignes + 1).
@export var row_offsets := PackedInt32Array()

static var _instance: OceanMask
static var _load_failed := false


## Masque chargé une fois (null si le fichier manque).
static func get_mask() -> OceanMask:
	if _instance == null and not _load_failed:
		_instance = load(PATH) as OceanMask if ResourceLoader.exists(PATH) else null
		_load_failed = _instance == null
		if _load_failed:
			push_warning("OceanMask : %s introuvable (tools/build_ocean_mask.gd), tout est considéré comme terre" % PATH)
	return _instance


## Le point (degrés) est-il sur une mer ou un océan ? Faux sans masque.
static func is_ocean(latitude_deg: float, longitude_deg: float) -> bool:
	var mask := get_mask()
	return mask != null and mask._is_ocean_row(_row_of(latitude_deg), longitude_deg)


## Y a-t-il de la terre dans le disque de rayon radius_km autour du point (degrés) ? Vrai sans masque.
static func has_land_within(latitude_deg: float, longitude_deg: float, radius_km: float) -> bool:
	var mask := get_mask()
	if mask == null:
		return true
	var dlat := radius_km / KM_PER_DEGREE
	var first := _row_of(minf(latitude_deg + dlat, 90.0))
	var last := _row_of(maxf(latitude_deg - dlat, -90.0))
	for row in range(first, last + 1):
		var row_lat := _row_latitude(row)
		var dy := (row_lat - latitude_deg) * KM_PER_DEGREE
		var chord := sqrt(maxf(radius_km * radius_km - dy * dy, 0.0))
		var dlon := rad_to_deg(chord / (OrbitSimulation.EARTH_RADIUS_KM * maxf(cos(deg_to_rad(row_lat)), 1e-3)))
		if dlon >= 180.0 or mask._has_land_on_row(row, longitude_deg - dlon, longitude_deg + dlon):
			return true
	return false


static func row_count() -> int:
	return 180 * ROWS_PER_DEGREE


static func _row_of(latitude_deg: float) -> int:
	return clampi(int(floor((90.0 - latitude_deg) * ROWS_PER_DEGREE)), 0, row_count() - 1)


## Latitude du milieu de la ligne (là où ses traversées ont été calculées).
static func _row_latitude(row: int) -> float:
	return 90.0 - (row + 0.5) / ROWS_PER_DEGREE


## Nombre de traversées de la ligne à l'ouest de la longitude donnée (recherche dichotomique).
func _crossings_west_of(row: int, longitude_deg: float) -> int:
	var lo := row_offsets[row]
	var hi := row_offsets[row + 1]
	var start := lo
	while lo < hi:
		var mid := (lo + hi) >> 1
		if crossings[mid] < longitude_deg:
			lo = mid + 1
		else:
			hi = mid
	return lo - start


func _is_ocean_row(row: int, longitude_deg: float) -> bool:
	return _crossings_west_of(row, wrapf(longitude_deg, -180.0, 180.0)) % 2 == 1


## Terre sur la ligne entre deux longitudes (degrés, from < to, intervalle de moins d'un tour) ?
func _has_land_on_row(row: int, from_deg: float, to_deg: float) -> bool:
	var a := wrapf(from_deg, -180.0, 180.0)
	var b := a + (to_deg - from_deg)
	if b > 180.0:
		# L'intervalle passe l'antiméridien : deux morceaux.
		return _has_land_on_row(row, a, 180.0) or _has_land_on_row(row, -180.0, b - 360.0)
	if not _is_ocean_row(row, a):
		return true
	# En mer au départ : de la terre seulement si une traversée tombe dans l'intervalle.
	return _crossings_west_of(row, b) != _crossings_west_of(row, a)
