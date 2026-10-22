class_name AlertsPage
extends VBoxContainer
## Onglet Alertes de la tablette (TabletDisplay) : la tablette est le récepteur des appels prioritaires
## (PriorityCall), comme un téléphone. En haut (~80 %), l'écran de réception : l'appel en cours (expéditeur, objet,
## heure de réception ; le message se lit au poste COMM), sinon « Aucune alerte » ; au-dessus des boutons, le bandeau
## clignotant PRIORITY_CALL_BANNER pendant l'appel ; en bas, les 5 gros boutons du niveau d'alerte de la station
## (Station.set_alert : Normal, Jaune, Orange, Rouge, Tout éteindre = « plus de lumière »), dessinés comme le bouton
## de tir ou BURN (BigRedButton), de la couleur de l'alerte ; le niveau en cours est marqué « ▲ ».
## L'appel prioritaire est créé par le directeur de campagne : il est cherché à chaque image jusqu'à exister, page
## affichée ou non ; à l'arrivée d'un appel, call_started est émis (la tablette passe sur cet onglet).

## Un appel prioritaire arrive (l'écran de réception est à jour).
signal call_started

## Boutons du niveau d'alerte, dans l'ordre de Station.Alert : texte et couleur du capuchon (celle de l'éclairage ;
## noir pour « Tout éteindre »).
const ALERT_KEYS: Array[String] = ["TABLET_ALERT_NONE", "TABLET_ALERT_YELLOW", "TABLET_ALERT_ORANGE",
		"TABLET_ALERT_RED", "TABLET_ALERT_BLACKOUT"]
const ALERT_CAPS: Array[Color] = [Color(0.86, 0.87, 0.88), Color(0.95, 0.78, 0.18), Color(0.95, 0.5, 0.1),
		Color(0.8, 0.07, 0.04), Color(0.1, 0.1, 0.11)]
const ALERT_BUTTON_SIZE := Vector2(80.0, 74.0)
const COLOR_CALL := Color(1.0, 0.62, 0.18)
const BLINK_S := 0.5

## Appel prioritaire suivi (trouvé à la première image où il existe), écran de réception (appel en cours, ou « Aucune
## alerte »), bandeau, étiquettes des boutons de niveau, horloge du clignotement.
var _call: PriorityCall
var _call_idle: Label
var _call_box: VBoxContainer
var _call_from: Label
var _call_subject: Label
var _call_time: Label
var _call_banner: PanelContainer
var _alert_labels: Array[Label] = []
var _shown_alert := -1
var _blink := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var screen := PanelContainer.new()
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0.02, 0.035, 0.03), ScreenPalette.FRAME, 1, 6, 16.0))
	add_child(screen)
	var center := CenterContainer.new()
	screen.add_child(center)
	_call_idle = _make_label("TABLET_ALERT_IDLE", 26, ScreenPalette.DIM)
	center.add_child(_call_idle)
	_call_box = VBoxContainer.new()
	_call_box.add_theme_constant_override("separation", 10)
	center.add_child(_call_box)
	_call_box.add_child(_make_label("TABLET_CALL_TITLE", 34, COLOR_CALL))
	_call_from = _make_label("", 24, ScreenPalette.TEXT, false)
	_call_subject = _make_label("", 24, ScreenPalette.TEXT, false)
	_call_time = _make_label("", 22, ScreenPalette.DIM, false)
	for label in [_call_from, _call_subject, _call_time]:
		_call_box.add_child(label)
	# Bandeau de l'appel, au-dessus des boutons : orange sur fond sombre, clignotant.
	_call_banner = PanelContainer.new()
	_call_banner.add_theme_stylebox_override("panel", UiKit.flat_box(Color(0.08, 0.04, 0.02), COLOR_CALL, 2, 4, 6.0))
	var banner_text := _make_label("PRIORITY_CALL_BANNER", 17, COLOR_CALL)
	# Texte coupé plutôt que page élargie (traductions longues).
	banner_text.clip_text = true
	banner_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_call_banner.add_child(banner_text)
	add_child(_call_banner)
	# Boutons du niveau d'alerte (Station.Alert), répartis sur la largeur.
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	add_child(buttons)
	for level in ALERT_KEYS.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = 1.0
		cell.add_theme_constant_override("separation", 2)
		buttons.add_child(cell)
		var button := BigRedButton.new()
		button.cap_color = ALERT_CAPS[level]
		button.custom_minimum_size = ALERT_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void:
			var station := _station()
			if station:
				station.set_alert(level as Station.Alert))
		cell.add_child(button)
		# Texte traduit dès le départ (la clé brute, plus large, élargirait la page pour de bon).
		var label := _make_label(tr(ALERT_KEYS[level]), 18, ScreenPalette.DIM, false)
		cell.add_child(label)
		_alert_labels.append(label)
	_show_call({})


## Appel prioritaire (suivi dès qu'il existe), clignotement du bandeau et niveau d'alerte en cours (étiquette du
## bouton allumée) quand la page est affichée.
func _process(delta: float) -> void:
	if _call == null:
		_call = get_tree().get_first_node_in_group(PriorityCall.GROUP) as PriorityCall
		if _call:
			_call.call_started.connect(func(call_info: Dictionary) -> void:
				_show_call(call_info)
				call_started.emit())
			_call.call_stopped.connect(func() -> void: _show_call({}))
			_show_call(_call.info)
	if not visible:
		return
	_blink += delta
	_call_banner.modulate.a = 1.0 if fmod(_blink, BLINK_S * 2.0) < BLINK_S else 0.3
	var station := _station()
	var current := station.get_alert() if station else Station.Alert.NONE
	if current == _shown_alert:
		return
	_shown_alert = current
	for level in _alert_labels.size():
		var label := _alert_labels[level]
		var active := level == current
		label.add_theme_color_override("font_color", ScreenPalette.TEXT if active else ScreenPalette.DIM)
		label.text = ("▲ %s" if active else "%s") % tr(ALERT_KEYS[level])


## Écran de réception : l'appel call_info (from, subject, received_unix), ou « Aucune alerte » s'il est vide.
func _show_call(call_info: Dictionary) -> void:
	var active := not call_info.is_empty()
	_call_idle.visible = not active
	_call_box.visible = active
	_call_banner.visible = active
	if not active:
		return
	_call_from.text = tr("TABLET_CALL_FROM").format({"from": call_info.get("from", "")})
	_call_subject.text = tr("TABLET_CALL_SUBJECT").format({"subject": call_info.get("subject", "")})
	_call_time.text = tr("TABLET_CALL_TIME").format({"time": Time.get_datetime_string_from_unix_time(
			int(call_info.get("received_unix", 0.0))).substr(11, 5)})


func _station() -> Station:
	return get_tree().get_first_node_in_group(Station.GROUP) as Station


## Étiquette centrée (texte : clé de langue, ou composé si translate est faux).
static func _make_label(text: String, font_size: int, color: Color, translate := true) -> Label:
	return UiKit.label(text, font_size, color, translate, HORIZONTAL_ALIGNMENT_CENTER)
