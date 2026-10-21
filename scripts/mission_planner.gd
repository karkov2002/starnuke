class_name MissionPlanner
extends RefCounted
## Passage le plus tôt possible pour une mission de campagne (calculs purs, sans état ; utilisés par CampaignDirector
## pour le temps de référence, par tools/check_campaign.gd et par le banc d'équilibrage). Règles :
## - photo : le point sous la station passe à la verticale de la cible ;
## - tir : la cible est visible depuis la station à au moins MIN_ELEVATION_DEG au-dessus de l'horizon ;
## - manœuvres comprises : orbite actuelle, ou orbite obtenue par un changement de plan (une seule poussée, en un
##   point quelconque de l'orbite après le début de la recherche) dans les limites du poste de pilotage (inclinaison
##   ≤ 80°, décalage du nœud ≤ ±FlightComputer.MAX_NODE_SHIFT_DEG), altitude inchangée. Le plan visé est celui qui
##   contient le point de poussée et la cible à l'instant du passage, précession J2 entre les deux comprise (à la
##   dérive de l'orbite actuelle près : quelques km d'écart, sans importance pour un temps de référence) ;
## - objectifs dans l'ordre imposé par « after », sinon le plus tôt possible d'abord (glouton) ; chacun part de
##   l'orbite laissée par le précédent.
## Orbite (« état ») : dictionnaire {unix (instant UTC du temps 0), radius (km), inclination, raan, arg_lat (rad,
## au temps 0), n (rad/s), raan_rate (rad/s)} ; temps en secondes depuis ce temps 0.

const MIN_ELEVATION_DEG := 20.0
## Pas de recherche : point de poussée, instant de passage (affiné par dichotomie), visibilité d'une cible de tir.
const BURN_STEP_S := 300.0
const PASS_STEP_S := 120.0
const STRIKE_STEP_S := 60.0
const BISECT_STEPS := 10


## État de l'orbite réelle, temps 0 = maintenant.
static func state_of(orbit: OrbitSimulation) -> Dictionary:
	var now := orbit.sim_time_s
	return _state(orbit.get_utc_unix_s(), orbit.altitude_km, orbit.inclination_deg, orbit.get_raan(now),
			orbit.get_argument_of_latitude(now), orbit.raan_precession)


## État d'un départ de campagne (format de CampaignData : utc, orbit), temps 0 = son heure UTC.
static func state_from_start(start: Dictionary) -> Dictionary:
	var unix := CampaignData.parse_utc(str(start.utc))
	var orbit: Dictionary = start.orbit
	var over: Dictionary = orbit.over
	var plane := OrbitSimulation.plane_over(float(orbit.inclination_deg), float(over.lat), float(over.lon),
			bool(orbit.get("ascending", true)), unix)
	return _state(unix, float(orbit.altitude_km), float(orbit.inclination_deg), plane.x, plane.y, true)


## Déroulement au plus tôt d'une campagne valide (tools/check_campaign.gd, tools/balance_campaign.gd) : journée par
## journée, toutes les missions de la journée (conditions « when » ignorées), chacune remplie au plus tôt depuis
## l'orbite laissée par la précédente, coucher dès la fin de la journée (réveil : départ de la journée, sinon
## wake_up_utc, sinon CampaignData.NIGHT_HOURS). Une entrée par mission : {day, mission (identifiant), wake_unix
## (réveil de sa journée), earliest_s (depuis l'arrivée du briefing, INF : impossible à temps), par_s (depuis le
## départ du chrono, par_hours compris), deadline_s, period_s}.
static func timeline(campaign: CampaignData) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var state := {}
	var t := 0.0
	var days := campaign.days()
	for i in days.size():
		var day: Dictionary = days[i]
		var start := campaign.start_of_day(i)
		if not start.is_empty():
			state = state_from_start(start)
			t = 0.0
		elif day.has("wake_up_utc"):
			var now: float = state.unix + t
			var parts := str(day.wake_up_utc).split(":")
			var wake := floorf(now / 86400.0) * 86400.0 + int(parts[0]) * 3600.0 + int(parts[1]) * 60.0
			t += wake - now + (86400.0 if wake <= now else 0.0)
		else:
			t += CampaignData.NIGHT_HOURS * 3600.0
		var wake_unix: float = state.unix + t
		for entry: Dictionary in day.get("missions", []):
			var mission := campaign.mission(str(entry.mission))
			var deadline := float(mission.get("deadline_hours", 0.0)) * 3600.0 \
					+ float(mission.get("deadline_minutes", 0.0)) * 60.0
			var grace := MissionScoring.START_GRACE_S
			var plan := earliest(state, mission.objectives, t, t + grace + deadline)
			var row := {"day": day.id, "mission": str(entry.mission), "wake_unix": wake_unix, "earliest_s": INF,
					"par_s": deadline, "deadline_s": deadline, "period_s": period_s(state)}
			if plan.time < INF:
				row.earliest_s = plan.time - t
				row.par_s = minf(maxf(row.earliest_s - grace, 0.0) + row.period_s, deadline)
				t = plan.time
				state = plan.state
			else:
				t += grace + deadline
			var fixed: Variant = mission.get("par_hours", null)
			if fixed != null:
				row.par_s = float(fixed) * 3600.0
			rows.append(row)
	return rows


