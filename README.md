# starnuke

POC Godot 4.7 : vue depuis une station spatiale en orbite basse (~400 km), depuis la Cupola de l'ISS.
Jeu « d'ambiance » : la priorité est une vue de la Terre la plus réaliste possible.

## Lancer

Ouvrir le projet dans Godot 4.7 puis F5 (scène principale : `res://scenes/orbit_view.tscn`).
Les tuiles haute résolution (`assets/earth_tiles/`, `assets/earth_night_tiles/`) doivent avoir été générées (voir plus bas).

## Contrôles

| Action | Contrôle |
|---|---|
| Orienter la vue | Maintenir le **clic droit** et déplacer la souris (tangage limité à ±80°) |
| Curseur | Libre le reste du temps (clic gauche sur le panneau de contrôle) |
| Altitude | Curseur du panneau, **200 à 800 km** (clic, glisser ou molette) |
| Inclinaison de l'orbite | Curseur du panneau, **0 à 70°**, bornée par la latitude courante (voir ci-dessous) |
| Date et heure (UTC) | Champ **date** (AAAA-MM-JJ, valider par Entrée), boutons **−1 j / +1 j**, curseur de l'**heure** du jour. La station reste au-dessus du même point ; le soleil, les étoiles et les nuages (poussés par le vent) se placent selon la nouvelle heure. Départ : **15 juillet 2035** |
| Vitesse du temps | Boutons **Pause, x1, x2, x4, x8, x16** |
| Redémarrer | Boutons **Restart by day** / **Restart by night** : temps remis à zéro, station au-dessus de l'Espagne (Madrid, 40,4° N 3,7° O, phase montante) à **midi** / **minuit** heure solaire locale, le même jour ; l'altitude est conservée, l'inclinaison relevée à 40,4° si elle était plus faible |
| Tir nucléaire | **Gros bouton rouge** à droite du panneau : frappe le point de la Terre visé par le **centre de la vue** (réticule), avec la puissance choisie en dessous (**10 kt, 100 kt, 500 kt, 1 Mt, 10 Mt, 50 Mt** ; 1 Mt par défaut). Si le centre de la vue ne vise pas la Terre (ciel, au-delà du limbe), il ne se passe rien. Voir « Explosions nucléaires » |

Pendant la rotation le curseur est masqué, puis replacé là où le clic droit a commencé.
L'observateur ne peut pas se déplacer pour l'instant (des contrôles d'orientation de la vue sont prévus).

**Panneau de contrôle** (`scenes/ui/orbit_controls.tscn`, script `scripts/orbit_controls.gd`), en bas au centre.
Il affiche l'altitude et la période orbitale, l'inclinaison et le point survolé (latitude, longitude), ainsi que
la date et l'heure UTC et l'heure solaire locale du point survolé. Les curseurs agissent en direct sur le nœud `Orbit`. Hors manipulation, ils affichent les
valeurs réellement appliquées. Le panneau a une largeur fixe et ne bouge pas quand les valeurs changent. Sa
dernière colonne (bouton de tir et puissance) vient de `nuke/`.

**Règles de l'orbite appliquées par les contrôles :**
- changer l'altitude conserve le point survolé et le sens de passage (montant / descendant) ; la période change
  avec l'altitude ;
- changer l'inclinaison se fait au point courant (comme un changement de plan orbital). Elle **ne peut pas être
  inférieure à la latitude actuelle** de la station : une orbite d'inclinaison i ne dépasse jamais ±i de latitude.
  La valeur demandée est donc remontée à |latitude| si besoin (le curseur se recale). Par exemple, au-dessus de
  Madrid (40,4° N), le minimum est 40,4°.
- l'accélération du temps agit sur l'orbite, la rotation de la Terre, le soleil et le déplacement des nuages par le vent (pas sur la lente évolution du relief de leurs sommets).

## Organisation de la scène

- **Station** : instance de `scenes/iss_cupola.tscn`, inspirée de l'ISS. L'unité de la scène est le mètre.
  - Module type **Node 3 « Tranquility »** : section intérieure 2,1 × 2,1 m, longueur 4,6 m, parois couvertes de
    racks, deux plafonniers, mains courantes autour du port nadir.
  - **Cupola** fixée sur le port nadir : dôme hexagonal (Ø ~2,8 m, hauteur ~1,3 m) construit en CSG (`CSGPolygon3D`
    en mode *spin* à 6 côtés), avec le **hublot central rond de 80 cm** et six fenêtres latérales trapézoïdales
    séparées par des montants.
  - Comme sur l'ISS, l'axe de la Cupola pointe vers le nadir (centre de la Terre). La station est inclinée de 30°
    (`Station.rotation_degrees.x`) pour que l'observateur, qui garde la verticale du monde comme « haut », voie à la
    fois le hublot central et l'horizon par les fenêtres latérales.
- **Observateur** (`Camera`, script `scripts/station_camera.gd`) : tête dans la Cupola, à ~1 m du hublot central ;
  vue initiale inclinée de 22° vers le bas (horizon dans le haut de l'image, Terre dans le reste du champ).
- **Terre** (`Earth/`) : rendue à l'échelle **1/10 000** (1 unité = 10 km ; rayon 637,1 u) pour éviter les
  problèmes de précision du tampon de profondeur. La caméra ne se déplaçant pas, la taille angulaire est identique
  à celle d'une vraie Terre. Sa position et son orientation sont recalculées à chaque image par le nœud `Orbit`.
  - `Surface` (shader `earth_surface.gdshader` + script `earth_detail_tiles.gd`, voir ci-dessous).
  - `CloudLayer` (sphère de 638,4 u) : nuages volumétriques procéduraux, voir ci-dessous.
  - `AtmosphereGround` (638,7 u) et `AtmosphereSky` (664 u) : diffusion atmosphérique physique, voir ci-dessous.
- **Orbite** (`Orbit`, script `scripts/orbit.gd`) : mécanique orbitale, voir ci-dessous.
- **Soleil** : `DirectionalLight3D` orientée par `Orbit` (position réelle du soleil, éteinte pendant l'éclipse) ;
  elle éclaire la Terre et produit le reflet du soleil sur les océans (masque d'eau déduit de la couleur).
- **Transition jour / nuit** (`shaders/sun_light.gdshaderinc`, partagé par le sol et les nuages) : la lumière du
  soleil est atténuée par l'air qu'elle traverse. Au-dessus de l'horizon local, on utilise la masse d'air de
  Kasten-Young. Sous l'horizon, le rayon a frôlé la Terre à l'altitude tangente ht et traversé une colonne d'environ
  √(2πRH)·e^(−ht/H) (approximation de Chapman). Elle rougit donc puis s'éteint progressivement, sans coupure, et les
  nuages en altitude gardent la lumière rose-orangée après le coucher du soleil au sol. Le sol a un éclairage
  personnalisé (`light()` : Lambert + GGX avec cette lumière teintée) et reçoit en plus la lumière diffuse bleutée du
  ciel (`sky_light_*`), qui persiste au crépuscule jusqu'à ~12° sous l'horizon (`twilight_end`). Les lumières des
  villes s'allument entre +2° et −7°.
- **Ciel / rendu** : `materials/space_environment.tres` (panorama étoilé HDR, tonemapping ACES, bloom qui adoucit
  le limbe). Le ciel est orienté à chaque image par `Orbit` (`Environment.sky_rotation`) : les étoiles sont à leur
  vraie place et tournent d'un tour par orbite autour de la station, comme vues depuis l'ISS.
- **Disque solaire** (shader de ciel `shaders/space_sky.gdshader`, qui dessine aussi le panorama étoilé) : soleil à
  sa position calculée, de rayon angulaire réel (0,267°), avec assombrissement centre-bord. Sa luminance
  (`sun_disc_energy` = 40 000, proche du maximum du format 16 bits) sature l'image et pilote l'éblouissement et
  l'exposition (voir ci-dessous). `Orbit` lui transmet à chaque image la
  direction du soleil et la position de l'observateur, dans le repère du ciel. Près du limbe, le disque est atténué
  par la transmittance spectrale de l'atmosphère, avec le même modèle que `atmosphere.gdshader` (paramètres
  partagés dans `shaders/atmosphere_common.gdshaderinc`). Il rougit, s'éteint en passant derrière le limbe, puis la
  Terre le masque. Comme la sphère `AtmosphereSky` atténue déjà le fond de la transmittance moyenne (gris), le ciel
  n'applique que le rapport couleur / moyenne. Depuis la Cupola, tournée vers le nadir, on ne voit le soleil que
  lorsqu'il est assez bas, par les fenêtres latérales (lever et coucher à chaque orbite).
- **Éblouissement** : glow de l'Environment, en mode additif, sur les 7 niveaux (du plus fin au plus large,
  poids 0,6 → 0,15), avec un plafond de luminance relevé à 1000 (`glow_hdr_luminance_cap`). Seul le disque solaire
  (et les reflets les plus intenses) dépasse nettement le seuil : il produit un halo progressif. Comme c'est un
  effet d'image, ce halo déborde sur les montants des fenêtres, comme dans l'œil ou un objectif. Il disparaît dès que
  le disque est masqué par la station ou par la Terre.
- **Exposition automatique** (`materials/camera_attributes.tres`, affecté au `WorldEnvironment`) : Godot ajuste
  l'exposition d'après la luminance moyenne de l'image HDR (exposition = `auto_exposure_scale` / moyenne).
  - **Jour** : `auto_exposure_scale` = 0,22 est la luminance moyenne d'une vue de jour typique ; la vue de jour
    garde donc la même luminosité qu'avant.
  - **Face au soleil** : le disque visible domine la moyenne, et l'exposition baisse d'environ 5 fois. La Terre
    s'assombrit et les étoiles s'effacent.
  - **Nuit** : la moyenne s'effondre et l'exposition remonte, plafonnée à × 2,5
    (`auto_exposure_min_sensitivity` = 70,4, soit une luminance minimale de 0,088). Au-delà, l'intérieur de la
    Cupola, éclairé par la seule lumière ambiante, paraissait en plein jour.
  - **Lumière ambiante** : celle de l'Environment n'éclaire que la station. La surface terrestre l'ignore
    (`render_mode ambient_light_disabled` dans `earth_surface.gdshader`) : remontée de × 2,5 la nuit, elle
    rendait les continents visibles. La face nocturne n'a que ses émissions (villes, lueur des terres, ciel au
    crépuscule).
  - **Compensations** : les étoiles (`panorama_energy` = 0,4) et les lumières des villes (`night_intensity` = 0,64)
    sont divisées par 2,5. La nuit, elles retrouvent leur éclat ; de jour, les étoiles sont à peine visibles,
    comme sur les photos prises depuis l'ISS.
  - **Vitesse d'adaptation** : `auto_exposure_speed` = 1.

### Orbite (`scripts/orbit.gd`)

Orbite **circulaire képlérienne** autour d'une Terre **en rotation** (sidérale, 7,292 × 10⁻⁵ rad/s) :
- rayon a = 6371 km + altitude ; vitesse angulaire n = √(μ / a³) (μ = 398 600,44 km³/s²) ; période 2π/n
  (88,4 min à 200 km, 92,4 min à 400 km, 100,7 min à 800 km) ;
- position dans le repère inertiel équatorial (ECI : x vers le point vernal, z vers le pôle nord céleste) avec
  i = inclinaison, Ω = ascension droite du nœud ascendant, u = argument de latitude (u = u₀ + n·t) :
  `r = a·(cosΩ·cos u − sinΩ·sin u·cos i, sinΩ·cos u + cosΩ·sin u·cos i, sin u·sin i)` ;
- repère terrestre (ECEF) = rotation de −θ autour de z, θ = angle sidéral de Greenwich = θ₀ + ω_terre·t : la
  trace au sol dérive donc vers l'ouest d'environ 23° de longitude par orbite ;
- point survolé : latitude = asin(z/|r|), longitude = atan2(y, x) dans l'ECEF.

**Rendu** : la station et la caméra restent fixes dans la scène. À chaque image, le repère orbital local
(zénith = r̂, direction de vol = v̂) est aligné sur le repère de la station (+Y local = zénith, −Z local = direction
de vol), et on en déduit l'orientation et la position de la Terre, la direction du soleil et l'orientation du ciel.

**Date et heure** : l'horloge est une vraie date UTC (`epoch_unix_s + sim_time_s`). Le jeu se passe en 2035 : départ
le `start_date` (2035-07-15, juillet comme les textures) à l'heure solaire locale `start_local_solar_hour` (10 h 30)
au point de départ. L'angle sidéral θ est l'angle de rotation de la Terre (IAU 2000), calculé à partir de la date
julienne. Le soleil est placé par les formules de l'Astronomical Almanac (longitude moyenne, anomalie, obliquité ;
précision ~0,01°), et suit donc les saisons, l'équation du temps et son déplacement d'environ 1° par jour. Le
soleil, la Terre et les étoiles sont cohérents entre eux (ex. en juillet à 22 h, le couchant est au nord-ouest).
Changer la date ou l'heure (`set_utc_unix_s`) recalcule l'orbite pour que la station reste au-dessus du même point.
Les textures du sol sont celles de juillet : une date d'hiver garde un sol estival (pas de neige).
Jour et nuit alternent naturellement (~35 min de nuit par orbite à 400 km ; l'été aux hautes latitudes, la station
peut rester au soleil alors que le sol est dans la nuit). `get_sunlight_fraction()` donne l'éclipse par la Terre
(ombre cylindrique adoucie sur 60 km), qui éteint la lumière du soleil sur la station.

