class_name NukeParams
extends Resource
## Paramètres d'une explosion : tout ce dont l'effet a besoin, le reste découle de la puissance (NukeScaling).

## Puissance (kt).
@export_range(10.0, 50000.0, 1.0, "exp", "suffix:kt") var yield_kt := 1000.0
## Point d'impact (degrés ; longitude positive vers l'est).
@export_range(-90.0, 90.0, 0.01, "suffix:°") var latitude_deg := 0.0
@export_range(-180.0, 180.0, 0.01, "suffix:°") var longitude_deg := 0.0
## Direction d'où vient le vent (convention météo : 0 = vent du nord, 90 = vent d'est). Tirée au hasard à la
## création ; NukeLauncher la remplace par le vent réel GFS au point d'impact (NukeWind).
@export_range(0.0, 360.0, 0.1, "suffix:°") var wind_direction_deg := 0.0
## Vitesse du vent (m/s).
@export_range(0.0, 100.0, 0.1, "suffix:m/s") var wind_speed_m_s := 10.0
## Profil vertical du vent (vent réel GFS, NukeWind.sample_profile) : Vector3(altitude km, vent vers l'est, vent vers
## le nord en m/s), d'altitude croissante. Vide : le vent ci-dessus à toutes les altitudes.
@export var wind_profile := PackedVector3Array()
## Instant de l'explosion sur l'horloge des explosions (NukeClock.time_s).
@export var start_time_s := 0.0
## Hauteur d'explosion (0 = au sol).
@export_range(0.0, 50.0, 0.01, "suffix:km") var burst_height_km := 0.0


func _init() -> void:
	wind_direction_deg = randf() * 360.0


## Vent (m/s, x = vers l'est, y = vers le nord) à l'altitude donnée : interpolé linéairement dans wind_profile,
## constant sous son premier niveau et au-dessus du dernier.
func wind_at(height_km: float) -> Vector2:
	var n := wind_profile.size()
	if n == 0:
		var from := deg_to_rad(wind_direction_deg)
		return -Vector2(sin(from), cos(from)) * wind_speed_m_s
	var below := wind_profile[0]
	if height_km <= below.x:
		return Vector2(below.y, below.z)
	for i in range(1, n):
		var above := wind_profile[i]
		if height_km <= above.x:
			var f := (height_km - below.x) / maxf(above.x - below.x, 1e-3)
			return Vector2(lerpf(below.y, above.y, f), lerpf(below.z, above.z, f))
		below = above
	return Vector2(below.y, below.z)
