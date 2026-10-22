class_name StationSolarPanels
extends RefCounted
## Suivi du soleil par les panneaux solaires (composant de Station, scripts/station.gd, qui garde les réglages
## exportés). Les 4 pivots Pivot_Panneau_* tournent autour de leur axe (Z du modèle) pour présenter la face des
## cellules au soleil : n(θ) = (−sin θ, cos θ) dans le plan XY de la station suit la projection du soleil, mais reste
## au-dessus de l'horizon local (n · zénith ≥ sin(marge)) : si le soleil est sous l'horizon, elle s'arrête à la
## limite (règle de furtivité : la face des cellules n'est jamais tournée vers la Terre). Même angle pour les 4
## panneaux (même axe, même soleil), vitesse bornée (panel_max_speed_deg), placement direct à la première image.

var _station: Station
var _sun: Node3D
var _earth: Node3D
var _pivots: Array[Node3D] = []
## Angle courant (radians autour de Z) ; NAN avant la première image.
var _angle := NAN


## sun : lumière directionnelle (son axe Z pointe vers le soleil) ; earth : centre de la Terre (zénith local).
func _init(station: Station, sun: Node3D, earth: Node3D) -> void:
	_station = station
	_sun = sun
	_earth = earth
	_pivots.assign(station.find_children("Pivot_Panneau_*", "Node3D", false, false))


func update(delta: float) -> void:
	if _sun == null or _pivots.is_empty():
		return
	var inverse := _station.global_basis.inverse()
	var sun_dir := inverse * _sun.global_basis.z
	var zenith := inverse * (_station.global_position - _earth.global_position) if _earth else Vector3.UP
	var target := Vector2(sun_dir.x, sun_dir.y)
	var up := Vector2(zenith.x, zenith.y)
	if up.length() < 1e-4:
		return
	up = up.normalized()
	if target.length() < 1e-4:
		target = up
	target = target.normalized()
	# Angle limite autour du zénith projeté : la face peut s'écarter de 90° − marge du zénith au plus.
	var max_tilt := deg_to_rad(90.0 - _station.panel_horizon_margin_deg)
	var offset := clampf(up.angle_to(target), -max_tilt, max_tilt)
	var wanted := _normal_angle(up.rotated(offset))
	if is_nan(_angle):
		_angle = wanted
	else:
		var step := deg_to_rad(_station.panel_max_speed_deg) * delta
		_angle += clampf(angle_difference(_angle, wanted), -step, step)
	for pivot in _pivots:
		pivot.quaternion = Quaternion(Vector3.BACK, _angle)


## Angle θ autour de +Z tel que la normale (−sin θ, cos θ) vaut n.
static func _normal_angle(n: Vector2) -> float:
	return atan2(-n.x, n.y)
