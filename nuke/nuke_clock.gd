extends Node
## Horloge des explosions (autoload NukeClock), distincte du temps réel.
##
## - time_s avance au rythme du temps de l'orbite (Orbit.time_scale : Pause, x2… x16 s'appliquent aussi aux
##   explosions), multiplié par acceleration. Sans orbite liée (cf. NukeLauncher), seul acceleration compte.
## - physical_time() convertit le temps écoulé depuis une explosion en temps « physique » de l'effet : les phases
##   rapides (flash, boule de feu, onde de choc) défilent en temps réel pendant realtime_phase_s, les phases lentes
##   (montée et étalement du champignon, ~10 min) sont ensuite accélérées de slow_phase_acceleration.

## Facteur d'accélération global des explosions.
@export var acceleration := 1.0
## Durée (temps de l'horloge) jouée en temps réel après l'explosion.
@export var realtime_phase_s := 20.0
## Accélération des phases lentes, au-delà de realtime_phase_s.
@export var slow_phase_acceleration := 10.0

var time_s := 0.0
## Orbite dont on suit l'accélération du temps.
var orbit: OrbitSimulation


func _process(delta: float) -> void:
	var scale := acceleration
	if is_instance_valid(orbit):
		scale *= orbit.time_scale
	time_s += delta * scale


## Temps physique (s) écoulé depuis l'instant since_s de l'horloge.
func physical_time(since_s: float) -> float:
	return to_physical(time_s - since_s)


## Conversion d'une durée d'horloge en durée physique (et réciproque).
func to_physical(clock_elapsed_s: float) -> float:
	var t := maxf(clock_elapsed_s, 0.0)
	if t <= realtime_phase_s:
		return t
	return realtime_phase_s + (t - realtime_phase_s) * slow_phase_acceleration


func to_clock(physical_s: float) -> float:
	var t := maxf(physical_s, 0.0)
	if t <= realtime_phase_s:
		return t
	return realtime_phase_s + (t - realtime_phase_s) / slow_phase_acceleration
