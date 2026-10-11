extends Node
## Horloge des explosions (autoload NukeClock), distincte du temps réel.
##
## - time_s avance au rythme du temps de l'orbite (Orbit.time_scale : Pause, x2… x16 s'appliquent aussi aux
##   explosions), multiplié par acceleration. Sans orbite liée (cf. NukeLauncher), seul acceleration compte.
## - physical_time() convertit le temps écoulé depuis une explosion en temps « physique » de l'effet : les phases
##   rapides (flash, boule de feu, onde de choc) défilent en temps réel pendant realtime_phase_s, puis la vitesse du
##   temps physique monte progressivement (smoothstep) jusqu'à slow_phase_acceleration sur ramp_s, pour la montée du
##   champignon (~10 min), et redescend de la même façon jusqu'à 1 quand slow_phase_end_s de temps physique sont
##   écoulés : ensuite, l'explosion vit au rythme du jeu (incendies sur plusieurs jours, dissipation du champignon sur
##   des heures), avec une avance fixe (late_offset_s). Les rampes évitent les sauts de vitesse : un effet encore en
##   cours à la fin de la phase en temps réel (anneau de condensation d'une forte puissance) ne se met pas à filer
##   d'un coup.

## Facteur d'accélération global des explosions.
@export var acceleration := 1.0
## Durée (temps de l'horloge) jouée en temps réel après l'explosion.
@export var realtime_phase_s := 20.0
## Durée (temps de l'horloge) de chaque rampe de vitesse (montée après realtime_phase_s, puis descente).
@export var ramp_s := 40.0
## Accélération des phases lentes, atteinte à la fin de la rampe.
@export var slow_phase_acceleration := 10.0
## Temps physique (s) au-delà duquel la vitesse redescend vers 1 (temps du jeu) : après la montée du champignon
## (NukeScaling.MUSHROOM_RISE_S) et la fermeture des trous dans les nuages (NukeCloudFX.recovery_s).
@export var slow_phase_end_s := 1800.0

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


## Durée d'horloge (s) passée à pleine accélération, entre les deux rampes.
func hold_clock_s() -> float:
	var physical_before := realtime_phase_s + ramp_s * (1.0 + 0.5 * (slow_phase_acceleration - 1.0))
	return maxf(slow_phase_end_s - physical_before, 0.0) / slow_phase_acceleration


## Avance du temps physique sur l'horloge une fois la vitesse revenue à 1 (s ; 1 764 s avec les réglages par défaut).
func late_offset_s() -> float:
	return (slow_phase_acceleration - 1.0) * (ramp_s + hold_clock_s())


## Conversion d'une durée d'horloge en durée physique : intégrale de la vitesse 1 + (A − 1) · e(t), où e monte de 0 à 1
## sur la première rampe (smoothstep, primitive x³ − x⁴ / 2), reste à 1, puis redescend à 0 sur la seconde.
func to_physical(clock_elapsed_s: float) -> float:
	var t := maxf(clock_elapsed_s, 0.0)
	if t <= realtime_phase_s:
		return t
	var up_end := realtime_phase_s + ramp_s
	var down_start := up_end + hold_clock_s()
	var x := minf((t - realtime_phase_s) / ramp_s, 1.0)
	var y := clampf((t - down_start) / ramp_s, 0.0, 1.0)
	var excess := ramp_s * _smoothstep_integral(x) + clampf(t - up_end, 0.0, down_start - up_end) \
			+ ramp_s * (y - _smoothstep_integral(y))
	return t + (slow_phase_acceleration - 1.0) * excess


## Réciproque de to_physical (par dichotomie : to_physical est croissante et to_physical(t) ≥ t).
func to_clock(physical_s: float) -> float:
	var target := maxf(physical_s, 0.0)
	if target <= realtime_phase_s:
		return target
	var low := realtime_phase_s
	var high := target
	for i in 50:
		var mid := 0.5 * (low + high)
		if to_physical(mid) < target:
			low = mid
		else:
			high = mid
	return 0.5 * (low + high)


## Primitive de smoothstep sur [0, x] : x³ − x⁴ / 2 (0,5 en x = 1).
static func _smoothstep_integral(x: float) -> float:
	return x * x * x - 0.5 * x * x * x * x
