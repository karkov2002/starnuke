class_name NukeScaling
extends RefCounted
## Lois d'échelle des explosions en fonction de la puissance W (kt). Toutes les tailles de l'effet en découlent :
## une seule animation, paramétrée par la puissance. Les coefficients sont en tête de fichier pour les régler.
##
##   rayon de la boule de feu  = FIREBALL_COEF_KM · W^FIREBALL_EXP              (1 Mt : ~1,05 km)
##   rayon de choc de référence = SHOCK_REF_KM · (W / REF_YIELD_KT)^(1/3)      (similitude de Hopkinson-Cranz)
##   sommet du nuage            = interpolation log-log entre CLOUD_TOP_POINTS (8 km à 10 kt, 22,5 km à 1 Mt, 65 km à 50 Mt)
##   rayon du chapeau           = CAP_RADIUS_PER_TOP · sommet du nuage

const MIN_YIELD_KT := 10.0
const MAX_YIELD_KT := 50000.0
const REF_YIELD_KT := 10.0

const FIREBALL_COEF_KM := 0.066
const FIREBALL_EXP := 0.4
const SHOCK_REF_KM := 2.0
const SHOCK_EXP := 1.0 / 3.0
# Sommet du nuage stabilisé (W en kt, km), interpolé en log-log entre ces points. Les hauteurs réelles varient
# beaucoup avec la météo et la tropopause (Glasstone & Dolan §2.16) :
# - 10 kt : 8 km, choix de jeu entre la moyenne américaine de Glasstone & Dolan (19 000 ft, 5,8 km, §2.17) et Nagasaki ;
# - 20 kt : 11 km (« 7 miles », Glasstone) ; Nagasaki (21 kt) est monté à 45 000 ft (13,7 km) ;
# - 1 Mt : 22,5 km (« 14 miles », Glasstone) ;
# - 15 Mt : 40 km (Castle Bravo ; Ivy Mike, 10,4 Mt, ~40 km) ;
# - 50 Mt : 65 km (Tsar Bomba, 64 à 67 km).
const CLOUD_TOP_POINTS: Array[Vector2] = [Vector2(10.0, 8.0), Vector2(20.0, 11.0), Vector2(1000.0, 22.5),
		Vector2(15000.0, 40.0), Vector2(50000.0, 65.0)]
const CAP_RADIUS_PER_TOP := 0.6
# Champignon (NukeMushroom) : ses Curves sont lues en âge normalisé a = t / MUSHROOM_RISE_S (temps physique). Le nuage
# se stabilise en ~10 min quelle que soit la puissance (Glasstone & Dolan 1977, §2.12, nuage de 1 Mt montant à
# 14 miles : 2 miles à 0,3 min, 4 à 0,7 min, 6 à 1,1 min, 10 à 2,5 min, 12 à 3,8 min, soit 14 %, 29 %, 43 %, 71 % et
# 86 % du sommet), soit ~1 min 36 s d'horloge avec l'accélération des phases lentes (NukeClock).
const MUSHROOM_RISE_S := 600.0
# Dissipation, après la stabilisation (t > MUSHROOM_RISE_S). « Le nuage peut rester visible une heure ou plus avant
# d'être dispersé par les vents dans l'atmosphère environnante, où il se confond avec les nuages naturels » (Glasstone
# & Dolan §2.16). Modèle :
# - étalement horizontal par la turbulence : R² = R0² + 4 K (t − t_s), K = CLOUD_SPREAD_K_M2_S (ordre de grandeur de
#   la diffusivité horizontale aux échelles de 10 à 100 km, 10⁴ à 10⁵ m²/s). 1 Mt : chapeau de 13,5 km de rayon,
#   ~21 km à 1 h, ~36 km à 4 h ; 10 kt : 4,8 km, ~16 km à 1 h. L'étirement dans le sens du vent vient du cisaillement
#   (vent différent au-dessus et au-dessous du centre du chapeau, profil GFS) ;
# - amincissement : épaisseur × (R0 / R)^CLOUD_THIN_EXP (la stratification freine le mélange vertical) ;
# - masse conservée : densité × (R0 / R)^(2 − CLOUD_THIN_EXP), soit une épaisseur optique vue de dessus × (R0 / R)² ;
# - disparition (évaporation, dépôt, mélange avec l'air environnant) : × exp(−(t − t_s) / τ), τ = CLOUD_FADE_TROPO_S
#   pour un chapeau dans la troposphère, CLOUD_FADE_STRATO_S au-dessus de la tropopause (air sec et stable, pas de
#   précipitations), avec un passage progressif sur ±CLOUD_TROPOPAUSE_BLEND_KM.
# Le champignon est masqué sous CLOUD_FADE_MIN : ~2 h à 10 kt, ~6 h à 1 Mt (temps physique ; ~1 h 30 et ~5 h 30
# d'horloge, la première demi-heure physique étant jouée en ~4 min, cf. NukeClock) : il survit à plusieurs orbites.
const CLOUD_SPREAD_K_M2_S := 2.0e4
const CLOUD_THIN_EXP := 0.5
const CLOUD_FADE_TROPO_S := 3600.0
const CLOUD_FADE_STRATO_S := 7200.0
const CLOUD_TROPOPAUSE_BLEND_KM := 2.0
const CLOUD_FADE_MIN := 0.01
# Tropopause (km) : ~17 km à l'équateur, ~9 km aux pôles, en cos² de la latitude.
const TROPOPAUSE_EQUATOR_KM := 17.0
const TROPOPAUSE_POLE_KM := 9.0
# La boule de feu reste lumineuse ~1 min pour 1 Mt (Glasstone & Dolan §2.18), ~70 t_max : 8 s à 10 kt, 6 min à 50 Mt.
const FIREBALL_GLOW_TMAX := 70.0

