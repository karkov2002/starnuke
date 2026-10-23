extends SceneTree
## Banc d'équilibrage des campagnes (outil hors-jeu) : simule chaque mission en Monte-Carlo pour trois profils de
## joueur et compare leurs notes aux cibles (expert ≥ 17, moyen 12 à 15, débutant 8 à 11).
## Usage (éditeur fermé ou ouvert) :
##   godot --headless --path . -s tools/balance_campaign.gd                          campagne officielle
##   godot --headless --path . -s tools/balance_campaign.gd -- <campagne> [tirages] [graine]
## Le rapport (Markdown) est affiché et écrit dans tools/bench/results/balance_<campagne>_<date>.md.
##
## Modèle d'une mission (déroulement au plus tôt de MissionPlanner.timeline, mêmes règles que CampaignDirector) :
## - le joueur remplit la mission après le passage le plus tôt possible, avec un retard tiré au hasard dans
##   delay_orbits (en orbites) ;
## - pour chaque objectif : à chaque passage, il le manque avec la probabilité miss (pas prêt) ; sinon, son écart au
##   sol suit une loi demi-normale d'écart type sigma_km (photo : point sous la station ; tir : impact) ; un écart au
##   moins égal à la tolérance ne compte pas. Chaque passage manqué ou raté coûte une orbite ;
## - au-delà de l'échéance, les objectifs restants valent 0 ; note = précision pondérée × facteur temps
##   (MissionScoring), réussite si ≥ success_score.
## Note de la campagne d'un tirage : moyenne de ses missions (comme CampaignSession.global_score). Les profils sont des
## estimations à recaler avec les journaux de vraies parties (user://logs, scripts/campaign_journal.gd) : retards
## (earliest_s, elapsed_s), distances (shot.nearest_km), passages manqués.

const PROFILES := {
	"expert": {"target": [17.0, 20.0], "delay_orbits": [0.0, 0.3], "miss": 0.05,
			"sigma_km": {"photo": 5.0, "strike": 3.0}},
	"moyen": {"target": [12.0, 15.0], "delay_orbits": [0.3, 1.2], "miss": 0.2,
			"sigma_km": {"photo": 12.0, "strike": 6.0}},
	"débutant": {"target": [8.0, 11.0], "delay_orbits": [1.0, 2.5], "miss": 0.35,
			"sigma_km": {"photo": 20.0, "strike": 10.0}},
}
const DEFAULT_RUNS := 1000
const DEFAULT_SEED := 1
const RESULTS := "res://tools/bench/results"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var args := PackedStringArray(OS.get_cmdline_user_args())
	var id := args[0] if args.size() > 0 else Campaigns.OFFICIAL
	var runs := int(args[1]) if args.size() > 1 else DEFAULT_RUNS
	_rng.seed = int(args[2]) if args.size() > 2 else DEFAULT_SEED
	var campaign := CampaignData.parse(Campaigns.read(id))
	if not campaign.is_valid():
		print("✗ %s : campagne absente ou invalide (tools/check_campaign.gd)" % id)
		quit(1)
		return
	var report := _report(id, campaign, runs)
	print(report)
	var date := Time.get_date_string_from_system()
	var path := ProjectSettings.globalize_path(RESULTS).path_join("balance_%s_%s.md" % [id, date])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(report)
		print("Rapport : " + path)
	quit(0)


