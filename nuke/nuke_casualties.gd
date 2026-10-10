class_name NukeCasualties
extends RefCounted
## Pertes humaines d'une explosion, par pays, et leur évolution dans le temps (snapshot).
##
## Modèle de l'Office of Technology Assessment du Congrès américain (*The Effects of Nuclear War*, 1979, ch. II),
## tiré des pertes d'Hiroshima : la part de tués et de blessés ne dépend que de la surpression de crête au sol, par
## tranches (BANDS). Surpression : équation de Brode (NukeScaling.overpressure_psi), selon la puissance et la hauteur
## d'explosion. Population : grille GHS-POP 2030 (PopulationGrid, cellules de ~0,9 km). Pays de chaque cellule :
## CountryMask (mêmes lignes de latitude).
##
## Les cellules coupées par une limite de tranche sont découpées en SUBCELLS x SUBCELLS sous-cellules (population
## répartie uniformément), sinon une explosion de 10 kt (5 psi à ~1 km) serait mal résolue.
## Chronologie (snapshot, constantes PHASE_*) : une part des morts tombe au flash, une autre au passage de l'onde de
## choc (NukeScaling.shock_arrival_s, anneaux de RINGS distances par pays), le reste meurt de ses blessures dans les
## heures suivantes. Les retombées radioactives (jours) viennent de NukeFallout, calculé à part.
## Non comptés : tempête de feu, effets à long terme.

## Tranches de surpression (psi minimale) : part tuée, part blessée (OTA 1979).
const BANDS: Array[Dictionary] = [
	{"psi": 12.0, "killed": 0.98, "injured": 0.02},
	{"psi": 5.0, "killed": 0.50, "injured": 0.40},
	{"psi": 2.0, "killed": 0.05, "injured": 0.45},
	{"psi": 1.0, "killed": 0.0, "injured": 0.25},
]
const SUBCELLS := 4
## Anneaux de distance (part du rayon de 1 psi) pour dater l'arrivée de l'onde de choc.
const RINGS := 24
## Chronologie des morts du souffle et de la chaleur (part du total OTA) : au flash (brûlures mortelles, rayonnement
## initial), au passage de l'onde de choc, puis morts différées (grands brûlés, blessés graves, victimes ensevelies),
## comptées d'abord parmi les blessés, en exp(−t / PHASE_DELAYED_TAU_S).
const PHASE_FLASH := 0.3
const PHASE_SHOCK := 0.5
const PHASE_DELAYED := 0.2
const PHASE_DELAYED_TAU_S := 21600.0
const KM_PER_DEGREE := 111.195


