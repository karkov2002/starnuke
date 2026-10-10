class_name NukeShock
extends Node3D
## Traces visibles de l'onde de choc au sol (scène nuke/nuke_shock.tscn, enfant d'une NukeEffect ; repère local en
## km, Y = verticale). Le front de choc lui-même est invisible une fois détaché de la boule de feu : on voit l'anneau
## de condensation (nuage de Wilson) qui le suit brièvement, et la poussière qu'il soulève au sol.
##
## Rayon du front r(t) = R_max · (1 − exp(−t / τ)) : il décélère naturellement (NukeScaling.shock_max_radius_km,
## shock_tau_s). Avec la progression p = r / R_max :
## - condensation : apparaît vers condensation_start, culmine à condensation_peak, s'évapore à condensation_end ;
##   front qui s'amincit de start_width à end_width (part de R_max) ;
## - poussière : jupe autour du point zéro, soulevée par le front dès dust_start, qui s'étend avec lui jusqu'à
##   dust_max (part de R_max), reste en place puis retombe (constante de temps dust_fade_tau × τ) ; seulement pour une
##   explosion basse (hauteur < ~2 rayons de boule de feu). Sur la mer (NukeParams.over_ocean), ce sont des embruns
##   (eau pulvérisée) : même jupe, blanche.
## Dessin : nuke/shaders/nuke_shock_ring.gdshader sur un quad horizontal légèrement surélevé (lift_km).

@export_group("Condensation")
@export var condensation_opacity := 0.8
@export var condensation_start := 0.03
@export var condensation_peak := 0.12
@export var condensation_end := 0.5
## Épaisseur du front, en part de R_max, au départ et à la fin.
@export var start_width := 0.05
@export var end_width := 0.012
@export_group("Poussière")
@export var dust_opacity := 1.0
@export var dust_start := 0.05
## Rayon maximal de la jupe de poussière, en part de R_max.
@export var dust_max := 0.6
## Durée de retombée de la poussière, en multiples de τ.
@export var dust_fade_tau := 8.0
@export_group("")
## Hauteur du quad au-dessus du sol (km), contre le z-fighting.
@export var lift_km := 0.03

var _effect: NukeEffect

@onready var _ring: MeshInstance3D = $Ring


func _ready() -> void:
	_effect = get_parent() as NukeEffect
	_update()


func _process(_delta: float) -> void:
	_update()


## Progression p = r / R_max (0 avant l'explosion).
func get_progress() -> float:
	var w := _effect.params.yield_kt
	return NukeScaling.shock_front_radius_km(w, _effect.get_time_s()) / NukeScaling.shock_max_radius_km(w)


func _update() -> void:
	if _effect == null or _effect.params == null:
		return
	var params := _effect.params
	var tau := NukeScaling.shock_tau_s(params.yield_kt)
	var t := _effect.get_time_s()
	var p := get_progress()
	var condensation := condensation_opacity * smoothstep(condensation_start, condensation_peak, p) \
			* (1.0 - smoothstep(condensation_peak, condensation_end, p))
	var low_burst := NukeScaling.low_burst(params.yield_kt, params.burst_height_km)
	var dust := dust_opacity * low_burst * smoothstep(dust_start, dust_start + 0.1, p) * exp(-t / (dust_fade_tau * tau))
	_ring.visible = condensation > 0.002 or dust > 0.002
	if not _ring.visible:
		return
	var r_max := NukeScaling.shock_max_radius_km(params.yield_kt)
	var radius := r_max * p
	var width := r_max * lerpf(start_width, end_width, p)
	# Le quad couvre le front et son dégradé extérieur.
	var extent := radius + 8.0 * width + 0.05
	_ring.position = Vector3(0.0, lift_km, 0.0)
	_ring.scale = Vector3(extent, 1.0, extent)
	_ring.set_instance_shader_parameter("radius_km", radius)
	_ring.set_instance_shader_parameter("extent_km", extent)
	_ring.set_instance_shader_parameter("front_width_km", width)
	_ring.set_instance_shader_parameter("condensation", condensation)
	_ring.set_instance_shader_parameter("dust", dust)
	_ring.set_instance_shader_parameter("spray", 1.0 if params.over_ocean else 0.0)
	_ring.set_instance_shader_parameter("dust_max_km", r_max * dust_max)
