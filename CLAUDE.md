# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

« Star Nuke » — projet de jeu **Godot 4.7** (moteur de rendu Forward Plus, physique 3D Jolt, pilote D3D12 sous Windows).
État actuel : un POC de vue orbitale. Scène principale `res://scenes/orbit_view.tscn` (Terre + ciel étoilé + instance de `scenes/iss_cupola.tscn`, module Node 3 + Cupola de l'ISS).
Arborescence : `scenes/` (dont `scenes/ui/`), `scripts/`, `shaders/`, `materials/` (matériaux et Environment en `.tres`), `assets/textures/`,
`nuke/` (tout le code des explosions nucléaires, dont l'autoload `NukeClock` et la scène de debug `nuke/debug/nuke_debug.tscn`).
Masques géographiques (Natural Earth) : mers et océans (`scripts/ocean_mask.gd`, `assets/ocean_mask.res`) et pays
(`scripts/country_mask.gd`, `assets/country_mask.res`), générés par `tools/build_ocean_mask.gd` et `tools/build_country_mask.gd`.
Population 2030 (GHS-POP, `scripts/population_grid.gd`, `assets/population_2030.bin` ~74 Mo, `tools/build_population.ps1`) :
pertes humaines des explosions (`nuke/nuke_casualties.gd`, chronologie et retombées WSEG-10 `nuke/nuke_fallout.gd`).
Centrales électriques (WRI, `scripts/power_plants.gd`, `assets/power_plants.res`, `tools/build_power_plants.gd`) et carte des
pays pour les shaders (`assets/textures/country_ids.png`, import sans perte) : black-out (`nuke/nuke_grid_impact.gd`, `nuke/nuke_blackout_fx.gd`).
Organisation du code des explosions (une responsabilité par classe) et banc de performances (`tools/bench/nuke_bench.tscn`) : README,
« Explosions nucléaires », sections « Organisation du code » et « Performances ».
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
- Aucun outil de build, lint ou test n'est configuré. Le jeu se lance depuis l'éditeur Godot (ou via le MCP).

## Conventions

- `project.godot` est généré par l'éditeur : préférer les modifications via l'éditeur/MCP (`update_project_settings`) plutôt qu'à la main.
- Encodage UTF-8 pour tous les fichiers (`.editorconfig`).
- Non versionnés (`.gitignore`) : `.godot/` (cache d'import, shader cache, régénéré par l'éditeur ; ne pas modifier
  son contenu manuellement) et `addons/godot_mcp/cache/` (captures d'écran et instantanés d'annulation du MCP).
- Tout ajout ou modification d'une règle du jeu doit s'accompagner, dans le même travail, de la mise à jour de la
  documentation correspondante (README.md ou document de règles dédié lorsqu'il existera).
