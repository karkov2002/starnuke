class_name WakeUp
extends CanvasLayer
## Réveil et endormissement de l'observateur (nœud WakeUp de scenes/orbit_view.tscn, groupe GROUP), règle de jeu :
## - au lancement d'une partie (mode libre comme campagne), réveil : écran noir, titre (campagne : « Jour n » ; mode
##   libre : aucun ; en campagne, dessous, date, heure UTC et point survolé de la journée), puis ouverture des paupières (shaders/eyelids.gdshader, comme la séquence de mort mais à
##   l'envers) : elles s'entrouvrent, clignent une fois puis s'ouvrent (WAKE_STEPS) ; la vue, d'abord floue et
##   sombre sur les bords, devient nette. Pas au décor de l'écran de démarrage ni aux bancs de mesure (la scène du jeu
##   n'y est pas la scène courante) ;
## - fall_asleep (CampaignDirector, couchette) : fondu au noir ; puis play(titre, ligne de la journée) au réveil.
## Pendant le noir et l'ouverture, la souris est bloquée ; le voile est masqué ensuite (sinon il garderait les clics,
## dont le clic droit qui tourne la tête).

signal awake

const GROUP := &"wake_up"
const EYELIDS_SHADER := preload("res://shaders/eyelids.gdshader")
## Fondu au noir (s), titre affiché (s).
const FADE_S := 1.5
const TITLE_S := 1.8
## Titre avec la ligne de date, d'heure et de position (plus longue à lire).
const TITLE_WITH_HEADING_S := 3.2
## Ouverture des yeux : (fermeture visée de 1 à 0, durée en s) — entrouverts, un clignement, ouverts.
const WAKE_STEPS: Array[Vector2] = [Vector2(0.55, 0.6), Vector2(0.9, 0.2), Vector2(0.0, 0.9)]

var _veil: ColorRect
var _title_box: CenterContainer
var _title: Label
var _subtitle: Label
var _eyelids_rect: ColorRect
var _eyelids: ShaderMaterial
var _busy := false


func _ready() -> void:
	add_to_group(GROUP)
	layer = 50
	_build()
	if owner != null and owner == get_tree().current_scene:
		# Noir dès la première image (pas d'éclair de la scène avant le réveil).
		_veil.visible = true
		_veil.color.a = 1.0
		_play_start.call_deferred()


## Réveil ou endormissement en cours.
func is_busy() -> bool:
	return _busy


## Fondu au noir (endormissement).
func fall_asleep() -> void:
	_busy = true
	_veil.visible = true
	await create_tween().tween_property(_veil, "color:a", 1.0, FADE_S).finished


## Réveil : titre sur le noir (s'il y en a un) et sa ligne de dessous (date, heure, point survolé), puis ouverture
## des paupières.
func play(title: String, subtitle := "") -> void:
	_busy = true
	_veil.visible = true
	_veil.color.a = 1.0
	if not title.is_empty():
		_title.text = title
		_subtitle.text = subtitle
		_subtitle.visible = not subtitle.is_empty()
		await create_tween().tween_property(_title_box, "modulate:a", 1.0, 0.5).finished
		await get_tree().create_timer(TITLE_S if subtitle.is_empty() else TITLE_WITH_HEADING_S).timeout
		await create_tween().tween_property(_title_box, "modulate:a", 0.0, 0.6).finished
	# Paupières closes (noir complet) à la place du voile, puis ouverture.
	_eyelids.set_shader_parameter("closure", 1.0)
	_eyelids_rect.visible = true
	_veil.color.a = 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var from := 1.0
	for step: Vector2 in WAKE_STEPS:
		tween.tween_method(func(c: float) -> void: _eyelids.set_shader_parameter("closure", c), from, step.x, step.y)
		from = step.x
	await tween.finished
	_eyelids_rect.visible = false
	_veil.visible = false
	_busy = false
	awake.emit()


## Réveil de lancement : en campagne, « Jour n » et la ligne de la journée (CampaignDirector.day_heading) ; aucun
## titre en mode libre. Une image plus tard : la journée est alors en place (départ appliqué, différé lui aussi).
func _play_start() -> void:
	await get_tree().process_frame
	var director := get_tree().get_first_node_in_group(CampaignDirector.GROUP) as CampaignDirector
	if director and director.is_active():
		play(tr("DAY_TITLE").format({"n": Campaigns.day_index + 1}), director.day_heading())
	else:
		play("")


func _build() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(0, 0, 0, 0)
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.visible = false
	add_child(_veil)
	# Paupières : visibles seulement pendant l'ouverture (elles lisent l'image de l'écran).
	_eyelids = ShaderMaterial.new()
	_eyelids.shader = EYELIDS_SHADER
	_eyelids_rect = ColorRect.new()
	_eyelids_rect.material = _eyelids
	_eyelids_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_eyelids_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_eyelids_rect.visible = false
	add_child(_eyelids_rect)
	# Titre (« Jour n ») et, dessous, date, heure et point survolé, centrés ; ils apparaissent et s'effacent ensemble.
	_title_box = CenterContainer.new()
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_box.modulate.a = 0.0
	_title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title_box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_title_box.add_child(column)
	_title = _add_title_label(column, 56, Color(0.9, 0.92, 0.95))
	_subtitle = _add_title_label(column, 26, Color(0.62, 0.66, 0.72))


static func _add_title_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := UiKit.label("", font_size, color, false, HORIZONTAL_ALIGNMENT_CENTER)
	parent.add_child(label)
	return label