**Ciel étoilé** : la carte NASA est en coordonnées équatoriales (ascension droite 0h au centre, croissante vers la
gauche, déclinaison +90° en haut). Le panorama Godot lit la direction locale d avec u = atan2(d.x, −d.z)/2π et
v = acos(d.y)/π, d'où d = (y_ECI, z_ECI, x_ECI). `sky_rotation` reçoit la rotation ciel → monde
(repère station ← ECEF ← ECI ← ciel). Godot applique son inverse aux directions de vue (vérifié dans
`servers/rendering/renderer_rd/environment/sky.cpp`).

**Conditions initiales** : `start_latitude_deg`, `start_longitude_deg` et `start_ascending` (40,4° N, 3,7° O,
montante : l'Espagne, au-dessus de Madrid). L'orbite est calculée pour y passer (`pass_over`).

**API pour le gameplay** (classe `OrbitSimulation` ; altitude, inclinaison et temps sont reliés au panneau) :
| Méthode / propriété | Rôle |
|---|---|
| `altitude_km` (200–800) | Change l'altitude ; le point survolé et le sens de passage sont conservés. |
| `inclination_deg` (0–70°) | Change l'inclinaison au point courant (comme une manœuvre de changement de plan) ; bornée à ≥ \|latitude courante\|. |
| `pass_over(lat, lon, ascending)` | Recalcule Ω et la phase pour être, maintenant, à la verticale de (lat, lon). Exige \|lat\| ≤ inclinaison. |
| `restart(heure_solaire)` | Temps remis à zéro, station au-dessus du point de départ, le même jour, à l'heure solaire locale donnée (12 = midi, 0 = minuit). Utilisé par les boutons Restart. |
| `set_utc_unix_s(s)`, `get_utc_unix_s()`, `get_utc_datetime()` | Date et heure UTC (secondes Unix) ; le changement garde la station au-dessus du même point. |
| `get_local_solar_hour(lon)`, `get_sun_direction_eci()` | Heure solaire vraie à une longitude, direction du soleil. |
| `get_subsatellite_point(t)` | Point survolé (lat, lon) à l'instant t. |
| `predict_ground_track(durée, pas)` | Trace au sol prévue (pour une carte ou le calcul de manœuvres). |
| `get_period_s()`, `get_orbital_speed_km_s()`, `get_raan_deg()`, `is_ascending()` | Grandeurs orbitales. |
| `time_scale`, `sim_time_s` | Accélération / temps simulé. |

**Inclinaison maximale (70°) et pôles** : la trace au sol monte jusqu'à la latitude égale à l'inclinaison, et la vue
porte ~20° plus loin, donc presque jusqu'au pôle à 70°. Aux plus hautes latitudes, la fenêtre de tuiles HD (découpée
en latitude/longitude) devient étroite : au-delà de ~65° de latitude, le sol loin du nadir peut être un peu moins
net. Pour survoler les pôles sans perte, il faudrait un découpage en « cube-sphère » (voir plus bas).

### Nuages volumétriques (`shaders/cloud_volume.gdshader`, `shaders/cloud_density.gdshaderinc`)

Couche entre **3 et 10 km** d'altitude, rendue par lancer de rayon (jusqu'à 72 pas) sur la sphère `CloudLayer`.
- **Où et combien** : nuages **réels** d'une journée d'imagerie satellite (VIIRS NOAA-20, 15 juillet 2023 : ouragan
  Calvin dans le Pacifique, dépressions en spirale, fronts, bancs de stratocumulus, amas orageux tropicaux…). La
  couche alpha est calculée par différence avec la Blue Marble sans nuages (`tools/build_cloud_tiles.ps1`). Elle est
  globale en 16K (`assets/textures/earth_clouds_16k.jpg`) et en tuiles 500 m/px autour de la station
  (`assets/earth_cloud_tiles/*.webp`, même fenêtre 5 × 5 que le sol). Le niveau de détail lu dépend de la
  distance, pour éviter le scintillement au loin.
- **Épaisseur** : la couverture moyenne à grande échelle (~8 km, `cloud_height_lod`) fixe la hauteur du sommet. Un
  cumulus isolé ou un voile reste bas (~1 km d'épaisseur, `cloud_thin_top`), une masse étendue et dense (front,
  cyclone, cumulonimbus) monte jusqu'à 10 km.
- **Forme** : les masses suivent directement la carte (pas de seuillage d'un bruit cellulaire, qui donnait l'aspect
  « billes de polystyrène »). Les sommets sont bosselés par un bruit fractal doux à deux échelles : ondulation sur
  50 km (`cloud_top_billow`) et relief « chou-fleur » sur ~8 km (`cloud_top_detail`). Un bruit de Worley
  (`cloud_detail_noise.tres`) n'effiloche que les bords (couverture partielle, `cloud_edge_erosion`).
- **Éclairage** : marche vers le soleil (auto-ombrage, loi de Beer + diffusion multiple approchée,
  `multiple_scattering`), phase double Henyey-Greenstein (liseré lumineux à contre-jour), soleil rougi puis éteint
  progressivement par l'atmosphère (`sun_light.gdshaderinc`), lumière ambiante bleutée du ciel ; nuages éteints côté
  nuit.
- **Ombres au sol** et voilage des lumières des villes : le shader de surface intègre la même densité.
- **Trous des explosions** : `cloud_density()` appelle `nuke_cloud_warp()` (`nuke/shaders/nuke_clouds.gdshaderinc`,
  voir « Explosions nucléaires », « Nuages ») ; sans explosion, le test `nuke_cloud_count > 0` évite tout calcul.
