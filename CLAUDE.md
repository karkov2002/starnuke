# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

« Star Nuke » — projet de jeu **Godot 4.7** (moteur de rendu Forward Plus, physique 3D Jolt, pilote D3D12 sous Windows).
État actuel : un POC de vue orbitale. Scène principale `res://scenes/orbit_view.tscn` (Terre + ciel étoilé + instance de `scenes/iss_cupola.tscn`, module Node 3 + Cupola de l'ISS).
Arborescence : `scenes/` (dont `scenes/ui/`), `scripts/`, `shaders/`, `materials/` (matériaux et Environment en `.tres`), `assets/textures/`,
`nuke/` (tout le code des explosions nucléaires, dont l'autoload `NukeClock` et la scène de debug `nuke/debug/nuke_debug.tscn`).
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
défaut dans le script). Dans un shader spatial, `hint_depth_texture` s'est révélé peu fiable sous D3D12 : l'éviter.

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
