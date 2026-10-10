class_name NukeMath
extends RefCounted
## Fonctions mathématiques absentes de GDScript (modèles des explosions).


## Fonction de répartition de la loi normale centrée réduite (Abramowitz & Stegun 7.1.26, erreur < 1,5·10⁻⁷).
static func normal_cdf(z: float) -> float:
	var x := absf(z) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var erf := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) \
			* t * exp(-x * x)
	return 0.5 * (1.0 + (erf if z >= 0.0 else -erf))


## Fonction gamma (approximation de Lanczos, g = 7), pour x > 0.
static func gamma(x: float) -> float:
	const C := [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313,
			-176.61502916214059, 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6,
			1.5056327351493116e-7]
	if x < 0.5:
		return PI / (sin(PI * x) * gamma(1.0 - x))
	x -= 1.0
	var a: float = C[0]
	var t := x + 7.5
	for i in range(1, 9):
		a += C[i] / (x + i)
	return sqrt(TAU) * pow(t, x + 0.5) * exp(-t) * a


