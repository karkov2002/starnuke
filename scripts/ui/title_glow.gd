class_name TitleGlow
extends TextureRect
## Titre lumineux de l'écran de démarrage (scripts/ui/main_menu.gd) : le texte est rendu en blanc dans un SubViewport
## transparent, puis affiché avec un halo (shaders/title_glow.gdshader). Sa couleur suit lentement, en allant et
## venant, celle d'un corps noir chauffé : noir (froid), rouge sombre, rouge, orange, jaune, jusqu'au blanc
## (~6 600 K), puis retour. La luminosité suit la température (un corps noir froid ne rayonne pas de lumière
## visible) : au plus froid, le titre et son halo s'éteignent presque.

## Texte (clé de langue) et taille de police.
@export var text := "GAME_TITLE"
@export var font_size := 112
## Durée d'un aller-retour noir → blanc → noir (s).
@export var period_s := 18.0
## Températures extrêmes (K).
@export var temperature_range := Vector2(700.0, 6600.0)
## Marge autour du texte pour le halo (pixels).
@export var glow_margin := 40

var _label: Label
var _viewport: SubViewport
var _time := 0.0


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.position = Vector2(glow_margin, glow_margin)
	_viewport.add_child(_label)
	_label.resized.connect(_fit)
	_fit()
	texture = _viewport.get_texture()
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/title_glow.gdshader")
	material = shader_material
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_color()


func _process(delta: float) -> void:
	_time += delta
	_update_color()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label:
		_fit.call_deferred()


func _fit() -> void:
	var text_size := _label.get_combined_minimum_size()
	_viewport.size = Vector2i(text_size) + Vector2i.ONE * glow_margin * 2
	custom_minimum_size = Vector2(_viewport.size)


func _update_color() -> void:
	var heat := 0.5 - 0.5 * cos(TAU * _time / period_s)
	var kelvin := lerpf(temperature_range.x, temperature_range.y, heat)
	var color := blackbody(kelvin)
	# Luminosité visible : nulle au plus froid, vite pleine (le rouge et l'orange rougeoient, comme du métal chauffé ;
	# trop sombres, ils tourneraient au brun), puis la couleur seule blanchit.
	var brightness := pow(clampf(inverse_lerp(temperature_range.x, temperature_range.y, kelvin) * 3.0, 0.0, 1.0), 0.8)
	color = color * lerpf(0.04, 1.0, brightness)
	color.a = 1.0
	(material as ShaderMaterial).set_shader_parameter("tint", color)
	# Halo jamais éteint (lueur minimale de braise dans le shader, halo_floor) : le titre reste lisible au plus froid.
	(material as ShaderMaterial).set_shader_parameter("glow_strength", lerpf(0.9, 1.4, brightness))


## Couleur d'un corps noir à la température kelvin (approximation de Tanner Helland, 1 000 à 40 000 K).
static func blackbody(kelvin: float) -> Color:
	var t := clampf(kelvin, 1000.0, 40000.0) / 100.0
	var r := 1.0 if t <= 66.0 else clampf(329.698727446 * pow(t - 60.0, -0.1332047592) / 255.0, 0.0, 1.0)
	var g := clampf((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0) if t <= 66.0 \
			else clampf(288.1221695283 * pow(t - 60.0, -0.0755148492) / 255.0, 0.0, 1.0)
	var b := 1.0 if t >= 66.0 else (0.0 if t <= 19.0 \
			else clampf((138.5177312231 * log(t - 10.0) - 305.0447927307) / 255.0, 0.0, 1.0))
	return Color(r, g, b)
