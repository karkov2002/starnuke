extends SceneTree
## Outil hors-jeu : vérifie un ou plusieurs campaign.json (format 2, scripts/campaign_data.gd) et liste leurs erreurs.
## Usage (éditeur fermé ou ouvert) :
##   godot --headless --path . -s tools/check_campaign.gd                 toutes les campagnes de campaign/
##   godot --headless --path . -s tools/check_campaign.gd -- starnuke     une campagne (nom de son dossier)
## Code de sortie : 0 si tout est valide, 1 sinon.


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
		else:
			failed += 1
			print("✗ %s : %d erreur(s)" % [id, campaign.errors.size()])
			for error in campaign.errors:
				print("    - " + error)
	quit(1 if failed > 0 else 0)