# Onde de choc : un seul front r(t) = R_max · (1 − exp(−t / τ)) pour l'anneau de condensation, la poussière au sol
# et le trou dans la couche nuageuse (nuke/shaders/nuke_clouds.gdshaderinc), qu'il pousse devant lui.
# R_max = SHOCK_VISUAL_SCALE · rayon de choc de référence + SHOCK_VISUAL_MIN_KM : choix visuel, plus grand que le rayon
# de référence, surtout pour les petites puissances (l'ajout fixe compte davantage) : 6,4 km à 10 kt (référence :
# 2 km), 15 km à 1 Mt, 45 km à 50 Mt. Un trou plus petit que l'épaisseur de la couche nuageuse (jusqu'à 7 km) n'est
# qu'un puits sombre vu de biais.
# τ est proportionnel au rayon de référence. Valeur réaliste : 1,28 s/km (vitesse du son en moyenne). Entorse au
# réalisme : l'onde est ralentie de SHOCK_SLOWDOWN, pour que son anneau de condensation (qui s'évapore à ~0,7 τ)
# survive au flash : 2,8 s à 10 kt, 13 s à 1 Mt, 48 s à 50 Mt. Durée totale (98 % de R_max) : 3,9 τ, soit ~16 s à
# 10 kt, ~74 s à 1 Mt, ~270 s à 50 Mt.
const SHOCK_VISUAL_SCALE := 1.2
const SHOCK_VISUAL_MIN_KM := 4.0
const SHOCK_TAU_S_PER_KM := 1.28
const SHOCK_SLOWDOWN := 1.6

# Incendies allumés par le flash : rayon initial où l'exposition thermique dépasse ~10 cal/cm² (inflammation des
# matériaux courants, Glasstone & Dolan ch. VII ; ~12 km pour 1 Mt avec l'absorption de l'air), ∝ W^0,41 (entre la loi
# en W^0,5 du vide et l'absorption croissante avec la distance) : ~1,8 km à 10 kt, ~60 km à 50 Mt. Règle de jeu : les
# incendies durent plusieurs jours et laissent un sol brûlé jusqu'à la fin de la partie. Modèle, évalué par le shader
# du sol (nuke/shaders/nuke_fire.gdshaderinc, constantes transmises par NukeGroundFX), en temps physique (au rythme du
# jeu après la première demi-heure, cf. NukeClock) :
# - zone du flash (rayon initial R0), calée sur Hiroshima (tempête de feu formée ~20 min après l'explosion, au maximum
#   vers 2–3 h) : foyers allumés par le flash (FIRE_FIRST_SHARE de l'intensité finale), qui se rejoignent de
#   FIRE_GROWTH_START_S à FIRE_GROWTH_END_S ;
# - propagation : le front gagne les terres alentour, rayon R0 · (1 + FIRE_SPREAD · (1 − exp(−t / FIRE_SPREAD_S))),
#   soit 2 R0 au bout de quelques jours (63 % du chemin en 1 jour, 95 % en 3 jours ; au départ ~0,5 km/h pour 1 Mt,
#   l'allure d'un feu de forêt). Un lieu atteint par le front s'embrase en FIRE_FRONT_RISE_S, moins fort que la tempête
#   de feu (FIRE_FRONT_SHARE) : un anneau de feu s'éloigne du centre ;
# - chaque lieu brûle avec une constante de temps d'extinction FIRE_BURN_S, puis il ne reste que le sol calciné (noirci
#   en FIRE_CHAR_S, puis brun : voir SCAR_*), définitif. Tout est éteint en 4 à 5 jours.
const FIRE_RADIUS_1MT_KM := 12.0
const FIRE_RADIUS_EXP := 0.41
const FIRE_FIRST_SHARE := 0.25
const FIRE_GROWTH_START_S := 120.0
const FIRE_GROWTH_END_S := 5400.0
const FIRE_SPREAD := 1.0
const FIRE_SPREAD_S := 86400.0
const FIRE_FRONT_SHARE := 0.3
const FIRE_FRONT_RISE_S := 3600.0
const FIRE_BURN_S := 21600.0
const FIRE_CHAR_S := 7200.0
# Irrégularité du bord des incendies (part du rayon initial, motif de bruit du shader) : la portée d'une explosion
# (fire_reach_km) en tient compte.
const FIRE_EDGE_NOISE := 0.35

