class_name NukeScaling
extends RefCounted
## Lois d'échelle des explosions en fonction de la puissance W (kt). Toutes les tailles de l'effet en découlent :
## une seule animation, paramétrée par la puissance. Les coefficients sont en tête de fichier pour les régler.
##
##   rayon de la boule de feu  = FIREBALL_COEF_KM · W^FIREBALL_EXP              (1 Mt : ~1,05 km)
##   rayon de choc de référence = SHOCK_REF_KM · (W / REF_YIELD_KT)^(1/3)      (similitude de Hopkinson-Cranz)
##   sommet du nuage            = CLOUD_TOP_REF_KM · (W / REF_YIELD_KT)^CLOUD_TOP_EXP   (50 Mt : ~65 km, Tsar Bomba)
##   rayon du chapeau           = CAP_RADIUS_PER_TOP · sommet du nuage

const MIN_YIELD_KT := 10.0
const MAX_YIELD_KT := 50000.0
const REF_YIELD_KT := 10.0

const FIREBALL_COEF_KM := 0.066
const FIREBALL_EXP := 0.4
const SHOCK_REF_KM := 2.0
const SHOCK_EXP := 1.0 / 3.0
const CLOUD_TOP_REF_KM := 10.0
const CLOUD_TOP_EXP := 0.22
const CAP_RADIUS_PER_TOP := 0.6

# Onde de choc au sol : rayon r(t) = R_max · (1 − exp(−t / τ)), R_max = rayon de choc de référence × facteur visuel.
# τ est proportionnel à R_max : le front atteint 90 % de R_max (t = 2,3 τ) à ~0,34 km/s de moyenne, la vitesse du
# son ; sa vitesse initiale R_max / τ vaut ~0,8 km/s (Mach 2,3). Durée totale (disparition à 98 %) : 3,9 τ, soit
# ~10 s à 10 kt, ~46 s à 1 Mt, ~170 s à 50 Mt.
const SHOCK_VISUAL_SCALE := 1.0
const SHOCK_TAU_S_PER_KM := 1.28

# Incendies allumés par le flash : rayon où l'exposition thermique dépasse ~10 cal/cm² (inflammation des matériaux
# courants, Glasstone & Dolan ch. VII ; ~12 km pour 1 Mt avec l'absorption de l'air), ∝ W^0,41 (entre la loi en W^0,5
# du vide et l'absorption croissante avec la distance) : ~1,8 km à 10 kt, ~60 km à 50 Mt.
# Évolution : premiers foyers dès le flash (FIRE_FIRST_SHARE), incendie généralisé en ~2 min, extension lente
# (+FIRE_SPREAD du rayon en ~30 min), extinction en quelques heures.
const FIRE_RADIUS_1MT_KM := 12.0
const FIRE_RADIUS_EXP := 0.41
const FIRE_FIRST_SHARE := 0.3
const FIRE_GROWTH_S := 120.0
const FIRE_SPREAD := 0.15
const FIRE_SPREAD_S := 1800.0
const FIRE_BURN_S := 10800.0

# Flash initial. Puissance thermique au second maximum (Glasstone & Dolan, The Effects of Nuclear Weapons, §7.88,
# explosion dans l'air) : P_max = 4 · W^0,56 kt/s. Pour 1 Mt : 8·10¹⁴ W, soit ~400 W/m² à 400 km (0,29 soleil) avant
# l'absorption par l'atmosphère (NukeAtmosphere et nuke/shaders/nuke_flash.gdshaderinc).
## Distance de référence des flux (km) : l'orbite nominale.
const FLASH_REF_DISTANCE_KM := 400.0
const FLASH_PEAK_POWER_COEF_KT_S := 4.0
const FLASH_FLUX_EXP := 0.56
const KILOTON_J := 4.184e12
## Éclairement solaire hors atmosphère (W/m²) : l'unité « soleil » des flux.
const SOLAR_CONSTANT_W_M2 := 1361.0
## Durée du flash pour 1 Mt (s, temps physique), et exposant : 10 kt ≈ 1,3 s, 50 Mt ≈ 3 s.
const FLASH_DURATION_1MT_S := 2.0
const FLASH_DURATION_EXP := 0.1
# Luminance de la boule de feu : celle du disque solaire (sun_disc_energy de space_sky.gdshader) × le rapport des
# luminances, plafonnée sous le maximum du format flottant 16 bits du rendu.
const SUN_DISC_HDR := 40000.0
const SUN_ANGULAR_RADIUS_RAD := 0.0046531
const FIREBALL_MAX_HDR := 50000.0


