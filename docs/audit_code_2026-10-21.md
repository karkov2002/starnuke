# Audit du code et proposition de réorganisation (21/10/2026)

Périmètre : les 96 scripts GDScript du jeu (`scripts/` 46, `scripts/ui/` 19, `nuke/` 31), hors `tools/`.
Critères, par ordre : **responsabilité unique** (une classe = un rôle), **évolutivité** (couplages, duplication,
données hors du code), puis **performance par image**. Lecture seule : aucun fichier du jeu n'a été modifié.

Les numéros de ligne renvoient aux fichiers au commit `3248f8b`.

## 1. Diagnostic d'ensemble

Ce qui est déjà bien et sert de modèle :

- `nuke/` : lois physiques dans une seule source (`NukeScaling`), calcul pur séparé du rendu, bilans en thread
  (`NukeImpact`), extractions déjà faites de `NukeMushroom` (`NukeMushroomDrift`, `NukeMushroomParticles`).
- Données géographiques (`PopulationGrid`, `CountryMask`, `OceanMask`, `PowerPlants`) : lecture paresseuse, mutex,
  dichotomie.
- `MissionPlanner`, `MissionScoring`, `CampaignData` : calculs purs réutilisés par les outils.
- `OrbitalMap` (seule implémentation de Mercator), `TechScreens` (cadence 15 Hz, rendu coupé hors module),
  `CommDisplay` (dépend du modèle `RadioComms`, pas de sa console), `BurnControl`.
- Règle des langues respectée partout sauf un fichier mort (`draggable_window.gd:42`).

Les quatre problèmes structurels :

1. **Quatre « god objects »** : `station.gd` (1 442 lignes, 9 rôles), `campaign_director.gd` (509 lignes, 6 rôles,
   14 dépendances sortantes), `nuke_mushroom.gd` (`_update` de 152 lignes, 6 étapes), `nuke_ground_fx.gd`
   (5 rôles).
2. **Cinq écrans 3D qui recopient le même schéma** (`pilot_console`, `comm_console`, `tv_console`,
   `nuke_report_panel`, `tablet`, plus `tech_screens`) : ~180 lignes identiques par console (SubViewport,
   mesure de la dalle, UV du rayon souris, transfert des entrées, siège, bulles). Le poste de pilotage n'a pas la
   garde de distance que les trois autres ont : son viewport de ~1 700 × 1 000 px est rendu à chaque image partout
   dans la station.
