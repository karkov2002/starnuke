class_name NukeFallout
extends RefCounted
## Retombées radioactives locales d'une explosion au sol et pertes qu'elles causent, par pays, sur plusieurs jours.
##
## Champ de retombées : modèle WSEG-10 (Weapons Systems Evaluation Group, 1959), tel que documenté par D. W. Hanifen
## (*Documentation and Analysis of the WSEG-10 Fallout Prediction Model*, thèse, Air Force Institute of Technology,
## 1980) : nuage stabilisé déporté par le vent, dépôt le long d'une « ligne chaude » sous le vent, répartition
## gaussienne de part et d'autre, correction au vent arrière. Il donne le débit de dose à H+1 (R/h, extrapolé à une
## heure après l'explosion) et l'heure d'arrivée des retombées en chaque point. Transcription d'après le paquet Python
## open source *glasstone* (MIT), en corrigeant deux unités : hauteur du nuage calculée en mégatonnes et vitesse du vent
## en miles par heure, comme chez Hanifen. Unités internes : miles, mph, kilopieds, heures.
##
## Dose reçue : débit en t^−1,2 (loi de Way-Wigner, Glasstone & Dolan §9.145), intégrée depuis l'arrivée des
## retombées : D(t) = 5 · D₁ · (t_a^−0,2 − t^−0,2), divisée par le facteur de protection moyen des bâtiments
## (PROTECTION_FACTOR, sans évacuation). Effets (Glasstone & Dolan ch. XII, irradiation aiguë sans soins) : mort
## avec une probabilité log-normale de dose médiane LD50_GY et d'écart-type LETHAL_SIGMA ; mal des rayons (compté avec
## les blessés) au-dessus de SICK50_GY. Les morts surviennent avec un délai (constante DEATH_LATENCY_H), les malades
## qui en mourront passent des blessés aux morts.
##
## Seulement pour une explosion basse (NukeScaling.low_burst) : une explosion en altitude ne produit pas de
## retombées locales. Les personnes déjà tuées par le souffle ne sont pas comptées (NukeCasualties.killed_fraction).
## Le calcul (quelques secondes pour 50 Mt) est lancé dans un thread par NukeLauncher.

const MI_PER_KM := 0.621371
const MPH_PER_M_S := 2.23694
## Grandeurs de la population et des doses.
const R_TO_GY := 0.0087
const PROTECTION_FACTOR := 3.0
const LD50_GY := 4.5
const LETHAL_SIGMA := 0.3
const SICK50_GY := 1.5
const SICK_SIGMA := 0.4
const DEATH_LATENCY_H := 144.0
## Fraction de l'énergie due à la fission : 1 pour une arme à fission pure (< FISSION_ONLY_KT), 0,5 au-delà
## (armes thermonucléaires, valeur usuelle de Glasstone & Dolan).
const FISSION_ONLY_KT := 50.0
const FISSION_FRACTION := 0.5
## Chronologie calculée : TIME_SAMPLES instants, répartis en échelle logarithmique de 0,25 h à HORIZON_H (60 jours).
const TIME_SAMPLES := 48
const HORIZON_H := 1440.0
## Grille : blocs de BLOCK x BLOCK cellules de PopulationGrid (~2,8 km : le champ de retombées est lisse).
const BLOCK := 3
## On ignore les lieux où la dose finale (sous abri) resterait sous MIN_DOSE_GY.
const MIN_DOSE_GY := 0.5


