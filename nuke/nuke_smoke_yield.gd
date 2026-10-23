class_name NukeSmokeYield
extends RefCounted
## Fumée des incendies par m² de sol en feu (kg/m²) d'une explosion : moyenne, sur les terres de la zone des incendies
## (rayon final, NukeScaling.fire_radius_km), du combustible consommé × facteur d'émission, pour la végétation
## (NukeScaling.SMOKE_WILDLAND_*) et le bâti (charge proportionnelle à la population, grille GHS-POP,
## NukeScaling.SMOKE_URBAN_*) ; la mer ne brûle pas (OceanMask). Calculée au tir dans le thread de NukeImpact ; les
## lois et coefficients restent dans NukeScaling, cette classe seule lit les données géographiques.


## Fumée par m² de sol en feu (kg/m²). Sûr depuis un autre thread (lectures seules).
static func estimate(params: NukeParams) -> float:
	var radius := NukeScaling.fire_radius_km(params.yield_kt, INF)
	var km_per_deg := GeoMath.KM_PER_DEGREE
	var cos_lat := maxf(cos(deg_to_rad(params.latitude_deg)), 0.05)
	var cell_km2 := pow(km_per_deg / PopulationGrid.CELLS_PER_DEGREE, 2.0) * cos_lat
	var has_population := PopulationGrid.is_available()
	var samples := NukeScaling.SMOKE_YIELD_SAMPLES
	var wildland := NukeScaling.SMOKE_WILDLAND_FUEL_KG_M2 * NukeScaling.SMOKE_WILDLAND_EF
	var total := 0.0
	var land := 0
	for i in samples:
		for j in samples:
			var x := ((i + 0.5) / samples * 2.0 - 1.0) * radius
			var y := ((j + 0.5) / samples * 2.0 - 1.0) * radius
			if x * x + y * y > radius * radius:
				continue
			var lat := params.latitude_deg + y / km_per_deg
			var lon := params.longitude_deg + x / (km_per_deg * cos_lat)
			if OceanMask.is_ocean(lat, lon):
				continue
			var density := 0.0
			if has_population:
				density = PopulationGrid.cell_population(PopulationGrid.row_of(lat), PopulationGrid.col_of(lon)) / cell_km2
			total += wildland + NukeScaling.SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2 * density * NukeScaling.SMOKE_URBAN_EF
			land += 1
	return total / land if land > 0 else wildland