# Trace au sol (règle de jeu ; nuke/shaders/nuke_fire.gdshaderinc) : pas de cratère (explosion à DEFAULT_BURST_HEIGHT_KM),
# mais une zone dévastée, définitive (la partie dure quelques semaines : aucune repousse visible). Deux causes :
# - le feu : le sol brûlé (zone du flash et extension des incendies) est d'abord noir de charbon, puis brunit à mesure
#   que les cendres s'envolent et que la végétation morte sèche, de SCAR_BROWN_START_S à SCAR_BROWN_END_S après son
#   passage : il reste une trace brune, sans verdure ;
# - le souffle : dans le rayon de SCAR_RUBBLE_PSI (bâtiments rasés, forêts couchées ; Glasstone & Dolan ch. V), sol de
#   gravats et de poussière, gris-brun dès l'explosion, même sans incendie (explosion sur une côte).
# Tout découle des rayons physiques, donc de la puissance : 10 kt, ~2 km de rayon brûlé (à peine une tache depuis
# l'orbite) ; 1 Mt, ~24 km ; 50 Mt, ~120 km (une région entière meurtrie).
const DEFAULT_BURST_HEIGHT_KM := 0.5
const SCAR_RUBBLE_PSI := 5.0
const SCAR_BROWN_START_S := 43200.0
const SCAR_BROWN_END_S := 345600.0

# Fumée des incendies (nuke/shaders/nuke_smoke.gdshaderinc ; nuke/nuke_ground_fx.gd). Panache gaussien (modèle classique
# de dispersion, intégré sur la verticale) : la fumée émise à l'instant t − a se trouve, à l'instant t, à la distance
# u · a sous le vent (grand cercle, vent réel GFS à SMOKE_HEIGHT_KM), étalée sur σ(a)² = σ0² + 2 K a (σ0 : taille du
# foyer, K = SMOKE_SPREAD_K_M2_S, diffusion horizontale à méso-échelle), et se dépose avec une constante de temps
# SMOKE_LIFETIME_S. Épaisseur optique verticale :
#   τ = MEE · Q(t − a) · e^(−a / L) / (u · √(2π) · σ(a)) · exp(−y² / 2σ²)
# Débit Q = Y · R0² · f(t) / FIRE_BURN_S, f = surface en feu (en R0², intensité comprise) calculée par
# smoke_burning_area() avec les lois des incendies, Y = fumée par m² de sol en feu (kg/m²) = combustible × facteur
# d'émission, moyenne sur la zone des incendies (smoke_yield_kg_m2, calculée au tir dans le thread de NukeImpact). Le
# combustible dépend de ce qui brûle :
# - végétation (campagne, maquis, forêts) : SMOKE_WILDLAND_FUEL_KG_M2 consommés (herbe 0,3 à 0,5 kg/m², broussailles
#   1 à 3, forêt 2 à 5 ; inventaires de feux de végétation, van der Werf et al. 2017), facteur d'émission de particules
#   SMOKE_WILDLAND_EF (~7 à 18 g/kg, Andreae 2019) ;
# - bâti : Toon et al. 2007 (§ 6.1) relient la charge de combustible à la population, 1,1·10⁷ g par habitant, soit
#   0,0011 g/cm² par hab./km² (SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2) : ~110 kg/m² à 10 000 hab./km² (centres-villes
#   mesurés : 120 à 470 kg/m², Hambourg 1943 : 470), facteur d'émission 0,020 g de fumée par g (Small 1989, repris par
#   Toon et al.).
# Une campagne peu peuplée (Sardaigne, ~70 hab./km²) donne ~0,03 kg/m², une grande ville 1 à 3 kg/m² : une explosion sur
# une ville produit 30 à 100 fois plus de fumée par km² en feu. Repère : 100 explosions de 15 kt sur des mégapoles
# donnent 1 à 5 Tg de suie (Toon et al. 2007), soit 0,01 à 0,05 Tg chacune. Efficacité d'extinction massique ~5 m²/g
# (fumée fraîche ; Toon et al. citent 4,4 à 7 m²/g). Le panache est tronqué au-delà de SMOKE_MAX_AGE_S (fumée diluée
# en voile ténu).
const SMOKE_HEIGHT_KM := 4.0
const SMOKE_WILDLAND_FUEL_KG_M2 := 2.0
const SMOKE_WILDLAND_EF := 0.012
const SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2 := 0.011
const SMOKE_URBAN_EF := 0.02
## Échantillons (par côté) de la zone des incendies pour smoke_yield_kg_m2.
const SMOKE_YIELD_SAMPLES := 24
const SMOKE_MEE_M2_KG := 5000.0
const SMOKE_SPREAD_K_M2_S := 5.0e4
const SMOKE_LIFETIME_S := 345600.0
const SMOKE_MAX_AGE_S := 172800.0
## Vent minimal du panache (m/s) : par calme plat, la fumée reste sur place (le modèle diverge à vent nul).
const SMOKE_MIN_WIND_M_S := 1.0
## Taille du foyer : σ0 = SMOKE_SOURCE_SIGMA · rayon initial des incendies.
const SMOKE_SOURCE_SIGMA := 0.7
## Table de f(t) : SMOKE_TABLE_SIZE valeurs, t en échelle log jusqu'à SMOKE_TABLE_MAX_S (au-delà, tout est éteint).
const SMOKE_TABLE_SIZE := 256
const SMOKE_TABLE_MAX_S := 864000.0

