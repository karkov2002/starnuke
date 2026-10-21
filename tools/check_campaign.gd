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


## Passages au plus tôt, journée par journée (MissionPlanner.timeline).
func _print_timing(campaign: CampaignData) -> void:
	var day := ""
	for row in MissionPlanner.timeline(campaign):
		if row.day != day:
			day = row.day
			print("    %s (réveil %s UTC)" % [day, Time.get_datetime_string_from_unix_time(int(row.wake_unix))])
		if row.earliest_s == INF:
			print("      ⚠ %s : impossible dans le délai (échéance %s)" % [row.mission, _hours(row.deadline_s)])
		else:
			print("      %s : au plus tôt %s après le briefing ; référence %s ; échéance %s" % [row.mission,
					_hours(row.earliest_s), _hours(row.par_s), _hours(row.deadline_s)])


static func _hours(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	return "%d h %02d" % [floori(minutes / 60.0), minutes % 60]
