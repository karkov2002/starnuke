# Banc Star Nuke — 2026-10-16 19:06:23

Godot 4.7.2-stable (steam), NVIDIA GeForce RTX 5080 (d3d12), écran 5120 × 1440. V-Sync coupée, fenêtre sans bordure à la résolution mesurée, rendu 3D à l'échelle 1. Scénarios : orbite simple (temps x1, 4 s) ; 8 missiles tirés d'un coup, mesurés par phase jusqu'à l'impact puis 60 s d'explosions ; 10 explosions de 50 Mt figées à chaque instant (120 images). CPU = temps entre deux images (le jeu attend le GPU).

| Résolution | Scénario | Phase | im/s | CPU moy. (ms) | CPU pire (ms) | GPU moy. (ms) | Appels de dessin |
|---|---|---|---|---|---|---|---|
| 1920 × 1080 | Orbite simple | temps x1 | 247 | 4.05 | 5.23 | 3.93 | 790 |
| 1920 × 1080 | 8 missiles | sortie du tube | 233 | 4.29 | 9.19 | 4.16 | 1326 |
| 1920 × 1080 | 8 missiles | propulsion | 236 | 4.24 | 5.76 | 4.07 | 853 |
| 1920 × 1080 | 8 missiles | croisière | 257 | 3.90 | 4.68 | 3.79 | 781 |
| 1920 × 1080 | 8 missiles | rentrée | 201 | 4.98 | 41.33 | 4.85 | 808 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (0–4 s) | 108 | 9.27 | 14.06 | 9.15 | 854 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (4–20 s) | 104 | 9.58 | 12.11 | 9.46 | 865 |
| 1920 × 1080 | 8 missiles | explosions à l'arrivée (20–60 s) | 187 | 5.34 | 35.09 | 5.19 | 864 |
| 1920 × 1080 | 10 × 50 Mt | figées à 5 s | 127 | 7.90 | 8.43 | 7.79 | 820 |
| 1920 × 1080 | 10 × 50 Mt | figées à 1 min | 183 | 5.46 | 7.17 | 5.31 | 798 |
| 1920 × 1080 | 10 × 50 Mt | figées à 10 min | 185 | 5.39 | 7.09 | 5.29 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 30 min | 197 | 5.08 | 5.87 | 4.97 | 803 |
| 1920 × 1080 | 10 × 50 Mt | figées à 6 h | 68 | 14.69 | 14.82 | 14.59 | 794 |
| 2560 × 1440 | Orbite simple | temps x1 | 153 | 6.53 | 8.21 | 6.41 | 744 |
| 2560 × 1440 | 8 missiles | sortie du tube | 146 | 6.84 | 17.24 | 6.71 | 1156 |
| 2560 × 1440 | 8 missiles | propulsion | 145 | 6.89 | 9.07 | 6.74 | 808 |
| 2560 × 1440 | 8 missiles | croisière | 152 | 6.57 | 8.35 | 6.45 | 733 |
| 2560 × 1440 | 8 missiles | rentrée | 125 | 8.01 | 34.20 | 7.88 | 761 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 62 | 16.02 | 19.13 | 15.93 | 806 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 61 | 16.51 | 20.69 | 16.39 | 817 |
| 2560 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 122 | 8.19 | 35.72 | 8.03 | 816 |
| 2560 × 1440 | 10 × 50 Mt | figées à 5 s | 94 | 10.65 | 13.99 | 10.53 | 772 |
| 2560 × 1440 | 10 × 50 Mt | figées à 1 min | 124 | 8.10 | 9.83 | 7.97 | 750 |
| 2560 × 1440 | 10 × 50 Mt | figées à 10 min | 123 | 8.16 | 9.95 | 8.03 | 757 |
| 2560 × 1440 | 10 × 50 Mt | figées à 30 min | 120 | 8.32 | 9.85 | 8.21 | 757 |
| 2560 × 1440 | 10 × 50 Mt | figées à 6 h | 42 | 23.73 | 26.44 | 23.61 | 749 |
| 3440 × 1440 | Orbite simple | temps x1 | 125 | 7.98 | 10.26 | 7.85 | 706 |
| 3440 × 1440 | 8 missiles | sortie du tube | 118 | 8.49 | 19.95 | 8.34 | 1046 |
| 3440 × 1440 | 8 missiles | propulsion | 118 | 8.49 | 11.23 | 8.33 | 774 |
| 3440 × 1440 | 8 missiles | croisière | 124 | 8.03 | 12.26 | 7.90 | 692 |
| 3440 × 1440 | 8 missiles | rentrée | 104 | 9.66 | 35.37 | 9.52 | 725 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 62 | 16.22 | 22.44 | 16.09 | 774 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 59 | 16.97 | 24.14 | 16.84 | 788 |
| 3440 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 105 | 9.54 | 35.37 | 9.37 | 783 |
| 3440 × 1440 | 10 × 50 Mt | figées à 5 s | 64 | 15.66 | 18.08 | 15.54 | 734 |
| 3440 × 1440 | 10 × 50 Mt | figées à 1 min | 107 | 9.35 | 10.61 | 9.23 | 714 |
| 3440 × 1440 | 10 × 50 Mt | figées à 10 min | 106 | 9.40 | 10.04 | 9.27 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 30 min | 106 | 9.41 | 10.04 | 9.28 | 719 |
| 3440 × 1440 | 10 × 50 Mt | figées à 6 h | 34 | 29.49 | 30.71 | 29.37 | 711 |
| 5120 × 1440 | Orbite simple | temps x1 | 102 | 9.78 | 10.09 | 9.63 | 679 |
| 5120 × 1440 | 8 missiles | sortie du tube | 98 | 10.23 | 15.95 | 10.08 | 1359 |
| 5120 × 1440 | 8 missiles | propulsion | 98 | 10.17 | 11.77 | 9.99 | 750 |
| 5120 × 1440 | 8 missiles | croisière | 103 | 9.72 | 10.32 | 9.57 | 664 |
| 5120 × 1440 | 8 missiles | rentrée | 87 | 11.44 | 36.34 | 11.27 | 694 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (0–4 s) | 61 | 16.31 | 17.34 | 16.16 | 736 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (4–20 s) | 58 | 17.16 | 18.45 | 17.00 | 750 |
| 5120 × 1440 | 8 missiles | explosions à l'arrivée (20–60 s) | 88 | 11.33 | 35.35 | 11.13 | 745 |
| 5120 × 1440 | 10 × 50 Mt | figées à 5 s | 75 | 13.35 | 13.73 | 13.20 | 708 |
| 5120 × 1440 | 10 × 50 Mt | figées à 1 min | 92 | 10.91 | 11.18 | 10.77 | 688 |
| 5120 × 1440 | 10 × 50 Mt | figées à 10 min | 90 | 11.08 | 11.83 | 10.92 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 30 min | 90 | 11.11 | 11.38 | 10.96 | 693 |
| 5120 × 1440 | 10 × 50 Mt | figées à 6 h | 29 | 34.95 | 35.23 | 34.79 | 685 |

