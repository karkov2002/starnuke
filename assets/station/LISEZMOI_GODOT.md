# Station spatiale « nuke_station » – guide d'import Godot

## Animations (AnimationPlayer)
| Nom | Images (30 i/s) | Notes |
|---|---|---|
| Retraction_Radiateurs | 1-90 | jouer à l'envers pour redéployer |
| Rotation_Panneaux | 1-600 | boucle |
| Balayage_Antennes | 1-241 | boucle |
| Fermeture_Ecoutilles | 1-40 | à l'envers = ouverture |
| Ouverture_Trappes | 1-~75 | 48 trappes, en vague |
| Lancement_Missile | 1-120 | trappe 1_12 + missile ; allumage à l'image 70 ; missile à -30 m puis échelle 0 à l'image 120 (relais vers le système de frappe) |
| Depressurisation_Sas | 1-505 (24 i/s) | valve du sas : manette, aiguille 1 -> 0 bar ; à l'envers = remplissage |
| Separation_Cargo | 1-721 (24 i/s : 30 s) | `Pivot_Cargo` (parent des 9 `Cargo_*`) recule de 10 m selon -X, départ et arrêt en douceur ; à l'envers = réamarrage |

## Sas de sortie (sous le module Arrimage, x = -10,1)
- `Interactif_Ecoutille_Sas_Haut` (plancher de l'Arrimage, Ø 0,80 m, s'ouvre vers le haut) et `Interactif_Ecoutille_Sas_Bas` (porte extérieure à hublot, Ø 1,20 m, s'ouvre vers le bas, vers la Terre) : type `ecoutille`, `ouvrable = true`, pistes dans `Fermeture_Ecoutilles` (image 1 ouverte, 40 fermée).
- `Interactif_Combinaison` (type `combinaison`, `porte` = son support) et `Interactif_Porte_Combinaison` (type `porte_combinaison`, `combinaison`) : clic sur la combinaison = on l'enfile (masquée), clic sur le support = elle revient.
- `Interactif_Valve_Sas` (type `valve_sas`) : pivots `Pivot_Valve_Sas` (manette) et `Pivot_Aiguille_Sas` (manomètre) animés par `Depressurisation_Sas` (1-505 à 24 i/s : vidange 1 -> 0 bar en 20 s ; à l'envers = remplissage) ; voyants = matériaux `Int_Voyant_Sas_Vert` (plein) et `Int_Voyant_Sas_Rouge` (vide).
- `Sas_Equipements` (sacs et objets, sans collision), `Sas_Paroi-col`, `Sas_Coque-col`, lampes `Lum_Sas_1`, `Lum_Sas_2`.
- Les anciennes trappes verrouillées `Interactif_Trappe_Nadir` et `Interactif_Trappe_Sas` (et le petit sas factice `Habitation_Sas*`) n'existent plus.

## Conventions de noms
- `-col` : collision statique générée par Godot (murs, sols, coques, passerelles).
- `-convcolonly` : collision convexe seule, enfant des portes et trappes (suit le mouvement).
- `Interactif_*` : objets manipulables. Métadonnées : propriétés glTF « extras », exposées par Godot dans la métadonnée `extras` (dictionnaire) : `get_meta("extras")["type"]`. Clés : `type`, `id`, `ouvrable`, `animation`, `charniere`, `silo`, `tube`, `materiau_ecran`. Écoutille cargo : `ouvrable = false`.
- `Charniere_*` : nœud pivot à tourner (Tween) pour piloter une porte ou une trappe individuellement.
- `Pivot_*` : pivots des panneaux solaires et paraboles.

## Repères (collection Reperes_Jeu)
- `Spawn_Joueur` : départ du joueur (module d'habitation).
- `Point_Vue_Cupola` : -Z vers la Terre.
- `Point_Lancement_<silo>_<tube>` : sortie de chaque tube, flèche = direction de sortie (vers la Terre).
- `Point_Tuyere_1_12` : enfant du missile ; +Z local = direction du jet ; échelle 0 = éteint, 1 = allumé (attacher les GPUParticles3D ici).

## Écrans
Chaque écran a son propre matériau `Ecran_XX` (émissif) : le remplacer par un ViewportTexture pour une interface dynamique.

## Textures
Toutes en images (dossier textures/), coordonnées UV en mètres. Coque extérieure : `Station/Coque_SNLE_*`.

## Orientation
Axe des modules = X Godot, module de commande vers +X, Terre vers -Y. Pour voler vers -Z, tourner l'instance de 90° autour de Y.
