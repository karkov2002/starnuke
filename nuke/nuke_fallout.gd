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
const KFT_PER_KM := 3.28084
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
	var w := WSEG10.new(params, low)
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
			var owner := NukeCasualties.cell_country(mask, row + 1, col + 1)
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


## Résumé lisible (console).
static func format_report(fallout: Dictionary, params: NukeParams) -> String:
	if fallout.is_empty():
		return "  retombées : aucune (explosion en altitude)"
	var last := TIME_SAMPLES - 1
	var line := "  retombées (WSEG-10, %s) : vent %.0f m/s vers %03d°, zone dangereuse sur %.0f km ; à %d jours : %s morts, %s malades" \
			% [NukeScaling.format_yield(params.yield_kt), fallout.wind_m_s, posmod(roundi(fallout.direction_deg), 360),
			fallout.hotline_km, roundi(HORIZON_H / 24.0), NukeCasualties.format_count(fallout.total_dead[last]),
			NukeCasualties.format_count(fallout.total_sick[last])]
	for c: Dictionary in fallout.countries.slice(0, 5):
		var dead: PackedFloat64Array = c.dead
		var sick: PackedFloat64Array = c.sick
		if dead[last] >= 1.0 or sick[last] >= 100.0:
			line += "\n    %s : %s morts, %s malades" % [c.name_fr, NukeCasualties.format_count(dead[last]),
					NukeCasualties.format_count(sick[last])]
	return line


## (part morte, part malade) d'une population au temps t_h (heures), pour un débit D₁ (R/h à H+1) et des retombées
## arrivées à ta (h).
static func _effects(d1: float, ta: float, t_h: float) -> Vector2:
	if t_h <= ta:
		return Vector2.ZERO
	var dose := 5.0 * d1 * (pow(ta, -0.2) - pow(t_h, -0.2)) * R_TO_GY / PROTECTION_FACTOR
	if dose <= 0.01:
		return Vector2.ZERO
	var lethal := _normal_cdf(log(dose / LD50_GY) / LETHAL_SIGMA)
	var sick := _normal_cdf(log(dose / SICK50_GY) / SICK_SIGMA)
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


## Fonction de répartition de la loi normale centrée réduite (Abramowitz & Stegun 7.1.26, erreur < 1,5·10⁻⁷).
static func _normal_cdf(z: float) -> float:
	var x := absf(z) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var erf := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) \
			* t * exp(-x * x)
	return 0.5 * (1.0 + (erf if z >= 0.0 else -erf))


## Fonction gamma (approximation de Lanczos, g = 7), pour x > 0.
static func _gamma(x: float) -> float:
	const C := [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
			-176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6,
			1.5056327351493116e-7]
	if x < 0.5:
		return PI / (sin(PI * x) * _gamma(1.0 - x))
	x -= 1.0
	var a: float = C[0]
	var t := x + 7.5
	for i in range(1, 9):
		a += C[i] / (x + i)
	return sqrt(TAU) * pow(t, x + 0.5) * exp(-t) * a


