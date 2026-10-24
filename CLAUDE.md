# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

« Star Nuke » — projet de jeu **Godot 4.7** (moteur de rendu Forward Plus, physique 3D Jolt, pilote D3D12 sous Windows).
État actuel : un POC de vue orbitale. Scène principale : l'écran de démarrage `res://scenes/ui/main_menu.tscn` (Start Game,
Settings, Quit ; Start Game ouvre les modes de jeu : nouvelle campagne, continuer, mode libre ; campagnes = sous-dossiers de `campaign/` avec `campaign.json` format 2, lu sur le disque comme `playlist/`, catalogue `scripts/campaign/campaigns.gd`, partie en cours `CampaignSession` (`scripts/campaign/`), vérifié par `scripts/campaign/campaign_data.gd` et `tools/check_campaign.gd`, équilibré par `tools/balance_campaign.gd`, journal `user://logs/` (`CampaignJournal`, abonné aux signaux du directeur), déroulé par le nœud `CampaignDirector` (séquencement et horloge seulement ; `scripts/campaign/` : `MissionRun` mission en cours, `CampaignMessages` gabarits radio, `WorldSnapshot` sauvegarde du monde ; sonde de bout en bout `tools/bench/campaign_probe.tscn` ; briefing à son heure, appel prioritaire `scripts/campaign/priority_call.gd` (alerte jaune), sirènes d'alerte `scripts/station/alert_sirens.gd` et sons `assets/audio/alarms/` générés par `tools/build_alarm_sounds.ps1`, temps de référence : passage au plus tôt, `scripts/campaign/mission_planner.gd`), écran de fin `scenes/ui/campaign_end_screen.tscn` ; réveil par les paupières au lancement de toute partie et à chaque journée : nœud `WakeUp`, `scripts/core/wake_up.gd`), qui charge la vue orbitale `res://scenes/orbit_view.tscn` (Terre + ciel étoilé + station Blender `scenes/station_spatiale.tscn`, script `scripts/station/station.gd` (façade : signaux, réglages, API) sur les composants de `scripts/station/` (`StationHatches`, `StationSilos`, `StationAirlock`, `StationThermal`, `StationLighting`, `StationSolarPanels`, `StationModelSetup`, boîte à outils `StationAnim`, géométrie `StationLayout`), sous le nœud `Station` ; l'ancienne `scenes/iss_cupola.tscn` est gardée). Modèle `assets/station/station_spatiale.glb` : jamais retouché à la main, il n'est produit que par l'export Blender (`tools/blender/export_station.py`) ; réglages côté Godot via son `.import`, `tools/import/station_import.gd` et la scène héritée. Versionné en **Git LFS** (`.gitattributes`) ; ses textures sont sorties par l'export dans `assets/station/station_spatiale_*.png/.jpg` (versionnées, réécrites seulement si elles changent) pour ménager le quota LFS. Tout fichier de plus de 100 Mo passe en LFS. Portables et écrans plats de la station (sauf l'écran du poste et les consoles de tir) : modèles procéduraux de `tools/blender/build_station_devices.py` (README, « Station spatiale »). Sas de sortie sous l'Arrimage (`tools/blender/build_airlock.py` : combinaison à enfiler au clic, modèle texturé `tools/blender/build_suit_model.py`, casque vu de l'intérieur une fois enfilée `scripts/player/suit_helmet.gd` ; valve de dépressurisation, sans verrouillage) ; pression par module, écoutilles qui relient les volumes, courant
d'air d'expulsion vers la porte extérieure (`scripts/station/station_atmosphere.gd`, nœud `StationAir`), jets d'air et souffle à la porte ouverte (`scripts/station/air_vent_fx.gd`), témoins de pression des
modules (`scripts/station/pressure_gauges.gd`) ; expulsion pilotable
et mort sans combinaison dans le vide (`scripts/station/airlock_hazard.gd` ; avec la combinaison, jamais de mort), séquence de mort (`scripts/core/death_sequence.gd`, paupières `shaders/eyelids.gdshader`) et écran `scenes/ui/death_screen.tscn` ; cargo détachable (`Separation_Cargo`) : même section.
Paramètres du joueur (vidéo, audio, langue) : autoload `GameSettings` (`scripts/core/game_settings.gd`), sauvés dans `user://settings.cfg`,
écran `scenes/ui/settings_menu.tscn` (README, « Écran de démarrage, paramètres et langues »). Musique : autoload `Music` (`scripts/core/music_player.gd`), playlists = sous-dossiers de `playlist/` (lu sur le disque, `.gdignore`, jamais dans le `.pck` : à côté de l'exe dans le jeu exporté, le joueur y ajoute les siennes), jouées en boucle en partie ; bus « Music » et « SFX » (`default_bus_layout.tres`). Exposition : le nœud `Exposure`
(`scripts/core/exposure_control.gd`) impose la **sensibilité de l'exposition automatique Godot (min = max)** d'après le
soleil au point regardé et le flash — jamais l'exposition auto libre (dépendante du cadrage : brûlée en 32:9), ni
`exposure_multiplier` (**sans effet sur le rendu dans ce build**, Godot 4.7 D3D12 ; README, « Exposition »).
Poste de pilotage : nœud `PilotConsole` (`scripts/screens/pilot_console.gd`), grand écran de la console du module Commande
(interface 2D dans un `SubViewport`, `scripts/ui/pilot_display.gd`, carte Mercator `scripts/ui/orbital_map.gd`,
contours `assets/world_map_lines.res` générés par `tools/build_map_lines.gd`), manœuvres au nœud par `FlightComputer`
(`scripts/orbit/flight_computer.gd`), anneau 3D de l'orbite visée `GhostTrack` (`scripts/orbit/ghost_track.gd`), poussée Auto / Manuel (BURN bleu
maintenu, `scripts/ui/burn_control.gd`, aussi sur la tablette), décalage du nœud (poussée à
l'intersection des plans), précession J2 de Ω ; l'orbite reste circulaire. Altitude et inclinaison directes : panneau de debug F4 seulement. README, « Poste de pilotage ». Écrans d'ambiance animés du module Commande (code, station en fil de fer, télémétrie) : `TechScreens` (`scripts/screens/tech_screens.gd`). Afficheurs muraux LCD (base `StationLcd`, dessin `SegmentDisplay` `scripts/ui/segment_display.gd`, modèle `tools/blender/build_station_clock.py`) : horloges (couchette, cuisine, poste, sas : date ISO et heure UTC du jeu) `StationClocks` (`scripts/screens/station_clocks.gd`) ; position de la station en temps réel au pied de la couchette (latitude / longitude, pour deviner où l'on est au réveil) `StationPosition` (`scripts/screens/station_position.gd`). « Bilan des explosions » : écran mural 02 du module Commande (`NukeReportPanel`, `nuke/nuke_report_panel.gd`), plus de fenêtre à l'écran. Tous ces écrans héritent de `scripts/screens/` : `ScreenConsole` (dalle `StationScreen`, viewport, luminosité, garde de distance) et `ScreenSeatConsole` (vue assise, souris/clavier transmis, groupe `screen_seat`) ; sonde `tools/bench/console_probe.tscn`. Communication radio (écran 08 du module Commande, programme COMM.EXE façon MS-DOS / Norton, vue au clic comme la télévision ; canaux, liaison avec les stations au sol, messages et réponses pour la campagne) : `CommConsole` (`scripts/screens/comm_console.gd`), `scripts/ui/comm_display.gd`, radio `Radio` (`scripts/screens/radio_comms.gd`), README, « Communication radio ». Console radar (à la place de l'écran 07, modèle `tools/blender/build_radar_console.py` : dalle et trois boutons 3D tournés en glissant la souris, azimut, fréquence, bande VHF / UHF ; sinusoïdes chaotiques qui fusionnent à la bonne fréquence, amplitude maximale dans l'axe de la source, triangulation ; sources du mode libre Oslo VHF 100 MHz et Los Angeles UHF 800 MHz, missions : `add_source`) : `RadarConsole` (`scripts/screens/radar_console.gd`), modèle et règles `RadarReceiver` (`scripts/screens/radar_receiver.gd`), `scripts/ui/radar_display.gd`, README, « Console radar ». Télévision (écran 03 du module Commande, chaînes d'information par pays, mire « Pas de signal » si la capitale est touchée, édition spéciale « Alerte info » 24 h après chaque explosion, avec bandeau défilant dans la langue du pays, `scripts/screens/tv_news.gd`, règles `assets/tv/news_rules.json` ; sans explosion : bourse, météo de la capitale d'après les nuages réels `scripts/geo/cloud_weather.gd`, sport) : `TvConsole` (`scripts/screens/tv_console.gd` ; chaînes et règles `TvChannels`, `scripts/screens/tv_channels.gd`, `assets/tv/channels.csv`) ; vidéos `.ogv` (`assets/tv/video/`) converties depuis des maîtres MP4 modifiables (`assets/tv/source/`) par `tools/build_tv_videos.ps1`, README, « Télévision ».
Tablette (touche Tab) : `Observer/Camera/Tablet` (`scripts/player/tablet.gd`, interface `scripts/ui/tablet_display.gd` : onglets Pilotage, Photographie (`scripts/ui/photo_page.gd` : vue au nadir `NadirCamera` `scripts/player/nadir_camera.gd`, photos satellites `scripts/player/photo_archive.gd` nœud `Photos`, PNG dans `user://photos/`, galerie), Tir de missile, Alertes (`scripts/ui/alerts_page.gd` : récepteur de l'appel prioritaire, niveau d'alerte de la station), bouton HUD On/Off (`Hud.overlay_enabled`) ; date,
carte réduite, BURN, silos et tir), modèle `assets/tablet/tablet.glb` produit par `tools/blender/build_tablet.py`
(Blender en arrière-plan, `E:\Blender\tablette.blend` ; main MakeHuman via l'extension MPFB2, textures CC0 dans
`assets/makehuman/`, `.gdignore` ; mettre au point dans Blender et faire valider avant d'exporter). Interface à l'écran : `Hud` (`scripts/ui/hud.gd` : barre de
vitesse du temps toujours visible, réticule dans la cupola). Date, heure et redémarrage : panneau de debug F4. README, « Tablette ».
Règle : **tous les textes du jeu sont dans les fichiers de langue** `locale/strings.csv` (interface) et `locale/countries.csv`
(noms de pays, `tools/build_country_names.gd`) et `locale/credits.csv` (écran Crédits : références et licences), 5 langues (en, fr, es, de, it ; anglais par défaut). Jamais de texte
affiché en dur : une clé (traduction automatique des contrôles) ou `tr("CLE").format({...})` ; toute nouvelle clé reçoit
ses 5 traductions. Seuls la console et le panneau de debug (outils de développement) restent en français.
Arborescence : `scenes/` (dont `scenes/ui/`), `scripts/` regroupé par domaine (`scripts/core/` : paramètres, musique, réveil, mort, exposition, nombres ; `scripts/player/` : observateur, caméra, torche, tablette, caméra nadir, photos, casque ; `scripts/station/` : station et ses composants, air, sas, sirènes, témoins, interactions ; `scripts/orbit/` : orbite, pose de la scène, tuiles HD, ordinateur de vol, orbite fantôme, cibles, vol du missile ; `scripts/campaign/` ; `scripts/screens/` : écrans 3D, consoles, télévision, radio ; `scripts/geo/` ; `scripts/ui/` : interfaces 2D ; `scripts/debug/`), `shaders/`, `materials/` (matériaux et Environment en `.tres`), `assets/textures/`,
`nuke/` (tout le code des explosions nucléaires, dont l'autoload `NukeClock` ; section explosions du panneau de debug `nuke/debug/nuke_debug_section.gd`). Panneau de debug (F4) : `scripts/debug/` (`DebugPanel`, sections station et orbite, `DebugUi`), scène `scenes/debug_scene.tscn`.
Socle géographique commun `scripts/geo/` : `GeoMath` (rayon terrestre, km par degré, haversine, cap initial, horizon vu d'une altitude, lat/lon ↔ maillage de la
Terre, rayon-sphère, formatage des coordonnées : **une seule source**, jamais de copie locale de ces constantes ou formules),
`GeoGrid` (cellules de 1/120°), `DataResource` (chargement unique des ressources générées) ; nombres : `NumberFormat`.
Masques géographiques (Natural Earth) : mers et océans (`scripts/geo/ocean_mask.gd`, `assets/ocean_mask.res`) et pays
(`scripts/geo/country_mask.gd`, `assets/country_mask.res`), générés par `tools/build_ocean_mask.gd` et `tools/build_country_mask.gd`.
Population 2030 (GHS-POP, `scripts/geo/population_grid.gd`, `assets/population_2030.bin` ~74 Mo, `tools/build_population.ps1`) :
pertes humaines des explosions (`nuke/nuke_casualties.gd`, chronologie et retombées WSEG-10 `nuke/nuke_fallout.gd`).
Centrales électriques (WRI, `scripts/geo/power_plants.gd`, `assets/power_plants.res`, `tools/build_power_plants.gd`) et carte des
pays pour les shaders (`assets/textures/country_ids.png`, import sans perte) : black-out (`nuke/nuke_grid_impact.gd`, `nuke/nuke_ground_fx.gd`).
Règle de jeu : le monde persiste — une explosion n'est jamais retirée, incendies sur plusieurs jours (fumée en panache
sous le vent, `nuke/shaders/nuke_smoke.gdshaderinc`) puis trace au sol définitive (charbon, puis terre brûlée brune et
gravats), black-out jamais réparé, sans plafond de nombre (`NukeGroundFX` : textures de données + maille de 1°).
Explosions à 500 m d'altitude par défaut (`NukeScaling.DEFAULT_BURST_HEIGHT_KM`), pas de cratère. Après
la première demi-heure physique (accélérée), le temps des explosions suit l'horloge du jeu (`NukeClock`).
Organisation du code des explosions (une responsabilité par classe) et banc de performances (`tools/bench/bench.tscn`,
résultats de référence dans `tools/bench/results/`, sondes des champignons et du flash `tools/bench/mushroom_probe.tscn`
et `flash_probe.tscn` (A/B par effet dans le même état, captures comparées par PSNR), test de fermeture
`tools/bench/quit_probe.tscn`, compteur
à l'écran `scripts/ui/fps_overlay.gd`, F3) : README, « Explosions nucléaires », sections « Organisation du code » et
« Performances ». Mesurer l'éditeur Godot fermé (il partage le GPU) ; la base GPU varie de ±1 ms entre lancements :
comparer en A/B dans le même lancement.
L'architecture (échelle 1/10 000 de la Terre, mécanique orbitale `scripts/orbit/orbit.gd`, atmosphère, nuages volumétriques,
tuiles HD, sources des textures) est décrite dans le README. Toute la scène est placée autour d'une station fixe :
c'est la Terre que le nœud `EarthScene` (`scripts/orbit/earth_scene_driver.gd`) déplace et oriente à chaque image d'après `Orbit` (modèle pur). L'horloge est une vraie date UTC (le jeu se passe en
2035) ; les nuages (instantané VIIRS du 15/07/2023) sont déplacés par le vent réel GFS du même jour
(`assets/textures/cloud_wind.exr`, généré par `tools/build_wind_field.ps1`).