## Estimation pour une explosion (bilan final du souffle et de la chaleur). Retour : {killed, injured, exposed
## (population au-dessus de 1 psi), radii_km (rayon de chaque tranche, même ordre que BANDS), ring_arrival_s (arrivée de
## l'onde de choc au milieu de chaque anneau), countries : [{code, name_fr, sovereign_fr, killed, injured, exposed,
## pop_est, ring_killed, ring_injured (par anneau)}] trié par tués décroissants}. Sûr depuis un autre thread (lectures seules).
static func estimate(params: NukeParams) -> Dictionary:
	var radii := PackedFloat64Array()
	for band in BANDS:
		radii.append(NukeScaling.overpressure_range_km(params.yield_kt, band.psi, params.burst_height_km))
	var reach := radii[radii.size() - 1]
	var arrivals := PackedFloat64Array()
	for i in RINGS:
		arrivals.append(NukeScaling.shock_arrival_s(params.yield_kt, (i + 0.5) / RINGS * reach))
	var result := {"killed": 0.0, "injured": 0.0, "exposed": 0.0, "radii_km": radii, "ring_arrival_s": arrivals,
			"countries": []}
	if reach <= 0.0 or not PopulationGrid.is_available():
		return result

	var mask := CountryMask.get_mask()
	var per_country := {} # indice du pays (-1 : aucun) -> [tués, blessés, exposés, tués par anneau…, blessés par anneau…]
	var lat0 := params.latitude_deg
	var lon0 := params.longitude_deg
	var cell_deg := 1.0 / PopulationGrid.CELLS_PER_DEGREE
	var first_row := PopulationGrid.row_of(minf(lat0 + reach / KM_PER_DEGREE, 90.0))
	var last_row := PopulationGrid.row_of(maxf(lat0 - reach / KM_PER_DEGREE, -90.0))
	for row in range(first_row, last_row + 1):
		var lat := PopulationGrid.cell_latitude(row)
		var km_x := KM_PER_DEGREE * maxf(cos(deg_to_rad(lat)), 1e-3)
		var km_y := KM_PER_DEGREE
		var dy := (lat - lat0) * km_y
		if absf(dy) > reach + km_y * cell_deg:
			continue
		var half_cols := int(ceil(minf(reach / km_x, 180.0) * PopulationGrid.CELLS_PER_DEGREE)) + 1
		var center_col := PopulationGrid.col_of(lon0)
		# Demi-diagonale d'une cellule (km) : au-delà de cette marge d'une limite, la cellule est entière dans sa tranche.
		var half_diag := 0.5 * Vector2(km_x * cell_deg, km_y * cell_deg).length()
		for k in range(-half_cols, half_cols + 1):
			var col := center_col + k
			var lon := PopulationGrid.cell_longitude(col)
			var dx := wrapf(lon - lon0, -180.0, 180.0) * km_x
			var d := Vector2(dx, dy).length()
			if d > reach + half_diag:
				continue
			var pop := PopulationGrid.cell_population(row, col)
			if pop <= 0.0:
				continue
			var fractions := _cell_fractions(d, half_diag, dx, dy, km_x * cell_deg, km_y * cell_deg, radii)
			if fractions.z <= 0.0:
				continue
			var owner := PopulationGrid.cell_country(row, col)
			var acc: PackedFloat64Array = per_country.get(owner, PackedFloat64Array())
			if acc.is_empty():
				acc.resize(3 + 2 * RINGS)
			var ring := mini(int(d / reach * RINGS), RINGS - 1)
			acc[0] += pop * fractions.x
			acc[1] += pop * fractions.y
			acc[2] += pop * fractions.z
			acc[3 + ring] += pop * fractions.x
			acc[3 + RINGS + ring] += pop * fractions.y
			per_country[owner] = acc

	var countries: Array[Dictionary] = []
	for owner: int in per_country:
		var acc: PackedFloat64Array = per_country[owner]
		result.killed += acc[0]
		result.injured += acc[1]
		result.exposed += acc[2]
		var entry := {"code": "", "name_fr": "(hors pays)", "sovereign_fr": "", "pop_est": 0,
				"killed": acc[0], "injured": acc[1], "exposed": acc[2], "ring_killed": acc.slice(3, 3 + RINGS),
				"ring_injured": acc.slice(3 + RINGS)}
		if owner >= 0:
			var c: Dictionary = mask.countries[owner]
			entry.code = c.code
			entry.name_fr = c.name_fr
			entry.sovereign_fr = c.sovereign_fr
			entry.pop_est = c.pop_est
		countries.append(entry)
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.killed > b.killed)
	result.countries = countries
	return result


