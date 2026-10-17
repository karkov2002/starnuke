extends Node
## Paramètres du joueur (autoload GameSettings) : affichage (mode, résolution) et langue. Sauvés dans
## user://settings.cfg à chaque changement et réappliqués au lancement suivant.
##
## Affichage :
## - fenêtré : la résolution est la taille de la fenêtre (centrée sur l'écran) ;
## - plein écran : la fenêtre couvre tout l'écran, à sa résolution native (Godot ne change pas le mode vidéo de
##   l'écran). La résolution choisie règle celle du rendu 3D (Viewport.scaling_3d_scale = hauteur choisie / hauteur
##   de l'écran) ; l'interface reste nette, à la résolution native.
## Résolutions proposées (available_resolutions) : formats 16:9, 16:10, 21:9 et 32:9 courants, jusqu'à la taille de
## l'écran, plus celle de l'écran (« native ») ; aucune limite propre au jeu (Godot rend jusqu'à 16384 px de côté).
## Les écrans ultra-larges sont gérés par l'étirement « expand » du projet : la vue 3D garde son champ vertical et
## s'élargit, l'interface s'étend sur toute la largeur.
##
## Luminosité (brightness, 0,5 à 1,5) : facteur du multiplicateur d'exposition des attributs de caméra partagés
## (materials/camera_attributes.tres, CameraAttributesPractical.exposure_multiplier), appliqué à toutes les vues 3D
## (menu et jeu). L'exposition elle-même est calculée par le nœud Exposure de orbit_view.tscn (ExposureControl :
## jour / nuit au point regardé, soleil dans le champ, éblouissement du flash), qui multiplie par ce réglage ;
## _apply_brightness ne sert qu'en l'absence de ce nœud.
##
## Langue : TranslationServer, fichiers de langue locale/strings.csv (textes du jeu) et locale/countries.csv (noms
## de pays) ; anglais par défaut.

signal changed

enum WindowMode { WINDOWED, FULLSCREEN }

const PATH := "user://settings.cfg"
const LOCALES: Array[String] = ["en", "fr", "es", "de", "it"]
## Nom de chaque langue dans sa propre langue (menu « Langue » : jamais traduit).
const LOCALE_NAMES := {"en": "English", "fr": "Français", "es": "Español", "de": "Deutsch", "it": "Italiano"}
const DEFAULT_LOCALE := "en"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3200, 1800), Vector2i(3840, 2160), Vector2i(5120, 2880), Vector2i(7680, 4320), # 16:9
	Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050), Vector2i(1920, 1200), Vector2i(2560, 1600),
	Vector2i(3840, 2400), # 16:10
	Vector2i(2560, 1080), Vector2i(3440, 1440), Vector2i(3840, 1600), Vector2i(5120, 2160), # 21:9
	Vector2i(3840, 1080), Vector2i(5120, 1440), Vector2i(7680, 2160), # 32:9
]
## Échelle minimale du rendu 3D en plein écran.
const MIN_3D_SCALE := 0.25
const CAMERA_ATTRIBUTES := "res://materials/camera_attributes.tres"
const BRIGHTNESS_RANGE := Vector2(0.25, 1.5)
const INTERIOR_LIGHT_RANGE := Vector2(0.1, 1.5)

var window_mode := WindowMode.FULLSCREEN
## Résolution choisie ; Vector2i.ZERO : celle de l'écran.
var resolution := Vector2i.ZERO
var locale := DEFAULT_LOCALE
## Multiplicateur de luminosité (1 = exposition automatique seule).
var brightness := 1.0
## Puissance de l'éclairage intérieur de la station (1 = réglage du modèle).
var interior_light := 1.0


func _ready() -> void:
	_load()
	TranslationServer.set_locale(locale)
	apply_display()
	_apply_brightness()


func set_brightness(value: float) -> void:
	brightness = clampf(value, BRIGHTNESS_RANGE.x, BRIGHTNESS_RANGE.y)
	_apply_brightness()
	_save()


## Puissance des lampes de la station (Station : énergie des lumières Lum_* × ce facteur), appliquée via changed.
func set_interior_light(value: float) -> void:
	interior_light = clampf(value, INTERIOR_LIGHT_RANGE.x, INTERIOR_LIGHT_RANGE.y)
	_save()
	changed.emit()


## Rien à écrire : le nœud Exposure (ExposureControl) lit brightness à chaque image et impose la sensibilité de
## l'exposition. (CameraAttributes.exposure_multiplier n'agit pas sur le rendu dans ce build, voir ExposureControl.)
func _apply_brightness() -> void:
	pass