## Paramètres WSEG-10 d'une explosion (Hanifen 1980). Unités : miles, mph, kilopieds, heures, mégatonnes.
class WSEG10:
	var yield_mt: float
	var ff: float
	var wind_mph: float
	var shear: float # mph par kilopied
	## Direction vers laquelle va le nuage (vecteur unitaire est, nord).
	var dir: Vector2
	var scale: float # part « explosion basse » (0 à 1) appliquée au débit de dose
	var h_c: float
	var s0: float
	var s_h: float
	var t_c: float
	var l0: float
	var s_x: float
	var l: float
	var n: float
	var a1: float
	var g_norm: float

	func _init(params: NukeParams, low_burst: float) -> void:
		yield_mt = params.yield_kt / 1000.0
		ff = 1.0 if params.yield_kt < FISSION_ONLY_KT else FISSION_FRACTION
		scale = low_burst
		var ln_y := log(yield_mt)
		var d := ln_y + 2.42
		h_c = 44.0 + 6.1 * ln_y - 0.205 * absf(d) * d # hauteur du centre du nuage (kilopieds)
		s0 = exp(0.7 + ln_y / 3.0 - 3.25 / (4.0 + pow(ln_y + 5.4, 2.0)))
		s_h = 0.18 * h_c
		t_c = 1.0573203 * (12.0 * (h_c / 60.0) - 2.5 * pow(h_c / 60.0, 2.0)) * (1.0 - 0.5 * exp(-pow(h_c / 25.0, 2.0)))
		# Vent effectif : moyenne du profil réel (GFS) entre le sol et le centre du nuage ; cisaillement entre les deux.
		var h_km := h_c / KFT_PER_KM
		var mean := Vector2.ZERO
		for i in 16:
			mean += params.wind_at((i + 0.5) / 16.0 * h_km)
		mean /= 16.0
		wind_mph = maxf(mean.length() * MPH_PER_M_S, 1.0)
		dir = mean.normalized() if mean.length() > 0.01 else Vector2(1.0, 0.0)
		var top := params.wind_at(h_km)
		var bottom := params.wind_at(0.0)
		shear = (top - bottom).length() * MPH_PER_M_S / maxf(h_c, 1.0)
		l0 = wind_mph * t_c
		var s02 := s0 * s0
		var l02 := l0 * l0
		var s_x2 := s02 * (l02 + 8.0 * s02) / (l02 + 2.0 * s02)
		s_x = sqrt(s_x2)
		l = sqrt(l02 + 2.0 * s_x2)
		# Exposant de la loi de dépôt. La transcription glasstone y met la fraction de fission, déjà comptée dans le
		# débit (f_x) : le dépôt s'étalait sur des centaines de km et le débit près du point zéro était 3 à 5 fois sous
		# les contours idéalisés de Glasstone & Dolan (1 Mt, 15 mph). Avec 1, on retrouve leur ordre de grandeur.
		n = (l02 + s_x2) / (l02 + 0.5 * s_x2)
		a1 = 1.0 / (1.0 + 0.001 * h_c * wind_mph / s0)
		g_norm = 1.0 / (l * NukeFallout._gamma(1.0 + 1.0 / n))

	## Écart-type de la répartition en travers du vent à la distance x sous le vent (miles).
	func crosswind_sigma(x: float) -> float:
		var s02 := s0 * s0
		var k := s_x * t_c * s_h * shear
		var m := (x + 2.0 * s_x) * l0 * t_c * s_h * shear
		return sqrt(s02 + 8.0 * absf(x + 2.0 * s_x) * s02 / l + 2.0 * k * k / (l * l) + m * m / pow(l, 4.0))

	## Débit de dose à H+1 (R/h) au point (x sous le vent, y en travers ; miles), activité qui finira par s'y déposer.
	func dose_rate_h1(x: float, y: float) -> float:
		var g := exp(-pow(absf(x) / l, n)) * g_norm
		var phi := NukeFallout._normal_cdf((l0 / l) * (x / (s_x * a1)))
		var f_x := yield_mt * 2.0e6 * phi * g * ff
		var s_y := crosswind_sigma(x)
		var a2 := 1.0 / (1.0 + (0.001 * h_c * wind_mph / s0) * (1.0 - NukeFallout._normal_cdf(2.0 * x / wind_mph)))
		var f_y := exp(-0.5 * pow(y / (a2 * s_y), 2.0)) / (2.5066282746310002 * s_y)
		return f_x * f_y * scale

	## Heure moyenne d'arrivée des retombées sur la ligne chaude à x (au moins 0,5 h).
	func arrival_h(x: float) -> float:
		var l02 := l0 * l0
		var s_x2 := s_x * s_x
		return sqrt(0.25 + l02 * pow(x + 2.0 * s_x, 2.0) * t_c * t_c / (l * l * (l02 + 0.5 * s_x2))
				+ 2.0 * s_x2 / (l02 + 0.5 * s_x2))

	## Dose finale sous abri (Gy) sur la ligne chaude, ou en (x, y).
	func final_dose_gy(x: float, y: float) -> float:
		return 5.0 * dose_rate_h1(x, y) * pow(arrival_h(x), -0.2) * R_TO_GY / PROTECTION_FACTOR
