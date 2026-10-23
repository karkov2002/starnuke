class_name NukeMushroomShape
extends RefCounted
## Forme et couleurs du champignon à un instant (calcul pur, unités normalisées : sommet final = 1), d'après les
## Curves et réglages de NukeMushroom et les lois de NukeScaling. Construite à chaque image par NukeMushroom, lue
## par NukeMushroomMesh, NukeMushroomVolume et les particules.
## - sommet h, chapeau (centre yc, rayon rc, épaisseur hc, dessous under, col y_neck), tige rs ; au départ, le
##   « chapeau » est la boule de feu (rayon rf), centrée à la hauteur d'explosion yb ;
## - nuage de vapeur (steam, explosion basse sur la mer) : chapeau plus rond, affaissement après la stabilisation ;
## - dissipation après la stabilisation : étalement spread (rayon ×, épaisseur ÷), densité fade (sous
##   NukeScaling.CLOUD_FADE_MIN : invisible), érosion de la tige ;
## - mouvements : slow (roulement et montée ralentis, intégrés analytiquement : rejouables) ;
## - couleurs : albedo selon l'âge, glow de la boule de feu (HDR).

## Temps physique (s), âge normalisé a = t / MUSHROOM_RISE_S et a1 = min(a, 1), âge de la lueur g.
var t := 0.0
var a := 0.0
var a1 := 0.0
var g := 0.0
## Sommet final (km) : échelle du nœud.
var top_km := 1.0
## Boule de feu et hauteur d'explosion (normalisées).
var rf := 0.0
var yb := 0.0
## Sommet, chapeau (centre, rayon, épaisseur, épaisseur avant l'étalement, profondeur du dessous, col), tige.
var h := 0.0
var yc := 0.0
var rc := 0.0
var hc := 0.0
var hc_rise := 0.0
var under := 1.0
var y_neck := 0.0
var rs := 0.0
## Dissipation : étalement (≥ 1), densité (0 à 1), érosion de la tige (0 à 3), visible (fade ≥ CLOUD_FADE_MIN).
var spread := 1.0
var fade := 1.0
var erosion := 0.0
var visible := true
## Temps ralenti du roulement et de la montée (s).
var slow := 0.0
var albedo := Color.WHITE
var glow := Color.BLACK


## Forme au temps physique t d'une explosion params, avec fireball_km le rayon courant de la boule de feu (flash) et
## steam la part « nuage de vapeur » (0 à 1), d'après les réglages du champignon m.
func _init(m: NukeMushroom, params: NukeParams, time_s: float, fireball_km: float, steam: float) -> void:
	t = time_s
	var w := params.yield_kt
	top_km = NukeScaling.cloud_top_km(w)
	a = t / NukeScaling.MUSHROOM_RISE_S
	a1 = minf(a, 1.0)
	rf = fireball_km / top_km
	yb = params.burst_height_km / top_km
	rc = maxf(rf, m.cap_radius_curve.sample(a1) * NukeScaling.CAP_RADIUS_PER_TOP)
	var aspect := m.cap_aspect_curve.sample(a1)
	hc = 2.0 * rc * lerpf(aspect, maxf(aspect, m.steam_aspect), steam)
	h = maxf(yb + 0.5 * hc, m.height_curve.sample(a1))
	rs = m.stem_curve.sample(a1) * rc
	under = lerpf(1.0, m.neck_drop, clampf(rs / (0.1 * rc), 0.0, 1.0))
	yc = h - 0.5 * hc
	y_neck = yc - under * 0.5 * hc
	# Nuage de vapeur (explosion sur la mer) : après la stabilisation, l'eau retombe en pluie, le nuage s'affaisse.
	if steam > 0.0:
		yc *= lerpf(1.0, NukeScaling.steam_sink(t), steam)
		h = yc + 0.5 * hc
		y_neck = yc - under * 0.5 * hc

	# Dissipation après la stabilisation : étalement, amincissement (centre du chapeau fixe), dilution, disparition
	# (bien plus rapide pour le nuage de vapeur).
	spread = NukeScaling.cloud_spread_ratio(w, t)
	fade = NukeScaling.cloud_fade(t, spread, yc * top_km, params.latitude_deg) \
			* lerpf(1.0, NukeScaling.steam_fade(t), steam)
	visible = fade >= NukeScaling.CLOUD_FADE_MIN
	hc_rise = hc
	if spread > 1.0:
		rc *= spread
		hc /= pow(spread, NukeScaling.CLOUD_THIN_EXP)
		h = yc + 0.5 * hc
		y_neck = yc - under * 0.5 * hc
	slow = m.roll_slowdown_s * log(1.0 + t / m.roll_slowdown_s)
	erosion = m.erosion_curve.sample(minf(a, m.erosion_curve.max_domain))
	albedo = m.albedo_gradient.sample(a1).lerp(m.steam_albedo, steam * m.steam_whiteness)
	g = minf(t / NukeScaling.fireball_glow_s(w), 1.0)
	glow = m.glow_gradient.sample(g) * (m.glow_hdr * maxf(m.glow_curve.sample(g), 0.0))


## Angle de roulement autour de l'anneau tourbillonnaire (rad) et défilement de la tige (unités normalisées).
func roll_angle(m: NukeMushroom) -> float:
	return TAU / m.roll_period_s * slow


func rise_offset(m: NukeMushroom) -> float:
	return m.stem_rise_speed * slow


func albedo_vec() -> Vector3:
	return Vector3(albedo.r, albedo.g, albedo.b)


func glow_vec() -> Vector3:
	return Vector3(glow.r, glow.g, glow.b)
