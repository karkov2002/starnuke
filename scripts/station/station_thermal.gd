class_name StationThermal
extends RefCounted
## Radiateurs et chaleur de la station (composant de Station, scripts/station.gd, qui garde les signaux
## radiator_changed, heat_changed et les réglages exportés). Les 4 radiateurs (Station.RADIATOR_IDS) sont déployés au
## repos ; chacun est replié ou déployé en rejouant ses trois articulations depuis l'animation Retraction_Radiateurs
## (début = déployé, fin = replié), tous ensemble par l'animation complète s'ils sont dans le même état.
## Chaleur (préparation d'une jauge) : heat (0 à 1) monte quand les radiateurs sont repliés (mode furtif : pas de
## rayonnement infrarouge) et redescend quand ils sont déployés, en proportion des radiateurs déployés.

## Radiateur : pistes de ses articulations dans l'animation, état, mouvement en cours.
class Radiator:
	var tracks: Array[int] = []
	var is_deployed := true
	var tween: Tween

## Chaleur de la station (0 à 1).
var heat := 0.0

var _station: Station
var _anim: StationAnim
## id -> Radiator.
var _radiators := {}


func _init(station: Station, anim: StationAnim) -> void:
	_station = station
	_anim = anim
	var animation := anim.animation(Station.ANIM_RADIATORS)
	if animation == null:
		return
	for id in Station.RADIATOR_IDS:
		var radiator := Radiator.new()
		for t in animation.get_track_count():
			if String(animation.track_get_path(t)).begins_with(id + "/"):
				radiator.tracks.append(t)
		if not radiator.tracks.is_empty():
			_radiators[id] = radiator


## Chaleur : monte avec les radiateurs repliés, redescend avec les radiateurs déployés ; heat_changed sur changement.
func update(delta: float) -> void:
	if _radiators.is_empty():
		return
	var deployed := 0.0
	for id: String in _radiators:
		deployed += 1.0 if _radiators[id].is_deployed else 0.0
	var share := deployed / _radiators.size()
	var rate := _station.heat_rise_per_s * (1.0 - share) - _station.heat_fall_per_s * share
	var value := clampf(heat + rate * delta, 0.0, 1.0)
	if not is_equal_approx(value, heat):
		heat = value
		_station.heat_changed.emit(heat)


func radiator_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_radiators.keys())
	return ids


func is_radiator_deployed(id: String) -> bool:
	return _radiators.has(id) and _radiators[id].is_deployed


## Déploie ou replie un radiateur (ses trois articulations, rejouées depuis Retraction_Radiateurs).
func set_radiator_deployed(id: String, deployed: bool) -> bool:
	if not _radiators.has(id):
		return false
	var radiator: Radiator = _radiators[id]
	if radiator.is_deployed == deployed:
		return true
	if radiator.tween:
		radiator.tween.kill()
	var animation := _anim.animation(Station.ANIM_RADIATORS)
	# Retraction_Radiateurs : début = déployé, fin = replié.
	var from := 0.0 if deployed == false else animation.length
	var to := animation.length if deployed == false else 0.0
	radiator.tween = _anim.play_tracks(animation, radiator.tracks, from, to, animation.length)
	radiator.tween.tween_callback(func() -> void:
		radiator.tween = null
		radiator.is_deployed = deployed
		_station.radiator_changed.emit(id, deployed))
	return true


## Tous les radiateurs : animation complète s'ils sont tous dans le même état, sinon un par un.
func set_all_radiators_deployed(deployed: bool) -> void:
	var group := _radiators.keys().all(func(id: String) -> bool:
		return _radiators[id].is_deployed != deployed and _radiators[id].tween == null)
	if group:
		_anim.play_group(Station.ANIM_RADIATORS, deployed, func() -> void:
			for id: String in _radiators:
				_radiators[id].is_deployed = deployed
				_station.radiator_changed.emit(id, deployed))
	else:
		for id: String in _radiators:
			set_radiator_deployed(id, deployed)