Les tuiles HD de la Terre (jour `assets/earth_tiles/` ~260 Mo, nuit `assets/earth_night_tiles/` ~180 Mo, nuages
`assets/earth_cloud_tiles/` ~350 Mo en WebP, `.gdignore`) sont
générées par `tools/build_earth_tiles.ps1`, `tools/build_cloud_tiles.ps1` et `tools/convert_tiles_webp.gd`
(voir README) ; elles sont versionnées dans le dépôt (choix validé malgré la taille).
Tout nouveau dossier de tuiles doit recevoir son `.gdignore` *avant* d'être rempli, sinon l'éditeur importe des milliers
d'images dans `.godot/imported` (fichiers `.import` et cache à supprimer ensuite).

Limites constatées du MCP Godot : il ne persiste pas l'affectation d'une ressource externe à une propriété quelconque
(ex. `WorldEnvironment.environment`) ni les `@export` de type `NodePath`/`Node` ; ces lignes ont dû être ajoutées
au `.tscn` puis réécrites via `write_file` (préférer des `@export var x: NodePath = ^"../Noeud"` avec valeur par
défaut dans le script). `instance_scene` remplace l'instance de scène déjà présente dans le même parent (il réutilise
le même identifiant d'`ext_resource`) : pour une deuxième instance, écrire le `.tscn` à la main. Dans un shader spatial, `hint_depth_texture` s'est révélé peu fiable sous D3D12 : l'éviter.