## Période (s) de l'orbite d'un état.
static func period_s(state: Dictionary) -> float:
	return TAU / float(state.n)


## Instant (s depuis le temps 0 de state) où tous les objectifs peuvent être remplis au plus tôt, en partant de
## from_s ; INF si c'est impossible avant horizon_s. Rend {time, state} : state est l'orbite après le dernier
## objectif (pour enchaîner les missions).
static func earliest(state: Dictionary, objectives: Array, from_s: float, horizon_s: float) -> Dictionary:
	var done := {}
	var now := from_s
	var current := state
	while done.size() < objectives.size():
		var best := {"time": INF}
		var best_k := -1
		for k in objectives.size():
			var objective: Dictionary = objectives[k]
			if done.has(k) or (objective.has("after") and not done.has(int(objective.after))):
				continue
			var lat := float(objective.target.lat)
			var lon := float(objective.target.lon)
			var limit := minf(horizon_s, best.time)
			var found := _earliest_photo(current, lat, lon, now, limit) if objective.type == "photo" \
					else _earliest_strike(current, lat, lon, now, limit)
			if found.time < best.time:
				best = found
				best_k = k
		if best_k < 0:
			return {"time": INF, "state": current}
		done[best_k] = true
		now = best.time
		current = best.state
	return {"time": now, "state": current}


# Photo : premier passage à la verticale de la cible, orbite actuelle ou après un changement de plan (voir en tête).
# {time, state, burn} (burn : instant de la poussée).
static func _earliest_photo(state: Dictionary, lat: float, lon: float, from_s: float, horizon_s: float) -> Dictionary:
	var best := {"time": INF, "state": state, "burn": from_s}
	var burn := from_s
	while burn < minf(best.time, horizon_s):
		var point := _position(state, burn)
		var normal := OrbitSimulation.plane_normal(state.inclination, _raan(state, burn))
		var previous := NAN
		var t := burn + PASS_STEP_S
		while t <= minf(best.time, horizon_s):
			var gap := _gap(state, burn, point, normal, lat, lon, t)
			# Racine : passage de négatif à positif (pas le saut de +π à −π).
			if not is_nan(previous) and not is_nan(gap) and previous < 0.0 and gap >= 0.0 and gap - previous < 1.0:
				var low := t - PASS_STEP_S
				var high := t
				for _i in BISECT_STEPS:
					var middle := (low + high) * 0.5
					var g := _gap(state, burn, point, normal, lat, lon, middle)
					if is_nan(g) or g >= 0.0:
						high = middle
					else:
						low = middle
				var plane: Vector3 = _burn_plane(state, burn, point, normal, lat, lon, high)[0]
				best = {"time": high, "state": _state_after(state, burn, point, plane), "burn": burn}
				break
			previous = gap
			t += PASS_STEP_S
		burn += BURN_STEP_S
	return best


# Tir : cible à MIN_ELEVATION_DEG au moins, sur l'orbite actuelle ou en avance d'un passage obtenu par manœuvre
# (le temps de parcourir l'angle de visibilité avant la verticale).
static func _earliest_strike(state: Dictionary, lat: float, lon: float, from_s: float, horizon_s: float) -> Dictionary:
	var reach := visibility_angle(state.radius)
	var best := {"time": INF, "state": state}
	var t := from_s
	while t <= horizon_s:
		if _position(state, t).angle_to(_target(state, lat, lon, t)) <= reach:
			best.time = t
			break
		t += STRIKE_STEP_S
	var over := _earliest_photo(state, lat, lon, from_s, minf(horizon_s, best.time))
	if over.time < INF:
		var early := maxf(over.burn, over.time - reach / float(state.n))
		if early < best.time:
			best = {"time": early, "state": over.state}
	return best


## Angle au centre de la Terre (rad) dans lequel une cible est vue à MIN_ELEVATION_DEG au moins, pour une orbite de
## rayon radius_km : acos(R·cos ε / a) − ε.
static func visibility_angle(radius_km: float) -> float:
	var elevation := deg_to_rad(MIN_ELEVATION_DEG)
	return acos(OrbitSimulation.EARTH_RADIUS_KM * cos(elevation) / radius_km) - elevation


