class_name GeoMath
extends RefCounted
## Constantes et formules géographiques partagées par tout le jeu (une seule source : orbite, bilans des explosions,
## cartes, radio, télévision). Fonctions pures, sûres depuis un autre thread.
##
## Repère du maillage de la Terre (SphereMesh du nœud Earth) : +Y = pôle nord, +Z = longitude −180°, +X = longitude
## −90° ; ECEF (x vers 0°, y vers 90° E, z nord) s'y envoie par (x, y, z) → (−y, z, −x), cf. OrbitSimulation.

## Rayon moyen de la Terre (sphère).
const EARTH_RADIUS_KM := 6371.0
const EARTH_RADIUS_M := EARTH_RADIUS_KM * 1000.0
## Longueur d'un degré de méridien (km) : π · R / 180.
const KM_PER_DEGREE := 111.195


## Angle au centre (rad) entre deux points (latitude, longitude en degrés) : formule de haversine.
static func central_angle_rad(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var a := deg_to_rad(lat1)
	var b := deg_to_rad(lat2)
	var d := sin((b - a) * 0.5) ** 2 + cos(a) * cos(b) * sin(deg_to_rad(lon2 - lon1) * 0.5) ** 2
	return 2.0 * asin(sqrt(minf(d, 1.0)))


## Distance au sol (km, grand cercle) entre deux points (latitude, longitude en degrés).
static func distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	return EARTH_RADIUS_KM * central_angle_rad(lat1, lon1, lat2, lon2)


## Verticale (unitaire) du point (degrés) dans le repère du maillage de la Terre.
static func lat_lon_to_mesh(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector3(-cos(lat) * sin(lon), sin(lat), -cos(lat) * cos(lon))


## Direction de l'est (unitaire) à la longitude donnée, repère du maillage.
static func mesh_east(lon_deg: float) -> Vector3:
	var lon := deg_to_rad(lon_deg)
	return Vector3(-cos(lon), 0.0, sin(lon))


## (latitude, longitude) en degrés d'un vecteur du repère du maillage (réciproque de lat_lon_to_mesh).
static func mesh_to_lat_lon(v: Vector3) -> Vector2:
	var n := v.normalized()
	return Vector2(rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(-n.x, -n.z)))


## Distance le long du rayon (origin, direction unitaire) jusqu'à l'entrée dans la sphère, ou −1 si le rayon la
## manque ou si l'entrée est derrière l'origine (origine dans la sphère : −1 aussi).
static func ray_sphere(origin: Vector3, direction: Vector3, center: Vector3, radius: float) -> float:
	var oc := origin - center
	var b := oc.dot(direction)
	var discriminant := b * b - (oc.length_squared() - radius * radius)
	if discriminant < 0.0:
		return -1.0
	var t := -b - sqrt(discriminant)
	return t if t > 0.0 else -1.0


## « 42.18° N » : positive_key et negative_key sont les clés de langue des directions (DIR_N, DIR_S, DIR_E, DIR_W).
static func format_angle(value: float, positive_key: String, negative_key: String, decimals := 2) -> String:
	return "%.*f° %s" % [decimals, absf(value), TranslationServer.translate(positive_key if value >= 0.0 else negative_key)]


## « 48.86° N  2.35° E » (directions traduites).
static func format_lat_lon(lat_deg: float, lon_deg: float, decimals := 2) -> String:
	return format_angle(lat_deg, "DIR_N", "DIR_S", decimals) + "  " + format_angle(lon_deg, "DIR_E", "DIR_W", decimals)
