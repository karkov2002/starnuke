extends SceneTree
## Outil hors-jeu : vérifie un ou plusieurs campaign.json (format 2, scripts/campaign_data.gd) et liste leurs erreurs.
## Usage (éditeur fermé ou ouvert) :
##   godot --headless --path . -s tools/check_campaign.gd                 toutes les campagnes de campaign/
##   godot --headless --path . -s tools/check_campaign.gd -- starnuke     une campagne (nom de son dossier)
## Code de sortie : 0 si tout est valide, 1 sinon.
## Pour une campagne valide, liste aussi par journée et par mission le passage le plus tôt possible (MissionPlanner,
## manœuvres comprises), le temps de référence calculé et l'échéance, en enchaînant les missions comme si chacune
## était remplie au plus tôt (toutes les missions de la journée, sans tenir compte de leurs conditions « when ») et
## en dormant dès la fin de la journée ; « ⚠ » : mission impossible dans son délai (avertissement, pas une erreur).


func _initialize() -> void:
	var ids := PackedStringArray(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = DirAccess.get_directories_at(Campaigns.root())
	var failed := 0
	for id in ids:
		var data := Campaigns.read(id)
		if data.is_empty():
			print("✗ %s : campaign.json absent ou illisible (JSON invalide, pas un objet)" % id)
			failed += 1
			continue
		var campaign := CampaignData.parse(data)
		if campaign.is_valid():
			var missions: Dictionary = data.get("missions", {})
			print("✓ %s : valide (%d journée(s), %d mission(s))" % [id, campaign.days().size(), missions.size()])
			_print_timing(campaign)
		else:
			failed += 1
			print("✗ %s : %d erreur(s)" % [id, campaign.errors.size()])
			for error in campaign.errors:
				print("    - " + error)
	quit(1 if failed > 0 else 0)


## Passages au plus tôt, journée par journée (temps en s depuis le temps 0 de l'orbite state).
func _print_timing(campaign: CampaignData) -> void:
	var state := {}
	var t := 0.0
	var days := campaign.days()
	for i in days.size():
		var day: Dictionary = days[i]
		var start := campaign.start_of_day(i)
		if not start.is_empty():
			state = MissionPlanner.state_from_start(start)
			t = 0.0
		elif day.has("wake_up_utc"):
			var now: float = state.unix + t
			var parts := str(day.wake_up_utc).split(":")
			var wake := floorf(now / 86400.0) * 86400.0 + int(parts[0]) * 3600.0 + int(parts[1]) * 60.0
			t += wake - now + (86400.0 if wake <= now else 0.0)
		else:
			t += CampaignData.NIGHT_HOURS * 3600.0
		print("    %s (réveil %s UTC)" % [day.id, Time.get_datetime_string_from_unix_time(int(state.unix + t))])
		for entry: Dictionary in day.get("missions", []):
			var mission := campaign.mission(str(entry.mission))
			var deadline := float(mission.get("deadline_hours", 0.0)) * 3600.0 \
					+ float(mission.get("deadline_minutes", 0.0)) * 60.0
			var grace := MissionScoring.START_GRACE_S
			var plan := MissionPlanner.earliest(state, mission.objectives, t, t + grace + deadline)
			if plan.time == INF:
				print("      ⚠ %s : impossible dans le délai (échéance %s)" % [entry.mission, _hours(deadline)])
				t += grace + deadline
				continue
			var par := maxf(plan.time - t - grace, 0.0) + MissionPlanner.period_s(state)
			var fixed: Variant = mission.get("par_hours", null)
			print("      %s : au plus tôt %s après le briefing ; référence %s%s ; échéance %s" % [entry.mission,
					_hours(plan.time - t), _hours(minf(par, deadline)),
					"" if fixed == null else " (par_hours : %s)" % _hours(float(fixed) * 3600.0), _hours(deadline)])
			t = plan.time
			state = plan.state


static func _hours(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	return "%d h %02d" % [floori(minutes / 60.0), minutes % 60]
