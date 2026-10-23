class_name NukeSmokePlumes
extends RefCounted
## Panaches de fumée des incendies (composant de NukeGroundFX) : pour chaque explosion, âges de la fumée encore
## présente (émise de 0 à fire_end_s, gardée jusqu'à NukeScaling.SMOKE_MAX_AGE_S), clé d'état du panache (la maille
## est reconstruite quand une clé change : allongement de ~10 %, fin de l'émission, disparition) et maille de 1°
## des panaches (NukeCellIndex : disques de SMOKE_CELL_STEP_KM le long du vent, jusqu'où l'épaisseur optique tombe
## sous SMOKE_CELL_MIN_TAU au débit maximal des incendies : la maille reste valable quand le débit varie).
## Les lois (débit d'émission f(t), étalement σ, durée de vie) sont celles de NukeScaling.

## Pas (km) des disques qui couvrent un panache dans la maille de la fumée.
const SMOKE_CELL_STEP_KM := 60.0
const SMOKE_CELL_MIN_TAU := 0.005

## Maille des panaches (textures nuke_smoke_cells, nuke_smoke_index).
var index := NukeCellIndex.new()
## Clé d'état du panache de chaque explosion à la dernière construction (−1 : pas de fumée).
var keys := PackedInt32Array()
## Fin des incendies (s, temps physique) : au-delà, plus de fumée émise ; surface en feu maximale (part de R0²).
var fire_end_s := 0.0
var burning_peak := 0.0


## Lois des incendies d'après la table de la surface en feu (NukeScaling.smoke_table, échelle logarithmique du temps).
func _init() -> void:
	var table := NukeScaling.smoke_table()
	for value in table:
		burning_peak = maxf(burning_peak, value)
	var scale := log(1.0 + NukeScaling.SMOKE_TABLE_MAX_S / 60.0)
	for i in table.size():
		if table[i] > 1e-3 * burning_peak:
			fire_end_s = 60.0 * (exp(float(i + 1) / float(table.size() - 1) * scale) - 1.0)


## Âges (s) de la fumée encore présente dans le panache d'une explosion au temps physique t, d'après ses données
## fixes (statics, NukeGroundFX : [rayons, vent, gravats/fumée]) : (plus jeune, plus vieille) ; ZERO si elle n'en a
## plus (ou n'en a jamais : rien ne brûle, ou fumée par m² pas encore calculée par NukeImpact).
func ages(statics: Array, t: float) -> Vector2:
	if statics[0].z <= 0.0 or statics[2].y <= 0.0 or t <= 0.0:
		return Vector2.ZERO
	var youngest := maxf(t - fire_end_s, 0.0)
	var oldest := minf(t, NukeScaling.SMOKE_MAX_AGE_S)
	return Vector2(youngest, oldest) if oldest > youngest else Vector2.ZERO


## Clé de l'état d'un panache (voir en tête) ; −1 sans fumée.
func key(statics: Array, t: float) -> int:
	var a := ages(statics, t)
	if a == Vector2.ZERO:
		return -1
	return floori(log(1.0 + a.y / 600.0) * 10.0) * 1000 + floori(log(1.0 + a.x / 600.0) * 10.0)


## Reconstruit la maille des panaches : effects (dans l'ordre des colonnes), times (temps physiques), statics
## (instance_id -> données fixes). Rend le nombre de panaches actifs ; keys est mise à jour.
func rebuild(effects: Array[NukeEffect], times: PackedFloat64Array, statics: Dictionary) -> int:
	keys.resize(effects.size())
	index.clear()
	var active := 0
	for i in effects.size():
		var fixed: Array = statics[effects[i].get_instance_id()]
		keys[i] = key(fixed, times[i])
		var a := ages(fixed, times[i])
		if a == Vector2.ZERO:
			continue
		active += 1
		var fire_km: float = fixed[0].z
		var wind: Vector4 = fixed[1]
		var smoke_yield: float = fixed[2].y
		var origin := (effects[i].position / OrbitSimulation.SCENE_UNITS_PER_KM).normalized()
		var direction := Vector3(wind.x, wind.y, wind.z)
		var start_km := wind.w * a.x / 1000.0
		var end_km := wind.w * a.y / 1000.0 + 2.0 * NukeScaling.smoke_sigma_m(fire_km, a.y) / 1000.0
		var steps := maxi(ceili((end_km - start_km) / SMOKE_CELL_STEP_KM), 1)
		for s in steps + 1:
			var along := lerpf(start_km, end_km, float(s) / steps)
			var age := along * 1000.0 / wind.w
			# Demi-largeur où τ tombe sous le seuil : τ_axe · exp(−y² / 2σ²) = SMOKE_CELL_MIN_TAU.
			var sigma := NukeScaling.smoke_sigma_m(fire_km, age)
			var axis_tau := NukeScaling.SMOKE_MEE_M2_KG * smoke_yield * 1.0e6 * fire_km * fire_km * burning_peak \
					/ NukeScaling.FIRE_BURN_S * exp(-age / NukeScaling.SMOKE_LIFETIME_S) / (wind.w * sqrt(TAU) * sigma)
			var half_width := sigma * sqrt(2.0 * log(maxf(axis_tau / SMOKE_CELL_MIN_TAU, 1.0)))
			# Marge : front étalé et bords déformés par le bruit du shader (jusqu'à ~0,7 σ), front à ±2 σ.
			var radius := (half_width + 2.0 * sigma) / 1000.0 + SMOKE_CELL_STEP_KM
			# Point du grand cercle à la distance along, dans la direction du vent (repère du maillage).
			var angle := along / OrbitSimulation.EARTH_RADIUS_KM
			var point := GeoMath.mesh_to_lat_lon(origin * cos(angle) + direction * sin(angle))
			index.add_disc(point.x, point.y, radius, i)
	index.upload()
	return active
