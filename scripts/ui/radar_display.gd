class_name RadarDisplay
extends Control
## Écran de la console radar (RadarConsole, dans un SubViewport) : oscilloscope à phosphore vert.
## - En haut : bande (VHF / UHF), azimut de l'antenne en grands chiffres au centre, fréquence accordée à droite.
## - Au centre : CURVES sinusoïdes. Hors accord, elles sont « chaotiques » (fréquences, phases et amplitudes qui
##   dérivent chacune à son rythme, bruit) ; plus l'accord approche la fréquence d'une source captée (cohérence de
##   RadarReceiver.measure), plus elles se rapprochent, jusqu'à fusionner en une seule sinusoïde stable, dont
##   l'amplitude suit le gain de l'antenne (maximale quand elle pointe la source). Position de la station en haut à
##   gauche (pour la triangulation), état de l'accord en haut à droite.
## - Barre de signal (cohérence × amplitude, en dB).
## - En bas : nom des trois boutons du modèle, au-dessus de chacun (KNOB_U : positions des boutons de
##   tools/blender/build_radar_console.py rapportées à la largeur de la dalle) ; bande choisie en surbrillance.
## - Radar extérieur arrêté ou en panne (fault_key, posé par la console) : bruit de fond seulement (NOISE_FLOOR) et
##   message clignotant au centre de l'oscilloscope.
## Textes : clés des fichiers de langue (tr), redessinés à chaque image.

const FONTS: PackedStringArray = ["Consolas", "Cascadia Mono", "Courier New", "monospace"]
const BACK := Color(0.008, 0.020, 0.014)
const GRID := Color(0.10, 0.34, 0.19, 0.45)
const GRID_AXIS := Color(0.14, 0.45, 0.25, 0.7)
const PHOSPHOR := Color(0.40, 1.0, 0.58)
const DIM := Color(0.20, 0.55, 0.32)
const AMBER := Color(1.0, 0.74, 0.28)
const CURVE_COLORS: Array[Color] = [Color(0.40, 1.0, 0.58), Color(0.30, 0.85, 1.0), Color(0.80, 1.0, 0.35),
		Color(0.25, 0.75, 0.62), Color(0.60, 0.95, 0.90)]
const CURVES := 5
const SAMPLES := 220
## Périodes affichées par la sinusoïde accordée.
const CYCLES := 3.0
## Abscisses (0–1) des boutons sous la dalle : x des boutons (−0,27 ; 0 ; 0,27 m) / largeur de la dalle (0,76 m).
const KNOB_U: Array[float] = [0.145, 0.5, 0.855]
## Vitesse (1/s) à laquelle l'affichage suit la mesure (fusion progressive des courbes).
const FOLLOW := 6.0
## Amplitude des courbes, radar extérieur hors service (bruit de fond du récepteur).
const NOISE_FLOOR := 0.06

var receiver: RadarReceiver
## Dernière mesure (RadarReceiver.measure) et point survolé (degrés), posés par la console.
var measure := {}
var station_point := Vector2.ZERO
## Clé du message de panne (RADAR_FAILURE, RADAR_OFF) ; vide si le radar extérieur fonctionne.
var fault_key := ""

var _font: SystemFont
var _time := 0.0
var _coherence := 0.0
var _amplitude := 0.0


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = FONTS
	_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY


func _process(delta: float) -> void:
	_time += delta
	var k := 1.0 - exp(-FOLLOW * delta)
	_coherence = lerpf(_coherence, float(measure.get("coherence", 0.0)), k)
	_amplitude = lerpf(_amplitude, float(measure.get("amplitude", 0.0)), k)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	if receiver == null:
		return
	_draw_header(w, h)
	var scope := Rect2(w * 0.03, h * 0.15, w * 0.94, h * 0.58)
	_draw_grid(scope)
	_draw_curves(scope)
	var position_text := tr("RADAR_POSITION").format({"pos": GeoMath.format_lat_lon(station_point.x, station_point.y, 3)})
	draw_string(_font, scope.position + Vector2(10, 24), position_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, DIM)
	if fault_key != "":
		_draw_fault(scope)
	else:
		var locked := _coherence >= RadarReceiver.LOCK
		var state := tr("RADAR_LOCKED") if locked else tr("RADAR_SEARCHING")
		if locked or fmod(_time, 1.2) < 0.8:
			_right(state, Vector2(scope.end.x - 10, scope.position.y + 24), 18, AMBER if locked else DIM)
	_draw_meter(Rect2(w * 0.03, h * 0.765, w * 0.94, h * 0.05))
	_draw_footer(w, h)


