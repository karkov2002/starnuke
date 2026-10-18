class_name ChannelTile
extends Button
## Vignette d'une chaîne dans la mosaïque du menu de la télévision (TvDisplay) : numéro de chaîne, logo, drapeau du
## pays (en haut à droite du logo), nom de la chaîne et pays ; grisée avec « hors d'antenne » si la capitale du pays est détruite ; cadre clair sur la chaîne
## en cours et au survol.
##
## Logo généré à partir du nom de la chaîne (même nom, même logo à chaque partie) : une couleur de marque tirée d'une
## palette de chaînes d'information, un des quatre styles (bloc plein, bandeau souligné, pastille ronde, bandes
## obliques) et un monogramme (initiales des mots, nombres gardés entiers : « Liberty News Network » → « LNN »,
## « Rus Vesti 24 » → « RV24 »).

const BRAND_COLORS: Array[Color] = [
	Color(0.80, 0.07, 0.09), Color(0.05, 0.22, 0.55), Color(0.02, 0.10, 0.28), Color(0.93, 0.42, 0.05),
	Color(0.00, 0.47, 0.55), Color(0.40, 0.12, 0.55), Color(0.10, 0.45, 0.20), Color(0.70, 0.55, 0.05),
	Color(0.55, 0.05, 0.20), Color(0.15, 0.15, 0.18),
]
const ACCENTS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.82, 0.15), Color(0.95, 0.15, 0.15), Color(0.4, 0.8, 1.0)]
const COLOR_TEXT := Color(0.95, 0.96, 0.98)
const COLOR_DIM := Color(0.65, 0.68, 0.74)
## Drapeaux des pays (tools/build_tv_flags.ps1), nommés par code pays.
const FLAG_DIR := "res://assets/tv/flags/"

var code := ""
var number := 0
var channel_name := ""
var country := ""
var current := false
var off_air := false

var _brand := Color.WHITE
var _accent := Color.WHITE
var _style := 0
var _monogram := ""
var _flag: Texture2D


func setup(channel_code: String, channel_number: int, display_name: String, country_name: String) -> void:
	code = channel_code
	number = channel_number
	channel_name = display_name
	country = country_name
	var h := hash(display_name)
	_brand = BRAND_COLORS[absi(h) % BRAND_COLORS.size()]
	_accent = ACCENTS[absi(h >> 8) % ACCENTS.size()]
	if _accent.is_equal_approx(Color(0.95, 0.15, 0.15)) and _brand.r > 0.5:
		_accent = Color.WHITE
	_style = absi(h >> 16) % 4
	_monogram = monogram(display_name)
	var flag_path := FLAG_DIR + channel_code + ".png"
	_flag = load(flag_path) as Texture2D if ResourceLoader.exists(flag_path) else null
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	focus_mode = Control.FOCUS_NONE
	flat = true
	tooltip_text = ""
	queue_redraw()


func set_state(is_current: bool, is_off_air: bool) -> void:
	if is_current != current or is_off_air != off_air:
		current = is_current
		off_air = is_off_air
		queue_redraw()


static func monogram(display_name: String) -> String:
	var letters := ""
	for word in display_name.split(" ", false):
		if word.is_valid_int() or word.ends_with("h") and word.left(-1).is_valid_int() or word == "24x7":
			letters += word
		else:
			letters += word.left(1).to_upper()
	return letters.left(4)