# Explosion basse sur une mer ou un océan (NukeParams.over_ocean, masque OceanMask) : la boule de feu vaporise une
# grande masse d'eau (Glasstone & Dolan §2.50 et suivants), le nuage est une grosse boule de vapeur condensée, blanche,
# chargée d'eau. Après la stabilisation (t_s = MUSHROOM_RISE_S), l'eau retombe en pluie : le nuage s'affaisse
# (hauteurs × 1 − STEAM_SINK · (1 − exp(−(t − t_s) / STEAM_SINK_S))) et disparaît vite (densité ×
# exp(−(t − t_s) / STEAM_FADE_S), en plus de la dissipation ordinaire) : masqué moins d'une heure après l'explosion
# (temps physique, une demi-heure d'horloge au plus), contre plusieurs heures sur terre.
const STEAM_SINK := 0.35
const STEAM_SINK_S := 900.0
const STEAM_FADE_S := 600.0

# Surpression de crête au sol (pertes humaines, NukeCasualties) : équation de Brode, H. L. Brode, *Airblast From
# Nuclear Bursts — Analytic Approximations*, Pacific-Sierra Research Corporation, 1986, p. 60–71 (transcription du
# paquet Python « glasstone », licence MIT). Explosion de 1 kt, distances en milliers de pieds, mise à l'échelle en
# racine cubique de la puissance ; hauteur d'explosion quelconque, surface idéale, pression ambiante du niveau de la
# mer ; précision ~10 %. Résultat en psi (1 psi = 6,895 kPa).
const KILOFEET_PER_KM := 3.28084

# Black-out électrique (NukeGridImpact, NukeGroundFX, nuke/shaders/nuke_blackout.gdshaderinc ; visible de nuit, sur les
# lumières des villes). Règle de jeu : le black-out dure jusqu'à la fin de la partie (réseau détruit, aucune remise en
# état pendant une guerre nucléaire). Trois couches :
# - zone détruite, éteinte dès l'explosion : rayon de BLACKOUT_DESTROYED_PSI (réseau de distribution, postes,
#   bâtiments) ;
# - panne régionale en cascade : disque de rayon BLACKOUT_REGION_1MT_KM · (W / 1 Mt)^(1/3) (~26 km à 10 kt, 120 km à
#   1 Mt, ~440 km à 50 Mt ; choix de jeu, au moins 2 fois la zone détruite), qui s'éteint par plaques du centre vers
#   le bord (front R · (1 − exp(−t / BLACKOUT_CASCADE_TAU_S))) ;
# - panne nationale : si les centrales détruites (dans le rayon de BLACKOUT_PLANT_PSI, Global Power Plant Database)
#   représentent au moins BLACKOUT_NATIONAL_SHARE de la capacité du pays, tout le pays s'éteint par plaques en
#   BLACKOUT_NATIONAL_OFF_S (effondrement de la fréquence). Repère : panne de la péninsule ibérique du 28 avril 2025,
#   Espagne et Portugal éteints en quelques secondes.
const BLACKOUT_DESTROYED_PSI := 2.0
const BLACKOUT_REGION_1MT_KM := 120.0
const BLACKOUT_CASCADE_TAU_S := 15.0
const BLACKOUT_PLANT_PSI := 5.0
const BLACKOUT_NATIONAL_SHARE := 0.10
const BLACKOUT_NATIONAL_OFF_S := 30.0

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
# Durées (Glasstone & Dolan §7.85–7.88) : temps du second maximum thermique t_max = 0,0417 · W^0,44 s (0,12 s à 10 kt,
# 0,87 s à 1 Mt, 4,9 s à 50 Mt) ; le flash est joué sur FLASH_DURATION_TMAX · t_max (l'essentiel de l'énergie
# thermique est émis avant 10 t_max), compressé par FLASH_TIME_SCALE. Les courbes de nuke_flash.tscn sont en
# u = t / durée jouée (u = 1 ↔ 10 t_max) : second maximum à
# u = 0,1, minimum entre les deux impulsions vers t_min = 0,0025 · W^0,5 s (u ≈ 0,007 à 0,012).
const FLASH_TMAX_COEF_S := 0.0417
const FLASH_TMAX_EXP := 0.44
const FLASH_DURATION_TMAX := 10.0
# Entorse au réalisme : le flash est joué en FLASH_TIME_SCALE fois sa durée (même forme d'impulsion). À sa durée
# réelle, sa traîne et l'éblouissement couvrent toute la vie de l'anneau de condensation de l'onde de choc ; raccourci
# (et l'onde ralentie, SHOCK_SLOWDOWN), l'anneau reste visible seul après le flash.
const FLASH_TIME_SCALE := 0.5
# Luminance de la boule de feu : celle du disque solaire (sun_disc_energy de space_sky.gdshader) × le rapport des
# luminances, plafonnée sous le maximum du format flottant 16 bits du rendu.
const SUN_DISC_HDR := 40000.0
const SUN_ANGULAR_RADIUS_RAD := 0.0046531
const FIREBALL_MAX_HDR := 50000.0


