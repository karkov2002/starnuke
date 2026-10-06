class_name NukeAtmosphere
extends RefCounted
## Transmittance de l'air entre deux points (positions en km dans le repère de la planète), pour la lumière des
## flashs. Même modèle et mêmes coefficients que la lumière du soleil (shaders/sun_light.gdshaderinc) : Rayleigh
## (hauteur d'échelle 8 km) et aérosols (1,2 km), densités exponentielles. Même calcul que nuke_air_transmittance()
## dans nuke/shaders/nuke_flash.gdshaderinc : intégration en STEPS pas, resserrés près de l'extrémité la plus basse
## (là où l'air est le plus dense).

const PLANET_RADIUS_KM := 6371.0
const RAYLEIGH_BETA := Vector3(5.802e-3, 13.558e-3, 33.1e-3) # par km, au niveau de la mer
const MIE_EXTINCTION := 4.4e-3
const RAYLEIGH_HEIGHT_KM := 8.0
const MIE_HEIGHT_KM := 1.2
const STEPS := 8


## Transmittance (r, v, b) entre a et b.
static func transmittance(a: Vector3, b: Vector3) -> Vector3:
	var low := a
	var high := b
	if a.length() > b.length():
		low = b
		high = a
	var segment := high - low
	var rayleigh := 0.0
	var mie := 0.0
	for k in STEPS:
		var t0 := pow(float(k) / STEPS, 2.0)
		var t1 := pow(float(k + 1) / STEPS, 2.0)
		var h := maxf((low + segment * (0.5 * (t0 + t1))).length() - PLANET_RADIUS_KM, 0.0)
		rayleigh += exp(-h / RAYLEIGH_HEIGHT_KM) * (t1 - t0)
		mie += exp(-h / MIE_HEIGHT_KM) * (t1 - t0)
	var length := segment.length()
	var od := RAYLEIGH_BETA * (rayleigh * length) + Vector3.ONE * (MIE_EXTINCTION * mie * length)
	return Vector3(exp(-od.x), exp(-od.y), exp(-od.z))


## Transmittance moyenne pondérée par la sensibilité de l'œil (luminance).
static func luminance_transmittance(a: Vector3, b: Vector3) -> float:
	return transmittance(a, b).dot(Vector3(0.2126, 0.7152, 0.0722))
