class_name NumberFormat
extends RefCounted
## Mise en forme des nombres partagée par les bilans (NukeReportText, écran mural) et la télévision (TvNews) :
## estimations arrondies à trois chiffres significatifs, groupement des milliers. Les séparateurs dépendent de la
## langue (NukeReportText.number_style pour celle du joueur, textes de TvNews pour celle de la chaîne). Fonctions
## pures, sûres depuis un autre thread.


## Estimation arrondie à trois chiffres significatifs (175 342 → 175 000 ; sous 1 000 : inchangé).
static func round_estimate(value: float) -> int:
	var n := roundi(value)
	if absi(n) < 1000:
		return n
	var step := int(pow(10.0, floorf(log(float(absi(n))) / log(10.0)) - 2.0))
	return roundi(float(n) / step) * step


## Entier avec ses milliers groupés par thousands (« 1 230 000 »).
static func group(value: int, thousands: String) -> String:
	var digits := str(absi(value))
	var grouped := ""
	while digits.length() > 3:
		grouped = thousands + digits.right(3) + grouped
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + grouped


## Estimation (round_estimate) avec ses milliers groupés.
static func count(value: float, thousands := " ") -> String:
	return group(round_estimate(value), thousands)
