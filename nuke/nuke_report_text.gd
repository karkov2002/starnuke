class_name NukeReportText
extends RefCounted
## Textes du bilan d'une explosion (console) et mise en forme des nombres, à partir des résultats de NukeCasualties,
## NukeGridImpact et NukeFallout. Fonctions pures, utilisables depuis un autre thread.


## Nombre arrondi à 3 chiffres significatifs, espaces entre milliers (« 1 230 000 »).
static func count(value: float) -> String:
	var n := int(round(value))
	if n >= 1000:
		var magnitude := pow(10.0, floor(log(float(n)) / log(10.0)) - 2.0)
		n = int(round(n / magnitude) * magnitude)
	var digits := str(n)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return out


## Part de la population d'un pays : « 0 % », « < 0,01 % », « 1,23 % » ; « — » sans population connue.
static func share(killed: float, population: float) -> String:
	if population <= 0.0:
		return "—"
	if killed < 0.5:
		return "0 %"
	var percent := 100.0 * killed / population
	return "< 0,01 %" if percent < 0.01 else ("%.2f %%" % percent).replace(".", ",")


## Nom affiché d'un pays (fiche CountryMask ou entrée de bilan) : suivi de son État souverain s'il en dépend.
static func country_label(c: Dictionary) -> String:
	var label: String = c.name_fr
	if not c.sovereign_fr.is_empty() and c.sovereign_fr != c.name_fr:
		label += " (%s)" % c.sovereign_fr
	return label


## En-tête du tir : puissance, lieu (pays, en mer), vent au sol et au niveau du chapeau.
static func launch(params: NukeParams) -> String:
	var country := params.get_country()
	var place := " en mer" if params.over_ocean else ""
	if not country.is_empty():
		place += " (%s)" % country.name_fr if country.sovereign_fr == country.name_fr \
				else " (%s, %s)" % [country.name_fr, country.sovereign_fr]
	var text := "NukeLauncher : %s sur %.2f°, %.2f°%s (vent du %03d°, %.1f m/s)" % [
			NukeScaling.format_yield(params.yield_kt), params.latitude_deg, params.longitude_deg, place,
			roundi(params.wind_direction_deg), params.wind_speed_m_s]
	if not params.wind_profile.is_empty():
		# Vent à l'altitude du chapeau stabilisé (~3/4 du sommet).
		var cap_km := 0.75 * NukeScaling.cloud_top_km(params.yield_kt)
		var cap_wind := params.wind_at(cap_km)
		text += "\n  vent à %.0f km (chapeau) : du %03d°, %.1f m/s" % [cap_km,
				roundi(NukeWind.from_direction_deg(cap_wind)), cap_wind.length()]
	return text


## Bilan final du souffle et de la chaleur (NukeCasualties.estimate), par pays.
static func casualties(result: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("  souffle et chaleur, bilan final (OTA 1979, population 2030) : %s morts, %s blessés, %s personnes à plus de 1 psi"
			% [count(result.killed), count(result.injured), count(result.exposed)])
	for c: Dictionary in result.countries:
		if c.killed + c.injured < 1.0:
			continue
		var part := ""
		if c.pop_est > 0:
			part = ", %s de la population" % share(c.killed, c.pop_est)
		lines.append("    %s : %s morts, %s blessés%s" % [country_label(c), count(c.killed), count(c.injured), part])
	return "\n".join(lines)


## Réseau électrique (NukeGridImpact.assess) : centrales détruites, part de la capacité du pays, panne nationale.
static func grid(result: Dictionary) -> String:
	var plants: Array = result.plants
	if plants.is_empty():
		return "  réseau électrique : aucune centrale recensée détruite"
	var names: Array[String] = []
	for plant: Dictionary in plants.slice(0, 3):
		names.append("%s (%s, %d MW)" % [plant.name, plant.fuel, roundi(plant.capacity_mw)])
	var text := "  réseau électrique : %d centrale(s) détruite(s), %d MW : %s%s" % [plants.size(), roundi(result.lost_mw),
			", ".join(names), "…" if plants.size() > 3 else ""]
	if result.country_index >= 0 and result.country_capacity_mw > 0.0:
		var name_fr: String = CountryMask.get_mask().countries[result.country_index].name_fr
		text += "\n    %s perd %s %% de sa capacité (%d MW)" % [name_fr, ("%.1f" % (100.0 * result.share)).replace(".", ","),
				roundi(result.country_capacity_mw)]
		if result.national >= 0:
			text += " : black-out national"
	return text


## Retombées (NukeFallout.estimate) : vent, zone dangereuse, morts et malades à l'horizon, par pays.
static func fallout(result: Dictionary, params: NukeParams) -> String:
	if result.is_empty():
		return "  retombées : aucune (explosion en altitude)"
	var last := NukeFallout.TIME_SAMPLES - 1
	var text := "  retombées (WSEG-10, %s) : vent %.0f m/s vers %03d°, zone dangereuse sur %.0f km ; à %d jours : %s morts, %s malades" \
			% [NukeScaling.format_yield(params.yield_kt), result.wind_m_s, posmod(roundi(result.direction_deg), 360),
			result.hotline_km, roundi(NukeFallout.HORIZON_H / 24.0), count(result.total_dead[last]),
			count(result.total_sick[last])]
	for c: Dictionary in result.countries.slice(0, 5):
		var dead: PackedFloat64Array = c.dead
		var sick: PackedFloat64Array = c.sick
		if dead[last] >= 1.0 or sick[last] >= 100.0:
			text += "\n    %s : %s morts, %s malades" % [c.name_fr, count(dead[last]), count(sick[last])]
	return text
