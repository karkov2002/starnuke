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
   - Le service OPeNDAP de la NOAA, plus simple, était hors service ; la réanalyse NCEP (2,5°) aurait été trop
     grossière pour les cyclones.
   - L'import Godot de cette texture doit rester **sans perte** (`detect_3d/compress_to=0` dans le `.import`), sinon
     la compression GPU fausse les vitesses.
   - Pour une autre journée de nuages, refaire les étapes 4 et 5 avec la même date.

## Explosions nucléaires (`nuke/`)

Tout le code des explosions est dans `res://nuke/`. Objectif : une animation unique, paramétrée par la puissance
(10 kt à 50 Mt), vue depuis l'espace. **État actuel : socle de l'effet** (tir, placement, lois d'échelle,
horloge) et **flash initial** ; les phases suivantes (boule de feu, champignon) restent à faire.

- **Paramètres** (`nuke/nuke_params.gd`, Resource `NukeParams`) : `yield_kt` (10 à 50 000), `latitude_deg`,
  `longitude_deg`, `wind_direction_deg` (d'où vient le vent, convention météo) et `wind_speed_m_s`,
  `start_time_s` (instant sur l'horloge `NukeClock`), `burst_height_km` (0 = au sol, valeur par défaut).
  - **Vent réel** (`nuke/nuke_wind.gd`) : au tir, le vent est lu au point d'impact dans la même carte que
    l'advection des nuages (`assets/textures/cloud_wind.exr`, vent GFS moyen du jour à 850/700/500 hPa, ~1,5 à
    5,5 km d'altitude, interpolation bilinéaire). Le panache dérivera donc comme les nuages. Limite : c'est le vent
    de la basse et moyenne troposphère, pas celui de la stratosphère où monte le chapeau des fortes puissances.
    Sans carte, la direction reste tirée au hasard.
- **Lois d'échelle** (`nuke/nuke_scaling.gd`, classe statique `NukeScaling`, coefficients en tête de fichier), W en kt :

  | Grandeur | Formule | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|---|
  | Rayon de la boule de feu | 0,066 · W^0,4 km | 0,17 km | 1,05 km | 5,0 km |
  | Rayon de choc de référence | 2 · (W/10)^(1/3) km | 2 km | 9,3 km | 34 km |
  | Sommet du nuage | 10 · (W/10)^0,22 km | 10 km | 27,5 km | 65 km |
  | Rayon du chapeau | 0,6 × sommet | 6 km | 16,5 km | 39 km |

  Depuis 400 km, un pixel vaut ~0,5 km au nadir : la boule de feu de 10 kt (0,3 km de diamètre) fait moins d'un
  pixel ; c'est l'éblouissement du flash (billboard de taille angulaire minimale) qui la rend visible.

  Flash (même fichier) : puissance thermique au second maximum **P = 4 · W^0,56 kt/s** (Glasstone & Dolan,
  *The Effects of Nuclear Weapons*, §7.88), rayonnée dans toutes les directions, en « soleils » (1 361 W/m²) à la
  distance de référence de 400 km ; durée 2 s · (W / 1 Mt)^0,1. **L'atmosphère absorbe ensuite cette lumière**
  selon le trajet (voir « Absorption par l'air » ci-dessous).

  | | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|
  | Flux au pic à 400 km, sans atmosphère | 0,022 soleil | 0,29 soleil | 2,6 soleils |
  | Durée du flash | 1,3 s | 2 s | 3 s |

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
  normalisé u = t / durée du flash, deux courbes `Curve` éditables dans la scène :
  - `intensity_curve` : part du flux au pic, avec la forme du double pic thermique (bref premier pic à u = 0,006,
    creux, second maximum à u = 0,1, décroissance jusqu'à 0 à u = 1) ;
  - `growth_curve` : rayon de la boule de feu, en part du rayon final (5 % → 100 % à u = 0,3).

  Il affiche :
  - **la boule de feu** (`nuke/shaders/nuke_fireball_flash.gdshader`) : sphère additive dont la luminance est
    physique, flux / angle solide rapportés au soleil (disque solaire = 40 000), plafonnée à 50 000 (format 16 bits).
    Elle est rendue avant les nuages (`render_priority` −1) : un banc nuageux la voile ;
  - **l'éblouissement** (`nuke/shaders/nuke_flare.gdshader`) : billboard additif (halo, cœur, étoile à 4 branches)
    construit en espace vue et ramené à mi-distance, pour passer devant la Terre et les nuages tout en restant
    masqué par la station. Taille angulaire et intensité suivent le flux reçu par l'observateur (1/d² ×
    transmittance de l'air, nul si la Terre cache le flash) ; réglages dans le groupe « Éblouissement » du script.
- **Lumière et effets d'écran du flash** (`nuke/nuke_flash_fx.gd`, nœud `FlashFX` créé par `NukeLauncher`), à
  chaque image, pour les flashs actifs :
  - **sol et nuages** : uniforms `nuke_flash_*` (les 4 flashs les plus intenses) de
    `nuke/shaders/nuke_flash.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` et
    `shaders/cloud_volume.gdshader`. Seul code des explosions hors de `nuke/` : une ligne d'inclusion et un appel
    dans chacun. Les lumières Godot ne conviennent pas ici : le sol a un `light()` propre au soleil, et les nuages
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
  - **éblouissement** : avec g = flux reçu / (flux reçu + 0,2), le glow de l'Environment (`glow_intensity` + 2·g,
    `glow_bloom` + 0,5·g) et le multiplicateur d'exposition de la caméra (× (1 + 2,5·g)) sont relevés, puis rendus
    à leurs valeurs d'origine. L'exposition automatique réagit ensuite d'elle-même : l'image s'assombrit après le
    flash puis récupère en quelques secondes. Un 50 Mt sature l'écran ; un 10 kt laisse un éclat net sans
    saturation.
- **Horloge** (`nuke/nuke_clock.gd`, autoload `NukeClock`), distincte du temps réel :
  - `time_s` avance au rythme du temps de l'orbite (**Pause, x2… x16 s'appliquent aussi aux explosions**),
    multiplié par `acceleration` (1 par défaut) ;
  - le temps physique d'une explosion défile en temps réel pendant `realtime_phase_s` (20 s : flash, boule de
    feu, onde de choc), puis `slow_phase_acceleration` (×10) plus vite (montée et étalement du champignon) ;
    `to_physical()` / `to_clock()` convertissent.
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
  - scrubber du temps physique (0 à 15 min, non linéaire : t = 15 min · v⁴, les 3 premières secondes occupent un
    quart de la course) : il suit la dernière explosion tirée depuis ce panneau ; le déplacer (ou cocher
    **Rejouer**) fige toutes les explosions au temps choisi, décocher rend la main à l'horloge.

## Sources des textures

Toutes issues de la NASA ou de la NOAA, domaine public (crédit demandé) :

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

Limites des nuages réels : c'est un instantané déplacé par le vent (les nuages ne se forment ni ne se dissipent, et
la journée se répète). On voit quelques raccords entre
passages successifs du satellite (lignes droites dans les champs de nuages), et la banquise arctique est en partie
comptée comme nuage.
