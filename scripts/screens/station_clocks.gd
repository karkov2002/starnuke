class_name StationClocks
extends Node
## Horloges murales LCD de la station (objets Interactif_Horloge_* du modèle, tools/blender/build_station_clock.py ;
## nœud StationClocks de scenes/orbit_view.tscn) : la date (ISO 8601) et l'heure UTC du jeu (Orbit) sont dessinées à
## chiffres à sept segments dans un seul SubViewport, partagé par toutes les dalles (matériau Ecran_Horloge : même
## heure partout) et redessiné seulement quand la seconde affichée change. Éteintes avec « plus de lumière »
## (Station.get_blackout). Textes affichés : chiffres et « UTC » (aucune langue) : hors fichiers de langue.
## Disposition identique à la texture de démonstration de l'aperçu Blender : date en petit en haut à gauche, « UTC »
## en haut à droite, heure en grands chiffres en bas (cotes en mètres sur la dalle de 184 × 66 mm, origine au centre).

## Dalle (build_station_clock.py : GLASS_W, GLASS_H) et image.
const GLASS_W := 0.184
const GLASS_H := 0.066
const SIZE := Vector2i(1024, 368)
const BACKGROUND := Color(0.010, 0.012, 0.014)
const LIT := Color(0.80, 0.93, 1.0)
const OFF := Color(0.032, 0.036, 0.042)

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var orbit_path: NodePath = ^"../Orbit"
@export var screen_energy := 1.2

var _station: Station
var _orbit: OrbitSimulation
var _viewport: SubViewport
var _canvas: ClockCanvas
var _screens: Array[StationScreen] = []
## Seconde UTC affichée (temps Unix), −1 avant le premier dessin.
var _shown_unix := -1


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	if _station == null or _orbit == null:
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.name = "Clock"
	_viewport.size = SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_2d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_canvas = ClockCanvas.new()
	_canvas.size = Vector2(SIZE)
	_viewport.add_child(_canvas)
	for mesh: MeshInstance3D in _station.find_children("Interactif_Horloge_*", "MeshInstance3D", true, false):
		var screen := StationScreen.find(_station, mesh.name)
		if screen == null:
			continue
		screen.apply_shader(StationScreen.TECH_SHADER, _viewport.get_texture(), {"energy": screen_energy, "scan_depth": 0.0})
		_screens.append(screen)
	if _screens.is_empty():
		push_error("StationClocks : aucune horloge (Interactif_Horloge_*) dans le modèle de la station")
		set_process(false)


func _process(_delta: float) -> void:
	var energy := screen_energy * (1.0 - _station.get_blackout())
	for screen in _screens:
		screen.set_energy(energy)
	var unix := int(floorf(_orbit.get_utc_unix_s()))
	if unix == _shown_unix:
		return
	_shown_unix = unix
	_canvas.datetime = Time.get_datetime_dict_from_unix_time(unix)
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Dessin de l'affichage : segments éteints à peine visibles, segments allumés clairs (chiffres légèrement penchés
## comme les afficheurs), deux points du séparateur d'heure, « UTC » en police normale.
class ClockCanvas:
	extends Control

	## Segments d'un chiffre (a haut, b haut droit, c bas droit, d bas, e bas gauche, f haut gauche, g milieu).
	const SEGMENTS := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
			"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""}
	const SLANT := 0.06
	const PX_PER_M := StationClocks.SIZE.x / StationClocks.GLASS_W

	var datetime := {}

	## Point de la dalle (mètres, origine au centre, z vers le haut) -> pixel.
	static func px(x: float, z: float) -> Vector2:
		return Vector2((x + StationClocks.GLASS_W / 2.0) * PX_PER_M, (StationClocks.GLASS_H / 2.0 - z) * PX_PER_M)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), StationClocks.BACKGROUND)
		if datetime.is_empty():
			return
		_draw_digits("%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day], -0.022, 0.0170, 0.0150, 0.0105)
		_draw_digits("%02d:%02d:%02d" % [datetime.hour, datetime.minute, datetime.second], 0.0, -0.0110, 0.0290, 0.0198)
		var font := ThemeDB.fallback_font
		var font_size := int(0.0115 * PX_PER_M)
		var text_size := font.get_string_size("UTC", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var right := px(StationClocks.GLASS_W / 2.0 - 0.010, 0.0170)
		draw_string(font, Vector2(right.x - text_size.x, right.y + font.get_ascent(font_size) * 0.36), "UTC",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, StationClocks.LIT)

	## Suite de caractères centrée en (cx, cz), chiffres de hauteur h (m), pas horizontal pitch.
	func _draw_digits(text: String, cx: float, cz: float, h: float, pitch: float) -> void:
		var x := cx - (text.length() - 1) * pitch / 2.0
		for ch in text:
			if ch == ":":
				for dz in [h * 0.22, -h * 0.22]:
					draw_circle(px(x, cz + dz), h * 0.07 * PX_PER_M, StationClocks.LIT)
			else:
				var lit: String = SEGMENTS.get(ch, "")
				var polys := _segment_polys(x, cz, h, h * 0.12)
				for key: String in polys:
					if not lit.contains(key):
						draw_colored_polygon(polys[key], StationClocks.OFF)
				for key: String in polys:
					if lit.contains(key):
						draw_colored_polygon(polys[key], StationClocks.LIT)
			x += pitch

	## Polygones (pixels) des sept segments d'un chiffre centré en (cx, cz), hauteur h, trait t (mètres).
	func _segment_polys(cx: float, cz: float, h: float, t: float) -> Dictionary:
		var w := h * 0.52
		var hw := w / 2.0
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
