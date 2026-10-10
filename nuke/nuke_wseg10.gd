class_name NukeWSEG10
extends RefCounted
## Champ de retombées WSEG-10 d'une explosion (Weapons Systems Evaluation Group, 1959 ; D. W. Hanifen, *Documentation
## and Analysis of the WSEG-10 Fallout Prediction Model*, thèse, Air Force Institute of Technology, 1980) : débit de
## dose à H+1 et heure d'arrivée des retombées en chaque point, dans le repère du vent (x sous le vent, y en travers).
## Unités : miles, mph, kilopieds, heures, mégatonnes. Transcription d'après le paquet Python open source *glasstone*
## (MIT), corrigée (voir NukeFallout). Utilisé par NukeFallout, qui en tire doses et pertes.

const MPH_PER_M_S := 2.23694
const KFT_PER_KM := 3.28084

var yield_mt: float
var ff: float
var wind_mph: float
var shear: float # mph par kilopied
## Direction vers laquelle va le nuage (vecteur unitaire est, nord).
var dir: Vector2
var scale: float # part « explosion basse » (0 à 1) appliquée au débit de dose
var h_c: float
var s0: float
var s_h: float
var t_c: float
var l0: float
var s_x: float
var l: float
var n: float
var a1: float
var g_norm: float

func _init(params: NukeParams, low_burst: float) -> void:
	yield_mt = params.yield_kt / 1000.0
	ff = 1.0 if params.yield_kt < NukeFallout.FISSION_ONLY_KT else NukeFallout.FISSION_FRACTION
	scale = low_burst
	var ln_y := log(yield_mt)
	var d := ln_y + 2.42
	h_c = 44.0 + 6.1 * ln_y - 0.205 * absf(d) * d # hauteur du centre du nuage (kilopieds)
	s0 = exp(0.7 + ln_y / 3.0 - 3.25 / (4.0 + pow(ln_y + 5.4, 2.0)))
	s_h = 0.18 * h_c
	t_c = 1.0573203 * (12.0 * (h_c / 60.0) - 2.5 * pow(h_c / 60.0, 2.0)) * (1.0 - 0.5 * exp(-pow(h_c / 25.0, 2.0)))
	# Vent effectif : moyenne du profil réel (GFS) entre le sol et le centre du nuage ; cisaillement entre les deux.
	var h_km := h_c / KFT_PER_KM
	var mean := Vector2.ZERO
	for i in 16:
		mean += params.wind_at((i + 0.5) / 16.0 * h_km)
	mean /= 16.0
	wind_mph = maxf(mean.length() * MPH_PER_M_S, 1.0)
	dir = mean.normalized() if mean.length() > 0.01 else Vector2(1.0, 0.0)
	var top := params.wind_at(h_km)
	var bottom := params.wind_at(0.0)
	shear = (top - bottom).length() * MPH_PER_M_S / maxf(h_c, 1.0)
	l0 = wind_mph * t_c
	var s02 := s0 * s0
	var l02 := l0 * l0
	var s_x2 := s02 * (l02 + 8.0 * s02) / (l02 + 2.0 * s02)
	s_x = sqrt(s_x2)
	l = sqrt(l02 + 2.0 * s_x2)
	# Exposant de la loi de dépôt. La transcription glasstone y met la fraction de fission, déjà comptée dans le
	# débit (f_x) : le dépôt s'étalait sur des centaines de km et le débit près du point zéro était 3 à 5 fois sous
	# les contours idéalisés de Glasstone & Dolan (1 Mt, 15 mph). Avec 1, on retrouve leur ordre de grandeur.
	n = (l02 + s_x2) / (l02 + 0.5 * s_x2)
	a1 = 1.0 / (1.0 + 0.001 * h_c * wind_mph / s0)
	g_norm = 1.0 / (l * NukeMath.gamma(1.0 + 1.0 / n))

## Écart-type de la répartition en travers du vent à la distance x sous le vent (miles).
func crosswind_sigma(x: float) -> float:
	var s02 := s0 * s0
	var k := s_x * t_c * s_h * shear
	var m := (x + 2.0 * s_x) * l0 * t_c * s_h * shear
	return sqrt(s02 + 8.0 * absf(x + 2.0 * s_x) * s02 / l + 2.0 * k * k / (l * l) + m * m / pow(l, 4.0))

## Débit de dose à H+1 (R/h) au point (x sous le vent, y en travers ; miles), activité qui finira par s'y déposer.
func dose_rate_h1(x: float, y: float) -> float:
	var g := exp(-pow(absf(x) / l, n)) * g_norm
	var phi := NukeMath.normal_cdf((l0 / l) * (x / (s_x * a1)))
	var f_x := yield_mt * 2.0e6 * phi * g * ff
	var s_y := crosswind_sigma(x)
	var a2 := 1.0 / (1.0 + (0.001 * h_c * wind_mph / s0) * (1.0 - NukeMath.normal_cdf(2.0 * x / wind_mph)))
	var f_y := exp(-0.5 * pow(y / (a2 * s_y), 2.0)) / (2.5066282746310002 * s_y)
	return f_x * f_y * scale

## Heure moyenne d'arrivée des retombées sur la ligne chaude à x (au moins 0,5 h).
func arrival_h(x: float) -> float:
	var l02 := l0 * l0
	var s_x2 := s_x * s_x
	return sqrt(0.25 + l02 * pow(x + 2.0 * s_x, 2.0) * t_c * t_c / (l * l * (l02 + 0.5 * s_x2))
			+ 2.0 * s_x2 / (l02 + 0.5 * s_x2))

## Dose finale sous abri (Gy) sur la ligne chaude, ou en (x, y).
func final_dose_gy(x: float, y: float) -> float:
	return 5.0 * dose_rate_h1(x, y) * pow(arrival_h(x), -0.2) * NukeFallout.R_TO_GY / NukeFallout.PROTECTION_FACTOR
