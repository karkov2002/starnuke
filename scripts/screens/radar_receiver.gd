class_name RadarReceiver
extends RefCounted
## Modèle du récepteur goniométrique de la console radar (RadarConsole) : antenne directive orientable sur 360°
## (azimut vrai, 0 = nord, sens horaire ; antenne stabilisée, indépendante de l'attitude de la station), accord en
## fréquence dans la bande choisie (VHF 30–300 MHz, UHF 300 MHz – 3 GHz) et sources d'émission au sol. Fonctions pures
## (aucun nœud) : la console règle l'état, l'interface (RadarDisplay) dessine la mesure.
##
## Règles de jeu (README, « Console radar ») :
## - une source n'est captée que si elle est dans la bande choisie et au-dessus de l'horizon de la station
##   (GeoMath.horizon_angle_rad : environ 2 200 km autour du point survolé à 400 km d'altitude) ;
## - accord : la cohérence (0–1) suit une courbe de résonance (lorentzienne) de l'écart de fréquence, 1/2 à
##   TUNE_WIDTH de l'étendue de la bande (VHF ± 1,1 MHz, UHF ± 11 MHz) : les sinusoïdes chaotiques se rapprochent
##   puis fusionnent en une seule ;
## - direction : le gain de l'antenne est maximal quand elle pointe le cap du grand cercle vers la source
##   (GeoMath.initial_bearing_deg), en cloche de demi-largeur à mi-puissance BEAM_HALF_DEG, SIDELOBE ailleurs ; à
##   moins de NADIR_DEG du point survolé, la source est sous la station : gain plein dans toutes les directions ;
## - le niveau baisse avec la distance, de 1 à la verticale à HORIZON_LEVEL à l'horizon.
## Deux relevés du cap de la source, pris de deux points de l'orbite, permettent de la situer par triangulation.

enum Band { VHF, UHF }

## Étendue de chaque bande (MHz).
const BAND_RANGE := {Band.VHF: Vector2(30.0, 300.0), Band.UHF: Vector2(300.0, 3000.0)}
## Fréquence au démarrage de chaque bande (MHz) : loin des sources du mode libre.
const DEFAULT_MHZ := {Band.VHF: 165.0, Band.UHF: 1650.0}
## Sources du mode libre (essai) : Oslo en VHF, Los Angeles en UHF (coordonnées de l'hôtel de ville).
const FREE_MODE_SOURCES: Array[Dictionary] = [
	{"id": "oslo", "lat": 59.9127, "lon": 10.7339, "band": Band.VHF, "mhz": 100.0},
	{"id": "los_angeles", "lat": 34.0537, "lon": -118.2427, "band": Band.UHF, "mhz": 800.0},
]
## Demi-largeur (degrés) du lobe de l'antenne à mi-puissance.
const BEAM_HALF_DEG := 6.0
## Gain hors du lobe principal (lobes secondaires et arrière).
const SIDELOBE := 0.06
## Écart d'accord (part de l'étendue de la bande) qui donne une cohérence de 1/2.
const TUNE_WIDTH := 0.004
## Niveau reçu d'une source à l'horizon (1 à la verticale).
const HORIZON_LEVEL := 0.45
## Angle au centre (degrés) en deçà duquel la source est considérée sous la station.
const NADIR_DEG := 0.8
## Cohérence à partir de laquelle l'accord est « verrouillé » (affiché à l'écran).
const LOCK := 0.9

var band := Band.VHF
## Azimut de l'antenne (degrés, 0–360).
var azimuth_deg := 0.0
## Sources : {id, lat, lon (degrés), band (Band), mhz}.
var sources: Array[Dictionary] = []
## Fréquence accordée dans chaque bande (MHz) : chaque bande garde son réglage.
var _mhz := DEFAULT_MHZ.duplicate()


static func band_min(b: Band) -> float:
	return (BAND_RANGE[b] as Vector2).x


static func band_max(b: Band) -> float:
	return (BAND_RANGE[b] as Vector2).y


static func band_span(b: Band) -> float:
	return band_max(b) - band_min(b)


func get_frequency_mhz() -> float:
	return _mhz[band]


func set_frequency_mhz(mhz: float) -> void:
	_mhz[band] = clampf(mhz, band_min(band), band_max(band))


func set_band(value: Band) -> void:
	band = value


func set_azimuth_deg(deg: float) -> void:
	azimuth_deg = fposmod(deg, 360.0)


## Ajoute une source (mode libre ou mission) ; une source de même identifiant est remplacée.
func add_source(id: String, lat: float, lon: float, source_band: Band, mhz: float) -> void:
	remove_source(id)
	sources.append({"id": id, "lat": lat, "lon": lon, "band": source_band, "mhz": mhz})


func remove_source(id: String) -> void:
	for i in range(sources.size() - 1, -1, -1):
		if sources[i].id == id:
			sources.remove_at(i)


## Gain de l'antenne (0–1) pour un écart (degrés) entre son azimut et le cap de la source.
static func antenna_gain(offset_deg: float) -> float:
	var x := absf(offset_deg) / BEAM_HALF_DEG
	return SIDELOBE + (1.0 - SIDELOBE) * exp(-log(2.0) * x * x)


## Mesure vue de la station (point survolé en degrés, altitude en km) : la source la mieux accordée de la bande
## au-dessus de l'horizon. Rend {coherence, amplitude (gain × niveau), id, bearing (degrés)} ; cohérence 0 et id
## vide sans source captée.
func measure(lat: float, lon: float, altitude_km: float) -> Dictionary:
	var best := {"coherence": 0.0, "amplitude": 0.0, "id": "", "bearing": 0.0}
	var horizon := GeoMath.horizon_angle_rad(altitude_km)
	var width := band_span(band) * TUNE_WIDTH
	for source in sources:
		if source.band != band:
			continue
		var angle := GeoMath.central_angle_rad(lat, lon, source.lat, source.lon)
		if angle >= horizon:
			continue
		var detune := (get_frequency_mhz() - float(source.mhz)) / width
		var coherence := 1.0 / (1.0 + detune * detune)
		if coherence <= best.coherence:
			continue
		var bearing := GeoMath.initial_bearing_deg(lat, lon, source.lat, source.lon)
		var gain := 1.0 if rad_to_deg(angle) < NADIR_DEG \
				else antenna_gain(angle_difference(deg_to_rad(azimuth_deg), deg_to_rad(bearing)) * 180.0 / PI)
		var level := lerpf(1.0, HORIZON_LEVEL, angle / horizon)
		best = {"coherence": coherence, "amplitude": gain * level, "id": source.id, "bearing": bearing}
	return best
