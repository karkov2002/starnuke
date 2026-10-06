class_name NukeParams
extends Resource
## Paramètres d'une explosion : tout ce dont l'effet a besoin, le reste découle de la puissance (NukeScaling).

## Puissance (kt).
@export_range(10.0, 50000.0, 1.0, "exp", "suffix:kt") var yield_kt := 1000.0
## Point d'impact (degrés ; longitude positive vers l'est).
@export_range(-90.0, 90.0, 0.01, "suffix:°") var latitude_deg := 0.0
@export_range(-180.0, 180.0, 0.01, "suffix:°") var longitude_deg := 0.0
## Direction d'où vient le vent (convention météo : 0 = vent du nord, 90 = vent d'est). Tirée au hasard à la
## création.
@export_range(0.0, 360.0, 0.1, "suffix:°") var wind_direction_deg := 0.0
## Instant de l'explosion sur l'horloge des explosions (NukeClock.time_s).
@export var start_time_s := 0.0
## Hauteur d'explosion (0 = au sol).
@export_range(0.0, 50.0, 0.01, "suffix:km") var burst_height_km := 0.0


func _init() -> void:
	wind_direction_deg = randf() * 360.0