- **Déplacement par le vent réel** (advection) : la carte de couverture est un instantané, pris par NOAA-20 vers
  **13 h 30 heure solaire locale** le 15 juillet 2023. Le vent utilisé est le vent moyen du même jour : modèle
  GFS de la NOAA, moyenne des niveaux 850/700/500 hPa et des 4 analyses du jour, texture
  `assets/textures/cloud_wind.exr`, 0,5°. Pour l'heure UTC courante, le shader remonte la trajectoire de l'air
  (6 pas Runge-Kutta 2) jusqu'à l'heure du passage satellite, et lit la carte (et le bruit du relief) au point de
  départ. Les nuages dérivent donc avec la vraie circulation : alizés, courants-jets, rotation de l'ouragan Calvin.
  - Le calcul est fait une fois par rayon de vue (au milieu de la traversée de la couche) et une fois par pixel du
    sol pour les ombres, puis appliqué à tous les échantillons voisins.
  - **Règle de répétition journalière** : l'écart à l'heure du passage est ramené dans [−12 h, +12 h]. La météo du
    15 juillet 2023 se rejoue donc chaque jour : changer de date sans changer d'heure redonne les mêmes nuages, alors
    que changer l'heure les déplace.
  - Vers ±12 h (≈ 1 h 30 du matin, heure locale, donc côté nuit), les deux trajectoires sont fondues sur
    `cloud_advection_blend_h` (1,5 h) pour éviter un saut. Cette règle absorbe aussi le raccord de date de
    l'imagerie VIIRS.
  - Les nuages se déplacent mais ne naissent ni ne disparaissent : à ±12 h ils sont étirés par le cisaillement du
    vent.
  - Réglages : `cloud_wind_scale` (1 = vent réel), `cloud_snapshot_local_hour` (13,5).
- **Évolution des sommets** : `cloud_wind_km_s` fait en plus évoluer lentement le relief des sommets (temps réel).
Les nuages sont attachés au repère de la Terre (ils tournent avec elle). Réglages principaux dans le matériau
`materials/cloud_volume.tres` (voir aussi `materials/earth_surface.tres`, qui partage les paramètres de densité).

### Atmosphère (`shaders/atmosphere.gdshader`)

