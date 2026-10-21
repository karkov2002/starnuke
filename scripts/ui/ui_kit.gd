class_name UiKit
extends RefCounted
## Fabriques de l'interface construite en code (écrans de la station, menus) : étiquettes, boutons des menus, boîtes de
## style. Une seule écriture de chaque recette, au lieu d'une par écran.

## Taille et police des boutons des menus plein écran (démarrage, fin de campagne, mort).
const MENU_BUTTON_SIZE := Vector2(380.0, 60.0)
const MENU_BUTTON_FONT_SIZE := 26


## Étiquette : text est une clé de langue (translate) ou un texte déjà composé (sans traduction automatique, qui le
## remplacerait par la clé introuvable) ; font_size 0 : taille du thème.
static func label(text: String, font_size := 0, color := Color.WHITE, translate := true,
		alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var result := Label.new()
	result.text = text
	if not translate:
		result.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	result.horizontal_alignment = alignment
	if font_size > 0:
		result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


## Bouton des menus plein écran (clé de langue, action au clic).
static func menu_button(key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = key
	button.custom_minimum_size = MENU_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", MENU_BUTTON_FONT_SIZE)
	button.pressed.connect(action)
	return button


## Boîte plate : fond, liseré (épaisseur 0 : aucun), coins arrondis, marge intérieure.
static func flat_box(fill: Color, border := Color.TRANSPARENT, border_width := 0, radius := 6, margin := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style
