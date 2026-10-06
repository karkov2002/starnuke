class_name NukeShock
extends Node3D
## Onde de choc au sol (scène nuke/nuke_shock.tscn, enfant d'une NukeEffect ; repère local en km, Y = verticale).
##
## Rayon r(t) = R_max · (1 − exp(−t / τ)) : le front décélère naturellement (NukeScaling.shock_max_radius_km,
## shock_tau_s). Avec la progression p = r / R_max :
## - apparition sur les premiers pourcents (le front sort de la boule de feu) ;
## - épaisseur qui s'amincit de start_width à end_width (part de R_max) ;
## - intensité qui décroît en sqrt(1 − p), puis fondu de fade_start à fade_end, où l'anneau disparaît.
## Dessin : nuke/shaders/nuke_shock_ring.gdshader sur un quad horizontal légèrement surélevé (lift_km).

## Intensité HDR du front au départ.
@export var start_intensity := 10.0
## Épaisseur du front, en part de R_max, au départ et à la fin.
@export var start_width := 0.05
@export var end_width := 0.012
## Fondu de sortie (progression p) ; l'anneau disparaît à fade_end.
@export var fade_start := 0.75
@export var fade_end := 0.98
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
	var t := _effect.get_time_s()
	return 1.0 - exp(-maxf(t, 0.0) / NukeScaling.shock_tau_s(_effect.params.yield_kt))


func _update() -> void:
	if _effect == null or _effect.params == null:
		return
	var p := get_progress()
	_ring.visible = p > 0.0 and p < fade_end
	if not _ring.visible:
		return
	var r_max := NukeScaling.shock_max_radius_km(_effect.params.yield_kt)
	var radius := r_max * p
	var width := r_max * lerpf(start_width, end_width, p)
	var intensity := start_intensity * sqrt(1.0 - p) * smoothstep(0.0, 0.03, p) \
			* (1.0 - smoothstep(fade_start, fade_end, p))
	# Le quad couvre le front, son dégradé extérieur et le second anneau.
	var extent := radius + 8.0 * width + 0.05
	_ring.position = Vector3(0.0, lift_km, 0.0)
	_ring.scale = Vector3(extent, 1.0, extent)
	_ring.set_instance_shader_parameter("radius_km", radius)
	_ring.set_instance_shader_parameter("extent_km", extent)
	_ring.set_instance_shader_parameter("front_width_km", width)
	_ring.set_instance_shader_parameter("intensity", intensity)