- 1920 × 1080 : tir de 10 explosions en 14.9 ms, pire image après le tir 18.1 ms.
- 2560 × 1440 : tir de 10 explosions en 14.7 ms, pire image après le tir 12.5 ms.
- 3440 × 1440 : tir de 10 explosions en 14.7 ms, pire image après le tir 11.6 ms.
- 5120 × 1440 : tir de 10 explosions en 14.5 ms, pire image après le tir 11.1 ms.

Part de chaque effet (10 × 50 Mt figées à 60 s, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 10.97 | — |
| Mushroom | 9.98 | 0.99 |
| Shock | 10.69 | 0.28 |
| nuke_cloud_count | 10.89 | 0.08 |
| nuke_ground_count | 10.96 | 0.00 |
| nuke_smoke_count | 10.92 | 0.05 |

---

Complément (même séance, `--only-breakdown`, la fenêtre encore à 5120 × 1440) : part de chaque effet à 1 min et à 6 h.

Part de chaque effet (10 × 50 Mt figées à 1 min, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 10.98 | — |
| Mushroom | 9.96 | 1.02 |
| Shock | 10.50 | 0.48 |
| nuke_cloud_count | 10.89 | 0.09 |
| nuke_ground_count | 11.00 | -0.02 |
| nuke_smoke_count | 10.96 | 0.02 |

Part de chaque effet (10 × 50 Mt figées à 6 h, 5120 × 1440) : temps GPU sans cet effet.

| Effet coupé | GPU moy. (ms) | Gain (ms) |
|---|---|---|
| aucun | 35.74 | — |
| Mushroom | 10.03 | 25.71 |
| Shock | 36.13 | -0.39 |
| nuke_cloud_count | 36.25 | -0.51 |
| nuke_ground_count | 36.32 | -0.58 |
| nuke_smoke_count | 36.15 | -0.41 |