func _report(id: String, campaign: CampaignData, runs: int) -> String:
	var rows := MissionPlanner.timeline(campaign)
	var defaults := campaign.defaults()
	var lines := PackedStringArray([
		"# Équilibrage — %s" % id, "",
		"%d tirages par profil, graine %d, %s. Cibles : %s." % [runs, _rng.seed, Time.get_datetime_string_from_system(),
				", ".join(PROFILES.keys().map(func(p: String) -> String:
					return "%s %s" % [p, _band(PROFILES[p].target)]))], "",
		"| Mission | Au plus tôt | Référence | Échéance | " + " | ".join(PROFILES.keys()) + " |",
		"|---|---|---|---|" + "---|".repeat(PROFILES.size()),
	])
	# Notes par profil : tirage -> somme des notes des missions (moyenne de campagne).
	var totals := {}
	for profile: String in PROFILES:
		totals[profile] = PackedFloat64Array()
		totals[profile].resize(runs)
	var flagged := 0
	for row in rows:
		var mission := campaign.mission(row.mission)
		var cells := PackedStringArray()
		for profile: String in PROFILES:
			var scores := PackedFloat64Array()
			var successes := 0
			for r in runs:
				var score := _simulate(mission, row, PROFILES[profile], defaults)
				scores.append(score)
				totals[profile][r] += score
				if score >= float(defaults.get("success_score", 10.0)):
					successes += 1
			var mean := _mean(scores)
			var ok := _in_band(mean, PROFILES[profile].target)
			if not ok:
				flagged += 1
			cells.append("%s%.1f ± %.1f (%d %%)" % ["" if ok else "⚠ ", mean, _sd(scores, mean),
					roundi(100.0 * successes / runs)])
		lines.append("| %s (%s) | %s | %s | %s | %s |" % [row.mission, row.day,
				"impossible" if row.earliest_s == INF else _hours(row.earliest_s), _hours(row.par_s),
				_hours(row.deadline_s), " | ".join(cells)])
	var campaign_cells := PackedStringArray()
	for profile: String in PROFILES:
		var means := PackedFloat64Array()
		for total in totals[profile]:
			means.append(total / maxf(rows.size(), 1.0))
		var mean := _mean(means)
		var ok := _in_band(mean, PROFILES[profile].target)
		if not ok:
			flagged += 1
		campaign_cells.append("%s%.1f ± %.1f" % ["" if ok else "⚠ ", mean, _sd(means, mean)])
	lines.append("| **Campagne** | | | | %s |" % " | ".join(campaign_cells))
	lines.append("")
	lines.append("Cellules : note moyenne ± écart type (part de réussites). Au plus tôt, référence et échéance : "
			+ "depuis l'arrivée du briefing (départ du chrono).")
	lines.append("")
	lines.append("%d case(s) hors cible (⚠)." % flagged if flagged > 0 else "Toutes les notes sont dans leur cible.")
	lines.append("")
	lines.append("Profils : " + "; ".join(PROFILES.keys().map(func(p: String) -> String:
		var profile: Dictionary = PROFILES[p]
		return "%s : retard %s orbite(s), passage manqué %d %%, écart type %s km (photo) et %s km (tir)" % [p,
				"%.1f à %.1f" % profile.delay_orbits, roundi(100.0 * profile.miss), profile.sigma_km.photo,
				profile.sigma_km.strike])) + ".")
	return "\n".join(lines) + "\n"


## Note d'un tirage de la mission pour un profil.
func _simulate(mission: Dictionary, row: Dictionary, profile: Dictionary, defaults: Dictionary) -> float:
	var objectives: Array = mission.objectives
	if row.earliest_s == INF:
		return 0.0
	var limit: float = row.deadline_s
	var t: float = row.earliest_s + _rng.randf_range(profile.delay_orbits[0], profile.delay_orbits[1]) * row.period_s
	var precisions := []
	for objective: Dictionary in objectives:
		var tolerance := MissionScoring.tolerance_km(objective, defaults)
		var precision := NAN
		while t <= limit:
			if _rng.randf() >= profile.miss:
				var d := absf(_rng.randfn(0.0, profile.sigma_km[objective.type]))
				if d < tolerance:
					precision = MissionScoring.precision(d, tolerance)
					break
			t += row.period_s
		precisions.append(precision)
	var weights: Array = objectives.map(func(o: Dictionary) -> float: return float(o.get("weight", 1.0)))
	var factor := MissionScoring.time_factor(minf(t, limit), row.par_s, row.deadline_s,
			float(defaults.get("time_floor", 0.6)))
	return MissionScoring.mission_precision(precisions, weights) * factor


static func _mean(values: PackedFloat64Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(values.size(), 1.0)


static func _sd(values: PackedFloat64Array, mean: float) -> float:
	var total := 0.0
	for v in values:
		total += (v - mean) * (v - mean)
	return sqrt(total / maxf(values.size(), 1.0))


static func _in_band(value: float, band: Array) -> bool:
	return value >= float(band[0]) and value <= float(band[1])


static func _band(band: Array) -> String:
	return "≥ %d" % band[0] if band[1] >= CampaignData.MAX_SCORE else "%d à %d" % band


static func _hours(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	return "%d h %02d" % [floori(minutes / 60.0), minutes % 60]