static func fireball_radius_km(yield_kt: float) -> float:
	return FIREBALL_COEF_KM * pow(_clamp_yield(yield_kt), FIREBALL_EXP)


static func shock_radius_km(yield_kt: float) -> float:
	return SHOCK_REF_KM * pow(_clamp_yield(yield_kt) / REF_YIELD_KT, SHOCK_EXP)


## Surpression de crête au sol (psi) à la distance ground_range_km du point zéro (équation de Brode).
static func overpressure_psi(yield_kt: float, ground_range_km: float, burst_height_km := 0.0) -> float:
	var cube := pow(_clamp_yield(yield_kt), 1.0 / 3.0)
	var ground := maxf(ground_range_km * KILOFEET_PER_KM, 1e-4)
	var height := maxf(burst_height_km, 0.0) * KILOFEET_PER_KM
	var z := height / ground
	var y := height / cube
	var x := ground / cube
	var r := sqrt(x * x + y * y)
	var a := 1.22 - 3.908 * z * z / (1.0 + 810.2 * pow(z, 5.0))
	var b := 2.321 + 6.195 * pow(z, 18.0) / (1.0 + 1.113 * pow(z, 18.0)) \
			- 0.03831 * pow(z, 17.0) / (1.0 + 0.02415 * pow(z, 17.0)) + 0.6692 / (1.0 + 4164.0 * pow(z, 8.0))
	var c := 4.153 - 1.149 * pow(z, 18.0) / (1.0 + 1.641 * pow(z, 18.0)) - 1.1 / (1.0 + 2.771 * pow(z, 2.5))
	var d := -4.166 + 25.76 * pow(z, 1.75) / (1.0 + 1.382 * pow(z, 18.0)) + 8.257 * z / (1.0 + 3.219 * z)
	var e := 1.0 - 0.004642 * pow(z, 18.0) / (1.0 + 0.003886 * pow(z, 18.0))
	var f := 0.6096 + 2.879 * pow(z, 9.25) / (1.0 + 2.359 * pow(z, 14.5)) - 17.5 * z * z / (1.0 + 71.66 * pow(z, 3.0))
	var g := 1.83 + 5.361 * z * z / (1.0 + 0.3139 * pow(z, 6.0))
	var h := 8.808 * pow(z, 1.5) / (1.0 + 154.5 * pow(z, 3.5)) - (0.2905 + 64.67 * pow(z, 5.0)) / (1.0 + 441.5 * pow(z, 5.0)) \
			- 1.389 * z / (1.0 + 49.03 * pow(z, 5.0)) \
			+ 1.094 * r * r / ((781.2 - 123.4 * r + 37.98 * pow(r, 1.5) + r * r) * (1.0 + 2.0 * y))
	var j := 0.000629 * pow(y, 4.0) / (3.493e-9 + pow(y, 4.0)) - 2.67 * y * y / (1.0 + 1e7 * pow(y, 4.3))
	var k := 5.18 + 0.2803 * pow(y, 3.5) / (3.788e-6 + pow(y, 4.0))
	return 10.47 / pow(r, a) + b / pow(r, c) + d * e / (1.0 + f * pow(r, g)) + h + j / pow(r, k)


