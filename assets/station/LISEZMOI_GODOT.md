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

## Conventions de noms
- `-col` : collision statique générée par Godot (murs, sols, coques, passerelles).
- `-convcolonly` : collision convexe seule, enfant des portes et trappes (suit le mouvement).
- `Interactif_*` : objets manipulables. Métadonnées : propriétés glTF « extras », exposées par Godot dans la métadonnée `extras` (dictionnaire) : `get_meta("extras")["type"]`. Clés : `type`, `id`, `ouvrable`, `animation`, `charniere`, `silo`, `tube`, `materiau_ecran`. Écoutille cargo et trappes de sol : `ouvrable = false`.
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
