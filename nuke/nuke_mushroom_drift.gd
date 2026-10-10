class_name NukeMushroomDrift
extends RefCounted
## Dérive d'un champignon au vent (profil vertical du vent réel GFS au point d'impact, NukeParams.wind_profile), en
## unités normalisées du champignon (sommet final = 1 ; repère local : X = est, −Z = nord).
##
## Chaque hauteur part avec le vent de son altitude. Pendant la montée (NukeScaling.MUSHROOM_RISE_S), une parcelle garde
## sa hauteur relative dans le nuage : son déplacement intègre le vent des altitudes traversées (RISE_STEPS pas) ;
## ensuite, chaque hauteur avance au vent de son altitude. Le pied reste au point zéro : sous la hauteur d'ancrage
## (centre du chapeau), la dérive est multipliée par (y / ancrage)^shear, la tige penche. Le déplacement est
## échantillonné en SAMPLES hauteurs de 0 à TOP (samples, uniform drift_profile des shaders, interpolé par
## nuke/shaders/nuke_drift.gdshaderinc).
##
## Le vent est lu dans une table de WIND_TABLE hauteurs calculée une fois (le profil GFS est interpolé linéairement
## par niveaux : la table le reproduit à 1 % près), au lieu de 512 interpolations du profil par image pendant la montée.

## Nombre de hauteurs (= taille du tableau drift_profile de nuke_drift.gdshaderinc), hauteur couverte (au-dessus du
## chapeau et de sa déformation), pas d'intégration pendant la montée.
const SAMPLES := 32
const TOP := 1.4
const RISE_STEPS := 16
const WIND_TABLE := 128

## Dérive (unités normalisées) aux SAMPLES hauteurs, au dernier update().
var samples := PackedVector3Array()

var _params: NukeParams
var _height_curve: Curve
var _shear: float
var _top_km := -1.0
## Vent (unités normalisées par seconde physique) aux hauteurs de la table, de 0 à TOP × sommet.
var _wind_table := PackedVector3Array()
## Vent aux SAMPLES hauteurs, et déplacement accumulé pendant toute la montée (calculés une fois).
var _wind_units := PackedVector3Array()
var _rise_drift := PackedVector3Array()


## height_curve : montée du sommet (part du sommet final, en âge t / MUSHROOM_RISE_S) ; shear : exposant d'ancrage.
func _init(params: NukeParams, height_curve: Curve, shear: float) -> void:
	_params = params
	_height_curve = height_curve
	_shear = shear
	samples.resize(SAMPLES)


static func sample_height(i: int) -> float:
	return TOP * float(i) / float(SAMPLES - 1)


## Recalcule samples au temps t (s, physique) ; anchor_height : hauteur d'ancrage (unités normalisées).
func update(t: float, top_km: float, anchor_height: float) -> void:
	if top_km != _top_km:
		_build_tables(top_km)
	var rise := NukeScaling.MUSHROOM_RISE_S
	var rise_part: PackedVector3Array
	if t < rise:
		rise_part = _integrate_rise(t)
	else:
		if _rise_drift.is_empty():
			_rise_drift = _integrate_rise(rise)
		rise_part = _rise_drift
	var after := maxf(t - rise, 0.0)
	for i in SAMPLES:
		var anchor := pow(clampf(sample_height(i) / maxf(anchor_height, 1e-4), 0.0, 1.0), _shear)
		samples[i] = (rise_part[i] + _wind_units[i] * after) * anchor


## Dérive à la hauteur y (même interpolation que nuke_drift.gdshaderinc).
func at(y: float) -> Vector3:
	var f := clampf(y / TOP, 0.0, 1.0) * (SAMPLES - 1)
	var i := mini(int(f), SAMPLES - 2)
	return samples[i].lerp(samples[i + 1], f - i)


## Dérives extrêmes [min, max] (x et z) entre les hauteurs y_low et y_high, échantillons voisins compris.
func extent(y_low: float, y_high: float) -> Array[Vector3]:
	var step := TOP / float(SAMPLES - 1)
	var low := at(y_low)
	var high := low
	for i in SAMPLES:
		var y := sample_height(i)
		if y >= y_low - step and y <= y_high + step:
			low = low.min(samples[i])
			high = high.max(samples[i])
	return [low, high]


func _build_tables(top_km: float) -> void:
	_top_km = top_km
	_rise_drift.clear()
	_wind_table.resize(WIND_TABLE)
	for k in WIND_TABLE:
		_wind_table[k] = _wind_from_profile(TOP * top_km * float(k) / float(WIND_TABLE - 1))
	_wind_units.resize(SAMPLES)
	for i in SAMPLES:
		_wind_units[i] = _wind_at(sample_height(i) * top_km)


## Déplacement accumulé de 0 à t (≤ MUSHROOM_RISE_S) par la parcelle qui est à la hauteur y_i au temps t. Elle garde
## sa hauteur relative dans le nuage qui monte : au temps τ, elle était à y_i · h(τ) / h(t) (h : height_curve).
func _integrate_rise(t: float) -> PackedVector3Array:
	var rise := NukeScaling.MUSHROOM_RISE_S
	var h_now := maxf(_height_curve.sample(minf(t / rise, 1.0)), 0.02)
	var dt := t / RISE_STEPS
	var ratios := PackedFloat32Array()
	ratios.resize(RISE_STEPS)
	for k in RISE_STEPS:
		ratios[k] = maxf(_height_curve.sample((k + 0.5) * dt / rise), 0.02) / h_now
	var result := PackedVector3Array()
	result.resize(SAMPLES)
	for i in SAMPLES:
		var y_km := sample_height(i) * _top_km
		var d := Vector3.ZERO
		for k in RISE_STEPS:
			d += _wind_at(y_km * ratios[k])
		result[i] = d * dt
	return result


## Vent à l'altitude donnée (table), en unités normalisées par seconde physique.
func _wind_at(height_km: float) -> Vector3:
	var f := clampf(height_km / (TOP * _top_km), 0.0, 1.0) * (WIND_TABLE - 1)
	var k := mini(int(f), WIND_TABLE - 2)
	return _wind_table[k].lerp(_wind_table[k + 1], f - k)


## Vent du profil GFS à l'altitude donnée, en unités normalisées par seconde physique.
func _wind_from_profile(height_km: float) -> Vector3:
	var v := _params.wind_at(height_km)
	return Vector3(v.x, 0.0, -v.y) * (0.001 / _top_km)
