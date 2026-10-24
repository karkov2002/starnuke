class_name SegmentDisplay
extends RefCounted
## Dessin des afficheurs à cristaux liquides de la station (horloges, position) : chiffres à sept segments légèrement
## penchés, segments éteints à peine visibles, « : », « . », « ° », lettres en police normale. Cotes en mètres sur la
## dalle nominale de 184 × 66 mm (origine au centre, z vers le haut), les mêmes que les textures de démonstration de
## tools/blender/build_station_clock.py (le modèle posé est agrandi, la dalle garde ses proportions).

const GLASS_W := 0.184
const GLASS_H := 0.066
## Image (1024 px de large, proportions de la dalle).
const SIZE := Vector2i(1024, 368)
const PX_PER_M := SIZE.x / GLASS_W
const BACKGROUND := Color(0.010, 0.012, 0.014)
const LIT := Color(0.80, 0.93, 1.0)
const OFF := Color(0.032, 0.036, 0.042)
## Segments allumés par caractère (a haut, b haut droit, c bas droit, d bas, e bas gauche, f haut gauche, g milieu).
const SEGMENTS := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
		"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""}
const SLANT := 0.06
## Largeur des caractères étroits, relative au pas.
const NARROW := {".": 0.45, "°": 0.5}


## Point de la dalle (mètres) -> pixel.
static func px(x: float, z: float) -> Vector2:
	return Vector2((x + GLASS_W / 2.0) * PX_PER_M, (GLASS_H / 2.0 - z) * PX_PER_M)


static func text_width(text: String, pitch: float) -> float:
	var width := 0.0
	for ch in text:
		width += float(NARROW.get(ch, 1.0)) * pitch
	return width


static func clear(canvas: CanvasItem) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), BACKGROUND)


## Caractères à sept segments partant de x_left, centrés verticalement en cz, hauteur h, pas pitch (mètres).
static func draw_digits(canvas: CanvasItem, text: String, x_left: float, cz: float, h: float, pitch: float) -> void:
	var x := x_left
	for ch in text:
		var w := float(NARROW.get(ch, 1.0)) * pitch
		var cx := x + w / 2.0
		match ch:
			":":
				for dz: float in [h * 0.22, -h * 0.22]:
					canvas.draw_circle(px(cx + SLANT * dz, cz + dz), h * 0.07 * PX_PER_M, LIT)
			".":
				canvas.draw_circle(px(cx - SLANT * h * 0.44, cz - h * 0.44), h * 0.065 * PX_PER_M, LIT)
			"°":
				canvas.draw_arc(px(cx + SLANT * h * 0.34, cz + h * 0.34), (h * 0.13 - h * 0.0275) * PX_PER_M, 0.0, TAU,
						24, LIT, h * 0.055 * PX_PER_M, true)
			_:
				var lit: String = SEGMENTS.get(ch, "")
				var polys := _segment_polys(cx, cz, h, h * 0.12)
				for key: String in polys:
					if not lit.contains(key):
						canvas.draw_colored_polygon(polys[key], OFF)
				for key: String in polys:
					if lit.contains(key):
						canvas.draw_colored_polygon(polys[key], LIT)
		x += w


## Texte en police normale (gras) centré verticalement en cz, aligné à gauche de x ou à droite de x (right).
static func draw_label(canvas: CanvasItem, text: String, x: float, cz: float, size_m: float, right := false) -> void:
	var font := ThemeDB.fallback_font
	var font_size := int(size_m * PX_PER_M)
	var at := px(x, cz)
	if right:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	at.y += font.get_ascent(font_size) * 0.36
	canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LIT)


## Polygones (pixels) des sept segments d'un chiffre centré en (cx, cz), hauteur h, trait t (mètres).
static func _segment_polys(cx: float, cz: float, h: float, t: float) -> Dictionary:
	var hw := h * 0.26
	var hh := h / 2.0
	var g := t * 0.18
	var horiz := func(zc: float, half: float) -> Array:
		return [[-half + g, zc], [-half + t / 2.0 + g, zc + t / 2.0], [half - t / 2.0 - g, zc + t / 2.0],
				[half - g, zc], [half - t / 2.0 - g, zc - t / 2.0], [-half + t / 2.0 + g, zc - t / 2.0]]
	var vert := func(xc: float, z0: float, z1: float) -> Array:
		return [[xc, z0 + g], [xc + t / 2.0, z0 + t / 2.0 + g], [xc + t / 2.0, z1 - t / 2.0 - g], [xc, z1 - g],
				[xc - t / 2.0, z1 - t / 2.0 - g], [xc - t / 2.0, z0 + t / 2.0 + g]]
	var shapes := {
		"a": horiz.call(hh - t / 2.0, hw - t / 2.0), "d": horiz.call(-hh + t / 2.0, hw - t / 2.0),
		"g": horiz.call(0.0, hw - t / 2.0),
		"b": vert.call(hw - t / 2.0, 0.0, hh), "c": vert.call(hw - t / 2.0, -hh, 0.0),
		"f": vert.call(-hw + t / 2.0, 0.0, hh), "e": vert.call(-hw + t / 2.0, -hh, 0.0),
	}
	var result := {}
	for key: String in shapes:
		var points := PackedVector2Array()
		for p: Array in shapes[key]:
			points.append(px(cx + p[0] + SLANT * p[1], cz + p[1]))
		result[key] = points
	return result
