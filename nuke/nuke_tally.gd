class_name NukeTally
extends RefCounted
## Bilan cumulé de toutes les explosions en cours, à l'instant présent de chacune (NukeCasualties.snapshot : souffle,
## chaleur, retombées), par pays. Données pour la fenêtre de bilan (NukeReportPanel), sans mise en forme.


## Retour : {count (explosions), killed, injured, final_killed (projection), pending (explosions dont le bilan est
## encore en calcul), countries : [{code, label, killed, injured, explosions, pop_est, blackout}]} trié par morts
## décroissants, puis par nombre d'explosions. explosions : celles dont le point zéro est sur le territoire du pays (une
## explosion frontalière fait aussi des victimes chez le voisin). Pays retenus : touchés, visés ou sous black-out.
static func compute(effects: Array[NukeEffect]) -> Dictionary:
	var by_code := {}
	var result := {"count": effects.size(), "killed": 0.0, "injured": 0.0, "final_killed": 0.0, "pending": 0,
			"countries": []}
	var mask := CountryMask.get_mask()
	for effect in effects:
		var ground_zero := effect.params.get_country()
		if not ground_zero.is_empty():
			_entry(by_code, ground_zero).explosions += 1
		if not effect.grid.is_empty() and effect.grid.national >= 0 and mask:
			_entry(by_code, mask.countries[effect.grid.national]).blackout = true
		if effect.impact_pending or effect.fallout_pending:
			result.pending += 1
		var now := NukeCasualties.snapshot(effect.casualties, effect.fallout, effect.get_time_s())
		result.killed += now.killed
		result.injured += now.injured
		result.final_killed += now.final_killed
		for c: Dictionary in now.countries:
			var entry := _entry(by_code, c)
			entry.killed += c.killed
			entry.injured += c.injured
	for code: String in by_code:
		var entry: Dictionary = by_code[code]
		if entry.killed + entry.injured >= 1.0 or entry.blackout or entry.explosions > 0:
			result.countries.append(entry)
	result.countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.killed > b.killed if a.killed != b.killed else a.explosions > b.explosions)
	return result


## Ligne d'un pays (créée au besoin), à partir d'une fiche CountryMask ou d'un pays de NukeCasualties.snapshot.
static func _entry(by_code: Dictionary, country: Dictionary) -> Dictionary:
	var code: String = country.code
	if not by_code.has(code):
		by_code[code] = {"code": code, "label": NukeReportText.country_label(country), "killed": 0.0, "injured": 0.0,
				"explosions": 0, "pop_est": country.pop_est, "blackout": false}
	return by_code[code]
