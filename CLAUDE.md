# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

« Star Nuke » — projet de jeu **Godot 4.7** (moteur de rendu Forward Plus, physique 3D Jolt, pilote D3D12 sous Windows).
État actuel : un POC de vue orbitale. Scène principale : l'écran de démarrage `res://scenes/ui/main_menu.tscn` (Start Game,
Settings, Quit), qui charge la vue orbitale `res://scenes/orbit_view.tscn` (Terre + ciel étoilé + station Blender `scenes/station_spatiale.tscn`, script `scripts/station.gd`, sous le nœud `Station` ; l'ancienne `scenes/iss_cupola.tscn` est gardée). Modèle `assets/station/station_spatiale.glb` : jamais retouché à la main, il n'est produit que par l'export Blender (`tools/blender/export_station.py`) ; réglages côté Godot via son `.import`, `tools/import/station_import.gd` et la scène héritée. Portables et écrans plats de la station (sauf l'écran du poste et les consoles de tir) : modèles procéduraux de `tools/blender/build_station_devices.py` (README, « Station spatiale »).
Paramètres du joueur (vidéo, audio, langue) : autoload `GameSettings` (`scripts/game_settings.gd`), sauvés dans `user://settings.cfg`,
écran `scenes/ui/settings_menu.tscn` (README, « Écran de démarrage, paramètres et langues »). Musique : autoload `Music` (`scripts/music_player.gd`), playlists = sous-dossiers de `playlist/` (lu sur le disque, `.gdignore`, jamais dans le `.pck` : à côté de l'exe dans le jeu exporté, le joueur y ajoute les siennes), jouées en boucle en partie ; bus « Music » et « SFX » (`default_bus_layout.tres`). Exposition : le nœud `Exposure`
(`scripts/exposure_control.gd`) impose la **sensibilité de l'exposition automatique Godot (min = max)** d'après le
soleil au point regardé et le flash — jamais l'exposition auto libre (dépendante du cadrage : brûlée en 32:9), ni
`exposure_multiplier` (**sans effet sur le rendu dans ce build**, Godot 4.7 D3D12 ; README, « Exposition »).
Poste de pilotage : nœud `PilotConsole` (`scripts/pilot_console.gd`), grand écran de la console du module Commande
(interface 2D dans un `SubViewport`, `scripts/ui/pilot_display.gd`, carte Mercator `scripts/ui/orbital_map.gd`,
contours `assets/world_map_lines.res` générés par `tools/build_map_lines.gd`), manœuvres au nœud par `FlightComputer`
(`scripts/flight_computer.gd`), anneau 3D de l'orbite visée `GhostTrack` (`scripts/ghost_track.gd`), poussée Auto / Manuel (BURN bleu
maintenu, `scripts/ui/burn_control.gd`, aussi sur la tablette), décalage du nœud (poussée à
l'intersection des plans), précession J2 de Ω ; l'orbite reste circulaire. Altitude et inclinaison directes : panneau de debug F4 seulement. README, « Poste de pilotage ». Écrans d'ambiance animés du module Commande (code, station en fil de fer, télémétrie) : `TechScreens` (`scripts/tech_screens.gd`). Télévision (écran 03 du module Commande, chaînes d'information par pays, mire « Pas de signal » si la capitale est touchée, édition spéciale « Alerte info » 24 h après chaque explosion, avec bandeau défilant dans la langue du pays, `scripts/tv_news.gd`) : `TvConsole` (`scripts/tv_console.gd`, `assets/tv/channels.csv`) ; vidéos `.ogv` (`assets/tv/video/`) converties depuis des maîtres MP4 modifiables (`assets/tv/source/`) par `tools/build_tv_videos.ps1`, README, « Télévision ».
Tablette (touche Tab) : `Observer/Camera/Tablet` (`scripts/tablet.gd`, interface `scripts/ui/tablet_display.gd` : onglets Pilotage, Photographie (vue au nadir), Tir de missile, bouton HUD On/Off (`Hud.overlay_enabled`) ; date,
carte réduite, BURN, silos et tir), modèle `assets/tablet/tablet.glb` produit par `tools/blender/build_tablet.py`
(Blender en arrière-plan, `E:\Blender\tablette.blend` ; main MakeHuman via l'extension MPFB2, textures CC0 dans
`assets/makehuman/`, `.gdignore` ; mettre au point dans Blender et faire valider avant d'exporter). Interface à l'écran : `Hud` (`scripts/ui/hud.gd` : barre de
vitesse du temps toujours visible, réticule dans la cupola). Date, heure et redémarrage : panneau de debug F4. README, « Tablette ».
Règle : **tous les textes du jeu sont dans les fichiers de langue** `locale/strings.csv` (interface) et `locale/countries.csv`
(noms de pays, `tools/build_country_names.gd`), 5 langues (en, fr, es, de, it ; anglais par défaut). Jamais de texte
affiché en dur : une clé (traduction automatique des contrôles) ou `tr("CLE").format({...})` ; toute nouvelle clé reçoit
ses 5 traductions. Seuls la console et le panneau de debug (outils de développement) restent en français.
Arborescence : `scenes/` (dont `scenes/ui/`), `scripts/`, `shaders/`, `materials/` (matériaux et Environment en `.tres`), `assets/textures/`,
`nuke/` (tout le code des explosions nucléaires, dont l'autoload `NukeClock` et la scène de debug `nuke/debug/nuke_debug.tscn`).
Masques géographiques (Natural Earth) : mers et océans (`scripts/ocean_mask.gd`, `assets/ocean_mask.res`) et pays
(`scripts/country_mask.gd`, `assets/country_mask.res`), générés par `tools/build_ocean_mask.gd` et `tools/build_country_mask.gd`.
Population 2030 (GHS-POP, `scripts/population_grid.gd`, `assets/population_2030.bin` ~74 Mo, `tools/build_population.ps1`) :
pertes humaines des explosions (`nuke/nuke_casualties.gd`, chronologie et retombées WSEG-10 `nuke/nuke_fallout.gd`).
Centrales électriques (WRI, `scripts/power_plants.gd`, `assets/power_plants.res`, `tools/build_power_plants.gd`) et carte des
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
L'architecture (échelle 1/10 000 de la Terre, mécanique orbitale `scripts/orbit.gd`, atmosphère, nuages volumétriques,
tuiles HD, sources des textures) est décrite dans le README. Toute la scène est placée autour d'une station fixe :
c'est la Terre que `Orbit` déplace et oriente à chaque image. L'horloge est une vraie date UTC (le jeu se passe en
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
- Aucun outil de build, lint ou test n'est configuré. Le jeu se lance depuis l'éditeur Godot (ou via le MCP).

## Conventions

- `project.godot` est généré par l'éditeur : préférer les modifications via l'éditeur/MCP (`update_project_settings`) plutôt qu'à la main.
- Encodage UTF-8 pour tous les fichiers (`.editorconfig`).
- Non versionnés (`.gitignore`) : `.godot/` (cache d'import, shader cache, régénéré par l'éditeur ; ne pas modifier
  son contenu manuellement) et `addons/godot_mcp/cache/` (captures d'écran et instantanés d'annulation du MCP).
- Tout ajout ou modification d'une règle du jeu doit s'accompagner, dans le même travail, de la mise à jour de la
  documentation correspondante (README.md ou document de règles dédié lorsqu'il existera).
