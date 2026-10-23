# Banc CPU (headless) — 2026-10-23T20:39:10

10 explosions de 1 Mt ; 3 passages par état, 120 images chacun.

| État | ms / image (meilleur passage, moy. tronquée) |
|---|---|
| Orbite seule | 3.191 |
| 10 explosions figées à 5 s | 5.167 |
| 10 explosions figées à 1 min | 5.036 |
| 10 explosions figées à 30 min | 4.097 |
| 10 explosions figées à 6 h | 4.520 |
| Assis au poste de pilotage (explosions à 6 h) | 3.199 |
| Tablette sortie (explosions à 6 h) | 5.737 |

Ventilation — explosions à 6 h (référence médiane 3.160 ms) : économie quand le nœud est désactivé

| Nœud | ms / image |
|---|---|
| WorldEnvironment | 4.146 |
| CommConsole | 1.391 |
| AlertSirens | 0.629 |
| NukeReport | 0.613 |
| PilotConsole | 0.508 |
| Effets/Flash | 0.501 |
| FpsOverlay | 0.454 |
| NukeLauncher/Impact | 0.453 |
| TvConsole | 0.440 |
| HatchInteraction | 0.416 |
| NukeLauncher/FlashFX | 0.312 |
| GroundTarget | 0.310 |
| Effets/Mushroom | 0.300 |
| WakeUp | 0.244 |
| NukeLauncher/CloudFX | 0.184 |
| Sun | 0.175 |
| Photos | 0.171 |
| Effets/Shock | 0.169 |
| AirlockHazard | 0.144 |
| CampaignDirector | 0.132 |
| EarthScene | 0.119 |
| Earth | 0.116 |
| Station | 0.095 |
| PauseMenu | 0.084 |
| NukeLauncher/GroundFX | 0.052 |

Ventilation — explosions à 5 s (référence médiane 4.764 ms) : économie quand le nœud est désactivé

| Nœud | ms / image |
|---|---|
| NukeLauncher/CloudFX | 0.946 |
| NukeLauncher/Impact | 0.932 |
| Effets/Flash | 0.494 |
| Orbit | 0.354 |
| Exposure | 0.294 |
| Effets/Shock | 0.288 |
| Earth | 0.237 |
| Station | 0.236 |
| Effets/Mushroom | 0.194 |
| NukeReport | 0.139 |
| NukeLauncher/GroundFX | 0.093 |