## Retombées d'une explosion : {times_h (instants calculés), total_dead, total_sick (à chaque instant), countries :
## [{code, name_fr, sovereign_fr, pop_est, dead, sick}] (par instant), wind_m_s, hotline_km (longueur de la zone
## dangereuse sous le vent), direction_deg (vers où va le nuage)} ; {} sans retombées (explosion en altitude).
## Sûr depuis un autre thread (lectures seules).
static func estimate(params: NukeParams, blast_radii: PackedFloat64Array) -> Dictionary:
	var low := NukeScaling.low_burst(params.yield_kt, params.burst_height_km)
	if low <= 0.01 or not PopulationGrid.is_available():
		return {}
	var w := NukeWSEG10.new(params, low)
	var times := PackedFloat64Array()
	for i in TIME_SAMPLES:
		times.append(0.25 * pow(HORIZON_H / 0.25, float(i) / (TIME_SAMPLES - 1)))

	# Étendue utile : le long de la ligne chaude jusqu'à ce que la dose finale passe sous MIN_DOSE_GY, et de part et
	# d'autre jusqu'à 3,5 écarts-types (en tenant compte de la correction au vent arrière).
	var x_max_mi := 2.0
	while x_max_mi < 3000.0 and w.final_dose_gy(x_max_mi, 0.0) >= MIN_DOSE_GY:
		x_max_mi += 2.0
	var x_min_mi := -3.0 * w.s0
	var y_max_mi := 0.0
	var x := x_min_mi
	while x <= x_max_mi:
		y_max_mi = maxf(y_max_mi, 3.5 * w.crosswind_sigma(x))
		x += maxf((x_max_mi - x_min_mi) / 32.0, 0.5)
	var result := {"times_h": times, "countries": [], "wind_m_s": w.wind_mph / MPH_PER_M_S,
			"hotline_km": x_max_mi / MI_PER_KM, "direction_deg": rad_to_deg(atan2(w.dir.x, w.dir.y))}
	var reach_km := Vector2(maxf(x_max_mi, -x_min_mi), y_max_mi).length() / MI_PER_KM

	var mask := CountryMask.get_mask()
	var per_country := {} # indice du pays -> [morts par instant…, malades par instant…]
	var lat0 := params.latitude_deg
	var lon0 := params.longitude_deg
	var block_deg := float(BLOCK) / PopulationGrid.CELLS_PER_DEGREE
	var first_row := PopulationGrid.row_of(minf(lat0 + reach_km / NukeCasualties.KM_PER_DEGREE, 89.0))
	var last_row := PopulationGrid.row_of(maxf(lat0 - reach_km / NukeCasualties.KM_PER_DEGREE, -89.0))
	first_row -= first_row % BLOCK
	for row in range(first_row, last_row + 1, BLOCK):
		var lat := PopulationGrid.cell_latitude(row) - 0.5 * (BLOCK - 1) / float(PopulationGrid.CELLS_PER_DEGREE)
		var km_x := NukeCasualties.KM_PER_DEGREE * maxf(cos(deg_to_rad(lat)), 1e-3)
		var dy_km := (lat - lat0) * NukeCasualties.KM_PER_DEGREE
		var half_cols := int(ceil(minf(reach_km / km_x, 180.0) / block_deg)) + 1
		var center_col := PopulationGrid.col_of(lon0)
		center_col -= center_col % BLOCK
		for k in range(-half_cols, half_cols + 1):
			var col := center_col + k * BLOCK
			var lon := PopulationGrid.cell_longitude(col) + 0.5 * (BLOCK - 1) / float(PopulationGrid.CELLS_PER_DEGREE)
			var dx_km := wrapf(lon - lon0, -180.0, 180.0) * km_x
			# Repère du vent (miles) : x sous le vent, y en travers.
			var offset := Vector2(dx_km, dy_km) * MI_PER_KM
			var xw := offset.dot(w.dir)
			var yw := offset.dot(Vector2(-w.dir.y, w.dir.x))
			if xw < x_min_mi or xw > x_max_mi or absf(yw) > y_max_mi:
				continue
			var d1 := w.dose_rate_h1(xw, yw)
			var ta := w.arrival_h(xw)
			var final_gy := 5.0 * d1 * pow(ta, -0.2) * R_TO_GY / PROTECTION_FACTOR
			if final_gy < MIN_DOSE_GY:
				continue
			var survivors := 0.0
			for r in BLOCK:
				for c in BLOCK:
					survivors += PopulationGrid.cell_population(row + r, col + c)
			survivors *= 1.0 - NukeCasualties.killed_fraction(Vector2(dx_km, dy_km).length(), blast_radii)
			if survivors <= 0.0:
				continue
			var owner := PopulationGrid.cell_country(row + 1, col + 1)
			var acc: PackedFloat64Array = per_country.get(owner, PackedFloat64Array())
			if acc.is_empty():
				acc.resize(2 * TIME_SAMPLES)
			for i in TIME_SAMPLES:
				var effects := _effects(d1, ta, times[i])
				acc[i] += survivors * effects.x
				acc[TIME_SAMPLES + i] += survivors * effects.y
			per_country[owner] = acc

	var total_dead := PackedFloat64Array()
	var total_sick := PackedFloat64Array()
	total_dead.resize(TIME_SAMPLES)
	total_sick.resize(TIME_SAMPLES)
	for owner: int in per_country:
		var acc: PackedFloat64Array = per_country[owner]
		var entry := {"code": "", "name_fr": "(hors pays)", "sovereign_fr": "", "pop_est": 0,
				"dead": acc.slice(0, TIME_SAMPLES), "sick": acc.slice(TIME_SAMPLES)}
		if owner >= 0:
			var c: Dictionary = mask.countries[owner]
			entry.code = c.code
			entry.name_fr = c.name_fr
			entry.sovereign_fr = c.sovereign_fr
			entry.pop_est = c.pop_est
		for i in TIME_SAMPLES:
			total_dead[i] += acc[i]
			total_sick[i] += acc[TIME_SAMPLES + i]
		result.countries.append(entry)
	result.countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.dead[TIME_SAMPLES - 1] > b.dead[TIME_SAMPLES - 1])
	result.total_dead = total_dead
	result.total_sick = total_sick
	return result


## (part morte, part malade) d'une population au temps t_h (heures), pour un débit D₁ (R/h à H+1) et des retombées
## arrivées à ta (h).
static func _effects(d1: float, ta: float, t_h: float) -> Vector2:
	if t_h <= ta:
		return Vector2.ZERO
	var dose := 5.0 * d1 * (pow(ta, -0.2) - pow(t_h, -0.2)) * R_TO_GY / PROTECTION_FACTOR
	if dose <= 0.01:
		return Vector2.ZERO
	var lethal := NukeMath.normal_cdf(log(dose / LD50_GY) / LETHAL_SIGMA)
	var sick := NukeMath.normal_cdf(log(dose / SICK50_GY) / SICK_SIGMA)
	var dead := lethal * (1.0 - exp(-(t_h - ta) / DEATH_LATENCY_H))
	return Vector2(dead, maxf(sick - dead, 0.0))


## (morts, malades) d'un pays au temps t (s, physique), interpolés entre les instants calculés.
static func at(fallout: Dictionary, country: Dictionary, t: float) -> Vector2:
	var times: PackedFloat64Array = fallout.times_h
	var t_h := t / 3600.0
	if t_h <= times[0]:
		return Vector2.ZERO
	var dead: PackedFloat64Array = country.dead
	var sick: PackedFloat64Array = country.sick
	var last := times.size() - 1
	if t_h >= times[last]:
		return Vector2(dead[last], sick[last])
	var i := times.bsearch(t_h) - 1
	var f := (log(t_h) - log(times[i])) / (log(times[i + 1]) - log(times[i]))
	return Vector2(lerpf(dead[i], dead[i + 1], f), lerpf(sick[i], sick[i + 1], f))