func _draw() -> void:
	var font := get_theme_default_font()
	var r := Rect2(Vector2.ZERO, size)
	var hovered := is_hovered() and not off_air
	# Fond de la vignette.
	_box(r, Color(0.07, 0.09, 0.13, 0.96) if not hovered else Color(0.12, 0.16, 0.24, 0.98), 6.0)
	# Logo (zone 16:9 en haut).
	var pad := size.x * 0.06
	var logo := Rect2(Vector2(pad, pad), Vector2(size.x - 2.0 * pad, (size.x - 2.0 * pad) * 0.5))
	_draw_logo(logo, font)
	# Numéro, nom de la chaîne, pays.
	# Numéro dans une pastille sombre (lisible sur tous les logos).
	var digits := str(number)
	var badge := Rect2(logo.position + Vector2(4, 4), Vector2(12.0 + 8.0 * digits.length(), 20))
	_box(badge, Color(0, 0, 0, 0.7), 4.0)
	draw_string(font, Vector2(badge.position.x, badge.position.y + 15.0), digits, HORIZONTAL_ALIGNMENT_CENTER,
			badge.size.x, 13, Color.WHITE)
	# Drapeau du pays en haut à droite (liseré sombre : lisible sur les logos clairs comme foncés).
	if _flag:
		var height := logo.size.y * 0.3
		var width := height * _flag.get_width() / float(_flag.get_height())
		var flag_rect := Rect2(Vector2(logo.end.x - width - 5.0, logo.position.y + 5.0), Vector2(width, height))
		draw_rect(flag_rect.grow(1.5), Color(0, 0, 0, 0.75))
		draw_texture_rect(_flag, flag_rect, false, Color(1, 1, 1, 0.45) if off_air else Color.WHITE)
	var y := logo.end.y + size.y * 0.13
	draw_string(font, Vector2(pad, y), channel_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * pad, 15,
			COLOR_DIM if off_air else COLOR_TEXT, TextServer.JUSTIFICATION_NONE)
	draw_string(font, Vector2(pad, y + 18.0), country, HORIZONTAL_ALIGNMENT_LEFT, size.x - 2.0 * pad, 12, COLOR_DIM)
	if off_air:
		draw_rect(logo, Color(0.05, 0.05, 0.06, 0.72))
		draw_string(font, Vector2(logo.position.x, logo.get_center().y + 5.0), tr("TV_OFF_AIR").to_upper(),
				HORIZONTAL_ALIGNMENT_CENTER, logo.size.x, 13, Color(1.0, 0.45, 0.4))
	# Cadre : chaîne en cours, survol.
	if current or hovered:
		draw_rect(r.grow(-1.5), Color(1, 1, 1, 0.95) if current else Color(0.55, 0.75, 1.0, 0.9), false, 3.0)


func _draw_logo(r: Rect2, font: Font) -> void:
	# Zone du monogramme : centrée, rétrécie des deux côtés de la largeur du drapeau (entre le numéro et le drapeau).
	var flag_width := r.size.y * 0.3 * _flag.get_width() / float(_flag.get_height()) + 8.0 if _flag else 0.0
	var inner := r.grow_individual(-flag_width, 0.0, -flag_width, 0.0)
	var text_size := r.size.y * 0.5
	match _style:
		0: # Bloc plein, monogramme centré.
			_box(r, _brand, 4.0)
			_centered(font, inner, _monogram, text_size, _accent)
		1: # Fond clair, monogramme couleur, bandeau souligné.
			_box(r, Color(0.94, 0.95, 0.97), 4.0)
			_centered(font, Rect2(inner.position, Vector2(inner.size.x, r.size.y * 0.8)), _monogram, text_size, _brand)
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.8), Vector2(r.size.x, r.size.y * 0.2)), _brand)
		2: # Pastille ronde sur fond sombre.
			_box(r, Color(0.04, 0.05, 0.08), 4.0)
			var radius := r.size.y * 0.42
			draw_circle(inner.get_center(), radius, _brand)
			draw_arc(inner.get_center(), radius, 0.0, TAU, 48, _accent, 2.0, true)
			_centered(font, inner, _monogram, text_size * [1.0, 1.0, 1.0, 0.8, 0.62][mini(_monogram.length(), 4)], Color.WHITE)
		3: # Bandes obliques, monogramme à gauche.
			_box(r, _brand.darkened(0.35), 4.0)
			var x := r.end.x - r.size.y * 1.1
			for i in 3:
				var dx := x + i * r.size.y * 0.28
				draw_colored_polygon(PackedVector2Array([Vector2(dx, r.end.y), Vector2(dx + r.size.y * 0.5, r.position.y),
						Vector2(dx + r.size.y * 0.62, r.position.y), Vector2(dx + r.size.y * 0.12, r.end.y)]),
						_accent if i == 1 else _brand.lightened(0.15))
			draw_string(font, Vector2(r.position.x + r.size.x * 0.08, r.get_center().y + text_size * 0.36), _monogram,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(text_size), Color.WHITE)


## Texte centré dans r, réduit au besoin pour tenir dans 88 % de sa largeur.
func _centered(font: Font, r: Rect2, label: String, font_size: float, color: Color) -> void:
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_size)).x
	if width > r.size.x * 0.88:
		font_size *= r.size.x * 0.88 / width
	draw_string(font, Vector2(r.position.x, r.get_center().y + font_size * 0.36), label, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, int(font_size), color)


func _box(r: Rect2, color: Color, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, r)