# Écart angulaire (rad, −π..π) entre le chemin parcouru depuis la poussée et l'angle du point de poussée à la cible,
# dans le plan qui les contient ; NAN si ce plan est hors des limites du poste de pilotage.
static func _gap(state: Dictionary, burn: float, point: Vector3, normal: Vector3, lat: float, lon: float,
		t: float) -> float:
	var found := _burn_plane(state, burn, point, normal, lat, lon, t)
	var plane: Vector3 = found[0]
	var target: Vector3 = found[1]
	if plane == Vector3.ZERO:
		return NAN
	var inclination := acos(clampf(plane.z, -1.0, 1.0))
	var shift := wrapf(atan2(plane.x, -plane.y) - _raan(state, burn), -PI, PI)
	if inclination > deg_to_rad(OrbitSimulation.MAX_INCLINATION_DEG) \
			or absf(shift) > deg_to_rad(FlightComputer.MAX_NODE_SHIFT_DEG):
		return NAN
	var angle := acos(clampf(point.dot(target), -1.0, 1.0))
	if point.cross(target).dot(plane) < 0.0:
		angle = TAU - angle
	return wrapf(float(state.n) * (t - burn) - angle, -PI, PI)


# Plan visé par une poussée au temps burn (station en point) pour passer sur la cible au temps t : [normale (ZERO si
# indéfini), cible tournée de la précession (_target_at_burn)]. La précession est d'abord celle de l'orbite
# actuelle, puis celle du plan trouvé (son inclinaison).
static func _burn_plane(state: Dictionary, burn: float, point: Vector3, normal: Vector3, lat: float, lon: float,
		t: float) -> Array:
	var target := _target_at_burn(state, burn, lat, lon, t, state.raan_rate)
	var plane := _plane_through(point, target, normal)
	if plane != Vector3.ZERO and state.raan_rate != 0.0:
		var rate := OrbitSimulation.raan_rate_at(state.radius - OrbitSimulation.EARTH_RADIUS_KM,
				rad_to_deg(acos(clampf(plane.z, -1.0, 1.0))))
		target = _target_at_burn(state, burn, lat, lon, t, rate)
		plane = _plane_through(point, target, normal)
	return [plane, target]


# Normale du plan contenant point et target, dans le même sens que normal ; ZERO si les deux points sont alignés.
static func _plane_through(point: Vector3, target: Vector3, normal: Vector3) -> Vector3:
	var plane := point.cross(target)
	if plane.length() < 0.02:
		return Vector3.ZERO
	plane = plane.normalized()
	return plane if plane.dot(normal) >= 0.0 else -plane


# Orbite après une poussée au temps burn (station en point) vers le plan de normale plane.
static func _state_after(state: Dictionary, burn: float, point: Vector3, plane: Vector3) -> Dictionary:
	if plane == Vector3.ZERO:
		return state
	var inclination := acos(clampf(plane.z, -1.0, 1.0))
	var raan := atan2(plane.x, -plane.y)
	var node := Vector3(cos(raan), sin(raan), 0.0)
	var quarter := Vector3(-sin(raan) * cos(inclination), cos(raan) * cos(inclination), sin(inclination))
	var arg_lat := atan2(point.dot(quarter), point.dot(node))
	var after := _state(state.unix, state.radius - OrbitSimulation.EARTH_RADIUS_KM, rad_to_deg(inclination), raan,
			arg_lat, state.raan_rate != 0.0)
	# Ramené au temps 0 de state.
	after.raan -= after.raan_rate * burn
	after.arg_lat -= after.n * burn
	return after


static func _state(unix: float, altitude_km: float, inclination_deg: float, raan: float, arg_lat: float,
		precession: bool) -> Dictionary:
	return {"unix": unix, "radius": OrbitSimulation.EARTH_RADIUS_KM + altitude_km,
			"inclination": deg_to_rad(inclination_deg), "raan": raan, "arg_lat": arg_lat,
			"n": OrbitSimulation.mean_motion_at(altitude_km),
			"raan_rate": OrbitSimulation.raan_rate_at(altitude_km, inclination_deg) if precession else 0.0}


static func _raan(state: Dictionary, t: float) -> float:
	return state.raan + state.raan_rate * t


# Direction (unitaire, ECI) de la station au temps t.
static func _position(state: Dictionary, t: float) -> Vector3:
	return OrbitSimulation.circular_position_eci(1.0, state.inclination, _raan(state, t), state.arg_lat + state.n * t)


# Point du sol au temps t, tourné autour de l'axe des pôles de la précession du plan (raan_rate) entre burn et t :
# le plan qui le contient au temps burn contiendra le point lui-même au temps t.
static func _target_at_burn(state: Dictionary, burn: float, lat: float, lon: float, t: float,
		raan_rate: float) -> Vector3:
	return _target(state, lat, lon, t).rotated(Vector3.BACK, -raan_rate * (t - burn))


# Direction (unitaire, ECI) d'un point du sol au temps t (la Terre tourne).
static func _target(state: Dictionary, lat: float, lon: float, t: float) -> Vector3:
	var theta := OrbitSimulation._sidereal_angle_at_unix(state.unix + t)
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	var x := cos(la) * cos(lo)
	var y := cos(la) * sin(lo)
	return Vector3(x * cos(theta) - y * sin(theta), x * sin(theta) + y * cos(theta), sin(la))