func set_window_mode(mode: WindowMode) -> void:
	window_mode = mode
	apply_display()
	_save()


func set_resolution(value: Vector2i) -> void:
	resolution = Vector2i.ZERO if value == screen_size() else value
	apply_display()
	_save()


func set_locale(value: String) -> void:
	locale = value if value in LOCALES else DEFAULT_LOCALE
	TranslationServer.set_locale(locale)
	_save()
	changed.emit()


## Taille de l'écran où se trouve la fenêtre.
func screen_size() -> Vector2i:
	return DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())


## Résolutions proposées : celles de RESOLUTIONS qui tiennent dans l'écran, plus celle de l'écran ; par nombre de
## pixels croissant.
func available_resolutions() -> Array[Vector2i]:
	var screen := screen_size()
	var result: Array[Vector2i] = []
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			result.append(r)
	if not screen in result:
		result.append(screen)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * a.y < b.x * b.y if a.x * a.y != b.x * b.y else a.x < b.x)
	return result


## Résolution appliquée : la résolution choisie si l'écran la permet, sinon celle de l'écran.
func effective_resolution() -> Vector2i:
	return resolution if resolution in available_resolutions() else screen_size()


## Le jeu peut-il changer sa fenêtre ? Non quand il est intégré à l'éditeur (onglet « Jeu », lancé avec --wid et
## --resolution) : l'éditeur impose la taille et le mode de la fenêtre ; les choix sont alors seulement sauvés, pour le
## prochain lancement hors de l'éditeur (ou avec l'intégration désactivée).
func can_change_display() -> bool:
	return not Engine.is_embedded_in_editor()


func apply_display() -> void:
	if not can_change_display():
		changed.emit()
		return
	var screen := screen_size()
	var target := effective_resolution()
	var root := get_tree().root
	if window_mode == WindowMode.FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		root.scaling_3d_scale = clampf(float(target.y) / float(screen.y), MIN_3D_SCALE, 1.0)
	else:
		root.scaling_3d_scale = 1.0
		# Une fenêtre qui ne tient pas dans la zone utile de l'écran (barre des tâches, barre de titre) : maximisée.
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		# Bordure et barre de titre : mesurées en fenêtré, estimées sinon (Windows 11 : ~16 × 39 px à 100 %).
		var decorations := (DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()) \
				.max(Vector2i(16, 39))
		if target.x + decorations.x > usable.size.x or target.y + decorations.y > usable.size.y:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		else:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(target)
			@warning_ignore("integer_division")
			DisplayServer.window_set_position(usable.position + (usable.size - target - decorations) / 2)
	changed.emit()


## « 5120 × 1440 (32:9) » ; « native » si c'est la taille de l'écran.
func describe_resolution(r: Vector2i) -> String:
	var text := "%d × %d  (%s)" % [r.x, r.y, aspect_label(r)]
	if r == screen_size():
		text += "  · " + tr("VIDEO_NATIVE")
	return text


## Format d'image usuel (16:9, 21:9…) le plus proche, sinon le rapport réduit.
static func aspect_label(r: Vector2i) -> String:
	var ratio := float(r.x) / float(r.y)
	for known: Array in [[16, 9], [16, 10], [21, 9], [32, 9], [4, 3], [5, 4]]:
		# Tolérance : les écrans « 21:9 » vont de 2,33 (2560 × 1080 : 2,37) à 2,4 (3840 × 1600).
		if absf(ratio - float(known[0]) / float(known[1])) < 0.075:
			return "%d:%d" % [known[0], known[1]]
	var g := _gcd(r.x, r.y)
	@warning_ignore("integer_division")
	return "%d:%d" % [r.x / g, r.y / g]


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	window_mode = WindowMode.WINDOWED if config.get_value("video", "window_mode", "fullscreen") == "windowed" \
			else WindowMode.FULLSCREEN
	resolution = config.get_value("video", "resolution", Vector2i.ZERO)
	brightness = clampf(float(config.get_value("video", "brightness", 1.0)), BRIGHTNESS_RANGE.x, BRIGHTNESS_RANGE.y)
	interior_light = clampf(float(config.get_value("video", "interior_light", 1.0)), INTERIOR_LIGHT_RANGE.x,
			INTERIOR_LIGHT_RANGE.y)
	locale = config.get_value("game", "locale", DEFAULT_LOCALE)
	if not locale in LOCALES:
		locale = DEFAULT_LOCALE


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "window_mode", "windowed" if window_mode == WindowMode.WINDOWED else "fullscreen")
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "brightness", brightness)
	config.set_value("video", "interior_light", interior_light)
	config.set_value("game", "locale", locale)
	config.save(PATH)
