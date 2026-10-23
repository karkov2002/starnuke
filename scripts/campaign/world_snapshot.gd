class_name WorldSnapshot
extends RefCounted
## Monde d'une partie de campagne, capturé pour la sauvegarde au coucher et recréé au « Continuer »
## (CampaignDirector) : orbite au moment de la capture (heure UTC, altitude, inclinaison, point survolé, sens de
## passage), explosions (point, puissance, âge sur l'horloge des explosions, heure UTC), photos et cibles au sol.
## Seule classe à connaître la forme de sauvegarde de ces nœuds (OrbitSimulation, NukeLauncher, PhotoArchive,
## GroundTarget) ; un nœud absent (null) est ignoré à la capture comme à la restauration.

var _orbit: OrbitSimulation
var _launcher: NukeLauncher
var _photos: PhotoArchive
var _targets: GroundTarget


func _init(orbit: OrbitSimulation, launcher: NukeLauncher, photos: PhotoArchive, targets: GroundTarget) -> void:
	_orbit = orbit
	_launcher = launcher
	_photos = photos
	_targets = targets


## Monde à sauvegarder : {orbit, detonations, photos, targets} (clés absentes pour les nœuds manquants).
func capture() -> Dictionary:
	var world := {}
	if _orbit:
		var point := _orbit.get_subsatellite_point()
		world.orbit = {"utc": _orbit.get_utc_unix_s(), "altitude_km": _orbit.altitude_km,
				"inclination_deg": _orbit.inclination_deg, "lat": point.x, "lon": point.y,
				"ascending": _orbit.is_ascending()}
	if _launcher:
		world.detonations = []
		for effect in _launcher.get_effects():
			var p := effect.params
			if p:
				world.detonations.append({"lat": p.latitude_deg, "lon": p.longitude_deg, "yield_kt": p.yield_kt,
						"clock_age_s": NukeClock.time_s - p.start_time_s, "utc": p.detonation_utc_s})
	if _photos:
		world.photos = _photos.to_save()
	if _targets:
		world.targets = _targets.to_save()
	return world


## Recrée le monde d'une sauvegarde (capture) : orbite, explosions avec leur âge (marquées restored : pas un tir),
## photos, cibles.
func restore(world: Dictionary) -> void:
	var orbit: Dictionary = world.get("orbit", {})
	if _orbit and not orbit.is_empty():
		_orbit.place(float(orbit.utc), float(orbit.altitude_km), float(orbit.inclination_deg), float(orbit.lat),
				float(orbit.lon), bool(orbit.ascending))
	if _launcher:
		for d: Dictionary in world.get("detonations", []):
			_launcher.restore_at(float(d.lat), float(d.lon), float(d.yield_kt), float(d.clock_age_s), float(d.utc))
	if _photos and world.has("photos"):
		_photos.restore(world.photos)
	if _targets and world.has("targets"):
		_targets.restore(world.targets)
