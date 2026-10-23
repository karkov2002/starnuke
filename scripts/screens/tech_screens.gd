class_name TechScreens
extends Node
## Écrans d'ambiance « techno-thriller » des modules Commande et Arrimage (nœud TechScreens de scenes/orbit_view.tscn) :
## sur les écrans plats et les portables (pas sur le grand écran du poste de pilotage, PilotConsole), des
## programmes animés dessinés en 2D dans quelques SubViewports partagés :
## - CODE : listage de code et de journaux qui défile (lignes générées une fois au démarrage ; clin d'œil : environ un
##   commentaire sur douze est « // only Trap15 could understand this ») ;
## - WIREFRAME : la station en fil de fer qui tourne sur elle-même (modèle simplifié précalculé : modules, silos,
##   poutre, panneaux), avec réticule et mesures ;
## - TELEMETRY : courbes de télémétrie qui défilent, barregraphes, balayage radar ;
## - ORBIT : la Terre et l'orbite vues de dessus, la station qui tourne, colonnes de valeurs hexadécimales ;
## - STRIP : bandeau large (écrans 13 et 14) : spectre et oscilloscope.
## Coût réduit : chaque image n'est redessinée qu'à refresh_hz (15 Hz), et seulement quand la caméra est dans un
## module qui a des écrans animés (StationLayout.SCREEN_MODULES, boîtes élargies de MODULE_MARGIN_M ; sinon les
## SubViewports ne sont plus rendus). Écrans éteints avec « plus de lumière »
## (Station.get_blackout). Les textes affichés sont du pseudo-code et des valeurs (pas de langue) : hors fichiers de
## langue.

enum Program { CODE, WIREFRAME, TELEMETRY, ORBIT, STRIP }

## Écran (nom de l'objet du modèle) -> programme. Les écrans 02 (bilan des explosions), 03 (télévision) et 08
## (communication radio, CommConsole) ont leur propre affichage.
const ASSIGNMENT := {
	"Interactif_Ecran_01": Program.WIREFRAME,
	"Interactif_Ecran_04": Program.ORBIT,
	"Interactif_Ecran_05": Program.CODE,
	"Interactif_Ecran_06": Program.WIREFRAME,
	"Interactif_Ecran_07": Program.ORBIT,
	"Interactif_Ecran_13": Program.STRIP,
	"Interactif_Ecran_14": Program.STRIP,
	"Interactif_Ordinateur_01": Program.CODE,
	"Interactif_Ordinateur_02": Program.TELEMETRY,
	"Interactif_Ordinateur_03": Program.CODE,
	"Interactif_Ordinateur_04": Program.ORBIT,
	# Module Arrimage (paroi −Y, à côté de l'écoutille du sas de sortie).
	"Interactif_Ordinateur_05": Program.TELEMETRY,
}
const SIZE_16_10 := Vector2i(512, 320)
const SIZE_STRIP := Vector2i(1024, 304)
## Marge (m) autour des volumes des modules à écrans (StationLayout.ZONES) : les écrans s'animent déjà depuis la
## jonction voisine, avant d'entrer dans le module.
const MODULE_MARGIN_M := 1.5

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var refresh_hz := 15.0
@export var screen_energy := 1.1

var _station: Station
var _viewports := {}
var _canvases := {}
## Dalles habillées (StationScreen : matériau d'affichage, luminosité).
var _screens: Array[StationScreen] = []
var _time := 0.0
var _since := 0.0
var _active := false


func _ready() -> void:
	_station = get_node_or_null(station_path) as Station
	if _station == null:
		return
	for program in Program.values():
		var viewport := SubViewport.new()
		viewport.name = "Tech_%d" % program
		viewport.size = SIZE_STRIP if program == Program.STRIP else SIZE_16_10
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var canvas := TechCanvas.new()
		canvas.program = program
		canvas.size = Vector2(viewport.size)
		viewport.add_child(canvas)
		_viewports[program] = viewport
		_canvases[program] = canvas
	for screen_name: String in ASSIGNMENT:
		var screen := StationScreen.find(_station, screen_name)
		if screen == null:
			continue
		screen.apply_shader(StationScreen.TECH_SHADER, (_viewports[ASSIGNMENT[screen_name]] as SubViewport).get_texture(),
				{"energy": screen_energy})
		_screens.append(screen)
	if _screens.is_empty():
		push_error("TechScreens : aucun écran du module Commande trouvé")
	_tick()