Diffusion simple calculée par lancer de rayon dans la coquille atmosphérique (rayon terrestre 6371 km, épaisseur
100 km ; calculs en km via `units_to_km = 10`) :
- **Rayleigh** (hauteur d'échelle 8 km) : bleu du ciel et du limbe ;
- **Mie** (hauteur d'échelle 1,2 km, g = 0,8) : halo blanchâtre près du sol et autour du soleil ;
- **Ozone** (couche centrée à 25 km) : absorption qui donne le passage bleu profond → noir.
La densité décroît exponentiellement avec l'altitude, d'où une transition progressive vers l'espace (plus de
« couche de verre »). Au-dessus du sol, la même intégration produit la perspective aérienne (voile bleuté vers
l'horizon) et atténue la lumière du sol. Rendu après les nuages (`render_priority = 1`) en mélange
prémultiplié, sur deux sphères avec le même shader (`ground_rays`) : `AtmosphereSky` (664 u, faces arrière seulement)
pour les rayons qui manquent la Terre, et `AtmosphereGround` (638,7 u, juste au-dessus des nuages, faces avant)
pour ceux qui la touchent. Ainsi l'atmosphère reste correcte même quand la caméra est *dans* la coquille
atmosphérique (orbite à 200 km), et la station la masque par le simple test de profondeur.

`height_scale = 2.5` étire l'atmosphère verticalement (hauteurs d'échelle et épaisseur × 2,5, coefficients ÷ 2,5) :
le voile au-dessus du sol garde la même opacité, mais le halo du limbe devient plus épais et plus diffus, comme sur
les photos de référence (1 = Terre réelle, liseré fin). La sphère `AtmosphereSky` (rayon 664 u) doit contenir
`6371 + 100 × height_scale` km. Autres réglages : `sun_intensity` (9), `primary_steps` / `light_steps`
(qualité / coût). Le modèle (rayon, coefficients, hauteurs d'échelle, `height_scale`) est dans
`shaders/atmosphere_common.gdshaderinc`, partagé avec le shader de ciel. Si on change un paramètre dans un matériau,
il faut le changer aussi dans l'autre.

### Texture de la surface : globale + tuiles haute résolution

Trois jeux de données identiquement découpés : **jour** (Blue Marble NG), **nuit** (Black Marble 2016, lumières
des villes) et **couverture nuageuse** (VIIRS, voir « Nuages volumétriques » ; tuiles en WebP niveaux de gris,
gardées en L8 en mémoire, ~50 Mo de VRAM).
- Partout : `assets/textures/earth_bluemarble_16k.jpg` et `earth_night_16k.jpg` (16384 × 8192, ~2,4 km/pixel).
- Autour du point survolé : tuiles de 5° en **500 m/pixel** (`assets/earth_tiles/rLL_cCC.jpg` et
  `assets/earth_night_tiles/rLL_cCC.jpg`, 1200 × 1200 px, 72 colonnes × 36 lignes, ligne 0 = 90° N, colonne 0 =
  180° O). Le script `scripts/earth_detail_tiles.gd` garde une fenêtre de 5 × 5 tuiles (25° × 25°, soit au moins
  1100 km autour du nadir) dans un `Texture2DArray` par jeu (jour, nuit, nuages), tous avec la même attribution de
  couches. Il transmet ces tableaux, l'origine de la fenêtre et la table des couches au matériau de surface et à
  celui des nuages (`extra_material_paths`) ; la logique de lecture est partagée dans
  `shaders/detail_window.gdshaderinc`. Quand la station change de tuile, il charge les tuiles entrantes en tâche de
  fond (`WorkerThreadPool`) et les copie dans les couches libérées. Les shaders fondent la fenêtre dans les textures
  globales sur ses bords. Les tuiles sont gardées non compressées (~430 Mo de VRAM au total, chargement < 2 s) ; l'option
  `compress_tiles` les compresse en BC1 (VRAM ÷ 8) mais le chargement devient beaucoup plus lent et le
  compresseur n'existe que dans l'éditeur. Sans tuiles de nuit, seule la texture globale de nuit est utilisée.
- **Lumières nocturnes** (shader de surface, en émission) : allumées quand le soleil passe sous l'horizon local
  (`night_sun_high` ≈ +2° → `night_sun_low` ≈ −7°), atténuées sous les nuages (transmittance verticale de la
  couche nuageuse, `night_cloud_floor`), intensité `night_intensity` (0,64, compensée par l'exposition
  automatique, qui remonte l'image de × 2,5 la nuit). La faible lueur bleutée des terres présente
  dans le composite NASA (clair de lune, neige) est gardée mais atténuée (`night_land_level`).
- Les dossiers de tuiles contiennent un `.gdignore` : l'éditeur n'importe pas les ~7800 tuiles (pas de
  copie dans `.godot/`), le jeu les lit directement avec `FileAccess`. **À prévoir pour un export** : inclure ces
  fichiers dans le paquet (filtre d'export de fichiers non-ressources ou distribution à côté de l'exécutable).
- **Pôles** : le découpage latitude/longitude (équirectangulaire) dégénère aux pôles. Les tuiles y deviennent des
  bandes très étroites, la fenêtre 5 × 5 ne couvre presque plus rien, et le maillage `SphereMesh` pince ses UV.
  D'où la limite d'inclinaison à 70°. La technique standard pour survoler les pôles sans dégrader la vue est la
  **cube-sphère** : on projette la Terre sur les 6 faces d'un cube (chaque face découpée en tuiles carrées
  quasi uniformes), avec un maillage de sphère issu du cube et des coordonnées calculées par pixel à partir de la
  direction. Il n'y a alors plus de singularité nulle part. Cela demande de reprojeter les tuiles NASA (outil
  hors-jeu) et d'adapter `earth_detail_tiles.gd` et le shader de surface.

### Génération des tuiles

1. Télécharger les 8 images Blue Marble Next Generation de juillet 2004, variante **sans relief ombré** (le relief
   ombré « topo.bathy » est figé et éclairé du nord-ouest, irréaliste avec un soleil dynamique, et dessine le fond
   des mers)
   (`world.200407.3x21600x21600.{A1,B1,C1,D1,A2,B2,C2,D2}.jpg`, ~350 Mo) depuis
   `https://eoimages.gsfc.nasa.gov/images/imagerecords/74000/74092/` dans un dossier, renommées `A1.jpg` … `D2.jpg`.
   Le serveur coupe souvent les gros transferts : reprendre avec `curl -C -` jusqu'à la taille annoncée.
2. Lancer `tools/build_earth_tiles.ps1 -src <dossier>` (PowerShell, quelques minutes). Il écrit les tuiles et
   régénère la texture globale 16K à partir de la même source (couleurs identiques entre les deux niveaux).
   Le script est en .NET car Godot refuse les images de plus de 268 Mpx (les sources en font 466).
3. Nuit : télécharger `BlackMarble_2016_{A1,B1,C1,D1,A2,B2,C2,D2}.jpg` (~220 Mo) depuis
   `https://eoimages.gsfc.nasa.gov/images/imagerecords/144000/144898/`, renommées `A1.jpg` … `D2.jpg`, puis lancer
   `tools/build_earth_tiles.ps1 -src <dossier> -kind night` (même découpage, sorties `assets/earth_night_tiles/`
   et `assets/textures/earth_night_16k.jpg`).
4. Nuages (nécessite les tuiles de jour) :
   - télécharger les 2592 tuiles VIIRS de la journée choisie, même nom et même emprise que les tuiles de jour
     (`rLL_cCC.jpg`, 5°, 1200 × 1200 px). WMS NASA GIBS
     `https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=VIIRS_NOAA20_CorrectedReflectance_TrueColor&CRS=EPSG:4326&BBOX=<lat_min>,<lon_min>,<lat_max>,<lon_max>&WIDTH=1200&HEIGHT=1200&FORMAT=image/jpeg&TIME=2023-07-15`
     (~410 Mo, quelques minutes avec 12 requêtes en parallèle) ;
   - `tools/build_cloud_tiles.ps1 -viirs <dossier>` (PowerShell + routine C# compilée à la volée, ~3 min). Il calcule
     la couche alpha (différence de luminance avec la Blue Marble, filtre des pixels colorés, suppression du reflet
     du soleil sur l'océan, repérable car lisse, par l'écart-type local). Là où la journée n'a pas de données (nuit
     polaire), il prend la carte nuageuse Blue Marble 8K. Il écrit les tuiles JPEG et la texture globale 16K ;
   - `godot --headless --path . --script res://tools/convert_tiles_webp.gd -- <projet>/assets/earth_cloud_tiles`
     convertit les tuiles en WebP niveaux de gris (~2 fois plus léger que le JPEG).
5. Vent (déplacement des nuages) : `tools/build_wind_field.ps1 [-date 20230715]` (PowerShell + routine C#, ~1 min).
   - Il lit l'index `.idx` des analyses GFS 0,25° du jour (00, 06, 12, 18 UTC) sur l'archive publique AWS
     `https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.AAAAMMJJ/HH/atmos/gfs.tHHz.pgrb2.0p25.anl`, et ne télécharge
     que les composantes UGRD/VGRD à 850, 700 et 500 hPa (~24 Mo).
   - Il décode le GRIB2 lui-même (gabarit 5.3, « complex packing + spatial differencing »), puis fait la moyenne.
   - Il écrit `assets/textures/cloud_wind.exr` (720 × 360, R = vent vers l'est, G = vers le nord, m/s).
   - Il écrit aussi le **profil vertical** du vent, pour la dérive des champignons atomiques
     (`assets/textures/wind_profile.exr`) : 14 niveaux de pression (850, 700, 500, 300, 250, 200, 150, 100, 50, 20,
     10, 5, 1 et 0,1 hPa, soit ~1,5 à ~64 km d'altitude), moyennés sur les 4 analyses du jour et empilés
     verticalement du plus bas au plus haut, 360 × 180 texels (1°) chacun. Canaux : R = vent vers l'est, G = vers le
     nord (m/s), B = altitude géopotentielle du niveau (champ HGT, km). Téléchargement : ~150 Mo, quelques minutes.
   - Le service OPeNDAP de la NOAA, plus simple, était hors service ; la réanalyse NCEP (2,5°) aurait été trop
     grossière pour les cyclones.
   - L'import Godot de ces deux textures doit rester **sans perte** (`detect_3d/compress_to=0` dans le `.import`),
     sinon la compression GPU fausse les vitesses.
   - Pour une autre journée de nuages, refaire les étapes 4 et 5 avec la même date.
6. Masque mers et océans (explosions sur la mer, voir « Explosions sur la mer ») :
   - télécharger la couche « ocean » de Natural Earth 1:10 M en GeoJSON (~10 Mo) :
     `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_ocean.geojson` ;
   - `godot --headless --path . --script res://tools/build_ocean_mask.gd -- <ne_10m_ocean.geojson>` (~1 s). Il écrit
     `assets/ocean_mask.res` (ressource `OceanMask`, ~2,4 Mo).

## Explosions nucléaires (`nuke/`)

Tout le code des explosions est dans `res://nuke/`. Objectif : une animation unique, paramétrée par la puissance
(10 kt à 50 Mt), vue depuis l'espace. **État actuel : socle de l'effet** (tir, placement, lois d'échelle,
horloge), **flash initial**, **onde de choc** (condensation, poussière), **incendies**, **trous dans la couche
nuageuse**, **champignon** (boule de feu comprise ; dérive selon le profil vertical du vent, dissipation et panache)
et **explosions sur la mer** (pas d'incendie au large, nuage de vapeur d'eau qui retombe vite).

- **Paramètres** (`nuke/nuke_params.gd`, Resource `NukeParams`) : `yield_kt` (10 à 50 000), `latitude_deg`,
  `longitude_deg`, `wind_direction_deg` (d'où vient le vent, convention météo) et `wind_speed_m_s`,
  `start_time_s` (instant sur l'horloge `NukeClock`), `burst_height_km` (0 = au sol, valeur par défaut),
  `over_ocean` (point zéro sur une mer ou un océan, renseigné au tir, voir « Explosions sur la mer »).
  - **Vent réel** (`nuke/nuke_wind.gd`) : au tir, le vent est lu au point d'impact dans la même carte que
    l'advection des nuages (`assets/textures/cloud_wind.exr`, vent GFS moyen du jour à 850/700/500 hPa, ~1,5 à
    5,5 km d'altitude, interpolation bilinéaire) : le trou dans la couche nuageuse dérive comme les nuages. Sans
    carte, la direction reste tirée au hasard.
  - **Profil vertical** (`wind_profile`, `NukeWind.sample_profile`) : le vent GFS du même jour à 14 altitudes, de
    ~1,5 à ~64 km (`assets/textures/wind_profile.exr`), interpolé linéairement en altitude par
    `NukeParams.wind_at()` (constant sous le premier niveau et au-dessus du dernier ; vide : le vent ci-dessus
    partout). C'est lui qui fait dériver le champignon. Le tir affiche le vent au niveau du chapeau. Exemple, 15 juillet
    à 42° N : vent de sud-ouest de 12 m/s en bas, 19 m/s à 17 km (courant-jet), vents d'est stratosphériques
    au-dessus de ~20 km (43 m/s à 49 km) : un 50 Mt part vers l'ouest quand le trou dans les nuages part vers le
    nord-est.
- **Lois d'échelle** (`nuke/nuke_scaling.gd`, classe statique `NukeScaling`, coefficients en tête de fichier), W en kt :

  | Grandeur | Formule | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|---|
  | Rayon de la boule de feu | 0,066 · W^0,4 km | 0,17 km | 1,05 km | 5,0 km |
  | Rayon de choc de référence | 2 · (W/10)^(1/3) km | 2 km | 9,3 km | 34 km |
  | Sommet du nuage | interpolation (voir ci-dessous) | 8 km | 22,5 km | 65 km |
  | Rayon du chapeau | 0,6 × sommet | 4,8 km | 13,5 km | 39 km |

  Sommet du nuage stabilisé (`CLOUD_TOP_POINTS`, interpolation log-log). Les hauteurs réelles varient beaucoup avec
  la météo et la tropopause (Glasstone & Dolan §2.16) :

  | Puissance | Sommet | Référence |
  |---|---|---|
  | 10 kt | 8 km | choix de jeu, entre l'exemple « typique » de Glasstone & Dolan (19 000 ft, 5,8 km, §2.17) et Nagasaki |
  | 20 kt | 11 km | « 7 miles » (Glasstone) ; Nagasaki (21 kt) : 45 000 ft (13,7 km) |
  | 1 Mt | 22,5 km | « 14 miles » (Glasstone) |
  | 15 Mt | 40 km | Castle Bravo ; Ivy Mike (10,4 Mt) : ~40 km |
  | 50 Mt | 65 km | Tsar Bomba (64 à 67 km) |

  Un champignon de 10 kt (8 km) reste sous le sommet d'une couche nuageuse épaisse (jusqu'à 10 km) : il n'est visible
  que par ciel dégagé ou à travers le trou creusé par l'onde de choc.

  Depuis 400 km, un pixel vaut ~0,5 km au nadir : la boule de feu de 10 kt (0,3 km de diamètre) fait moins d'un
  pixel ; c'est l'éblouissement du flash (billboard de taille angulaire minimale) qui la rend visible.

  Flash (même fichier) : puissance thermique au second maximum **P = 4 · W^0,56 kt/s** (Glasstone & Dolan,
  *The Effects of Nuclear Weapons*, §7.88), rayonnée dans toutes les directions, en « soleils » (1 361 W/m²) à la
  distance de référence de 400 km. **L'atmosphère absorbe ensuite cette lumière** selon le trajet (voir
  « Absorption par l'air » ci-dessous).

  Durées réelles (même source, §7.85) : second maximum thermique à **t_max = 0,0417 · W^0,44 s** ; l'essentiel de
  l'énergie thermique est émis avant 10 t_max. Le minimum entre les deux impulsions tombe à t_min = 0,0025 · W^0,5 s.

  **Entorse au réalisme** : le flash est joué **2 fois plus vite** (`FLASH_TIME_SCALE` = 0,5), avec la même forme
  d'impulsion, et l'onde de choc est ralentie de 1,6 (voir « Onde de choc »). À leurs vitesses réelles, la traîne du
  flash et l'éblouissement masquaient toute la vie de l'anneau de condensation (qui s'évapore vers 0,7 τ : 1,8 s à
  10 kt, 8 s à 1 Mt, 30 s à 50 Mt). Désormais l'anneau survit au flash : il reste visible seul ~2 s à 10 kt, ~9 s à
  1 Mt, ~24 s à 50 Mt.

  | | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|
  | Flux au pic à 400 km, sans atmosphère | 0,022 soleil | 0,29 soleil | 2,6 soleils |
  | Second maximum t_max (réel) | 0,12 s | 0,87 s | 4,9 s |
  | Durée réelle (10 t_max) | 1,2 s | 8,7 s | 49 s |
  | Durée jouée (× 0,5) | 0,6 s | 4,4 s | 24 s |

  Le flux décroît en 1/d² : depuis une orbite à 800 km, le flash paraît 4 fois moins fort qu'à 400 km.
- **Absorption par l'air** (`nuke/nuke_atmosphere.gd` pour l'observateur, `nuke_air_transmittance()` dans
  `nuke/shaders/nuke_flash.gdshaderinc` pour le sol et les nuages ; même calcul) : transmittance par canal (r, v, b)
  le long du segment source → récepteur. Elle utilise le modèle de la lumière solaire (`shaders/sun_light.gdshaderinc` :
  Rayleigh, hauteur d'échelle 8 km, et aérosols, 1,2 km), intégré en 8 pas resserrés près de l'extrémité basse.
  L'effet dépend donc de l'altitude du trajet :
  - vers l'espace (station), il traverse peu d'air : ~90 % transmis au nadir ;
  - près du sol (sol et nuages bas lointains), il est fortement atténué et rougi : un nuage à 100 km d'une
    explosion au sol ne reçoit plus qu'une lueur orangée ;
  - une explosion en altitude (`burst_height_km`) est moins atténuée qu'au sol.
- **Effet** (`nuke/nuke_effect.tscn`, script `nuke/nuke_effect.gd`, classe `NukeEffect`) : enfant du nœud `Earth`,
  placé au point (latitude, longitude) sur la sphère. Repère local : **Y = verticale locale**, X = est, −Z = nord,
  origine au point d'impact. Le nœud est mis à l'échelle 0,1 (`SCENE_UNITS_PER_KM`) : **ses enfants travaillent
  directement en km**, avec des coordonnées petites (bonne précision flottante). `get_time_s()` donne le temps
  physique écoulé depuis l'explosion (`time_override_s` ≥ 0 l'impose, pour rejouer l'effet).
  - Marqueurs de debug (`DebugMarkers`, `show_debug_markers`, désactivés par défaut) : boule de feu (sphère
    orange, centrée à la hauteur d'explosion), rayon de choc (anneau jaune au sol), colonne et chapeau du nuage
    (cyan, au sommet calculé). Rendus après les nuages et l'atmosphère (`render_priority` 2), masqués par la station.
- **Flash initial** (`nuke/nuke_flash.tscn`, script `nuke/nuke_flash.gd`, enfant `Flash` de l'effet). En temps
  normalisé u = t / durée jouée du flash (u = 1 ↔ 10 t_max réels), deux courbes `Curve` éditables dans la scène :
  - `intensity_curve` : part du flux au pic, avec la forme de l'impulsion thermique de Glasstone & Dolan :
    - bref premier pic (u = 0,002), puis minimum vers t_min (u ≈ 0,009) ;
    - second maximum à t_max (u = 0,1) ;
    - décroissance : 0,55 à 2 t_max, 0,3 à 3 t_max, 0,12 à 5 t_max, 0,05 à 7 t_max, 0 à 10 t_max ;
  - `growth_curve` : rayon de la boule de feu, en part du rayon final (5 % au départ, 45 % à t_min, 90 % à t_max,
    100 % à 3 t_max).

  Les tangentes des courbes valent la pente entre les points voisins (nulles aux extrema), sinon la courbe
  d'Hermite forme des paliers (l'éclat décroîtrait par marches). Elles sont lues avec `sample()` : la version
  précalculée (`sample_baked()`, 100 points) effacerait le premier pic.

  Il affiche :
  - **la boule de feu** (`nuke/shaders/nuke_fireball_flash.gdshader`) : sphère additive dont la luminance est
    physique, flux / angle solide rapportés au soleil (disque solaire = 40 000), plafonnée à 50 000 (format 16 bits).
    Elle est rendue avant les nuages (`render_priority` −1) : un banc nuageux la voile. Son rayon affiché est d'au
    moins 1,5 pixel (`min_fireball_pixels`), avec la luminance recalculée sur ce rayon (même flux total) : sinon,
    pour 10–100 kt, la sphère plus petite qu'un pixel apparaît et disparaît en défilant sous la station, et le flash
    décroît par saccades ;
  - **l'éblouissement** (`nuke/shaders/nuke_flare.gdshader`) : billboard additif (halo, cœur, étoile à 4 branches)
    construit en espace vue et ramené à mi-distance, pour passer devant la Terre et les nuages tout en restant
    masqué par la station. Taille angulaire et intensité suivent le flux reçu par l'observateur (1/d² ×
    transmittance de l'air, nul si la Terre cache le flash) ; réglages dans le groupe « Éblouissement » du script.
    Le cœur et les branches sont élargis à au moins un pixel (à énergie constante), pour ne pas scintiller quand le
    halo est petit.
- **Onde de choc** (`nuke/nuke_shock.tscn`, script `nuke/nuke_shock.gd`, enfant `Shock` de l'effet). Le front de
  choc ne brille que tant qu'il forme la surface de la boule de feu (première fraction de seconde, cf. le creux du
  double pic du flash). Une fois détaché, il refroidit et devient transparent : à 0,7 bar de surpression, l'air
  n'est chauffé que d'~50 °C. Ce qui brûle au loin, c'est le rayonnement thermique (voir « Incendies »). Depuis
  l'espace, on voit donc seulement :
  - **l'anneau de condensation** (nuage de Wilson) : la détente derrière le front refroidit l'air humide, qui
    condense un bref instant. Il est blanc, éclairé par le soleil (presque invisible de nuit) et suit le front. Il
    apparaît à p = 0,03, culmine à 0,12 et s'évapore à 0,5. Le front monte nettement côté intérieur et se dégrade
    vers l'extérieur ; son épaisseur s'amincit de 5 % à 1,2 % de R_max ;
  - **la jupe de poussière** autour du point zéro, pour les explosions basses (hauteur < ~2 rayons de boule de
    feu). Gris-brun (poussière mêlée de fumée), elle est soulevée par le front dès p = 0,05 et s'étend avec lui
    jusqu'à 60 % de R_max. Elle retombe ensuite lentement (constante de temps 8 τ). Vue en oblique, le voile
    atmosphérique réduit beaucoup son contraste ; elle ressort mieux près du nadir. Sur la mer, ce sont des
    **embruns** (eau pulvérisée) : même jupe, blanche (`spray` du shader).

  Rayon du front **r(t) = R_max · (1 − exp(−t / τ))**, avec une progression p = r / R_max :
  - R_max = `NukeScaling.shock_max_radius_km` = 1,2 × rayon de choc de référence + 4 km (`SHOCK_VISUAL_SCALE`,
    `SHOCK_VISUAL_MIN_KM`) : 6,4 km à 10 kt, 15 km à 1 Mt, 45 km à 50 Mt. **Choix visuel** : plus grand que le rayon
    de référence, surtout pour les petites puissances, pour que le trou creusé dans les nuages se voie (voir
    « Nuages ») ;
  - ce front unique porte l'anneau de condensation, soulève la poussière et **pousse les nuages devant lui** : le
    trou dans la couche nuageuse a exactement le même rayon à chaque instant ;
  - τ = 1,28 s par km de R_max serait la valeur réaliste : le front atteindrait 90 % de R_max à ~0,34 km/s de
    moyenne (la vitesse du son), avec une vitesse initiale de ~0,8 km/s ;
  - **entorse au réalisme** : l'onde est ralentie de `SHOCK_SLOWDOWN` = 1,6 (τ = 2,05 s/km : ~0,5 km/s au départ,
    ~0,2 km/s de moyenne), pour que l'anneau de condensation survive au flash (voir « Flash ») ;
  - l'anneau s'évapore vers 2,8 s à 10 kt, 13 s à 1 Mt, 48 s à 50 Mt ; le front atteint 98 % de R_max en ~16 s à
    10 kt, ~74 s à 1 Mt, ~270 s à 50 Mt (temps physique ; au-delà de 20 s, l'horloge accélère progressivement, voir
    « Horloge »).

  Shader unique et réutilisable (`nuke/shaders/nuke_shock_ring.gdshader`) :
  - un quad horizontal surélevé de 30 m, dont le centre est l'origine du maillage ;
  - paramètres par instance : rayon, demi-côté du quad, largeur du front, opacités de condensation et de
    poussière, rayon maximal de la poussière ;
  - matériau éclairé par les lumières de la scène, sans lumière ambiante, irrégularités par un bruit de valeur ;
  - largeurs élargies à au moins un pixel ;
  - rendu avant les nuages (`render_priority` −1) : un banc nuageux le voile.

  Réglages dans le script : groupes « Condensation » et « Poussière », `lift_km`.
- **Incendies** (`nuke/nuke_fire_fx.gd`, nœud `FireFX` créé par `NukeLauncher` ; `nuke/shaders/nuke_fire.gdshaderinc`,
  inclus dans `shaders/earth_surface.gdshader`). Ils sont allumés par le flash dans le rayon où l'exposition
  thermique dépasse ~10 cal/cm² (inflammation des matériaux courants, Glasstone & Dolan ch. VII).
  - Rayon : 12 km · (W / 1 Mt)^0,41, soit ~1,8 km à 10 kt, 12 km à 1 Mt et ~60 km à 50 Mt
    (`NukeScaling.fire_radius_km`).
  - Évolution (`NukeScaling.fire_intensity`), calée sur Hiroshima (tempête de feu formée ~20 min après
    l'explosion, au plus fort vers 2–3 h) :
    - 25 % de l'intensité finale dès le flash (foyers allumés par le rayonnement thermique) ;
    - les foyers se rejoignent entre 2 min et 1 h 30 ; intensité (0 à 1) : ~0,3 à 20 min, ~0,6 à 1 h, maximum
      ~0,7 vers 1 h 20 ;
    - le rayon s'étend de 15 % (constante de temps 1 h) ;
    - extinction progressive (constante de temps 4 h).
    - avec l'accélération de l'horloge (×10 après la rampe), 1 h 20 physique ≈ 8 min 30 s à l'écran.
  - Rendu, en émission sur le sol :
    - la part du sol en feu est forte au centre (l'exposition décroît en 1/d²) ;
    - seulement sur les terres (masque d'eau du sol) : **une mer ou un océan ne brûle pas**. Une explosion en mer
      sans aucune terre dans le rayon des incendies (`OceanMask.has_land_within`, `NukeEffect.can_ignite_land`)
      n'allume rien ; près d'une côte, le flash enflamme les terres à portée ;
    - plus forte et plus vive dans les villes (combustible, lu dans l'image des lumières nocturnes) ;
    - modulée par un motif irrégulier dont l'échelle suit la taille de la zone ;
    - bord très irrégulier, léger scintillement ;
    - voilée par les nuages comme les lumières des villes.
  - Depuis l'orbite (~0,5 km par pixel), on ne voit pas les flammes une à une, mais la lueur moyenne des zones en
    feu. Elle est faible devant un sol au soleil : les incendies se voient surtout de nuit.
  - `FireFX` transmet au sol les 8 incendies les plus intenses (position, rayon, intensité).
- **Champignon** (`nuke/nuke_mushroom.tscn`, script `nuke/nuke_mushroom.gd`, enfant `Mushroom` de l'effet ;
  shaders `nuke/shaders/nuke_mushroom_volume.gdshader`, `nuke/shaders/nuke_mushroom.gdshader` et
  `nuke/shaders/nuke_smoke.gdshader`).
  - **Rendu volumétrique** (par défaut, `volumetric`) : lancer de rayon dans un champ de densité, sur une boîte
    englobante (nœud `Volume`) recalculée à chaque image autour du nuage, de sa dérive et du nuage de base.
    - Densité : formes analytiques fondues en douceur, érodées par un bruit 3D sur une bande `edge_softness` (bords
      gazeux) :
      - chapeau : super-ellipse aplatie (`cap_power` 2,6 : dessus plat, bord arrondi), dessous creusé autour de la
        tige ;
      - tige : évasée au pied et sous le chapeau, dissoute avec l'âge ;
      - nuage de base.
    - **Asymétrie** : une déformation basse fréquence du domaine (`warp`) et des lobes autour du chapeau (`lobes`),
      tirés d'une graine propre à chaque explosion (latitude, longitude, puissance), rendent la silhouette
      irrégulière. S'y ajoute l'inclinaison par le vent.
    - Éclairage comme les nuages de la couche : marche vers le soleil (5 pas doublés depuis 0,3 km, auto-ombrage,
      loi de Beer et diffusion multiple approchée), phase double de Henyey-Greenstein, soleil filtré par
      l'atmosphère, ciel ambiant. La lueur de la boule de feu est émise au cœur du chapeau. Extinction : 1 km⁻¹
      (`volume_extinction_per_km`).
    - 64 pas par rayon, décalage d'échantillonnage fixe par pixel (pas de bruit temporel) : pas de scintillement.
    - Profondeur écrite par le shader : celle du premier point dense (alpha cumulé > 0,35), sinon un point juste
      au-dessus du sol. Les nuages et l'atmosphère, rendus après, ne le recouvrent que là où ils sont devant lui.
    - Coût mesuré : ~91 i/s avec un 50 Mt et un 1 Mt à l'écran (contre 120 i/s, plafond de la synchro verticale,
      sans champignon).
    - Les sections « Maillage de révolution », « Shader » et le nuage de base `BaseSurge` ci-dessous décrivent le
      rendu par maillage, conservé pour comparaison (`volumetric = false`) ; formes, Curves, couleurs, roulement et
      dérive sont partagés.
  - **Repère normalisé** : le nœud est mis à l'échelle `cloud_top_km`, tout est exprimé en unités où le sommet
    final vaut 1 (chapeau final de rayon 0,6). Le même champignon fait 8 km de haut à 10 kt, 22,5 km à 1 Mt et
    65 km à 50 Mt, particules comprises.
  - **Maillage de révolution** fixe (96 anneaux × 128 segments). Le profil (méridienne de 48 points : tige au pied et
    au col évasés, puis chapeau à dessous creusé, bord arrondi et dessus aplati) est recalculé à chaque image et
    posé par le vertex shader, qui l'interpole entre ses points.
  - **Dérive au vent** (`_update_drift`, `nuke/shaders/nuke_drift.gdshaderinc`) : profil vertical du vent réel GFS
    au point d'impact (`NukeParams.wind_profile`, voir « Paramètres »). Chaque altitude part avec son propre vent :
    - le déplacement est calculé en 32 hauteurs (0 à 1,4 sommet final) et interpolé par les shaders (volume,
      maillage) et pour les émetteurs de particules ;
    - pendant la montée (10 min), une parcelle garde sa hauteur relative dans le nuage qui monte : son déplacement
      intègre le vent des altitudes traversées (16 pas). Ensuite, chaque hauteur avance au vent de son altitude ;
    - le pied reste au point zéro : sous le centre du chapeau, la dérive est multipliée par (y / centre)^`drift_shear`
      (1,5), la tige penche ;
    - **cisaillement** : le vent diffère au-dessus et au-dessous du centre du chapeau. Le chapeau s'étire en panache
      dans le sens du cisaillement (en « stade » : un disque décalé le long d'une direction) et se tord quand la
      direction change avec l'altitude. Exemple (1 Mt, 42° N, 15 juillet) : courant-jet vers 13 km, vent presque nul
      vers 21 km, le panache s'étend sur ~80 km en 1 h ;
    - le bruit fin ne subit que 20 % du cisaillement (`noise_shear`) : étiré sur des dizaines de km, il se
      décorrélerait d'un pas de la marche à l'autre (grain, stries). La forme le subit en entier.
  - **Dissipation** (« Le nuage peut rester visible une heure ou plus avant d'être dispersé par les vents dans
    l'atmosphère environnante, où il se confond avec les nuages naturels », Glasstone & Dolan §2.16). Après la
    stabilisation (t > 10 min), constantes de `NukeScaling` :
    - **étalement** par la turbulence : R² = R0² + 4 K (t − 10 min), K = 2·10⁴ m²/s (`CLOUD_SPREAD_K_M2_S`, ordre de
      grandeur de la diffusivité horizontale aux échelles de 10 à 100 km). Rayon du chapeau : 1 Mt, 13,5 km →
      ~21 km à 1 h, ~36 km à 4 h ; 10 kt, 4,8 km → ~16 km à 1 h ;
    - **amincissement** : épaisseur × (R0 / R)^0,5 (`CLOUD_THIN_EXP`), centre du chapeau fixe ;
    - **dilution** (masse conservée) : densité × (R0 / R)^1,5, soit une épaisseur optique vue de dessus × (R0 / R)² ;
    - **disparition** (évaporation, dépôt, mélange) : × exp(−(t − 10 min) / τ), τ = 1 h pour un chapeau dans la
      troposphère, 2 h au-dessus de la tropopause (air sec et stable, pas de précipitations), avec un passage
      progressif sur ±2 km. Tropopause : 17 km à l'équateur, 9 km aux pôles, en cos² de la latitude
      (`NukeScaling.tropopause_km`) ;
    - **fragmentation** : le nuage dilué se déchire en lambeaux (trous de bruit basse fréquence, seuil 0,55 ×
      (1 − √densité), `breakup` du shader) ; la déformation verticale du domaine est réduite de R0 / R (couche mince) ;
    - le champignon est masqué sous 1 % de densité : ~2 h après un 10 kt, ~6 h après un 1 Mt (temps physique ;
      ~12 et ~36 min d'horloge avec l'accélération ×10). Effet visible : à 1 Mt, chapeau net à 30 min, panache
      étiré à 1 h, voile ténu à 2 h ;
    - la boîte englobante suit les hauteurs occupées : une fois la tige dissoute, elle ne descend plus jusqu'au sol
      et ne couvre que la dérive du chapeau (qui peut être à des centaines de km du point zéro) ;
    - rendu par maillage : opacité × la même densité.
  - **Contact avec le sol adouci** : l'opacité du champignon monte depuis 0 au sol jusqu'à 4 % du sommet final
    (`ground_fade` du shader), avec une limite rongée par le bruit.
  - **Nuage de base** (`BaseSurge`, explosions basses) : dôme de poussière bas, même shader et même couleur que le
    champignon.
    - Il s'étend vers l'extérieur avec l'onde de choc : rayon = 0,8 × front de choc (`surge_shock_ratio`), hauteur
      = 8 % de ce rayon (`surge_aspect`).
    - Translucide (`surge_opacity` 0,6), dense au centre, effiloché au bord.
    - Il s'estompe en même temps que la tige se dissout (même érosion).
  - **Profil piloté par des Curves** (éditables dans la scène), lues en âge a = t / 600 s physiques
    (`MUSHROOM_RISE_S`). Le nuage se stabilise en ~10 min quelle que soit la puissance, soit ~1 min 36 s
    d'horloge avec l'accélération des phases lentes :
    - `height_curve` : sommet, calé sur la montée d'un nuage de 1 Mt (Glasstone & Dolan 1977, §2.12, sommet final
      14 miles) : 14 % à 18 s, 29 % à 42 s, 43 % à 1 min 06, 71 % à 2 min 30, 86 % à 3 min 48, 96 % à 6 min ;
    - `cap_radius_curve` (rayon du chapeau), `cap_aspect_curve` (épaisseur / diamètre ; 1 = sphère),
      `stem_curve` (rayon de la tige / rayon du chapeau) ;
    - `erosion_curve` (domaine 0 à 3) : la tige se dissout après la stabilisation.
  - **Boule de feu** : au départ, le chapeau est une sphère de la taille de la boule de feu du flash, centrée à la
    hauteur d'explosion. Le flash s'estompe en la révélant, puis elle monte et s'aplatit en chapeau.
  - **Couleurs selon l'âge** :
    - lueur interne, au cœur du chapeau, `glow_gradient` × `glow_curve` × `glow_hdr` (200) : blanc, jaune,
      orange, rouge sombre, éteinte. Elle est lue en g = t / 70 t_max (`NukeScaling.fireball_glow_s` : ~8 s à
      10 kt, ~1 min à 1 Mt, ~5 min 40 s à 50 Mt ; Glasstone & Dolan §2.18) ;
    - albédo (`albedo_gradient`) : roux des oxydes d'azote, puis blanc-gris de la condensation.
  - **Shader** :
    - relief : bruit 3D (3 octaves) et bourgeons « chou-fleur » (bruit en valeur absolue) qui déplacent les
      sommets ; au pixel, la normale est perturbée par le gradient des bourgeons (`bump`). Ce détail plus fin que le
      maillage s'efface quand il devient plus petit qu'un pixel (sinon il crénèle en grains sombres). Creux et
      dessous du chapeau assombris ;
    - éclairage par le soleil seul, en diffus enveloppant, filtré par l'atmosphère au point
      (`sun_light.gdshaderinc` : rougi au crépuscule, éteint la nuit), plus la lumière du ciel en émission ;
    - silhouette adoucie par effet fresnel, bords rasants effilochés, érosion de la tige ;
    - **roulement toroïdal** : dans chaque plan méridien, le bruit du chapeau est lu en coordonnées tournées
      autour de l'anneau tourbillonnaire (rayon 0,55 × chapeau). Le motif monte au centre, s'écarte au sommet,
      redescend au bord et rentre par-dessous. Tour en 15 min physiques au début (`roll_period_s` : circulation de
      quelques dizaines de m/s autour d'un anneau de plusieurs km ; ~1 min 30 à l'écran avec l'horloge à ×10), puis
      de plus en plus lent (ω = ω0 / (1 + t / 300 s), intégré : rejouable au scrubber). Le bruit de la tige défile
      vers le haut à ~35 m/s à 1 Mt, ~100 m/s à 50 Mt (`stem_rise_speed` = 0,0015 × sommet par s) ; bouillonnement
      lent (`boil_rate`). Vus depuis l'orbite, ces mouvements doivent rester à peine perceptibles. Ces réglages valent
      pour les deux rendus ;
    - rendu avant les nuages (`render_priority` −1) avec pré-passe de profondeur : les nuages et l'atmosphère ne
      le recouvrent pas là où il les dépasse, mais un champignon plus bas que la couche nuageuse (10 kt sous un
      banc épais) reste caché dessous.
  - **Particules** (GPUParticles3D créés par le script, bouffées procédurales par bruit, éclairées comme le nuage) :
    - fumée le long de la tige (rendu par maillage seulement : en volumétrique, elle ferait doublon avec la tige du
      volume) ;
    - jupon de condensation : anneaux autour de la tige pendant la montée (a de 0,03 à 0,3) ;
    - débris et poussière aspirés au pied (explosions basses, a < 0,5).

    Leur vitesse suit celle du temps physique (`speed_scale` : pause et accélération de l'horloge). Elles ne se
    rejouent pas au scrubber. Pas de *soft particles* : elles liraient la texture de profondeur, peu fiable sous
    D3D12 dans ce projet ; les bords sont adoucis par la forme. Pas de flipbook (aucun dans le projet).
- **Explosions sur la mer** (règles de jeu) :
  - **Détection** (`scripts/ocean_mask.gd`, classe `OceanMask`, données `assets/ocean_mask.res`) : au tir,
    `NukeLauncher` demande `OceanMask.is_ocean(latitude, longitude)` et renseigne `NukeParams.over_ocean` (la console
    affiche « en mer »). Le masque vient du trait de côte Natural Earth 1:10 M (couche « ocean » : océans et mers
    reliées, la Caspienne comprise ; les lacs comptent comme de la terre). Il est stocké par lignes de latitude
    (120 par degré, ~0,9 km) : pour chaque ligne, les longitudes exactes où elle croise la côte ; un point est en mer
    si un nombre impair de croisements est à sa gauche. Précision : celle du trait de côte (quelques centaines de
    mètres) en longitude, ~0,5 km en latitude. Vérifié sur l'Atlantique, la Méditerranée, la Manche, la Baltique, la
    rade de Marseille (mer) et Paris, le Léman, le lac Michigan, l'Antarctique (terre), antiméridien compris. Coût :
    chargement ~60 ms au premier tir, puis une recherche dichotomique. Sans le fichier, tout est terre.
  - **Pas d'incendie sur l'eau** : voir « Incendies ». Au large (aucune terre à portée du flash), aucun feu.
  - **Nuage de vapeur d'eau** (explosion basse, même critère que la poussière ; `NukeScaling.low_burst`) : la boule
    de feu vaporise une grande masse d'eau (Glasstone & Dolan §2.50 et suivants). Dans `NukeMushroom` (groupe
    « Explosion sur la mer ») :
    - nuage blanc de vapeur condensée (`steam_albedo`, 85 % de `steam_whiteness`), chapeau en grosse boule
      (épaisseur / diamètre d'au moins `steam_aspect` = 0,75 au lieu de 0,42) ;
    - nuage de base d'embruns plus large (rayon = front de choc) et plus dense (0,85) ; au pied, des embruns blancs
      au lieu des débris ; jupe d'embruns blanche sous l'onde de choc ;
    - même montée que sur terre (stabilisation en 10 min), puis **l'eau retombe** : le nuage s'affaisse (hauteurs ×
      1 − 0,35 · (1 − exp(−(t − 10 min) / 15 min)), `NukeScaling.STEAM_SINK`, `STEAM_SINK_S`) et **disparaît vite**
      (densité × exp(−(t − 10 min) / 10 min), `STEAM_FADE_S`, en plus de la dissipation ordinaire). À 1 Mt : boule
      dense à 20 min, voile ténu à 35 min, masqué vers 50 min (temps physique, ~5 min d'horloge), contre ~6 h sur
      terre.
- **Nuages** (`nuke/nuke_cloud_fx.gd`, nœud `CloudFX` créé par `NukeLauncher` ; `nuke/shaders/nuke_clouds.gdshaderinc`) :
  l'onde de choc creuse un trou dans la couche nuageuse, qui se referme ensuite.
  - **Branchement** : l'include est appelé par `cloud_density()` (`shaders/cloud_density.gdshaderinc` : une ligne
    d'inclusion, un appel). Toute lecture de la densité est donc modifiée : rendu volumétrique, **ombres portées au
    sol**, voilage des lumières nocturnes et des incendies, lumière des flashs dans les nuages. Les ombres suivent
    le trou sans code dédié (vérifié : couche nuageuse masquée, le sol montre un disque éclairé dans la zone
    ombrée, décalé selon la direction du soleil).
  - **Trou** : à l'intérieur du rayon courant du front de choc, la densité est supprimée.
    - Rayon : celui du front qui porte l'anneau de condensation (`NukeScaling.shock_front_radius_km`, voir « Onde
      de choc ») : le front pousse les nuages devant lui, trou et anneau avancent ensemble.
    - Rayon final : 6,4 km à 10 kt, 15 km à 1 Mt, 45 km à 50 Mt (agrandi par rapport au rayon de choc de
      référence : un trou plus étroit que l'épaisseur de la couche, jusqu'à 7 km, ne serait qu'un puits sombre vu de
      biais).
    - **Bord flou** : largeur de 18 % du rayon, au moins 0,6 km (`nuke_cloud_edge_soft`, `nuke_cloud_edge_km`),
      rendue irrégulière par le bruit 3D des nuages (`nuke_cloud_edge_noise`, période 0,3 × rayon). Le sommet des
      nuages y descend en pente douce.
  - **Nuages poussés** : la carte est lue plus près du centre, ce qui déplace les nuages radialement vers
    l'extérieur. Le décalage vaut au plus 12 % du rayon du trou (`nuke_cloud_push`) et décroît en exp(−x / w) au-delà
    du bord (x : distance au bord ; w = 8 % du rayon, `nuke_cloud_rim_width`). La matière balayée est tassée contre
    le bord.
  - **Bourrelet** : densité × (1 + 0,6), sommet relevé de 25 % sur le bord (`nuke_cloud_rim_gain`,
    `nuke_cloud_rim_lift`), même décroissance.
  - **Retour des nuages** sur `recovery_s` (export de `CloudFX`, **1 200 s de temps physique** de l'explosion,
    ≈ 2 min d'horloge après l'accélération) :
    - chaque point se referme à partir du passage du front, t = −τ · ln(1 − r / R_max) ;
    - le bord se referme 2 fois plus vite que le centre (`nuke_cloud_edge_fill` = 1) : les nuages regagnent le trou
      du bord vers le centre ;
    - décalage et bourrelet s'estompent sur la même durée.

    Vu en jeu : à 10 kt, trou visible dès 3 s, sol visible au fond à 30 s ; à 1 Mt, ~15 km de rayon à 40 s ; à
    50 Mt, ~40 km à 2 min ; à moitié refermé vers 10 min, disparu vers 20 min.
  - **Dérive** : le centre du trou suit le vent du point d'impact (`NukeParams`, vent réel GFS), le même champ de
    vent que l'advection des nuages : le trou part avec la masse d'air.
  - **Données** : 16 explosions au plus (les plus récentes), deux `vec4` chacune, en tableaux d'uniforms
    `nuke_cloud_a` / `nuke_cloud_b` :
    - a = (centre x, y, z en km dans le repère de la planète, rayon courant du trou) ;
    - b = (rayon final du front R_max, τ, temps physique écoulé, puissance en kt).

    C'est la disposition de deux texels RGBA32F par explosion. Pour passer à une texture de données, seuls
    `nuke_cloud_event()` (shader) et `NukeCloudFX._upload()` changent. Une explosion sort de la liste quand son trou
    est refermé (t > `recovery_s` + 4 τ).
  - Coût : avec 16 trous actifs, la scène reste au plafond de 120 i/s (synchro verticale).
- **Lumière et effets d'écran du flash** (`nuke/nuke_flash_fx.gd`, nœud `FlashFX` créé par `NukeLauncher`), à
  chaque image, pour les flashs actifs :
  - **sol et nuages** : uniforms `nuke_flash_*` (les 4 flashs les plus intenses) de
    `nuke/shaders/nuke_flash.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` et
    `shaders/cloud_volume.gdshader`. Seul code des explosions hors de `nuke/` (avec celui des trous dans les
    nuages, voir « Nuages ») : une ligne d'inclusion et un appel dans chacun. Les lumières Godot ne conviennent pas ici : le sol a un `light()` propre au soleil, et les nuages
    sont unshaded.
    - Le **sol** reçoit flux × (400 km / d)² × cos(incidence) × transmittance de l'air, en émission (de jour
      comme de nuit). L'horizon local est respecté (exact sur une sphère), l'ombre des nuages est calculée sur le
      segment sol → flash (4 échantillons), et une petite part est diffusée par l'air (3 %, portée 60 km).
    - Les **nuages** reçoivent le même flux × transmittance de l'air, nul si la Terre s'interpose, avec
      auto-ombrage (marche vers le flash) et diffusion isotrope.
    - Unité : le « soleil » (le sol reçoit `nuke_flash_ground_gain` = 2, comme la lumière `Sun`). L'éclairement
      est plafonné à 2 000 près de la boule de feu.
  - **station** : `DirectionalLight3D` dirigée depuis le flash le plus intense (à 400 km la source est à l'infini
    pour une station de 3 m). Énergie = flux reçu × 2 (un soleil), ombres portées des montants. Elle n'éclaire que
    la station : `FlashFX` ajoute le calque 20 à tous ses maillages, et la lumière a ce seul calque dans son masque.
  - **éblouissement**, comme un œil : ébloui par la *montée* de la lumière, il s'adapte ensuite même si le flash
    dure (jusqu'à ~12 s joués pour 50 Mt) :
    - l'intensité du glow suit le flux reçu : `glow_intensity` + 2·g, avec g = flux reçu / (flux reçu + 0,2). La
      source reste éclatante tant qu'elle brille ;
    - le bloom (`glow_bloom` + 0,5·e) et le multiplicateur d'exposition de la caméra (× (1 + 2,5·e)) suivent
      l'éblouissement e = excès / (excès + 0,2), l'excès étant le flux reçu au-delà d'un niveau d'adaptation qui
      le rattrape en 1,5 s (temps réel, `adaptation_s`) ;
    - tout revient aux valeurs d'origine à la fin du flash, et l'exposition automatique réagit ensuite d'elle-même ;
    - un 50 Mt sature l'écran à la montée du flash ; un 10 kt laisse un éclat net sans saturation.
- **Horloge** (`nuke/nuke_clock.gd`, autoload `NukeClock`), distincte du temps réel :
  - `time_s` avance au rythme du temps de l'orbite (**Pause, x2… x16 s'appliquent aussi aux explosions**),
    multiplié par `acceleration` (1 par défaut) ;
  - le temps physique d'une explosion défile en temps réel pendant `realtime_phase_s` (20 s : flash, boule de
    feu, onde de choc). Sa vitesse monte ensuite **progressivement** (smoothstep) sur `ramp_s` (40 s d'horloge)
    jusqu'à `slow_phase_acceleration` (×10), pour la montée et l'étalement du champignon ;
  - la rampe évite un saut de vitesse : un effet encore en cours à 20 s ne se met pas à filer d'un coup (l'anneau
    de condensation d'un 50 Mt s'évapore vers 35 s d'horloge, à ×3,8) ;
  - repères : 60 s d'horloge = 240 s physiques, 10 min physiques ≈ 1 min 36 s d'horloge, 3 h ≈ 19 min ;
  - `to_physical()` (intégrale de la vitesse) et `to_clock()` (réciproque, par dichotomie) convertissent.
- **Tir** (`nuke/nuke_launcher.gd`, nœud `NukeLauncher` de `orbit_view.tscn`, groupe `nuke_launcher`) : rayon partant
  de la caméra par le centre de l'écran, intersecté analytiquement avec la sphère terrestre (6371 km, soit 637,1 u).
  Le point touché est converti dans le repère local du nœud `Earth` (qui tourne avec la planète) et en
  latitude / longitude (même convention que `Orbit` et les UV de la sphère). Si le rayon manque la Terre, rien ne
  se passe. La station n'est pas prise en compte : viser à travers un montant de la Cupola tire quand même.
  - `get_aim()` : point visé (`local`, `latitude`, `longitude`) ou `{}` ;
  - `launch(yield_kt)` : tire sur le point visé et retourne la `NukeEffect` créée ; sans cible, retourne `null`
    sans rien faire ;
  - `launch_at(latitude, longitude, yield_kt)` : tire sur des coordonnées ; `fire(params)` : à partir d'une
    `NukeParams` ;
  - signal `detonated(effect)` ; `get_effects()`, `clear_effects()`. Les explosions restent en place (pas encore
    de fin d'effet).
  - Au démarrage, il lie `NukeClock` au nœud `Orbit` (`orbit_path`).
- **Interface** : colonne `Launch` du panneau de contrôle (`nuke/launch_control.gd`) : gros bouton rouge
  (`nuke/big_red_button.gd`, dessiné à la main) et, en dessous, les boutons de puissance. Au clic, le capuchon
  s'enfonce, reste un instant en bas puis remonte avec un léger rebond. Réticule au centre de l'écran
  (`nuke/aim_reticle.gd`) : rouge avec la latitude et la longitude du point visé quand la vue vise la Terre, gris
  sinon.
- **Scène de debug** (`nuke/debug/nuke_debug.tscn`, à lancer avec F6 ; instancie `orbit_view.tscn` et ajoute le
  panneau `nuke/debug/nuke_debug_panel.gd` en haut à gauche) :
  - curseur de puissance en échelle logarithmique (10 kt à 50 Mt), avec les tailles calculées ;
  - champs latitude / longitude (Madrid par défaut), bouton **Point visé** (recopie le centre de la vue),
    **Tirer**, **Effacer** ;
  - case **Marqueurs** (marqueurs de taille des explosions) ;
  - scrubber du temps physique (0 à 6 h, pour voir la dissipation du champignon ; non linéaire : t = 6 h · v⁵, les
    3 premières secondes occupent 17 % de la course, les 10 premières minutes la moitié) : il suit la dernière explosion tirée depuis ce panneau ; le déplacer (ou cocher
    **Rejouer**) fige toutes les explosions au temps choisi, décocher rend la main à l'horloge.

## Sources des textures

Toutes issues de la NASA, de la NOAA ou de Natural Earth, domaine public (crédit demandé) :

| Fichier | Contenu | Source |
|---|---|---|
| `assets/earth_tiles/*.jpg` | Blue Marble Next Generation, juillet 2004, sans relief ombré, 500 m/px (2592 tuiles, ~260 Mo) | NASA Visible Earth / Earth Observatory, image 74092 |
| `assets/textures/earth_bluemarble_16k.jpg` | Même source réduite à 16384 × 8192 | idem |
| `assets/earth_night_tiles/*.jpg` | Black Marble 2016 (lumières nocturnes, composite couleur), 500 m/px (2592 tuiles, ~180 Mo) | NASA Earth Observatory, image 144898 |
| `assets/textures/earth_night_16k.jpg` | Même source réduite à 16384 × 8192 | idem |
| `assets/earth_cloud_tiles/*.webp` | Couverture nuageuse (alpha) du 15 juillet 2023, déduite de VIIRS NOAA-20 Corrected Reflectance True Color, 500 m/px (2592 tuiles, ~350 Mo) | NASA GIBS / Worldview (données LANCE/VIIRS) |
| `assets/textures/earth_clouds_16k.jpg` | Même couverture, 16384 × 8192 | idem |
| `assets/textures/earth_clouds_8k.jpg` | Couverture nuageuse Blue Marble, 8192 × 4096 : utilisée seulement par l'outil, pour combler les zones sans données VIIRS | NASA Visible Earth / Earth Observatory, image 57747 |
| `assets/textures/starmap_4k.exr` | Deep Star Maps 2020, 4096 × 2048, HDR | NASA Scientific Visualization Studio, animation 4851 |
| `assets/textures/cloud_wind.exr` | Vent moyen du 15 juillet 2023 (850–500 hPa), 720 × 360 | NOAA, modèle GFS, analyses 0,25° (NOAA Open Data Dissemination, AWS) |
| `assets/textures/wind_profile.exr` | Profil vertical du vent du même jour (14 niveaux, 850 à 0,1 hPa) et altitude de chaque niveau, 360 × 180 par niveau (~11 Mo) | idem |
| `assets/ocean_mask.res` | Masque mers et océans (croisements du trait de côte par ligne de latitude, ~2,4 Mo) | Natural Earth 1:10 M, couche « ocean » (domaine public) |

Limites des nuages réels : c'est un instantané déplacé par le vent (les nuages ne se forment ni ne se dissipent, et
la journée se répète). On voit quelques raccords entre
passages successifs du satellite (lignes droites dans les champs de nuages), et la banquise arctique est en partie
comptée comme nuage.
