extends Node
## Horloge des explosions (autoload NukeClock), distincte du temps réel.
##
## - time_s avance au rythme du temps de l'orbite (Orbit.time_scale : Pause, x2… x16 s'appliquent aussi aux
##   explosions), multiplié par acceleration. Sans orbite liée (cf. NukeLauncher), seul acceleration compte.
## - physical_time() convertit le temps écoulé depuis une explosion en temps « physique » de l'effet : les phases
##   rapides (flash, boule de feu, onde de choc) défilent en temps réel pendant realtime_phase_s, puis la vitesse du
##   temps physique monte progressivement (smoothstep) jusqu'à slow_phase_acceleration sur ramp_s, pour les phases
##   lentes (montée et étalement du champignon, ~10 min). La rampe évite un saut de vitesse : un effet encore en cours
##   à la fin de la phase en temps réel (anneau de condensation d'une forte puissance) ne se met pas à filer d'un coup.

## Facteur d'accélération global des explosions.
@export var acceleration := 1.0
## Durée (temps de l'horloge) jouée en temps réel après l'explosion.
@export var realtime_phase_s := 20.0
## Durée (temps de l'horloge) de la montée progressive de la vitesse, après realtime_phase_s.
@export var ramp_s := 40.0
## Accélération des phases lentes, atteinte à la fin de la rampe.
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


## Conversion d'une durée d'horloge en durée physique : intégrale de la vitesse 1 + (A − 1) · smoothstep(x), x allant
## de 0 à 1 sur la rampe (primitive de smoothstep : x³ − x⁴ / 2), puis A au-delà.
func to_physical(clock_elapsed_s: float) -> float:
	var t := maxf(clock_elapsed_s, 0.0)
	if t <= realtime_phase_s:
		return t
	var x := minf((t - realtime_phase_s) / ramp_s, 1.0)
	var ramp := ramp_s * (x * x * x - 0.5 * x * x * x * x)
	var after := maxf(t - realtime_phase_s - ramp_s, 0.0)
	return t + (slow_phase_acceleration - 1.0) * (ramp + after)


## Réciproque de to_physical (par dichotomie : to_physical est croissante et to_physical(t) ≥ t).
func to_clock(physical_s: float) -> float:
	var target := maxf(physical_s, 0.0)
	if target <= realtime_phase_s:
		return target
	var low := realtime_phase_s
	var high := target
	for i in 40:
		var mid := 0.5 * (low + high)
		if to_physical(mid) < target:
			low = mid
		else:
			high = mid
	return 0.5 * (low + high)