func _process(delta: float) -> void:
	_time += delta
	_since += delta
	var camera := get_viewport().get_camera_3d()
	var active := camera != null and _in_module(camera.global_position)
	if active != _active:
		_active = active
		_since = INF
	if not _active or _since < 1.0 / refresh_hz:
		return
	_since = 0.0
	_tick()


func _tick() -> void:
	var energy := screen_energy * (1.0 - _station.get_blackout())
	for screen in _screens:
		screen.set_energy(energy)
	for program: int in _canvases:
		var canvas: TechCanvas = _canvases[program]
		canvas.time = _time
		canvas.queue_redraw()
		(_viewports[program] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _in_module(world_position: Vector3) -> bool:
	var blender := StationLayout.to_blender(_station.global_transform.affine_inverse() * world_position)
	for zone in StationLayout.SCREEN_MODULES:
		if StationLayout.is_in_zone(blender, zone, MODULE_MARGIN_M):
			return true
	return false


# --- Dessin des programmes ------------------------------------------------------------------------------------------

class TechCanvas:
	extends Control

	const GREEN := Color(0.35, 1.0, 0.55)
	const DIM := Color(0.15, 0.45, 0.25)
	const CYAN := Color(0.3, 0.85, 1.0)
	const AMBER := Color(1.0, 0.7, 0.2)
	const RED := Color(1.0, 0.3, 0.25)
	const BACKGROUND := Color(0.008, 0.02, 0.015)
	const CODE_WORDS := ["init", "vec3", "quat", "orbit", "burn", "thrust", "node", "raan", "argp", "ecef", "eci",
			"gyro", "imu", "kalman", "dt", "sigma", "frame", "sync", "uplink", "packet", "crc32", "buffer", "mutex",
			"thread", "silo", "tube", "arm", "seal", "valve", "bus", "volt", "amp", "temp", "rad", "flux", "deltaV"]
	const CODE_KEYWORDS := ["fn", "let", "if", "for", "return", "while", "match", "const", "assert", "yield"]

	var program := 0
	var time := 0.0
	var _font: Font
	var _lines: PackedStringArray = []
	var _line_colors: PackedColorArray = []
	var _hex: PackedStringArray = []
	## Station en fil de fer : segments (paires de points 3D, repère de la station, mètres).
	var _wire := PackedVector3Array()
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		var system := SystemFont.new()
		system.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
		_font = system
		_rng.seed = 7919 + program * 101
		match program:
			0:
				_build_code(220)
			3:
				_build_hex(64)
			1:
				_build_wire()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
		match program:
			0:
				_draw_code()
			1:
				_draw_wireframe()
			2:
				_draw_telemetry()
			3:
				_draw_orbit()
			4:
				_draw_strip()
		# Cadre fin et coin d'interface.
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), DIM, false, 1.0)
		draw_line(Vector2(3, 3), Vector2(40, 3), GREEN, 2.0)
		draw_line(Vector2(3, 3), Vector2(3, 24), GREEN, 2.0)

	# CODE ---------------------------------------------------------------------------------------------------------

	func _build_code(count: int) -> void:
		for i in count:
			var kind := _rng.randi() % 6
			var indent := "    ".repeat(_rng.randi() % 3)
			var line := ""
			var color := GREEN
			match kind:
				0:
					line = "%s%s %s(%s, %s) {" % [indent, _pick(CODE_KEYWORDS), _pick(CODE_WORDS), _pick(CODE_WORDS),
							_pick(CODE_WORDS)]
				1:
					line = "%s%s.%s = %s * %.4f;" % [indent, _pick(CODE_WORDS), _pick(CODE_WORDS), _pick(CODE_WORDS),
							_rng.randf_range(-9.0, 9.0)]
				2:
					line = "%s// %s %s %s" % [indent, _pick(CODE_WORDS).to_upper(), _pick(CODE_WORDS), _pick(CODE_WORDS)]
					# Clin d'œil : de temps en temps, un commentaire de développeur égaré dans le listage.
					if _rng.randf() < 1.0 / 12.0:
						line = "%s// only Trap15 could understand this" % indent
					color = DIM
				3:
					line = "[%07.3f] %s::%s ... OK" % [_rng.randf_range(0.0, 9999.0), _pick(CODE_WORDS).to_upper(),
							_pick(CODE_WORDS)]
					color = CYAN
				4:
					line = "0x%08X  %02X %02X %02X %02X  %02X %02X %02X %02X" % [_rng.randi(), _rng.randi() % 256,
							_rng.randi() % 256, _rng.randi() % 256, _rng.randi() % 256, _rng.randi() % 256,
							_rng.randi() % 256, _rng.randi() % 256, _rng.randi() % 256]
					color = DIM.lerp(GREEN, 0.5)
				5:
					line = "%s}" % indent if _rng.randf() < 0.6 else "WARN %s.%s threshold %d%%" % [_pick(CODE_WORDS),
							_pick(CODE_WORDS), _rng.randi_range(80, 99)]
					color = GREEN if line.ends_with("}") else AMBER
			_lines.append(line)
			_line_colors.append(color)

	func _draw_code() -> void:
		var line_h := 15.0
		var offset := fmod(time * 42.0, line_h * _lines.size())
		var first := int(offset / line_h)
		var shift := fmod(offset, line_h)
		var rows := int(size.y / line_h) + 2
		for r in rows:
			var i := (first + r) % _lines.size()
			var y := 18.0 + r * line_h - shift
			draw_string(_font, Vector2(12, y), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 12, _line_colors[i])
		# Curseur clignotant et barre d'état.
		draw_rect(Rect2(Vector2(0, size.y - 22), Vector2(size.x, 22)), Color(0.02, 0.08, 0.05))
		draw_string(_font, Vector2(12, size.y - 7), "SYS/NAV  PID %d  CPU %02d%%  MEM %.1fG" % [4100 + int(time) % 37,
				40 + int(abs(sin(time * 0.7)) * 50), 3.2 + sin(time * 0.3)], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GREEN)
		if fmod(time, 1.0) < 0.5:
			draw_rect(Rect2(Vector2(size.x - 30, size.y - 18), Vector2(10, 14)), GREEN)

	# WIREFRAME ------------------------------------------------------------------------------------------------------

	func _ring(center: Vector3, axis: int, radius: float, segments := 16) -> void:
		for k in segments:
			var a := TAU * k / segments
			var b := TAU * (k + 1) / segments
			_wire.append(center + _circle(axis, radius, a))
			_wire.append(center + _circle(axis, radius, b))

	func _circle(axis: int, radius: float, a: float) -> Vector3:
		match axis:
			0:
				return Vector3(0, cos(a), sin(a)) * radius
			1:
				return Vector3(cos(a), 0, sin(a)) * radius
		return Vector3(cos(a), sin(a), 0) * radius

	func _cylinder(from: Vector3, to: Vector3, axis: int, radius: float, rings := 3) -> void:
		for i in rings:
			_ring(from.lerp(to, float(i) / float(rings - 1)), axis, radius)
		for k in 8:
			var p := _circle(axis, radius, TAU * k / 8)
			_wire.append(from + p)
			_wire.append(to + p)

	func _box(center: Vector3, half: Vector3, grid := 0) -> void:
		var corners := []
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					corners.append(center + Vector3(sx, sy, sz) * half)
		for i in 8:
			for j in range(i + 1, 8):
				var d: Vector3 = corners[i] - corners[j]
				if int(d.x != 0) + int(d.y != 0) + int(d.z != 0) == 1:
					_wire.append(corners[i])
					_wire.append(corners[j])
		for g in grid:
			var t := float(g + 1) / float(grid + 1)
			_wire.append(center + Vector3(-half.x, lerpf(-half.y, half.y, t), 0))
			_wire.append(center + Vector3(half.x, lerpf(-half.y, half.y, t), 0))

	## Modèle simplifié de la station (repère du modèle : modules le long de X, silos le long de Y).
	func _build_wire() -> void:
		_cylinder(Vector3(-17.0, 0, 0), Vector3(-7.1, 0, 0), 0, 2.1, 4)
		_cylinder(Vector3(-4.5, 0, 0), Vector3(4.5, 0, 0), 0, 2.15, 4)
		_cylinder(Vector3(7.1, 0, 0), Vector3(16.9, 0, 0), 0, 2.15, 4)
		_cylinder(Vector3(-7.1, 0, 0), Vector3(-4.5, 0, 0), 0, 1.3, 2)
		_cylinder(Vector3(4.5, 0, 0), Vector3(7.1, 0, 0), 0, 1.3, 2)
		for s in [-1, 1]:
			_cylinder(Vector3(0, s * 5.0, 0), Vector3(0, s * 21.0, 0), 1, 3.8, 5)
			_cylinder(Vector3(0, s * 1.4, 0), Vector3(0, s * 5.0, 0), 1, 1.5, 2)
			_box(Vector3(0, s * 25.0, 6.0), Vector3(0.5, 0.5, 0.6))
			for p in [-1, 1]:
				_box(Vector3(p * 16.5, s * 33.0, 9.5), Vector3(0.05, 9.0, 4.8), 6)
		_box(Vector3(0, 0, 6.0), Vector3(0.4, 25.6, 0.4))
		_box(Vector3(0, 0, 6.0), Vector3(16.5, 0.3, 0.3))
		_ring(Vector3(11.6, 0, -3.2), 2, 1.4, 6)

	func _draw_wireframe() -> void:
		# Rotation autour de la verticale de la station (+Z du modèle), vue en légère plongée ; projection : X à droite,
		# Z en haut. La station tient dans un rayon de ~46 m (panneaux compris).
		var angle := time * 0.35
		var tilt := 0.42 + 0.08 * sin(time * 0.2)
		var turn := Basis(Vector3.RIGHT, -tilt) * Basis(Vector3.BACK, angle)
		var pixels_per_m := minf(size.y * 0.44, size.x * 0.3) / 46.0
		var center := Vector2(size.x * 0.37, size.y * 0.54)
		var points := PackedVector2Array()
		points.resize(_wire.size())
		for i in _wire.size():
			var p := turn * (_wire[i] - Vector3(0, 0, 4.0))
			points[i] = center + Vector2(p.x, -p.z) * pixels_per_m
		draw_multiline(points, CYAN.lerp(GREEN, 0.25) * Color(1, 1, 1, 0.85), 1.0, true)
		# Réticule, échelle et étiquettes de mesure.
		draw_arc(center, size.y * 0.42, 0.0, TAU, 64, DIM, 1.0, true)
		for k in 12:
			var a := TAU * k / 12 + time * 0.1
			draw_line(center + Vector2.from_angle(a) * size.y * 0.4, center + Vector2.from_angle(a) * size.y * 0.44, DIM)
		var x := size.x * 0.76
		draw_string(_font, Vector2(x, 34), "STRUCT MODEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GREEN)
		draw_string(_font, Vector2(x, 54), "ROT %06.2f" % fmod(rad_to_deg(angle), 360.0), HORIZONTAL_ALIGNMENT_LEFT, -1,
				12, CYAN)
		draw_string(_font, Vector2(x, 70), "TILT %05.2f" % rad_to_deg(tilt), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
		for i in 8:
			var ok := fmod(time * 0.5 + i * 0.37, 7.0) > 0.4
			draw_string(_font, Vector2(x, 100 + i * 17), "MOD-%02d %s" % [i + 1, "NOMINAL" if ok else "CHECK"],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GREEN if ok else AMBER)

	# TELEMETRY ------------------------------------------------------------------------------------------------------

	func _draw_telemetry() -> void:
		var graph := Rect2(Vector2(14, 28), Vector2(size.x * 0.62, size.y * 0.55))
		draw_rect(graph, DIM, false, 1.0)
		for g in 5:
			var y := graph.position.y + graph.size.y * g / 4.0
			draw_line(Vector2(graph.position.x, y), Vector2(graph.end.x, y), DIM * Color(1, 1, 1, 0.4))
		var colors := [GREEN, CYAN, AMBER]
		for c in 3:
			var points := PackedVector2Array()
			for k in 96:
				var t := time * 1.4 + k * 0.08
				var v := sin(t * (1.0 + c * 0.6) + c) * 0.35 + sin(t * 3.7 + c * 2.0) * 0.12 + sin(t * 0.3) * 0.2
				points.append(graph.position + Vector2(graph.size.x * k / 95.0, graph.size.y * (0.5 - v * 0.9)))
			draw_polyline(points, colors[c], 1.5, true)
		draw_string(_font, Vector2(16, 20), "TELEMETRY  CH1 CH2 CH3", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GREEN)
		# Barregraphes.
		for b in 10:
			var level := 0.5 + 0.45 * sin(time * (0.8 + b * 0.13) + b)
			var x := 14.0 + b * (graph.size.x / 10.0)
			var h := (size.y - graph.end.y - 30.0) * level
			draw_rect(Rect2(Vector2(x + 2, size.y - 14 - h), Vector2(graph.size.x / 10.0 - 6, h)),
					GREEN if level < 0.85 else AMBER)
		# Radar à balayage.
		var center := Vector2(size.x * 0.83, size.y * 0.42)
		var radius := size.y * 0.3
		for r in 3:
			draw_arc(center, radius * (r + 1) / 3.0, 0.0, TAU, 48, DIM, 1.0, true)
		var sweep := fmod(time * 1.8, TAU)
		for k in 12:
			var a := sweep - k * 0.06
			draw_line(center, center + Vector2.from_angle(a) * radius, GREEN * Color(1, 1, 1, 0.5 * (1.0 - k / 12.0)), 2.0)
		for blip in 5:
			var a := blip * 1.3 + 0.4
			var age := fposmod(sweep - a, TAU)
			if age < 2.5:
				draw_circle(center + Vector2.from_angle(a) * radius * (0.3 + 0.13 * blip), 3.0,
						GREEN * Color(1, 1, 1, 1.0 - age / 2.5))
		draw_string(_font, Vector2(center.x - radius, center.y + radius + 22), "RNG %04d KM" % (1200 + int(time * 7) % 800),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)

	# ORBIT ----------------------------------------------------------------------------------------------------------

	func _build_hex(count: int) -> void:
		for i in count:
			_hex.append("%04X %08X %08X" % [i * 16, _rng.randi(), _rng.randi()])

	func _draw_orbit() -> void:
		var center := Vector2(size.y * 0.55, size.y * 0.52)
		var earth := size.y * 0.24
		draw_circle(center, earth, Color(0.02, 0.08, 0.12))
		draw_arc(center, earth, 0.0, TAU, 64, CYAN, 1.5, true)
		# Méridiens (ellipses qui tournent avec la Terre) et parallèles.
		for m in 6:
			var squash := cos(time * 0.2 + m * PI / 6.0)
			var meridian := PackedVector2Array()
			for k in 33:
				var phi := PI * k / 32.0 - PI / 2.0
				meridian.append(center + Vector2(cos(phi) * squash, sin(phi)) * earth)
			draw_polyline(meridian, CYAN * Color(1, 1, 1, 0.22), 1.0, true)
		for p in [-0.5, 0.0, 0.5]:
			var half := sqrt(1.0 - p * p) * earth
			draw_line(center + Vector2(-half, p * earth), center + Vector2(half, p * earth), CYAN * Color(1, 1, 1, 0.22))
		var orbit_r := earth * 1.55
		var points := PackedVector2Array()
		for k in 65:
			var theta := TAU * k / 64
			points.append(center + Vector2(cos(theta) * orbit_r, sin(theta) * orbit_r * 0.45).rotated(0.4))
		draw_polyline(points, GREEN, 1.5, true)
		var a := time * 0.6
		var station := center + Vector2(cos(a) * orbit_r, sin(a) * orbit_r * 0.45).rotated(0.4)
		draw_circle(station, 4.0, AMBER)
		draw_arc(station, 9.0 + 3.0 * sin(time * 4.0), 0.0, TAU, 24, AMBER, 1.0, true)
		draw_string(_font, Vector2(14, 22), "ORBIT DETERMINATION", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GREEN)
		draw_string(_font, Vector2(14, size.y - 14), "ALT 400.0  INC 51.6  T+%06d" % int(time * 10.0),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
		var x := size.x * 0.6
		var first := int(time * 6.0)
		for r in 16:
			draw_string(_font, Vector2(x, 26 + r * 17), _hex[(first + r) % _hex.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					GREEN if r != 7 else AMBER)

	# STRIP ----------------------------------------------------------------------------------------------------------

	func _draw_strip() -> void:
		var bars := 64
		var width := size.x * 0.55 / bars
		for b in bars:
			var level := absf(sin(time * 2.0 + b * 0.31) * 0.6 + sin(time * 5.3 + b * 0.77) * 0.3) + 0.05
			var h := (size.y - 40.0) * minf(level, 1.0)
			draw_rect(Rect2(Vector2(14 + b * width, size.y - 14 - h), Vector2(width - 2, h)),
					GREEN.lerp(AMBER, clampf(level - 0.6, 0.0, 1.0) * 2.0))
		var scope := Rect2(Vector2(size.x * 0.6, 20), Vector2(size.x * 0.38, size.y - 40))
		draw_rect(scope, DIM, false, 1.0)
		draw_line(Vector2(scope.position.x, scope.get_center().y), Vector2(scope.end.x, scope.get_center().y), DIM)
		var points := PackedVector2Array()
		for k in 128:
			var t := k / 127.0
			var v := sin(t * TAU * 3.0 + time * 6.0) * 0.6 * (0.6 + 0.4 * sin(time * 0.9)) + sin(t * TAU * 11.0) * 0.08
			points.append(Vector2(scope.position.x + scope.size.x * t, scope.get_center().y - v * scope.size.y * 0.45))
		draw_polyline(points, CYAN, 1.5, true)
		draw_string(_font, Vector2(16, 18), "RF SPECTRUM  2.2-2.3 GHz", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GREEN)

	func _pick(words: Array) -> String:
		return words[_rng.randi() % words.size()]