## Distance au sol (km) jusqu'à laquelle la surpression atteint au moins psi (0 si elle n'est atteinte nulle part).
## Recherche dichotomique en échelle logarithmique, depuis le plus loin.
static func overpressure_range_km(yield_kt: float, psi: float, burst_height_km := 0.0) -> float:
	var lo := 0.01
	var hi := 2000.0
	if overpressure_psi(yield_kt, lo, burst_height_km) < psi:
		return 0.0
	for i in 60:
		var mid := sqrt(lo * hi)
		if overpressure_psi(yield_kt, mid, burst_height_km) >= psi:
			lo = mid
		else:
			hi = mid
	return lo


## Temps physique (s) d'arrivée de l'onde de choc à la distance r_km : celui du front affiché (anneau de condensation,
## trou dans les nuages : shock_front_radius_km, ralenti de SHOCK_SLOWDOWN), pour que les pertes du souffle
## apparaissent quand on voit passer le front. Au-delà de 98 % de son rayon final (le front n'y arrive
## qu'asymptotiquement), l'onde continue à la vitesse du son.
const SOUND_SPEED_KM_S := 0.34


static func shock_arrival_s(yield_kt: float, r_km: float) -> float:
	var r_max := shock_max_radius_km(yield_kt)
	var tau := shock_tau_s(yield_kt)
	var r_end := 0.98 * r_max
	if r_km <= r_end:
		return -tau * log(1.0 - r_km / r_max)
	return -tau * log(1.0 - r_end / r_max) + (r_km - r_end) / SOUND_SPEED_KM_S


## Rayon de la zone dont l'éclairage est détruit pour de bon (km).
static func blackout_destroyed_km(yield_kt: float, burst_height_km := 0.0) -> float:
	return overpressure_range_km(yield_kt, BLACKOUT_DESTROYED_PSI, burst_height_km)


## Rayon de la panne régionale en cascade (km).
static func blackout_region_km(yield_kt: float, burst_height_km := 0.0) -> float:
	return maxf(BLACKOUT_REGION_1MT_KM * pow(_clamp_yield(yield_kt) / 1000.0, 1.0 / 3.0),
			2.0 * blackout_destroyed_km(yield_kt, burst_height_km))


## Part « explosion basse » (1 au sol, 0 au-dessus de ~2 rayons de boule de feu) : poussière ou embruns soulevés,
## nuage de base, vapeur d'eau.
static func low_burst(yield_kt: float, burst_height_km: float) -> float:
	return 1.0 - smoothstep(0.5, 2.0, burst_height_km / fireball_radius_km(yield_kt))


## Affaissement du nuage de vapeur d'une explosion sur la mer : facteur des hauteurs au temps t (s, physique).
static func steam_sink(t: float) -> float:
	return 1.0 - STEAM_SINK * (1.0 - exp(-maxf(t - MUSHROOM_RISE_S, 0.0) / STEAM_SINK_S))


## Disparition du nuage de vapeur (pluie) : facteur de densité au temps t (s, physique), 1 jusqu'à la stabilisation.
static func steam_fade(t: float) -> float:
	return exp(-maxf(t - MUSHROOM_RISE_S, 0.0) / STEAM_FADE_S)


## Rayon final du front de choc affiché (km) : anneau de condensation, poussière et trou dans les nuages.
static func shock_max_radius_km(yield_kt: float) -> float:
	return SHOCK_VISUAL_SCALE * shock_radius_km(yield_kt) + SHOCK_VISUAL_MIN_KM


## Constante de temps de l'expansion du front de choc (s, temps physique).
static func shock_tau_s(yield_kt: float) -> float:
	return SHOCK_TAU_S_PER_KM * SHOCK_SLOWDOWN * shock_radius_km(yield_kt)


## Rayon courant du front de choc (km) au temps t (s, physique) : R_max · (1 − exp(−t / τ)).
static func shock_front_radius_km(yield_kt: float, t: float) -> float:
	return shock_max_radius_km(yield_kt) * (1.0 - exp(-maxf(t, 0.0) / shock_tau_s(yield_kt)))


## Rayon initial des incendies (km) : zone allumée par le flash.
static func fire_base_radius_km(yield_kt: float) -> float:
	return FIRE_RADIUS_1MT_KM * pow(_clamp_yield(yield_kt) / 1000.0, FIRE_RADIUS_EXP)


## Rayon du front des incendies (km) au temps t (s, physique) ; t = INF : extension finale (2 fois le rayon initial).
static func fire_radius_km(yield_kt: float, t: float) -> float:
	return fire_base_radius_km(yield_kt) * (1.0 + FIRE_SPREAD * (1.0 - exp(-maxf(t, 0.0) / FIRE_SPREAD_S)))