## Outils

- Un serveur MCP Godot (`godot-mcp-server`, lancé via `npx`) est configuré dans `.mcp.json`. Le privilégier pour créer/modifier
  des scènes et nœuds, lancer une scène (`run_scene`), lire les erreurs/logs et prendre des captures, plutôt que d'éditer
  les fichiers `.tscn` à la main. Il nécessite que l'éditeur Godot soit ouvert sur le projet.
- Blender ouvert sur `E:\Blender\nuke_station.blend` avec l'extension officielle « MCP » de Blender Lab (serveur TCP
  `localhost:9876`) : lui envoyer du Python avec `tools/blender_exec.ps1` (`-Code '...'` ou `-File script.py` ; le
  code assigne `result`). Mêmes capacités que depuis Claude Desktop. Chaîne : modifier le modèle dans Blender
  (contrôle par rendu), exporter avec `tools/blender/export_station.py` (réglages figés : pivots jamais appliqués,
  une piste NLA = une animation, extras, suffixes `-col`/`-convcolonly`, sans Draco), rescan Godot, capture en jeu.
  **Règle : pas de réexport vers le projet Godot sans le feu vert explicite de l'utilisateur** (modifier et rendre
  dans Blender reste libre). Chaque réexport est commité, en précisant ce qui a changé dans le `.blend`.
