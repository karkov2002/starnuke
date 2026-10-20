extends Control
## Écran de démarrage (scène principale scenes/ui/main_menu.tscn) : titre provisoire et boutons à droite, en pages :
## - accueil : « Commencer la partie » (page des modes), « Paramètres » (écran scenes/ui/settings_menu.tscn
##   par-dessus), « Quitter » ;
## - modes de jeu : « Démarrer une nouvelle campagne » (page des campagnes), « Continuer la campagne en cours »
##   (cliquable seulement si une campagne est en cours, Campaigns.has_saved : reprend la sauvegarde du dernier coucher), « Mode libre »
##   (le jeu tel quel), « Retour » ;
## - campagnes : sélecteur déroulant des campagnes du dossier campaign/ (scripts/campaigns.gd ; l'officielle en premier
##   et en bleu, les autres en blanc), « Lancer la campagne » (pour le moment, la partie normale), « Retour ».
## Échap revient à la page précédente. Le mode choisi est retenu par Campaigns (mode, current_id). À gauche,
## la station vue de l'extérieur au-dessus de la Terre qui défile. Tous les textes sont des clés des fichiers de
## langue (locale/strings.csv), traduites automatiquement.
##
## Décor : la scène du jeu elle-même (Terre, nuages, atmosphère, station), chargée en tâche de fond dès l'ouverture
## du menu puis affichée en fondu, sans son interface ni le tir (Hud, NukeReport, NukeLauncher, PilotConsole, tablette retirés),
## observateur désactivé, filmée par une caméra extérieure (BACKDROP_CAMERA_*), en temps réel (BACKDROP_TIME_SCALE).
## Le même chargement sert au lancement de la partie : le choix d'un mode n'attend plus que la fin du chargement
## s'il n'est pas terminé.
## Écran de chargement dès le démarrage du jeu : « Chargement en cours… » (points animés, pourcentage) sur le fond noir
## jusqu'à ce que le décor soit en place ; le décor et les boutons apparaissent ensuite en fondu.

const GAME_SCENE := "res://scenes/orbit_view.tscn"
const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const BUTTON_SIZE := Vector2(380.0, 60.0)
## Choix de la campagne : couleur de la campagne officielle, lignes visibles avant défilement.
const OFFICIAL_COLOR := Color(0.45, 0.72, 1.0)
## Campagne avec des erreurs (grisée, ne se lance pas).
const INVALID_COLOR := Color(0.5, 0.5, 0.5)
const CAMPAIGN_LIST_ROWS := 8
## Caméra du décor (repère de la scène du jeu : station à l'origine, avant −Z, Terre en bas) : position, point visé,
## décalage horizontal (positif : station et Terre à gauche de l'écran), champ.
const BACKDROP_CAMERA_POSITION := Vector3(58.0, 22.0, 45.0)
const BACKDROP_CAMERA_TARGET := Vector3(0.0, -6.0, 0.0)
const BACKDROP_CAMERA_H_OFFSET := 0.38
const BACKDROP_CAMERA_FOV := 55.0
const BACKDROP_TIME_SCALE := 1.0
const BACKDROP_FADE_S := 2.0
## Nœuds de la scène du jeu retirés du décor (interface, tir).
const BACKDROP_REMOVED: Array[String] = ["Hud", "NukeReport", "NukeLauncher", "PauseMenu", "PilotConsole",
		"Observer/Camera/Tablet"]

var _menu: Control
var _start_button: Button
var _main_page: VBoxContainer
var _mode_page: VBoxContainer
var _campaign_page: VBoxContainer
var _continue_button: Button
var _page: VBoxContainer
## Choix de la campagne : campagnes listées (Campaigns.list), sélecteur, liste déroulante, campagne choisie.
var _campaigns: Array[Dictionary] = []
var _campaign_select: Button
var _launch_button: Button
var _campaign_list: ItemList
var _campaign_index := 0
var _veil: ColorRect
var _loading: Label
var _loading_dots := 0
var _game_scene: PackedScene
var _load_failed := false
## Décor en place (ou chargement en échec) : le menu est utilisable.
var _ready_to_play := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Voile noir : fond tant que le décor charge, puis s'efface en fondu.
	_veil = ColorRect.new()
	_veil.color = Color.BLACK
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_veil)
	_load_failed = ResourceLoader.load_threaded_request(GAME_SCENE) != OK

	# Boutons dans la moitié droite de l'écran.
	_menu = CenterContainer.new()
	_menu.anchor_left = 0.5
	_menu.anchor_right = 1.0
	_menu.anchor_bottom = 1.0
	add_child(_menu)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_menu.add_child(column)

	# Titre lumineux : halo et couleur de corps noir qui va et vient du noir au blanc (scripts/ui/title_glow.gd).
	var title := TitleGlow.new()
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8.0
	column.add_child(spacer)

	# Pages du menu (une seule visible) : accueil, modes de jeu, choix de la campagne.
	_main_page = _add_page(column)
	_start_button = _add_button(_main_page, "MENU_START", func() -> void: _show_page(_mode_page))
	_add_button(_main_page, "MENU_SETTINGS", _on_settings)
	_add_button(_main_page, "MENU_QUIT", func() -> void: get_tree().quit())
	_mode_page = _add_page(column)
	_add_button(_mode_page, "MENU_NEW_CAMPAIGN", _open_campaigns)
	# Reprend la campagne sauvegardée au dernier coucher (grisé sans sauvegarde : Campaigns.has_saved).
	_continue_button = _add_button(_mode_page, "MENU_CONTINUE_CAMPAIGN", func() -> void:
		if Campaigns.continue_saved():
			_on_start())
	_add_button(_mode_page, "MENU_FREE_MODE", func() -> void:
		Campaigns.start_free()
		_on_start())
	_add_button(_mode_page, "MENU_BACK", func() -> void: _show_page(_main_page))
	_campaign_page = _add_page(column)
	_show_page(_main_page)

	# Écran de chargement : le menu reste caché tant que le décor n'est pas en place.
	_menu.visible = false
	_loading = Label.new()
	_loading.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading.add_theme_font_size_override("font_size", 32)
	_loading.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_loading)
	_show_loading(0.0)
	if _load_failed:
		_show_menu()


