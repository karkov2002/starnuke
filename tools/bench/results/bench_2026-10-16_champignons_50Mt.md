# Banc Star Nuke — 2026-10-16 19:44:45

Godot 4.7.2-stable (steam), NVIDIA GeForce RTX 5080 (d3d12), écran 5120 × 1440. V-Sync coupée, fenêtre sans bordure à la résolution mesurée, rendu 3D à l'échelle 1. Scénarios : orbite simple (temps x1, 4 s) ; 8 missiles tirés d'un coup, mesurés par phase jusqu'à l'impact puis 60 s d'explosions ; 10 explosions de 50 Mt figées à chaque instant (120 images). CPU = temps entre deux images (le jeu attend le GPU).

| Résolution | Scénario | Phase | im/s | CPU moy. (ms) | CPU pire (ms) | GPU moy. (ms) | Appels de dessin |
|---|---|---|---|---|---|---|---|
| 1920 × 1080 | Orbite simple | temps x1 | 252 | 3.97 | 5.07 | 3.83 | 790 |
| 1920 × 1080 | 8 missiles | sortie du tube | 240 | 4.17 | 8.89 | 4.02 | 1342 |
| 1920 × 1080 | 8 missiles | propulsion | 245 | 4.08 | 5.87 | 3.92 | 855 |
| 1920 × 1080 | 8 missiles | croisière | 263 | 3.80 | 4.85 | 3.67 | 781 |
| 1920 × 1080 | 8 missiles | rentrée | 205 | 4.87 | 47.45 | 4.73 | 808 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (0–4 s) | 106 | 9.44 | 14.05 | 9.31 | 854 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (4–20 s) | 101 | 9.86 | 15.45 | 9.72 | 865 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (20–60 s) | 192 | 5.21 | 34.99 | 5.06 | 864 |
| 1920 × 1080 | 10 × 50 Mt | figées à 5 s | 121 | 8.25 | 11.95 | 8.14 | 819 |
| 1920 × 1080 | 10 × 50 Mt | figées à 1 min | 194 | 5.14 | 6.54 | 5.01 | 798 |
| 1920 × 1080 | 10 × 50 Mt | figées à 10 min | 194 | 5.15 | 7.45 | 5.01 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 30 min | 215 | 4.64 | 6.05 | 4.52 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 6 h | 150 | 6.66 | 8.06 | 6.53 | 789 |
| 2560 × 1440 | Orbite simple | temps x1 | 161 | 6.23 | 7.64 | 6.10 | 744 |
| 2560 × 1440 | 8 missiles | sortie du tube | 153 | 6.52 | 13.40 | 6.38 | 1154 |
| 2560 × 1440 | 8 missiles | propulsion | 155 | 6.44 | 8.25 | 6.28 | 807 |
| 2560 × 1440 | 8 missiles | croisière | 165 | 6.06 | 7.51 | 5.93 | 733 |
| 2560 × 1440 | 8 missiles | rentrée | 132 | 7.55 | 34.22 | 7.40 | 761 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 76 | 13.18 | 18.36 | 13.03 | 806 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 61 | 16.50 | 20.03 | 16.34 | 817 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 121 | 8.25 | 35.80 | 8.08 | 817 |
| 2560 × 1440 | 10 × 50 Mt | figées à 5 s | 99 | 10.13 | 10.76 | 9.97 | 772 |
| 2560 × 1440 | 10 × 50 Mt | figées à 1 min | 133 | 7.52 | 8.63 | 7.39 | 750 |
| 2560 × 1440 | 10 × 50 Mt | figées à 10 min | 135 | 7.43 | 9.07 | 7.29 | 756 |
| 2560 × 1440 | 10 × 50 Mt | figées à 30 min | 142 | 7.05 | 8.42 | 6.92 | 757 |
| 2560 × 1440 | 10 × 50 Mt | figées à 6 h | 93 | 10.79 | 12.39 | 10.66 | 749 |
| 3440 × 1440 | Orbite simple | temps x1 | 130 | 7.71 | 9.48 | 7.57 | 706 |
| 3440 × 1440 | 8 missiles | sortie du tube | 124 | 8.09 | 13.88 | 7.94 | 1034 |
| 3440 × 1440 | 8 missiles | propulsion | 124 | 8.05 | 10.52 | 7.89 | 773 |
| 3440 × 1440 | 8 missiles | croisière | 133 | 7.50 | 9.53 | 7.37 | 692 |
| 3440 × 1440 | 8 missiles | rentrée | 110 | 9.06 | 33.44 | 8.91 | 725 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 66 | 15.22 | 21.80 | 15.10 | 774 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 46 | 21.60 | 24.65 | 21.45 | 788 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 100 | 9.95 | 35.52 | 9.77 | 783 |
| 3440 × 1440 | 10 × 50 Mt | figées à 5 s | 83 | 12.06 | 13.43 | 11.92 | 734 |
| 3440 × 1440 | 10 × 50 Mt | figées à 1 min | 102 | 9.84 | 10.50 | 9.71 | 713 |
| 3440 × 1440 | 10 × 50 Mt | figées à 10 min | 112 | 8.94 | 10.07 | 8.81 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 30 min | 116 | 8.60 | 10.47 | 8.48 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 6 h | 75 | 13.29 | 14.89 | 13.15 | 711 |
| 5120 × 1440 | Orbite simple | temps x1 | 97 | 10.31 | 11.65 | 10.16 | 680 |
| 5120 × 1440 | 8 missiles | sortie du tube | 94 | 10.67 | 16.41 | 10.50 | 1390 |
| 5120 × 1440 | 8 missiles | propulsion | 96 | 10.45 | 13.22 | 10.25 | 751 |
| 5120 × 1440 | 8 missiles | croisière | 99 | 10.08 | 12.76 | 9.93 | 664 |
| 5120 × 1440 | 8 missiles | rentrée | 83 | 12.01 | 36.74 | 11.83 | 694 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 60 | 16.77 | 18.08 | 16.60 | 736 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 55 | 18.29 | 20.04 | 18.12 | 750 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 88 | 11.42 | 35.08 | 11.21 | 745 |
| 5120 × 1440 | 10 × 50 Mt | figées à 5 s | 58 | 17.37 | 18.84 | 17.22 | 708 |
| 5120 × 1440 | 10 × 50 Mt | figées à 1 min | 84 | 11.94 | 12.78 | 11.78 | 688 |
| 5120 × 1440 | 10 × 50 Mt | figées à 10 min | 85 | 11.73 | 12.87 | 11.57 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 30 min | 93 | 10.75 | 12.32 | 10.58 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 6 h | 62 | 16.24 | 17.47 | 16.07 | 685 |

- 1920 × 1080 : tir de 10 explosions en 14.6 ms, pire image après le tir 11.5 ms.
- 2560 × 1440 : tir de 10 explosions en 14.5 ms, pire image après le tir 12.5 ms.
- 3440 × 1440 : tir de 10 explosions en 14.8 ms, pire image après le tir 11.9 ms.
- 5120 × 1440 : tir de 10 explosions en 14.8 ms, pire image après le tir 11.5 ms.

Part de chaque effet (10 × 50 Mt figées à 1 min, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 11.78 | — |
| Mushroom | 9.79 | 1.99 |
| Shock | 10.67 | 1.12 |
| nuke_cloud_count | 11.76 | 0.03 |
| nuke_ground_count | 11.84 | -0.06 |
| nuke_smoke_count | 11.84 | -0.06 |

Part de chaque effet (10 × 50 Mt figées à 6 h, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 15.92 | — |
| Mushroom | 9.90 | 6.02 |
| Shock | 15.99 | -0.07 |
| nuke_cloud_count | 16.00 | -0.08 |
| nuke_ground_count | 15.97 | -0.05 |
| nuke_smoke_count | 15.90 | 0.01 |
