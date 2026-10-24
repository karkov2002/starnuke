class_name RadarConsole
extends ScreenSeatConsole
## Console radar du module Commande (nœud RadarConsole de scenes/orbit_view.tscn) : récepteur goniométrique posé à la
## place de l'écran d'ambiance SCREEN_NODE (retiré de TechScreens ; modèle tools/blender/build_radar_console.py).
## La dalle affiche l'oscilloscope (RadarDisplay, dans un SubViewport) ; sous la dalle, trois boutons 3D du modèle
## (KNOB_NODES), qu'on tourne en maintenant le clic et en glissant la souris à gauche ou à droite (Maj : réglage fin) :
## - azimut de l'antenne, sur 360° (AZIMUTH_DEG_PER_PX), le bouton tourne avec ;
## - fréquence dans la bande (part FREQUENCY_SPAN_PER_PX de la bande par pixel), le bouton tourne de
##   FREQUENCY_TURNS tours sur toute la bande ;
## - bande VHF / UHF : sélecteur à manette deux positions (glisser à droite : UHF, à gauche : VHF).
## Comme la télévision et la radio (ScreenSeatConsole) : un clic sur la dalle installe devant la console (cadre
## agrandi vers le bas pour montrer les boutons, SEAT_EXTEND_DOWN), clic droit pour quitter, garde de distance.
## Modèle et règles de jeu (sources, horizon, accord, lobe de l'antenne) : RadarReceiver. Sources : en mode libre,
## RadarReceiver.FREE_MODE_SOURCES (Oslo VHF 100 MHz, Los Angeles UHF 800 MHz) ; les missions de la campagne
## ajouteront les leurs par add_source.

enum Knob { NONE = -1, AZIMUTH, FREQUENCY, BAND }

const SCREEN_NODE := "Interactif_Ecran_07"
const VIEWPORT_HEIGHT := 600
const KNOB_NODES := {Knob.AZIMUTH: "Radar_Bouton_Azimut", Knob.FREQUENCY: "Radar_Bouton_Frequence",
		Knob.BAND: "Radar_Bouton_Bande"}
## Rayon (m) de la zone de prise d'un bouton, autour de son axe.
const KNOB_RADIUS_M := 0.05
const AZIMUTH_DEG_PER_PX := 0.25
## Part de l'étendue de la bande par pixel glissé (VHF : 0,135 MHz, UHF : 1,35 MHz).
const FREQUENCY_SPAN_PER_PX := 1.0 / 2000.0
## Facteur du réglage fin (Maj enfoncée).
const FINE := 0.1
## Tours du bouton de fréquence d'un bout à l'autre de la bande.
const FREQUENCY_TURNS := 12.0
## Angle (degrés) des deux positions du sélecteur de bande (VHF à gauche, UHF à droite), comme le modèle.
const BAND_DEG := 40.0
## Glissement (px) qui fait basculer le sélecteur de bande.
const BAND_DRAG_PX := 25.0
## Agrandissement vers le bas du cadre de la vue assise (part de la hauteur de la dalle) : bande des boutons.
const SEAT_EXTEND_DOWN := 0.6

@export var orbit_path: NodePath = ^"../Orbit"

var receiver := RadarReceiver.new()

var _orbit: OrbitSimulation
var _display: RadarDisplay
## Bouton -> Node3D du modèle, et sa pose de repos (Transform3D locale, position zéro ; sélecteur sur VHF).
var _knobs := {}
var _knob_rest := {}
## Axe de rotation des boutons dans le repère de leur parent (vers l'observateur).
var _knob_axis := Vector3.ZERO
var _drag := Knob.NONE
var _band_drag := 0.0
var _hover := Knob.NONE
## Angle affiché du sélecteur de bande (rad, par rapport au repos), qui rejoint sa position en douceur.
var _band_angle := 0.0


## Ajoute une source d'émission (mission de la campagne) : voir RadarReceiver.add_source.
func add_source(id: String, lat: float, lon: float, band: RadarReceiver.Band, mhz: float) -> void:
	receiver.add_source(id, lat, lon, band, mhz)


func remove_source(id: String) -> void:
	receiver.remove_source(id)


## Mesure courante (RadarReceiver.measure) vue de la station.
func current_measure() -> Dictionary:
	var point := _orbit.get_subsatellite_point()
	return receiver.measure(point.x, point.y, _orbit.altitude_km)


func _screen_node() -> String:
	return SCREEN_NODE


func _prepare() -> bool:
	_orbit = get_node_or_null(orbit_path) as OrbitSimulation
	if _orbit == null:
		return false
	if CampaignSession.mode == CampaignSession.Mode.FREE:
		for source in RadarReceiver.FREE_MODE_SOURCES:
			receiver.add_source(source.id, source.lat, source.lon, source.band, source.mhz)
	return true


func _make_viewport() -> SubViewport:
	return _screen.make_viewport(VIEWPORT_HEIGHT)


