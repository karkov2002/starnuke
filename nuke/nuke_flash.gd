class_name NukeFlash
extends Node3D
## Flash initial d'une explosion (scène nuke/nuke_flash.tscn, enfant d'une NukeEffect ; repère local en km).
##
## Sur la durée du flash (NukeScaling.flash_duration_s, ~2 s), en temps normalisé u = t / durée :
## - intensity_curve : part du flux au pic (NukeScaling.flash_peak_flux_sun) ; forme du double pic thermique
##   (bref premier pic, creux, second maximum, décroissance) ;
## - growth_curve : rayon de la boule de feu, en part de NukeScaling.fireball_radius_km.
## Il affiche la boule de feu (sphère additive, luminance physique : flux / angle solide) et l'éblouissement
## (billboard, taille et intensité selon le flux reçu par l'observateur). La lumière projetée sur le sol, les nuages
## et la station, et les effets d'écran sont gérés globalement par NukeFlashFX, qui lit flux_ref et get_light_position().

@export var intensity_curve: Curve
@export var growth_curve: Curve
@export_group("Éblouissement")
## Intensité HDR du cœur pour un flux reçu de 1 soleil.
@export var flare_gain := 600.0
## Rayon angulaire du halo pour un flux reçu de 1 soleil (rad), exposant, bornes.
@export var flare_size_rad := 0.12
@export var flare_size_exp := 0.35
@export var flare_min_rad := 0.008
@export var flare_max_rad := 0.4

## Flux courant à NukeScaling.FLASH_REF_DISTANCE_KM (soleils) ; 0 hors du flash.
var flux_ref := 0.0
## Rayon courant de la boule de feu (km).
var radius_km := 0.0

var _effect: NukeEffect

@onready var _fireball: MeshInstance3D = $Fireball
@onready var _flare: MeshInstance3D = $Flare


func _ready() -> void:
	_effect = get_parent() as NukeEffect
	_update()


func _process(_delta: float) -> void:
	_update()


## Point d'émission de la lumière (repère local de l'effet, km) : au-dessus du centre de la boule de feu, pour qu'une
## explosion au sol éclaire quand même le terrain autour.
func get_light_position() -> Vector3:
	return Vector3(0.0, _effect.params.burst_height_km + radius_km * 0.5 + 0.05, 0.0)


## Flux reçu (soleils) en un point de la scène (coordonnées globales) : 1/d² en km, nul si la Terre s'interpose.
func received_flux(at: Vector3) -> float:
	if flux_ref <= 0.0:
		return 0.0
	var source := global_transform * get_light_position()
	var earth := _effect.get_parent() as Node3D
	var radius := OrbitSimulation.EARTH_RADIUS_KM * OrbitSimulation.SCENE_UNITS_PER_KM
	var to := source - at
	var length := to.length()
	var direction := to / length
	var oc := at - earth.global_position
	var b := oc.dot(direction)
	var discriminant := b * b - (oc.length_squared() - radius * radius)
	if discriminant > 0.0:
		var t := -b - sqrt(discriminant)
		if t > 0.0 and t < length * 0.9999:
			return 0.0
	var distance_km := length / OrbitSimulation.SCENE_UNITS_PER_KM
	return flux_ref * pow(NukeScaling.FLASH_REF_DISTANCE_KM / distance_km, 2.0)


func _update() -> void:
	if _effect == null or _effect.params == null:
		return
	var w := _effect.params.yield_kt
	var u := _effect.get_time_s() / NukeScaling.flash_duration_s(w)
	if u >= 1.0:
		flux_ref = 0.0
		_fireball.visible = false
		_flare.visible = false
		return
	flux_ref = NukeScaling.flash_peak_flux_sun(w) * maxf(intensity_curve.sample_baked(u), 0.0)
	radius_km = NukeScaling.fireball_radius_km(w) * maxf(growth_curve.sample_baked(u), 0.01)

	_fireball.visible = flux_ref > 0.0
	_fireball.position = Vector3(0.0, _effect.params.burst_height_km, 0.0)
	_fireball.scale = Vector3.ONE * radius_km
	_fireball.set_instance_shader_parameter("radiance", NukeScaling.fireball_radiance_hdr(flux_ref, radius_km))

	var camera := get_viewport().get_camera_3d()
	var received := received_flux(camera.global_position) if camera else 0.0
	_flare.visible = received > 1e-4
	if _flare.visible:
		_flare.position = get_light_position()
		_flare.set_instance_shader_parameter("flare_intensity", flare_gain * received)
		_flare.set_instance_shader_parameter("flare_radius_rad",
				clampf(flare_size_rad * pow(received, flare_size_exp), flare_min_rad, flare_max_rad))
