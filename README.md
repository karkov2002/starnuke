# starnuke

POC Godot 4.7 : vue depuis une station spatiale en orbite basse (~400 km), depuis la Cupola de l'ISS.
Jeu « d'ambiance » : la priorité est une vue de la Terre la plus réaliste possible.

## Lancer

Ouvrir le projet dans Godot 4.7 puis F5 (scène principale : l'écran de démarrage `res://scenes/ui/main_menu.tscn` ;
la vue orbitale `res://scenes/orbit_view.tscn` se lance aussi seule, F6).
Les tuiles haute résolution (`assets/earth_tiles/`, `assets/earth_night_tiles/`) doivent avoir été générées (voir plus bas).

## Version distribuable (Windows)

`powershell -ExecutionPolicy Bypass -File tools/package_game.ps1` (modèles d'export Godot 4.7.2 installés ; l'éditeur
peut rester ouvert) construit `../exe/starnuke/` et `../exe/StarNuke.zip` (~1 Go) :
- export « release » du preset « Windows Desktop » (`export_presets.cfg`) : `Star Nuke.exe` et `Star Nuke.pck`
  (~450 Mo : toutes les ressources, plus `assets/population_2030.bin`, fichier brut ajouté par `include_filter` ;
  `tools/` et le cache du MCP, `addons/godot_mcp/cache/`, ~500 Mo de captures, exclus par `exclude_filter`) ;
- tuiles HD (`assets/earth_tiles`, `earth_night_tiles`, `earth_cloud_tiles`, 3 × 2 592 fichiers) copiées dans
  `assets/` à côté de l'exécutable : leurs dossiers ont un `.gdignore` et ne peuvent pas entrer dans le `.pck`, mais
  un fichier `res://` absent du `.pck` est cherché dans le dossier de l'exécutable, où le jeu les trouve ;
- archive zip du dossier (tar de Windows).

Pour jouer : dézipper, lancer `Star Nuke.exe` (Windows 10/11 64 bits, carte graphique Direct3D 12). Vérifié : jeu
exporté sur un écran 5120 × 1440 (fenêtre maximisée, tuiles HD, bilan des pertes). Le module MCP (`MCPRuntime`) reste
dans l'export : il ne fait rien sans serveur MCP sur la machine, mais en présence de celui-ci (développement) il
permet de piloter le jeu exporté.

## Écran de démarrage, paramètres et langues

- **Écran de démarrage** (`scenes/ui/main_menu.tscn`, script `scripts/ui/main_menu.gd`, construit en code) : fond
  noir, titre provisoire « Star Nuke », boutons **Start Game** (charge `orbit_view.tscn`), **Settings** (écran des
  paramètres, par-dessus) et **Quit**. Après **Start Game**, la scène du jeu est chargée en tâche de fond
  (`ResourceLoader.load_threaded_request`, quelques secondes) : le menu laisse place à « Loading in progress… »
  (clé `MENU_LOADING`, points animés et pourcentage), qui reste affiché pendant la mise en place de la scène.
- **Écran des paramètres** (`scenes/ui/settings_menu.tscn`, script `scripts/ui/settings_menu.gd`) : onglets
  **Video**, **Audio**, **Controls**, **Game** ; Audio et Controls sont à venir (onglets désactivés, infobulle
  « Coming soon »). **Back** ou Échap pour revenir. Chaque choix est appliqué et sauvé aussitôt.
  - **Video** : mode d'affichage (**fenêtré** / **plein écran**) et **résolution**.
    - Fenêtré : la résolution est la taille de la fenêtre, centrée dans la zone utile de l'écran ; une fenêtre qui
      n'y tient pas avec sa bordure et sa barre de titre (résolution native, par exemple) est maximisée.
    - **Jeu lancé depuis l'éditeur** : par défaut, Godot 4.7 l'intègre dans l'onglet « Jeu » (lancé avec `--wid` et
      `--resolution 1920x1080`) et impose la fenêtre. Les changements d'affichage y sont seulement sauvés
      (`GameSettings.can_change_display`, `Engine.is_embedded_in_editor`), avec un avertissement dans l'onglet Vidéo.
      Pour les tester : désactiver l'intégration du jeu (menu d'options de l'onglet Jeu) ou lancer le jeu hors de
      l'éditeur (`godot --path <projet>`, ou version exportée). Vérifié hors éditeur sur un écran 5120 × 1440 :
      plein écran 5120 × 1440 ; fenêtré 1280 × 720 centré ; fenêtré natif maximisé.
    - Plein écran : la fenêtre couvre tout l'écran à sa résolution native (Godot ne change pas le mode vidéo de
      l'écran ; plein écran sans bordure, `WINDOW_MODE_FULLSCREEN`). La résolution choisie règle celle du **rendu
      3D** (`Viewport.scaling_3d_scale` = hauteur choisie / hauteur de l'écran, au moins 0,25) ; l'interface reste
      nette à la résolution native. Utile pour gagner des images par seconde sur un très grand écran.
    - Résolutions proposées : formats courants 16:9 (1280 × 720 à 7680 × 4320), 16:10 (1280 × 800 à
      3840 × 2400), 21:9 (2560 × 1080, 3440 × 1440, 3840 × 1600, 5120 × 2160) et 32:9 (3840 × 1080, 5120 × 1440,
      7680 × 2160), jusqu'à la taille de l'écran, plus celle de l'écran (« native »). Le jeu n'a pas de limite
      propre (Godot rend jusqu'à 16384 px de côté) ; la limite pratique est le GPU (le jeu est limité par le GPU :
      5120 × 1440 = 7,4 Mpx, 3,6 fois 1920 × 1080).
    - **Écrans ultra-larges** (21:9, 32:9) : étirement `canvas_items` / `expand` du projet (base 1920 × 1080). La vue
      3D garde son champ de vision vertical et s'élargit (`Camera3D.keep_aspect` = hauteur) ; l'interface garde sa
      taille et s'étend sur toute la largeur (panneau en bas au centre, bilan en haut à droite).
  - **Game** : **langue** (English, Français, Español, Deutsch, Italiano ; anglais par défaut), appliquée en direct.
- **Sauvegarde** (autoload `GameSettings`, `scripts/game_settings.gd`) : `user://settings.cfg` (sous Windows
  `%APPDATA%/Godot/app_userdata/Star Nuke/settings.cfg`), réappliqué au lancement suivant. Sections `[video]`
  (`window_mode` = `"fullscreen"` / `"windowed"`, `resolution`, `Vector2i(0, 0)` = native) et `[game]`
  (`locale`). Premier lancement : plein écran, résolution native, anglais.
- **Langues** (règle du projet : **tous les textes du jeu sont dans des fichiers de langue**) : tableaux CSV importés
  par Godot (`TranslationServer`), une colonne par langue (`en`, `fr`, `es`, `de`, `it`), déclarés dans
  `project.godot` (`internationalization/locale/translations`) :
  - `locale/strings.csv` : textes de l'interface (clés `MENU_*`, `SETTINGS_*`, `TAB_*`, `VIDEO_*`, `GAME_*`,
    `HUD_*`, `REPORT_*`, `DIR_*` pour les points cardinaux) ;
  - `locale/countries.csv` : noms des pays (`COUNTRY_<ADM0_A3>`, code de `CountryMask`) et des États souverains
    (`SOVEREIGN_<SOV_A3>`), générés par `tools/build_country_names.gd` à partir de Natural Earth (champs NAME_EN,
    NAME_FR, NAME_ES, NAME_DE, NAME_IT ; 258 pays, 209 États).

  Dans le code, un texte fixe est la clé elle-même (`label.text = "MENU_START"` : traduction automatique des
  contrôles) ; un texte composé passe par `tr()` et des champs nommés (`tr("HUD_ALTITUDE").format({"altitude": …})`,
  pour que chaque langue place les valeurs où elle veut), sur un contrôle dont la traduction automatique est coupée
  (`auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED`). Formats des nombres selon la langue
  (`NukeReportText.number_style` : « 1,230,000 » en anglais, « 1 230 000 » en français, « 1.230.000 » en
  espagnol, allemand, italien). Ajouter un texte : une ligne dans le CSV (les 5 langues), réimport automatique par
  l'éditeur ; les fichiers `.translation` produits par l'import ne sont pas versionnés (`.gitignore`). Ajouter une
  langue : une colonne dans les deux CSV, son code dans `GameSettings.LOCALES` et son nom dans
  `GameSettings.LOCALE_NAMES`.
  - Restent en français (outils de développement, hors interface du jeu) : la console (bilan détaillé des tirs,
    `NukeReportText`) et le panneau de debug des explosions (`nuke/debug/`).

## Contrôles

