class_name CountryMask
extends Resource
## Masque des pays (assets/country_mask.res, généré par tools/build_country_mask.gd à partir des frontières Natural
## Earth 1:10 M, couche « admin 0 countries » : pays souverains et territoires dépendants, frontières de fait).
##
## Stockage par lignes de latitude (ROWS_PER_DEGREE par degré, ~0,9 km), comme OceanMask : pour chaque ligne, les
## longitudes (exactes, en degrés) où elle traverse une frontière ou une côte, triées, et le pays qui occupe la ligne
## à l'est de chacune (-1 : aucun, mer). Précision : celle des frontières (quelques centaines de mètres) en
## longitude, ~0,5 km en latitude.

const PATH := "res://assets/country_mask.res"
const ROWS_PER_DEGREE := 120
const KM_PER_DEGREE := 111.195

## Longitudes des changements de pays, ligne après ligne (ligne 0 = 90° N).
@export var breaks := PackedFloat32Array()
## Pays (indice dans countries, -1 : aucun) à l'est de chaque longitude de breaks.
@export var owners := PackedInt32Array()
## Début des changements de chaque ligne dans breaks (taille : nombre de lignes + 1).
@export var row_offsets := PackedInt32Array()
## Fiche de chaque pays : code (ADM0_A3), iso_a2, name_fr, name_en, sovereign_code et sovereign_fr (État dont il
## dépend, lui-même pour un pays souverain), type, continent, population (pop_est, pop_year), PIB en millions de
## dollars (gdp_md, gdp_year), income_group.
@export var countries: Array[Dictionary] = []

static var _instance: CountryMask
static var _load_failed := false


## Masque chargé une fois (null si le fichier manque).
static func get_mask() -> CountryMask:
	if _instance == null and not _load_failed:
		_instance = load(PATH) as CountryMask if ResourceLoader.exists(PATH) else null
		_load_failed = _instance == null
		if _load_failed:
			push_warning("CountryMask : %s introuvable (tools/build_country_mask.gd), aucun pays détecté" % PATH)
	return _instance


## Fiche du pays au point (degrés), ou {} en mer (ou sans masque).
static func country_at(latitude_deg: float, longitude_deg: float) -> Dictionary:
	var mask := get_mask()
	if mask == null:
		return {}
	var index := mask._owner_at(_row_of(latitude_deg), wrapf(longitude_deg, -180.0, 180.0))
	return mask.countries[index] if index >= 0 else {}


## Fiches des pays présents dans le disque de rayon radius_km autour du point (degrés), du plus proche au plus
## éloigné du centre (distance approchée à la ligne près).
static func countries_within(latitude_deg: float, longitude_deg: float, radius_km: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mask := get_mask()
	if mask == null:
		return result
	var nearest := {} # indice du pays -> distance minimale (km)
	var dlat := radius_km / KM_PER_DEGREE
	var first := _row_of(minf(latitude_deg + dlat, 90.0))
	var last := _row_of(maxf(latitude_deg - dlat, -90.0))
	for row in range(first, last + 1):
		var row_lat := _row_latitude(row)
		var dy := (row_lat - latitude_deg) * KM_PER_DEGREE
		var chord := sqrt(maxf(radius_km * radius_km - dy * dy, 0.0))
		var km_per_lon := KM_PER_DEGREE * maxf(cos(deg_to_rad(row_lat)), 1e-3)
		var dlon := minf(chord / km_per_lon, 180.0)
		mask._collect_on_row(row, longitude_deg, dlon, absf(dy), km_per_lon, nearest)
	var indices := nearest.keys()
	indices.sort_custom(func(a: int, b: int) -> bool: return nearest[a] < nearest[b])
	for index: int in indices:
		result.append(mask.countries[index])
	return result


## Indice dans countries du pays de la ligne row (même découpage que PopulationGrid) à la longitude donnée (−180 à
## 180), -1 en mer.
func index_at_row(row: int, longitude_deg: float) -> int:
	return _owner_at(row, longitude_deg)


## Comme index_at_row, mais si le point tombe « en mer » (le trait de côte au 1:10 M est plus grossier que les données
## qu'on y rattache : cellules de population littorales, centrales côtières), le pays le plus proche à moins de
## search lignes de 1/120° (~0,9 km chacune), en parcourant des carrés de plus en plus grands. -1 au large.
func index_near(row: int, longitude_deg: float, search: int) -> int:
	var step := 1.0 / ROWS_PER_DEGREE
	for radius in search + 1:
		for dr in range(-radius, radius + 1):
			for dc in range(-radius, radius + 1):
				if maxi(absi(dr), absi(dc)) != radius:
					continue # seulement le pourtour du carré : du plus proche au plus éloigné
				var r := clampi(row + dr, 0, row_count() - 1)
				var index := _owner_at(r, wrapf(longitude_deg + dc * step, -180.0, 180.0))
				if index >= 0:
					return index
	return -1


static func row_count() -> int:
	return 180 * ROWS_PER_DEGREE


static func _row_of(latitude_deg: float) -> int:
	return clampi(int(floor((90.0 - latitude_deg) * ROWS_PER_DEGREE)), 0, row_count() - 1)


static func _row_latitude(row: int) -> float:
	return 90.0 - (row + 0.5) / ROWS_PER_DEGREE


## Indice du dernier changement à l'ouest de la longitude (ou au début de la ligne : row_offsets[row] − 1).
func _last_break_west_of(row: int, longitude_deg: float) -> int:
	var lo := row_offsets[row]
	var hi := row_offsets[row + 1]
	while lo < hi:
		var mid := (lo + hi) >> 1
		if breaks[mid] <= longitude_deg:
			lo = mid + 1
		else:
			hi = mid
	return lo - 1


func _owner_at(row: int, longitude_deg: float) -> int:
	var i := _last_break_west_of(row, longitude_deg)
	return owners[i] if i >= row_offsets[row] else -1


## Ajoute à nearest les pays de la ligne entre center − dlon et center + dlon, avec leur distance minimale au centre.
func _collect_on_row(row: int, center_deg: float, dlon: float, dy_km: float, km_per_lon: float,
		nearest: Dictionary) -> void:
	var from := center_deg - dlon
	var to := center_deg + dlon
	# Morceaux dans [−180, 180] (l'intervalle peut passer l'antiméridien).
	var pieces: Array[Vector2] = []
	if dlon >= 180.0:
		pieces.append(Vector2(-180.0, 180.0))
	elif from < -180.0:
		pieces.append_array([Vector2(from + 360.0, 180.0), Vector2(-180.0, to)])
	elif to > 180.0:
		pieces.append_array([Vector2(from, 180.0), Vector2(-180.0, to - 360.0)])
	else:
		pieces.append(Vector2(from, to))
	var start := row_offsets[row]
	var end := row_offsets[row + 1]
	for piece in pieces:
		var i := _last_break_west_of(row, piece.x)
		var a := piece.x
		while true:
			var next := breaks[i + 1] if i + 1 < end else 181.0
			var b := minf(next, piece.y)
			var owner := owners[i] if i >= start else -1
			if owner >= 0:
				# Distance au centre du point de [a, b] le plus proche (longitudes ramenées autour du centre).
				var da := wrapf(a - center_deg, -180.0, 180.0)
				var db := wrapf(b - center_deg, -180.0, 180.0)
				var dx := 0.0 if da <= 0.0 and db >= 0.0 else minf(absf(da), absf(db))
				var d := Vector2(dx * km_per_lon, dy_km).length()
				nearest[owner] = minf(nearest.get(owner, INF), d)
			if next >= piece.y:
				break
			a = next
			i += 1
