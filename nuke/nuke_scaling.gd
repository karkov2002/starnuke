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

# Flash initial. La puissance thermique au pic varie comme W / t_max, avec t_max ∝ W^0,44 (Glasstone & Dolan,
# temps du second maximum thermique), d'où un flux ∝ W^0,56. Ordre de grandeur réel : ~1 500 TJ rayonnés en ~1 s
# pour 1 Mt, soit ~700 W/m² à 400 km, la moitié du soleil.
## Distance de référence des flux (km) : l'orbite nominale.
const FLASH_REF_DISTANCE_KM := 400.0
## Flux au pic à FLASH_REF_DISTANCE_KM pour 1 Mt, en « soleils » (1 = éclairement solaire hors atmosphère).
const FLASH_FLUX_1MT_SUN := 0.5
const FLASH_FLUX_EXP := 0.56
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


static func cloud_top_km(yield_kt: float) -> float:
	return CLOUD_TOP_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, CLOUD_TOP_EXP)


static func cloud_cap_radius_km(yield_kt: float) -> float:
	return CAP_RADIUS_PER_TOP * cloud_top_km(yield_kt)


## Flux au pic du flash à FLASH_REF_DISTANCE_KM (soleils).
static func flash_peak_flux_sun(yield_kt: float) -> float:
	return FLASH_FLUX_1MT_SUN * pow(_clamp_yield(yield_kt) / 1000.0, FLASH_FLUX_EXP)


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