func _process(_delta: float) -> void:
	if _game_scene or _load_failed:
		set_process(false)
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_game_scene = ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
		_open_menu()
	elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_load_failed = true
		_show_menu()
	else:
		_show_loading(float(progress[0]) if not progress.is_empty() else 0.0)


## Texte de chargement (part chargée de 0 à 1), points animés d'une image à l'autre.
func _show_loading(share: float) -> void:
	_loading_dots = (_loading_dots + 1) % 30
	_loading.text = tr("MENU_LOADING").format({"dots": ".".repeat(1 + floori(_loading_dots / 10.0)),
			"percent": roundi(100.0 * share)})


## Scène chargée : 100 % affiché, puis mise en place du décor (sur le fil principal, l'écran se fige un instant) et
## apparition du menu.
func _open_menu() -> void:
	_loading.text = tr("MENU_LOADING").format({"dots": "...", "percent": 100})
	# Deux images : le texte final est affiché avant la mise en place, qui fige l'écran.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_backdrop()
	_show_menu()


func _show_menu() -> void:
	_ready_to_play = true
	_loading.visible = false
	_menu.visible = true
	_menu.modulate.a = 0.0
	create_tween().tween_property(_menu, "modulate:a", 1.0, 0.5)
	_show_page(_main_page)


## Décor : scène du jeu sans interface ni tir, caméra extérieure, temps accéléré, apparition en fondu.
func _build_backdrop() -> void:
	var backdrop := _game_scene.instantiate()
	for removed in BACKDROP_REMOVED:
		var node := backdrop.get_node_or_null(removed)
		if node:
			node.get_parent().remove_child(node)
			node.free()
	var observer := backdrop.get_node_or_null("Observer")
	if observer:
		observer.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.name = "MenuCamera"
	camera.fov = BACKDROP_CAMERA_FOV
	camera.far = 3000.0
	camera.h_offset = BACKDROP_CAMERA_H_OFFSET * 2.0 * tan(deg_to_rad(BACKDROP_CAMERA_FOV) * 0.5) \
			* BACKDROP_CAMERA_POSITION.distance_to(BACKDROP_CAMERA_TARGET)
	backdrop.add_child(camera)
	add_child(backdrop)
	move_child(backdrop, 0)
	camera.look_at_from_position(BACKDROP_CAMERA_POSITION, BACKDROP_CAMERA_TARGET)
	camera.make_current()
	var orbit := backdrop.get_node_or_null("Orbit")
	if orbit:
		orbit.set("time_scale", BACKDROP_TIME_SCALE)
	create_tween().tween_property(_veil, "color:a", 0.0, BACKDROP_FADE_S)


func _add_page(parent: Control) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	page.visible = false
	parent.add_child(page)
	return page


## Affiche une page du menu (les autres masquées) et donne le focus à son premier bouton actif.
func _show_page(page: VBoxContainer) -> void:
	for other: VBoxContainer in [_main_page, _mode_page, _campaign_page]:
		other.visible = other == page
	_page = page
	_continue_button.disabled = not Campaigns.has_saved()
	for child in page.get_children():
		var button := child as Button
		if button and not button.disabled:
			button.grab_focus.call_deferred()
			break


## Échap : page précédente.
func _unhandled_input(event: InputEvent) -> void:
	if not _menu.visible or not event.is_action_pressed(&"ui_cancel"):
		return
	if _page == _campaign_page:
		_show_page(_mode_page)
	elif _page == _mode_page:
		_show_page(_main_page)
	else:
		return
	get_viewport().set_input_as_handled()