func _draw_header(w: float, h: float) -> void:
	var band_name := "VHF" if receiver.band == RadarReceiver.Band.VHF else "UHF"
	var box := Rect2(w * 0.03, h * 0.025, w * 0.11, h * 0.085)
	draw_rect(box, AMBER, false, 2.0)
	_centered(band_name, box.get_center() + Vector2(0, 11), 30, AMBER)
	draw_string(_font, Vector2(w * 0.17, h * 0.045), tr("RADAR_BAND"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DIM)
	_centered(tr("RADAR_AZIMUTH"), Vector2(w * 0.5, h * 0.035), 16, DIM)
	_centered("%05.1f°" % receiver.azimuth_deg, Vector2(w * 0.5, h * 0.115), 50, PHOSPHOR)
	var mhz := receiver.get_frequency_mhz()
	var frequency := ("%.2f MHz" % mhz) if receiver.band == RadarReceiver.Band.VHF else ("%.1f MHz" % mhz)
	_right(tr("RADAR_FREQUENCY"), Vector2(w * 0.97, h * 0.035), 16, DIM)
	_right(frequency, Vector2(w * 0.97, h * 0.11), 38, PHOSPHOR)


func _draw_grid(scope: Rect2) -> void:
	draw_rect(scope, GRID_AXIS, false, 2.0)
	for i in range(1, 10):
		var x := scope.position.x + scope.size.x * i / 10.0
		draw_line(Vector2(x, scope.position.y), Vector2(x, scope.end.y), GRID_AXIS if i == 5 else GRID, 1.0)
	for i in range(1, 8):
		var y := scope.position.y + scope.size.y * i / 8.0
		draw_line(Vector2(scope.position.x, y), Vector2(scope.end.x, y), GRID_AXIS if i == 4 else GRID, 1.0)


func _draw_curves(scope: Rect2) -> void:
	var c := clampf(_coherence, 0.0, 1.0)
	var chaos := 1.0 - c
	var cy := scope.get_center().y
	var hh := scope.size.y * 0.5 * (NOISE_FLOOR if fault_key != "" else 1.0)
	var tuned_amp := hh * 0.88 * (0.10 + 0.90 * clampf(_amplitude, 0.0, 1.0))
	var points := PackedVector2Array()
	points.resize(SAMPLES + 1)
	for k in CURVES:
		var fk := float(k)
		var cycles := CYCLES * (1.0 + chaos * 0.6 * sin(_time * (0.37 + 0.11 * fk) + fk * 1.9))
		var phase := -_time * 2.0 + chaos * (fk * 1.37 + 1.8 * sin(_time * (0.53 + 0.17 * fk) + fk))
		var noise_amp := hh * (0.30 + 0.18 * sin(_time * (0.8 + 0.2 * fk) + fk * 2.3))
		var amp := lerpf(noise_amp, tuned_amp, c)
		var jitter := chaos * hh * 0.09
		for i in SAMPLES + 1:
			var x := float(i) / SAMPLES
			var y := sin(TAU * cycles * x + phase) * amp \
					+ jitter * sin(x * 53.0 + _time * (7.0 + fk * 3.0) + fk) * sin(x * 17.0 + _time * 2.3 + fk * 0.7)
			points[i] = Vector2(scope.position.x + x * scope.size.x, cy - clampf(y, -hh, hh))
		var color := CURVE_COLORS[k].lerp(PHOSPHOR, c)
		if c > 0.5:
			var glow := color
			glow.a = 0.12 * (c - 0.5) * 2.0
			draw_polyline(points, glow, 8.0, true)
		color.a = lerpf(0.7, 0.95, c)
		draw_polyline(points, color, 2.0, true)


## Message de panne, clignotant, dans un cadre au centre de l'oscilloscope.
func _draw_fault(scope: Rect2) -> void:
	if fmod(_time, 1.0) >= 0.6:
		return
	var text := tr(fault_key)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x + 48.0
	var box := Rect2(scope.get_center() - Vector2(width * 0.5, 38), Vector2(width, 76))
	draw_rect(box, BACK)
	draw_rect(box, AMBER, false, 3.0)
	_centered(text, box.get_center() + Vector2(0, 15), 44, AMBER)


func _draw_meter(rect: Rect2) -> void:
	var level := clampf(_coherence, 0.0, 1.0) * clampf(_amplitude, 0.0, 1.0)
	var db := 20.0 * log(maxf(level, 0.001)) / log(10.0)
	draw_string(_font, rect.position + Vector2(0, rect.size.y * 0.78), tr("RADAR_SIGNAL"), HORIZONTAL_ALIGNMENT_LEFT, -1,
			18, DIM)
	var bar := Rect2(rect.position.x + rect.size.x * 0.14, rect.position.y + 2, rect.size.x * 0.70, rect.size.y - 4)
	var segments := 40
	var lit := int(round(segments * (db + 60.0) / 60.0))
	var step := bar.size.x / segments
	for i in segments:
		var r := Rect2(bar.position.x + i * step + 1, bar.position.y, step - 3, bar.size.y)
		var on := i < lit
		var color := (AMBER if i >= segments * 0.85 else PHOSPHOR) if on else Color(0.06, 0.16, 0.10)
		draw_rect(r, color)
	_right("%.1f dB" % db, Vector2(rect.end.x, rect.position.y + rect.size.y * 0.78), 18, PHOSPHOR)


func _draw_footer(w: float, h: float) -> void:
	var y := h * 0.93
	draw_line(Vector2(w * 0.03, h * 0.855), Vector2(w * 0.97, h * 0.855), GRID_AXIS, 1.0)
	_centered(tr("RADAR_AZIMUTH"), Vector2(w * KNOB_U[0], y), 24, PHOSPHOR)
	_centered(tr("RADAR_FREQUENCY"), Vector2(w * KNOB_U[1], y), 24, PHOSPHOR)
	var vhf := receiver.band == RadarReceiver.Band.VHF
	var bx := w * KNOB_U[2]
	_centered(tr("RADAR_BAND"), Vector2(bx, h * 0.895), 18, DIM)
	_centered("VHF", Vector2(bx - 48, h * 0.965), 24, AMBER if vhf else DIM)
	_centered("UHF", Vector2(bx + 48, h * 0.965), 24, DIM if vhf else AMBER)
	# Flèches vers les boutons, sous la dalle.
	for u in KNOB_U:
		var x := w * u
		draw_colored_polygon(PackedVector2Array([Vector2(x - 9, h * 0.975), Vector2(x + 9, h * 0.975),
				Vector2(x, h * 0.995)]), DIM)


func _centered(text: String, baseline_center: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, baseline_center - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _right(text: String, baseline_end: Vector2, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, baseline_end - Vector2(width, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