## Distance maximale (km) à laquelle les incendies peuvent brûler, bord irrégulier compris.
static func fire_reach_km(yield_kt: float) -> float:
	return fire_base_radius_km(yield_kt) * (1.0 + FIRE_SPREAD + FIRE_EDGE_NOISE)


## Intensité des flammes (0 à 1) à la distance relative x = d / R0 et au temps t (s, physique) : mêmes lois que le
## shader (nuke_fire.gdshaderinc), motif irrégulier moyen.
static func fire_burning(x: float, t: float) -> float:
	var t_ignite := 0.0
	var share: float
	if x <= 1.0:
		share = lerpf(0.8, 0.25, clampf(x, 0.0, 1.0))
	else:
		var u := (x - 1.0) / FIRE_SPREAD
		if u >= 1.0:
			return 0.0
		t_ignite = -FIRE_SPREAD_S * log(1.0 - u)
		share = FIRE_FRONT_SHARE * (1.0 - smoothstep(0.85, 1.0, u))
	var age := t - t_ignite
	if age <= 0.0:
		return 0.0
	var growth: float
	if x <= 1.0:
		growth = FIRE_FIRST_SHARE * smoothstep(0.3, 1.5, age) \
				+ (1.0 - FIRE_FIRST_SHARE) * smoothstep(FIRE_GROWTH_START_S, FIRE_GROWTH_END_S, age)
	else:
		growth = smoothstep(0.0, FIRE_FRONT_RISE_S, age)
	# Motif irrégulier du shader (zones qui brûlent plus ou moins) : facteur moyen mix(0.05, 1, ~0,5).
	return share * growth * exp(-age / FIRE_BURN_S) * 0.55


## Surface en feu au temps t (s, physique), en unités de R0² (intensité comprise) : ∫ fire_burning · 2πx dx. Ne dépend
## pas de la puissance (toutes les distances sont relatives à R0, les durées sont les mêmes).
static func smoke_burning_area(t: float) -> float:
	const STEPS := 96
	var x_max := 1.0 + FIRE_SPREAD
	var dx := x_max / STEPS
	var area := 0.0
	for i in STEPS:
		var x := (i + 0.5) * dx
		area += fire_burning(x, t) * TAU * x * dx
	return area


## Coordonnée (0 à 1) du temps t dans la table de smoke_burning_area (échelle log, pas d'une minute au départ).
static func smoke_table_coord(t: float) -> float:
	return log(1.0 + maxf(t, 0.0) / 60.0) / log(1.0 + SMOKE_TABLE_MAX_S / 60.0)


## Table de smoke_burning_area aux SMOKE_TABLE_SIZE temps de smoke_table_coord (lue par le shader de fumée).
static func smoke_table() -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(SMOKE_TABLE_SIZE)
	var scale := log(1.0 + SMOKE_TABLE_MAX_S / 60.0)
	for i in SMOKE_TABLE_SIZE:
		var coord := float(i) / float(SMOKE_TABLE_SIZE - 1)
		table[i] = smoke_burning_area(60.0 * (exp(coord * scale) - 1.0))
	return table


## Fumée par m² de sol en feu (kg/m²), moyenne sur les terres de la zone des incendies (rayon final) : végétation et
## bâti (charge proportionnelle à la population, grille GHS-POP). Sûr depuis un autre thread (lectures seules).
static func smoke_yield_kg_m2(params: NukeParams) -> float:
	var radius := fire_radius_km(params.yield_kt, INF)
	var km_per_deg := 111.32
	var cos_lat := maxf(cos(deg_to_rad(params.latitude_deg)), 0.05)
	var cell_km2 := pow(km_per_deg / PopulationGrid.CELLS_PER_DEGREE, 2.0) * cos_lat
	var has_population := PopulationGrid.is_available()
	var total := 0.0
	var land := 0
	for i in SMOKE_YIELD_SAMPLES:
		for j in SMOKE_YIELD_SAMPLES:
			var x := ((i + 0.5) / SMOKE_YIELD_SAMPLES * 2.0 - 1.0) * radius
			var y := ((j + 0.5) / SMOKE_YIELD_SAMPLES * 2.0 - 1.0) * radius
			if x * x + y * y > radius * radius:
				continue
			var lat := params.latitude_deg + y / km_per_deg
			var lon := params.longitude_deg + x / (km_per_deg * cos_lat)
			if OceanMask.is_ocean(lat, lon):
				continue
			var density := 0.0
			if has_population:
				density = PopulationGrid.cell_population(PopulationGrid.row_of(lat), PopulationGrid.col_of(lon)) / cell_km2
			total += SMOKE_WILDLAND_FUEL_KG_M2 * SMOKE_WILDLAND_EF \
					+ SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2 * density * SMOKE_URBAN_EF
			land += 1
	return total / land if land > 0 else SMOKE_WILDLAND_FUEL_KG_M2 * SMOKE_WILDLAND_EF