## Choix de la campagne (il peut y en avoir des dizaines) : sélecteur déroulant (bouton qui affiche la campagne choisie
## et ouvre une liste à défilement), relu à chaque ouverture (une campagne ajoutée pendant que le jeu tourne apparaît) ;
## campagne officielle en premier et en bleu (OFFICIAL_COLOR), les autres en blanc ; description en infobulle.
## « Lancer la campagne » lance celle choisie.
func _open_campaigns() -> void:
	for child in _campaign_page.get_children():
		_campaign_page.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "MENU_CHOOSE_CAMPAIGN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	_campaign_page.add_child(title)
	_campaigns = Campaigns.list()
	if _campaigns.is_empty():
		var none := Label.new()
		none.text = "MENU_NO_CAMPAIGN"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_campaign_page.add_child(none)
	else:
		_campaign_select = _add_button(_campaign_page, "", _open_campaign_list)
		_campaign_select.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_campaign_select.icon = get_theme_icon(&"arrow", &"OptionButton")
		_campaign_select.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_campaign_list = _build_campaign_list()
		_launch_button = _add_button(_campaign_page, "MENU_LAUNCH_CAMPAIGN", func() -> void:
			if Campaigns.start_campaign(_campaigns[_campaign_index].id):
				_on_start())
		_select_campaign(0)
	_add_button(_campaign_page, "MENU_BACK", func() -> void: _show_page(_mode_page))
	_show_page(_campaign_page)


## Liste déroulante des campagnes (fenêtre surgissante sous le sélecteur, défilement au-delà de CAMPAIGN_LIST_ROWS).
func _build_campaign_list() -> ItemList:
	var popup := PopupPanel.new()
	_campaign_page.add_child(popup)
	var list := ItemList.new()
	list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	list.add_theme_font_size_override("font_size", 24)
	for campaign: Dictionary in _campaigns:
		var index := list.add_item(Campaigns.text_of(campaign.data, "name", campaign.id))
		list.set_item_custom_fg_color(index, _campaign_color(campaign))
		list.set_item_tooltip(index, _campaign_tooltip(campaign))
	popup.add_child(list)
	list.item_activated.connect(func(index: int) -> void:
		_select_campaign(index)
		popup.hide()
		_campaign_select.grab_focus())
	list.item_clicked.connect(func(index: int, _at: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_select_campaign(index)
			popup.hide()
			_campaign_select.grab_focus())
	return list


func _open_campaign_list() -> void:
	var popup := _campaign_list.get_parent() as PopupPanel
	var row := _campaign_list.get_theme_font_size(&"font_size") * 1.6
	var rows := mini(_campaigns.size(), CAMPAIGN_LIST_ROWS)
	var rect := _campaign_select.get_global_rect()
	popup.popup(Rect2i(Vector2i(rect.position + Vector2(0.0, rect.size.y)),
			Vector2i(int(rect.size.x), int(rows * row + 16.0))))
	_campaign_list.select(_campaign_index)
	_campaign_list.ensure_current_is_visible()
	_campaign_list.grab_focus()


func _select_campaign(index: int) -> void:
	_campaign_index = index
	var campaign: Dictionary = _campaigns[index]
	_campaign_select.text = Campaigns.text_of(campaign.data, "name", campaign.id)
	_campaign_select.tooltip_text = _campaign_tooltip(campaign)
	_launch_button.disabled = not (campaign.campaign as CampaignData).is_valid()
	var color := _campaign_color(campaign)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_focus_color", &"font_pressed_color"]:
		_campaign_select.add_theme_color_override(state, color)


## Couleur d'une campagne dans le sélecteur : bleu pour l'officielle, blanc pour les autres, gris si elle a des
## erreurs (elle ne se lance pas).
static func _campaign_color(campaign: Dictionary) -> Color:
	if not (campaign.campaign as CampaignData).is_valid():
		return INVALID_COLOR
	return OFFICIAL_COLOR if campaign.id == Campaigns.OFFICIAL else Color.WHITE


## Infobulle : description, ou nombre d'erreurs (détail : tools/check_campaign.gd, ou la console du jeu).
func _campaign_tooltip(campaign: Dictionary) -> String:
	var errors := (campaign.campaign as CampaignData).errors.size()
	if errors > 0:
		return tr("MENU_CAMPAIGN_INVALID").format({"count": errors})
	return Campaigns.text_of(campaign.data, "description")


func _add_button(parent: Control, key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.custom_minimum_size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 26)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## La scène du jeu est déjà chargée (le menu n'apparaît qu'ensuite) : le menu laisse place au dernier message de
## chargement pendant la mise en place de la scène (_ready des nœuds), qui se fait sur le fil principal, puis la scène
## remplace le menu.
func _on_start() -> void:
	if not _ready_to_play:
		return
	if _load_failed or _game_scene == null:
		get_tree().change_scene_to_file(GAME_SCENE)
		return
	_menu.visible = false
	_loading.text = tr("MENU_LOADING").format({"dots": "...", "percent": 100})
	_loading.visible = true
	# Deux images : le texte est affiché avant la mise en place de la scène, qui fige l'écran un instant.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_packed(_game_scene)


func _on_settings() -> void:
	var settings := SETTINGS_SCENE.instantiate()
	_menu.visible = false
	settings.closed.connect(func() -> void:
		settings.queue_free()
		_menu.visible = true
		_show_page(_main_page))
	add_child(settings)