func _create_display(into: SubViewport) -> void:
	_display = RadarDisplay.new()
	_display.name = "Display"
	_display.receiver = receiver
	_display.size = Vector2(into.size)
	into.add_child(_display)
	_knob_axis = Vector3.ZERO
	for knob: Knob in KNOB_NODES:
		var node := _station.find_child(KNOB_NODES[knob], true, false) as Node3D
		if node == null:
			push_error("RadarConsole : bouton %s introuvable dans le modèle" % KNOB_NODES[knob])
			continue
		_knobs[knob] = node
		_knob_rest[knob] = node.transform
		if _knob_axis == Vector3.ZERO:
			_knob_axis = (node.get_parent_node_3d().global_basis.inverse() * _screen.toward_viewer()).normalized()
	_update_knobs(0.0)


func _scan_depth() -> float:
	return 0.05


func _on_near_changed(near_now: bool) -> void:
	_display.set_process(near_now)


func _update_screen(delta: float, near_now: bool) -> void:
	if not near_now:
		return
	var point := _orbit.get_subsatellite_point()
	_display.station_point = point
	_display.measure = receiver.measure(point.x, point.y, _orbit.altitude_km)
	_update_knobs(delta)


func _hover_key() -> String:
	return "RADAR_HOVER"


func _exit_key() -> String:
	return "RADAR_EXIT_HINT"


func _seat_pose() -> Dictionary:
	return _screen.seat_pose(_camera, get_viewport().get_visible_rect().size.aspect(), screen_fill, SEAT_EXTEND_DOWN)


func _on_stood_up() -> void:
	_drag = Knob.NONE
	_set_hover(Knob.NONE)


## Toute la souris du poste est pour les boutons (l'écran n'a pas d'interface cliquable).
func _handle_mouse(mouse: InputEventMouse) -> bool:
	var button := mouse as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_drag = _knob_at(button.position)
			_band_drag = 0.0
		else:
			_drag = Knob.NONE
		_set_hover(_drag if _drag != Knob.NONE else _knob_at(button.position))
		return true
	var motion := mouse as InputEventMouseMotion
	if motion:
		if _drag == Knob.NONE:
			_set_hover(_knob_at(motion.position))
		else:
			turn(_drag, motion.relative.x * (FINE if motion.shift_pressed else 1.0))
	return true


## Tourne un bouton d'un glissement de dx pixels (positif : vers la droite, sens horaire).
func turn(knob: Knob, dx: float) -> void:
	match knob:
		Knob.AZIMUTH:
			receiver.set_azimuth_deg(receiver.azimuth_deg + dx * AZIMUTH_DEG_PER_PX)
		Knob.FREQUENCY:
			var span := RadarReceiver.band_span(receiver.band)
			receiver.set_frequency_mhz(receiver.get_frequency_mhz() + dx * span * FREQUENCY_SPAN_PER_PX)
		Knob.BAND:
			_band_drag += dx
			if _band_drag > BAND_DRAG_PX:
				receiver.set_band(RadarReceiver.Band.UHF)
				_band_drag = 0.0
			elif _band_drag < -BAND_DRAG_PX:
				receiver.set_band(RadarReceiver.Band.VHF)
				_band_drag = 0.0


## Bouton sous la position de la souris (vue du jeu), NONE ailleurs.
func _knob_at(screen_pos: Vector2) -> Knob:
	var uv := _screen.plane_uv_at(_camera, screen_pos)
	if uv == StationScreen.NONE:
		return Knob.NONE
	var size := _screen.size_m()
	for knob: Knob in _knobs:
		var offset: Vector2 = (uv - _screen.uv_of((_knobs[knob] as Node3D).global_position)) * size
		if offset.length() <= KNOB_RADIUS_M:
			return knob
	return Knob.NONE


## Curseur « glisser » au survol d'un bouton.
func _set_hover(knob: Knob) -> void:
	if knob == _hover:
		return
	_hover = knob
	Input.set_default_cursor_shape(Input.CURSOR_HSIZE if knob != Knob.NONE else Input.CURSOR_ARROW)


## Pose des boutons d'après le réglage : rotation autour de leur axe (positive = antihoraire vue de face).
func _update_knobs(delta: float) -> void:
	if _knobs.is_empty():
		return
	var target := 0.0 if receiver.band == RadarReceiver.Band.VHF else deg_to_rad(-2.0 * BAND_DEG)
	_band_angle = target if delta <= 0.0 else lerpf(_band_angle, target, 1.0 - exp(-14.0 * delta))
	var span := RadarReceiver.band_span(receiver.band)
	var turns := (receiver.get_frequency_mhz() - RadarReceiver.band_min(receiver.band)) / span * FREQUENCY_TURNS
	var angles := {Knob.AZIMUTH: -deg_to_rad(receiver.azimuth_deg), Knob.FREQUENCY: -TAU * turns,
			Knob.BAND: _band_angle}
	for knob: Knob in _knobs:
		var rest: Transform3D = _knob_rest[knob]
		(_knobs[knob] as Node3D).transform = Transform3D(Basis(_knob_axis, angles[knob]) * rest.basis, rest.origin)