- Pas de build ni de lint. Vérifications avant tout commit qui touche au code du jeu :
  `powershell -ExecutionPolicy Bypass -File tools/bench/run_all_probes.ps1` (headless, ~75 s, éditeur et partie en cours
  tolérés ; s'arrête au premier échec ; README, « Lancer »). Le jeu se lance depuis l'éditeur Godot (ou via le MCP).

## Conventions

- `project.godot` est généré par l'éditeur : préférer les modifications via l'éditeur/MCP (`update_project_settings`) plutôt qu'à la main.
- **Version du jeu** (`application/config/version`, convention x.y.z, README « Version distribuable ») : **z est incrémenté à
  chaque commit** (dans le commit lui-même) ; **y** à chaque ajout fonctionnel dans le jeu (z repart à 0) ; **x reste à 0**
  (alpha) et ne change que sur demande explicite de l'utilisateur (passage en RC). Affichée en bas à droite de l'écran de
  démarrage, nom du zip (`StarNuke_<version>.zip`), métadonnées de l'exe.
- Encodage UTF-8 pour tous les fichiers (`.editorconfig`).
- Non versionnés (`.gitignore`) : `.godot/` (cache d'import, shader cache, régénéré par l'éditeur ; ne pas modifier
  son contenu manuellement) et `addons/godot_mcp/cache/` (captures d'écran et instantanés d'annulation du MCP).
- Tout ajout ou modification d'une règle du jeu doit s'accompagner, dans le même travail, de la mise à jour de la
  documentation correspondante (README.md ou document de règles dédié lorsqu'il existera).