3. **Duplication de constantes et de formules de base** : rayon terrestre (3 déclarations), km par degré
   (4 déclarations, dont deux valeurs différentes : 111,195 et 111,32 dans `nuke_scaling.gd:406`), haversine
   (3 copies), lat/lon ↔ vecteur du maillage (4 sites), balayage de la grille GHS-POP (2 copies de ~50 lignes),
   **règles de jeu de la campagne codées deux fois** (`CampaignDirector` et `MissionPlanner.timeline`, pour le
   banc d'équilibrage : elles peuvent diverger en silence).
4. **Signaux émis mais jamais écoutés, remplacés par du sondage par image** : `Station.alert_changed`,
   `hatch_moving`, `hatch_changed`, `Orbit.orbit_changed` n'ont aucun abonné ; `AlertSirens`, `StationAtmosphere`,
   `PilotDisplay` sondent à la place (`get_first_node_in_group` par image, reconstruction des groupes de volumes
   deux fois par image).

Côté résolution des dépendances, la convention `@export var x_path: NodePath` est majoritaire mais concurrencée par
~45 `get_first_node_in_group`, dont une dizaine **par image**, 7 `find_child` par nom de nœud du GLB, et deux
accès par réflexion (`campaign_director.gd:374-376` appelle la méthode privée `Observer._place_at_start` via
`has_method`/`call` ; `nuke_flash_fx.gd:138` écrit `_exposure.set(&"dazzle", …)`).

## 2. Constats par zone

### 2.1 `scripts/station.gd` (Station)

Rôles mélangés dans la même classe : (a) boîte à outils d'animation (`_play_tracks`, `_apply_track`, `_play_group`,
`_track_for`, `_fill_hinge`, `_tween_hinge`) ; (b) écoutilles et volants ; (c) rideaux (clés de forme + zones de
clic) ; (d) sas (combinaison, valve, courbe de l'aiguille, voyants) ; (e) cargo ; (f) trappes des silos, gyrophares,
lancement des missiles ; (g) radiateurs et chaleur ; (h) éclairage intérieur, alerte, black-out, matériaux
d'écrans ; (i) panneaux solaires ; (j) préparation du modèle (calques, collisions, vitrage mat).

| Constat | Lignes | Gravité |
|---|---|---|
| `launch_missile` : 70 lignes, calcule la transposition du missile modèle, la trappe, la tuyère, la vitesse de sortie | 870-940 | moyenne |
| `_track_sun` : `get_node_or_null(sun_path)` et `(earth_path)` à chaque image | 1026, 1031 | basse |
| `_blink_beacons` : `get_node("Lampe")`, `get_node("Lumiere")` par gyrophare et par image | 1014-1016 | basse |
| Chaleur : boucle sur `_radiators` à chaque image pour un état qui ne change qu'avec un radiateur | 263-273 | basse |
| Dictionnaires non typés (`_hatches`, `_silo_doors`, `_valve` avec 14 clés) : clés non vérifiées à la compilation | 162-205 | moyenne |
| Signaux `alert_changed`, `hatch_moving`, `hatch_changed` sans abonné (voir 2.3) | 25-44 | moyenne |

`_update_interior_light` est bien fait (application seulement si la valeur change).

**Découpe proposée** (nœuds enfants de `StationSpatiale`, créés par `Station._ready` ou posés dans la scène
héritée ; `Station` reste la façade publique et conserve son API et ses signaux, qu'elle relaie) :

| Classe | Fichier | Contenu |
|---|---|---|
| `StationAnim` (RefCounted) | `scripts/station/station_anim.gd` | bibliothèque, lecteurs par animation, `play_tracks`, `apply_track`, `play_group`, `track_for`, `fill_hinge`, `handoff_time` |
| `StationHatches` | `scripts/station/station_hatches.gd` | écoutilles, volants, rideaux (ou `StationCurtains` à part) |
| `StationAirlock` | `scripts/station/station_airlock.gd` | combinaison, valve, courbe de l'aiguille, voyants |
| `StationSilos` | `scripts/station/station_silos.gd` | trappes, gyrophares, `launch_missile`, `available_tubes` |
| `StationThermal` | `scripts/station/station_thermal.gd` | radiateurs, chaleur, `set_stealth` |
| `StationLighting` | `scripts/station/station_lighting.gd` | lampes, matériaux luminaires/écrans, alerte, black-out |
| `StationSolarPanels` | `scripts/station/station_solar_panels.gd` | suivi du soleil |
| `StationModelSetup` (static) | `scripts/station/station_model_setup.gd` | calques intérieurs, collisions, vitrage mat, cargo |

Chaque composant reçoit `Station` et `StationAnim` à la construction. Les entrées de dictionnaires deviennent de
petites classes (`HatchEntry`, `SiloDoor`, `AirlockValve`) : champs typés, plus de `entry.get("target", …)`.

### 2.2 Écrans 3D et interface (`*_console.gd`, `tablet.gd`, `nuke_report_panel.gd`, `scripts/ui/`)

Relevé des blocs identiques (fichier:lignes) :

| Bloc | pilot_console | comm_console | tv_console | tablet | nuke_report_panel | tech_screens |
|---|---|---|---|---|---|---|
| `find_child(SCREEN_NODE)` | 65 | 56 | 79 | 121 | 68 | 76 |
| Mesure de la dalle | 231-252 (normale) | 203-223 (UV) | 324-344 (UV) | 309-321 | — | — |
| Création du SubViewport | 72-78 | 64-69 | 87-93 | 125-131 | 73-78 | 60-73 |
| Surface `extras.materiau_ecran` + ShaderMaterial | 255-271 | 78-82 | 101-105 | 145-152 | 143-155 | 79-89 |
| `_screen_uv` (rayon → UV) | 157-175 | 226-244 | 347-365 | 286-304 | — | — |
| Garde de distance 12 m | **absente** | 105-109 | 185-189 | 169-170 | 85-89 | 99-104 |
| `energy` × (1 − black-out) par image sans test | — | 97 | 174 | — | 84 | 15 Hz |
| `_input` : Hud par groupe, transfert souris | 122-153 | 123-157 | 203-231 | 194-215 | — | — |
| `_sit` / `_stand_up` / `_move_to` | 178-219 | 160-198 | 282-319 | — | — | — |
| Bulles + `_bubble_style` | 274-302 | 247-275 | 368-396 | — | — | (hatch_interaction 140-147) |

Autres constats :

- `tv_console.gd` porte le **modèle des chaînes** (CSV, règle « capitale touchée », « Alerte info 24 h »,
  `news_text`), et `tv_display.gd:25` garde une référence arrière vers la console : couplage vue ↔ console.
- `tablet.gd:326-409` : caméra nadir et prise de photo (4 `await`, échange d'environnement) n'ont rien à voir
  avec la tablette en main.
- `tablet_display.gd:336-453` : page Alertes de 130 lignes dans l'ossature ; `_process` continue tablette rangée
  (Hud par groupe + horloge reformatée chaque image).
- `pilot_display.gd:126-150` : 11 `text =` par image avec `%` et `tr()`, sans test de changement.
- `tv_display.gd:117-130` : hors d'antenne, la mire (160 rectangles + RNG) est redessinée à chaque image même à
  12 m, car `set_playing` ne coupe que la vidéo.
- `settings_menu.gd:397-430` : chaque cran de curseur relit les playlists sur le disque et reconstruit la liste
  des résolutions.
- `main_menu.gd:40-41, 171-195` : le décor retire des nœuds de `orbit_view.tscn` par noms en dur et pilote
  `Orbit` par `set("time_scale", …)`.
- Cinq fabriques de `Label`, six fabriques de `StyleBoxFlat`, trois boutons 380 × 60 identiques, palettes
  redéclarées (`COLOR_GHOST` ×3, `COLOR_DIM` avec deux teintes, `MAP_MAX_LAT_DEG` redéclaré).
- `draggable_window.gd` : code mort (aucune référence) avec un texte en dur en français.
- `title_glow.gd:27` : SubViewport en `UPDATE_ALWAYS` pour un texte statique du menu.

**Découpe proposée** :

| Classe | Rôle |
|---|---|
| `StationScreen` (RefCounted, `scripts/screens/station_screen.gd`) | trouver la dalle, la mesurer (par UV ou par normale), `uv_at(camera, pos)`, `make_viewport`, `apply_shader`, `set_energy` avec test de changement |
| `ScreenInputForwarder` (RefCounted) | transfert souris/clavier vers un SubViewport, état `mouse_inside`, `pressing` |
| `HoverBubble` (CanvasLayer) | bulles de survol et de sortie, style unique, masquage en pause ; sert aussi à `HatchInteraction` |
| `ScreenSeatConsole` (Node, base) | exports communs, survol, garde de distance, siège, `_input`/`_unhandled_input`, observateur suspendu ; crochets `_screen_name`, `_measure`, `_make_material`, `_create_display`, `_on_seated`, `_on_stood_up`, `_on_near_changed`, `_handle_key` |
| `TvChannels` (`scripts/tv_channels.gd`) | modèle des chaînes extrait de `TvConsole`, injecté dans `TvDisplay` à la place de `console` |
| `NadirCamera` (SubViewport) | caméra nadir, `capture()` ; `Tablet` ne fait que relayer |
| `AlertsPage`, `PhotoPage` (Control) | pages de la tablette, comme `BurnControl` l'est déjà |
| `UiKit` / `HudStyles` / `ScreenPalette` (static) | fabriques de Label, boutons de menu, StyleBox, couleurs d'écran |

Ce qui reste spécifique après la base : Pilot = mesure par normale, shader `pilot_screen`, temps ×1 au siège,
`end_burn` en se levant ; Comm = clavier → `display.handle_key`, `mark_shown` ; TV = `TvChannels`,
`set_playing` ; NukeReportPanel = pas de siège (sous-base sans `_sit`) ; Tablet = pas de siège, main animée.
Gain estimé : ~500 lignes retirées, une seule garde de distance, un seul transfert souris.

### 2.3 Station : air, alertes, interactions

- `station_atmosphere.gd:90,143` : `_groups()` appelé deux fois par image (allocation de dictionnaires et
  tableaux, 8 appels à `is_hatch_opening`), `_route` refait un parcours en largeur par image, alors que les
  groupes ne changent qu'avec une écoutille : s'abonner à `Station.hatch_moving`/`hatch_changed`.
- `alert_sirens.gd:33-35` : `get_first_node_in_group(Station.GROUP)` à chaque image pour lire `get_alert()` :
  s'abonner à `Station.alert_changed` et supprimer `_process`.
- `station_atmosphere.gd:26-46` + `pressure_gauges.gd:13-19` : boîtes des modules et positions des témoins en
  coordonnées Blender codées en dur dans deux scripts, conversion `(x, z, −y)` écrite trois fois. Proposition :
  une ressource `StationLayout` (ou un JSON émis par `tools/blender/export_station.py`) et une seule fonction
  `BlenderFrame.to_godot(v)`. `tech_screens.gd:40-41` code aussi la géométrie des modules (`MODULES_X`).
- `station_atmosphere.gd:132-150` : la règle « alerte rouge automatique » est une règle de jeu, séparable de
  la physique des pressions.
- `exposure_control.gd:88-185` : par image, `_station.call(&"is_in_cupola")` (appel dynamique), 9 intersections
  rayon-sphère, un `Dictionary` alloué, `get_camera_3d()` 3-4 fois. L'adaptation étant lissée (τ 0,25-1 s),
  évaluer la cible à ~20 Hz suffit ; typer `_station: Station`.
- `air_vent_fx.gd:53-97` : porte fermée, calcule quand même le niveau, pose `emitting`/`amount_ratio` et cherche
  la caméra et la zone avant de tester le volume ; `:218-247` : 104 000 échantillons générés en GDScript au
  chargement (un `.wav` par `tools/build_alarm_sounds.ps1` conviendrait).
- `pressure_gauges.gd:52-67` : `"%.2f bar" %` + 3 setters de matériau par témoin et par image sans test.
- `hatch_interaction.gd:17-34` : `console_path` mort ; `:126` `CampaignDirector` par groupe à chaque rayon.
- `observer.gd:47` / `campaign_director.gd:374-376` : `_place_at_start` privée appelée par réflexion ;
  rendre publique et donner au directeur un `observer_path`.

### 2.4 Orbite, vol, campagne

- `orbit.gd:461-510` : `_update_scene` mêle modèle et placement de la scène (Terre, soleil, ciel, boucle sur
  les enfants de `Earth` avec `get_children()` alloué par image et 2 `set_shader_parameter` par enfant).
  Proposition : `EarthSceneDriver` (nœud qui lit Orbit et pose la scène), Orbit redevient un modèle pur ;
  cacher la liste des `ShaderMaterial` au `_ready`.
- `orbit.gd:188-190` ≡ `flight_computer.gd:178-180, 204-211` ≡ `mission_planner.gd:238-240` : base du plan
  orbital `node`/`quarter` + `atan2` recopiée : `OrbitSimulation.arg_lat_of(point, inc, raan)`.
- `orbit.gd` : code mort `get_raan_deg`, `get_next_node_time_s`, `is_ascending_node_at`, `predict_ground_track`,
  signal `orbit_changed` sans abonné ; `_sidereal_angle_at_unix` privée appelée par `mission_planner.gd:275`.
- `flight_computer.gd:199-214` : `get_ghost()` alloue un Dictionary de 7 clés, appelé par image par
  `ghost_track.gd:51` et `orbital_map.gd:369` : cacher, invalider sur `plan_changed`.
- **`mission_planner.gd:50-92` (`timeline`) réimplémente trois règles du `CampaignDirector`** : échéance
  (`:74-75` vs `campaign_director.gd:487`), temps de référence `par` (`:82-90` vs `:496-503`), nuit/réveil
  (`:58-70` vs `:135-139, 432-441`). Les mettre dans `CampaignData` (`deadline_s`, `par_s`,
  `wake_unix_of_day`) utilisées des deux côtés ; `tools/check_campaign.gd` sert de non-régression.
- `mission_planner.gd:132-159` : `_earliest_photo` ≈ 13 000 évaluations trigonométriques sur le fil principal à
  l'instant de l'appel prioritaire : à mesurer, et passer en `WorkerThreadPool` si > 50 ms (fonctions pures).
- **`campaign_director.gd`** (509 lignes) : séquencement, mission en cours (chrono, objectifs, précisions,
  note), messages radio, journal, capture/restauration du monde, sommeil/transition, appel prioritaire, sauts
  de temps. Découpe : `MissionRun` (RefCounted : `record`, `is_complete`, `result`), `CampaignMessages`
  (static : briefing, résultat, débriefing), `WorldSnapshot` (static `capture`/`restore` : la connaissance de
  NukeLauncher/PhotoArchive/GroundTarget/NukeClock sort du directeur), journal abonné aux signaux
  `day_started`/`mission_*`. Le directeur garde séquencement + horloge (~250 lignes). Aussi : `message_received`
  émis pendant `post` avant que l'identifiant soit connu (rattrapage `find(_briefing_id)`, `:218-230`) :
  passer l'`id` à `post`.
- `campaigns.gd` : catalogue disque + état de session statique + sauvegarde dans la même classe ;
  `pending_world` est un canal implicite menu → directeur. `root()` dupliqué avec `music_player.gd:40-43`.
- `campaign_data.gd` : parsing « HH:MM » écrit 3 fois, `RegEx.create_from_string` recompilé à chaque appel.
- `game_settings.gd:16-20, 135-136` : en-tête périmé (exposure_multiplier), `_apply_brightness` vide,
  `CAMERA_ATTRIBUTES` inutilisé.
- `photo_archive.gd:41,81` : `save_png` pleine résolution synchrone à la prise de vue (gel ponctuel).

### 2.5 Données géographiques (duplication de base)

| Élément | Copies |
|---|---|
| Rayon terrestre | `orbit.gd:28` (km), `cloud_weather.gd:17` (m), `nuke_atmosphere.gd:9` |
| Km par degré | `country_mask.gd:13`, `ocean_mask.gd:13`, `nuke_casualties.gd:35` (111,195), `nuke_scaling.gd:406` (**111,32**) |
| Haversine | `mission_scoring.gd:21`, `tv_console.gd:273`, `radio_comms.gd:191` |
| `ROWS_PER_DEGREE` + `_row_of`/`_row_latitude` + chargeur `get_mask()` | `country_mask`, `ocean_mask`, `power_plants`, `world_map_lines`, `population_grid` |
| Lat/lon ↔ vecteur du maillage de la Terre | `nuke_launcher.gd:90, 96-102`, `nuke_effect.gd:52-61`, `nuke_ground_fx.gd:259-260`, `ground_target.gd:104-108` |
| Intersection rayon-sphère | `nuke_launcher.gd:76-88`, `nuke_flash.gd:66-75`, `exposure_control.gd:142-185` |
| Conversion repère Blender → Godot | `station_atmosphere.gd:272-277`, `pressure_gauges.gd:73,81` |
| Formatage lat/lon (N/S/E/W) | `ground_target.gd:97-99`, `pilot_display.gd:198-199` |
| Arrondi 3 chiffres + groupement des milliers | `tv_news.gd:225-239`, `nuke_report_text.gd:21-32` |
| `KFT_PER_KM`, `MPH_PER_M_S`, dose WSEG-10 | `nuke_scaling`/`nuke_wseg10`, `nuke_fallout`/`nuke_wseg10` (dose écrite 3 fois) |

Proposition : `scripts/geo/geo_math.gd` (`GeoMath` : constantes, haversine, lat/lon ↔ ECEF ↔ maillage, rayon-sphère,
format), `scripts/geo/geo_grid.gd` (`GeoGrid` : lignes par degré, `row_of`, chargeur de masque), `NumberFormat`.
`nuke_grid_impact.gd:31` appelle `CountryMask._row_of` (privée) : exposer `CountryMask.index_at`.

### 2.6 `nuke/`

- **`nuke_launcher.gd:167-172`** : `get_effects()` parcourt les enfants de Earth et construit un Array à chaque
  appel ; appelé par image par `NukeFlashFX`, `NukeCloudFX`, `NukeGroundFX` (qui compare ensuite deux Arrays).
  Tenir la liste et émettre `effects_changed`.
- **`nuke_mushroom.gd:184-335`** : `_update` de 152 lignes. Avec `volumetric = true` (toujours), ~25
  `set_shader_parameter` par image vont à deux matériaux de maillages invisibles, `_profile()` alloue un
  `PackedVector2Array` de 48 points par image, et une dizaine d'uniforms constants sont renvoyés chaque image.
  Découpe : `NukeMushroomShape` (calcul pur), `NukeMushroomVolume`, `NukeMushroomMesh`. Couplage
  `_effect.get_parent().get_parent().get_node_or_null(^"Sun")` (`:141-144`).
- `nuke_flash.gd:110` + `nuke_flash_fx.gd:111-116` : `received_flux` (8 pas d'atmosphère) calculé deux fois par
  flash et par image ; `_eye_exposed` cherche la station par groupe chaque image alors que `setup` la reçoit.
- `nuke_ground_fx.gd` : 5 rôles (constantes, colonnes d'événements, maille 1°, panaches, pannes nationales) ;
  `:109-129` réécrit toute la texture de données par image alors que seule la ligne des temps change ;
  `_update_countries` alloue et boucle chaque image.
- `nuke_casualties.gd:59-119` ≡ `nuke_fallout.gd:75-141` : même balayage de la grille GHS-POP (~50 lignes) :
  `NukePopulationScan.scan(lat, lon, reach, visitor)` + `country_entry`.
- `launch_control.gd` : UI du panneau de tir et séquence de lancement (station → `MissileFlight` → lanceur) dans
  le même `HBoxContainer` ; 5 `get_first_node_in_group`, `&"hud"` en littéral, remontée `get_parent()` jusqu'au
  `CanvasLayer`. Extraire `LaunchSequencer` (sans UI, utilisé par le banc).
- `nuke_scaling.gd:404-428` : `smoke_yield_kg_m2` lit `PopulationGrid`/`OceanMask` depuis la classe de lois ;
  `format_yield` est de la présentation.
- `nuke_debug_panel.gd` : panneau de debug général (station, radio, orbite, temps) rangé sous `nuke/debug`,
  `_ready` de 124 lignes ; par image : 3 formatages `%` et 2 lookups de groupe.
- `aim_reticle.gd:14-31` : `queue_redraw` + lookup de groupe + `%` + 2 `tr()` par image.
- `nuke_effect.gd:65-72` : `get_flash()` = `get_node_or_null` par image ; `get_time_s()` appelé 5 à 7 fois par
  explosion et par image : le calculer une fois dans `_process` et l'exposer.

## 3. Plan proposé

Quatre lots, chacun en étapes commitables séparément (montrer, documenter, commiter). Les lots 0 et 1 ne
changent aucun comportement et s'exécutent vite ; les lots 2 et 3 sont les vraies découpes.

### Lot 0 : corrections sans risque (une séance) — **fait le 21/10/2026** (6 commits, « Lot 0 (n/6) »)

Vérifié en jeu par le MCP (scène lancée, aucune erreur, états lus à l'exécution) ; banc de mesure non relancé
(l'éditeur était ouvert : à faire éditeur fermé, résultat à verser dans `tools/bench/results/`).

1. S'abonner aux signaux existants : `AlertSirens` ← `alert_changed` ; `StationAtmosphere` ← `hatch_moving`
   / `hatch_changed` (groupes et routes recalculés sur événement, mélange seul par image).
2. `Observer.place_at_start()` publique + `observer_path` dans le directeur ; `post(id)` avant le briefing.
3. `NukeLauncher` : liste des effets + `effects_changed` ; `NukeFlash` stocke `received_at_camera` ;
   `NukeFlashFX` garde `_station`.
4. Garde de distance au poste de pilotage (comme les trois autres écrans) ; `TitleGlow` en `UPDATE_ONCE` ;
   `set_energy` avec test de changement (3 fichiers).
5. Code mort : `draggable_window.gd`, méthodes orphelines d'`orbit.gd`, `hatch_interaction.console_path`,
   `exposure_control.orbit_path`, en-tête et `CAMERA_ATTRIBUTES` de `game_settings.gd`.
6. `Hud.GROUP` et `ExposureControl.GROUP` à la place des littéraux ; typer `_station`/`_exposure`.

Mesure : banc `tools/bench/bench.tscn` avant/après (résultat versionné dans `tools/bench/results/`).

### Lot 1 : boîtes à outils partagées (une à deux séances) — **fait le 21/10/2026** (5 commits, « Lot 1 (n/5) »)

Vérifié en headless depuis la ligne de commande (compilation des scripts touchés, valeurs unitaires de GeoMath,
GeoGrid, NumberFormat, CampaignData, StationScreen, UiKit, StationLayout, sortie identique de
`tools/check_campaign.gd`, sonde de fermeture `tools/bench/quit_probe.tscn` sans erreur). Écart avec le plan :
`StationLayout` est une table GDScript (une source), pas encore un fichier exporté par Blender ; la constante
km/degré unique vaut 111,195.

1. `GeoMath` + `GeoGrid` + `NumberFormat` ; remplacer les copies ; trancher la valeur unique de km/degré
   (111,195 : l'autre est une approximation à l'équateur) et comparer un bilan de tir en console avant/après.
2. Règles de campagne dans `CampaignData` (`deadline_s`, `par_s`, `wake_unix_of_day`), utilisées par le
   directeur et par `MissionPlanner.timeline` ; `tools/check_campaign.gd` doit donner la même sortie.
3. `StationScreen` + `ScreenInputForwarder` + `HoverBubble` : extraction de code identique, UV comparées
   avant/après.
4. `UiKit` / `HudStyles` / `ScreenPalette` ; `_add_percent_slider` généralisé dans les paramètres.
5. `StationLayout` (boîtes des modules, témoins, écrans) en ressource ou JSON exporté de Blender, avec
   `BlenderFrame.to_godot` ; `TechScreens.MODULES_X` et `Station.is_in_cupola` lisent la même source.

### Lot 2 : découpes « une classe, un rôle » (plusieurs séances, une classe par commit)

1. `ScreenSeatConsole` : base des trois consoles ; `NukeReportPanel` passe de `CanvasLayer` à `Node`. — **fait
   le 22/10/2026** : deux bases (`ScreenConsole` pour la dalle, le viewport, la luminosité et la garde de
   distance ; `ScreenSeatConsole` pour la vue assise), `ScreenSeat` fondu dans `ScreenSeatConsole` ; les trois
   consoles passent de 178 / 158 / 270 lignes à 90 / 62 / 174, le bilan de 262 à 252. Vérifié par la sonde
   `tools/bench/console_probe.tscn` (64 contrôles en headless) et en jeu par le MCP (captures des trois écrans).
   Écart avec l'avant : pendant la transition de retour, la radio aussi garde la souris (comme le poste et la
   télévision) ; l'interface n'est suspendue ou reprise qu'au changement de portée, plus à chaque image.
2. `TvChannels` extrait de `TvConsole`, injecté dans `TvDisplay`. — **fait le 22/10/2026** : `TvChannels`
   (RefCounted, `scripts/tv_channels.gd`) tient le CSV, les deux règles de jeu et le texte des bandeaux, sans
   nœud : la console lui passe les explosions et l'heure UTC (`update`), l'interface se rafraîchit sur son signal
   `changed` et ne connaît plus la console. `TvConsole` : 174 → 95 lignes.
3. `Tablet` : `NadirCamera`, `AlertsPage`, `PhotoPage`. — **fait le 22/10/2026** : `NadirCamera` (SubViewport,
   `scripts/nadir_camera.gd` : caméra, suivi de la station, `capture_photo`, emprise), `PhotoPage` et `AlertsPage`
   (`scripts/ui/`) ; `Tablet` 340 → 272 lignes, `TabletDisplay` 473 → 220. Sonde : section Tablette (sortie,
   nadir active sur l'onglet, visée, emprise, niveau d'alerte marqué ; la photo elle-même n'est vérifiable qu'avec
   rendu : `frame_post_draw` ne vient pas en headless), photo vérifiée en jeu par le MCP.
4. `Station` : `StationAnim`, puis un composant par commit (`StationLighting`, `StationSilos`,
   `StationAirlock`, `StationHatches`, `StationThermal`, `StationSolarPanels`, `StationModelSetup`), entrées
   typées. — **en cours** : `StationAnim` fait le 22/10/2026 (`scripts/station/station_anim.gd` : bibliothèque,
   lecteurs, `play_group`, `play_tracks`, `tween_hinge`, `fill_hinge`, `apply_track`, `track_for`,
   `handoff_time` ; `Station` 1 442 → 1 337 lignes) ; `StationLighting` fait le 22/10 (lampes, luminaires, écrans,
   alerte, black-out ; `Station` → 1 234 lignes) ; `StationSolarPanels` fait le 22/10 (suivi du soleil, soleil et
   Terre résolus une fois ; `Station` → 1 194 lignes) ; `StationSilos` fait le 22/10 (trappes en entrées typées
   `SiloDoor`, gyrophares, lancement ; `StationAnim.tween_hinge` rend le Tween et `hinge_range` remplace les
   dictionnaires ; `Station` → 1 014 lignes, façade de relais) ; `StationHatches` fait le 22/10 (écoutilles et
   trappes verrouillées `Hatch`, volants, rideaux `Curtain` ; `Station` → 815 lignes). Non-régression : section Station de
   `tools/bench/console_probe.tscn` (écoutille, trappe, radiateurs et chaleur, cargo, combinaison, valve du sas,
   alerte et black-out, lancement d'un missile jusqu'au relais), écrite avant la découpe.
5. `CampaignDirector` : `WorldSnapshot`, `CampaignMessages`, `MissionRun`, journal par signaux ; `Campaigns`
   scindé en catalogue et session. Non-régression : une campagne jouée de bout en bout + `balance_campaign`.
6. `nuke/` : `NukePopulationScan`, `NukeMushroomShape`/`Volume`/`Mesh`, `NukeCellIndex` + `NukeSmokePlumes`
   hors de `NukeGroundFX`, `LaunchSequencer`, `NukeSmokeYield` hors de `NukeScaling`, panneau de debug scindé
   (`scripts/debug/`).
7. `Orbit` : `EarthSceneDriver` ; `arg_lat_of` partagé.

### Lot 3 : boucles par image (après les lots 1 et 2, mesuré en A/B)

- `ExposureControl` cadencé à 20 Hz, caméra cachée, retour sans allocation.
- `NukeMushroom` : rien pour les maillages quand volumétrique, uniforms constants posés une fois (PSNR avec
  `tools/bench/mushroom_probe.tscn`).
- `NukeGroundFX` : texture des temps séparée (une ligne réécrite) ; `_update_countries` sur événement.
- `PilotDisplay`, `TabletDisplay`, `TvDisplay`, `BurnControl`, `AimReticle` : sur signaux (`orbit_changed`,
  `plan_changed`, `overlay_changed`) ou cadence 2 Hz ; `set_process(false)` quand l'écran n'est pas rendu.
- `AirVentFx` sortie anticipée porte fermée ; `PressureGauges` à 10 Hz ; `SettingsMenu` : valeurs et listes
  rafraîchies séparément ; `PhotoArchive.save_png` en thread ; `MissionPlanner.earliest` en thread si > 50 ms.
- `FlightComputer.get_ghost()` mis en cache ; `_groups()`/`any_seated` sans allocation par image.

### Arborescence cible (optionnelle, en dernier)

`scripts/` compte 46 fichiers à plat. Une fois les découpes faites, regrouper par domaine avec le déplacement
de l'éditeur Godot (qui réécrit les références) : `scripts/station/` (station et composants, air, sas,
interactions), `scripts/orbit/` (orbite, vol, missile), `scripts/campaign/`, `scripts/screens/` (écrans 3D et
leurs vues), `scripts/geo/` (masques, population, centrales, GeoMath), `scripts/core/` (paramètres, musique,
réveil, mort). Mettre à jour `CLAUDE.md` et le README (« Organisation de la scène ») au même commit.

## 4. Conventions à fixer (pour l'évolutivité)

- **Résolution des dépendances** : `@export var x_path: NodePath` pour les nœuds de la même scène (règle déjà
  dans `CLAUDE.md`) ; groupe seulement pour ce qui est optionnel ou créé à l'exécution, résolu **une fois** au
  `_ready` ou à la première utilisation, jamais par image ; aucun `find_child` par nom de nœud du GLB hors de
  `Station` (qui expose `get_screen(id)`, `module_at(position)`, etc.).
- **Événement plutôt que sondage** : un état qui change rarement (alerte, écoutille, orbite, plan de manœuvre,
  liste des explosions) est publié par signal ; `_process` ne reste que pour ce qui bouge chaque image.
- **Une constante, une source** : physique dans `NukeScaling`, géographie dans `GeoMath`, règles de campagne
  dans `CampaignData`, couleurs d'écran dans `ScreenPalette`.
- **Données hors du code** quand elles décrivent le monde ou le modèle : stations au sol (`radio_comms.gd:35-52`
  en constante → CSV comme `channels.csv`), rubriques des crédits, géométrie de la station (export Blender).
- **Entrées typées** : une petite classe plutôt qu'un `Dictionary` à clés libres dès qu'une structure traverse
  deux fonctions (`HatchEntry`, `OrbitState`, `TvChannel`, `PendingShot`, `NukeImpactResult`).
- Fonction > 60 lignes = à découper par étape ; classe > 400 lignes = à justifier.