## Bilan au temps t (s, physique, depuis l'explosion) : souffle et chaleur (estimate, selon la chronologie PHASE_*)
## plus retombées (NukeFallout.estimate, {} tant qu'elles ne sont pas calculées). Retour : {killed, injured,
## final_killed (projection : bilan final du souffle + retombées à NukeFallout.HORIZON_H), countries : [{code, name_fr,
## sovereign_fr, pop_est, killed, injured}] (pays présents dans l'un ou l'autre bilan)}.
static func snapshot(casualties: Dictionary, fallout: Dictionary, t: float) -> Dictionary:
	var by_code := {}
	var result := {"killed": 0.0, "injured": 0.0, "final_killed": 0.0, "countries": []}
	if not casualties.is_empty():
		var arrivals: PackedFloat64Array = casualties.ring_arrival_s
		for c: Dictionary in casualties.countries:
			var entry := _snapshot_entry(by_code, c)
			var blast := _blast_at(c, arrivals, t)
			entry.killed += blast.x
			entry.injured += blast.y
			result.final_killed += c.killed
	if not fallout.is_empty():
		for c: Dictionary in fallout.countries:
			var entry := _snapshot_entry(by_code, c)
			var rad := NukeFallout.at(fallout, c, t)
			entry.killed += rad.x
			entry.injured += rad.y
			var dead: PackedFloat64Array = c.dead
			result.final_killed += dead[dead.size() - 1]
	for code: String in by_code:
		var entry: Dictionary = by_code[code]
		result.killed += entry.killed
		result.injured += entry.injured
		result.countries.append(entry)
	return result


static func _snapshot_entry(by_code: Dictionary, c: Dictionary) -> Dictionary:
	var code: String = c.code
	if not by_code.has(code):
		by_code[code] = {"code": code, "name_fr": c.name_fr, "sovereign_fr": c.sovereign_fr, "pop_est": c.pop_est,
				"killed": 0.0, "injured": 0.0}
	return by_code[code]


## (morts, blessés) du souffle et de la chaleur pour un pays au temps t : au flash, au passage du front dans chaque
## anneau, puis les morts différées (les blessés qui ne survivront pas).
static func _blast_at(c: Dictionary, arrivals: PackedFloat64Array, t: float) -> Vector2:
	if t <= 0.0:
		return Vector2.ZERO
	var ring_killed: PackedFloat64Array = c.ring_killed
	var ring_injured: PackedFloat64Array = c.ring_injured
	var dead := PHASE_FLASH * float(c.killed)
	var injured := 0.0
	for i in ring_killed.size():
		var since := t - arrivals[i]
		if since < 0.0:
			continue
		var dying := exp(-since / PHASE_DELAYED_TAU_S)
		dead += ring_killed[i] * (PHASE_SHOCK + PHASE_DELAYED * (1.0 - dying))
		injured += ring_injured[i] + ring_killed[i] * PHASE_DELAYED * dying
	return Vector2(dead, injured)


## Parts (tuée, blessée, exposée) de la population d'une cellule à la distance d de son centre. Si une limite de
## tranche passe à moins d'une demi-diagonale, la cellule est découpée en sous-cellules.
static func _cell_fractions(d: float, half_diag: float, dx: float, dy: float, w_km: float, h_km: float,
		radii: PackedFloat64Array) -> Vector3:
	var straddles := false
	for r in radii:
		if absf(d - r) < half_diag:
			straddles = true
			break
	if not straddles:
		return _band_fractions(d, radii)
	var sum := Vector3.ZERO
	for i in SUBCELLS:
		for j in SUBCELLS:
			var sx := dx + ((i + 0.5) / SUBCELLS - 0.5) * w_km
			var sy := dy + ((j + 0.5) / SUBCELLS - 0.5) * h_km
			sum += _band_fractions(Vector2(sx, sy).length(), radii)
	return sum / float(SUBCELLS * SUBCELLS)


## Part de la population tuée par le souffle et la chaleur à la distance d (pour ne pas irradier des morts).
static func killed_fraction(d: float, radii: PackedFloat64Array) -> float:
	return _band_fractions(d, radii).x


## (part tuée, part blessée, 1 si exposé à au moins 1 psi) à la distance d.
static func _band_fractions(d: float, radii: PackedFloat64Array) -> Vector3:
	for i in BANDS.size():
		if d <= radii[i]:
			return Vector3(BANDS[i].killed, BANDS[i].injured, 1.0)
	return Vector3.ZERO


