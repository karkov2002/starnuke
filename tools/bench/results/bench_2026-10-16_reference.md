# Banc Star Nuke — 2026-10-16 18:44:49

Godot 4.7.2-stable (steam), NVIDIA GeForce RTX 5080 (d3d12), écran 5120 × 1440. V-Sync coupée, fenêtre sans bordure à la résolution mesurée, rendu 3D à l'échelle 1. Scénarios : orbite simple (temps x1, 4 s) ; 8 missiles tirés d'un coup, mesurés par phase jusqu'à l'impact puis 4 s d'explosions ; 10 explosions de 1 Mt figées à chaque instant (120 images). CPU = temps entre deux images (le jeu attend le GPU).

| Résolution | Scénario | Phase | im/s | CPU moy. (ms) | CPU pire (ms) | GPU moy. (ms) | Appels de dessin |
|---|---|---|---|---|---|---|---|
| 1920 × 1080 | Orbite simple | temps x1 | 259 | 3.86 | 4.78 | 3.74 | 790 |
| 1920 × 1080 | 8 missiles | sortie du tube | 246 | 4.07 | 22.92 | 3.93 | 1329 |
| 1920 × 1080 | 8 missiles | propulsion | 249 | 4.02 | 14.38 | 3.87 | 854 |
| 1920 × 1080 | 8 missiles | croisière | 269 | 3.72 | 4.78 | 3.61 | 781 |
| 1920 × 1080 | 8 missiles | rentrée | 235 | 4.26 | 145.59 | 4.12 | 810 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (0–4 s) | 161 | 6.21 | 9.43 | 6.08 | 845 |
| 1920 × 1080 | 10 × 1 Mt | figées à 5 s | 253 | 3.95 | 4.80 | 3.85 | 775 |
| 1920 × 1080 | 10 × 1 Mt | figées à 1 min | 228 | 4.38 | 6.33 | 4.26 | 787 |
| 1920 × 1080 | 10 × 1 Mt | figées à 10 min | 215 | 4.66 | 6.53 | 4.55 | 787 |
| 1920 × 1080 | 10 × 1 Mt | figées à 30 min | 238 | 4.21 | 5.27 | 4.10 | 777 |
| 1920 × 1080 | 10 × 1 Mt | figées à 6 h | 260 | 3.84 | 4.62 | 3.73 | 758 |
| 2560 × 1440 | Orbite simple | temps x1 | 163 | 6.15 | 7.64 | 6.01 | 744 |
| 2560 × 1440 | 8 missiles | sortie du tube | 155 | 6.44 | 8.25 | 6.30 | 1156 |
| 2560 × 1440 | 8 missiles | propulsion | 156 | 6.39 | 8.37 | 6.23 | 809 |
| 2560 × 1440 | 8 missiles | croisière | 164 | 6.11 | 12.72 | 5.98 | 733 |
| 2560 × 1440 | 8 missiles | rentrée | 148 | 6.74 | 33.84 | 6.60 | 762 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 114 | 8.80 | 10.56 | 8.66 | 797 |
| 2560 × 1440 | 10 × 1 Mt | figées à 5 s | 160 | 6.24 | 6.85 | 6.11 | 727 |
| 2560 × 1440 | 10 × 1 Mt | figées à 1 min | 151 | 6.64 | 7.66 | 6.52 | 739 |
| 2560 × 1440 | 10 × 1 Mt | figées à 10 min | 144 | 6.95 | 7.14 | 6.83 | 739 |
| 2560 × 1440 | 10 × 1 Mt | figées à 30 min | 150 | 6.68 | 7.56 | 6.55 | 729 |
| 2560 × 1440 | 10 × 1 Mt | figées à 6 h | 164 | 6.09 | 7.24 | 5.97 | 711 |
| 3440 × 1440 | Orbite simple | temps x1 | 131 | 7.61 | 9.29 | 7.47 | 705 |
| 3440 × 1440 | 8 missiles | sortie du tube | 125 | 8.01 | 10.30 | 7.85 | 1037 |
| 3440 × 1440 | 8 missiles | propulsion | 125 | 8.03 | 9.88 | 7.86 | 774 |
| 3440 × 1440 | 8 missiles | croisière | 132 | 7.57 | 9.41 | 7.43 | 692 |
| 3440 × 1440 | 8 missiles | rentrée | 122 | 8.22 | 35.02 | 8.06 | 726 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 98 | 10.23 | 13.97 | 10.09 | 765 |
| 3440 × 1440 | 10 × 1 Mt | figées à 5 s | 130 | 7.71 | 8.65 | 7.56 | 689 |
| 3440 × 1440 | 10 × 1 Mt | figées à 1 min | 121 | 8.27 | 9.65 | 8.12 | 701 |
| 3440 × 1440 | 10 × 1 Mt | figées à 10 min | 118 | 8.50 | 8.81 | 8.36 | 701 |
| 3440 × 1440 | 10 × 1 Mt | figées à 30 min | 120 | 8.35 | 9.42 | 8.21 | 691 |
| 3440 × 1440 | 10 × 1 Mt | figées à 6 h | 133 | 7.54 | 8.22 | 7.39 | 673 |
| 5120 × 1440 | Orbite simple | temps x1 | 101 | 9.92 | 11.08 | 9.74 | 679 |
| 5120 × 1440 | 8 missiles | sortie du tube | 97 | 10.33 | 12.06 | 10.15 | 1393 |
| 5120 × 1440 | 8 missiles | propulsion | 96 | 10.46 | 13.25 | 10.26 | 752 |
| 5120 × 1440 | 8 missiles | croisière | 100 | 10.04 | 12.93 | 9.87 | 664 |
| 5120 × 1440 | 8 missiles | rentrée | 95 | 10.56 | 36.85 | 10.38 | 695 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 85 | 11.81 | 14.79 | 11.65 | 727 |
| 5120 × 1440 | 10 × 1 Mt | figées à 5 s | 106 | 9.39 | 9.88 | 9.24 | 663 |
| 5120 × 1440 | 10 × 1 Mt | figées à 1 min | 104 | 9.63 | 10.02 | 9.49 | 675 |
| 5120 × 1440 | 10 × 1 Mt | figées à 10 min | 99 | 10.08 | 10.26 | 9.93 | 675 |
| 5120 × 1440 | 10 × 1 Mt | figées à 30 min | 103 | 9.73 | 9.93 | 9.58 | 665 |
| 5120 × 1440 | 10 × 1 Mt | figées à 6 h | 108 | 9.23 | 9.41 | 9.08 | 647 |

- 1920 × 1080 : tir de 10 explosions en 14.1 ms, pire image après le tir 9.2 ms.
- 2560 × 1440 : tir de 10 explosions en 14.1 ms, pire image après le tir 9.4 ms.
- 3440 × 1440 : tir de 10 explosions en 14.4 ms, pire image après le tir 10.4 ms.
- 5120 × 1440 : tir de 10 explosions en 14.2 ms, pire image après le tir 10.0 ms.

Part de chaque effet (10 × 1 Mt figées à 60 s, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 9.49 | — |
| Mushroom | 9.24 | 0.25 |
| Shock | 9.52 | -0.03 |
| nuke_cloud_count | 9.53 | -0.04 |
| nuke_ground_count | 9.73 | -0.24 |
| nuke_smoke_count | 9.65 | -0.16 |