static func fireball_radius_km(yield_kt: float) -> float:
	return FIREBALL_COEF_KM * pow(_clamp_yield(yield_kt), FIREBALL_EXP)


static func shock_radius_km(yield_kt: float) -> float:
	return SHOCK_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, SHOCK_EXP)


## Rayon final de l'anneau de choc affiché (km).
static func shock_max_radius_km(yield_kt: float) -> float:
	return SHOCK_VISUAL_SCALE * shock_radius_km(yield_kt)


## Constante de temps de l'expansion de l'anneau de choc (s, temps physique).
static func shock_tau_s(yield_kt: float) -> float:
	return SHOCK_TAU_S_PER_KM * shock_radius_km(yield_kt)


## Rayon de la zone en feu (km) au temps t (s, physique).
static func fire_radius_km(yield_kt: float, t: float) -> float:
	var base := FIRE_RADIUS_1MT_KM * pow(_clamp_yield(yield_kt) / 1000.0, FIRE_RADIUS_EXP)
	return base * (1.0 + FIRE_SPREAD * (1.0 - exp(-maxf(t, 0.0) / FIRE_SPREAD_S)))


## Intensité des incendies (0 à 1) au temps t (s, physique).
static func fire_intensity(t: float) -> float:
	if t <= 0.0:
		return 0.0
	var growth := FIRE_FIRST_SHARE * smoothstep(0.3, 1.5, t) + (1.0 - FIRE_FIRST_SHARE) * smoothstep(2.0, FIRE_GROWTH_S, t)
	return growth * exp(-t / FIRE_BURN_S)


static func cloud_top_km(yield_kt: float) -> float:
	return CLOUD_TOP_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, CLOUD_TOP_EXP)


static func cloud_cap_radius_km(yield_kt: float) -> float:
	return CAP_RADIUS_PER_TOP * cloud_top_km(yield_kt)


## Flux au pic du flash à FLASH_REF_DISTANCE_KM, sans atmosphère (soleils) : 0,022 à 10 kt, 0,29 à 1 Mt, 2,6 à 50 Mt.
static func flash_peak_flux_sun(yield_kt: float) -> float:
	var power_w := FLASH_PEAK_POWER_COEF_KT_S * pow(_clamp_yield(yield_kt), FLASH_FLUX_EXP) * KILOTON_J
	var distance_m := FLASH_REF_DISTANCE_KM * 1000.0
	return power_w / (4.0 * PI * distance_m * distance_m) / SOLAR_CONSTANT_W_M2


## Durée du flash (s, temps physique).
static func flash_duration_s(yield_kt: float) -> float:
	return FLASH_DURATION_1MT_S * pow(_clamp_yield(yield_kt) / 1000.0, FLASH_DURATION_EXP)


## Luminance HDR d'une boule de feu de rayon radius_km dont le flux à FLASH_REF_DISTANCE_KM vaut flux_ref (soleils) :
## flux / angle solide, rapportés à ceux du soleil (indépendant de la distance d'observation).
static func fireball_radiance_hdr(flux_ref: float, radius_km: float) -> float:
	var ratio := flux_ref * pow(FLASH_REF_DISTANCE_KM * SUN_ANGULAR_RADIUS_RAD / maxf(radius_km, 1e-3), 2.0)
	return minf(SUN_DISC_HDR * ratio, FIREBALL_MAX_HDR)


## « 10 kt », « 340 kt », « 1 Mt », « 2.5 Mt », « 50 Mt ».
static func format_yield(yield_kt: float) -> String:
	if yield_kt < 999.5:
		return "%d kt" % roundi(yield_kt)
	return ("%.1f" % (yield_kt / 1000.0)).trim_suffix(".0") + " Mt"


static func _clamp_yield(yield_kt: float) -> float:
	return clampf(yield_kt, MIN_YIELD_KT, MAX_YIELD_KT)
