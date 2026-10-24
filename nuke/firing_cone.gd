class_name FiringCone
extends RefCounted
## Cône de tir (règle de jeu, mode libre et campagne) : un missile ne part que vers l'avant de la station, dans un
## secteur au sol centré sur la trace (direction du déplacement au-dessus du sol), et pas au-delà d'une portée.
## - Ouverture (angle total du secteur, degrés) : selon l'altitude, de APERTURE_LOW (altitude, ouverture) à
##   APERTURE_HIGH, linéaire entre les deux, bornée au-delà ; plus haut, la station voit et vise plus large.
## - Portée : RANGE_HORIZON_FRACTION de la distance au sol de l'horizon à l'altitude de la station
##   (GeoMath.horizon_angle_rad ; ~1 760 km à 400 km).
## Le secteur part du point survolé (sommet), les directions sont celles des grands cercles qui en partent (comme la
## trace) : la cible doit être à moins de la demi-ouverture de la trace, vue du point survolé, et à moins de la
## portée. Contrôlé par la commande de tir (LaunchControl) et le réticule (aim_reticle.gd) ; dessiné sur la Terre dans
## la cupola en mode « HUD : On » (FiringConeMarker). Valeurs à régler d'après les essais.

## (Altitude km, ouverture totale en degrés) : bas et haut de l'interpolation.
const APERTURE_LOW := Vector2(400.0, 70.0)
const APERTURE_HIGH := Vector2(800.0, 100.0)
## Part de la distance de l'horizon atteignable.
const RANGE_HORIZON_FRACTION := 0.8
## Sous cette distance du point survolé (km), la direction n'a pas de sens : toujours dans le cône.
const APEX_KM := 5.0
## Intervalle (s) pour la direction de la trace (point survolé maintenant et un peu plus tard).
const HEADING_STEP_S := 10.0

enum Status { OK, OUT_OF_CONE, OUT_OF_RANGE }


## Ouverture totale du cône (degrés) à l'altitude altitude_km.
static func aperture_deg(altitude_km: float) -> float:
	var t := clampf(inverse_lerp(APERTURE_LOW.x, APERTURE_HIGH.x, altitude_km), 0.0, 1.0)
	return lerpf(APERTURE_LOW.y, APERTURE_HIGH.y, t)


## Portée (km, le long du sol) à l'altitude altitude_km.
static func range_km(altitude_km: float) -> float:
	return RANGE_HORIZON_FRACTION * GeoMath.horizon_angle_rad(altitude_km) * GeoMath.EARTH_RADIUS_KM


## Sommet (point survolé, vecteur unitaire du repère du maillage de la Terre) et direction de la trace (tangente au
## sol, unitaire) : {apex, forward}.
static func frame(orbit: OrbitSimulation) -> Dictionary:
	var now := orbit.get_subsatellite_point()
	var later := orbit.get_subsatellite_point(orbit.sim_time_s + HEADING_STEP_S)
	var apex := GeoMath.lat_lon_to_mesh(now.x, now.y)
	var ahead := GeoMath.lat_lon_to_mesh(later.x, later.y)
	return {"apex": apex, "forward": (ahead - apex * apex.dot(ahead)).normalized()}


## Le point (latitude, longitude) peut-il être visé depuis la station de l'orbite orbit ?
static func status(orbit: OrbitSimulation, latitude_deg: float, longitude_deg: float) -> Status:
	var f := frame(orbit)
	var apex: Vector3 = f.apex
	var target := GeoMath.lat_lon_to_mesh(latitude_deg, longitude_deg)
	var distance_km := acos(clampf(apex.dot(target), -1.0, 1.0)) * GeoMath.EARTH_RADIUS_KM
	if distance_km > range_km(orbit.altitude_km):
		return Status.OUT_OF_RANGE
	if distance_km < APEX_KM:
		return Status.OK
	var toward := (target - apex * apex.dot(target)).normalized()
	var off_axis := rad_to_deg(acos(clampf((f.forward as Vector3).dot(toward), -1.0, 1.0)))
	return Status.OK if off_axis <= aperture_deg(orbit.altitude_km) * 0.5 else Status.OUT_OF_CONE


## Point visé aim (NukeLauncher.get_aim : {latitude, longitude}) depuis la station de la partie (NukeClock.orbit) :
## OK sans point visé ou sans orbite (rien à refuser).
static func aim_status(aim: Dictionary) -> Status:
	if aim.is_empty() or NukeClock.orbit == null:
		return Status.OK
	return status(NukeClock.orbit, aim.latitude, aim.longitude)


## Clé de langue du refus ("" : tir permis).
static func refusal_key(state: Status) -> String:
	match state:
		Status.OUT_OF_CONE:
			return "LAUNCH_OUT_OF_CONE"
		Status.OUT_OF_RANGE:
			return "LAUNCH_OUT_OF_RANGE"
	return ""
