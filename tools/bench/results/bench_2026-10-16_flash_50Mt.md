# Banc Star Nuke — 2026-10-16 20:33:25

Godot 4.7.2-stable (steam), NVIDIA GeForce RTX 5080 (d3d12), écran 5120 × 1440. V-Sync coupée, fenêtre sans bordure à la résolution mesurée, rendu 3D à l'échelle 1. Scénarios : orbite simple (temps x1, 4 s) ; 8 missiles tirés d'un coup, mesurés par phase jusqu'à l'impact puis 60 s d'explosions ; 10 explosions de 50 Mt figées à chaque instant (120 images). CPU = temps entre deux images (le jeu attend le GPU).

| Résolution | Scénario | Phase | im/s | CPU moy. (ms) | CPU pire (ms) | GPU moy. (ms) | Appels de dessin |
|---|---|---|---|---|---|---|---|
| 1920 × 1080 | Orbite simple | temps x1 | 240 | 4.17 | 5.30 | 4.01 | 790 |
| 1920 × 1080 | 8 missiles | sortie du tube | 227 | 4.40 | 6.90 | 4.21 | 1334 |
| 1920 × 1080 | 8 missiles | propulsion | 230 | 4.34 | 6.78 | 4.14 | 854 |
| 1920 × 1080 | 8 missiles | croisière | 252 | 3.96 | 5.65 | 3.79 | 781 |
| 1920 × 1080 | 8 missiles | rentrée | 220 | 4.55 | 90.72 | 4.40 | 810 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (0–4 s) | 149 | 6.71 | 9.67 | 6.54 | 854 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (4–20 s) | 145 | 6.89 | 10.12 | 6.74 | 865 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (20–60 s) | 187 | 5.34 | 34.66 | 5.18 | 864 |
| 1920 × 1080 | 10 × 50 Mt | figées à 5 s | 174 | 5.73 | 8.53 | 5.58 | 819 |
| 1920 × 1080 | 10 × 50 Mt | figées à 1 min | 184 | 5.44 | 6.89 | 5.33 | 798 |
| 1920 × 1080 | 10 × 50 Mt | figées à 10 min | 187 | 5.34 | 6.55 | 5.20 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 30 min | 210 | 4.75 | 6.41 | 4.62 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 6 h | 142 | 7.06 | 8.69 | 6.93 | 789 |
| 2560 × 1440 | Orbite simple | temps x1 | 157 | 6.36 | 8.26 | 6.20 | 745 |
| 2560 × 1440 | 8 missiles | sortie du tube | 150 | 6.68 | 9.52 | 6.53 | 1155 |
| 2560 × 1440 | 8 missiles | propulsion | 151 | 6.61 | 9.04 | 6.42 | 807 |
| 2560 × 1440 | 8 missiles | croisière | 158 | 6.32 | 8.11 | 6.17 | 733 |
| 2560 × 1440 | 8 missiles | rentrée | 135 | 7.42 | 34.11 | 7.21 | 763 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 97 | 10.26 | 15.47 | 10.07 | 806 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 83 | 12.04 | 15.87 | 11.86 | 817 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 117 | 8.53 | 36.04 | 8.29 | 817 |
| 2560 × 1440 | 10 × 50 Mt | figées à 5 s | 105 | 9.53 | 11.35 | 9.34 | 772 |
| 2560 × 1440 | 10 × 50 Mt | figées à 1 min | 124 | 8.04 | 9.82 | 7.84 | 750 |
| 2560 × 1440 | 10 × 50 Mt | figées à 10 min | 128 | 7.80 | 9.47 | 7.60 | 756 |
| 2560 × 1440 | 10 × 50 Mt | figées à 30 min | 134 | 7.45 | 9.31 | 7.25 | 757 |
| 2560 × 1440 | 10 × 50 Mt | figées à 6 h | 87 | 11.55 | 13.34 | 11.38 | 749 |
| 3440 × 1440 | Orbite simple | temps x1 | 127 | 7.87 | 9.87 | 7.65 | 705 |
| 3440 × 1440 | 8 missiles | sortie du tube | 121 | 8.27 | 16.23 | 8.05 | 1037 |
| 3440 × 1440 | 8 missiles | propulsion | 122 | 8.21 | 10.90 | 8.03 | 774 |
| 3440 × 1440 | 8 missiles | croisière | 129 | 7.78 | 10.57 | 7.62 | 692 |
| 3440 × 1440 | 8 missiles | rentrée | 112 | 8.92 | 34.33 | 8.72 | 726 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 81 | 12.34 | 19.16 | 12.16 | 774 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 70 | 14.32 | 22.64 | 14.14 | 788 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 98 | 10.20 | 35.52 | 10.00 | 783 |
| 3440 × 1440 | 10 × 50 Mt | figées à 5 s | 99 | 10.15 | 11.52 | 9.99 | 734 |
| 3440 × 1440 | 10 × 50 Mt | figées à 1 min | 97 | 10.27 | 10.64 | 10.11 | 713 |
| 3440 × 1440 | 10 × 50 Mt | figées à 10 min | 105 | 9.51 | 10.60 | 9.36 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 30 min | 114 | 8.77 | 10.12 | 8.63 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 6 h | 69 | 14.54 | 15.74 | 14.39 | 711 |
| 5120 × 1440 | Orbite simple | temps x1 | 93 | 10.79 | 12.31 | 10.61 | 679 |
| 5120 × 1440 | 8 missiles | sortie du tube | 91 | 11.03 | 13.08 | 10.85 | 1406 |
| 5120 × 1440 | 8 missiles | propulsion | 93 | 10.80 | 14.23 | 10.58 | 753 |
| 5120 × 1440 | 8 missiles | croisière | 93 | 10.71 | 14.18 | 10.54 | 664 |
| 5120 × 1440 | 8 missiles | rentrée | 88 | 11.35 | 35.96 | 11.15 | 696 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 75 | 13.37 | 16.75 | 13.19 | 736 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 72 | 13.80 | 17.41 | 13.60 | 750 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 88 | 11.37 | 35.34 | 11.12 | 745 |
| 5120 × 1440 | 10 × 50 Mt | figées à 5 s | 74 | 13.60 | 15.11 | 13.43 | 708 |
| 5120 × 1440 | 10 × 50 Mt | figées à 1 min | 81 | 12.40 | 13.22 | 12.23 | 688 |
| 5120 × 1440 | 10 × 50 Mt | figées à 10 min | 84 | 11.87 | 13.78 | 11.70 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 30 min | 87 | 11.44 | 12.84 | 11.26 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 6 h | 58 | 17.20 | 18.92 | 17.01 | 685 |

- 1920 × 1080 : tir de 10 explosions en 14.2 ms, pire image après le tir 11.9 ms.
- 2560 × 1440 : tir de 10 explosions en 14.4 ms, pire image après le tir 11.7 ms.
- 3440 × 1440 : tir de 10 explosions en 14.6 ms, pire image après le tir 11.8 ms.
- 5120 × 1440 : tir de 10 explosions en 14.5 ms, pire image après le tir 11.8 ms.

Part de chaque effet (10 × 50 Mt figées à 1 min, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 12.27 | — |
| Mushroom | 10.17 | 2.10 |
| Shock | 11.15 | 1.12 |
| nuke_cloud_count | 12.19 | 0.08 |
| nuke_ground_count | 12.23 | 0.04 |
| nuke_smoke_count | 12.25 | 0.02 |

Part de chaque effet (10 × 50 Mt figées à 6 h, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 17.00 | — |
| Mushroom | 10.15 | 6.85 |
| Shock | 17.15 | -0.15 |
| nuke_cloud_count | 17.17 | -0.17 |
| nuke_ground_count | 17.14 | -0.14 |
| nuke_smoke_count | 16.91 | 0.09 |
