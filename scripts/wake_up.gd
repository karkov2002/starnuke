class_name WakeUp
extends CanvasLayer
## Réveil et endormissement de l'observateur (nœud WakeUp de scenes/orbit_view.tscn, groupe GROUP), règle de jeu :
## - au lancement d'une partie (mode libre comme campagne), réveil : écran noir, titre (campagne : « Jour n » ; mode
##   libre : aucun), puis ouverture des paupières (shaders/eyelids.gdshader, comme la séquence de mort mais à
##   l'envers) : elles s'entrouvrent, clignent une fois puis s'ouvrent (WAKE_STEPS) ; la vue, d'abord floue et
##   sombre sur les bords, devient nette. Pas au décor de l'écran de démarrage ni aux bancs de mesure (la scène du jeu
##   n'y est pas la scène courante) ;
## - fall_asleep (CampaignDirector, couchette) : fondu au noir ; puis play(titre) au réveil.
## Pendant le noir et l'ouverture, la souris est bloquée ; le voile est masqué ensuite (sinon il garderait les clics,
## dont le clic droit qui tourne la tête).

signal awake

const GROUP := &"wake_up"
const EYELIDS_SHADER := preload("res://shaders/eyelids.gdshader")
## Fondu au noir (s), titre affiché (s).
const FADE_S := 1.5
const TITLE_S := 1.8
## Ouverture des yeux : (fermeture visée de 1 à 0, durée en s) — entrouverts, un clignement, ouverts.
const WAKE_STEPS: Array[Vector2] = [Vector2(0.55, 0.6), Vector2(0.9, 0.2), Vector2(0.0, 0.9)]

var _veil: ColorRect
var _title: Label
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
		play.call_deferred(_start_title())


## Réveil ou endormissement en cours.
func is_busy() -> bool:
	return _busy


## Fondu au noir (endormissement).
func fall_asleep() -> void:
	_busy = true
	_veil.visible = true
	await create_tween().tween_property(_veil, "color:a", 1.0, FADE_S).finished


## Réveil : titre sur le noir (s'il y en a un), puis ouverture des paupières.
func play(title: String) -> void:
	_busy = true
	_veil.visible = true
	_veil.color.a = 1.0
	if not title.is_empty():
		_title.text = title
		await create_tween().tween_property(_title, "modulate:a", 1.0, 0.5).finished
		await get_tree().create_timer(TITLE_S).timeout
		await create_tween().tween_property(_title, "modulate:a", 0.0, 0.6).finished
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


## Titre du réveil de lancement : « Jour n » en campagne, aucun en mode libre.
func _start_title() -> String:
	if Campaigns.mode == Campaigns.Mode.CAMPAIGN and Campaigns.current != null:
		return tr("DAY_TITLE").format({"n": Campaigns.day_index + 1})
	return ""


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
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	_title.modulate.a = 0.0
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_title)