## Étalement latéral du panache (m) pour une fumée âgée de age_s, émise par un foyer de rayon initial fire_km.
static func smoke_sigma_m(fire_km: float, age_s: float) -> float:
	var s0 := SMOKE_SOURCE_SIGMA * fire_km * 1000.0
	return sqrt(s0 * s0 + 2.0 * SMOKE_SPREAD_K_M2_S * maxf(age_s, 0.0))


## Sommet du nuage stabilisé (km) : interpolation log-log entre CLOUD_TOP_POINTS.
static func cloud_top_km(yield_kt: float) -> float:
	var w := _clamp_yield(yield_kt)
	for i in range(1, CLOUD_TOP_POINTS.size()):
		var b := CLOUD_TOP_POINTS[i]
		if w <= b.x or i == CLOUD_TOP_POINTS.size() - 1:
			var a := CLOUD_TOP_POINTS[i - 1]
			var f := log(w / a.x) / log(b.x / a.x)
			return a.y * pow(b.y / a.y, f)
	return CLOUD_TOP_POINTS[-1].y


static func cloud_cap_radius_km(yield_kt: float) -> float:
	return CAP_RADIUS_PER_TOP * cloud_top_km(yield_kt)


## Étalement du chapeau stabilisé : R / R0 au temps t (s, physique), 1 avant la stabilisation.
static func cloud_spread_ratio(yield_kt: float, t: float) -> float:
	var r0_m := cloud_cap_radius_km(yield_kt) * 1000.0
	return sqrt(1.0 + 4.0 * CLOUD_SPREAD_K_M2_S * maxf(t - MUSHROOM_RISE_S, 0.0) / (r0_m * r0_m))


## Altitude de la tropopause (km) à la latitude donnée.
static func tropopause_km(latitude_deg: float) -> float:
	var c := cos(deg_to_rad(latitude_deg))
	return lerpf(TROPOPAUSE_POLE_KM, TROPOPAUSE_EQUATOR_KM, c * c)


## Facteur de densité du nuage (1 jusqu'à la stabilisation) : masse diluée par l'étalement (spread = R / R0) et
## disparition progressive, plus lente pour un chapeau stratosphérique (centre à cap_center_km).
static func cloud_fade(t: float, spread: float, cap_center_km: float, latitude_deg: float) -> float:
	var above := smoothstep(-CLOUD_TROPOPAUSE_BLEND_KM, CLOUD_TROPOPAUSE_BLEND_KM,
			cap_center_km - tropopause_km(latitude_deg))
	var tau := lerpf(CLOUD_FADE_TROPO_S, CLOUD_FADE_STRATO_S, above)
	return pow(spread, CLOUD_THIN_EXP - 2.0) * exp(-maxf(t - MUSHROOM_RISE_S, 0.0) / tau)


## Flux au pic du flash à FLASH_REF_DISTANCE_KM, sans atmosphère (soleils) : 0,022 à 10 kt, 0,29 à 1 Mt, 2,6 à 50 Mt.
static func flash_peak_flux_sun(yield_kt: float) -> float:
	var power_w := FLASH_PEAK_POWER_COEF_KT_S * pow(_clamp_yield(yield_kt), FLASH_FLUX_EXP) * KILOTON_J
	var distance_m := FLASH_REF_DISTANCE_KM * 1000.0
	return power_w / (4.0 * PI * distance_m * distance_m) / SOLAR_CONSTANT_W_M2


## Durée jouée du flash (s, temps physique) : 10 t_max × FLASH_TIME_SCALE, soit ~0,6 s à 10 kt, ~4,4 s à 1 Mt, ~24 s
## à 50 Mt (durées réelles : 1,2 s, 8,7 s, 49 s).
static func flash_duration_s(yield_kt: float) -> float:
	return FLASH_DURATION_TMAX * flash_tmax_s(yield_kt) * FLASH_TIME_SCALE


## Durée pendant laquelle la boule de feu reste lumineuse dans le champignon (s, physique) : 70 t_max réels, soit
## ~8 s à 10 kt, ~61 s à 1 Mt, ~5 min 40 s à 50 Mt.
static func fireball_glow_s(yield_kt: float) -> float:
	return FIREBALL_GLOW_TMAX * flash_tmax_s(yield_kt)


## Temps du second maximum thermique (s, physique) : 0,12 s à 10 kt, 0,87 s à 1 Mt, 4,9 s à 50 Mt.
static func flash_tmax_s(yield_kt: float) -> float:
	return FLASH_TMAX_COEF_S * pow(_clamp_yield(yield_kt), FLASH_TMAX_EXP)


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
