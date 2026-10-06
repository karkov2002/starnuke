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


static func fireball_radius_km(yield_kt: float) -> float:
	return FIREBALL_COEF_KM * pow(_clamp_yield(yield_kt), FIREBALL_EXP)


static func shock_radius_km(yield_kt: float) -> float:
	return SHOCK_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, SHOCK_EXP)


static func cloud_top_km(yield_kt: float) -> float:
	return CLOUD_TOP_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, CLOUD_TOP_EXP)


static func cloud_cap_radius_km(yield_kt: float) -> float:
	return CAP_RADIUS_PER_TOP * cloud_top_km(yield_kt)


## « 10 kt », « 340 kt », « 1 Mt », « 2.5 Mt », « 50 Mt ».
static func format_yield(yield_kt: float) -> String:
	if yield_kt < 999.5:
		return "%d kt" % roundi(yield_kt)
	return ("%.1f" % (yield_kt / 1000.0)).trim_suffix(".0") + " Mt"


static func _clamp_yield(yield_kt: float) -> float:
	return clampf(yield_kt, MIN_YIELD_KT, MAX_YIELD_KT)
