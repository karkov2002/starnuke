class_name NukeFlash
extends Node3D
## Flash initial d'une explosion (scène nuke/nuke_flash.tscn, enfant d'une NukeEffect ; repère local en km).
##
## Sur la durée du flash (NukeScaling.flash_duration_s = 10 t_max : ~1,2 s à 10 kt, ~8,7 s à 1 Mt, ~49 s à 50 Mt), en
## temps normalisé u = t / durée (lues avec sample() : la version précalculée, à 100 points, effacerait le premier
## pic) :
## - intensity_curve : part du flux au pic (NukeScaling.flash_peak_flux_sun) ; forme de l'impulsion thermique de
##   Glasstone & Dolan : bref premier pic (u = 0,002), minimum (u ≈ 0,009, t_min), second maximum à t_max (u = 0,1),
##   puis 0,55 à 2 t_max, 0,3 à 3 t_max, 0,12 à 5 t_max, 0,05 à 7 t_max ;
## - growth_curve : rayon de la boule de feu, en part de NukeScaling.fireball_radius_km (45 % à t_min, 90 % à t_max,
##   100 % à 3 t_max).
## Tangentes des courbes : pente entre les points voisins (nulle aux extrema), pour éviter les paliers.
## Il affiche la boule de feu (sphère additive, luminance physique : flux / angle solide) et l'éblouissement
## (billboard, taille et intensité selon le flux reçu par l'observateur). La lumière projetée sur le sol, les nuages
## et la station, et les effets d'écran sont gérés globalement par NukeFlashFX, qui lit flux_ref et get_light_position().

@export var intensity_curve: Curve
@export var growth_curve: Curve
## Rayon minimal affiché de la boule de feu, en pixels (évite le scintillement des boules de feu sous-pixel).
@export var min_fireball_pixels := 1.5
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


## Flux reçu (soleils) en un point de la scène (coordonnées globales) : 1/d² en km × transmittance de l'air sur le
## trajet (NukeAtmosphere), nul si la Terre s'interpose.
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
	var to_planet_km := earth.global_transform.affine_inverse()
	var air := NukeAtmosphere.luminance_transmittance(to_planet_km * source / OrbitSimulation.SCENE_UNITS_PER_KM,
			to_planet_km * at / OrbitSimulation.SCENE_UNITS_PER_KM)
	return flux_ref * pow(NukeScaling.FLASH_REF_DISTANCE_KM / distance_km, 2.0) * air


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
	flux_ref = NukeScaling.flash_peak_flux_sun(w) * maxf(intensity_curve.sample(u), 0.0)
	radius_km = NukeScaling.fireball_radius_km(w) * maxf(growth_curve.sample(u), 0.01)

	var camera := get_viewport().get_camera_3d()
	_fireball.visible = flux_ref > 0.0
	_fireball.position = Vector3(0.0, _effect.params.burst_height_km, 0.0)
	# Rayon affiché au moins égal à min_fireball_pixels : une sphère plus petite qu'un pixel (10–100 kt depuis 400 km)
	# apparaît ou disparaît selon qu'elle couvre le centre d'un pixel, et clignote en défilant sous la station. La
	# luminance est calculée sur le rayon affiché (flux / surface), donc le flux total reste exact.
	var drawn_km := radius_km
	if camera:
		var pixel_rad := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) / get_viewport().get_visible_rect().size.y
		var distance_km := (_fireball.global_position - camera.global_position).length() / OrbitSimulation.SCENE_UNITS_PER_KM
		drawn_km = maxf(radius_km, min_fireball_pixels * pixel_rad * distance_km)
	_fireball.scale = Vector3.ONE * drawn_km
	_fireball.set_instance_shader_parameter("radiance", NukeScaling.fireball_radiance_hdr(flux_ref, drawn_km))

	var received := received_flux(camera.global_position) if camera else 0.0
	_flare.visible = received > 1e-4
	if _flare.visible:
		_flare.position = get_light_position()
		_flare.set_instance_shader_parameter("flare_intensity", flare_gain * received)
		_flare.set_instance_shader_parameter("flare_radius_rad",
				clampf(flare_size_rad * pow(received, flare_size_exp), flare_min_rad, flare_max_rad))
