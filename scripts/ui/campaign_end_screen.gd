extends Control
## Écran de fin de campagne (scenes/ui/campaign_end_screen.tscn), quand on dort après la dernière journée
## (CampaignDirector.sleep, sauvegarde déjà effacée) : nom de la campagne, message de fin (« ending », choisi selon
## les notes comme celui envoyé par la radio), moyenne globale sur 20 avec RÉUSSITE / ÉCHEC (success_score), puis le
## détail par journée (note de la journée) et par mission jouée (note, verdict), dans l'ordre de la campagne. Lit les
## notes de Campaigns (results, day_scores) : elles ne sont vidées (Campaigns.start_free) qu'au « Retour au menu ».
## Textes : clés des fichiers de langue (CAMPAIGN_END_*).

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const FADE_IN_S := 1.5
const SUCCESS_COLOR := Color(0.45, 0.85, 0.5)
const FAILURE_COLOR := Color(0.9, 0.35, 0.3)
const DIM_COLOR := Color(0.6, 0.62, 0.66)
const DETAIL_WIDTH := 760.0
const DETAIL_HEIGHT := 360.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	var campaign := Campaigns.current
	var success_score := float(campaign.defaults().get("success_score", 10.0)) if campaign else 10.0

	_add_label(column, "CAMPAIGN_END_TITLE", 56, Color.WHITE)
	if campaign:
		_add_label(column, Campaigns.text_of(campaign.data, "name", Campaigns.current_id), 30, DIM_COLOR, false)
		var ending := _ending_text()
		if not ending.is_empty():
			var message := _add_label(column, ending, 24, Color(0.85, 0.87, 0.9), false)
			message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			message.custom_minimum_size.x = DETAIL_WIDTH
	var global: Variant = Campaigns.global_score()
	if global == null:
		_add_label(column, "CAMPAIGN_END_NO_MISSION", 32, DIM_COLOR)
	else:
		var passed := float(global) >= success_score
		_add_label(column, tr("CAMPAIGN_END_GLOBAL").format({"score": "%.1f" % float(global),
				"verdict": tr("RESULT_SUCCESS" if passed else "RESULT_FAILURE")}), 36,
				SUCCESS_COLOR if passed else FAILURE_COLOR, false)
	if campaign:
		column.add_child(_build_details(campaign, success_score))

	var back := Button.new()
	back.text = "CAMPAIGN_END_BACK_TO_MENU"
	back.custom_minimum_size = Vector2(380.0, 60.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.add_theme_font_size_override("font_size", 26)
	back.pressed.connect(func() -> void:
		Campaigns.start_free()
		get_tree().change_scene_to_file(MAIN_MENU))
	column.add_child(back)

	center.modulate.a = 0.0
	create_tween().tween_property(center, "modulate:a", 1.0, FADE_IN_S)
	back.grab_focus()


## Message de fin : le même que celui de la radio (notes de la dernière journée) ; "" si la campagne n'en a pas.
func _ending_text() -> String:
	var days := Campaigns.current.days()
	if days.is_empty():
		return ""
	var scores := Campaigns.scores(str(days[-1].id), "")
	var ending := CampaignData.pick_message(Campaigns.current.data.get("ending", []), scores)
	return "" if ending.is_empty() else Campaigns.text_of(ending, "body")


## Détail à défilement : par journée, « Jour n » et sa note, puis ses missions jouées (titre, note, verdict).
func _build_details(campaign: CampaignData, success_score: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(DETAIL_WIDTH, DETAIL_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var days := campaign.days()
	for i in days.size():
		var day: Dictionary = days[i]
		var day_score: Variant = Campaigns.day_scores.get(day.id, null)
		var day_label := _add_label(grid, tr("DAY_TITLE").format({"n": i + 1}), 26, Color.WHITE, false)
		day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_score_cells(grid, day_score, success_score, 26)
		var played := false
		for entry: Dictionary in day.get("missions", []):
			var id := str(entry.mission)
			var result: Dictionary = Campaigns.results.get(id, {})
			if result.is_empty() or result.get("day", "") != day.id:
				continue
			played = true
			var title := _add_label(grid, "    " + Campaigns.text_of(campaign.mission(id), "title", id), 22,
					Color(0.85, 0.87, 0.9), false)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_add_score_cells(grid, float(result.score), success_score, 22)
		if not played:
			var none := _add_label(grid, "    " + tr("CAMPAIGN_END_NO_MISSION"), 22, DIM_COLOR, false)
			none.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_add_label(grid, "", 22, DIM_COLOR, false)
			_add_label(grid, "", 22, DIM_COLOR, false)
	return scroll


## Deux cellules : note sur 20 et verdict (« — » sans note).
func _add_score_cells(grid: GridContainer, score: Variant, success_score: float, font_size: int) -> void:
	if score == null:
		_add_label(grid, "—", font_size, DIM_COLOR, false)
		_add_label(grid, "", font_size, DIM_COLOR, false)
		return
	var passed := float(score) >= success_score
	var color := SUCCESS_COLOR if passed else FAILURE_COLOR
	var value := _add_label(grid, tr("CAMPAIGN_END_SCORE").format({"score": "%.1f" % float(score)}), font_size,
			color, false)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_add_label(grid, tr("RESULT_SUCCESS" if passed else "RESULT_FAILURE"), font_size, color, false)


## Étiquette centrée ; translate : traduction automatique (texte = clé), sinon texte déjà traduit.
func _add_label(parent: Control, text: String, font_size: int, color: Color, translate := true) -> Label:
	var label := Label.new()
	label.text = text
	if not translate:
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
