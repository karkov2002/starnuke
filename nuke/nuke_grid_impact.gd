class_name NukeGridImpact
extends RefCounted
## Effet d'une explosion sur le réseau électrique : centrales détruites (PowerPlants, dans le rayon de
## NukeScaling.BLACKOUT_PLANT_PSI) et décision d'une panne nationale (part de la capacité du pays perdue au moins
## NukeScaling.BLACKOUT_NATIONAL_SHARE). Le rendu de la panne est fait par NukeBlackoutFX.
## Calcul pur, sûr depuis un autre thread (lectures seules).


## Bilan : {plants : [{name, fuel, capacity_mw, country}] détruites (de la plus puissante à la moins puissante),
## lost_mw, country_index (pays du point zéro, -1 en mer), country_capacity_mw, share (part de la capacité du pays
## perdue), national (indice CountryMask du pays plongé dans le noir, -1 sinon)}.
static func assess(params: NukeParams) -> Dictionary:
	var result := {"plants": [], "lost_mw": 0.0, "country_index": -1, "country_capacity_mw": 0.0, "share": 0.0,
			"national": -1}
	var plants := PowerPlants.get_plants()
	var mask := CountryMask.get_mask()
	if plants == null or mask == null:
		return result
	var radius := NukeScaling.overpressure_range_km(params.yield_kt, NukeScaling.BLACKOUT_PLANT_PSI, params.burst_height_km)
	var lost_by_country := {}
	var hit: Array[Dictionary] = []
	for i in plants.within(params.latitude_deg, params.longitude_deg, radius):
		var country := plants.countries[i]
		hit.append({"name": plants.names[i], "fuel": plants.fuels[i], "capacity_mw": plants.capacities_mw[i],
				"country": country})
		lost_by_country[country] = lost_by_country.get(country, 0.0) + plants.capacities_mw[i]
		result.lost_mw += plants.capacities_mw[i]
	hit.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.capacity_mw > b.capacity_mw)
	result.plants = hit
	# Pays : celui du point zéro, à défaut (en mer, près d'une côte) celui qui perd le plus de capacité.
	var index := mask.index_at_row(CountryMask._row_of(params.latitude_deg), wrapf(params.longitude_deg, -180.0, 180.0))
	if index < 0:
		for country: int in lost_by_country:
			if country >= 0 and (index < 0 or lost_by_country[country] > lost_by_country[index]):
				index = country
	result.country_index = index
	if index >= 0:
		var capacity := plants.country_capacity_mw[index]
		result.country_capacity_mw = capacity
		result.share = lost_by_country.get(index, 0.0) / capacity if capacity > 0.0 else 0.0
		if result.share >= NukeScaling.BLACKOUT_NATIONAL_SHARE:
			result.national = index
	return result