| Action | Contrôle |
|---|---|
| Orienter la vue | Maintenir le **clic droit** et déplacer la souris (lacet et tangage autour des axes de la tête) ; **A / E** (AZERTY, Q / E en QWERTY) : **roulis** gauche / droite autour de l'axe du regard (60°/s, mise en rotation et arrêt progressifs). Orientation libre comme en apesanteur : pas de « haut » imposé, tangage non limité |
| Se déplacer dans la station | **Z / S** (W / S en QWERTY) ou **flèches haut / bas** : avancer / reculer dans la direction du regard (y compris vers le haut ou le bas, apesanteur) ; **Q / D** (A / D en QWERTY) ou **flèches gauche / droite** : déplacement latéral. 1,5 m/s ; inertie d'apesanteur : démarrage et arrêt en douceur (~1 s), on continue sur sa lancée un instant après avoir relâché la touche ; collisions avec les parois, les vitres et les objets intérieurs (tubes des silos…) |
| Curseur | Libre le reste du temps (clic gauche sur le panneau de contrôle) |
| Altitude | Curseur du panneau, **200 à 800 km** (clic, glisser ou molette) |
| Inclinaison de l'orbite | Curseur du panneau, **0 à 70°**, bornée par la latitude courante (voir ci-dessous) |
| Date et heure (UTC) | Champ **date** (AAAA-MM-JJ, valider par Entrée), boutons **−1 j / +1 j**, curseur de l'**heure** du jour. La station reste au-dessus du même point ; le soleil, les étoiles et les nuages (poussés par le vent) se placent selon la nouvelle heure. Départ : **15 juillet 2035** |
| Vitesse du temps | Boutons **Pause, x1, x2, x4, x8, x16** |
| Redémarrer | Boutons **By day** / **By night** (« De jour » / « De nuit » en français) : temps remis à zéro, station au-dessus de l'Espagne (Madrid, 40,4° N 3,7° O, phase montante) à **midi** / **minuit** heure solaire locale, le même jour ; l'altitude est conservée, l'inclinaison relevée à 40,4° si elle était plus faible |
| Silos | **48 voyants ronds numérotés de 1 à 48** à droite du panneau, un par tube de lancement, en 2 blocs de 3 × 8 placés comme les deux silos sur la station (vue de dessus, l'avant en haut ; silo 1 à gauche). **Orange** : missile prêt ; clic → **vert** : tube choisi pour le prochain tir (un seul à la fois, nouveau clic pour annuler) ; **gris** : tube vide. **48 missiles en tout**, sans rechargement. Choisir un tube **ouvre sa trappe** (animation Blender) et allume à côté un **gyrophare rouge** à éclats, qui éclaire la trappe et le dessous de la coque ; le tube choisi auparavant referme sa trappe et éteint son gyrophare (de même si on annule le choix). Après le tir, quand le missile a quitté la station, la trappe se referme et le gyrophare s'éteint |
| Tir nucléaire | **Gros bouton rouge** à droite des silos : lance le missile du **tube choisi (vert)** sur le point de la Terre visé par le **centre de la vue** (réticule), avec la puissance choisie sous les silos (**10 kt, 100 kt, 500 kt, 1 Mt, 10 Mt, 50 Mt** ; 1 Mt par défaut). Le point visé et la puissance sont figés à l'appui. Le missile sort de son tube (animation de lancement, 5 s : trappe, descente, allumage), le tube passe au gris, puis le missile poursuit sa ligne droite en accélérant, s'incurve vers le point visé et s'éloigne en rétrécissant jusqu'à n'être plus qu'un point lumineux ; l'explosion a lieu à son arrivée, **10 s** de temps de jeu après sa sortie de l'animation (durée provisoire, `flight_time_s` de `nuke/launch_control.gd`, en attendant une durée de vol réaliste ; le vol se fige en pause et s'accélère avec le temps). Sans tube choisi, ou si le centre de la vue ne vise pas la Terre (ciel, au-delà du limbe), il ne se passe rien et le missile reste dans son tube. Voir « Explosions nucléaires » |
| Bilan des explosions | Fenêtre **« Bilan des explosions »**, ouverte au premier tir (en haut à droite) : pays touchés et pertes, cumulées sur toutes les explosions. **Glisser sa barre de titre** (clic gauche maintenu) pour la déplacer ; bouton **—** / **+** pour la replier ; molette ou barre de défilement pour parcourir la liste |

Pendant la rotation le curseur est masqué, puis replacé là où le clic droit a commencé.
Les touches sont définies par leur **position physique** sur le clavier (actions `move_forward`, `move_back`,
`move_left`, `move_right`, `roll_left`, `roll_right` de `project.godot`) : la même disposition en AZERTY et en QWERTY.
Elles sont ignorées pendant la saisie du champ date.
L'inertie (`smooth_toward` de `scripts/station_camera.gd`) est un double lissage exponentiel : la commande est lissée,
puis la vitesse est lissée vers la commande lissée, ce qui donne une courbe en S sans à-coup au départ ni à l'arrivée
(constantes de temps : 0,25 s en translation, 0,2 s en roulis). La souris garde un léger lissage (0,08 s) pour rester
précise à la visée.

**Le panneau de contrôle et le réticule de tir n'apparaissent que dans la cupola** (sphère de 1,6 m autour du repère
`Point_Vue_Cupola`, `Station.is_in_cupola`) : en sortant de la cupola ils disparaissent en fondu (0,5 s), et
réapparaissent en fondu en y revenant. Hors de la cupola, on ne peut donc pas tirer.

**Panneau de contrôle** (`scenes/ui/orbit_controls.tscn`, script `scripts/orbit_controls.gd`), en bas au centre.
Il affiche l'altitude et la période orbitale, l'inclinaison et le point survolé (latitude, longitude), ainsi que
la date et l'heure UTC et l'heure solaire locale du point survolé. Les curseurs agissent en direct sur le nœud `Orbit`. Hors manipulation, ils affichent les
valeurs réellement appliquées. Le panneau a une largeur fixe et ne bouge pas quand les valeurs changent. Sa
dernière colonne (bouton de tir et puissance) vient de `nuke/`.

**Fenêtre « Bilan des explosions »** (nœud `NukeReport` de `scenes/orbit_view.tscn`, script
`nuke/nuke_report_panel.gd`, construite en code). Elle apparaît au premier tir, en haut à droite, et disparaît
quand il n'y a plus d'explosion (« Effacer » du panneau de debug).
- Résumé : nombre d'explosions, total des morts et des blessés **à l'instant présent** (au temps de chaque
  explosion : flash, onde de choc, décès des blessés, retombées ; voir « Pertes humaines »), puis la projection à
  60 jours (bilan final du souffle et de la chaleur + retombées), avec « bilan : calcul en cours… » tant que
  leur calcul tourne.
- Liste défilante (260 px) des pays touchés, cumulés sur toutes les explosions et triés par morts décroissants
  (à égalité, par nombre d'explosions). Colonnes :
  - **Expl.** : nombre d'explosions dont le point zéro est sur le territoire du pays (« — » pour un pays touché
    seulement par une explosion voisine : l'Allemagne après un tir sur Bâle) ;
  - **Morts**, **Blessés** ;
  - **Population** : part de la population du pays tuée (« 0 % » sans mort).
  Un territoire dépendant est suivi de son État souverain. Un pays sous black-out national est en jaune, marqué ⚡
  (infobulle), même sans perte humaine ; un pays visé sans perte (désert) apparaît aussi. Les lignes sont
  regroupées par code de pays (`CountryMask`).
- Fenêtre déplaçable comme sous Windows : clic gauche maintenu sur la barre de titre (curseur « déplacer »),
  bornée à l'écran ; une fois posée, elle garde sa place, même après « Effacer ». Bouton **—** / **+** : replier
  / déplier.
- Rafraîchie deux fois par seconde (`NukeCasualties.snapshot` sur `NukeEffect.casualties`, `NukeEffect.fallout`,
  `NukeEffect.grid`, via `NukeTally`, sans recalcul) : les chiffres montent sous les yeux. Les lignes sont mises à jour sur place
  et ne sont recréées que si l'ordre des pays change (infobulles et défilement stables). Avec le scrubber du panneau
  de debug, elle suit le temps rejoué.

**Règles de l'orbite appliquées par les contrôles :**
- changer l'altitude conserve le point survolé et le sens de passage (montant / descendant) ; la période change
  avec l'altitude ;
- changer l'inclinaison se fait au point courant (comme un changement de plan orbital). Elle **ne peut pas être
  inférieure à la latitude actuelle** de la station : une orbite d'inclinaison i ne dépasse jamais ±i de latitude.
  La valeur demandée est donc remontée à |latitude| si besoin (le curseur se recale). Par exemple, au-dessus de
  Madrid (40,4° N), le minimum est 40,4°.
- l'accélération du temps agit sur l'orbite, la rotation de la Terre, le soleil et le déplacement des nuages par le vent (pas sur la lente évolution du relief de leurs sommets).

## Station spatiale (modèle Blender)

Modèle `assets/station/station_spatiale.glb` (Blender, ~60 Mo, textures intégrées ; conventions dans
`assets/station/LISEZMOI_GODOT.md`). **Ne jamais modifier le .glb** : il est réexporté depuis Blender avec les mêmes
noms de nœuds ; tout réglage passe par son `.import`, le script de post-import et la scène héritée.
- **Import** (`station_spatiale.glb.import`) : échelle 1 (mètres), racine `StationSpatiale`, collisions par
  suffixes de noms (`-col` : collision statique concave + maillage ; `-convcolonly` : collision convexe seule),
  LOD générés, animations à 24 i/s, **Rotation_Panneaux** (plus jouée : suivi du soleil, voir plus bas) et **Balayage_Antennes** en boucle (les autres jouées
  une fois). Textures extraites à côté du .glb (compression GPU S3TC/BPTC) : les images sont régénérées à chaque
  import et ne sont pas versionnées (`.gitignore`) ; leurs `.import` le sont (UID et réglages stables).
- **Post-import** (`tools/import/station_import.gd`) :
  - collisions des portes et trappes (enfants d'une `Charniere_*` animée) converties en `AnimatableBody3D`, qui
    suivent le mouvement ;
  - pistes constantes retirées des animations : l'export Blender met dans chaque action tous les objets animés
    (75 pistes) ; il ne reste que les pistes utiles (Rotation_Panneaux 4, Balayage_Antennes 3, Fermeture_Ecoutilles
    4, Ouverture_Trappes 48, Retraction_Radiateurs 12, Lancement_Missile 5). Sans cela, jouer une animation
    remettrait aussi en place tous les autres objets animés.
  - **Piège** : l'éditeur garde le script de post-import en cache ; modifié hors de l'éditeur, il n'est pas relu à
    l'import suivant (relancer l'éditeur). Toucher le `.import` ne relance pas l'import : il faut changer un
    réglage ou réexporter le .glb.
- **Métadonnées** : les propriétés personnalisées Blender (extras glTF) sont dans `get_meta("extras")`, un
  dictionnaire ; les nombres y sont des flottants (`silo: 1.0`). `ouvrable` (vrai pour les écoutilles et trappes
  animées, faux pour l'écoutille cargo et les trappes sas et nadir, verrouillées).
- **Scène héritée** `scenes/station_spatiale.tscn` : base de tout le jeu (script, réglages des lumières, etc.).
  Aperçu seul : `scenes/debug/station_preview.tscn` (soleil, fond noir, caméra extérieure).
- **Pilotage** (`scripts/station.gd`, classe `Station`, racine de la scène héritée). Rien n'est codé en dur : objets
  trouvés par leurs extras (`type` : `ecoutille`, `trappe_silo`, `trappe` ; `id`, `charniere`, `silo`, `tube`,
  `ouvrable`), angles et durées lus dans les animations Blender. Un objet seul est piloté par un Tween qui rejoue
  ses pistes ; un groupe entier dans le même état (toutes les écoutilles, les 48 trappes, les 4 radiateurs) par
  l'animation complète. Chaque animation a son propre AnimationPlayer (créé au démarrage, bibliothèque partagée) :
  les antennes tournent en boucle pendant les autres mouvements.
  - **Panneaux solaires : suivi du soleil, station furtive** (`Station._track_sun`, `track_sun_panels`). L'animation
    Blender `Rotation_Panneaux` (rotation continue, trop rapide) n'est plus jouée : à chaque image, les 4 pivots
    `Pivot_Panneau_*` (axe Z du modèle, face des cellules du côté +Y au repos) tournent pour présenter les cellules
    au soleil (projection de la direction du soleil, lumière `Sun`, sur leur plan de rotation) : ils suivent donc le
    soleil à sa vitesse apparente (un tour par orbite). **Règle de furtivité** : le dessous des panneaux porte un
    cache qui les empêche de briller vus de la Terre, et la face des cellules ne doit jamais être tournée vers le
    sol ; elle reste au moins 2° au-dessus de l'horizon local (`panel_horizon_margin_deg`, verticale = direction
    Terre → station, nœud `Earth`). Quand le soleil passe sous l'horizon de la station, les panneaux s'arrêtent à
    cette limite. Vitesse bornée à 6°/s (`panel_max_speed_deg`), pour éviter un saut quand la date ou l'heure change.
  - États au repos : écoutilles ouvertes, trappes des silos fermées, radiateurs déployés. Écoutille cargo et
    trappes sas et nadir verrouillées (`ouvrable` faux) : leurs commandes renvoient `false`.
  - Écoutilles : `open_hatch(id)`, `close_hatch(id)`, `set_hatch_open(id, open)`, `set_all_hatches_open(open)`,
    `is_hatch_open(id)`, `hatch_ids()` ; signal `hatch_changed(id, open)`.
  - Trappes des silos : `open_silo_door(silo, tube)`, `close_silo_door(…)`, `set_all_silo_doors_open(open, silo)`
    (silo 0 : les deux) ; signal `silo_door_changed(silo, tube, open)`. Une demande inverse en cours de mouvement
    repart de la position actuelle (état visé `target`) ; le lancement reprend la trappe où elle est (déjà ouverte par
    le choix du tube : pas de saut).
  - Gyrophare : `set_silo_beacon(silo, tube, on)` (groupe « Gyrophare des silos ») : lampe émissive de 7 cm et
    `OmniLight3D` rouge (énergie 4, portée 6 m, ombres, pas sur les surfaces intérieures) juste sous la coque, à
    0,75 m de la trappe vers l'extérieur de la rangée ; éclat de 0,35 du cycle de 0,9 s, montée et descente douces.
  - **Missiles** (`launch_missile(silo, tube)`, `can_launch`, `available_tubes()`) : un seul missile est modélisé
    (tube 1_12) ; pour un autre tube, il est copié et placé à l'identique par rapport au `Point_Lancement` du tube
    (repère du tube × repère du tube 1_12⁻¹ × missile animé). Le lancement rejoue `Lancement_Missile` : ouverture de
    la trappe (si elle est fermée, avec les angles de la trappe du tube), descente, allumage de la tuyère à 2,9 s
    (`Point_Tuyere` : échelle 0 → 1 ; signal `missile_ignited`), jusqu'à ~30 m sous la station (5 s ; la dernière
    clé à pleine échelle, avant celle où Blender annule l'échelle : le missile ne rétrécit jamais). Signal
    `missile_released(silo, tube, missile, velocity)` : le récepteur prend en charge le missile (nœud, propulsion
    allumée) et sa vitesse de sortie pour la suite du vol (voir « Vol du missile » ci-dessous) ; sans récepteur, la
    station le masque. Chaque tube ne tire qu'une fois. `tube_ids()` et `tube_position(silo, tube)` (repère de la
    station : +X avant, +Z droite) servent au panneau des silos ; la station est dans le groupe `Station.GROUP`.
  - **Propulsion du missile** (`scenes/effects/missile_exhaust.tscn`, script `scripts/missile_exhaust.gd`, classe
    `MissileExhaust`, instancié sous `Missile_Balistique_1_12/Point_Tuyere_1_12` dans la scène héritée : chaque copie
    du missile en hérite). Moteur à propergol solide dans le vide :
    - cœur : cône additif de 2,6 m (`shaders/missile_exhaust_core.gdshader`), éblouissant au ras de la tuyère
      (blanc-jaune, luminance HDR 24 : glow), qui s'élargit et vire à l'orange ;
    - panache : sans air pour le confiner, le gaz se détend très largement : 900 particules additives
      (`shaders/missile_exhaust_particle.gdshader`), 35 à 70 m/s, demi-angle 65°, durée de vie 0,4 s, de ~1 à
      ~5 m ; opacité qui chute vite (densité en 1/r²) : voile translucide, **pas de traînée de fumée** ;
    - lumière : `OmniLight3D` orange qui vacille (combustion irrégulière), 40 m de portée, avec ombres (quelques
      secondes seulement), qui n'éclaire pas les surfaces intérieures (calque `INTERIOR_LAYER`).
    - Allumage : échelle de `Point_Tuyere` (0 → 1 à 2,9 s, cf. `Lancement_Missile`) ; l'effet en hérite et naît à
      la taille zéro. Direction du jet : à l'opposé du déplacement du missile (le +Z de `Point_Tuyere_1_12`, annoncé
      comme direction du jet, est horizontal dans le modèle : le missile descend, sa tuyère est en haut et le jet
      monte vers la station).
    - En vol (`enter_flight`) : panache en coordonnées locales (il suit le missile et rétrécit avec lui ; le panache
      en coordonnées du monde s'éteint de lui-même), direction du jet imposée (`jet_direction`, opposée à la pointe),
      lumière atténuée (`light_scale`).
  - **Vol du missile** (`scripts/missile_flight.gd`, classe `MissileFlight`, créée par `nuke/launch_control.gd` à
    `missile_released`, enfant de la scène) :
    - trajectoire en mètres réels, dans le repère de la station : le missile poursuit la ligne droite de Blender
      (vitesse de sortie ~32 m/s) en accélérant à 30 m/s², puis s'incurve vers le point d'impact (500 m au-dessus de
      la cible, qui suit la Terre en mouvement) selon g(u) = (e^(9u) − 1 − 9u) / (e^9 − 1 − 9), u = temps écoulé /
      durée du vol (pente nulle au départ : pas d'à-coup au relais). Mesures : ~290 m à 2 s, ~6 km à 5 s, ~130 km à
      8,6 s, impact à 10 s. La pointe (−Y du missile) suit la direction du déplacement (1,2 rad/s au plus) ;
    - le vol suit l'horloge du jeu (`Orbit.time_scale` : pause, accélération) ; à l'arrivée, signal `arrived` →
      explosion (`NukeLauncher.launch_at`), le missile est libéré ;
    - **rendu à l'échelle préservant la perspective** (la même astuce que la Terre à 1/10 000 : un objet K fois plus
      proche et K fois plus petit paraît identique). À une distance réelle d de la caméra, le missile est dessiné à
      taille réelle jusqu'au palier F (90 % de la distance de la couche nuageuse dans sa direction, ~35 m sous la
      cupola), puis sur ce palier réduit de F/d (toujours devant les nuages et la Terre), enfin à l'échelle exacte de
      la Terre quand d/10 000 dépasse F (bas de l'atmosphère : les nuages le masquent comme il se doit) ;
    - halo (`shaders/missile_glow.gdshader`, disque additif face à la caméra) : rayon réel 2,5 m, jamais moins de
      4 pixels à l'écran, apparaît entre 150 m et 1,5 km (de près, la flamme et le panache suffisent) puis baisse
      lentement (45 % à 600 km) : le moteur reste un point lumineux jusqu'à l'impact ;
    - lumière du moteur sur la station : pleine jusqu'à 40 m, puis en 1/d².
  - Radiateurs : `set_radiator_deployed(id, deployed)` (`Radiateur_D15`, `D21`, `G15`, `G21`),
    `set_all_radiators_deployed`, `set_stealth(enabled)` ; signal `radiator_changed`.
  - **Éclairage intérieur** (réglages dans le groupe « Éclairage intérieur » de `Station`) : les 28 lampes
    ponctuelles du modèle (`Lum_*`, importées à 6 522 d'énergie et 4 096 m de portée) sont recalibrées au démarrage :
    blanc 4 500 K (luminaires LED de l'ISS en mode jour), énergie 1,2, portée 5,5 m, atténuation 1,3, reflets 0,4,
    **sans ombres**. Sans ombres, une lampe traverse les parois : elles n'éclairent donc que les surfaces intérieures,
    sur le calque `INTERIOR_LAYER` (bit 11, `light_cull_mask`). Est intérieur un matériau dont le nom commence par
    `Int_` ou `Ecran_` ; hublots et vitrages sont des deux côtés ; tout le reste est extérieur. Les 14 coques mixtes
    (surface `Coque_Silo` dehors, `Int_Coque` dedans, dans un même objet) sont doublées : l'original ne montre que
    ses surfaces extérieures, une copie `<nom>_Interieur` (même maillage, LOD compris, sans ombre portée) ses
    surfaces intérieures ; les surfaces cachées ont un matériau qui place leurs sommets hors du champ (aucun pixel
    calculé). L'extérieur n'est éclairé que par le soleil (et le flash des explosions).
  - **Vitrage de la cupola sans reflet** (`Station._matte_glass`) : le reflet de l'environnement (disque solaire du
    ciel) ignore l'ombre portée de la station ; il faisait briller un point lumineux dans le hublot du nadir alors
    que la cupola est à l'ombre. Le matériau `Vitrage` est remplacé au démarrage par une copie sans reflet
    spéculaire (métal 0, spéculaire 0, rugosité 1), toujours transparente.
  - **Chaleur** (règle de jeu, valeurs provisoires en attendant la jauge) : `heat` (0 à 1) monte de
    `heat_rise_per_s` (0,01/s) radiateurs tous repliés (**mode furtif** : pas de rayonnement infrarouge, la chaleur
    s'accumule) et descend de `heat_fall_per_s` (0,02/s) radiateurs tous déployés, en proportion des radiateurs
    déployés ; signal `heat_changed`.

## Organisation de la scène

- **Station** : nœud `Station` (repère de vol lu par `Orbit` : zénith +Y, direction de vol −Z ; aussi utilisé par
  `NukeFlashFX` pour éclairer la station au flash), qui contient l'instance `StationSpatiale` de
  `scenes/station_spatiale.tscn` (modèle Blender, voir « Station spatiale (modèle Blender) ») **tournée de 90°
  autour de Y** : le module Commande (+X du modèle) vole à l'avant, le dessous de la station (cupola, trappes des
  silos, −Y) face à la Terre. L'unité de la scène est le mètre (station ~42 × 80 m avec les panneaux).
  - Ancienne station, gardée dans le projet : `scenes/iss_cupola.tscn` (module Node 3 « Tranquility » + Cupola en
    CSG, inclinée de 30°).
- **Observateur** : corps `Observer` (`CharacterBody3D`, script `scripts/observer.gd`, déplacement en mode
  « flottant », sphère de collision de 0,3 m) portant la caméra `Observer/Camera` (script
  `scripts/station_camera.gd`, orientation). Départ 1 m sous le repère `Point_Vue_Cupola` du modèle, la tête au
  ras des vitres ((0, −4,2, −11,6) dans la scène ; plus haut, la paroi de la cupola masque l'horizon), vue initiale
  plongeant de 24° sous l'horizon de la station, tournée de 30° à gauche de l'avant : l'horizon terrestre (~20°
  sous l'horizontale à 400 km) est visible à travers les vitres latérales, et le centre de l'écran (réticule de
  tir) tombe sur la Terre au milieu de la vitre avant-gauche de la cupola hexagonale (droit devant, il tombait sur
  un montant, qui masquait la cible et la fin du vol du missile). `Orbit` place la Terre par rapport à la
  caméra (`observer_path`).
- **Collisions de la station** (`Station._add_interior_collisions`) : les parois générées à l'import (« -col »,
  formes concaves) bloquent des deux côtés (`backface_collision`, sinon on traverse la coque de l'intérieur) ; les
  objets `Interactif_*` sans collision (48 tubes des silos, consoles…) reçoivent au démarrage une forme convexe
  simplifiée. Les trappes et écoutilles ont déjà leur corps animé (`AnimatableBody3D`).
- **Ombres du soleil** : jusqu'à 60 m (`directional_shadow_max_distance`), pour que la station (80 m) porte ses ombres
  sur elle-même ; la Terre ne reçoit pas d'ombres portées (`shadows_disabled` dans `earth_surface.gdshader`) : à
  1/10 000, l'ombre de la station y serait 10 000 fois trop grande (invisible en réalité depuis l'orbite).
- **Échelle** : la Terre est à 1/10 000 (voir ci-dessous) ; à 400 km d'altitude, sa surface est à 40 unités sous la
  caméra (20 à 200 km). La station (trappes des silos à −4,6 m) reste au-dessus ; le missile lancé quitte
  l'animation Blender à −30 m puis est rendu à l'échelle préservant la perspective (`MissileFlight`) : il ne
  traverse jamais la Terre miniature.
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
- **Trous des explosions** : `cloud_density_masked()` (et `cloud_density()`, qui prend toutes les explosions) appelle `nuke_cloud_warp()` pour les explosions de son masque (`nuke/shaders/nuke_clouds.gdshaderinc`,
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
7. Masque des pays (voir « Pays touché ») :
   - télécharger la couche « admin 0 countries » de Natural Earth 1:10 M en GeoJSON (~13 Mo) :
     `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson` ;
   - `godot --headless --path . --script res://tools/build_country_mask.gd -- <ne_10m_admin_0_countries.geojson>`
     (~1 s). Il écrit `assets/country_mask.res` (ressource `CountryMask`, ~3 Mo).
8. Population (voir « Pertes humaines ») :
   - télécharger GHS-POP R2023A, époque 2030, 30 secondes d'arc, WGS84 (~460 Mo, à décompresser : seul le `.tif` sert) :
     `https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_POP_GLOBE_R2023A/GHS_POP_E2030_GLOBE_R2023A_4326_30ss/V1-0/` ;
   - `tools/build_population.ps1 -src <GHS_POP_E2030_GLOBE_R2023A_4326_30ss_V1_0.tif>` (PowerShell + routine C#,
     ~30 s). Il décode le GeoTIFF (BigTIFF, flottants 64 bits, LZW, décodeur intégré) et écrit
     `assets/population_2030.bin` (~74 Mo, format décrit en tête de l'outil). Il affiche la population mondiale :
     8 546 141 387 en 2030 (projection de l'ONU : ~8,5 milliards).
   - Le `.bin` n'est pas importé par l'éditeur (extension inconnue, pas de `.gdignore` nécessaire) ; le jeu le lit
     avec `FileAccess`. **À prévoir pour un export** : l'inclure dans le paquet, comme les tuiles.
9. Centrales électriques (voir « Black-out électrique » ; nécessite le masque des pays, étape 7) :
   - télécharger la Global Power Plant Database v1.3 du WRI (~4 Mo, décompresser `global_power_plant_database.csv`) :
     `https://wri-dataportal-prod.s3.amazonaws.com/manual/global_power_plant_database_v_1_3.zip` ;
   - `godot --headless --path . --script res://tools/build_power_plants.gd -- <global_power_plant_database.csv>`
     (~1 s). Il écrit `assets/power_plants.res` (ressource `PowerPlants`, ~0,7 Mo) : 34 936 centrales, 5 693 GW.
   - La carte des pays pour les shaders (`assets/textures/country_ids.png`, 8192 × 4096, ~0,4 Mo) est écrite par
     l'outil des pays (étape 7). Son import doit rester **sans perte et sans mipmaps** (`compress/mode=0`,
     `mipmaps/generate=false`, `detect_3d/compress_to=0` dans le `.import`) : les pixels sont des numéros de pays.

## Explosions nucléaires (`nuke/`)

Tout le code des explosions est dans `res://nuke/`. Objectif : une animation unique, paramétrée par la puissance
(10 kt à 50 Mt), vue depuis l'espace. **État actuel : socle de l'effet** (tir, placement, lois d'échelle,
horloge), **flash initial**, **onde de choc** (condensation, poussière), **incendies**, **trous dans la couche
nuageuse**, **champignon** (boule de feu comprise ; dérive selon le profil vertical du vent, dissipation et panache)
et **explosions sur la mer** (pas d'incendie au large, nuage de vapeur d'eau qui retombe vite) ; le **pays touché**
et les **pertes humaines** (par pays, selon la densité de population) sont calculés au tir ; **black-out électrique**
de nuit (zone détruite, panne régionale en cascade, panne nationale si une grosse centrale est détruite).

**Persistance du monde (règle de jeu)** : une explosion n'est jamais retirée ; ses effets au sol durent toute la
partie, sans limite de nombre. Les incendies s'étendent pendant plusieurs jours, sous un **panache de fumée** emporté
par le vent sur des centaines de km, puis s'éteignent en laissant une **trace au sol définitive** (charbon, puis terre
brûlée brune et gravats : plus de verdure, visible de jour, d'autant plus étendue que la bombe est puissante) ; le
**black-out ne se répare jamais** (zone détruite, panne régionale et panne nationale). Explosions à **500 m
d'altitude** : pas de cratère. Le champignon se dissipe en quelques heures de jeu (dérive et dilution réelles). Après la première
demi-heure physique, jouée en accéléré, une explosion vit au rythme de l'horloge du jeu (voir « Horloge ») : ce que
l'on retrouve après une ou plusieurs orbites correspond au temps réellement écoulé dans la partie.

### Organisation du code

Une responsabilité par classe (principe « S » de SOLID). Trois familles :

| Rôle | Classes (fichiers dans `nuke/` sauf mention) |
|---|---|
| **Tir** | `NukeLauncher` (visée, création de l'explosion, liste des explosions ; crée les nœuds ci-dessous), `NukeParams` (paramètres d'un tir), `NukeEffect` (une explosion : placement, temps, résultats du bilan), `NukeClock` (horloge) |
| **Rendu d'une explosion** (enfants de `NukeEffect`) | `NukeFlash`, `NukeShock`, `NukeMushroom` (forme, volume, couleurs) avec `NukeMushroomDrift` (dérive au vent) et `NukeMushroomParticles` (particules) |
| **Rendu global** (nœuds créés par le lanceur, alimentent les shaders du globe) | `NukeFlashFX`, `NukeCloudFX` (effets brefs, tableaux d'uniforms), `NukeGroundFX` (effets durables au sol : incendies, fumée, trace au sol, black-out ; textures de données sans plafond) ; `NukeFXMaterials` (recherche des matériaux qui déclarent un uniform) |
| **Modèles** (calcul pur, sans nœud, utilisables depuis un thread) | `NukeScaling` (lois d'échelle, surpression de Brode), `NukeCasualties` (pertes du souffle et de la chaleur, chronologie), `NukeFallout` (doses et pertes des retombées) avec `NukeWSEG10` (champ de retombées) et `NukeMath`, `NukeGridImpact` (centrales détruites, panne nationale), `NukeAtmosphere`, `NukeWind` |
| **Bilan** | `NukeImpact` (nœud `Impact` : calcule le bilan d'un tir dans un thread et l'écrit en console), `NukeTally` (cumul par pays, à l'instant présent), `NukeReportText` (textes et nombres), `NukeReportPanel` (fenêtre, affichage seulement) avec `DraggableWindow` (`scripts/ui/`, fenêtre déplaçable réutilisable) |
| **Données géographiques** (`scripts/`) | `OceanMask`, `CountryMask` (dont `index_near` : pays le plus proche d'un point côtier), `PopulationGrid` (dont `cell_country`), `PowerPlants` |

Un tir ne fait que créer la scène de l'explosion (~1 ms) : tout le bilan (pertes, réseau électrique, retombées) est
calculé par `NukeImpact` dans un `WorkerThreadPool`, puis remis à l'explosion dans le fil principal ; la console est
écrite depuis ce thread.

### Performances

Banc de mesure : `tools/bench/nuke_bench.tscn` (`godot --path . res://tools/bench/nuke_bench.tscn -- <résultats.txt>`).
Il charge la scène principale, coupe la synchro verticale, fige l'orbite, tire 0 à 16 explosions de 1 Mt dans le
champ de vision (graine fixe), et mesure le temps CPU par image (moyen et pire), le temps GPU (RenderingServer), la
durée des tirs et la pire image qui suit, puis 4 × 50 Mt, puis la part GPU de chaque effet (en le coupant). **Ne rien
faire tourner d'autre pendant la mesure** (une partie lancée depuis l'éditeur partage le GPU et fausse tout).

Mesures (RTX 5080, 1920 × 1080, 2026-10-10), avant et après la refactorisation et les optimisations :

| | Avant | Après |
|---|---|---|
| 16 tirs enchaînés : durée des appels | 996 ms | 20 ms |
| Pire image après ces 16 tirs | 257 ms | 5 ms |
| 0 explosion : temps par image | 4,2 ms (235 im/s) | 4,3 ms (235 im/s) |
| 16 × 1 Mt à 60 s | 8,6 ms (116 im/s) | 6,2 ms (162 im/s) |
| 16 × 1 Mt à 30 min | 7,3 ms (137 im/s) | 7,2 ms (139 im/s) |
| GPU des trous dans les nuages (16 × 1 Mt) | 2,65 ms | 0,17 ms |
| GPU des incendies (16 × 1 Mt) | 0,21 ms | 0,03 ms |

Le jeu est limité par le GPU (temps CPU ≈ temps GPU). Ce qui a été corrigé :
- **à-coups au tir** (la vraie cause des ralentissements ressentis) : chaque `print()` coûte 6 à 9 ms (sortie de
  l'éditeur) et un tir en écrivait 6 à 8 ; le calcul des pertes prenait 4 à 40 ms et les cartes de vent étaient
  chargées au premier tir. Désormais tout le bilan et la console sont dans un thread (`NukeImpact`) et les cartes
  de vent sont préchargées au démarrage (`NukeWind.preload_maps`). Seul le tout premier tir de la partie coûte
  ~17 ms (première création de la scène de l'explosion) ;
- **trous dans les nuages** : chaque échantillon de nuage (marche de rayon et marche vers le soleil) testait toutes
  les explosions. Le shader des nuages calcule maintenant une fois par rayon la liste des explosions dont la zone
  d'influence croise son trajet (`nuke_cloud_events_near_segment`, masque de bits) et n'évalue qu'elles
  (`cloud_density_masked`) ;
- **incendies** : le voile des nuages sur les feux (une marche de nuages par pixel du sol) était calculé sur tout le
  globe dès qu'un feu existait ; il ne l'est plus que là où il y a du feu ;
- **dérive des champignons** (CPU) : pendant les 10 min de montée, 512 interpolations du profil de vent par
  champignon et par image ; le vent est maintenant lu dans une table précalculée (`NukeMushroomDrift`).

Coût restant (16 × 1 Mt à 60 s, GPU) : champignons volumétriques 1,5 ms, anneaux d'onde de choc 0,6 ms. Essayé sans
gain mesurable, donc abandonné : un pas adaptatif pour la marche de rayon du champignon (les rayons traversent
surtout des volumes hauts, où 64 pas restent nécessaires).

- **Paramètres** (`nuke/nuke_params.gd`, Resource `NukeParams`) : `yield_kt` (10 à 50 000), `latitude_deg`,
  `longitude_deg`, `wind_direction_deg` (d'où vient le vent, convention météo) et `wind_speed_m_s`,
  `start_time_s` (instant sur l'horloge `NukeClock`), `burst_height_km` (**règle de jeu : 500 m par défaut**, `NukeScaling.DEFAULT_BURST_HEIGHT_KM` ; 0 = au sol). À
  500 m, la boule de feu touche encore le sol à partir de ~1 Mt (rayon 1,05 km) : retombées locales et poussière
  aspirée ; à 10 kt, c'est une explosion aérienne (pas de retombées locales), et à 100 kt seulement en partie
  (`NukeScaling.low_burst`, 1 au sol, 0 au-dessus de 2 rayons de boule de feu). Jamais de
  cratère,
  `over_ocean` (point zéro sur une mer ou un océan, renseigné au tir, voir « Explosions sur la mer »),
  `country_code` (pays du point zéro, renseigné au tir, voir « Pays touché »).
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
- **Incendies et trace au sol** (règle de jeu ; nœud `GroundFX`, classe `NukeGroundFX`, créé par `NukeLauncher` ;
  `nuke/shaders/nuke_fire.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` ; lois dans `NukeScaling`,
  constantes `FIRE_*` et `SCAR_*`). Ils sont allumés par le flash dans le rayon où l'exposition thermique dépasse ~10 cal/cm²
  (inflammation des matériaux courants, Glasstone & Dolan ch. VII), **s'étendent pendant plusieurs jours** et
  laissent une **trace au sol jusqu'à la fin de la partie**.
  - Rayon initial R0 : 12 km · (W / 1 Mt)^0,41, soit ~1,8 km à 10 kt, 12 km à 1 Mt et ~60 km à 50 Mt
    (`NukeScaling.fire_base_radius_km`).
  - Zone du flash, calée sur Hiroshima (tempête de feu formée ~20 min après l'explosion, au plus fort vers 2–3 h) :
    25 % de l'intensité finale dès le flash (foyers allumés par le rayonnement thermique), foyers qui se rejoignent
    entre 2 min et 1 h 30 ; intensité maximale ~0,8 vers 1 h 30.
  - Propagation : le front gagne les terres alentour, rayon R0 · (1 + 1 · (1 − exp(−t / 1 jour)))
    (`FIRE_SPREAD`, `FIRE_SPREAD_S`, `NukeScaling.fire_radius_km`) : 63 % du chemin en 1 jour, 95 % en 3 jours,
    jusqu'à 2 R0 (24 km à 1 Mt) ; au départ ~0,5 km/h pour 1 Mt, l'allure d'un feu de forêt. Un lieu atteint par le
    front s'embrase en 1 h, moins fort que la tempête de feu (30 %) : **un anneau de feu s'éloigne du centre**.
  - Chaque lieu brûle avec une constante de temps d'extinction de 6 h (`FIRE_BURN_S`) : le centre est éteint en
    ~1 jour, les derniers feux du front en 4 à 5 jours.
  - **Trace au sol** (règle de jeu : pas de cratère, explosion à 500 m ; la partie dure quelques semaines, aucune
    repousse visible : la trace est **définitive**). Deux causes, toutes deux fonction de la puissance :
    - **le feu** : chaque lieu brûlé noircit en 2 h (`FIRE_CHAR_S`, charbon `nuke_burn_albedo`), puis **brunit**
      entre 12 h et 4 jours après son passage (`SCAR_BROWN_START_S`, `SCAR_BROWN_END_S` : cendres envolées,
      végétation morte) : terre brûlée brun sombre (`nuke_scar_albedo`, réflectance de ~5 à 8 % comme les cicatrices
      de brûlis sur les images satellites, plus sombre qu'un sol aride), sans verdure. Plus marquée dans la zone du
      flash, motif irrégulier ;
    - **le souffle** : dans le rayon de 5 psi (`SCAR_RUBBLE_PSI` : bâtiments rasés, forêts couchées), gravats et
      poussière gris-brun (`nuke_rubble_albedo`) dès l'explosion, même sans incendie.

    Mélange jusqu'à 95 % (`nuke_scar_strength`) ; le relief du sol d'origine reste un peu visible
    (`nuke_scar_relief`) ; dans les villes, la trace tire vers le gris des gravats. Seulement sur les terres. Étendue :
    ~2 km de rayon à 10 kt (à peine une tache depuis l'orbite), ~24 km à 1 Mt, ~120 km à 50 Mt (une région entière
    meurtrie ; dix 50 Mt couvrent un pays). Vue de biais à plusieurs centaines de km, la brume atmosphérique atténue
    nettement le contraste (comme sur les photos obliques prises depuis l'ISS) ; vue plongeante, la trace est franche.
    Choix du rendu procédural plutôt qu'une image (PNG) plaquée : forme irrégulière propre à chaque tir, taille
    exacte quelle que soit la puissance (de 2 à 120 km), netteté à toutes les distances, sans texture à projeter
    sur la sphère.
  - Toutes les durées sont en temps physique, au rythme du jeu après la première demi-heure (voir « Horloge ») :
    les incendies durent donc plusieurs jours de la partie.
  - Rendu des flammes, en émission sur le sol :
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
  - **Aucun plafond sur le nombre d'explosions** (`NukeGroundFX`, `nuke/shaders/nuke_ground.gdshaderinc`) : chaque
    explosion est une colonne d'une texture de données (centre, temps physique, rayons : zone détruite, panne
    régionale, incendies, portée ; vent de la fumée ; rayon des gravats). Une maille de 1° (360 × 180) indexe les
    explosions dont la portée la touche : un pixel du sol ne teste que les explosions proches. Seuls les temps sont
    renvoyés à chaque image ; la maille est reconstruite à chaque tir. Les mêmes textures servent au black-out et à
    la fumée (qui a sa propre maille, voir ci-dessous).
- **Fumée des incendies** (règle de jeu ; `nuke/shaders/nuke_smoke.gdshaderinc`, inclus dans
  `shaders/earth_surface.gdshader` ; données et maille par `NukeGroundFX` ; lois dans `NukeScaling`, constantes
  `SMOKE_*`). Tant que les incendies brûlent (plusieurs jours), leur fumée est emportée par le vent réel GFS à 4 km
  (`SMOKE_HEIGHT_KM`) en un panache de centaines de km.
  - **Modèle** : panache gaussien intégré sur la verticale (modèle classique de dispersion). La fumée émise à
    l'instant t − a est, à l'instant t, à u · a sous le vent (le long du grand cercle), étalée sur
    σ(a)² = σ0² + 2 K a (σ0 = 0,7 R0, taille du foyer ; K = 5·10⁴ m²/s, diffusion à méso-échelle), et se dépose en
    4 jours (`SMOKE_LIFETIME_S`). Épaisseur optique verticale
    τ = MEE · Q(t − a) · e^(−a/L) / (u · √(2π) · σ) · exp(−y² / 2σ²) ; le panache est tronqué progressivement vers
    2 jours d'âge (`SMOKE_MAX_AGE_S`).
  - **Bords** : le modèle gaussien classique néglige la diffusion dans le sens du vent ; comme l'émission démarre au
    flash, le front du panache (fumée la plus ancienne, à u · t) y serait une coupure droite perpendiculaire au vent.
    Le front est donc étalé sur ±2 σ (même diffusion K que sur les côtés). Les bords sont en outre déformés par un
    bruit à l'échelle de l'étalement (±0,7 σ en distance et en écart latéral : langues et volutes), propre à chaque
    explosion. Au vent du foyer, la fumée ne déborde que de la moitié de la taille du foyer.
  - **Accumulation** : la formule du panache décrit le régime établi (la fumée part avec le vent aussi vite qu'elle
    est émise), atteint quand le vent a balayé le foyer, u · t ≈ √(2π) σ0 (2 à 3 h pour un foyer de 40 km à 10 m/s).
    Avant, la fumée s'accumule au-dessus du foyer (colonne Q · t / 2π σ0²) : le panache s'épaissit progressivement au
    lieu de couvrir d'emblée toute la zone.
  - **Débit** Q = Y · R0² · f(t) / 6 h (`FIRE_BURN_S`), où f est la surface en feu (`NukeScaling.smoke_burning_area`,
    mêmes lois que les incendies, table de 256 valeurs en échelle log, `nuke_smoke_rate`) et Y la fumée par m² en feu,
    **selon ce qui brûle** (`NukeScaling.smoke_yield_kg_m2`, calculée au tir dans le thread de `NukeImpact` : moyenne
    de 24 × 24 points des terres de la zone des incendies, population GHS-POP) :
    - végétation : 2 kg/m² de combustible consumé (`SMOKE_WILDLAND_FUEL_KG_M2` ; herbe 0,3 à 0,5, broussailles 1 à 3,
      forêt 2 à 5, van der Werf et al. 2017), facteur d'émission 1,2 % (`SMOKE_WILDLAND_EF`, Andreae 2019) ;
    - bâti : 0,011 kg/m² par hab./km² (`SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2` : 1,1·10⁷ g par habitant, Toon et al. 2007
      § 6.1 ; centres-villes mesurés 120 à 470 kg/m²), facteur d'émission 2 % (`SMOKE_URBAN_EF`, Small 1989).

    Mesures : 50 Mt sur la Sardaigne (~70 hab./km²), Y = 0,042 kg/m² ; 1 Mt sur Paris, Y = 1,17 kg/m² (28 fois plus).
    Repère : 100 explosions de 15 kt sur des mégapoles donnent 1 à 5 Tg de suie (Toon et al. 2007). Efficacité
    d'extinction 5 m²/g (`SMOKE_MEE_M2_KG` ; Toon et al. citent 4,4 à 7 m²/g). Une 50 Mt sur une île rurale : voile
    léger à 30 min, épaississement sur 2 à 3 h, panache épais sous le vent ensuite (l'île entière brûle : le rayon
    d'inflammation, ~60 km, couvre presque toute la Sardaigne) ; sur une grande ville, panache bien plus opaque.
    Version précédente (corrigée) : tout sol en feu était traité comme une ville (~0,65 kg/m²), soit ~15 fois trop
    de fumée en campagne, et le panache atteignait d'emblée son régime établi.
  - **Rendu** : couche plate sous les nuages (fumée de 1 à 6 km ; vue de 400 km, sa parallaxe est négligeable). Elle
    voile le sol (albédo gris-brun `nuke_smoke_albedo` éclairé par le soleil, noir la nuit), les reflets de la mer et
    les lumières des villes ; la lueur des incendies la traverse en partie (`nuke_smoke_fire_glow`). Volutes : bruit à
    deux échelles (70 et 18 km) qui module τ de ±70 % et dérive lentement.
  - **Maille de la fumée** (`nuke_smoke_cells`, `nuke_smoke_index`) : chaque panache est couvert par des disques le
    long de son axe, de demi-largeur celle où τ tombe sous 0,005 (au débit maximal) ; reconstruite quand un panache
    s'allonge d'environ 10 % ou disparaît.
  - Limites : vent constant (celui du point zéro le jour du tir) ; fumée sous les nuages (un pyrocumulonimbus qui
    monte au-dessus des nuages n'est pas rendu au-dessus) ; pas d'ombre du panache.
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
    - Profondeur écrite par le shader : là où le pixel est presque opaque (alpha total > 0,8, `depth_alpha`), celle
      du premier point dense (alpha cumulé > 0,35, `depth_first`), sinon un point juste au-dessus du sol. Les nuages
      et l'atmosphère, rendus après, ne le recouvrent que là où ils sont devant lui : c'est cette profondeur qui rend
      le champignon visible au-dessus d'un banc nuageux. Un panache ténu (alpha < 0,8) est donc caché par les nuages
      qu'il survole, mais reste visible au-dessus d'un sol dégagé. Avec l'ancien seuil (0,35 sur l'alpha cumulé), le
      bord d'un panache qui s'étiole au-dessus des nuages scintillait : chaque pixel y basculait entre « panache sur
      le sol, nuages masqués » (gris) et « nuages » (blanc), selon le décalage d'échantillonnage. À 0,8, les deux
      aspects sont proches (mesure : 302 pixels changeant brutalement en 2 s de temps physique à 1 h 30 d'un 10 Mt,
      contre 2).
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
  - **Dérive au vent** (`nuke/nuke_mushroom_drift.gd`, classe `NukeMushroomDrift` ; `nuke/shaders/nuke_drift.gdshaderinc`) : profil vertical du vent réel GFS
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
      ~1 h 30 et ~5 h 30 d'horloge, soit une à plusieurs orbites). Effet visible : à 1 Mt, chapeau net à 30 min, panache
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
- **Black-out électrique** (règle de jeu ; `nuke/nuke_grid_impact.gd`, classe `NukeGridImpact` ; `nuke/nuke_ground_fx.gd`, classe `NukeGroundFX`, nœud `GroundFX` créé par
  `NukeLauncher` ; `nuke/shaders/nuke_blackout.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` ; lois et
  durées dans `NukeScaling`, constantes `BLACKOUT_*`). **Le black-out dure jusqu'à la fin de la partie** : réseau
  détruit, aucune remise en état pendant une guerre nucléaire. Seules les lumières des villes s'éteignent : **de jour, rien
  ne se voit** ; au crépuscule, les villes s'allument autour d'une zone qui reste noire (la panne multiplie
  l'allumage progressif des lumières, du soleil à +2° jusqu'à −7° sous l'horizon) ; à l'aube tout s'éteint
  ensemble. Une ville éteinte retombe à la lueur de la campagne non éclairée (quasi noire, gris bleuté), pas à une
  version atténuée d'elle-même. Les incendies restent visibles dans le noir. Trois couches :
  1. **Zone détruite** : rayon de 2 psi (`BLACKOUT_DESTROYED_PSI` : réseau, postes, bâtiments ; 1,8 km à 10 kt,
     8,5 km à 1 Mt, 31 km à 50 Mt), éteinte dès l'explosion et pour de bon, bord irrégulier.
  2. **Panne régionale en cascade** : disque de 120 km · (W / 1 Mt)^(1/3) (`BLACKOUT_REGION_1MT_KM` : ~26 km à
     10 kt, ~440 km à 50 Mt ; au moins 2 fois la zone détruite). Le front de la panne avance du centre vers le bord
     (R · (1 − exp(−t / 15 s))), par plaques d'une vingtaine de km (quartiers, communes : bruit fixe), et reste
     éteint.
  3. **Panne nationale** : au tir, `NukeGridImpact.assess()` (dans le thread de `NukeImpact`) cherche les centrales détruites (rayon de 5 psi,
     `BLACKOUT_PLANT_PSI`) dans la Global Power Plant Database (`scripts/power_plants.gd`, classe `PowerPlants`,
     `assets/power_plants.res`). Si elles représentent au moins 10 % de la capacité du pays
     (`BLACKOUT_NATIONAL_SHARE`), tout le pays s'éteint, à ses frontières (carte `assets/textures/country_ids.png`
     lue par le shader), par plaques en 5 à 30 s (effondrement de la fréquence), et reste éteint. Repère : la panne
     de la péninsule ibérique du 28 avril 2025 (Espagne et Portugal éteints en quelques secondes). Le pays retenu est
     celui du point zéro (en mer : celui qui perd le plus de capacité). Les pays dans le noir sont transmis au shader
     par une texture indexée par pays (`nuke_ground_countries`), sans limite de nombre.
  - Console :
    ```
      réseau électrique : 2 centrale(s) détruite(s), 2923 MW : DOEL 4 (Nuclear, 2910 MW), Loghidden City (Solar, 13 MW)
        Belgique perd 23,0 % de sa capacité (12693 MW) : black-out national
    ```
    Exemples de centrales qui déclenchent seules une panne nationale : Doel (Belgique, 23 %), Paks (Hongrie, 30 %),
    Kozloduy (Bulgarie, 22 %), Guri (Venezuela, 28 %). La France (111 GW recensés), l'Espagne (78 GW) ou le Japon
    (215 GW) ne s'éteignent pas pour une seule centrale.
  - Les plaques basculent sur une fenêtre de temps (5 % de la date, au moins 2 s) : pas de clignotement. Le motif
    des plaques est fixe (centré sur l'explosion, ou en coordonnées planétaires à échelle constante pour un pays).
  - Mesure : 1 Mt sur Anvers, de nuit : Belgique noire à 10 min, et pour le reste de la partie.
  - Limites : la base recense ~70 % de la capacité mondiale (surtout les grosses centrales, qui comptent ici) ; les
    réseaux interconnectés (une panne qui déborde sur les pays voisins) et l'impulsion électromagnétique d'une
    explosion en haute altitude ne sont pas simulés.
- **Pertes humaines** (`nuke/nuke_casualties.gd`, classe `NukeCasualties` ; `nuke/nuke_fallout.gd`, classe
  `NukeFallout` ; règle de jeu). Au tir, le nœud `Impact` (`NukeImpact`) calcule hors du fil principal le bilan final du souffle et de la chaleur
  (`NukeEffect.casualties`), puis les retombées (`NukeEffect.fallout`). Les pertes
  s'affichent **en temps réel** dans la fenêtre « Bilan des explosions » (voir « Contrôles ») et le bilan en
  console, par pays :
  ```
  NukeLauncher : 1 Mt sur 47.56°, 7.59° (Suisse) (…)
    souffle et chaleur, bilan final (OTA 1979, population 2030) : 222 000 morts, 161 000 blessés, 604 000 personnes à plus de 1 psi
      Suisse : 200 000 morts, 94 400 blessés, 2,33 % de la population
      Allemagne : 14 100 morts, 47 600 blessés, 0,02 % de la population
      France : 8 110 morts, 19 200 blessés, 0,01 % de la population
  ```
  - **Modèle** : celui de l'Office of Technology Assessment (*The Effects of Nuclear War*, 1979, ch. II), tiré des
    pertes d'Hiroshima. Souffle, chaleur et rayonnement initial confondus, la part de tués et de blessés ne dépend
    que de la surpression de crête au sol :

    | Surpression | Tués | Blessés |
    |---|---|---|
    | > 12 psi | 98 % | 2 % |
    | 5 à 12 psi | 50 % | 40 % |
    | 2 à 5 psi | 5 % | 45 % |
    | 1 à 2 psi | 0 | 25 % |

  - **Surpression** : équation de Brode (1986, `NukeScaling.overpressure_psi`, précision ~10 %), selon la puissance,
    la distance et la hauteur d'explosion ; `NukeScaling.overpressure_range_km` en donne les rayons (recherche
    dichotomique). Vérifications : 1 Mt au sol, 5 psi à 4,65 km et 1 psi à 14,3 km ; Hiroshima (15 kt à 580 m),
    5 psi à 1,6 km.

    | Au sol | 12 psi | 5 psi | 2 psi | 1 psi |
    |---|---|---|---|---|
    | 10 kt | 0,6 km | 1,0 km | 1,8 km | 3,1 km |
    | 1 Mt | 2,85 km | 4,65 km | 8,5 km | 14,3 km |
    | 50 Mt | 10,5 km | 17,1 km | 31,5 km | 52,5 km |

  - **Population** : grille GHS-POP 2030 (`scripts/population_grid.gd`, classe `PopulationGrid`, données
    `assets/population_2030.bin`), ~0,9 km par cellule. Fichier découpé en tuiles de 5° : seules celles qui touchent
    la zone sont lues (cache de 24 tuiles). Cellules quantifiées sur 16 bits (habitants = (q / 64)²). Une cellule
    coupée par la limite d'une tranche est découpée en 4 × 4 sous-cellules.
  - **Pays de chaque cellule** : `CountryMask` (mêmes lignes de latitude). Une cellule littorale habitée que le
    trait de côte au 1:10 M place en mer est rattachée au pays le plus proche (jusqu'à 4 cellules).
  - Coût : 5 à 35 ms par tir (10 kt à 50 Mt).
  - Exemples (au sol sauf mention) : Hiroshima 2030 (15 kt à 580 m), ~42 000 morts ; Paris (1 Mt), ~1,3 million
    de morts ; New York (50 Mt), ~6 millions ; Sahara ou pleine mer, aucun.
  - **Chronologie** (`NukeCasualties.snapshot`, constantes `PHASE_*`), du bilan OTA de chaque pays :
    1. **flash** (dès l'explosion) : 30 % des morts (brûlures mortelles, rayonnement initial) ;
    2. **onde de choc** : 50 % des morts et tous les blessés, au passage du front à leur distance (24 anneaux par
       pays ; `NukeScaling.shock_arrival_s`, celui du front affiché, puis la vitesse du son au-delà) : quelques
       secondes à une minute ;
    3. **décès différés** : les 20 % restants (grands brûlés, blessés graves, victimes ensevelies), comptés d'abord
       parmi les blessés, meurent en exp(−t / 6 h).
    Exemple (Paris, 1 Mt au sol) : 403 000 morts à 0,1 s, 828 000 à 5 s, 1,07 million à 40 s, 1,18 million à 3 h,
    1,41 million à 10 jours avec les retombées ; projection à 60 jours : 1,49 million.
  - **Retombées radioactives** (`NukeFallout`, seulement pour une explosion basse, `NukeScaling.low_burst`) :
    - champ de retombées **WSEG-10** (Weapons Systems Evaluation Group, 1959 ; documentation de Hanifen, 1980) :
      nuage stabilisé déporté par le vent, dépôt le long d'une « ligne chaude » sous le vent, répartition
      gaussienne en travers, correction au vent arrière. Il donne en chaque point le débit de dose à H+1 (R/h) et
      l'heure d'arrivée des retombées ;
    - vent : le profil réel GFS au point d'impact, moyenné entre le sol et le centre du nuage (13 km à 1 Mt) ;
      cisaillement entre les deux ;
    - fraction de fission : 1 sous 50 kt (armes à fission), 0,5 au-delà ;
    - transcription d'après le paquet *glasstone* (MIT), avec trois corrections : hauteur du nuage en mégatonnes et
      vent en miles par heure (comme chez Hanifen), et l'exposant de la loi de dépôt calculé sans la fraction de
      fission (déjà comptée dans le débit), sinon le débit près du point zéro était 3 à 5 fois sous les contours
      idéalisés de Glasstone & Dolan. Vérification (1 Mt de fission, vent de 15 mph) : ~1 500 R/h à 20 miles sous le
      vent, ~1 000 R/h vers 45 miles, ~440 R/h à 100 miles, du même ordre que ces contours ;
    - dose : débit en t^−1,2 (loi de Way-Wigner), intégré depuis l'arrivée des retombées, divisé par un facteur de
      protection moyen des bâtiments de 3 (pas d'évacuation) ;
    - effets (irradiation aiguë, sans soins, Glasstone & Dolan ch. XII) : mort selon une loi log-normale de dose
      médiane 4,5 Gy (écart-type 0,3 en logarithme), mal des rayons au-dessus de ~1,5 Gy (compté avec les blessés) ;
      les morts surviennent avec un délai (constante de 6 jours), les malades qui en mourront passent des blessés
      aux morts ;
    - les personnes déjà tuées par le souffle ne sont pas comptées deux fois ; population par blocs de 3 × 3
      cellules (~2,8 km : le champ est lisse) ; chronologie précalculée en 48 instants (0,25 h à 60 jours) puis
      interpolée ;
    - coût : ~50 ms à 1 Mt, ~4 s à 50 Mt (thread) ; console : vent, longueur de la zone dangereuse, morts et malades
      à 60 jours par pays ;
    - exemples (morts à 60 jours) : Kansas City 1 Mt, ~40 000 (en plus de 64 000 pour le souffle) ; Paris 1 Mt
      (vent de 32 m/s vers le nord-est), ~143 000 ; Paris 50 Mt, ~15 millions jusqu'en Allemagne, en Belgique et aux
      Pays-Bas.
    - Ces jours sont des jours de la partie : après la première demi-heure, le temps physique suit l'horloge du jeu
      (1 jour physique ≈ 1 jour d'horloge, moins de temps réel avec les vitesses x2 à x16 du panneau).
  - **Non comptés** : tempête de feu (le modèle de surpression la sous-estime pour les fortes puissances, critique
    de Postol), effets à long terme (cancers), contamination de l'eau et des aliments, évacuation et soins. Le
    modèle de l'OTA vaut pour une ville de faible hauteur ; il est discutable pour les tours modernes.
- **Pays touché** (`scripts/country_mask.gd`, classe `CountryMask`, données `assets/country_mask.res`) : au tir,
  `NukeLauncher` renseigne `NukeParams.country_code` (code ADM0_A3) avec `CountryMask.country_at(latitude,
  longitude)` ; `NukeParams.get_country()` rend la fiche du pays, vide en mer. La console affiche le pays, et l'État
  souverain pour un territoire dépendant (« Gibraltar, Royaume-Uni »).
  - Données : frontières Natural Earth 1:10 M (couche « admin 0 countries », 258 pays et territoires). Ce sont les
    frontières **de fait** : la Crimée compte pour la Russie, le Sahara occidental pour le Maroc, Taïwan comme
    pays. Natural Earth publie aussi des variantes selon le point de vue d'un pays, dont la France
    (`ne_10m_admin_0_countries_fra.geojson`, même outil).
  - Fiche de chaque pays : `code`, `iso_a2`, `name_fr`, `name_en`, `sovereign_code`, `sovereign` et `sovereign_fr`
    (État dont il dépend), `type`, `continent`, population estimée (`pop_est`, `pop_year`, 2019 en général), PIB en
    millions de dollars (`gdp_md`, `gdp_year`), `income_group`.
  - Stockage comme `OceanMask` : 120 lignes de latitude par degré (~0,9 km) ; pour chaque ligne, les longitudes
    exactes où elle franchit une frontière ou une côte, et le pays situé à l'est de chacune. Recherche dichotomique.
    Précision : celle des frontières (quelques centaines de mètres) en longitude, ~0,5 km en latitude. Vérifié :
    Strasbourg / Kehl, Genève / Annemasse, Lille / Tournai, La Línea / Gibraltar, Monaco, Saint-Marin, Andorre,
    Hong Kong (Chine), Groenland (Danemark), Fidji et Tchoukotka (antiméridien), mer et Caspienne (aucun pays).
    Limite : un territoire plus petit qu'une ligne peut être manqué (Vatican, enclaves de Baarle-Hertog).
  - `CountryMask.countries_within(latitude, longitude, rayon_km)` : pays présents dans un disque, du plus proche au
    plus éloigné (Bâle, 30 km : Allemagne, France, Suisse ; détroit de Béring, 60 km : Russie, États-Unis).
  - Chargement : ~0,5 s, lancé en tâche de fond par `NukeLauncher` au démarrage (`OceanMask` aussi) : pas d'à-coup au
    premier tir. Sans le fichier, aucun pays n'est détecté.
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
      rendue irrégulière par le bruit 3D des nuages (`nuke_cloud_edge_noise`, période 0,3 × rayon **final**). Le
      sommet des nuages y descend en pente douce. Le motif est lu en coordonnées centrées sur l'explosion, à
      l'échelle du rayon final : il est fixe. (Il était lu à l'échelle du rayon courant et en coordonnées
      planétaires, à ~6 371 km de l'origine : pendant l'expansion, la moindre variation du rayon le décalait de
      plusieurs périodes, et le bord grouillait à chaque image. Mesure à 50 Mt, 2 min, deux images à 0,5 s
      d'écart : 9 532 pixels changeant brutalement avant, 0 après.)
  - **Nuages poussés** : la carte est lue plus près du centre, ce qui déplace les nuages radialement vers
    l'extérieur. Le décalage vaut au plus 12 % du rayon du trou (`nuke_cloud_push`) et décroît en exp(−x / w) au-delà
    du bord (x : distance au bord ; w = 8 % du rayon, `nuke_cloud_rim_width`). La matière balayée est tassée contre
    le bord : la carte y est lue jusqu'à 2,5 fois plus serrée. Le niveau de mipmap de la carte est relevé d'autant
    (log2 du tassement, sortie `squeeze` de `nuke_cloud_warp`), sinon ses détails deviennent plus fins qu'un pixel
    et scintillent.
  - **Bourrelet** : densité × (1 + 0,6), sommet relevé de 25 % sur le bord (`nuke_cloud_rim_gain`,
    `nuke_cloud_rim_lift`), même décroissance.
  - **Retour des nuages** sur `recovery_s` (export de `CloudFX`, **1 200 s de temps physique** de l'explosion,
    ≈ 2 min d'horloge après l'accélération) :
    - chaque point se referme à partir du passage du front, t = −τ · ln(1 − r / R_max), plafonné à celui de
      0,98 R_max (~3,9 τ) : le front n'atteint R_max qu'asymptotiquement, et sans ce plafond un anneau très fin
      restait ouvert au bord jusqu'à la fin (plus fin qu'un pixel, il scintillait, puis disparaissait d'un coup) ;
    - tout est refermé au plus tard à `recovery_s` + 4 τ, quand `CloudFX` retire l'événement (pas de saut) ;
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
    jusqu'à `slow_phase_acceleration` (×10), pour la montée du champignon et les trous dans les nuages ;
  - quand `slow_phase_end_s` (30 min) de temps physique sont écoulés, la vitesse **redescend** de la même façon
    (smoothstep sur `ramp_s`) jusqu'à 1 : l'explosion vit ensuite **au rythme du jeu**, avec une avance fixe de
    ~29 min (`late_offset_s()`, 1 764 s). Sans ce retour, une orbite (92 min) valait ~15 h pour les explosions et
    tout avait disparu au passage suivant ; désormais incendies (jours), dissipation du champignon (heures), décès
    différés et retombées suivent la date de la partie ;
  - les rampes évitent les sauts de vitesse : un effet encore en cours à 20 s ne se met pas à filer d'un coup
    (l'anneau de condensation d'un 50 Mt s'évapore vers 35 s d'horloge, à ×3,8) ;
  - repères : 60 s d'horloge = 240 s physiques, 10 min physiques ≈ 1 min 36 s d'horloge, 30 min ≈ 3 min 36 s,
    fin de la redescente à ~4 min 16 s d'horloge (~34 min physiques) ; au-delà, physique = horloge + 1 764 s ;
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
  - signal `detonated(effect)` ; `get_effects()`, `clear_effects()`. Les explosions restent en place jusqu'à la
    fin de la partie (persistance du monde) : seul `clear_effects()` (debug, banc de mesure) les retire.
  - Au démarrage, il lie `NukeClock` au nœud `Orbit` (`orbit_path`).
- **Interface** : colonne `Launch` du panneau de contrôle (`nuke/launch_control.gd`, chaîne de tir : tube choisi →
  `Station.launch_missile` → `missile_released` → vol `MissileFlight` (`flight_time_s`) → `NukeLauncher.launch_at` sur le point
  visé à l'appui) : panneau des silos (`nuke/silo_panel.gd`, voyants `nuke/silo_button.gd` dessinés à la main) et,
  en dessous, les boutons de puissance ; à droite, gros bouton rouge (`nuke/big_red_button.gd`, dessiné à la main).
  Au clic, le capuchon s'enfonce, reste un instant en bas puis remonte avec un léger rebond. Réticule au centre de l'écran
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

Issues de la NASA, de la NOAA ou de Natural Earth (domaine public, crédit demandé), du WRI (centrales, CC BY 4.0) et du JRC de la Commission
européenne (population, CC BY 4.0) :

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
| `assets/power_plants.res` | 34 936 centrales électriques (position, puissance, combustible, pays) et capacité de chaque pays (~0,7 Mo) | Global Power Plant Database v1.3, World Resources Institute (CC BY 4.0 ; modifié : pays recalculé sur les frontières Natural Earth) |
| `assets/textures/country_ids.png` | Carte des pays (numéro + 1 sur 16 bits), 8192 × 4096 | dérivée de Natural Earth 1:10 M, « admin 0 countries » |
| `assets/population_2030.bin` | Habitants par cellule de 1/120° en 2030 (projection), tuiles de 5° compressées (~74 Mo) | GHS-POP R2023A, JRC / Commission européenne (CC BY 4.0 ; modifié : recalage, quantification) |
| `assets/country_mask.res` | Masque des pays (changements de pays par ligne de latitude) et fiches des 258 pays et territoires (~3 Mo) | Natural Earth 1:10 M, couche « admin 0 countries » (domaine public) |

Limites des nuages réels : c'est un instantané déplacé par le vent (les nuages ne se forment ni ne se dissipent, et
la journée se répète). On voit quelques raccords entre
passages successifs du satellite (lignes droites dans les champs de nuages), et la banquise arctique est en partie
comptée comme nuage.

## Bibliographie

Ouvrages, articles et jeux de données dont sont tirés les calculs, les modèles de rendu et les images du projet.
Les paragraphes (§) sont ceux des ouvrages ; entre parenthèses, les fichiers du projet qui s'en servent.

### Effets des explosions nucléaires

- Glasstone, S. et Dolan, P. J. (1977). *The Effects of Nuclear Weapons*, 3ᵉ édition. U.S. Department of Defense et
  U.S. Department of Energy, Washington, U.S. Government Printing Office. Source principale de `nuke/` :
  - ch. II : montée du nuage (§2.12), hauteurs du nuage stabilisé et dissipation (§2.16, §2.17), durée de la
    lueur de la boule de feu (§2.18), explosions à la surface de l'eau (§2.50 et suivants) ;
  - ch. III : lois d'échelle de l'onde de choc en racine cubique de la puissance (similitude de Hopkinson-Cranz) ;
  - ch. VII : impulsion thermique (§7.85 à §7.88 : t_max, t_min, puissance au second maximum), seuils
    d'inflammation (~10 cal/cm²), incendies et tempête de feu de Hiroshima ;
  - ch. IX : retombées locales, décroissance du débit de dose en t^−1,2, contours idéalisés de débit de dose
    (vérification de `NukeFallout`), protection offerte par les bâtiments ;
  - ch. XII : effets de l'irradiation aiguë sur l'homme (dose létale médiane de l'ordre de 4,5 Gy sans soins).
- Adamsky, V. et Smirnov, Y. (1994). « Moscow's Biggest Bomb: the 50-Megaton Test of October 1961 ». *Cold War
  International History Project Bulletin*, n° 4, Woodrow Wilson International Center for Scholars. Hauteur du
  nuage de la Tsar Bomba (64 à 67 km).
- Hawthorne, H. A. (dir.) (1979). *Compilation of Local Fallout Data from Test Detonations 1945–1962 Extracted from
  DASA 1251*, DNA 1251-1-EX et 1251-2-EX. Defense Nuclear Agency. Nuages des essais Ivy Mike et Castle Bravo
  (~40 km).
- U.S. Congress, Office of Technology Assessment (1979). *The Effects of Nuclear War*, OTA-NS-89, Washington, U.S.
  Government Printing Office. Ch. II : pertes en fonction de la surpression, tirées d'Hiroshima (`NukeCasualties`).
  Table des tranches recoupée dans « Inaccurate Prediction of Nuclear Weapons Effects and Possible Adverse
  Influences on Nuclear Terrorism Preparedness », *Homeland Security Affairs*, article 97
  (https://www.hsaj.org/articles/97), qui en discute aussi les limites.
- Brode, H. L. (1986). *Airblast From Nuclear Bursts — Analytic Approximations*. Pacific-Sierra Research
  Corporation, p. 60–71. Surpression de crête au sol (`NukeScaling.overpressure_psi`), transcrite du paquet Python
  open source *glasstone* (GOFAI, licence MIT, https://github.com/GOFAI/glasstone).
- Hanifen, D. W. (1980). *Documentation and Analysis of the WSEG-10 Fallout Prediction Model*. Thèse, Air Force
  Institute of Technology. Modèle de retombées WSEG-10 (Weapons Systems Evaluation Group, 1959) de `NukeFallout`,
  transcrit d'après le paquet *glasstone* (fichier `fallout.py`).
- Way, K. et Wigner, E. P. (1948). « The Rate of Decay of Fission Products ». *Physical Review*, 73, p. 1318.
  Décroissance du débit de dose des retombées en t^−1,2 (reprise par Glasstone & Dolan, ch. IX).
- Postol, T. A. (1986). « Possible fatalities from superfires following nuclear attacks in or near urban areas ».
  In *The Medical Implications of Nuclear War*, National Academy Press. Critique du modèle de surpression (non
  retenue : limite documentée).
- Toon, O. B., Turco, R. P., Robock, A., Bardeen, C., Oman, L. et Stenchikov, G. L. (2007). « Atmospheric effects
  and societal consequences of regional scale nuclear conflicts and acts of individual nuclear terrorism ».
  *Atmospheric Chemistry and Physics*, 7, p. 1973–2002, doi:10.5194/acp-7-1973-2007. Charge de combustible urbain
  (1,1·10⁷ g par habitant, 0,0011 g/cm² par hab./km², § 6.1), facteur d'émission de fumée (0,020 g/g, d'après
  Small 1989), 1 à 5 Tg de suie pour 100 explosions de 15 kt (fumée des incendies, `NukeScaling.SMOKE_*`).
- Andreae, M. O. (2019). « Emission of trace gases and aerosols from biomass burning – an updated assessment ».
  *Atmospheric Chemistry and Physics*, 19, p. 8523–8546. Facteurs d'émission de particules des feux de végétation.
- van der Werf, G. R. et al. (2017). « Global fire emissions estimates during 1997–2016 ». *Earth System Science
  Data*, 9, p. 697–720 (GFED4). Ordres de grandeur du combustible consumé par les feux de végétation.

### Réseaux électriques

- Global Energy Observatory, Google, KTH Royal Institute of Technology in Stockholm, Enipedia, World Resources
  Institute (2019). *Global Power Plant Database*, v1.3 (2021). Licence CC BY 4.0. Publié sur Resource Watch et
  Google Earth Engine. Centrales et capacités par pays (`assets/power_plants.res`).
- Byers, L., Friedrich, J., Hennig, R., Kressig, A., Li, X., McCormick, C. et Malaguzzi Valeri, L. (2018). *A Global
  Database of Power Plants*. World Resources Institute, document technique joint à la base.
- U.S.-Canada Power System Outage Task Force (2004). *Final Report on the August 14, 2003 Blackout in the United
  States and Canada: Causes and Recommendations*. Durées de rétablissement d'une panne en cascade (panne
  régionale).
- Panne de la péninsule ibérique du 28 avril 2025 : rapports d'ENTSO-E (Réseau européen des gestionnaires de réseau
  de transport d'électricité) et de Red Eléctrica. Effondrement national en quelques secondes, rétablissement en une
  dizaine d'heures (panne nationale).

### Atmosphère, nuages et éclairage

- Bruneton, É. et Neyret, F. (2008). « Precomputed Atmospheric Scattering ». *Computer Graphics Forum*, 27(4)
  (EGSR 2008). Modèle de diffusion Rayleigh + Mie à densités exponentielles.
- Hillaire, S. (2020). « A Scalable and Production Ready Sky and Atmosphere Rendering Technique ». *Computer
  Graphics Forum*, 39(4) (EGSR 2020). Coefficients de diffusion Rayleigh, Mie et d'absorption de l'ozone
  (`shaders/atmosphere_common.gdshaderinc`, `shaders/sun_light.gdshaderinc`, `nuke/nuke_atmosphere.gd`).
- Henyey, L. G. et Greenstein, J. L. (1941). « Diffuse radiation in the Galaxy ». *The Astrophysical Journal*,
  93, p. 70–83. Fonction de phase des nuages et du champignon.
- Wrenninge, M., Kulla, C. et Lundqvist, V. (2013). « Oz: The Great and Volumetric ». *ACM SIGGRAPH 2013 Talks*.
  Approximation de la diffusion multiple (somme d'octaves d'extinction atténuée) dans les nuages et le champignon.
- Loi de Beer-Lambert : atténuation exponentielle de la lumière dans les nuages, le champignon et l'air.

### Orbite et astronomie

- U.S. Naval Observatory et HM Nautical Almanac Office. *The Astronomical Almanac*, section C, « Low-precision
  formulas for the Sun ». Position du soleil (`scripts/orbit.gd`, précision ~0,01°).
- Capitaine, N., Guinot, B. et McCarthy, D. D. (2000). « Definition of the Celestial Ephemeris Origin and of UT1 in
  the International Celestial Reference Frame ». *Astronomy & Astrophysics*, 355, p. 398–405. Angle de rotation de
  la Terre (IAU 2000).
- Petit, G. et Luzum, B. (dir.) (2010). *IERS Conventions (2010)*, IERS Technical Note n° 36. Repères céleste et
  terrestre, vitesse de rotation sidérale.
- National Imagery and Mapping Agency (2000). *Department of Defense World Geodetic System 1984*, TR8350.2,
  3ᵉ édition. Constante gravitationnelle géocentrique μ = 398 600,4418 km³/s².

### Images satellites et données géographiques

- Stöckli, R., Vermote, E., Saleous, N., Simmon, R. et Herring, D. (2005). *The Blue Marble Next Generation – A true
  color Earth dataset including seasonal dynamics from MODIS*. NASA Earth Observatory. Texture de jour (juillet
  2004, Visible Earth image 74092).
- Román, M. O. et al. (2018). « NASA's Black Marble nighttime lights product suite ». *Remote Sensing of
  Environment*, 210, p. 113–143. Lumières nocturnes (composite Black Marble 2016, Visible Earth image 144898).
- NASA EOSDIS, Global Imagery Browse Services (GIBS) et Worldview. *VIIRS NOAA-20 Corrected Reflectance (True
  Color)*, 15 juillet 2023, données LANCE. Couverture nuageuse.
- NASA Visible Earth (2002). *Blue Marble: Clouds*, image 57747. Nuages des zones sans données VIIRS.
- NASA Goddard Scientific Visualization Studio (2020). *Deep Star Maps 2020*, animation 4851 (catalogues Hipparcos-2,
  Tycho-2 et Gaia DR2). Ciel étoilé.
- NOAA National Centers for Environmental Prediction. *Global Forecast System (GFS)*, analyses 0,25° du 15 juillet
  2023, NOAA Open Data Dissemination (AWS). Vent des nuages et profil vertical du vent des champignons.
- Organisation météorologique mondiale. *Manual on Codes* (OMM-n° 306), vol. I.2, format GRIB2 (gabarit 5.3). Décodage
  des fichiers GFS (`tools/build_wind_field.ps1`).
- Natural Earth. *1:10m Physical Vectors – Ocean* (domaine public). Masque mers et océans (`assets/ocean_mask.res`).
- Schiavina, M., Freire, S., Carioli, A. et MacManus, K. (2023). *GHS-POP R2023A – GHS population grid multitemporal
  (1975–2030)*. Commission européenne, Centre commun de recherche (JRC), doi:10.2905/2FF68A52-5B5B-4A22-8F40-C41DA8332CFE.
  Licence CC BY 4.0, © Union européenne 1995-2026. Époque 2030, 30 secondes d'arc. **Modifié** : recalé sur une
  grille alignée sur 1/120° (décalage < 0,05 cellule), quantifié sur 16 bits et découpé en tuiles
  (`assets/population_2030.bin`, `tools/build_population.ps1`).
- Natural Earth. *1:10m Cultural Vectors – Admin 0 – Countries*, version 5 (domaine public). Frontières de fait,
  population estimée et PIB des pays (`assets/country_mask.res`).
