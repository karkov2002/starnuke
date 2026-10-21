# starnuke

POC Godot 4.7 : vue depuis une station spatiale en orbite basse (~400 km), depuis la Cupola de l'ISS.
Jeu « d'ambiance » : la priorité est une vue de la Terre la plus réaliste possible.

## Lancer

Ouvrir le projet dans Godot 4.7 puis F5 (scène principale : l'écran de démarrage `res://scenes/ui/main_menu.tscn` ;
la vue orbitale `res://scenes/orbit_view.tscn` se lance aussi seule, F6).
Les tuiles haute résolution (`assets/earth_tiles/`, `assets/earth_night_tiles/`) doivent avoir été générées (voir plus bas).

## Version distribuable (Windows)

`powershell -ExecutionPolicy Bypass -File tools/package_game.ps1` (modèles d'export Godot 4.7.2 installés ; l'éditeur
peut rester ouvert) construit `../exe/starnuke/` et `../exe/StarNuke.zip` (~1 Go) :
- export « release » du preset « Windows Desktop » (`export_presets.cfg`) : `Star Nuke.exe` et `Star Nuke.pck`
  (~450 Mo : toutes les ressources, plus `assets/population_2030.bin`, fichier brut ajouté par `include_filter` ;
  `tools/` et le cache du MCP, `addons/godot_mcp/cache/`, ~500 Mo de captures, exclus par `exclude_filter`) ;
- tuiles HD (`assets/earth_tiles`, `earth_night_tiles`, `earth_cloud_tiles`, 3 × 2 592 fichiers) copiées dans
  `assets/` à côté de l'exécutable : leurs dossiers ont un `.gdignore` et ne peuvent pas entrer dans le `.pck`, mais
  un fichier `res://` absent du `.pck` est cherché dans le dossier de l'exécutable, où le jeu les trouve ;
- dossiers `playlist/` (musiques) et `campaign/` (campagnes) copiés à côté de l'exécutable : jamais dans le `.pck`, le
  joueur y ajoute ses playlists et ses campagnes (voir « Écran de démarrage, paramètres et langues ») ;
- archive zip du dossier (tar de Windows).

Pour jouer : dézipper, lancer `Star Nuke.exe` (Windows 10/11 64 bits, carte graphique Direct3D 12). Vérifié : jeu
exporté sur un écran 5120 × 1440 (fenêtre maximisée, tuiles HD, bilan des pertes). Le module MCP (`MCPRuntime`) reste
dans l'export : il ne fait rien sans serveur MCP sur la machine, mais en présence de celui-ci (développement) il
permet de piloter le jeu exporté.

## Écran de démarrage, paramètres et langues

- **Modes de jeu** (règle de jeu ; `scripts/ui/main_menu.gd`, pages du menu, Échap : page précédente ;
  `scripts/campaigns.gd`, classe `Campaigns`, qui retient le mode le temps de la session) : **Start Game** ouvre la
  page des modes : **Start a new campaign** (choix de la campagne : il peut y en avoir des dizaines, d'où un
  **sélecteur déroulant** — bouton qui affiche la campagne choisie et ouvre une liste à défilement, 8 lignes
  visibles — avec **la campagne officielle toujours en premier, en bleu**, les autres en blanc, la description en
  infobulle ; puis **Launch campaign** et **Back**), **Continue current campaign** (cliquable
  seulement s'il y a une sauvegarde, `Campaigns.has_saved` : voir « Sauvegarde au coucher »),
  **Free mode** (le jeu tel quel : `orbit_view.tscn`) et **Back**. Le **mode campagne** sera le cœur du jeu
  (`Campaigns.mode`, `current_id`, `current` : `CampaignData` vérifié, `day_index` retenus) : au lancement, le nœud
  `CampaignDirector` (`scripts/campaign_director.gd`) applique le **départ de la journée** (heure UTC et position
  exacte de la station, `OrbitSimulation.place` ; la manœuvre en préparation est annulée). Une campagne avec des
  erreurs est proposée **grisée**, avec leur nombre en infobulle, et ne se lance pas.
- **Déroulement d'une journée** (règles de jeu, `CampaignDirector`) :
  - **Heure du briefing** (règle de jeu) : une mission n'arrive pas au réveil. Son briefing est envoyé par le sol à
	l'heure de la mission — `briefing_utc` (« HH:MM » UTC, dans l'entrée de la journée ; aussitôt si l'heure est
	déjà passée quand la mission devient disponible), sinon `briefing_delay_minutes` (`defaults`, **30 min** par
	défaut) après le réveil ou la fin de la mission précédente (`CampaignData.briefing_unix`). Avant, aucune
	mission n'est en cours : promenade libre. Comme tout message radio, **il n'arrive qu'avec la liaison** (station
	au sol en vue, bon canal) : au-dessus d'un océan, il attend.
  - **Briefing** par la radio (écran de communication ; expéditeur et canal de la mission, sinon `defaults`) :
	« Mission : titre / Objectif : … / texte / Cible(s) : Photo ou Frappe et coordonnées / Durée avant échec :
	6 h 00 min (chronomètre en marche) » (toujours avec les minutes : « 5 h 30 min ») (clés `BRIEFING_*`). **Les
	délais sont en heures et minutes** (règle de jeu : plus précis et plus stressants que des jours). **À sa
	réception, le chrono de la mission part** (pas avant), **le temps revient à ×1** et l'**appel prioritaire**
    retentit.
  - **Appel prioritaire** (règle de jeu, `scripts/priority_call.gd`, `PriorityCall`, créé par `CampaignDirector`) :
    **un appel passe la station en alerte jaune simple** (`Station.set_alert` : luminaires jaunes et **sirène
	jaune**, voir « Sirènes d'alerte » ; pas de sonnerie propre) **jusqu'à la lecture du briefing**, puis retour au
    normal (sauf si le niveau a changé entre-temps) ; une alerte déjà en cours (jaune, orange, rouge, plus de
	lumière) est gardée. **La tablette est le récepteur de l'appel, comme un téléphone** : elle passe sur son onglet
	**Alertes** (appel en cours, bandeau clignotant « TRANSMISSION PRIORITAIRE — poste COMM, module Commande »,
	`PRIORITY_CALL_BANNER`, jusqu'à la lecture ; voir « Tablette ») ; plus rien ne s'affiche par-dessus la vue. Le
	briefing se lit au poste COMM. Une mission terminée sans que son briefing ait été lu arrête l'appel.
  - **Sirènes d'alerte** (règle de jeu, `scripts/alert_sirens.gd`, nœud `AlertSirens` de `orbit_view.tscn`, mode
	libre compris) : tant que la station est en alerte **jaune, orange ou rouge** (tablette, panneau de debug, sas),
	le son de ce niveau passe **en boucle par l'interphone, audible dans toute la station** (bus SFX, sans
    position) : **jaune** (précaution), carillon doux de deux notes descendantes 660 puis 523 Hz toutes les 4 s ;
    **orange** (avertissement), trois bips secs à 740 Hz toutes les 2,4 s ; **rouge** (urgence), sirène montante
    de 550 à 1 450 Hz, continue. Normal et « Tout éteindre » (courant coupé) : silence. Volume croissant avec
	l'urgence (−12, −9, −8 dB, `AlertSirens.VOLUMES_DB`) ; abonné au signal `Station.alert_changed`. Sons
	**provisoires** : `assets/audio/alarms/`
	`alert_yellow.ogg`, `alert_orange.ogg`, `alert_red.ogg`, synthétisés par `tools/build_alarm_sounds.ps1`
	(ffmpeg, formules d'onde). **Pour les remplacer**, déposer à leur place des fichiers **Ogg Vorbis de même
	nom** : l'éditeur les réimporte, et le fichier entier est joué en boucle (`loop` réglé par le code ; durée
	libre, prévoir un raccord propre entre la fin et le début). Le script n'écrase jamais un son présent, sauf avec
    `-Force`.
  - **Objectifs** : une **photo** satellite (point sous la station à la prise de vue) ou un **impact** de missile à
	moins de la tolérance d'une cible remplit l'objectif correspondant (le premier encore ouvert de ce type, dont
	l'objectif préalable `after` est rempli) ; plus loin, il ne compte pas.
  - **Note sur 20** (`scripts/mission_scoring.gd`) : précision d'un objectif = 20 jusqu'à tolérance / 4, puis
	décroissance linéaire jusqu'à 0 à la tolérance (non rempli : 0) ; précision de la mission = moyenne pondérée
	(`weight`) ; **facteur temps** = 1 jusqu'au temps de référence, puis décroissance linéaire jusqu'à
	`time_floor` (0,6) à l'échéance ; note = précision × facteur temps ; **réussite si note ≥ 10**
	(`success_score`).
  - **Temps de référence** (règle de jeu) : `par_hours` s'il est donné, sinon **calculé à l'arrivée du briefing**
	d'après l'orbite réelle (`scripts/mission_planner.gd`, `MissionPlanner`) : **passage le plus tôt possible**
	pour remplir tous les objectifs, compté depuis la réception du briefing, **plus une orbite** (~1 h 32 à 400 km), au
	plus l'échéance (mission impossible à temps : pas de pénalité de temps). Passage possible : **photo**, le point
    sous la station passe à la verticale de la cible ; **tir**, la cible est vue à **au moins 20° au-dessus de
	l'horizon** (`MIN_ELEVATION_DEG`, ~870 km autour du point survolé à 400 km). **Manœuvres comprises** : orbite
	actuelle ou changement de plan en une poussée, n'importe où sur l'orbite, dans les limites du poste de pilotage
	(inclinaison ≤ 80°, décalage du nœud ≤ ±20°, altitude inchangée), précession J2 comprise ; objectifs dans
	l'ordre de `after`, sinon le plus tôt possible d'abord, chacun depuis l'orbite laissée par le précédent.
    Recherche par pas (point de poussée tous les 5 min, passage tous les 2 min affiné par dichotomie) : quelques
    millisecondes à moins de 0,1 s.
  - **Fin de mission** : tous les objectifs remplis, ou échéance (`deadline_hours` heures après la réception du briefing) ;
    résultat retenu (`Campaigns.results` : note, réussite, précision, facteur temps, journée ; **moyenne globale**
    `Campaigns.global_score()`, toutes missions jouées, échecs compris) et message de résultat (message `result` de
    la mission choisi selon la note, sinon « Objectif atteint » / « Objectif non atteint », avec la note, RÉUSSITE
    ou ÉCHEC, la précision et le facteur temps), puis la mission suivante de la journée dont la condition est vraie
    est programmée (son briefing à son heure).
  - **Fin de journée** (plus de mission) : note de la journée retenue (`Campaigns.day_scores`), message `debrief` ;
    à la dernière journée, message de fin de campagne (`ending`, selon la moyenne globale).
  - **Nuit** : la journée terminée, promenade libre ; **la couchette devient cliquable** (bulle « Dormir »,
    `HatchInteraction`, `CampaignDirector.can_sleep` ; avant, elle ne réagit pas). Dormir : fondu au noir (1,5 s),
	puis **réveil dans la couchette** au départ de la journée suivante — son `start` s'il est défini : avec `orbit`,
	heure et position exactes ; **sans `orbit`, saut dans le temps** jusqu'à sa date et son heure (plusieurs jours
    peuvent séparer deux journées), la station ayant continué son orbite (ignoré si la date est déjà passée) ; sans
	`start`, **la station a continué son orbite** jusqu'à l'heure de réveil (`wake_up_utc`, le lendemain si elle
    est passée ; sans heure, 8 h de sommeil) —, puis la première mission est programmée. Après la dernière
	journée, dormir termine la campagne : la sauvegarde est effacée et l'**écran de fin de campagne** s'affiche
	(voir ci-dessous). Pendant la nuit et les sauts dans le temps, les explosions vieillissent d'autant (horloge
	`NukeClock` avancée : incendies, fumées).
  - **Journal de partie** (`scripts/campaign_journal.gd`, `CampaignJournal`) : un fichier **JSON Lines** par partie
	lancée (nouvelle campagne ou « Continuer »), `user://logs/<campagne>_<date et heure réelles>.jsonl`
	(`%APPDATA%/Godot/app_userdata/Star Nuke/logs/`), écrit et vidé sur le disque ligne par ligne. Chaque ligne :
	`event`, heure réelle (`real`), heure du jeu (`utc`, `unix`) et les champs de l'événement — `session`
    (campagne, journée, reprise ou non), `day_start`, `mission_scheduled` (heure prévue du briefing),
    `briefing_sent` (envoi par le sol), `mission_start` (réception : échéance, temps de référence, **passage le plus
    tôt possible** `earliest_s`, −1 si impossible, altitude, inclinaison, vitesse du temps avant le retour à ×1),
    `briefing_read` (délai de lecture), `burn` (qualité de la poussée, dosage, Auto ou Manuel), `shot` (photo ou
    tir : point, distance à la cible la plus proche de ce type, objectif rempli ou −1, précision, temps depuis le
    départ du chrono), `mission_end` (note et son détail, temps écoulé, mission complète ou non), `day_end`,
	`sleep`, `campaign_end`. Il sert à régler les profils du banc d'équilibrage d'après de vraies parties.
  - **Fin de campagne** (`scenes/ui/campaign_end_screen.tscn`, `scripts/ui/campaign_end_screen.gd`), sur fond noir
    en fondu : « Campagne terminée », nom de la campagne, **message de fin** (`ending`, le même que celui de la
	radio : choisi d'après les notes de la dernière journée), **moyenne globale** sur 20 avec RÉUSSITE / ÉCHEC
	(`success_score`), puis le **détail à défilement** : pour chaque journée, « Jour n » et sa note, et chaque
	mission jouée (titre, note, verdict ; vert si réussie, rouge sinon), dans l'ordre de la campagne (« — » et
    « Aucune mission jouée » pour une journée sans mission). « Retour au menu » vide les notes
	(`Campaigns.start_free`) et ramène à l'écran de démarrage.
  - **Sauvegarde au coucher** (règle de jeu ; `Campaigns.save`, `user://saves/campaign.json`, un seul emplacement :
	la campagne en cours) : campagne, **journée à venir**, notes (missions, journées, **moyenne globale**
	`global_score`) et monde au réveil — orbite (heure UTC, altitude, inclinaison, point survolé, sens de passage),
	**explosions** (point, puissance, âge sur l'horloge des explosions, heure UTC), photos (fichiers de
	`user://photos/` et leurs vignettes `user://photos/thumbs/`), cibles. La radio n'est pas gardée (la journée
	commence par son briefing). **« Continuer la campagne en cours »** (cliquable s'il y a une sauvegarde valide,
    `Campaigns.continue_saved`) relance la partie au réveil de la journée sauvegardée : orbite replacée, explosions
    **recréées à leur âge** (`NukeLauncher.restore_at` : incendies, traces au sol, black-out où ils en étaient ;
    marquées `restored` : elles ne remplissent aucun objectif et la télévision garde leur heure réelle pour
	l'édition spéciale), galerie et cibles rétablies.
  - **Réveil** (règle de jeu, `scripts/wake_up.gd`, nœud `WakeUp`) : **au lancement de toute partie (mode libre
	compris)** et au début de chaque journée de campagne : noir, titre « Jour n » (campagne seulement) et, dessous,
	**date, heure UTC et point survolé** de la journée (« 18 juillet 2035 — 11 h 15 UTC — 46.84° N  21.85° O »,
	`CampaignDirector.day_heading`, clés `WAKE_HEADING` et `MONTH_1` à `MONTH_12`), puis **ouverture des
	paupières**, comme la séquence de mort à l'envers (`shaders/eyelids.gdshader`) : elles s'entrouvrent, clignent
	une fois puis s'ouvrent tout à fait (~1,7 s, `WakeUp.WAKE_STEPS` ; titre 1,8 s, 3,2 s avec la date) ; la
	vue, d'abord floue et sombre sur les bords, devient nette. Pendant le sommeil et le réveil, les clics sont
	bloqués ; le voile est retiré ensuite (il gardait sinon le clic droit qui tourne la tête). Ni au décor de
	l'écran de démarrage ni aux bancs de mesure (la scène du jeu n'y est pas la scène courante).
- **Campagnes** : dossier `campaign/` à côté de `playlist/`, un sous-dossier par campagne (son nom est l'identifiant
  de la campagne) avec un fichier `campaign.json`. Comme les playlists, le dossier est lu sur le disque (`.gdignore`,
  jamais dans le `.pck`) : `campaign/` du projet dans l'éditeur, à côté de l'exécutable dans le jeu exporté (copié
  par `tools/package_game.ps1`), où **les joueurs ajoutent leurs propres campagnes** ; la liste est relue à chaque
  ouverture de la page. Campagne officielle : **`starnuke`** (proposée en premier, les autres par ordre
  alphabétique ; seule versionnée, `.gitignore`). Un dossier sans `campaign.json` lisible n'est pas proposé.
- **Format de `campaign.json`** (format 2, lu et vérifié par `CampaignData`, `scripts/campaign_data.gd`, où il est
  décrit en entier) :
  - **Textes** (`name`, `description`, titres, messages…) : clé des fichiers de langue (la campagne officielle n'utilise
    que des clés, `CAMPAIGN_STARNUKE_*`), texte, ou dictionnaire par langue `{"en": …, "fr": …}` (langue du jeu,
	sinon l'anglais).
  - **`start`** : départ de la campagne — `utc` (« 2035-07-15T06:00:00Z ») et `orbit` (`altitude_km` 200 à 800,
	`inclination_deg` 0 à 80, `over` {`lat`, `lon`} : point survolé à cet instant, `|lat|` ≤ inclinaison,
	`ascending` : sens de passage). **Chaque journée peut avoir son propre `start`** : avec `orbit`, heure et
	position exactes de la station au début de la journée ; **`utc` seul : saut dans le temps** jusqu'à cette date
    (ex. `"start": {"utc": "2035-07-18T11:15:00Z"}` : trois jours plus tard), la station continuant son orbite.
    Sans `start`, la première journée prend celui de la campagne et les suivantes reprennent là où la précédente
	s'est arrêtée (`wake_up_utc`, sinon 8 h de sommeil). `start` et `wake_up_utc` s'excluent.
  - **`defaults`** : expéditeur des messages (`from`), canal radio (`channel`), note de réussite (`success_score`,
	10), tolérances par type d'objectif (`tolerance_km` : photo 40 km, tir 15 km), plancher du facteur temps
	(`time_floor`, 0,6), délai d'un briefing sans heure (`briefing_delay_minutes`, 30).
  - **`days`** : journées, dans l'ordre — `id`, `start` (facultatif), `wake_up_utc` (« HH:MM »), `missions` (liste
	de `{mission, when, briefing_utc}` : `briefing_utc` « HH:MM » UTC, heure d'arrivée du briefing, facultative ;
    une entrée dont la condition est fausse est sautée, ce qui permet de choisir la mission
    selon les notes), `debrief` (messages de fin de journée).
  - **`missions`** (dictionnaire par identifiant) : `title`, `objective`, `description`, `deadline_hours` et `deadline_minutes` (facultatif, 0 à 59) (durée avant
    échec, en heures : règle de jeu), `par_hours` (temps de référence, `null` : calculé), `objectives` (`type` « photo » ou « strike »,
    `target` {`lat`, `lon`}, `tolerance_km`, `weight`, `yield_kt` pour un tir, `after` : objectif à remplir avant),
    `result` (messages selon la note).
  - **`ending`** : messages de fin de campagne.
  - **Messages** : `{when, subject, body}` ; le premier dont la condition est vraie est retenu. **Conditions**
    (`when`) : `global_score`, `day_score`, `mission_score` ou `score_of` {`id`} avec `min` (inclus) et/ou `max`
    (exclu), notes sur 20 ; une note encore inconnue rend la condition fausse.
  - **Vérification** : `godot --headless --path . -s tools/check_campaign.gd [-- <campagne>]` liste les erreurs de
	chaque campagne (chemin dans le fichier et explication, en français ; code de sortie 1 s'il y en a). Pour une
	campagne valide, il donne aussi, journée par journée, l'heure du briefing, le **passage le plus tôt
	possible**, le **temps de référence** et l'échéance de chaque mission (missions enchaînées comme si chacune
	était remplie au plus tôt, conditions `when` ignorées, briefing reçu à son heure sans attendre la liaison,
	coucher dès la fin de la journée) et signale par « ⚠ » une mission **impossible
	dans son délai** (avertissement, pas une erreur).
  - **Banc d'équilibrage** : `godot --headless --path . -s tools/balance_campaign.gd [-- <campagne> [tirages]
	[graine]]` (campagne officielle, 1 000 tirages, graine 1 par défaut ; moins d'une seconde) simule chaque
	mission en **Monte-Carlo** pour **trois profils de joueur** et compare la note moyenne à leur cible :
	**expert ≥ 17, moyen 12 à 15, débutant 8 à 11** (« ⚠ » hors cible, par mission et pour la campagne). Modèle :
	déroulement au plus tôt (`MissionPlanner.timeline`, comme `check_campaign.gd`), retard tiré au hasard après le
	passage le plus tôt possible (expert 0 à 0,3 orbite, moyen 0,3 à 1,2, débutant 1 à 2,5), passage manqué
	(5 %, 20 %, 35 %), écart au sol demi-normal (écart type photo 5, 12, 20 km ; tir 3, 6, 10 km) ; chaque
	passage manqué ou raté (écart ≥ tolérance) coûte une orbite ; au-delà de l'échéance, les objectifs restants
    valent 0. Ces profils sont des **estimations à recaler** avec les journaux de vraies parties. Rapport Markdown
    dans `tools/bench/results/balance_<campagne>_<date>.md` (part de réussites, note moyenne ± écart type). Il
    sert à régler les missions (échéance, tolérance, `par_hours`) pour que chaque profil tombe dans sa cible.
	La campagne officielle contient pour l'instant deux journées d'essai : photo de Kourou (briefing à 06 h 30),
    puis, trois jours plus tard (saut au 18 juillet 2035, 11 h 15 UTC), photo de Toulouse (briefing 30 min après le
    réveil).

- **Écran de démarrage** (`scenes/ui/main_menu.tscn`, script `scripts/ui/main_menu.gd`, construit en code) : titre
  provisoire « Star Nuke » lumineux (`scripts/ui/title_glow.gd`, `shaders/title_glow.gdshader` : texte rendu en
  blanc dans un SubViewport (une seule fois, `UPDATE_ONCE`, le texte ne changeant qu'avec la langue) puis teinté par
  le shader, avec un halo flou ; sa couleur suit celle d'un corps noir chauffé, allant
  et venant en 18 s de ~700 K, presque noir, au rouge, à l'orange, au jaune puis au blanc ~6 600 K, approximation
  de Tanner Helland ; la luminosité monte vite avec la température pour que le rouge rougeoie ; le halo garde une
  lueur minimale de braise, `halo_floor` : au plus froid, les lettres sombres restent lisibles) et boutons **Start Game** (page des modes de
  jeu, voir ci-dessous), **Settings** (écran des paramètres, par-dessus), **Credits** (voir ci-dessous) et **Quit**
  dans la moitié droite ; à gauche, **la station vue de l'extérieur, côté
  soleil et légèrement en plongée, au-dessus de la Terre qui défile** (en temps réel). Ce décor est la scène du jeu elle-même, chargée
  en tâche de fond dès l'ouverture du menu (`ResourceLoader.load_threaded_request`, ~0,9 s) puis affichée en fondu
  (2 s), sans son interface ni le tir (`Hud`, `NukeReport`, `PilotConsole`, tablette,
  `NukeLauncher` retirés), observateur désactivé, caméra extérieure (`BACKDROP_CAMERA_*` ; décalage horizontal
  pour placer station et Terre à gauche). **Écran de chargement dès le démarrage** : jusqu'à ce que le décor soit
  en place, fond noir et « Loading in progress… » (clé `MENU_LOADING`, points animés et pourcentage), puis les
  boutons apparaissent en fondu (0,5 s). Le même chargement sert à **Start Game** : le message de chargement
  revient pendant la mise en place de la partie. Mesure hors éditeur (18/10/2026) : fenêtre à 0,5 s, menu à
  1,5 s ; la mise en place du décor (70 ms) figeait l'écran 4,7 s tant que les collisions des objets interactifs
  étaient calculées au démarrage (elles le sont maintenant à l'import, voir « Post-import »).
- **Écran des paramètres** (`scenes/ui/settings_menu.tscn`, script `scripts/ui/settings_menu.gd`) : onglets
  **Video**, **Audio**, **Controls**, **Game**. **Back** ou Échap pour revenir. Chaque choix est appliqué et sauvé aussitôt.
  - **Controls** : aide (la réaffectation des touches viendra plus tard) : une ligne par action (avancer / reculer,
	déplacement latéral, roulis, orienter la vue, utiliser, quitter le poste ou la télévision, tablette, lampe torche,
	pause) avec ses touches dessinées comme des touches de clavier. Les touches étant physiques, leur lettre est celle
	du **clavier du joueur** (`DisplayServer.keyboard_get_keycode_from_physical` : Z / S en AZERTY, W / S en QWERTY) ;
	flèches en symboles, Échap et Tab traduits (`CONTROLS_HELP`, `KEY_NAMES` de `settings_menu.gd`).
  - **Video** : mode d'affichage (**fenêtré** / **plein écran**), **résolution** et **luminosité** (25 à 150 %,
	`GameSettings.brightness`, sauvée dans `user://settings.cfg` : facteur du multiplicateur d'exposition des
	attributs de caméra partagés `materials/camera_attributes.tres`, appliqué au menu et au jeu par le nœud
	`Exposure`, voir « Exposition » dans « Organisation de la scène ») et **éclairage intérieur** (10 à 150 %, **40 % par défaut**,
	`GameSettings.interior_light`, sauvé de même : comme un potentiomètre sur les luminaires de la station,
	`Station` multiplie par ce facteur l'énergie de chaque lampe `Lum_*` **et** l'émission propre des luminaires
	(matériaux `Int_Lumiere*`, donc aussi leur halo de glow) ; c'est la valeur de jour : dans l'ombre de la Terre, les
	luminaires passent en **mode nuit** à 75 % de ce réglage (`Station.night_light_ratio`, fondu avec
	l'ensoleillement `Orbit.get_sunlight_fraction`, pénombre comprise : 40 % de jour → 30 % de nuit) ; l'exposition
	de l'intérieur étant constante, c'est ce réglage qui règle la clarté des parois et l'éblouissement des lampes). L'écran des paramètres a un fond
	translucide : on juge le réglage sur la vue 3D derrière.
	- Fenêtré : la résolution est la taille de la fenêtre, centrée dans la zone utile de l'écran ; une fenêtre qui
	  n'y tient pas avec sa bordure et sa barre de titre (résolution native, par exemple) est maximisée.
	- **Jeu lancé depuis l'éditeur** : par défaut, Godot 4.7 l'intègre dans l'onglet « Jeu » (lancé avec `--wid` et
	  `--resolution 1920x1080`) et impose la fenêtre. Les changements d'affichage y sont seulement sauvés
	  (`GameSettings.can_change_display`, `Engine.is_embedded_in_editor`), avec un avertissement dans l'onglet Vidéo.
	  Pour les tester : désactiver l'intégration du jeu (menu d'options de l'onglet Jeu) ou lancer le jeu hors de
	  l'éditeur (`godot --path <projet>`, ou version exportée). Vérifié hors éditeur sur un écran 5120 × 1440 :
      plein écran 5120 × 1440 ; fenêtré 1280 × 720 centré ; fenêtré natif maximisé.
	- Plein écran : la fenêtre couvre tout l'écran à sa résolution native (Godot ne change pas le mode vidéo de
	  l'écran ; plein écran sans bordure, `WINDOW_MODE_FULLSCREEN`). La résolution choisie règle celle du **rendu
	  3D** (`Viewport.scaling_3d_scale` = hauteur choisie / hauteur de l'écran, au moins 0,25) ; l'interface reste
      nette à la résolution native. Utile pour gagner des images par seconde sur un très grand écran.
    - Résolutions proposées : formats courants 16:9 (1280 × 720 à 7680 × 4320), 16:10 (1280 × 800 à
      3840 × 2400), 21:9 (2560 × 1080, 3440 × 1440, 3840 × 1600, 5120 × 2160) et 32:9 (3840 × 1080, 5120 × 1440,
	  7680 × 2160), jusqu'à la taille de l'écran, plus celle de l'écran (« native »). Le jeu n'a pas de limite
	  propre (Godot rend jusqu'à 16384 px de côté) ; la limite pratique est le GPU (le jeu est limité par le GPU :
	  5120 × 1440 = 7,4 Mpx, 3,6 fois 1920 × 1080).
	- **Écrans ultra-larges** (21:9, 32:9) : étirement `canvas_items` / `expand` du projet (base 1920 × 1080). La vue
	  3D garde son champ de vision vertical et s'élargit (`Camera3D.keep_aspect` = hauteur) ; l'interface garde sa
	  taille et s'étend sur toute la largeur (panneau en bas au centre, bilan en haut à droite).
  - **Audio** : **volume de la musique** et **volume des effets sonores** (0 à 100 %, `GameSettings.music_volume`,
    100 % par défaut, et `sfx_volume`, 80 % par défaut ; réglables ensuite par le joueur), volumes des bus « Music » et « SFX » (`default_bus_layout.tres`, muet à
    0 %) ; à côté de chaque curseur, un bouton bascule à **icône de haut-parleur** (barré en rouge quand le son est
    coupé, infobulle « Muet » ; `music_muted`, `sfx_muted`, sauvés) coupe totalement
    le bus et désactive (grise) le curseur, le volume réglé étant gardé pour la remise en route ; **playlist** : menu
    déroulant des playlists disponibles (`GameSettings.playlist`, « starnuke » par défaut).
	Une playlist est un sous-dossier de `playlist/` (son nom est celui du dossier) ; l'autoload `Music`
	(`scripts/music_player.gd`) joue tous ses morceaux (.mp3, .ogg, .wav, ordre alphabétique) puis recommence, dès le
	début de la partie (scène `orbit_view.tscn`, pause comprise) ; il s'arrête à l'écran de démarrage. Changer de
	playlist en cours de partie lance aussitôt la nouvelle. Playlist « starnuke » : « Deep Space Hiss » 1 et 2.
	**Le dossier `playlist/` est lu sur le disque, jamais importé ni mis dans le `.pck`** (`.gdignore`) : dans le
	jeu exporté, c'est `playlist/` **à côté de l'exécutable** (copié par `tools/package_game.ps1`), où le joueur
	ajoute ses propres playlists (un dossier, ses fichiers MP3 / OGG / WAV tels quels, `AudioStreamMP3.load_from_file`
	et équivalents) ; dans l'éditeur, `playlist/` du projet. La liste est relue à chaque ouverture des paramètres
    (pas besoin de relancer le jeu) ; un fichier illisible est sauté.
  - **Game** : **langue** (English, Français, Español, Deutsch, Italiano ; anglais par défaut), appliquée en direct.
- **Sauvegarde** (autoload `GameSettings`, `scripts/game_settings.gd`) : `user://settings.cfg` (sous Windows
  `%APPDATA%/Godot/app_userdata/Star Nuke/settings.cfg`), réappliqué au lancement suivant. Sections `[video]`
  (`window_mode` = `"fullscreen"` / `"windowed"`, `resolution`, `Vector2i(0, 0)` = native) et `[game]`
  (`locale`). Premier lancement : plein écran, résolution native, anglais.
- **Langues** (règle du projet : **tous les textes du jeu sont dans des fichiers de langue**) : tableaux CSV importés
  par Godot (`TranslationServer`), une colonne par langue (`en`, `fr`, `es`, `de`, `it`), déclarés dans
  `project.godot` (`internationalization/locale/translations`) :
  - `locale/strings.csv` : textes de l'interface (clés `MENU_*`, `SETTINGS_*`, `TAB_*`, `VIDEO_*`, `GAME_*`,
	`HUD_*`, `REPORT_*`, `DIR_*` pour les points cardinaux) ;
  - `locale/countries.csv` : noms des pays (`COUNTRY_<ADM0_A3>`, code de `CountryMask`) et des États souverains
	(`SOVEREIGN_<SOV_A3>`), générés par `tools/build_country_names.gd` à partir de Natural Earth (champs NAME_EN,
	NAME_FR, NAME_ES, NAME_DE, NAME_IT ; 258 pays, 209 États).

  Dans le code, un texte fixe est la clé elle-même (`label.text = "MENU_START"` : traduction automatique des
  contrôles) ; un texte composé passe par `tr()` et des champs nommés (`tr("HUD_ALTITUDE").format({"altitude": …})`,
  pour que chaque langue place les valeurs où elle veut), sur un contrôle dont la traduction automatique est coupée
  (`auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED`). Formats des nombres selon la langue
  (`NukeReportText.number_style` : « 1,230,000 » en anglais, « 1 230 000 » en français, « 1.230.000 » en
  espagnol, allemand, italien). Ajouter un texte : une ligne dans le CSV (les 5 langues), réimport automatique par
  l'éditeur ; les fichiers `.translation` produits par l'import ne sont pas versionnés (`.gitignore`). Ajouter une
  langue : une colonne dans les deux CSV, son code dans `GameSettings.LOCALES` et son nom dans
  `GameSettings.LOCALE_NAMES`.
  - Restent en français (outils de développement, hors interface du jeu) : la console (bilan détaillé des tirs,
	`NukeReportText`) et le panneau de debug des explosions (`nuke/debug/`).

## Contrôles

| Action | Contrôle |
|---|---|
| Orienter la vue | Maintenir le **clic droit** et déplacer la souris (lacet et tangage autour des axes de la tête) ; **A / E** (AZERTY, Q / E en QWERTY) : **roulis** gauche / droite autour de l'axe du regard (60°/s, mise en rotation et arrêt progressifs). Orientation libre comme en apesanteur : pas de « haut » imposé, tangage non limité |
| Se déplacer dans la station | **Z / S** (W / S en QWERTY) ou **flèches haut / bas** : avancer / reculer dans la direction du regard (y compris vers le haut ou le bas, apesanteur) ; **Q / D** (A / D en QWERTY) ou **flèches gauche / droite** : déplacement latéral. 1,5 m/s ; inertie d'apesanteur : démarrage et arrêt en douceur (~1 s), on continue sur sa lancée un instant après avoir relâché la touche ; collisions avec les parois, les vitres et les objets intérieurs (tubes des silos…) |
| Curseur | Libre le reste du temps (clic gauche sur la tablette, la barre du temps, l'écran du poste de pilotage) |
| Tablette | **Tab** (action `tablet`, touche physique) : sort ou range la **tablette** tenue en bas de la vue (elle glisse depuis le bas en 0,35 s) ; on clique directement sur son écran. Quatre onglets : **Pilotage** (carte, **BURN** bleu), **Photographie** (vue au nadir en direct, bouton Photo : photo satellite enregistrée dans `user://photos/`, galerie), **Tir de missile** (silos, puissance, bouton rouge), **Alertes** (appel prioritaire reçu, 5 boutons du niveau d'alerte de la station) ; bouton **HUD : On / Off** (surimpression dans la cupola). Ignorée pendant la saisie d'un texte et au poste de pilotage (elle s'y range). Voir « Tablette » |
| Vitesse du temps | **Barre toujours visible en haut au centre** : pause (deux barres) puis ×1 à ×16 en icônes de flèches (1 à 5 flèches ; infobulle : le facteur) ; la vitesse en cours est allumée. Le poste de pilotage et le BURN ramènent à ×1 |
| Altitude, inclinaison de l'orbite | Au **poste de pilotage** : manœuvre au prochain nœud (inclinaison visée **0 à 80°**, altitude visée **400 à 800 km**), exécutée en mode **Auto** ou en maintenant le bouton **BURN** bleu (mode **Manuel**, aussi sur la tablette) ; voir « Poste de pilotage ». Réglage direct (outil de développement) : section « Orbite » du **panneau de debug (F4)**, altitude 200 à 800 km, inclinaison 0 à 80° bornée par la latitude courante (voir ci-dessous) |
| Date, heure (UTC), redémarrer | Outils de développement, dans le **panneau de debug (F4)** : champ **date** (AAAA-MM-JJ, valider par Entrée), boutons **−1 j / +1 j**, curseur de l'**heure** du jour (la station reste au-dessus du même point ; le soleil, les étoiles et les nuages se placent selon la nouvelle heure ; départ : **15 juillet 2035**) ; **Redémarrer (Europe) De jour / De nuit** : temps remis à zéro, station au-dessus de l'Espagne (Madrid, 40,4° N 3,7° O, phase montante) à **midi** / **minuit** heure solaire locale, le même jour ; l'altitude est conservée, l'inclinaison relevée à 40,4° si elle était plus faible |
| Poste de pilotage | Grand écran de la console du module Commande (à l'avant) : le survoler à moins de 2,5 m affiche **« Contrôle orbital »** au curseur ; **clic gauche** dessus : position **« poste de pilotage »** (la vue se cadre face à l'écran, déplacements et rotation de la tête suspendus) ; **clic droit** : on quitte le poste (retour à la position d'avant). L'écran ne réagit à la souris qu'en position « poste de pilotage ». Voir « Poste de pilotage » |
| Lampe torche | **L** (action `torch`, touche physique) : allume ou éteint une lampe torche tenue par l'observateur (nœud `Observer/Camera/Torch`, `scripts/torch.gd` : `SpotLight3D` de 32°, portée 10 m, lumière chaude, ombres portées — elle ne traverse pas les parois), qui éclaire devant soi, avec un léger tremblement de la main (bruit lisse, ±0,7°, 1,6 Hz, amplifié en déplacement) ; précieuse quand la station est éteinte (« plus de lumière ») |
| Pause | **Échap** (action `pause`, touche physique ; un nouvel appui sur Échap reprend la partie) : fige le jeu (orbite, missiles en vol, explosions, animations : `SceneTree.paused`) et ouvre l'écran des paramètres par-dessus la vue figée (fond translucide), avec deux boutons : **Retour** (ou Échap) reprend la partie, **Quitter la partie** demande confirmation (**Oui** / **Non**, « Non » sélectionné par défaut) puis revient à l'écran de démarrage (la partie est perdue). Ignoré pendant la saisie de la date. Nœud `PauseMenu` de `orbit_view.tscn` (`scripts/ui/pause_menu.gd`, actif pendant la pause), `SettingsMenu.in_game` |
| Silos | **48 voyants ronds numérotés de 1 à 48** en bas de la tablette, un par tube de lancement, en 2 blocs de 3 × 8 placés comme les deux silos sur la station (vue de dessus, l'avant en haut ; silo 1 à gauche). **Orange** : missile prêt ; clic → **vert** : tube choisi pour le prochain tir (un seul à la fois, nouveau clic pour annuler) ; **gris** : tube vide. **48 missiles en tout**, sans rechargement. Choisir un tube **ouvre sa trappe** (animation Blender) et allume à côté un **gyrophare rouge** à éclats, qui éclaire la trappe et le dessous de la coque ; le tube choisi auparavant referme sa trappe et éteint son gyrophare (de même si on annule le choix). Après le tir, quand le missile a quitté la station, la trappe se referme et le gyrophare s'éteint |
| Tir nucléaire | **Gros bouton rouge** à droite des silos (tablette), **depuis la cupola seulement** (ailleurs, il est grisé avec « Actif uniquement dans la coupole ») : lance le missile du **tube choisi (vert)** sur le point de la Terre visé par le **centre de la vue** (réticule), avec la puissance choisie sous les silos (**10 kt, 100 kt, 500 kt, 1 Mt, 10 Mt, 50 Mt** ; 1 Mt par défaut). Le point visé et la puissance sont figés à l'appui. Le missile sort de son tube (animation de lancement, 5 s : trappe, descente, allumage), le tube passe au gris, puis le missile tourne vers la cible en accélérant pendant que son moteur brûle (9 s) et part vers la zone d'impact ; moteur éteint, on le perd de vue ; dans les dernières secondes, sa **rentrée atmosphérique** apparaît au-dessus de la cible, comme une étoile filante, puis l'explosion a lieu. **Durée du vol : de 20 s (cible au nadir) à 2 min (cible à l'horizon)**, proportionnelle à la distance (temps de jeu : le vol se fige en pause et s'accélère avec le temps). Un **chronomètre** par missile, en bas à droite de l'écran (« Silo 7 · impact dans 0:43 », toujours visible, même hors de la cupola), décompte jusqu'à l'impact, passe au rouge et clignote dans les 10 dernières secondes. Sans tube choisi, ou si le centre de la vue ne vise pas la Terre (ciel, au-delà du limbe), il ne se passe rien et le missile reste dans son tube. Voir « Explosions nucléaires » |
| Bilan des explosions | Sur l'écran mural à droite en face de la télévision (module Commande) : pays touchés et pertes, cumulées sur toutes les explosions ; la liste défile seule quand elle déborde |
| Compteur de performances et panneau de debug | **F4** ouvre ou masque le **panneau de debug des explosions** dans la partie en cours (outil de développement, en français : puissance, coordonnées, scrubber du temps, alerte de la station, case **Combinaison** (enfilée ou rangée, `Station.set_suit_worn`, suit aussi l'enfilage au clic), bouton **Radio** (message radio d'essai), altitude et inclinaison directes de l'orbite, date et heure UTC, redémarrage ; voir « Scène de debug » dans « Explosions nucléaires »). **F3** affiche ou masque la ligne en haut à droite (visible par défaut, outil de développement, non traduite) : images par seconde, temps CPU et GPU moyens par image, appels de dessin, mémoire vidéo (moyennes sur 0,5 s). Nœud `FpsOverlay` de `scenes/orbit_view.tscn`, script `scripts/ui/fps_overlay.gd` ; voir « Performances » |

Pendant la rotation le curseur est masqué, puis replacé là où le clic droit a commencé.
Les touches sont définies par leur **position physique** sur le clavier (actions `move_forward`, `move_back`,
`move_left`, `move_right`, `roll_left`, `roll_right` de `project.godot`) : la même disposition en AZERTY et en QWERTY.
Elles sont ignorées pendant la saisie du champ date.
L'inertie (`smooth_toward` de `scripts/station_camera.gd`) est un double lissage exponentiel : la commande est lissée,
puis la vitesse est lissée vers la commande lissée, ce qui donne une courbe en S sans à-coup au départ ni à l'arrivée
(constantes de temps : 0,25 s en translation, 0,2 s en roulis). La souris garde un léger lissage (0,08 s) pour rester
précise à la visée.

**Le réticule de tir n'apparaît que dans la cupola** (sphère de 1,6 m autour du repère `Point_Vue_Cupola`,
`Station.is_in_cupola`) : en sortant de la cupola il disparaît en fondu (0,5 s), et réapparaît en fondu en y
revenant. **Hors de la cupola, on ne peut pas tirer** : le bouton rouge de la tablette est grisé, avec « Actif uniquement dans la coupole »
écrit dessus (`LaunchControl`, `BigRedButton.disabled_message`), et se réactive en revenant dans la cupola.

**Interface à l'écran** (nœud `Hud` de `scenes/orbit_view.tscn`, `scripts/ui/hud.gd`, construite en code) : barre de
vitesse du temps en haut au centre (`scripts/ui/time_bar.gd`, icônes dessinées), réticule de tir
(`nuke/aim_reticle.gd`) et chronomètres des missiles (`nuke/impact_timers.gd`, ajoutés par `LaunchControl`). Au
poste de pilotage, la barre du temps reste cliquable (on peut accélérer le temps en attendant le point de
manœuvre). Il remplace l'ancien panneau de contrôle de la cupola, dont les commandes sont passées sur la tablette et
dans le panneau de debug.

## Tablette

Tablette de 12 pouces (28 × 19 cm, 5,5 mm d'épaisseur, coque en aluminium anodisé gris sidéral aux coins arrondis, verre noir, caméra
frontale, boutons sur les tranches) tenue par l'observateur. Modèle `assets/tablet/tablet.glb`, construit par
`tools/blender/build_tablet.py` dans un Blender lancé en arrière-plan (`blender --background --python
tools/blender/build_tablet.py -- <glb|-> <blend> <peau.png> [aperçu.png]` ; `-` : sans export, pour la mise au point
dans Blender ; aperçus de face, de dos, du joueur et de côté), qui enregistre aussi `E:\Blender\tablette.blend` pour
la retoucher. **Règle : la main est mise au point dans Blender (aperçus) et validée avant d'être exportée vers
Godot.** Objets : `Tablette_Coque`, `Ecran_Tablette` (dalle, UV 0–1), `Tablette_Objectif`, `Tablette_Boutons`, et la
**main droite qui la tient** : `Main_Droite`, main et bas de l'avant-bras d'un **humain MakeHuman** généré par
l'extension Blender **MPFB2** (à installer dans Blender), texture de peau CC0
(`assets/makehuman/skins/young_caucasian_male/young_lightskinned_male_diffuse.png`). Prise : la tranche droite repose
dans le creux entre le pouce et l'index (base du pouce contre la tranche), doigts tendus à plat contre le dos, pouce
amené par cinématique inverse sur la bordure avant à côté de l'écran, sa dernière phalange tournée de 50° sur son
axe pour laisser voir l'ongle (sinon le pouce paraissait coupé) ; la tablette (5,5 mm, épaisseur choisie pour
tenir dans l'ouverture de la main) est centrée entre le pouce et les doigts (contact à 0,3 mm près). `Manche` :
avant-bras dans la manche bleu marine d'une combinaison de vol, dans l'axe de l'avant-bras, hors du champ. La main arrive et repart
avec la tablette ; sortie, **seul le pouce reste visible** (la paume est derrière, le poignet et le bras sous le bas
de la vue).

- **Nœud `Observer/Camera/Tablet`** (`scripts/tablet.gd`) : enfant de la caméra, il suit la vue. Sortie, elle est
  **en bas à droite** de la vue (pas centrée) : 42 % de la hauteur de la vue (`view_fill` ; cadrage calculé d'après
  le champ de la caméra et les proportions de la fenêtre), son bord droit à 10 % du bord droit (le coin inférieur
  droit, qui dépasse avec la perspective, et le pouce restent dans le champ), son bord bas un peu au-dessus du bas
  de la vue (`bottom_margin` 8 % avant l'inclinaison vers l'œil, qui abaisse ce bord : à 3,5 %, la dernière rangée
  de silos et le bouton de tir sortaient de l'écran, d'autant plus si la barre des tâches mord sur la fenêtre ; la
  main et le bras sont dessous), son haut
  sous le centre (le réticule reste visible), à moitié tournée vers l'œil (tout à fait, en bord de vue, elle
  paraissait de biais). **Réduite à 40 % et rapprochée de l'œil d'autant** (`NEAR_SCALE`, homothétie de centre
  l'œil : même image) : à ~12 cm, elle est plus près que tout obstacle (sphère de collision de l'observateur,
  0,3 m) ; à taille réelle (~30 cm), les barreaux de la cupola passaient devant elle. Rangée, elle est masquée et
  son interface n'est plus redessinée. Éclairée par les lampes
  intérieures (calque `Station.INTERIOR_LAYER`) et le soleil, sans ombre portée.
- **Tenue en main** : **Tab** la fait apporter par la main (0,6 s) : elle arrive du bas à droite, plus près des yeux,
  en décrivant une boucle (courbe de Bézier cubique : montée sur le côté droit, léger dépassement vers la gauche et
  le haut, puis sa place, avec la décélération de la main) en se redressant (au départ inclinée de 32°, tournée de
  40° vers la droite et penchée de 25°) ; Tab la range par le chemin inverse (0,4 s). Sortie, elle **respire**
  (balancement lent de ~2 mm et 0,35°) et **suit la tête avec un temps de retard** : quand on tourne la vue, elle
  traîne d'une part de la rotation (au plus 3,4°) puis rattrape (0,16 s).
- **Écran** : l'interface est dessinée dans un `SubViewport` de 560 px de haut (proche de la taille affichée, pour un
  texte lisible) et affichée par `shaders/pilot_screen.gdshader` (le même que l'écran du poste : émission brute ; un
  `StandardMaterial3D` émet en nits avec les unités de lumière physiques du projet, ce qui blanchissait l'écran).
  Les clics et mouvements de la souris sur l'écran (rayon de la caméra intersecté avec la dalle, repérée par ses UV)
  sont transmis à l'interface ; un relâchement hors de l'écran aussi (bouton maintenu) ; le clic droit reste à la
  caméra (tourner la tête).
- **Interface** (`scripts/ui/tablet_display.gd`) : en haut, **trois onglets cliquables** — **Pilotage**,
  **Photographie**, **Tir de missile** — et, à droite, le bouton **« HUD : On / Off »** ; dessous, date et heure UTC
  et heure solaire du point survolé. Une seule page affichée à la fois, dans la hauteur restante (tout tient dans la
  dalle) :
  - **Pilotage** : carte réduite (la même `OrbitalMap` que le poste de pilotage : trace au sol, station, point de
    manœuvre, trace fantôme), **de 80° N à 80° S** comme au poste (rapport 1,29), aussi grande que la page le permet, et, dans une colonne à droite (210 px), la commande de
    poussée (`BurnControl` en colonne, compacte : compte à rebours 44 px, BURN bleu 100 × 94, textes 18 px,
    **jauge verticale** à droite sur toute la hauteur du bloc, remplie du bas vers le haut, pour un dosage précis) ;
  - **Photographie** : **vue au nadir en temps réel** (caméra de la tablette, `SubViewport` de 600 × 470 qui partage
	le monde de la scène, 15 m sous la station, champ de 22°, haut de l'image dans le sens du vol ; rendue seulement
	quand la tablette est sortie sur cet onglet) et bouton **« Photo »**. La caméra a une copie de l'environnement en
	mappage tonal linéaire et sans halo : l'image est ensuite vue par la caméra principale, qui les applique déjà
	(ACES deux fois : image délavée).
	**Photos satellites** (`Tablet._take_photo`, archive `scripts/photo_archive.gd`, nœud `Photos`, groupe
	`photo_archive`) : flash, puis la vue au nadir est rendue une fois en **1 600 × 1 253** avec le rendu final du
	jeu (environnement d'origine : ACES, halo) et enregistrée en **PNG dans `user://photos/`** (nom : date et heure
    du jeu, latitude, longitude ; le joueur garde ses photos) ; deux images plus tard, une seconde capture au rendu de
	la vue en direct sert à la galerie (sans quoi elle serait délavée sur l'écran). Chaque photo garde le **point
	survolé** à la prise de vue (point sous la station : c'est lui qui comptera pour la précision d'une photo de
	mission, signal `PhotoArchive.photo_taken`), l'heure UTC du jeu, l'altitude et l'**emprise au sol**
	(2 h tan 11° de haut × proportions de l'image : ~199 × 156 km à 400 km). **Galerie** : bouton « Galerie (n) »
	(dernière photo), ◀ ▶ (précédente, suivante), légende sur fond sombre (numéro, date, point survolé, altitude,
	emprise), « Vue en direct » pour revenir ; le bouton Photo revient aussi à la vue en direct. Photos gardées le
	temps de la partie (elles entreront dans la sauvegarde de campagne) ;
  - **Tir de missile** : la commande de tir (`LaunchControl` : 48 silos, **petits boutons de puissance** — à terme,
	chaque silo aura sa bombe et sa puissance —, gros bouton rouge), mise à l'échelle pour occuper la page ;
  - **Alertes** (règle de jeu : la tablette est le récepteur des alertes, comme un téléphone) : écran partagé en
	deux. En haut (~80 %), l'**écran de réception** : l'appel prioritaire en cours (`PriorityCall` : « APPEL
    PRIORITAIRE », expéditeur, objet, heure de réception ; le message lui-même se lit au poste COMM), sinon
	« Aucune alerte », et, juste au-dessus des boutons, le **bandeau clignotant** de l'appel (orange sur fond
	sombre). En bas, **5 gros boutons** du niveau d'alerte de la station (`Station.set_alert`, comme le menu
    « Alerte » du panneau de debug) : **Normal** (blanc), **Jaune**, **Orange**, **Rouge** et **Tout éteindre**
    (« plus de lumière » : lumières de secours seules), dessinés comme le bouton de tir ou BURN (`BigRedButton`),
	capuchon de la couleur de l'alerte (noir pour Tout éteindre) ; le niveau en cours est marqué « ▲ ». À l'arrivée
	d'un appel, la tablette passe d'elle-même sur cet onglet (sortie ou rangée : elle s'ouvrira dessus).
- **HUD (surimpression dans la cupola)** : `Hud.overlay_enabled` (**désactivé au démarrage** ; `set_overlay_enabled`,
  signal `overlay_changed`), basculé par le bouton de la tablette. Il porte les éléments 3D vus à travers les vitres
  de la cupola : pour l'instant l'anneau de l'orbite visée (`GhostTrack`), à venir la zone visée (photo, missiles).
  Le réticule de tir et la barre du temps n'en dépendent pas.

**Écran « Bilan des explosions »** (nœud `NukeReport` de `scenes/orbit_view.tscn`, script
`nuke/nuke_report_panel.gd`, construit en code) : affiché sur l'**écran mural `Interactif_Ecran_02`** du module
Commande (à droite, en face de la télévision, retiré des écrans d'ambiance), dans un `SubViewport` 1280 × 800 posé
sur la dalle avec le shader des écrans d'ambiance (`shaders/tech_screen.gdshader`, lignes de balayage). Il remplace
l'ancienne fenêtre déplaçable à l'écran. Sans explosion : « Aucune explosion ». Image rendue seulement si la caméra
est à moins de 12 m ; écran éteint avec « plus de lumière » (`Station.get_blackout`).
- Résumé : nombre d'explosions, total des morts et des blessés **à l'instant présent** (au temps de chaque
  explosion : flash, onde de choc, décès des blessés, retombées ; voir « Pertes humaines »), puis la projection à
  60 jours (bilan final du souffle et de la chaleur + retombées), avec « bilan : calcul en cours… » tant que
  leur calcul tourne.
- Liste des pays touchés, cumulés sur toutes les explosions et triés par morts décroissants (à égalité, par nombre
  d'explosions). Colonnes :
  - **Expl.** : nombre d'explosions dont le point zéro est sur le territoire du pays (« — » pour un pays touché
	seulement par une explosion voisine : l'Allemagne après un tir sur Bâle) ;
  - **Morts**, **Blessés** ;
  - **Population** : part de la population du pays tuée (« 0 % » sans mort).
  Un territoire dépendant est suivi de son État souverain. Un pays sous black-out national est en ambre, marqué ⚡,
  même sans perte humaine ; un pays visé sans perte (désert) apparaît aussi. Les lignes sont regroupées par code de
  pays (`CountryMask`). Pas de souris sur un écran mural : quand la liste déborde, elle **défile seule** (descente
  lente, pause en bas, retour en haut).
- Rafraîchi deux fois par seconde (`NukeCasualties.snapshot` sur `NukeEffect.casualties`, `NukeEffect.fallout`,
  `NukeEffect.grid`, via `NukeTally`, sans recalcul) : les chiffres montent sous les yeux. Les lignes sont mises à
  jour sur place et ne sont recréées que si l'ordre des pays change. Avec le scrubber du panneau de debug, il suit le
  temps rejoué.

**Compteur de performances** (nœud `FpsOverlay` de `scenes/orbit_view.tscn`, script `scripts/ui/fps_overlay.gd`,
`CanvasLayer` de couche 100, outil de développement) : une ligne en haut à droite, « 144 fps · CPU 6,9 ms · GPU 5,2 ms
· 790 draw · VRAM 2 450 Mo », moyennes sur 0,5 s de temps réel (indépendantes de la pause et de la vitesse du
temps). Le temps GPU vient de `RenderingServer.viewport_set_measure_render_time` sur le viewport principal (comme le
banc de mesure), les appels de dessin et la mémoire vidéo de `Performance`. **F3** le masque ou l'affiche. Texte non
traduit (outil de développement, comme la console et le panneau de debug).

**Règles de l'orbite appliquées par les réglages directs** (panneau de debug ; les manœuvres du poste de pilotage
se font au nœud, voir « Poste de pilotage ») **:**
- changer l'altitude conserve le point survolé et le sens de passage (montant / descendant) ; la période change
  avec l'altitude ;
- changer l'inclinaison se fait au point courant (comme un changement de plan orbital). Elle **ne peut pas être
  inférieure à la latitude actuelle** de la station : une orbite d'inclinaison i ne dépasse jamais ±i de latitude.
  La valeur demandée est donc remontée à |latitude| si besoin (le curseur se recale). Par exemple, au-dessus de
  Madrid (40,4° N), le minimum est 40,4°.
- l'accélération du temps agit sur l'orbite, la rotation de la Terre, le soleil et le déplacement des nuages par le vent (pas sur la lente évolution du relief de leurs sommets).

## Poste de pilotage

Le grand écran de la console du module Commande (`Interactif_Ecran_Principal`, dalle au matériau `Ecran_15`,
1,59 × 0,89 m ; les deux petits écrans latéraux ont été retirés du modèle) est l'écran de **contrôle orbital**,
une interface diégétique : elle est dessinée en 2D dans un `SubViewport` et affichée par la dalle elle-même.

- **Nœud `PilotConsole`** de `scenes/orbit_view.tscn` (`scripts/pilot_console.gd`) : crée le `SubViewport`
  (1 000 px de haut, largeur aux proportions de la dalle), remplace le matériau de la dalle par
  `shaders/pilot_screen.gdshader` (image émise, dalle noire peu réfléchissante ; les UV du modèle étant inutilisables,
  la position dans l'image vient de la position du sommet dans le rectangle de la dalle, mesuré au démarrage sur les
  faces `Ecran_15` tournées vers l'observateur), et gère le poste :
  - survol de la dalle (rayon de la caméra par le curseur, intersecté avec le rectangle de la dalle) à moins de
	2,5 m : bulle « Contrôle orbital » au curseur ;
  - clic gauche sur la dalle : position « poste de pilotage », **temps ramené à ×1** (les manœuvres se jouent en
	temps réel). L'œil glisse en 0,6 s face au centre de la dalle, à
    la distance où elle occupe 90 % de la vue (en hauteur ou en largeur selon les proportions de la fenêtre) ;
	l'observateur (`Observer`, corps et tête) est suspendu : ni déplacement, ni rotation, ni roulis. Toute la souris
	est alors prise par le poste : les mouvements et clics sur la dalle sont transmis à l'interface (position
	convertie en pixels de l'image), les autres sont ignorés (pas de tir, pas de clic sur le reste de l'interface).
    Indication en bas de la vue : « Clic droit : quitter le poste de pilotage » ;
  - clic droit : retour en 0,6 s à la position et à l'orientation d'avant, l'observateur reprend la main.
  - Coût : comme les autres écrans, l'image n'est rendue et l'interface mise à jour que si la caméra est à moins
	de 12 m de la dalle (`RENDER_DISTANCE`).
- **Interface** (`scripts/ui/pilot_display.gd`, construite en code) : carte à gauche ; à droite, l'orbite actuelle
  (heure UTC, position, altitude, inclinaison et **précession J2** de Ω en °/jour, période et **décalage de la trace
  au sol par tour**, vitesse orbitale) puis la **manœuvre** : curseurs de l'**inclinaison visée** (0 à 80°), de
  l'**altitude visée** (400 à 800 km, avec le décalage par tour qu'elle donnerait) et du **décalage du nœud** (±20°,
  E / O), Δv de la manœuvre, bouton **Annuler** (cible ramenée sur l'orbite actuelle), boutons **Auto / Manuel** et
  la **commande de poussée** (`scripts/ui/burn_control.gd`) : compte à rebours du point de manœuvre (« Nœud
  ascendant / descendant dans 31:10 » au passage de l'équateur, « Point de manœuvre dans 09:30 » ailleurs ; temps de
  jeu), gros bouton **BURN bleu** (même dessin que le bouton de tir, `nuke/big_red_button.gd`, en mode maintenu ;
  terne hors de la fenêtre), jauge de 0 à 150 % de la durée requise (zone verte 95–105 %, remplissage bleu, orange
  au-delà) et message d'état (résultat de la poussée affiché 6 s). La même commande de poussée est sur la
  **tablette** : on peut lancer le BURN de la manœuvre prévue de partout.
- **Trois leviers pour survoler un point** (règle de jeu) :
  - **attendre** : la Terre tourne sous l'orbite, la trace au sol recule vers l'ouest à chaque tour (−23,5° par tour
	à 400 km et 51,6°) ; toutes les longitudes défilent en moins d'un jour ;
  - **phasage par l'altitude** (peu coûteux) : une orbite plus haute a une période plus longue, sa trace recule
	davantage à chaque tour (−23,5°/tour à 400 km, −25,5°/tour à 800 km), et inversement ; les écarts s'additionnent
	d'un tour à l'autre. L'altitude sert donc aussi à caler le passage au-dessus d'un point ;
  - **décalage du nœud** (coûteux) : poussée qui fait tourner la ligne des nœuds (Ω) vers l'est ou l'ouest, à
	inclinaison constante, ~105 m/s par degré à 51,6° ;
  - s'y ajoute la **précession nodale J2** (aplatissement de la Terre, `Orbit.raan_precession`) : Ω dérive de
	−3/2·n·J2·(R/a)²·cos i, −5,0°/jour à 400 km et 51,6° (vers l'ouest pour une orbite prograde, nulle à 90°).
- **Règles de la manœuvre** (`scripts/flight_computer.gd`, nœud `FlightComputer`) :
  - tant que la cible diffère de l'orbite réelle (plus de 0,05°, 0,5 km ou 0,05° de décalage du nœud), une
    manœuvre est prévue et son orbite, la **trace fantôme**, est affichée ;
  - **point de manœuvre** : un changement de plan se fait là où l'orbite actuelle coupe le plan visé (droite
	d'intersection des deux plans ; deux points par tour, à une demi-période d'écart). Simple changement
	d'inclinaison : au **nœud** (passage à l'équateur, la ligne des nœuds reste en place) ; simple décalage du nœud :
	près du **sommet** de l'orbite (latitude maximale) ; manœuvre combinée : entre les deux ; altitude seule : au
	prochain nœud. La station garde sa position au point de manœuvre (la manœuvre est continue) ; l'orbite
	fantôme passe par ce point. L'orbite reste **circulaire** ;
  - Δv affiché : changement de plan 2·v·sin(θ/2) (θ : angle entre les deux plans, inclinaison et décalage du nœud
    compris) plus transfert de Hohmann entre les deux altitudes (somme des deux impulsions) ; ~4,2 km/s pour passer
    de 51,6° à 20°, ~1 050 m/s pour décaler le nœud de 10° : les changements de plan sont coûteux ;
  - **fenêtre** : la poussée n'est possible que de 5 s réelles avant à 5 s réelles après le passage du point de
	manœuvre (5 s × la vitesse du temps en temps de jeu, au plus 60 s) ; le compte à rebours passe au vert, puis
	reste à 00:00 tant que la fenêtre du point passé est ouverte ;
  - **mode Auto** : au passage du point de manœuvre, l'orbite prend exactement la cible (message « Pilote
    automatique : manœuvre au point de manœuvre » en attendant) ;
  - **mode Manuel** (par défaut) : maintenir le bouton **BURN** (temps ramené à ×1). Durée requise : 1,5 s +
    2,5 s × √(Δv en km/s), au plus 8 s (~2,3 s pour 100 m/s, ~6,6 s pour 4,2 km/s), affichée dans la fenêtre
	(« Fenêtre ouverte : maintenir BURN 3.9 s »). La poussée s'applique **progressivement** pendant l'appui : l'orbite
	passe de l'orbite de départ vers la cible au rythme de la jauge (au-delà de 100 %, elle dépasse la cible) ; à
	150 %, la poussée s'arrête d'elle-même. Relâché entre **95 et 105 %** : **poussée parfaite**, l'orbite prend
	exactement la cible. Sinon, **sous-poussée** ou **sur-poussée** : la part appliquée reste (inclinaison, altitude
	et Ω interpolés), plus des **erreurs aléatoires** proportionnelles à l'écart de dosage (jusqu'à ±2°
	d'inclinaison et ±60 km d'altitude pour 100 % d'écart, appliquées au point courant : l'erreur d'inclinaison est
	une erreur de cap, la station ne saute pas) ; l'orbite reste circulaire. L'inclinaison et l'altitude visées ne
	changent pas, le décalage du nœud restant est mis à jour (2,5° restent après une demi-poussée sur 5°) : la
	manœuvre reste prévue (trace fantôme) et se corrige au point suivant. Quitter le poste pendant la poussée la
	relâche.
- **Trace fantôme** : sur la carte, trace au sol de l'orbite fantôme en **pointillés cyan** sur une période, à partir
  du point de manœuvre (losange cyan, toujours affiché) ; en 3D, **anneau en pointillés cyan autour de la Terre**
  (`scripts/ghost_track.gd`, nœud `GhostTrack`, `MeshInstance3D` + `ImmediateMesh` en lignes, 720 segments, un sur
  deux tracés par paires). L'anneau est construit dans le repère inertiel ECI pour Ω = 0 (reconstruit seulement si
  le rayon ou l'inclinaison changent) et, à chaque image après `Orbit`, placé au centre de la Terre, tourné de Ω
  (précession comprise) puis par `Orbit.get_eci_to_world()` : la Terre tourne dessous, sa trace au sol reste
  cohérente. Rendu non éclairé, couleur × 1,5 (HDR) pour rester visible sur la Terre
  éclairée (à × 3, l'exposition automatique de nuit faisait baver les tirets en halos) ; caché quand aucune manœuvre
  n'est prévue.
- **Carte** (`scripts/ui/orbital_map.gd`) : projection de **Mercator de 80° N à 80° S** (rapport largeur / hauteur
  2π / (2·ln tan(45° + 40°)) ≈ 1,29), lignes blanches sur fond noir : contours des pays et des continents
  (`assets/world_map_lines.res`, Natural Earth 1:50 M, `scripts/world_map_lines.gd`, généré par
  `tools/build_map_lines.gd` ; sommets à au moins 0,05° les uns des autres). Méridiens et parallèles tous les 10° et
  équateur en gris. Trace au sol de l'orbite (sinusoïde déformée par la projection et décalée vers l'ouest à
  chaque tour par la rotation de la Terre), coupée à l'antiméridien : demi-période passée en gris-vert fin, **orbite
  en cours** (une période à partir de maintenant) en **vert très clair**, puis les **orbites à venir** (0 à 4, 1 par
  défaut) d'un vert de plus en plus sombre, la 4ᵉ vert sombre mais bien visible ; station en jaune (flèche dans le
  sens du déplacement, cerclée) ; prochain nœud et trace fantôme en cyan (voir ci-dessus).
  - **Cibles au sol** (règle de jeu ; `scripts/ground_target.gd`, nœud `GroundTarget`, affichées par la carte du
	poste et celle de la tablette) : **jusqu'à 5 cibles, chacune de sa couleur** (jaune doré, rouge, magenta, violet,
	orange : distinctes du jaune pâle de la station, du vert des traces et du cyan de l'orbite visée), dont une
    **cible choisie**. **Elles ne se placent que sur la carte du poste de pilotage** (`OrbitalMap.targets_editable`),
    **à la main** (pas de saisie de coordonnées) : menu des cibles en haut à gauche de la carte — « Cibles », **un
	bouton par cible portant son icône** (cercle, point, croix) dans sa couleur, pâle tant qu'elle n'est pas posée,
    le bouton de la cible choisie en surbrillance, et **« Effacer »** (la cible choisie) ; un **clic** sur la carte
    (sans la glisser : moins de 5 px de déplacement) place la cible choisie au point cliqué, un clic sur une cible la
	choisit. La carte de la tablette les affiche seulement (un clic n'y fait rien). Sur les cartes : la même icône
	dans la couleur de la cible, coordonnées à côté (« 48.86° N  2.35° E ») ; la cible choisie en trait épais, les
	autres plus fines et un peu transparentes. Au **survol**, la latitude et la longitude du point sous le pointeur le
	suivent. Dans la **cupola en mode « HUD : On »**, chaque cible apparaît dans sa couleur **posée à l'horizontale
    sur la Terre**, dont elle épouse la courbure
    (`scripts/ui/target_marker.gd`, calque du `Hud`) : trois anneaux (40, 80 et 120 km) et une croix tracés sur la
    sphère, le long du sol, dans un maillage enfant de `Earth` (il tourne avec la planète ; la cible choisie pleine,
	les autres pâles), sans éclairage, dessiné après les nuages et l'atmosphère (qui n'écrivent pas de profondeur :
    elle reste par-dessus) mais avec test de profondeur (la structure de la coupole la cache), masqué sous
	l'horizon, sans coordonnées (elles masqueraient la vue : elles sont sur les cartes) ; flèche au bord de l'écran,
    dans sa couleur, quand la cible choisie est hors champ. Le tir de missile reste visé au
    réticule (centre de la vue).
  - **Survol des écrans en SubViewport** (poste, télévision, tablette) : un tel viewport, affiché comme texture,
	ne reçoit jamais de lui-même l'entrée de la souris ; sans elle, Godot ne lui transmet que les clics et les
	glisser, pas le simple survol. `ScreenSeat.set_mouse_inside` lui envoie l'entrée et la sortie de la souris
	(`NOTIFICATION_VP_MOUSE_ENTER` / `EXIT`) quand le pointeur arrive sur l'écran ou le quitte.
  - **Navigation, comme une carte en ligne** (même carte au poste et sur la tablette, chacune sa vue) : **molette** =
	zoom centré sur le curseur ; **glisser** (bouton gauche) = déplacer la carte dans le sens de la souris ; boutons
	en bas à gauche **« − » / « + »** = zoom centré sur le centre de la carte ; en bas à droite **« Orbites à
	venir » 0 1 2 3 4** (clés `MAP_ORBITS_AHEAD`, `MAP_ZOOM_IN`, `MAP_ZOOM_OUT`). Zoom de ×1 (monde entier) à ×32 (limite des contours Natural Earth au 1:50 M) ; le
	monde se répète d'est en ouest (on en fait le tour sans fin), la carte ne dépasse pas ±max_lat en latitude.
  - **Performances** : le fond (≈ 85 000 segments) est rendu dans la texture d'un `SubViewport` (`UPDATE_ONCE`,
	MSAA 4×) seulement quand la vue a changé et ne bouge plus depuis 0,15 s (redessiner autant de lignes lissées à
	chaque image coûtait ~20 ms de CPU) ; pendant un zoom ou un glisser, l'image précédente est déplacée et mise à
	l'échelle. Les points de trace sont **en cache** sur une grille de 20 s (une trace recalculée à chaque image
	coûtait ~3,5 ms par carte à 4 orbites) ; un point témoin recalculé par image (premier point de grille après le début de la trace) vide le cache si l'orbite ou l'orbite visée change
	(manœuvre, date, altitude). Une carte non affichée (onglet caché, tablette rangée) n'est pas redessinée.
- **Écrans d'ambiance des modules Commande et Arrimage** (`scripts/tech_screens.gd`, nœud `TechScreens` de
  `orbit_view.tscn`, shader `shaders/tech_screen.gdshader`) : sur les écrans plats et les portables du module Commande
  (pas sur le grand écran du poste) et sur le portable `Interactif_Ordinateur_05` de l'Arrimage (télémétrie), des programmes « techno-thriller » dessinés en 2D dans cinq `SubViewport` partagés : listage de code et
  de journaux qui défile (lignes générées une fois au démarrage ; clin d'œil : quelques commentaires « // only Trap15
  could understand this »), station en fil de fer qui tourne sur elle-même
  (modèle simplifié précalculé : modules, silos, poutre, panneaux), télémétrie (courbes, barregraphes, radar à
  balayage), détermination d'orbite (Terre, orbite, colonnes hexadécimales) et, sur les bandeaux 13 et 14, spectre
  radio et oscilloscope. Affectation : table `ASSIGNMENT`. Coût réduit : images redessinées à 15 Hz (`refresh_hz`)
  et seulement quand la caméra est dans un module qui a des écrans animés (`MODULES_X` : Commande, Arrimage) ; écrans éteints avec « plus de lumière »
  (`Station.get_blackout`). Mesure : 120 im/s inchangés dans le module. Les textes affichés sont du pseudo-code et
  des valeurs techniques, sans langue : ils ne passent pas par les fichiers de langue.
- **Communication radio** (`scripts/comm_console.gd`, nœud `CommConsole` ; interface `scripts/ui/comm_display.gd` ;
  radio `scripts/radio_comms.gd`, nœud `Radio`, groupe `radio`) : l'écran 08 du module Commande (paroi −Y, retiré des
  écrans d'ambiance `TechScreens`) affiche le programme **COMM.EXE**, interface « MS-DOS années 80 » façon Norton
  Commander en mode texte : grille de 80 × 25 caractères d'une police à chasse fixe (Consolas, sinon Lucida Console
  ou Courier New), palette CGA (fond bleu, cadres doubles cyan clair, barre de menu cyan avec l'heure UTC du jeu,
  barre des touches de fonction en bas, curseur clignotant), lignes de balayage du shader des écrans.
  - **Vue radio** : comme la télévision (survol à 2,5 m → bulle « Communications radio » ; clic → la vue se cadre
	face à l'écran ; clic droit ou F10 → on quitte ; groupe `ScreenSeat`). En vue radio, souris **et clavier** vont à
	l'écran : F1 aide, F2 choix du canal, F10 quitter, flèches (message ou canal précédent / suivant), chiffres
    (envoyer la réponse correspondante), Entrée (valider le canal), Échap (fermer une fenêtre) ; tout se fait aussi à
    la souris.
  - Écran : ligne d'état (canal, fréquence, bande ; liaison en barre de signal avec la station au sol, ou « PAS DE
	LIAISON » clignotant) ; à gauche les messages reçus (heure, expéditeur ; non lus en jaune, lus quand on s'installe
	devant l'écran ou qu'on les choisit), à droite le message choisi (expéditeur, objet, réception et fréquence, texte)
	et ses réponses `[1]`, `[2]`… ; une réponse envoyée s'affiche en vert.
  - **Règles de jeu** (`RadioComms`) : **liaison** seulement avec une station au sol en vue (16 stations du réseau de
	suivi, de Houston à Canberra ; élévation de la station d'au moins 5° au-dessus de leur horizon) : qualité de
	15 % au ras de l'horizon à 100 % dès 25° d'élévation, nulle hors de vue (coupures sur les océans). **Canaux** :
    6 (143,625 et 145,800 MHz VHF, 437,800 MHz UHF, 2 265 et 2 287,5 MHz bande S, 8 400 MHz bande X) ; un message
	posté sur un canal n'arrive que la radio réglée dessus (canal −1 : tous), et **attend au sol** que la liaison et le
	bon canal le permettent. **Réponses** : un message peut en proposer ; en envoyer une demande la liaison (sinon
	« Échec de l'émission ») ; une seule réponse par message (signal `replied`).
  - API pour la campagne : `RadioComms.post({from, subject, body, channel, replies})` (textes : clé des fichiers de
    langue, texte, ou dictionnaire par langue comme `campaign.json`), signaux `message_received`, `replied`. Panneau
	de debug : bouton « Radio » (message d'essai du contrôle sol, deux réponses).
- **Télévision** (`scripts/tv_console.gd`, nœud `TvConsole` ; interface `scripts/ui/tv_display.gd`) : l'écran
  `Interactif_Ecran_03` du module Commande (retiré des écrans d'ambiance) diffuse les chaînes d'information du monde.
  - **Vue TV** : survol à portée (2,5 m) → bulle « Télévision » ; clic gauche → la vue se cadre face à l'écran, comme
	au poste de pilotage (déplacements suspendus, tablette rangée, écoutilles non cliquables : groupe commun
	`ScreenSeat`, `scripts/screen_seat.gd`) ; **clic droit** pour quitter, la télévision reste sur la chaîne choisie
	(France par défaut).
  - **Chaînes** : bouton « Chaînes » en haut à gauche de l'écran → **guide des chaînes** plein écran, comme sur une
    vraie télévision : mosaïque défilante (molette) de vignettes (`scripts/ui/channel_tile.gd`) avec logo, drapeau du
    pays en haut à droite (`assets/tv/flags/<CODE>.png`, 80 px, drapeaux du projet flag-icons, licence MIT, via
    flagcdn.com, `tools/build_tv_flags.ps1`), numéro de
	chaîne, nom de la chaîne et pays ; chaîne en cours encadrée, pays hors d'antenne grisés ; bouton « Fermer ».
	Logos générés à partir du nom de la chaîne (toujours les mêmes) : couleur de marque, un des quatre styles (bloc,
	souligné, pastille ronde, bandes obliques) et monogramme (initiales des mots, nombres gardés : « RV24 »).
	Chaînes numérotées dans l'ordre alphabétique des pays (nom traduit,
	`locale/countries.csv`), chacun avec sa chaîne d'information au nom **inventé** mais vraisemblable (159 pays
	souverains d'au moins un million d'habitants — les plus petits n'ont pas de chaîne —, `assets/tv/channels.csv` : code ISO, nom de la chaîne, coordonnées de la capitale ; les noms de
    chaînes sont des noms propres, hors fichiers de langue). La chaîne diffuse une **vidéo en boucle** du plateau
    (deux présentateurs), avec le nom de la chaîne en haut à droite et un bandeau « En direct » + pays en bas.
  - **Deux éditions** : **normale** (têtes qui bougent calmement) et **spéciale « Alerte info »** (présentateurs
    agités qui se tournent vers le mur vidéo, où passe un champignon atomique, bandes rouges qui pulsent ; bandeau
    rouge clignotant `TV_BREAKING` à la place de « En direct »).
  - **Règles de jeu** : un pays dont la **capitale est touchée** (dans le rayon de 5 psi d'une explosion,
	`TvConsole.OFF_AIR_PSI`) ne diffuse plus, définitivement (le monde persiste) : sa chaîne passe sur la mire
	**« Pas de signal »** et la liste la signale « hors d'antenne ». Après chaque explosion, **toutes les chaînes
	encore à l'antenne passent en édition spéciale** pendant 24 h de jeu (`ALERT_HOURS`, horloge UTC d'`Orbit`)
	après la dernière, puis reviennent à l'édition normale. État recalculé à chaque tir et toutes les 2 s.
  - **Vidéos** (`tools/build_tv_videos.ps1`) : les **maîtres modifiables** sont dans `assets/tv/source/`
	(`.gdignore`) : `normal.mp4` et `alert.mp4` (H.264, 960 × 600, 25 im/s, boucles de 12 s, sans texte : tout le
	texte est incrusté par le jeu), `explosion.mp4` (images du mur vidéo, 1000 × 400) et `tv_studio.blend` (scènes
	`Studio_Normal`, `Studio_Alerte` et `Explosion`, produites par `tools/blender/build_tv_studio.py` dans un Blender
	en arrière-plan). Le jeu lit des **Ogg Theora** (seul format vidéo de Godot) : `assets/tv/video/normal.ogv` et
	`alert.ogv`, convertis depuis les maîtres. Une chaîne peut avoir **ses propres vidéos** :
	`assets/tv/source/<CODE>/normal.mp4` et `alert.mp4` (code ISO du pays) → `assets/tv/video/<CODE>/…ogv` ; sinon
	elle diffuse les vidéos communes. Après retouche d'un maître dans un logiciel vidéo : `build_tv_videos.ps1
    -ConvertOnly` ; après remplacement de `explosion.mp4` : `-Studio` (nouveau rendu du plateau) ; sans option :
	tout est régénéré (rendus Blender compris). Puis rescan dans l'éditeur.
  - **Bandeau défilant** (`scripts/tv_news.gd`, classe `TvNews`), dans les deux éditions (rouge en édition spéciale,
	bleu nuit en temps normal) : en bas de l'écran, dans la
    **langue de la chaîne** (colonne `lang` de `channels.csv` : langue majoritaire du pays, à défaut celle de ses
    journaux télévisés — anglais, français, portugais… pour les pays sans langue majoritaire ou dont la langue
	majoritaire n'est pas traduite ; 65 langues, défilement vers la droite pour l'arabe, l'hébreu, le persan et
	l'ourdou ; les écritures non latines s'affichent par les polices du système). Contenu, recomposé à chaque passage
	et aussitôt après chaque tir :
	0. **tant qu'aucune explosion n'a eu lieu, infos ordinaires** : préfixe « En bref : » / « L'essentiel : », Bourse
	   du pays (variation tirée chaque jour de jeu), **météo de la capitale** d'après les **vrais nuages** vus de la
	   station (`scripts/cloud_weather.gd`, classe `CloudWeather` : carte réduite de l'instantané VIIRS
	   `assets/cloud_cover.res`, 0,25°, générée par `tools/build_cloud_cover.gd`, lue au point d'où vient l'air en
       remontant le vent GFS comme le shader des nuages : soleil ou nuit claire, éclaircies dès 30 % de couverture,
       ciel couvert dès 65 %) et température plausible (latitude, saison, heure solaire, nuages), puis un **résultat
       sportif** inventé (football ou basket, deux équipes nationales et un score tirés chaque jour de jeu) ;
	1. préfixe « Alerte info : » en édition spéciale (« En bref : » ensuite, une fois revenu à l'édition normale) ;
	2. nombre d'explosions et puissance cumulée (kt sous 1 Mt, Mt à une décimale au-delà), pays touchés (point zéro
       sur leur territoire, `NukeTally`) ; « détectée(s) en mer » si aucun pays ;
	3. morts selon « nos experts » (bilan `NukeTally` à l'instant présent, arrondi à trois chiffres significatifs) ;
	4. capitales détruites (chaînes hors d'antenne) : sans nouvelles des autorités de ces pays ;
    5. déclaration du gouvernement du pays qui diffuse : **touché et puissance nucléaire** (États-Unis, Russie,
       France, Royaume-Uni, Inde, Pakistan, Chine, Israël, Corée du Nord : `nuclear_powers` de `news_rules.json`) → alerte
	   maximale, riposte à l'étude, consignes à la population ; **touché sans arme nucléaire** → alerte maximale et
	   consignes ; **non touché** → alerte maximale, protection du pays, pensées pour les pays touchés.
	**Règles d'affichage** (`assets/tv/news_rules.json`, vision d'ensemble des cas) : le bandeau est un préfixe puis
	des sections dans l'ordre (bourse, météo, sport, explosions, bilan, capitales, gouvernement) ; dans chaque section, la **première règle
    dont la condition est vraie** donne la **clé** de la phrase (aucune : la section est omise). Une condition porte
    sur des faits nommés (`explosions`, `yield_kt`, `countries_hit`, `deaths`, `capitals_destroyed`,
    `broadcaster_hit`, `broadcaster_nuclear`, `alert`, `cloud_cover`, `night`, `temperature`, `stock_change`, `roll`
    — tirage au hasard à chaque passage, pour alterner les rubriques), avec des tests « 1 », « >0 », « >=2 », « <5 », « !=1 » ou true /
    false ; la liste des puissances nucléaires (`nuclear_powers`) y est aussi. Ajouter un cas : une règle (avant les
    règles plus générales de sa section) et une nouvelle clé, dont les variantes vont dans le CSV des textes.
    Chaque phrase a **plusieurs variantes** (trois pour les alertes, deux pour les infos ordinaires) (même sens, tournures différentes), tirées au hasard à chaque passage. Textes :
    `assets/tv/news_ticker.csv` (une ligne par clé et variante `CLE.n`, une colonne par langue, plus les réglages de
	nombres et d'unités par langue : `LIST_SEP`, `THOUSANDS`, `DECIMAL`, `UNIT_KT`, `UNIT_MT` avec `{n}`). Pour les
	langues à déclinaisons, les noms de pays et de capitales sont placés après deux-points (nominatif, sans faute
	d'accord). Noms des pays (CLDR d'Unicode, à défaut Wikidata) et des capitales (Wikidata) dans chaque langue :
	`assets/tv/news_country_names.csv`, `assets/tv/news_capital_names.csv`, téléchargés par
	`tools/build_tv_news_names.ps1` (cases vides : nom anglais). Ces textes du monde du jeu dépendent du pays qui
	diffuse, pas de la langue du joueur : ils sont hors des fichiers de langue (`locale/`). Les CSV de `assets/tv/`
	sont importés en « keep » (sinon l'éditeur les prend pour des fichiers de traduction).
  - Coût : le `SubViewport` de l'écran n'est rendu et la vidéo n'avance que si la caméra est à moins de 12 m.

## Station spatiale (modèle Blender)

Modèle `assets/station/station_spatiale.glb` (Blender, ~48 Mo de géométrie et d'animations, en Git LFS ; textures à
côté, voir « Import » ; conventions dans
`assets/station/LISEZMOI_GODOT.md`). **Ne jamais retoucher le .glb à la main** : il n'est produit que par l'export Blender, avec les mêmes
noms de nœuds ; tout réglage côté Godot passe par son `.import`, le script de post-import et la scène héritée.
- **Export depuis Blender** (`tools/blender/export_station.py`, envoyé au Blender ouvert par `tools/blender_exec.ps1`,
  extension « MCP » de Blender Lab sur le port 9876) : pose de repos (image 1), lumières de travail `Soleil` et
  `Reflet_Terre` masquées, GLB sans caméras ni Draco, lumières intérieures, extras, modificateurs appliqués mais
  **jamais les transformations** (les pivots `Pivot_*`, `Charniere_*`, `Radiateur_*_Articulation_*` portent les axes
  des animations et des Tweens), une piste NLA = une animation (`Fermeture_Ecoutilles`, `Ouverture_Trappes`,
  `Lancement_Missile`, `Balayage_Antennes`, `Rotation_Panneaux`, `Retraction_Radiateurs`, contrôlées avant export),
  copie de la notice `LISEZMOI_GODOT.md`. Les textures sont ensuite **sorties du .glb** (`externalize_images`) :
  fichiers `station_spatiale_<image>.png/.jpg` à côté, référencés par URI, réécrits seulement si leur contenu change,
  et ceux qui ne servent plus sont supprimés avec leur `.import`. Un réexport n'ajoute ainsi à Git LFS que la
  géométrie (~48 Mo) et les textures modifiées, au lieu d'une copie complète de 114 Mo (quota GitHub : 10 Go). Orientation : axe des modules = +X (Commande vers +X), Terre vers −Y.
  Règle : pas de réexport vers le projet sans le feu vert de l'utilisateur.
- **Faces sans coordonnées de texture** (`tools/blender/fix_collapsed_uvs.py`, MODE « report » ou « apply ») : une
  face dont tous les coins ont la même UV n'a pas de tangente ; dans Godot, la normal map de son matériau l'éclaire
  alors n'importe comment. Symptôme typique : une surface qui **change de teinte avec la distance** (porte de
  l'écoutille du cargo sombre de près, claire de loin : les LOD générés à l'import, vus de loin, passent par d'autres
  sommets). L'outil déplie ces faces (matériaux à nœud Normal Map seulement) par projection en boîte sur l'axe
  dominant de leur normale, en coordonnées du monde, à la densité des faces correctes du même matériau (~1 m par
  répétition) ; 56 136 faces de 77 objets corrigées le 18/10/2026 (portes des écoutilles, cloisons, tubes des silos,
  coque). À relancer après l'ajout de pièces modélisées sans dépliage.
- **Portables et écrans plats** (`tools/blender/build_station_devices.py`, envoyé au Blender ouvert avec
  `MODE = "preview"` sur un fichier vide : modèles seuls, aperçus dans `E:\Blender\apercus_equipements\`, fichier
  `E:\Blender\equipements_station.blend` ; `MODE = "apply"` sur `nuke_station.blend` : remplacement en place) :
  modèles procéduraux détaillés qui remplacent les maillages des 5 `Interactif_Ordinateur_*` et de 10
  `Interactif_Ecran_*` (01–08, 13, 14). **`Interactif_Ecran_Principal` (poste de pilotage) et les consoles
  de tir des silos n'y sont pas touchés** ; les petits écrans 16 et 17 qui l'encadraient sont supprimés du `.blend`.
  Portable 14" 16:10 noir mat (84 touches en relief, légendes
  `E:\Blender\textures\clavier_legendes.png` rendues par le script, TrackPoint, pavé, connectique, charnières à fûts,
  écran ouvert à 105°) sur un bras articulé (plateau à griffes, rotule, deux segments à chapes et molettes, platine
  murale vissée, câble) ; écrans à bordure fine, coque arrière bombée, plaque VESA et support mural inclinable
  (dalle à 5,5 cm de la paroi, comme avant). Chaque objet garde son nom, ses extras et son matériau `Ecran_XX` (dalle
  UV 0–1, (0, 0) en haut à gauche) ; il reçoit le repère de l'appareil en transformation d'objet (table `LAPTOPS` /
  `SCREENS` du script, rejouable). Nouveaux matériaux préfixés `Int_` (rangés à l'intérieur par `station.gd`).
  `Interactif_Ordinateur_05` (module Arrimage, paroi −Y à côté de l'écoutille du sas de sortie, écran `Ecran_16`) est
  créé par le script s'il manque (table `NEW_DEVICES`) ; `ONLY = [...]` limite le mode « apply » à quelques appareils.
  Penser à **enregistrer le `.blend`** après chaque modification exportée : un export depuis un fichier non
  enregistré se perd à la réouverture.
- **Écoutilles des modules de missiles** (`tools/blender/add_missile_hatches.py`, envoyé au Blender ouvert sur
  `nuke_station.blend`, rejouable) : le tunnel Habitation → silo (Ø 2,88 m) est rétréci au passage standard
  (Ø 1,32 m) par une cloison `Missile_<s>_Cloison_Ecoutille-col` (couronne grise, anneaux métal et jaune aux
  dimensions de ceux de l'écoutille avant de l'Habitation mais lisses : section arrondie, 96 segments ; paumelle
  copiée) à |y| = 2,55 m ; l'écoutille (`Charniere_Ecoutille_Missile_<s>`, `Interactif_Ecoutille_Missile_<s>`
  et sa collision `-convcolonly`) est une copie exacte de `Ecoutille_Habitation_AV`, avec sa piste
  `Fermeture_Ecoutilles` (−90° en 40 images) ; elle s'ouvre vers le silo (porte ouverte : elle dépasse un peu
  dans le dôme du silo).
- **Cadres des écoutilles axiales** (`tools/blender/smooth_hatch_rings.py`, rejouable) : les anneaux métal
  (r 0,655–0,76 m) et jaune (r 0,755–0,80 m) des cadres d'Habitation AR et AV, Commande AR, Arrimage AV et de
  l'écoutille cargo (32 segments à section carrée, très facettés) sont refaits en révolution lisse (section aux coins
  arrondis, 96 segments), comme ceux des écoutilles des silos ; épaisseurs d'origine.
- **Accessoires souples de l'Habitation** (`tools/blender/build_habitation_props.py`, rejouable ; d'après la
  cuisine de l'ISS photographiée par Thomas Pesquet) : volumes partant d'une boîte à coins arrondis maillée finement
  (`soft_box`), gonflée, matelassée ou froissée, posés sur les parois par lancer de rayons.
  `Interactif_Couchette` (maillage remplacé, extras gardés) : matelas molletonné, sac de couchage matelassé (coutures
  tous les 15 cm), col roulé, oreiller, glissière, deux sangles à boucle. `Habitation_Sacs` : sacs de transfert
  souples type CTB (toile blanche, glissière du rabat, bandes velcro bleues, poignée, étiquette, sandow et crochets).
  `Habitation_Cuisine_Accessoires` : sachets repas en aluminium, poches à boire (paille, pince), filet garni,
  bouteilles de condiments sous sandow, rouleau d'adhésif. Équipements de la cuisine, construits avant les
  accessoires (qui se posent dessus) : `Interactif_Rechauffeur` (mallette en aluminium satiné, joint, loquets,
  charnière, poignée, panneau de commande, câble), `Interactif_Distributeur_Eau` (type PWD : écran, clavier, repères
  chaud / ambiant, sortie à aiguille, flexible), `Habitation_Cuisine-col` (contenants souples à rabat velcro et
  sangles, boîtes repas en plastique à couvercle coloré sous sandow, table de repas au plafond : plateau vert sombre,
  rails, sandows, velcro, couverts). Les matériaux d'origine texturés (`Int_Panneau_Blanc`, `Int_Noir`,
  `Int_Voyant_Vert`) sont réutilisés sans être réécrits.
- **Câbles, tuyaux et gaines** (`tools/blender/build_station_cables.py`, rejouable) : objets `<Module>_Cables`
  (Habitation, Commande, Arrimage ; sans collision). Les tracés suivent les arêtes du couloir octogonal
  (22,5° + k·45°) à la surface trouvée par rayons et s'interrompent devant un obstacle (écran, cuisine, casiers,
  niches) en plongeant dans la jonction des panneaux. Faisceaux de 3–4 câbles colorés serrés par des colliers tous
  les 0,45 m, tuyaux Ø 22 mm sur pattes, gaines de ventilation annelées orange. Tubes à repère transporté
  parallèlement (un repère qui pivotait vrillait les câbles en zigzag).
- **WC et douche** (`tools/blender/build_wc.py`, `tools/blender/build_shower.py`, rejouables ; fonctions communes
  `tools/blender/props_kit.py`, dont le rideau `build_curtain`) : `Interactif_WC` d'après le WC russe de l'ISS
  (réservoir dans son arceau, cuvette à couvercle relevé jaune, boîtier de commande, entonnoir urinaire sur
  flexible, flexibles annelés, poire orange, cale-cuisses, lingettes) ; `Interactif_Douche` pour l'apesanteur (fond
  inox, bouche d'aspiration perforée et son flexible, passe-pieds, mitigeur chaud / froid, douchette sur flexible
  métallique, miroir, poignée, serviettes, produits de toilette sous sandow, lampe de niche) ; rideaux
  `Habitation_Rideau_WC` (regroupé à gauche) et `Habitation_Rideau_Douche` (à droite) : rail, anneaux, tissu double
  couche, clé de forme `Ferme` (poids exporté 0). La lampe de chevet de la couchette est retirée (trop près de la
  tête).
- **Lampes des couloirs** (`tools/blender/slim_lamps.py`, rejouable) : les plafonniers `Int_Lumiere` des panneaux
  diagonaux gardent leur longueur (0,74 m) mais passent de 0,43 à 0,15 m de haut ; matériau et lumières `Lum_*`
  (sur l'axe) inchangés : même éclairage. **Règle : rien ne doit recouvrir une lampe.** Le script le vérifie par
  une grille de rayons lancés depuis la face de chaque lampe (marge 2 cm, sur 15 cm) ; une lampe recouverte par un
  équipement fixe est déplacée le long du couloir vers la place libre la plus proche, sur la paroi nue (pas sur les
  barres ou rails du couloir) ; s'il n'y en a pas, elle est retirée (celle cachée derrière les casiers de
  l'Habitation). Les accessoires (`build_habitation_props.py`) et équipements (`build_station_devices.py` :
  `Interactif_Ecran_13` décalé de 39 cm) sont placés hors des lampes.
- **Hiloires des cloisons intérieures** (`tools/blender/section_coamings.py`, rejouable) : quatre cloisons
  (Habitation x = ±1,5, section centrale ; Commande x = 10,1 et 13,1, section de la cupola) ont un passage non
  circulaire (r 1,25 m dans les axes, 1,353 m dans les diagonales) que bordait un anneau fin (r 1,23–1,30) : par les
  fentes des diagonales on voyait la face arrière de la cloison, que Godot ne dessine pas (paroi « trouée »).
  L'anneau fin est remplacé par une hiloire de style sous-marin, objet séparé `<module>_Hiloire_<x>-col` :
  r 1,17–1,45 m, ±10 cm (Habitation, près de l'entrée des tunnels : r 1,18–1,40 m, ±7 cm), section aux coins
  arrondis, 96 segments, couronne de 32 vis hexagonales (acier bruni, rondelle inox) sur chaque face. Contrôle :
  rayons lancés dans Blender en ignorant les faces vues de dos, comme Godot.
  L'écran `Interactif_Ecran_07` (paroi −Y, 0,82 m de large) mordait dans l'hiloire x = 13,1 : son centre est passé
  de x = 13,5 à 13,65 (table `SCREENS` de `build_station_devices.py`).
- **Charnières des écoutilles** (`tools/blender/build_hatch_hinges.py`, rejouable) : à la place du pavé de
  8 × 10 × 50 cm, une charnière à cinq nœuds arrondis sur l'axe de la `Charniere_*` : nœuds 1, 3, 5, pattes vissées
  sur les deux faces, capuchons bombés de l'axe et graisseur dans le maillage de la porte (ils tournent avec elle) ;
  nœuds 2 et 4 et leur patte vissée vers le cadre dans l'objet fixe `Paumelle_<id>`.
- **Portes d'écoutille lisses** (`tools/blender/smooth_hatch_doors.py`, rejouable) : les cylindres des portes
  (disque, panneaux en relief, plaques de manœuvre ; 16 à 32 côtés, porte cargo comprise) sont refaits à 96 côtés
  (48 pour les petits) avec une tranche arrondie ; maillages marqués `tranche_lisse`. Les portes des silos, copies de
  `Ecoutille_Habitation_AV`, sont traitées aussi.
- **Sas entre modules** (`tools/blender/remove_sas_pads.py`, rejouable) : retrait des 4 plaquettes blanches
  posées au milieu des sas (une par écoutille axiale, loin de sa charnière). Le modèle a ses écoutilles ouvertes
  au repos et la porte ouverte les cachait ; fermées au démarrage du jeu, elles flottaient seules. La plaquette
  jumelle, contre le cadre à côté de la charnière (paumelle), est gardée.
- **Embouchure des tunnels côté silo** (`tools/blender/fix_missile_tunnels.py`, rejouable) : le tunnel est recoupé
  au ras du col du dôme intérieur (|y| = 3,36 m ; il dépassait de 1,04 m dans le dôme, et sa face extérieure
  `Coque_Silo`, non éclairée à l'intérieur, y faisait un contour noir et plat) ; la bride extérieure qui flottait
  dans le dôme est ramenée dehors (|y| 3,12–3,24) ; collerette `Missile_<s>_Collerette_Tunnel-col` en métal
  intérieur : boudin arrondi sur la jonction, bord rabattu sur le dôme, 36 vis à tête hexagonale en acier bruni sur
  rondelle inox (une tête de la teinte du bord ne laissait voir que ses flancs : des « chevrons » sombres).
- **Écoutilles « façon sous-marin »** (`tools/blender/build_submarine_hatches.py`, rejouable) : les 6 écoutilles
  axiales (Arrimage AV, Habitation AR et AV, Commande AR, Missile 1 et 2) et l'écoutille cargo reprennent le modèle de
  l'écoutille du sas, à l'échelle de leur passage (porte r 0,74 m sur la bague métal du cadre, dans le liseré jaune) :
  disque gris, bague satinée, bagues de l'axe, poignées en U jaunes sur les deux faces, volant et contre-volant
  (`Volant_<id>` sous `Pivot_Volant_<id>`, extras `volant`, `volant_tours` = 1,25 ; volant fixe sur l'écoutille cargo,
  verrouillée), nœuds de charnière, `Paumelle_<id>` fixe vissée sur le cadre, collision cylindrique. Les portes sont
  centrées sur l'axe du passage (les anciennes étaient décalées de 4 cm, des pièces dépassaient du cadre) ; la
  charnière est déplacée hors du bord de la porte (r 0,76 m, à mi-épaisseur), pour qu'elle ne morde plus dans le
  cadre en pivotant (animation `Fermeture_Ecoutilles` inchangée : rotations seules). Les scripts
  `smooth_hatch_doors.py` et `build_hatch_hinges.py` visaient les anciennes portes : **ne plus les rejouer**.
- **Matériaux réalistes texturés** (`tools/blender/pbr_kit.py`, chargé par `build_airlock.py` et
  `build_arrimage_extinguisher.py`) : photos PBR d'ambientCG (licence CC0), 1K JPG, dans `E:\Blender\textures\<id>`
  (couleur, rugosité, métallicité, normales OpenGL ; une répétition par mètre de coordonnées de texture) :
  `PaintedMetal001` (métal peint rayé : couleur recalculée par `repainted_color` en orange pour la platine de la
  valve, `Int_Valve_Orange`, et en jaune pour son cadre et sa manette, `Int_Valve_Cadre` ; JPEG dans
  `E:\Blender\textures\Generated`), `PaintedMetal004` (peinture rouge écaillée : corps des extincteurs,
  `Int_Extincteur`), `Metal012` (acier : boîtier et lunette du manomètre, bossages, conduit, socle de la valve,
  pièces des extincteurs ; `Int_Acier_Poli`, rendu satiné). Métallicité des peintures fixée à 0,15 et usure
  modérée : le métal nu des écaillures, très réfléchissant, faisait des traînées noires ; l'acier poli d'origine ne
  reflétait que du noir (rugosité × 2,4, métallicité 0,75).
  - **Impressions** (`pbr_kit.Print`) : textures dessinées par Blender avec de vrais caractères (police Arial),
    rendues en orthographique (EEVEE, vue « Standard » : couleurs exactes) dans `E:\Blender\textures\Generated`,
    plaquées sur des pièces qui portent leurs propres coordonnées de texture (`uv_quad`, `uv_disk`, `_label_band` ;
    les `Builder` des scripts les recopient au lieu de projeter) : cadran du manomètre de la valve (0–1,2 bar,
    graduations, chiffres, zones rouge et verte, « AIRLOCK PRESSURE »), plaques gravées en aluminium anodisé noir
    (« AIRLOCK EQUALIZATION VALVE », « CLOSED » →, « VENT » ↓, « PRESS », « VAC »), cadran du manomètre de
	l'extincteur, étiquette de l'extincteur (bandeau « FIRE EXTINGUISHER », « ABC DRY POWDER 6 kg », pictogrammes
	des classes A, B, C, mode d'emploi en quatre étapes, mentions, code-barres). Textes en anglais : marquages
	d'origine du matériel, pas de l'interface (hors fichiers de langue, comme les touches des portables).
  - Peintures 2K (`painted_metal_2k`) : valve orange et jaune propres (rayures légères, pas d'écaillures :
    `chips` 0), laque rouge brillante des extincteurs (rugosité × 0,55, quelques écaillures discrètes) ; `chips`
	dose la carte d'usure (presque binaire : un seuil ne la réduisait pas).
  - Valve : vis cruciformes à tête fraisée aux coins de la platine, lunette sertie chromée et verre bombé du
	manomètre, écrou hexagonal et poignée caoutchouc moletée de la manette, lunettes chromées des voyants, bride
	boulonnée du conduit d'évent.
  - **Extincteur réaliste** (`build_extinguisher`, poudre 6 kg : Ø 0,13 m) : corps embouti à fond bombé et
    épaulement (soudure, fond serti), pied en caoutchouc, col fileté en laiton, tête de robinet chromée à bouchon
    moleté, levier de percussion et poignée de portage à gaine caoutchouc, goupille de sécurité, scellé et sa
    plaquette, manomètre imprimé à zone verte sous verre, flexible à bagues serties qui contourne le corps par le
	côté et lance à cornet clipsée, étiquette imprimée enroulée, colliers et platine murale vissée. Dans le sas (paroi −X) et dans l'Arrimage : `build_arrimage_extinguisher.py` remplace le cylindre rouge
	sommaire du râtelier de la paroi diagonale (îlot `Int_Rouge` d'`Arrimage_Stockage-col`, retiré une fois) par
    `Arrimage_Extincteur` (9 kg, échelle 1,35, couché le long du module).
- **Rangements souples du module Arrimage** (`tools/blender/build_arrimage_stowage.py`, rejouable ; d'après la
  cuisine de l'Habitation) : les blocs rigides et lisses d'`Arrimage_Stockage-col` (deux rangées de casiers verts
  `Int_Caisse`, pavés beiges sous filet `Int_Sac_Beige` au sol, au plafond, sur la paroi +Y et sur trois diagonales,
  réservoirs d'eau octogonaux `Int_Bleu_Eau`, leurs sangles, filets et bandes jaunes) sont retirés une fois
  (propriétés `rangement_souple`, `sangles_casiers_retirees`) ; les casiers blancs rigides, la boîte métallique du
  plafond et les cadres jaunes restent. À leur place, objet `Arrimage_Rangement` (~150 000 faces) :
  - sacs de transfert souples type CTB de tailles variées (grille irrégulière par zone, profondeur variable, second
    rang de petits sacs çà et là) : toile tissée blanc cassé ou beige, coins très arrondis, gonflée et froissée,
    glissière du rabat, poignées cousues, pastilles velcro, étiquette ;
  - maintien : deux sangles d'arrimage plaquées sur les sacs (lancer de rayons), boucle à came, platines aux bouts
	(anciens casiers) ; ailleurs, filet de cordelette (mailles de 11 cm) drapé sur les sacs, bordure et anneaux ;
  - poches d'eau souples type CWC (tissu enduit bleuté, très gonflées, poignées, bouchon bleu, étiquette) à la place
    des réservoirs ;
  - `Interactif_Caisse_01`–`03` (maillages remplacés, noms et extras gardés) : caisses moelleuses en tissu
    matelassé, couvercle à glissière, sangle jaune de ceinture, poignée, étiquette ; `Arrimage_Sacs` : sac CTB ;
  - collisions : `Arrimage_Rangement_Collision-colonly`, un pavé par sac du premier rang.
  Textures (photos ambientCG CC0, 2K) par `pbr_kit.fabric_material` : `Fabric036` (toile tissée, recolorée en blanc
  cassé `Int_Toile_CTB`, beige `Int_Toile_Beige`, noir `Int_Sangle_Toile` ; 3 répétitions par mètre), `Fabric048`
  (tissu matelassé `Int_Toile_Matelassee`), `Fabric082A` (tissu enduit `Int_Toile_Enduite`) ; couleur 2K recolorée,
  relief 2K réenregistré en JPEG 85 et rugosité ramenée en 1K (les cartes d'origine pèsent jusqu'à 10 Mo), partagés
  par tous les matériaux d'un même tissu.
- **Départ dans la couchette** (`tools/blender/add_bunk_view.py`, rejouable) : repère `Point_Vue_Couchette`
  (collection `Reperes_Jeu`) au-dessus de l'oreiller, regard vers les pieds, un peu plongé vers le sac de couchage ;
  axes : +Y regard, +Z haut (après conversion glTF : −Z et +Y, la base d'une `Camera3D`).
- **Séparation du vaisseau cargo** (`tools/blender/build_cargo_undock.py`, rejouable) : les 9 objets `Cargo_*` sont
  enfants d'un pivot `Pivot_Cargo` placé sur le plan d'amarrage (face avant de `Cargo_Anneau`, x = −17,47) ; piste NLA
  `Separation_Cargo` : recul de 10 m selon −X (axe des modules) en 30 s (images 1–721 à 24 i/s), départ et arrêt en
  douceur (Bézier aux poignées automatiques). Image 1 = amarré ; jouée à l'envers : réamarrage.
- **Sas de sortie** (`tools/blender/build_airlock.py`, rejouable ; collections `Module_Sas` et `Int_Sas`) : module
  plus petit que les autres (Ø 2,5 m au lieu de 4,2 m), perpendiculaire à l'Arrimage, vers le bas (vers la Terre),
  sur l'ancien port nadir (x = −10,1). Les retouches de l'Arrimage sont faites une fois (propriétés `trou_sas`,
  `sas_degage`) : trappe verrouillée `Interactif_Trappe_Nadir` et port nadir extérieur retirés ; plancher
  (`Arrimage_Couloir-col`) et coque percés par recoupe plane locale (32 côtés, Ø 0,86 m ; un booléen exact supprimait
  la moitié des faces du couloir, maillage ouvert) ; sac beige, sangles et petite main courante posés sur l'ancienne
  trappe retirés.
  - Accès : écoutille ronde `Interactif_Ecoutille_Sas_Haut` dans le plancher (passage Ø 0,80 m, celui des écoutilles
	russes ; cadre métal et liseré jaune, poignées), charnière d'axe Y côté arrière : elle s'ouvre vers le haut,
	dans l'Arrimage (−90°). Volant façon sous-marin (dessus) et contre-volant (dessous) sur un même axe : objet séparé
	`Volant_Ecoutille_Sas_Haut` sous le pivot `Pivot_Volant_Sas_Haut` (enfant de la porte ; extras de la porte
	`volant`, `volant_tours` = 1,25). Puits de 1,8 m (plancher → plafond du sas), nervures, main courante.
  - Pièces métalliques du sas en `Int_Metal_Satine` (métal satiné sans texture) : `Int_Metal`, plastique à carte de
	normales, se découpait en mosaïque sur les anneaux (projection en boîte des coordonnées de texture). Faces
	superposées supprimées : le disque de l'écoutille du haut s'arrête sous l'arrondi de sa bague (r 0,425 m) ; la
	lèvre d'appui extérieure de la porte du bas est en retrait du col (r 0,512 m) : à rayon égal, leurs faces se
	disputaient l'affichage (rectangles gris ou noirs qui clignotaient).
  - Intérieur Ø 2,24 m : parois blanches à montants et nervures, quatre mains courantes, deux luminaires au plafond
    (lampes `Lum_Sas_1`, `Lum_Sas_2`, copies de `Lum_Arrimage_2`), fond conique.
  - Porte extérieure `Interactif_Ecoutille_Sas_Bas` (Ø 1,20 m, passage Ø 1,00 m) : hublot central (`Vitrage`, on voit
    la Terre défiler), face intérieure `Int_` à poignées jaunes et levier, face extérieure `Metal_Furtif` à poignée de
	sortie ; charnière d'axe X côté −Y : elle s'ouvre vers le bas, vers la Terre (−100°). Les deux portes suivent la
    convention de `Fermeture_Ecoutilles` (image 1 ouverte, 40 fermée).
  - `Interactif_Combinaison` (extras `type` « combinaison », `porte`) : scaphandre texturé debout contre la paroi +Y,
    dos contre son support. Maillage remplacé par `tools/blender/build_suit_model.py` (à rejouer après
	`build_airlock.py`, qui recrée l'ancienne combinaison procédurale d'après l'Axiom AxEMU, gardée dans le `.blend`
	sous `Interactif_Combinaison_Procedurale`) : modèle « Walking astronaut » (`E:\Blender\astronaute\`, hors dépôt ;
	58 000 triangles, textures 2K/1K `Combi_Astro_*`) figé en pose de repos, bras abaissés (72°, 12° vers l'avant) et
    raccourcis (bras ×0,99, avant-bras ×0,825 : mains en haut des cuisses), squelette et animations supprimés ;
    pare-soleil doré `Int_Combi_Visiere_Or` (faces noires du casque trouvées par lancer de rayons, complétées par leur
	zone de texture ; l'anneau du cou garde son métal sombre) ; hauteur de l'ancienne combinaison (1,93 m).
  - `Interactif_Porte_Combinaison` (extras `type` « porte_combinaison », `combinaison`) : support séparé (deux rails
    sur pattes, berceau du sac à sabots, crochets, cale-pieds), qui reste en place quand la combinaison est portée.
    **Casque porté** (`scripts/suit_helmet.gd`, nœud `Observer/Camera/Helmet`) : tant que la combinaison est portée
	(`Station.suit_changed`), on voit l'intérieur du casque, qui suit la tête : coque noire mate (sphère de 16,5 cm
	de rayon centrée 7 cm derrière l'œil), fenêtre ronde comme la visière vue de l'extérieur (ellipse dans le plan de
	la vue, demi-axes ±59° de côté, +37° en haut, −46° en bas vus de l'œil : bord haut en dôme, au ras du haut de
	l'image au centre et descendant sur les côtés ; la tablette sortie reste entière), joint gris foncé, visière
	transparente (`shaders/helmet_visor.gdshader` : voile gris-bleu vers les bords et en incidence rasante) et ses
	reflets en arc (passe additive `shaders/helmet_visor_glint.gdshader`, en haut à gauche et plus faible en bas à
	droite : nets sur fond sombre, discrets sur fond clair, jamais d'assombrissement). Maillage généré par le script
    (pas de modèle Blender), sans ombre portée ni collision, sur le calque `Station.INTERIOR_LAYER`.
    **Règle de jeu** (`station.gd`) : un clic sur la combinaison la fait disparaître
	(on l'enfile) ; un clic sur le porte-combinaison la remet en place.
  - `Interactif_Valve_Sas` (paroi +X, extras `type` « valve_sas », `animation`, `voyant_plein`, `voyant_vide`) :
	bien visible : platine orange vif (`Int_Valve_Orange`) dans un cadre jaune riveté (rivets bombés sombres), agrandie
	(échelle de l'objet 1,6 : 0,61 × 0,48 m hors tout, centre à z −4,05, entre les nervures), écartée de 4,5 cm de la
	paroi courbe sur un socle (à plat contre elle, ses bords s'y enfonçaient) ; platine à manomètre 0–1,2 bar (zone rouge près de 0, repère vert à 1 bar), manette quart de tour (vers la droite
	fermée, vers le bas ouverte ; elle ne passe jamais devant le cadran), voyants `Int_Voyant_Sas_Vert` (plein) et
	`Int_Voyant_Sas_Rouge` (vide), conduit d'évent. Pivots enfants `Pivot_Valve_Sas` et `Pivot_Aiguille_Sas` ; piste
    NLA `Depressurisation_Sas` (images 1–505 à 24 i/s) : manette ouverte (0,5 s), aiguille de 1 à 0 bar en 20 s
	(vidange exponentielle adoucie, constante de temps 20 s / 2,2 : elle ne traîne plus aux faibles pressions), manette refermée (0,5 s). **Règle de jeu** : la valve vide le sas, jouée à l'envers elle
	le remplit.
  - `Sas_Equipements` (sans collision) : trois sacs CTB sous sandows, extincteur (paroi −X, au-dessus de la
	bouteille : la paroi +X est réservée à la valve), bouteille d'oxygène et masque,
	longe et enrouleur, batteries de rechange sous sangle, sacoche d'outils, fiche de procédure.
  - L'ancien petit sas factice sous l'Habitation (`Habitation_Sas`, `_Fond`, `_Anneau` et la trappe verrouillée
	`Interactif_Trappe_Sas`, sans rien derrière) est retiré : ce module le remplace.
  - Extérieur `Sas_Coque-col` : col du puits et bride, coque `Coque_Silo` (UV cylindriques en mètres), deux cerclages,
	lèvre d'appui de la porte, paumelles, mains courantes de sortie (matériau `Poignee_EVA`).
  - Contrôle : rendus EEVEE et Workbench avec élimination des faces arrière (comme Godot). Dans EEVEE, la face
    extérieure de la porte du bas paraît blanche et dentelée sous un soleil rasant : artefact de rendu, la géométrie
    et les normales sont saines.
- **Import** (`station_spatiale.glb.import`) : échelle 1 (mètres), racine `StationSpatiale`, collisions par
  suffixes de noms (`-col` : collision statique concave + maillage ; `-convcolonly` : collision convexe seule),
  LOD générés, animations à 24 i/s, **Rotation_Panneaux** (plus jouée : suivi du soleil, voir plus bas) et **Balayage_Antennes** en boucle (les autres jouées
  une fois). Textures à côté du .glb, écrites par l'export Blender et versionnées avec leurs `.import`
  (compression GPU S3TC/BPTC, normal maps, UID stables) ; mêmes noms que l'ancienne extraction de Godot.
- **Post-import** (`tools/import/station_import.gd`) :
  - collisions des portes et trappes (enfants d'une `Charniere_*` animée) converties en `AnimatableBody3D` (dont
	`station.gd` coupe `sync_to_physics` : voir « Collisions des portes et trappes » plus bas) ;
  - collisions des objets `Interactif_*` qui n'en ont pas (tubes des silos, consoles, caisses, portables, écrans…) :
	forme convexe simplifiée (`StaticBody3D` « Collision ») calculée **à l'import** : faite au démarrage
	(`Station._add_interior_collisions`, gardé en secours), elle coûtait 3,5 s sur le fil principal (77 objets, dont
	~1,6 s pour les portables et écrans détaillés) ;
  - pistes constantes retirées des animations : l'export Blender met dans chaque action tous les objets animés
    (75 pistes) ; il ne reste que les pistes utiles (Rotation_Panneaux 4, Balayage_Antennes 3, Fermeture_Ecoutilles
    6, Ouverture_Trappes 48, Retraction_Radiateurs 12, Lancement_Missile 5). Sans cela, jouer une animation
    remettrait aussi en place tous les autres objets animés.
  - **Piège** : l'éditeur garde le script de post-import en cache ; modifié hors de l'éditeur, il n'est pas relu à
	l'import suivant (relancer l'éditeur). Toucher le `.import` ne relance pas l'import : il faut changer un
    réglage ou réexporter le .glb.
- **Métadonnées** : les propriétés personnalisées Blender (extras glTF) sont dans `get_meta("extras")`, un
  dictionnaire ; les nombres y sont des flottants (`silo: 1.0`). `ouvrable` (vrai pour les écoutilles et trappes
  animées, faux pour l'écoutille cargo, verrouillée).
- **Scène héritée** `scenes/station_spatiale.tscn` : base de tout le jeu (script, réglages des lumières, etc.).
  Aperçu seul : `scenes/debug/station_preview.tscn` (soleil, fond noir, caméra extérieure).
- **Pilotage** (`scripts/station.gd`, classe `Station`, racine de la scène héritée). Rien n'est codé en dur : objets
  trouvés par leurs extras (`type` : `ecoutille`, `trappe_silo`, `trappe` ; `id`, `charniere`, `silo`, `tube`,
  `ouvrable`), angles et durées lus dans les animations Blender. Un objet seul est piloté par un Tween qui rejoue
  ses pistes ; un groupe entier dans le même état (les 48 trappes, les 4 radiateurs ; plus les écoutilles, fermées au démarrage : une par une) par
  l'animation complète. Chaque animation a son propre AnimationPlayer (créé au démarrage, bibliothèque partagée) :
  les antennes tournent en boucle pendant les autres mouvements.
  - **Panneaux solaires : suivi du soleil, station furtive** (`Station._track_sun`, `track_sun_panels`). L'animation
	Blender `Rotation_Panneaux` (rotation continue, trop rapide) n'est plus jouée : à chaque image, les 4 pivots
	`Pivot_Panneau_*` (axe Z du modèle, face des cellules du côté +Y au repos) tournent pour présenter les cellules
	au soleil (projection de la direction du soleil, lumière `Sun`, sur leur plan de rotation) : ils suivent donc le
	soleil à sa vitesse apparente (un tour par orbite). **Règle de furtivité** : le dessous des panneaux porte un
	cache qui les empêche de briller vus de la Terre, et la face des cellules ne doit jamais être tournée vers le
	sol ; elle reste au moins 2° au-dessus de l'horizon local (`panel_horizon_margin_deg`, verticale = direction
	Terre → station, nœud `Earth`). Quand le soleil passe sous l'horizon de la station, les panneaux s'arrêtent à
	cette limite. Vitesse bornée à 6°/s (`panel_max_speed_deg`), pour éviter un saut quand la date ou l'heure change.
  - États au repos (modèle) : écoutilles ouvertes, trappes des silos fermées, radiateurs déployés. **Règle de jeu :
	au démarrage, le passage Habitation – Commande est ouvert** (`Ecoutille_Habitation_AV`, `Ecoutille_Commande_AR` :
	`start_open_hatches`) **et les 6 autres écoutilles ouvrables sont fermées** (`start_hatches_closed`) : Arrimage AV,
	Habitation AR, les 2 des modules de missiles (`Ecoutille_Missile_1`, `_2`) et les 2 du sas de sortie
	(`Ecoutille_Sas_Haut`, `Ecoutille_Sas_Bas`). Écoutille cargo verrouillée (`ouvrable` faux, rien n'est modélisé
    derrière) : ses commandes renvoient `false`.
  - **Sas de sortie** (`Station`, groupe « Sas de sortie ») : une porte intérieure (`airlock_inner_hatch`,
	`Ecoutille_Sas_Haut`, plancher de l'Arrimage) et une porte extérieure (`airlock_outer_hatch`,
	`Ecoutille_Sas_Bas`, vers la Terre). **Règle de jeu : aucun verrouillage**, la sécurité est l'affaire du joueur :
    les portes, les écoutilles et la valve se manœuvrent librement. La valve (`Interactif_Valve_Sas`) est un
	robinet : un clic l'ouvre pour vider le sas (ou pour le remplir s'il est vide ; un clic pendant un cycle
	l'inverse) et elle se referme d'elle-même une fois la pression visée atteinte. Manette : début de
    `Depressurisation_Sas` (fermée → ouverte en 0,5 s) ; aiguille du manomètre : pression du sas calculée par
    `StationAtmosphere`, placée sur sa piste (rotation cumulée de la piste qui tourne le plus). Le sas est plein au
    démarrage. Voyants : vert allumé sas plein, rouge allumé sas vide, rouge clignotant (0,8 s) pendant un cycle
    (`indicator_energy`, `indicator_blink_s` ; copies émissives des matériaux `extras.voyant_plein` /
    `voyant_vide`). API : `get_airlock_pressure()`, `get_airlock_valve_mode()` (−1 vidange, +1 remplissage, 0),
    `is_airlock_cycling()`, `is_airlock_filling()`, `set_airlock_pressurized(full)`, `toggle_airlock_pressure()`,
    `airlock_step(pression, secondes)` (courbe de vidange du manomètre), `set_airlock_gauge(pression)` ; signaux
    `airlock_changed(pressurized)` (fin de cycle) et `hatch_moving(id, open)` (une écoutille commence à bouger).
  - **Air de la station** (règles de jeu, `scripts/station_atmosphere.gd`, classe `StationAtmosphere`, nœud
    `StationAir` de `orbit_view.tscn`) : une pression (0–1) par volume : modules Commande, Habitation, Arrimage,
	Missile 1 et 2, jonctions avant et arrière, sas (table `ZONES` : boîtes en coordonnées Blender, volume d'air,
	modules comptés). Les écoutilles intérieures isolent les modules ; **deux volumes communiquent quand
	l'écoutille qui les relie est ouverte** (table `HATCHES` ; état visé : une écoutille qui commence à s'ouvrir
	communique déjà, une écoutille qui commence à se fermer isole déjà). Les ensembles qui communiquent et le
	chemin du courant vers la sortie sont recalculés au mouvement d'une écoutille (signaux `Station.hatch_moving`
	et `hatch_changed`), pas à chaque image.
	- Des volumes qui communiquent ont la même pression (moyenne pondérée par les volumes d'air, équilibrée en
	  `equalize_s`, 0,5 s).
	- **Vidange par la valve** : la pression baisse dans **tous les volumes qui communiquent avec le sas**, sur la
	  courbe du manomètre (20 s pour le sas seul ; exponentielle adoucie, plus rapide aux faibles pressions).
	- **Remplissage par la valve** (porte extérieure fermée : sinon l'air repart dans l'espace) : **réserve
	  d'oxygène illimitée**, débit constant : 8 s de vide à plein pour le sas seul (`valve_fill_s`). **Règle de jeu :
	  seul le sas fournit de l'air à la station** : un module isolé garde sa pression, il faut l'ouvrir jusqu'au sas
	  pour le remettre en pression (bouteilles d'air dans certains modules : prévues plus tard).
	- **Durées par la valve, toute la station ouverte : 35 s au plus**, vidange comme remplissage
	  (`station_valve_s` ; mesuré : 34,4 s et 34,7 s) ; entre le sas seul et la station entière, selon la racine de
	  la part du volume d'air ajouté.
	- **Vidange par la porte extérieure** : tout l'ensemble qui communique avec l'espace se vide, sur la même
	  courbe, en `door_vent_s` (1,5 s) pour le sas seul.
	- Porte extérieure : durée multipliée par la racine du volume d'air rapporté à celui du sas (toute la station
	  ouverte : ~8 fois, ~12 s).
	- **Alerte rouge automatique** (règle de jeu, `StationAtmosphere._update_alert`) : dès que la porte intérieure
	  et la porte extérieure du sas sont ouvertes en même temps (dès le clic), la station passe en alerte rouge
	  (`Station.set_alert`). L'alerte se lève d'elle-même dès que la porte extérieure est fermée **et** que la
	  pression est revenue à 0,80 (`alert_clear_pressure`, arrondie au centième comme sur les témoins) dans le sas et
	  dans tout ce qui communique avec lui ; un module isolé (écoutilles fermées) garde sa pression, affichée par son
	  témoin, sans retenir l'alerte. L'alerte d'avant est rétablie (sauf si le joueur en a choisi une autre
	  entre-temps). Pas d'alerte sans courant (« Plus de lumière »).
	- **Témoins de pression** (`scripts/pressure_gauges.gd`, nœud `PressureGauges`) : dans chaque module (Commande,
	  Habitation, Arrimage, Missile 1 et 2), près de son écoutille d'entrée, un afficheur mural de 34 × 22 cm
	  (`gauge_scale` 2 : à taille réelle, 17 × 11 cm, il ne se lisait pas à travers le module) construit au
	  démarrage (`Temoin_Pression_<module>`, enfant de la station) : pression du module en bar, voyant et chiffres
	  verts au-dessus de 0,9, orange au-dessous, rouges clignotants sous 0,3 (perte de connaissance sans
	  combinaison) ; plaque « CABIN PRESSURE » (marquage du matériel, hors fichiers de langue). Emplacements relevés
	  par lancer de rayons dans le modèle (table `GAUGES`) : panneau de paroi à 30° au-dessus de l'horizontale, sous
	  les tuyaux et les luminaires ; dans les modules de missiles, cloison de l'écoutille, côté opposé au battant.
	  Le sas a le manomètre de sa valve.
  - **Jets d'air** (`scripts/air_vent_fx.gd`, nœud `AirVentFx`, placé de lui-même à la porte extérieure, +Y vers
	l'espace ; `StationAtmosphere.hatch_center`, `hatch_axis_from`) : porte extérieure ouverte et de l'air dans le
	sas (et ce qui communique avec lui), l'air jaillit vers l'espace. Détendu dans le vide, il se refroidit et son
	humidité se condense en glace : brouillard blanc, visible là où il est éclairé. Dans le sas, brouillard aspiré
	vers le centre de la porte et poussé dehors (calque `Station.INTERIOR_LAYER` : lampes du sas, rouges en
	alerte) ; dehors, panache comme d'un pot d'échappement (16 à 34 m/s, cône de 16°, ~4 m de large en fin de vie,
	0,7 s), éclairé par le soleil. Intensité = pression du sas (nombre de particules et vitesse) : bouffée violente à
	l'ouverture, puis le jet faiblit jusqu'à s'éteindre (sous 2 %) ; bien plus long si toute la station communique.
	**Son** : souffle généré au démarrage (sifflement et grondement en boucle de 3 s, fondu au raccord), à la porte
	côté intérieur, bus SFX, plus fort et plus aigu à forte pression ; il ne porte que dans l'air : volume × racine
	de la pression du volume de l'auditeur (rien dans le vide, ni dehors).
  - **Expulsion** (règle de jeu, `StationAtmosphere.flow_at`, `scripts/airlock_hazard.gd`) : porte extérieure
	ouverte, un courant d'air porte l'observateur vers la sortie **depuis n'importe quel volume qui communique avec
	l'espace** : de volume en volume, vers l'écoutille suivante sur le chemin de la porte extérieure (visée 0,8 m
	au-delà du passage), à travers la station jusque dans le vide. Vitesse : pression de l'ensemble × de 3 m/s (sas
	seul, `flow_speed_sas`) à 12 m/s (les 5 modules reliés, `flow_speed_max`), proportionnelle au nombre de modules
	reliés : **toutes les écoutilles ouvertes avant la porte extérieure, l'expulsion est la plus rapide** ; elle
	faiblit à mesure que l'air s'échappe. **Le joueur garde ses commandes** (déplacement, regard) et peut fermer une
	écoutille au clic pendant l'expulsion : fermée entre lui et la sortie, son volume ne communique plus avec
	l'espace et le courant s'arrête (il garde la pression qui lui reste). La poussée rejoint le courant en 0,3 s
	(`flow_response_s`) et retombe en 0,8 s dans l'air calme (`still_air_response_s`) ; contre une paroi, elle glisse
	le long d'elle (`Observer.set_air_flow`). Dehors (sorti par la porte extérieure : hors de tous les volumes, le
	dernier étant le sas ; `Station.observer_outside`, flashs et exposition), plus d'air : l'élan est gardé ;
	combinaison enfilée, son propulseur dorsal (SAFER) l'amortit en 3 s (`safer_s`) et le joueur peut revenir.
	Cupola : recoin du module Commande, le courant y vise d'abord l'ouverture vers le module (point de passage de la
	boîte secondaire). Tests depuis n'importe quel module : boutons « Ouverture totale » / « Fermeture totale » du
	panneau de debug (F4 ; toutes les écoutilles ouvrables, porte extérieure du sas comprise,
	`Station.set_all_hatches_open`). Simulation en vidéo depuis la cupola, avec ou sans combinaison :
	`tools/bench/expulsion_probe.tscn` (Movie Maker : `--write-movie <fichier.avi> --fixed-fps 30 --quit-after 720`,
	argument `-- --suit` pour la combinaison ; hors enregistrement, temps d'image écrit en console chaque
	demi-seconde : 8,3 ms (120 im/s) tout le long, pointes à 15–18 ms à la sortie ; le compteur des vidéos mesure
	la vitesse d'enregistrement, pas celle du jeu). Coût de l'animation des écoutilles :
	`tools/bench/hatch_probe.tscn` (aucun : 8,3 ms, physique 0,2 ms, 4 écoutilles en mouvement).
  - **Mort** (règles de jeu, `AirlockHazard`) : **sans combinaison, dans le vide ou presque** : pression du volume
	sous `death_pressure` (0,3 bar : vidange par la valve avec la porte intérieure ouverte, expulsion…) ou dehors.
	**Avec la combinaison, on ne meurt jamais.** Le corps reste porté par le courant après la mort (expulsé, il
	traverse la station et sort).
  - **Séquence de mort** (`scripts/death_sequence.gd`, classe `DeathSequence`, créée par `AirlockHazard`) : commandes
	coupées (déplacements, regard, interactions, tablette masquée ; le corps reste porté par le courant d'air ;
	dehors, le regard se tourne vers la station qui s'éloigne en roulant lentement ; yeux fermés après 1,2 s sur
	place, 3,5 s emporté, jusqu'à 3 s de plus quand on s'éloigne lentement), puis la vue se ferme comme des yeux qui se ferment
	(`shaders/eyelids.gdshader`) : deux paupières noires aux bords flous, en arc (les coins se ferment avant le
	centre), qui arrivent du haut et du bas, vue qui se brouille (flou de l'écran) et s'assombrit par les bords ; un
	dernier effort les rouvre un peu avant la fermeture (3,4 s). Écran noir : **écran de mort**
	(`scenes/ui/death_screen.tscn`, `scripts/ui/death_screen.gd`) : « Vous êtes mort » (`DEATH_TITLE`) et le bouton
	« Retour au menu » (`DEATH_BACK_TO_MENU`) sur fond noir ; le nœud `Backdrop`, vide, accueillera une animation en
	arrière-plan comme l'écran de démarrage.
  - **Combinaison** (règle de jeu) : un clic sur la combinaison l'enfile (elle disparaît, sa collision est coupée) ; un
	clic sur son support (`Interactif_Porte_Combinaison`) la remet en place. API : `is_suit_worn()`,
	`set_suit_worn(worn)`, `airlock_part_for(node)` ; signal `suit_changed(worn)`. Sans elle, ouvrir la porte
	extérieure est mortel (voir « Mort dans le sas »).
  - **Vaisseau cargo** : `set_cargo_docked(docked)` joue `Separation_Cargo` (recul de 10 m en 30 s) ou, à l'envers,
	le réamarrage ; `is_cargo_docked()`, `is_cargo_moving()`, signal `cargo_changed(docked)`. Bouton « Cargo » du
	panneau de debug (F4).
  - Écoutilles : `open_hatch(id)`, `close_hatch(id)`, `set_hatch_open(id, open)`, `toggle_hatch(id)`,
	`set_all_hatches_open(open)`, `is_hatch_open(id)`, `is_hatch_opening(id)` (état visé), `hatch_ids()`,
	`hatch_id_for(node)` (écoutille d'une porte ou de son corps de collision) ; signal `hatch_changed(id, open)`.
	Comme pour les trappes, une demande inverse en cours de mouvement repart de la position actuelle. Écoutille à
	volant (extras `volant`, `volant_tours`) : à l'ouverture, le volant tourne d'abord (déverrouillage, `volant_tours`
	tours en `hatch_wheel_s` = 0,9 s) puis la porte pivote ; à la fermeture, la porte puis le verrouillage.
  - **Écoutilles à la souris** (`scripts/hatch_interaction.gd`, nœud `HatchInteraction` de `orbit_view.tscn`) :
	rayon de la caméra contre les collisions, à 2,5 m au plus (`reach_m`) ; survol d'une écoutille ouvrable : bulle
	« Ouvrir l'écoutille » / « Fermer l'écoutille » (`HATCH_OPEN`, `HATCH_CLOSE`) ; clic gauche : ouverture ou
	fermeture animée (rotation de la charnière, durée de `Fermeture_Ecoutilles`). Inactif au poste de pilotage.
	Même interaction pour la combinaison (`SUIT_PUT_ON`), son support (`SUIT_STOW`) et la valve
	(`AIRLOCK_DEPRESSURIZE`, `AIRLOCK_REPRESSURIZE`, selon son état visé).
  - **Rideaux** (WC et douche de l'Habitation ; objets Blender d'extras `type` « rideau », `id` `Rideau_WC`,
	`Rideau_Douche`) : **fermés au démarrage** (`start_curtains_closed`) ; même interaction à la souris (bulle « Ouvrir le rideau » /
	« Fermer le rideau », clés `CURTAIN_OPEN`, `CURTAIN_CLOSE`), mouvement de 0,9 s (`curtain_duration_s`) qui fond
	la forme de base (ouvert, regroupé) dans la clé de forme `Ferme` (déployé), un clic pendant le mouvement
	l'inverse. API : `toggle_curtain(id)`, `set_curtain_closed(id, closed)`, `is_curtain_closing(id)`,
	`curtain_ids()` ; signal `curtain_changed(id, closed)`. Pas de collision (on traverse un rideau) : une zone de
	clic `Area3D` (calque de collision 20, `CURTAIN_LAYER`), boîte du tissu calculée depuis les sommets de la base et
	de la clé de forme, suit le mouvement ; le rayon du clic interroge aussi les zones (`collide_with_areas`).
  - Collisions des portes et trappes : `AnimatableBody3D` enfant de la porte, **sans `sync_to_physics`**
	(`Station._fit_door_collision`). Avec, le corps ne suivait que ses propres déplacements, pas ceux de la charnière
	parente : il restait figé dans la pose de l'import (porte fermée traversable, porte ouverte qui bloquait encore).
  - Trappes des silos : `open_silo_door(silo, tube)`, `close_silo_door(…)`, `set_all_silo_doors_open(open, silo)`
	(silo 0 : les deux) ; signal `silo_door_changed(silo, tube, open)`. Une demande inverse en cours de mouvement
	repart de la position actuelle (état visé `target`) ; le lancement reprend la trappe où elle est (déjà ouverte par
	le choix du tube : pas de saut).
  - Gyrophare : `set_silo_beacon(silo, tube, on)` (groupe « Gyrophare des silos ») : lampe émissive de 7 cm et
	`OmniLight3D` rouge (énergie 4, portée 6 m, ombres, pas sur les surfaces intérieures) juste sous la coque, à
	0,75 m de la trappe vers l'extérieur de la rangée ; éclat de 0,35 du cycle de 0,9 s, montée et descente douces.
  - **Missiles** (`launch_missile(silo, tube)`, `can_launch`, `available_tubes()`) : un seul missile est modélisé
	(tube 1_12) ; pour un autre tube, il est copié et placé à l'identique par rapport au `Point_Lancement` du tube
	(repère du tube × repère du tube 1_12⁻¹ × missile animé). Le lancement rejoue `Lancement_Missile` : ouverture de
	la trappe (si elle est fermée, avec les angles de la trappe du tube), descente, allumage de la tuyère à 2,9 s
	(`Point_Tuyere` : échelle 0 → 1 ; signal `missile_ignited`), jusqu'à ~30 m sous la station (5 s ; la dernière
	clé à pleine échelle, avant celle où Blender annule l'échelle : le missile ne rétrécit jamais). Signal
	`missile_released(silo, tube, missile, velocity)` : le récepteur prend en charge le missile (nœud, propulsion
	allumée) et sa vitesse de sortie pour la suite du vol (voir « Vol du missile » ci-dessous) ; sans récepteur, la
	station le masque. Chaque tube ne tire qu'une fois. `tube_ids()` et `tube_position(silo, tube)` (repère de la
	station : +X avant, +Z droite) servent au panneau des silos ; la station est dans le groupe `Station.GROUP`.
  - **Propulsion du missile** (`scenes/effects/missile_exhaust.tscn`, script `scripts/missile_exhaust.gd`, classe
	`MissileExhaust`, instancié sous `Missile_Balistique_1_12/Point_Tuyere_1_12` dans la scène héritée : chaque copie
	du missile en hérite). Moteur à propergol solide dans le vide :
	- cœur : cône additif de 2,6 m (`shaders/missile_exhaust_core.gdshader`), éblouissant au ras de la tuyère
	  (blanc-jaune, luminance HDR 24 : glow), qui s'élargit et vire à l'orange ;
	- panache : sans air pour le confiner, le gaz se détend très largement : 900 particules additives
	  (`shaders/missile_exhaust_particle.gdshader`), 35 à 70 m/s, demi-angle 40°, durée de vie 0,4 s ; elles
	  naissent petites (~25 cm, moins que la tuyère) juste derrière sa sortie, puis grossissent jusqu'à ~8 m (à 65°
	  et nées à 1 m, elles enveloppaient la coque : le gaz semblait sortir des flancs du missile) ; opacité qui chute vite (densité en 1/r²) : voile translucide, **pas de traînée de fumée** ;
	- lumière : `OmniLight3D` orange qui vacille (combustion irrégulière), 40 m de portée, avec ombres (quelques
	  secondes seulement), qui n'éclaire pas les surfaces intérieures (calque `INTERIOR_LAYER`).
	- Position : `Station.launch_missile` place `Point_Tuyere` à 3,5 m du centre du missile, 0,5 m derrière l'arrière de
	  son maillage (bout +Y à 3 m, la pointe est en −Y ; `nozzle_offset_m`, réglage visuel) : dans le modèle réexporté, ce repère est au centre du missile, et la propulsion semblait
	  sortir du milieu de la coque.
	- Allumage : échelle de `Point_Tuyere` (0 → 1 à 2,9 s, cf. `Lancement_Missile`) ; l'effet en hérite et naît à
	  la taille zéro. Direction du jet : à l'opposé du déplacement du missile (le +Z de `Point_Tuyere_1_12`, annoncé
	  comme direction du jet, est horizontal dans le modèle : le missile descend, sa tuyère est en haut et le jet
	  monte vers la station).
	- En vol (`enter_flight`) : panache en coordonnées locales (il suit le missile et rétrécit avec lui ; le panache
	  en coordonnées du monde s'éteint de lui-même), direction du jet imposée (`jet_direction`, opposée à la pointe),
	  lumière atténuée (`light_scale`).
  - **Vol du missile** (`scripts/missile_flight.gd`, classe `MissileFlight`, créée par `nuke/launch_control.gd` à
	`missile_released`, enfant de la scène) :
	- **durée du vol** (règle de jeu, `flight_time_range` de `nuke/launch_control.gd`) : proportionnelle à la
	  distance réelle œil → cible, de **20 s** quand on vise le nadir (distance = altitude) à **2 min** quand on vise
	  l'horizon (√((R + h)² − R²), ~2 290 km à 400 km d'altitude). Plus rapide que la réalité (une frappe depuis
	  l'orbite, qui doit d'abord casser la vitesse orbitale de 7,7 km/s, prend plusieurs minutes), pour garder la
	  tension d'une attente de torpille. En 2 min, la station parcourt ~900 km : une cible visée au nadir explose
	  derrière elle ;
	- **phase spatiale** (jusqu'au point d'entrée dans l'atmosphère), en mètres réels, dans le repère de la station :
	  comme un vrai missile, il **manœuvre pendant la combustion** (`MissileFlight._space_point`). **Le moteur
	  brûle 9 s** : le missile part dans l'axe de son tube (ligne droite de Blender, vitesse de sortie ~32 m/s,
	  30 m/s²), puis tourne vers le point d'entrée (100 km au-dessus de la cible, qui suit la Terre en mouvement) en
	  accélérant (courbe d'Hermite, vitesses continues). Moteur éteint (en 0,5 s, `MissileExhaust.throttle` :
	  panache, flamme, lumière et halo s'éteignent), il file sur sa lancée en ligne droite à vitesse constante
	  jusqu'au point d'entrée, où il arrive à l'heure prévue (vitesse de croisière V telle que la distance L =
	  V · (9 s / 2 + durée de la croisière)). La pointe (−Y du missile) suit la direction du déplacement (1,2 rad/s
	  au plus). On voit donc le missile partir vers la zone d'impact, puis on le perd de vue bien avant l'impact
	  (à quelques dizaines de km de la station à l'extinction) ;
	- **rentrée atmosphérique** (les derniers 20 % du vol, entre 6 et 12 s ; `scripts/reentry_streak.gd`,
	  `shaders/reentry_streak.gdshader`) : du point d'entrée au point d'explosion (500 m au-dessus de la cible), en
	  ralentissant, **dans le prolongement du vol** : le point d'entrée est en amont de la cible, du côté de la
	  station. Pente : 0,7 × la hauteur de la station vue depuis la cible (ligne de visée), bornée entre 8° (rentrée
	  rasante depuis l'orbite : cibles lointaines, ~460 km de traînée lumineuse) et 25° (tête de missile balistique :
	  cibles proches, ~150 km). Plus plate que la ligne de visée, la traînée arrive à l'écran du bas, du côté de
	  la station, et monte vers la cible, dans le sens où le missile est parti (pente égale à la ligne de visée :
	  traînée vue en bout, réduite à un point ; plus raide : elle semblerait tomber du haut de l'écran). La durée de
	  la rentrée, elle, est compressée comme tout le vol (6 à 12 s au lieu de 1 à 2 min) : la tête paraît 5 à 10 fois
	  plus rapide qu'en réalité (~7 km/s). Cible au
	  nadir : arrivée de l'arrière, le long de la trace au sol. La tête s'échauffe comme un météore vu depuis
	  l'ISS : tête blanc-bleuté éblouissante (halo additif, rayon 1,5 km, au moins 6 pixels) et traînée de plasma de
	  3,5 s de trajet, effilée, qui se refroidit du jaune à l'orange puis au rouge
	  sombre, avec des bouffées d'ablation et un léger vacillement. Éclat selon l'altitude : apparition sous 75 km,
	  plein de 60 à 30 km, extinction vers 10 km (la tête a ralenti). La traînée est mélangée par opacité (et non
	  additive) en couleurs HDR : elle reste orange devant des nuages blancs en plein jour, et déborde en halo.
	  Rendue à l'échelle exacte de la Terre : la Terre et les nuages la masquent ;
	- le vol suit l'horloge du jeu (`Orbit.time_scale` : pause, accélération) ; à l'arrivée, signal `arrived` →
	  explosion (`NukeLauncher.launch_at`), le missile est libéré ;
	- **rendu à l'échelle préservant la perspective** (la même astuce que la Terre à 1/10 000 : un objet K fois plus
	  proche et K fois plus petit paraît identique). À une distance réelle d de la caméra, le missile est dessiné à
	  taille réelle jusqu'au palier F (90 % de la distance de la couche nuageuse dans sa direction, ~35 m sous la
	  cupola), puis sur ce palier réduit de F/d (toujours devant les nuages et la Terre), enfin à l'échelle exacte de
	  la Terre quand d/10 000 dépasse F (bas de l'atmosphère : les nuages le masquent comme il se doit) ;
	- halo (`shaders/missile_glow.gdshader`, disque additif face à la caméra) : rayon réel 2,5 m, jamais moins de
	  4 pixels à l'écran, apparaît entre 150 m et 1,5 km (de près, la flamme et le panache suffisent), s'éteint avec
	  le moteur ;
	- lumière du moteur sur la station : pleine jusqu'à 40 m, puis en 1/d².
  - Radiateurs : `set_radiator_deployed(id, deployed)` (`Radiateur_D15`, `D21`, `G15`, `G21`),
	`set_all_radiators_deployed`, `set_stealth(enabled)` ; signal `radiator_changed`.
  - **Éclairage intérieur** (réglages dans le groupe « Éclairage intérieur » de `Station`) : les 30 lampes
	ponctuelles du modèle (`Lum_*`, importées à 6 522 d'énergie et 4 096 m de portée) sont recalibrées au démarrage :
	blanc 4 500 K (luminaires LED de l'ISS en mode jour), énergie 1,2 × le paramètre « Éclairage intérieur »
	(`GameSettings.interior_light`, voir « Écran de démarrage, paramètres et langues ») × 0,75 dans l'ombre de la
	Terre (mode nuit, `night_light_ratio`), portée 5,5 m,
	atténuation 1,3, reflets 0,4, **sans ombres**.
	- **Niveau d'alerte** (règle de jeu, `Station.set_alert`, enum `Alert` : `NONE`, `YELLOW`, `ORANGE`, `RED`) :
	  dans les situations critiques, les luminaires blancs de la station passent en **jaune**, **orange** ou
	  **rouge** (`alert_colors`, lumière projetée des lampes `Lum_*` et émission des bandeaux `Int_Lumiere` ; les
	  feux rouges des rails gardent leur couleur), avec un fondu de 0,8 s (`alert_fade_s`) ; en alerte rouge, la
	  puissance pulse lentement (−30 % d'amplitude, période 1,4 s : `red_alert_pulse`, `red_alert_period_s`).
	  Cinquième niveau, **« plus de lumière »** (`BLACKOUT`) : bandeaux et lampes s'éteignent (même fondu), sauf
	  une lampe sur quatre (`emergency_light_every`) qui reste en LED de secours, très faible (énergie 0,06,
	  `emergency_light_energy`) et froide (`emergency_light_color`), pour deviner les modules ; la lumière ambiante
	  de l'`Environment` (qui n'éclaire que la station) et les **écrans** (`Ecran_*`, émission coupée, dalle
	  presque noire) s'éteignent avec le même fondu, et les bandeaux éteints deviennent gris sombre (leur albédo
	  blanc paraîtrait allumé sous les LED) ; seuls les voyants du modèle (`Int_Voyant_*`, émissifs) restent
	  allumés. Les déclencheurs (quelles situations déclenchent quel
	  niveau) restent à définir ; le panneau de debug (`nuke/debug/`, F4 en jeu) permet d'essayer chaque niveau. Sans ombres, une lampe traverse les parois : elles n'éclairent donc que les surfaces intérieures,
	sur le calque `INTERIOR_LAYER` (bit 11, `light_cull_mask`). Est intérieur un matériau dont le nom commence par
	`Int_` ou `Ecran_` ; hublots et vitrages sont des deux côtés ; tout le reste est extérieur. Les 14 coques mixtes
	(surface `Coque_Silo` dehors, `Int_Coque` dedans, dans un même objet) sont doublées : l'original ne montre que
	ses surfaces extérieures, une copie `<nom>_Interieur` (même maillage, LOD compris, sans ombre portée) ses
	surfaces intérieures ; les surfaces cachées ont un matériau qui place leurs sommets hors du champ (aucun pixel
	calculé). L'extérieur n'est éclairé que par le soleil (et le flash des explosions).
  - **Vitrage de la cupola sans reflet** (`Station._matte_glass`) : le reflet de l'environnement (disque solaire du
	ciel) ignore l'ombre portée de la station ; il faisait briller un point lumineux dans le hublot du nadir alors
	que la cupola est à l'ombre. Le matériau `Vitrage` est remplacé au démarrage par une copie sans reflet
	spéculaire (métal 0, spéculaire 0, rugosité 1), toujours transparente.
  - **Chaleur** (règle de jeu, valeurs provisoires en attendant la jauge) : `heat` (0 à 1) monte de
	`heat_rise_per_s` (0,01/s) radiateurs tous repliés (**mode furtif** : pas de rayonnement infrarouge, la chaleur
	s'accumule) et descend de `heat_fall_per_s` (0,02/s) radiateurs tous déployés, en proportion des radiateurs
	déployés ; signal `heat_changed`.

## Organisation de la scène

- **Station** : nœud `Station` (repère de vol lu par `Orbit` : zénith +Y, direction de vol −Z ; aussi utilisé par
  `NukeFlashFX` pour éclairer la station au flash), qui contient l'instance `StationSpatiale` de
  `scenes/station_spatiale.tscn` (modèle Blender, voir « Station spatiale (modèle Blender) ») **tournée de 90°
  autour de Y** : le module Commande (+X du modèle) vole à l'avant, le dessous de la station (cupola, trappes des
  silos, −Y) face à la Terre. L'unité de la scène est le mètre (station ~42 × 80 m avec les panneaux).
  - Ancienne station, gardée dans le projet : `scenes/iss_cupola.tscn` (module Node 3 « Tranquility » + Cupola en
	CSG, inclinée de 30°).
- **Observateur** : corps `Observer` (`CharacterBody3D`, script `scripts/observer.gd`, déplacement en mode
  « flottant », sphère de collision de 0,3 m) portant la caméra `Observer/Camera` (script
  `scripts/station_camera.gd`, orientation). Le courant d'air de l'expulsion s'ajoute à son déplacement
  (`set_air_flow`, voir « Expulsion »). **Règle de jeu : on démarre allongé dans la couchette de l'Habitation,
  le regard vers ses pieds** (on voit le sac de couchage) : au démarrage, `Observer._place_at_start` place la caméra
  sur le repère `Point_Vue_Couchette` du modèle (`start_marker` ; vide : position de la scène), seulement quand la
  scène du jeu est la scène courante. Position de la scène (ancien départ, gardée par le décor du menu et les bancs
  de mesure, qui instancient la scène sous la leur) : 1 m sous le repère `Point_Vue_Cupola` du modèle, la tête au
  ras des vitres ((0, −4,2, −11,6) dans la scène ; plus haut, la paroi de la cupola masque l'horizon), vue initiale
  **dans l'axe de la trajectoire** (la station vole selon son avant : le sol défile du haut vers le bas de l'écran,
  à la rotation de la Terre près, ~4°), plongeant de 24° sous l'horizon de la station : l'horizon terrestre (~20°
  sous l'horizontale à 400 km) est visible, et le centre de l'écran (réticule de tir) tombe sur la Terre au milieu
  de la vitre avant.
- **Cupola** (modèle Blender) : hexagone orienté avec une face vers l'avant (+X du modèle), montants affinés
  (un montant pointait auparavant droit devant et masquait la vue avant).
- **Hublot cargo** (modèle Blender, `Hublot_Cargo` : tunnel de visée et cadres, `Hublot_Cargo_Vitre` : matériau
  `Vitrage`, donc visible des deux côtés et sans reflet, cf. `Station._matte_glass`) : percé dans la cloison du fond
  du module d'arrimage, à côté de l'écoutille cargo, il donne sur le vaisseau cargo amarré. `Orbit` place la Terre par rapport à la
  caméra (`observer_path`).
- **Collisions de la station** (`Station._add_interior_collisions`) : les parois générées à l'import (« -col »,
  formes concaves) bloquent des deux côtés (`backface_collision`, sinon on traverse la coque de l'intérieur) ; les
  objets `Interactif_*` sans collision (48 tubes des silos, consoles…) reçoivent au démarrage une forme convexe
  simplifiée. Les trappes et écoutilles ont déjà leur corps animé (`AnimatableBody3D`).
- **Ombres du soleil** : jusqu'à 60 m (`directional_shadow_max_distance`), pour que la station (80 m) porte ses ombres
  sur elle-même ; la Terre ne reçoit pas d'ombres portées (`shadows_disabled` dans `earth_surface.gdshader`) : à
  1/10 000, l'ombre de la station y serait 10 000 fois trop grande (invisible en réalité depuis l'orbite).
- **Échelle** : la Terre est à 1/10 000 (voir ci-dessous) ; à 400 km d'altitude, sa surface est à 40 unités sous la
  caméra (20 à 200 km). La station (trappes des silos à −4,6 m) reste au-dessus ; le missile lancé quitte
  l'animation Blender à −30 m puis est rendu à l'échelle préservant la perspective (`MissileFlight`) : il ne
  traverse jamais la Terre miniature.
- **Terre** (`Earth/`) : rendue à l'échelle **1/10 000** (1 unité = 10 km ; rayon 637,1 u) pour éviter les
  problèmes de précision du tampon de profondeur. La caméra ne se déplaçant pas, la taille angulaire est identique
  à celle d'une vraie Terre. Sa position et son orientation sont recalculées à chaque image par le nœud `Orbit`.
  - `Surface` (shader `earth_surface.gdshader` + script `earth_detail_tiles.gd`, voir ci-dessous).
  - `CloudLayer` (sphère de 638,4 u) : nuages volumétriques procéduraux, voir ci-dessous.
  - `AtmosphereGround` (638,7 u) et `AtmosphereSky` (664 u) : diffusion atmosphérique physique, voir ci-dessous.
- **Orbite** (`Orbit`, script `scripts/orbit.gd`) : mécanique orbitale, voir ci-dessous.
- **Soleil** : `DirectionalLight3D` orientée par `Orbit` (position réelle du soleil, éteinte pendant l'éclipse) ;
  elle éclaire la Terre et produit le reflet du soleil sur les océans. Masque d'eau : mers et océans d'après la carte
  des pays (`assets/textures/country_ids.png`, 0 = mer, `nuke_land_share`), plus les eaux intérieures reconnues à
  leur couleur (sombre et bleue). La couleur seule ne suffit pas : en espace linéaire, les mers de Blue Marble sont
  trop sombres pour être reconnues, et les océans étaient rendus mats comme les terres.
- **Transition jour / nuit** (`shaders/sun_light.gdshaderinc`, partagé par le sol et les nuages) : la lumière du
  soleil est atténuée par l'air qu'elle traverse. Au-dessus de l'horizon local, on utilise la masse d'air de
  Kasten-Young. Sous l'horizon, le rayon a frôlé la Terre à l'altitude tangente ht et traversé une colonne d'environ
  √(2πRH)·e^(−ht/H) (approximation de Chapman). Elle rougit donc puis s'éteint progressivement, sans coupure, et les
  nuages en altitude gardent la lumière rose-orangée après le coucher du soleil au sol. Le sol a un éclairage
  personnalisé (`light()` : Lambert + GGX avec cette lumière teintée) et reçoit en plus la lumière diffuse bleutée du
  ciel (`sky_light_*`), qui persiste au crépuscule jusqu'à ~12° sous l'horizon (`twilight_end`). Les lumières des
  villes s'allument entre +2° et −7°.
- **Ciel / rendu** : `materials/space_environment.tres` (panorama étoilé HDR, tonemapping ACES, bloom qui adoucit
  le limbe). Le ciel est orienté à chaque image par `Orbit` (`Environment.sky_rotation`) : les étoiles sont à leur
  vraie place et tournent d'un tour par orbite autour de la station, comme vues depuis l'ISS.
- **Disque solaire** (shader de ciel `shaders/space_sky.gdshader`, qui dessine aussi le panorama étoilé) : soleil à
  sa position calculée, de rayon angulaire réel (0,267°), avec assombrissement centre-bord. Sa luminance
  (`sun_disc_energy` = 40 000, proche du maximum du format 16 bits) sature l'image et pilote l'éblouissement et
  l'exposition (voir ci-dessous). `Orbit` lui transmet à chaque image la
  direction du soleil et la position de l'observateur, dans le repère du ciel. Près du limbe, le disque est atténué
  par la transmittance spectrale de l'atmosphère, avec le même modèle que `atmosphere.gdshader` (paramètres
  partagés dans `shaders/atmosphere_common.gdshaderinc`). Il rougit, s'éteint en passant derrière le limbe, puis la
  Terre le masque. Comme la sphère `AtmosphereSky` atténue déjà le fond de la transmittance moyenne (gris), le ciel
  n'applique que le rapport couleur / moyenne. Depuis la Cupola, tournée vers le nadir, on ne voit le soleil que
  lorsqu'il est assez bas, par les fenêtres latérales (lever et coucher à chaque orbite).
- **Éblouissement** : glow de l'Environment, en mode additif, sur les 7 niveaux (du plus fin au plus large,
  poids 0,6 → 0,15), avec un plafond de luminance relevé à 1000 (`glow_hdr_luminance_cap`). Seul le disque solaire
  (et les reflets les plus intenses) dépasse nettement le seuil : il produit un halo progressif. Comme c'est un
  effet d'image, ce halo déborde sur les montants des fenêtres, comme dans l'œil ou un objectif. Il disparaît dès que
  le disque est masqué par la station ou par la Terre.
- **Exposition** (nœud `Exposure`, `scripts/exposure_control.gd`, classe `ExposureControl` ; attributs de caméra
  `materials/camera_attributes.tres` affectés au `WorldEnvironment`). L'exposition automatique de Godot, laissée
  libre, se réglait sur la luminance moyenne de toute l'image : en 32:9, ou en plein écran, le ciel noir pèse
  davantage qu'en 16:9, la moyenne chute et l'exposition monte — Terre et station brûlées à 5120 × 1440 alors que
  la fenêtre 16:9 était correcte ; et elle dépendait de l'historique de la session (luminance moyenne de la même
  vue de jour, à froid : 86 à 100 ; de nuit : 45 à 135). Désormais l'exposition ne dépend que de ce qui est
  regardé, comme un œil adapté à l'extérieur, indépendamment du cadrage.
  - **Mécanisme** : l'exposition automatique reste activée mais **bridée** — le nœud impose à chaque image
	`auto_exposure_min_sensitivity` = `max_sensitivity` = `base_sensitivity` / facteur (`auto_exposure_scale`
	0,22, vitesse 20 : elle suit la consigne en quelques images ; le lissage est fait par le nœud). Pourquoi pas
	`exposure_multiplier` ? Dans ce build (Godot 4.7, D3D12, Forward+), **il n'agit pas sur le rendu** : à 0,
	l'image de jour garde 90 % de sa luminance (seuls ciel et glow y réagissent), alors que la sensibilité
	bridée expose réellement toute l'image (`tools/bench/exposure_sweep.tscn` : S = 50 brûlé, 200 référence,
	3 200 sombre). Le multiplicateur est neutralisé à 1. Une première version du nœud s'appuyait sur lui : le jeu
	tournait en fait à exposition ≈ 1 (HDR brut, « beaucoup plus brillant »), le curseur de luminosité presque
	sans effet, et le flash d'un 50 Mt inondait l'écran — une après-midi de fausses pistes (glow, éblouissement,
	lumières), jusqu'au test « exposition 0 → image inchangée ».
  - **jour / nuit** : d'après la hauteur du soleil au point de la Terre visé par le centre de la vue (sinon le point
	survolé) : sensibilité 200 quand elle dépasse 8° (`day_multiplier` × 1 : nuages texturés, océan profond — le
	rendu de référence), 70 sous −12° (`night_multiplier` × 2,85, le plafond de l'ancienne exposition automatique :
	villes et étoiles, montants clairs), interpolation géométrique entre les deux (crépuscule), lissage de 1 s vers
	le clair et 0,25 s vers le sombre (`adaptation_s`, `darkening_s`, comme l'œil). Vérifié à 1920 × 1080 et en
	vrai plein écran 5120 × 1440 : même luminance sur le même champ (le centre 2560 × 1440 de l'image 32:9), de
	jour (71,3 / 70,8) comme de nuit (38,0 / 37,6 ; `tools/bench/exposure_probe.tscn`) ;
  - **intérieur de la station** : l'écran est partagé entre la Terre et l'intérieur selon la part des rayons
	d'une grille 3 × 3 qui touchent la Terre (`_earth_view`, la Terre domine dès ~60 %) ; la part « intérieur »
	garde la sensibilité de jour (`interior_multiplier` × 1 : lumières artificielles constantes) — sans cela, la
	règle jour / nuit saturait l'intérieur la nuit (sonde `tools/bench/exposure_views_probe.tscn` : Terre,
	plafond de la cupola, intérieur, de jour et de nuit). **Hors de la cupola, dans les modules** (caméra à moins
	de 25 m de la station, `outside_distance_m`, et pas éjectée), le facteur est `interior_multiplier` seul : ni
	Terre (les rayons de `_earth_view` traversent la coque : viser le plancher la nuit changeait l'exposition), ni
	soleil, ni flash ;
  - **face au soleil** : depuis la cupola seulement (`Station.is_in_cupola`), quand le disque solaire est dans le
	champ (demi-diagonale, bord progressif sur ±10°), au-dessus du limbe terrestre et sous l'horizontale de la
	station (les fenêtres donnent vers la Terre ; un soleil derrière la coque est caché — viser le plafond
	assombrissait la vue), l'exposition est divisée par 5 (`sun_dimming`) : la Terre s'assombrit et les étoiles
	s'effacent (ce que faisait l'exposition automatique, dominée par le disque) ;
  - **facteur final** = luminosité des paramètres (`GameSettings.brightness`, 100 % = sensibilité 200 de jour) ×
	facteur jour / nuit × éblouissement du flash (`NukeFlashFX` fournit `dazzle`, voir « Lumière et effets d'écran
	du flash ») ÷ (1 + 8 × flux de flash reçu par la caméra, en soleils ; `flash_adapt_gain`) : l'œil s'adapte à la
	scène qu'un flash éclaire, qui s'assombrit autour de lui — ce que faisait l'exposition automatique ; sans ce
	terme, un 50 Mt éclairait toute la scène au lieu de rester un disque concentré (`tools/bench/flow_probe.tscn`,
	`flash_look_probe.tscn` : captures à 1, 2, 5, 10 et 20 s).
  - **Lumière ambiante** : celle de l'Environment n'éclaire que la station. La surface terrestre l'ignore
	(`render_mode ambient_light_disabled` dans `earth_surface.gdshader`) : remontée de × 2,5 la nuit, elle
	rendait les continents visibles. La face nocturne n'a que ses émissions (villes, lueur des terres, ciel au
	crépuscule).
  - **Compensations** : les étoiles (`panorama_energy` = 0,4) et les lumières des villes (`night_intensity` = 0,64)
	sont divisées par 2,5. La nuit, elles retrouvent leur éclat ; de jour, les étoiles sont à peine visibles,
	comme sur les photos prises depuis l'ISS.
  - **Vitesse d'adaptation** : `auto_exposure_speed` = 1.

### Orbite (`scripts/orbit.gd`)

Orbite **circulaire képlérienne** autour d'une Terre **en rotation** (sidérale, 7,292 × 10⁻⁵ rad/s) :
- rayon a = 6371 km + altitude ; vitesse angulaire n = √(μ / a³) (μ = 398 600,44 km³/s²) ; période 2π/n
  (88,4 min à 200 km, 92,4 min à 400 km, 100,7 min à 800 km) ;
- position dans le repère inertiel équatorial (ECI : x vers le point vernal, z vers le pôle nord céleste) avec
  i = inclinaison, Ω = ascension droite du nœud ascendant, u = argument de latitude (u = u₀ + n·t) :
  `r = a·(cosΩ·cos u − sinΩ·sin u·cos i, sinΩ·cos u + cosΩ·sin u·cos i, sin u·sin i)` ;
- repère terrestre (ECEF) = rotation de −θ autour de z, θ = angle sidéral de Greenwich = θ₀ + ω_terre·t : la
  trace au sol dérive donc vers l'ouest d'environ 23° de longitude par orbite ;
- point survolé : latitude = asin(z/|r|), longitude = atan2(y, x) dans l'ECEF.

**Rendu** : la station et la caméra restent fixes dans la scène. À chaque image, le repère orbital local
(zénith = r̂, direction de vol = v̂) est aligné sur le repère de la station (+Y local = zénith, −Z local = direction
de vol), et on en déduit l'orientation et la position de la Terre, la direction du soleil et l'orientation du ciel.

**Date et heure** : l'horloge est une vraie date UTC (`epoch_unix_s + sim_time_s`). Le jeu se passe en 2035 : départ
le `start_date` (2035-07-15, juillet comme les textures) à l'heure solaire locale `start_local_solar_hour` (10 h 30)
au point de départ. L'angle sidéral θ est l'angle de rotation de la Terre (IAU 2000), calculé à partir de la date
julienne. Le soleil est placé par les formules de l'Astronomical Almanac (longitude moyenne, anomalie, obliquité ;
précision ~0,01°), et suit donc les saisons, l'équation du temps et son déplacement d'environ 1° par jour. Le
soleil, la Terre et les étoiles sont cohérents entre eux (ex. en juillet à 22 h, le couchant est au nord-ouest).
Changer la date ou l'heure (`set_utc_unix_s`) recalcule l'orbite pour que la station reste au-dessus du même point.
Les textures du sol sont celles de juillet : une date d'hiver garde un sol estival (pas de neige).
Jour et nuit alternent naturellement (~35 min de nuit par orbite à 400 km ; l'été aux hautes latitudes, la station
peut rester au soleil alors que le sol est dans la nuit). `get_sunlight_fraction()` donne l'éclipse par la Terre
(ombre cylindrique adoucie sur 60 km), qui éteint la lumière du soleil sur la station.

**Ciel étoilé** : la carte NASA est en coordonnées équatoriales (ascension droite 0h au centre, croissante vers la
gauche, déclinaison +90° en haut). Le panorama Godot lit la direction locale d avec u = atan2(d.x, −d.z)/2π et
v = acos(d.y)/π, d'où d = (y_ECI, z_ECI, x_ECI). `sky_rotation` reçoit la rotation ciel → monde
(repère station ← ECEF ← ECI ← ciel). Godot applique son inverse aux directions de vue (vérifié dans
`servers/rendering/renderer_rd/environment/sky.cpp`).

**Conditions initiales** : `start_latitude_deg`, `start_longitude_deg` et `start_ascending` (40,4° N, 3,7° O,
montante : l'Espagne, au-dessus de Madrid). L'orbite est calculée pour y passer (`pass_over`).

**API pour le gameplay** (classe `OrbitSimulation`, groupe `orbit` ; le temps est relié au panneau, altitude et
inclinaison au poste de pilotage et au panneau de debug) :
| Méthode / propriété | Rôle |
|---|---|
| `altitude_km` (200–800) | Change l'altitude ; le point survolé et le sens de passage sont conservés. |
| `inclination_deg` (0–80°) | Change l'inclinaison au point courant (comme une manœuvre de changement de plan) ; bornée à ≥ \|latitude courante\|. |
| `get_next_node_time_s()`, `is_ascending_node_at(t)` | Temps simulé du prochain passage à l'équateur (u multiple de π ; orbite équatoriale : maintenant), nœud ascendant ou descendant. |
| `circular_position_eci(rayon, i, Ω, u)`, `mean_motion_at(altitude)` | Position sur une orbite circulaire quelconque, vitesse angulaire (orbite fantôme du poste de pilotage). |
| `get_eci_to_world()`, `ecef_to_world` | Rotations ECI → scène et ECEF → scène de la dernière image (objets fixes dans l'espace inertiel autour de la Terre). |
| `set_orbit_plane(i, Ω, altitude, t)` | Manœuvre : nouvelle inclinaison, Ω (au temps t) et altitude ; la station garde au temps t sa position projetée sur le nouveau plan (continue sur la droite d'intersection des deux plans). |
| `get_raan(t)`, `get_raan_rate()`, `raan_rate_at(altitude, i)`, `raan_precession` | Ω au temps t et sa dérive J2 (rad/s) ; `raan_precession` l'active (par défaut). |
| `ground_shift_per_orbit_deg(altitude, i)`, `plane_normal(i, Ω)` | Décalage de la trace au sol d'un tour à l'autre (rotation de la Terre pendant une période, moins la précession) ; normale au plan d'une orbite. |
| `pass_over(lat, lon, ascending)` | Recalcule Ω et la phase pour être, maintenant, à la verticale de (lat, lon). Exige \|lat\| ≤ inclinaison. |
| `restart(heure_solaire)` | Temps remis à zéro, station au-dessus du point de départ, le même jour, à l'heure solaire locale donnée (12 = midi, 0 = minuit). Utilisé par les boutons Restart. |
| `set_utc_unix_s(s)`, `get_utc_unix_s()`, `get_utc_datetime()` | Date et heure UTC (secondes Unix) ; le changement garde la station au-dessus du même point. |
| `get_local_solar_hour(lon)`, `get_sun_direction_eci()` | Heure solaire vraie à une longitude, direction du soleil. |
| `get_subsatellite_point(t)` | Point survolé (lat, lon) à l'instant t. |
| `predict_ground_track(durée, pas)` | Trace au sol prévue (pour une carte ou le calcul de manœuvres). |
| `get_period_s()`, `get_orbital_speed_km_s()`, `get_raan_deg()`, `is_ascending()` | Grandeurs orbitales. |
| `time_scale`, `sim_time_s` | Accélération / temps simulé. |

**Inclinaison maximale (80°) et pôles** : la trace au sol monte jusqu'à la latitude égale à l'inclinaison (80° :
limite de la carte Mercator du poste de pilotage), et la vue porte ~20° plus loin, donc jusqu'au pôle. Aux plus
hautes latitudes, la fenêtre de tuiles HD (découpée en latitude/longitude) devient étroite : au-delà de ~65° de
latitude, le sol loin du nadir peut être un peu moins net (la limite était de 70° avant le poste de pilotage). Pour survoler les pôles sans perte, il faudrait un découpage en « cube-sphère » (voir plus bas).

### Nuages volumétriques (`shaders/cloud_volume.gdshader`, `shaders/cloud_density.gdshaderinc`)

Couche entre **3 et 10 km** d'altitude, rendue par lancer de rayon (jusqu'à 72 pas) sur la sphère `CloudLayer`.
- **Où et combien** : nuages **réels** d'une journée d'imagerie satellite (VIIRS NOAA-20, 15 juillet 2023 : ouragan
  Calvin dans le Pacifique, dépressions en spirale, fronts, bancs de stratocumulus, amas orageux tropicaux…). La
  couche alpha est calculée par différence avec la Blue Marble sans nuages (`tools/build_cloud_tiles.ps1`). Elle est
  globale en 16K (`assets/textures/earth_clouds_16k.jpg`) et en tuiles 500 m/px autour de la station
  (`assets/earth_cloud_tiles/*.webp`, même fenêtre 5 × 5 que le sol). Le niveau de détail lu dépend de la
  distance, pour éviter le scintillement au loin.
- **Épaisseur** : la couverture moyenne à grande échelle (~8 km, `cloud_height_lod`) fixe la hauteur du sommet. Un
  cumulus isolé ou un voile reste bas (~1 km d'épaisseur, `cloud_thin_top`), une masse étendue et dense (front,
  cyclone, cumulonimbus) monte jusqu'à 10 km.
- **Forme** : les masses suivent directement la carte (pas de seuillage d'un bruit cellulaire, qui donnait l'aspect
  « billes de polystyrène »). Les sommets sont bosselés par un bruit fractal doux à deux échelles : ondulation sur
  50 km (`cloud_top_billow`) et relief « chou-fleur » sur ~8 km (`cloud_top_detail`). Un bruit de Worley
  (`cloud_detail_noise.tres`) n'effiloche que les bords (couverture partielle, `cloud_edge_erosion`).
- **Éclairage** : marche vers le soleil (auto-ombrage, loi de Beer + diffusion multiple approchée,
  `multiple_scattering`), phase double Henyey-Greenstein (liseré lumineux à contre-jour), soleil rougi puis éteint
  progressivement par l'atmosphère (`sun_light.gdshaderinc`), lumière ambiante bleutée du ciel ; nuages éteints côté
  nuit.
- **Ombres au sol** et voilage des lumières des villes : le shader de surface intègre la même densité.
- **Trous des explosions** : `cloud_density_masked()` (et `cloud_density()`, qui prend toutes les explosions) appelle `nuke_cloud_warp()` pour les explosions de son masque (`nuke/shaders/nuke_clouds.gdshaderinc`,
  voir « Explosions nucléaires », « Nuages ») ; sans explosion, le test `nuke_cloud_count > 0` évite tout calcul.
- **Déplacement par le vent réel** (advection) : la carte de couverture est un instantané, pris par NOAA-20 vers
  **13 h 30 heure solaire locale** le 15 juillet 2023. Le vent utilisé est le vent moyen du même jour : modèle
  GFS de la NOAA, moyenne des niveaux 850/700/500 hPa et des 4 analyses du jour, texture
  `assets/textures/cloud_wind.exr`, 0,5°. Pour l'heure UTC courante, le shader remonte la trajectoire de l'air
  (6 pas Runge-Kutta 2) jusqu'à l'heure du passage satellite, et lit la carte (et le bruit du relief) au point de
  départ. Les nuages dérivent donc avec la vraie circulation : alizés, courants-jets, rotation de l'ouragan Calvin.
  - Le calcul est fait une fois par rayon de vue (au milieu de la traversée de la couche) et une fois par pixel du
	sol pour les ombres, puis appliqué à tous les échantillons voisins.
  - **Règle de répétition journalière** : l'écart à l'heure du passage est ramené dans [−12 h, +12 h]. La météo du
	15 juillet 2023 se rejoue donc chaque jour : changer de date sans changer d'heure redonne les mêmes nuages, alors
	que changer l'heure les déplace.
  - Vers ±12 h (≈ 1 h 30 du matin, heure locale, donc côté nuit), les deux trajectoires sont fondues sur
	`cloud_advection_blend_h` (1,5 h) pour éviter un saut. Cette règle absorbe aussi le raccord de date de
	l'imagerie VIIRS.
  - Les nuages se déplacent mais ne naissent ni ne disparaissent : à ±12 h ils sont étirés par le cisaillement du
	vent.
  - Réglages : `cloud_wind_scale` (1 = vent réel), `cloud_snapshot_local_hour` (13,5).
- **Évolution des sommets** : `cloud_wind_km_s` fait en plus évoluer lentement le relief des sommets (temps réel).
Les nuages sont attachés au repère de la Terre (ils tournent avec elle). Réglages principaux dans le matériau
`materials/cloud_volume.tres` (voir aussi `materials/earth_surface.tres`, qui partage les paramètres de densité).

### Atmosphère (`shaders/atmosphere.gdshader`)

Diffusion simple calculée par lancer de rayon dans la coquille atmosphérique (rayon terrestre 6371 km, épaisseur
100 km ; calculs en km via `units_to_km = 10`) :
- **Rayleigh** (hauteur d'échelle 8 km) : bleu du ciel et du limbe ;
- **Mie** (hauteur d'échelle 1,2 km, g = 0,8) : halo blanchâtre près du sol et autour du soleil ;
- **Ozone** (couche centrée à 25 km) : absorption qui donne le passage bleu profond → noir.
La densité décroît exponentiellement avec l'altitude, d'où une transition progressive vers l'espace (plus de
« couche de verre »). Au-dessus du sol, la même intégration produit la perspective aérienne (voile bleuté vers
l'horizon) et atténue la lumière du sol. Rendu après les nuages (`render_priority = 1`) en mélange
prémultiplié, sur deux sphères avec le même shader (`ground_rays`) : `AtmosphereSky` (664 u, faces arrière seulement)
pour les rayons qui manquent la Terre, et `AtmosphereGround` (638,7 u, juste au-dessus des nuages, faces avant)
pour ceux qui la touchent. Ainsi l'atmosphère reste correcte même quand la caméra est *dans* la coquille
atmosphérique (orbite à 200 km), et la station la masque par le simple test de profondeur.

`height_scale = 2.5` étire l'atmosphère verticalement (hauteurs d'échelle et épaisseur × 2,5, coefficients ÷ 2,5) :
le voile au-dessus du sol garde la même opacité, mais le halo du limbe devient plus épais et plus diffus, comme sur
les photos de référence (1 = Terre réelle, liseré fin). La sphère `AtmosphereSky` (rayon 664 u) doit contenir
`6371 + 100 × height_scale` km. Autres réglages : `sun_intensity` (9), `primary_steps` / `light_steps`
(qualité / coût). Le modèle (rayon, coefficients, hauteurs d'échelle, `height_scale`) est dans
`shaders/atmosphere_common.gdshaderinc`, partagé avec le shader de ciel. Si on change un paramètre dans un matériau,
il faut le changer aussi dans l'autre.

### Texture de la surface : globale + tuiles haute résolution

Trois jeux de données identiquement découpés : **jour** (Blue Marble NG), **nuit** (Black Marble 2016, lumières
des villes) et **couverture nuageuse** (VIIRS, voir « Nuages volumétriques » ; tuiles en WebP niveaux de gris,
gardées en L8 en mémoire, ~50 Mo de VRAM).
- Partout : `assets/textures/earth_bluemarble_16k.jpg` et `earth_night_16k.jpg` (16384 × 8192, ~2,4 km/pixel).
- Autour du point survolé : tuiles de 5° en **500 m/pixel** (`assets/earth_tiles/rLL_cCC.jpg` et
  `assets/earth_night_tiles/rLL_cCC.jpg`, 1200 × 1200 px, 72 colonnes × 36 lignes, ligne 0 = 90° N, colonne 0 =
  180° O). Le script `scripts/earth_detail_tiles.gd` garde une fenêtre de 5 × 5 tuiles (25° × 25°, soit au moins
  1100 km autour du nadir) dans un `Texture2DArray` par jeu (jour, nuit, nuages), tous avec la même attribution de
  couches. Il transmet ces tableaux, l'origine de la fenêtre et la table des couches au matériau de surface et à
  celui des nuages (`extra_material_paths`) ; la logique de lecture est partagée dans
  `shaders/detail_window.gdshaderinc`. Quand la station change de tuile, il charge les tuiles entrantes en tâche de
  fond (`WorkerThreadPool`) et les copie dans les couches libérées. Les shaders fondent la fenêtre dans les textures
  globales sur ses bords. Les tuiles sont gardées non compressées (~430 Mo de VRAM au total, chargement < 2 s) ; l'option
  `compress_tiles` les compresse en BC1 (VRAM ÷ 8) mais le chargement devient beaucoup plus lent et le
  compresseur n'existe que dans l'éditeur. Sans tuiles de nuit, seule la texture globale de nuit est utilisée.
- **Lumières nocturnes** (shader de surface, en émission) : allumées quand le soleil passe sous l'horizon local
  (`night_sun_high` ≈ +2° → `night_sun_low` ≈ −7°), atténuées sous les nuages (transmittance verticale de la
  couche nuageuse, `night_cloud_floor`), intensité `night_intensity` (0,64, compensée par l'exposition
  automatique, qui remonte l'image de × 2,5 la nuit). La faible lueur bleutée des terres présente
  dans le composite NASA (clair de lune, neige) est gardée mais atténuée (`night_land_level`).
- Les dossiers de tuiles contiennent un `.gdignore` : l'éditeur n'importe pas les ~7800 tuiles (pas de
  copie dans `.godot/`), le jeu les lit directement avec `FileAccess`. **À prévoir pour un export** : inclure ces
  fichiers dans le paquet (filtre d'export de fichiers non-ressources ou distribution à côté de l'exécutable).
- **Pôles** : le découpage latitude/longitude (équirectangulaire) dégénère aux pôles. Les tuiles y deviennent des
  bandes très étroites, la fenêtre 5 × 5 ne couvre presque plus rien, et le maillage `SphereMesh` pince ses UV.
  D'où une Terre moins nette au-delà de ~70° de latitude (inclinaison maximale : 80°). La technique standard pour survoler les pôles sans dégrader la vue est la
  **cube-sphère** : on projette la Terre sur les 6 faces d'un cube (chaque face découpée en tuiles carrées
  quasi uniformes), avec un maillage de sphère issu du cube et des coordonnées calculées par pixel à partir de la
  direction. Il n'y a alors plus de singularité nulle part. Cela demande de reprojeter les tuiles NASA (outil
  hors-jeu) et d'adapter `earth_detail_tiles.gd` et le shader de surface.

### Génération des tuiles

1. Télécharger les 8 images Blue Marble Next Generation de juillet 2004, variante **sans relief ombré** (le relief
   ombré « topo.bathy » est figé et éclairé du nord-ouest, irréaliste avec un soleil dynamique, et dessine le fond
   des mers)
   (`world.200407.3x21600x21600.{A1,B1,C1,D1,A2,B2,C2,D2}.jpg`, ~350 Mo) depuis
   `https://eoimages.gsfc.nasa.gov/images/imagerecords/74000/74092/` dans un dossier, renommées `A1.jpg` … `D2.jpg`.
   Le serveur coupe souvent les gros transferts : reprendre avec `curl -C -` jusqu'à la taille annoncée.
2. Lancer `tools/build_earth_tiles.ps1 -src <dossier>` (PowerShell, quelques minutes). Il écrit les tuiles et
   régénère la texture globale 16K à partir de la même source (couleurs identiques entre les deux niveaux).
   Le script est en .NET car Godot refuse les images de plus de 268 Mpx (les sources en font 466).
3. Nuit : télécharger `BlackMarble_2016_{A1,B1,C1,D1,A2,B2,C2,D2}.jpg` (~220 Mo) depuis
   `https://eoimages.gsfc.nasa.gov/images/imagerecords/144000/144898/`, renommées `A1.jpg` … `D2.jpg`, puis lancer
   `tools/build_earth_tiles.ps1 -src <dossier> -kind night` (même découpage, sorties `assets/earth_night_tiles/`
   et `assets/textures/earth_night_16k.jpg`).
4. Nuages (nécessite les tuiles de jour) :
   - télécharger les 2592 tuiles VIIRS de la journée choisie, même nom et même emprise que les tuiles de jour
	 (`rLL_cCC.jpg`, 5°, 1200 × 1200 px). WMS NASA GIBS
	 `https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi?SERVICE=WMS&REQUEST=GetMap&VERSION=1.3.0&LAYERS=VIIRS_NOAA20_CorrectedReflectance_TrueColor&CRS=EPSG:4326&BBOX=<lat_min>,<lon_min>,<lat_max>,<lon_max>&WIDTH=1200&HEIGHT=1200&FORMAT=image/jpeg&TIME=2023-07-15`
	 (~410 Mo, quelques minutes avec 12 requêtes en parallèle) ;
   - `tools/build_cloud_tiles.ps1 -viirs <dossier>` (PowerShell + routine C# compilée à la volée, ~3 min). Il calcule
	 la couche alpha (différence de luminance avec la Blue Marble, filtre des pixels colorés, suppression du reflet
	 du soleil sur l'océan, repérable car lisse, par l'écart-type local). Là où la journée n'a pas de données (nuit
	 polaire), il prend la carte nuageuse Blue Marble 8K. Il écrit les tuiles JPEG et la texture globale 16K ;
   - `godot --headless --path . --script res://tools/convert_tiles_webp.gd -- <projet>/assets/earth_cloud_tiles`
	 convertit les tuiles en WebP niveaux de gris (~2 fois plus léger que le JPEG).
5. Vent (déplacement des nuages) : `tools/build_wind_field.ps1 [-date 20230715]` (PowerShell + routine C#, ~1 min).
   - Il lit l'index `.idx` des analyses GFS 0,25° du jour (00, 06, 12, 18 UTC) sur l'archive publique AWS
	 `https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.AAAAMMJJ/HH/atmos/gfs.tHHz.pgrb2.0p25.anl`, et ne télécharge
	 que les composantes UGRD/VGRD à 850, 700 et 500 hPa (~24 Mo).
   - Il décode le GRIB2 lui-même (gabarit 5.3, « complex packing + spatial differencing »), puis fait la moyenne.
   - Il écrit `assets/textures/cloud_wind.exr` (720 × 360, R = vent vers l'est, G = vers le nord, m/s).
   - Il écrit aussi le **profil vertical** du vent, pour la dérive des champignons atomiques
	 (`assets/textures/wind_profile.exr`) : 14 niveaux de pression (850, 700, 500, 300, 250, 200, 150, 100, 50, 20,
	 10, 5, 1 et 0,1 hPa, soit ~1,5 à ~64 km d'altitude), moyennés sur les 4 analyses du jour et empilés
	 verticalement du plus bas au plus haut, 360 × 180 texels (1°) chacun. Canaux : R = vent vers l'est, G = vers le
	 nord (m/s), B = altitude géopotentielle du niveau (champ HGT, km). Téléchargement : ~150 Mo, quelques minutes.
   - Le service OPeNDAP de la NOAA, plus simple, était hors service ; la réanalyse NCEP (2,5°) aurait été trop
	 grossière pour les cyclones.
   - L'import Godot de ces deux textures doit rester **sans perte** (`detect_3d/compress_to=0` dans le `.import`),
	 sinon la compression GPU fausse les vitesses.
   - Pour une autre journée de nuages, refaire les étapes 4 et 5 avec la même date.
6. Masque mers et océans (explosions sur la mer, voir « Explosions sur la mer ») :
   - télécharger la couche « ocean » de Natural Earth 1:10 M en GeoJSON (~10 Mo) :
	 `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_ocean.geojson` ;
   - `godot --headless --path . --script res://tools/build_ocean_mask.gd -- <ne_10m_ocean.geojson>` (~1 s). Il écrit
	 `assets/ocean_mask.res` (ressource `OceanMask`, ~2,4 Mo).
7. Masque des pays (voir « Pays touché ») :
   - télécharger la couche « admin 0 countries » de Natural Earth 1:10 M en GeoJSON (~13 Mo) :
	 `https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson` ;
   - `godot --headless --path . --script res://tools/build_country_mask.gd -- <ne_10m_admin_0_countries.geojson>`
	 (~1 s). Il écrit `assets/country_mask.res` (ressource `CountryMask`, ~3 Mo).
8. Population (voir « Pertes humaines ») :
   - télécharger GHS-POP R2023A, époque 2030, 30 secondes d'arc, WGS84 (~460 Mo, à décompresser : seul le `.tif` sert) :
	 `https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_POP_GLOBE_R2023A/GHS_POP_E2030_GLOBE_R2023A_4326_30ss/V1-0/` ;
   - `tools/build_population.ps1 -src <GHS_POP_E2030_GLOBE_R2023A_4326_30ss_V1_0.tif>` (PowerShell + routine C#,
	 ~30 s). Il décode le GeoTIFF (BigTIFF, flottants 64 bits, LZW, décodeur intégré) et écrit
	 `assets/population_2030.bin` (~74 Mo, format décrit en tête de l'outil). Il affiche la population mondiale :
	 8 546 141 387 en 2030 (projection de l'ONU : ~8,5 milliards).
   - Le `.bin` n'est pas importé par l'éditeur (extension inconnue, pas de `.gdignore` nécessaire) ; le jeu le lit
	 avec `FileAccess`. **À prévoir pour un export** : l'inclure dans le paquet, comme les tuiles.
9. Centrales électriques (voir « Black-out électrique » ; nécessite le masque des pays, étape 7) :
   - télécharger la Global Power Plant Database v1.3 du WRI (~4 Mo, décompresser `global_power_plant_database.csv`) :
	 `https://wri-dataportal-prod.s3.amazonaws.com/manual/global_power_plant_database_v_1_3.zip` ;
   - `godot --headless --path . --script res://tools/build_power_plants.gd -- <global_power_plant_database.csv>`
	 (~1 s). Il écrit `assets/power_plants.res` (ressource `PowerPlants`, ~0,7 Mo) : 34 936 centrales, 5 693 GW.
   - La carte des pays pour les shaders (`assets/textures/country_ids.png`, 8192 × 4096, ~0,4 Mo) est écrite par
	 l'outil des pays (étape 7). Son import doit rester **sans perte et sans mipmaps** (`compress/mode=0`,
	 `mipmaps/generate=false`, `detect_3d/compress_to=0` dans le `.import`) : les pixels sont des numéros de pays.

## Explosions nucléaires (`nuke/`)

Tout le code des explosions est dans `res://nuke/`. Objectif : une animation unique, paramétrée par la puissance
(10 kt à 50 Mt), vue depuis l'espace. **État actuel : socle de l'effet** (tir, placement, lois d'échelle,
horloge), **flash initial**, **onde de choc** (condensation, poussière), **incendies**, **trous dans la couche
nuageuse**, **champignon** (boule de feu comprise ; dérive selon le profil vertical du vent, dissipation et panache)
et **explosions sur la mer** (pas d'incendie au large, nuage de vapeur d'eau qui retombe vite) ; le **pays touché**
et les **pertes humaines** (par pays, selon la densité de population) sont calculés au tir ; **black-out électrique**
de nuit (zone détruite, panne régionale en cascade, panne nationale si une grosse centrale est détruite).

**Persistance du monde (règle de jeu)** : une explosion n'est jamais retirée ; ses effets au sol durent toute la
partie, sans limite de nombre. Les incendies s'étendent pendant plusieurs jours, sous un **panache de fumée** emporté
par le vent sur des centaines de km, puis s'éteignent en laissant une **trace au sol définitive** (charbon, puis terre
brûlée brune et gravats : plus de verdure, visible de jour, d'autant plus étendue que la bombe est puissante) ; le
**black-out ne se répare jamais** (zone détruite, panne régionale et panne nationale). Explosions à **500 m
d'altitude** : pas de cratère. Le champignon se dissipe en quelques heures de jeu (dérive et dilution réelles). Après la première
demi-heure physique, jouée en accéléré, une explosion vit au rythme de l'horloge du jeu (voir « Horloge ») : ce que
l'on retrouve après une ou plusieurs orbites correspond au temps réellement écoulé dans la partie.

### Organisation du code

Une responsabilité par classe (principe « S » de SOLID). Trois familles :

| Rôle | Classes (fichiers dans `nuke/` sauf mention) |
|---|---|
| **Tir** | `NukeLauncher` (visée, création de l'explosion, liste des explosions ; crée les nœuds ci-dessous), `NukeParams` (paramètres d'un tir), `NukeEffect` (une explosion : placement, temps, résultats du bilan), `NukeClock` (horloge) |
| **Rendu d'une explosion** (enfants de `NukeEffect`) | `NukeFlash`, `NukeShock`, `NukeMushroom` (forme, volume, couleurs) avec `NukeMushroomDrift` (dérive au vent) et `NukeMushroomParticles` (particules) |
| **Rendu global** (nœuds créés par le lanceur, alimentent les shaders du globe) | `NukeFlashFX`, `NukeCloudFX` (effets brefs, tableaux d'uniforms), `NukeGroundFX` (effets durables au sol : incendies, fumée, trace au sol, black-out ; textures de données sans plafond) ; `NukeFXMaterials` (recherche des matériaux qui déclarent un uniform) |
| **Modèles** (calcul pur, sans nœud, utilisables depuis un thread) | `NukeScaling` (lois d'échelle, surpression de Brode), `NukeCasualties` (pertes du souffle et de la chaleur, chronologie), `NukeFallout` (doses et pertes des retombées) avec `NukeWSEG10` (champ de retombées) et `NukeMath`, `NukeGridImpact` (centrales détruites, panne nationale), `NukeAtmosphere`, `NukeWind` |
| **Bilan** | `NukeImpact` (nœud `Impact` : calcule le bilan d'un tir dans un thread et l'écrit en console), `NukeTally` (cumul par pays, à l'instant présent), `NukeReportText` (textes et nombres), `NukeReportPanel` (écran mural du module Commande, affichage seulement) |
| **Données géographiques** (`scripts/`) | `OceanMask`, `CountryMask` (dont `index_near` : pays le plus proche d'un point côtier), `PopulationGrid` (dont `cell_country`), `PowerPlants` |

Un tir ne fait que créer la scène de l'explosion (~1 ms) : tout le bilan (pertes, réseau électrique, retombées) est
calculé par `NukeImpact` dans un `WorkerThreadPool`, puis remis à l'explosion dans le fil principal ; la console est
écrite depuis ce thread. Un bilan de 50 Mt prend plusieurs secondes (dix d'un coup : ~12 s, retombées sur plus de
1 000 km de ligne chaude) : à la fin de la partie ou du jeu (`NukeImpact._exit_tree`), les calculs sont **abandonnés**
(`NukeCasualties.abort`, drapeau testé à chaque ligne de la grille par `NukeCasualties.estimate` et
`NukeFallout.estimate`, résultats partiels jetés) puis **attendus** (`WorkerThreadPool.wait_for_task_completion`,
aussi pour les tâches finies, libérées au passage), comme le préchargement des cartes de vent (`NukeLauncher`) :
plus rien ne tourne pendant la destruction de la scène. Avant cela, quitter pendant un calcul faisait attendre la
fermeture jusqu'à la fin des bilans, puis plantait (accès à des objets détruits) ; les tâches terminées jamais
attendues plantaient aussi la sortie. Reproduction :
`tools/bench/quit_probe.tscn` (10 × 50 Mt figés à 6 h puis `quit()` selon une variante : `none`, `clear`, `free`,
`wait`, `t60`, `hide`).

### Performances

**Compteur à l'écran** : le nœud `FpsOverlay` (voir « Contrôles », F3) affiche en permanence images/s, temps CPU et
GPU par image, appels de dessin et mémoire vidéo.

**Banc de mesure de référence** : `tools/bench/bench.tscn` (`godot --path . res://tools/bench/bench.tscn
[-- [<résultats.md>] [--yield=<kt>]]` ; puissance des tirs 1 Mt par défaut, `--yield=50000` pour les gros
champignons ; sans fichier, le résultat va dans `tools/bench/results/bench_<date>_<puissance>.md`, versionné : c'est
la trace des mesures de référence, à comparer après chaque optimisation). Il charge la scène principale, coupe la
synchro verticale, met la fenêtre sans bordure à chaque résolution mesurée (1920 × 1080, 2560 × 1440, 3440 × 1440,
5120 × 1440 ; rendu 3D à l'échelle 1, pas de 3840 × 2160 : l'écran de référence fait 1440 px de haut) et y joue trois
scénarios, chacun depuis le même état (`Orbit.restart` à midi au-dessus de Madrid, plus d'explosion) :
1. **orbite simple** : temps x1, aucune explosion, 4 s ;
2. **8 missiles** tirés d'un coup depuis les tubes de la station (`LaunchControl.fire_tube`, cibles à ±2° du point
   visé, graine fixe), chaque image rangée dans sa phase : sortie du tube (animation de la station), propulsion,
   croisière, rentrée (dès qu'un missile y est), puis les explosions à l'arrivée, en direct, par fenêtres de temps
   réel (0–4 s : flash ; 4–20 s et 20–60 s : montée du champignon) ;
3. **10 explosions** tirées d'un coup (`launch_at`), orbite figée, toutes figées (`time_override_s`) à 5 s,
   60 s, 10 min, 30 min et 6 h, 120 images chacune (après 30 images de chauffe).
Pour chaque mesure : images/s, temps CPU par image (moyen et pire : temps entre deux images, qui inclut l'attente du
GPU), temps GPU (`RenderingServer.viewport_get_measured_render_time_gpu`), appels de dessin ; en notes, la durée des
appels de tir et la pire image qui suit ; enfin, à la dernière résolution, la part GPU de chaque effet (en le
coupant), à 60 s et à 6 h (`--only-breakdown` : seulement cette partie, ~1 min). Durée : ~10 min. Une capture
d'écran par mesure dans `user://bench_shots/` (hors dépôt) pour vérifier ce qui a été mesuré. Les temps GPU de
base varient de ±1 ms d'un lancement à l'autre (fréquences du GPU) : pour juger un réglage fin, comparer dans le
même lancement (A/B), comme le fait la sonde des champignons (`tools/bench/mushroom_probe.tscn`, 10 × 50 Mt figés à
1 min, 30 min, 2 h et 6 h : boîtes englobantes, couverture écran, temps GPU avec/sans chaque volume et pour chaque
réglage du shader, captures `probe_*.png` à comparer par PSNR avec ffmpeg). **Ne rien faire tourner d'autre pendant la mesure** : fermer l'éditeur Godot (ou au moins
ne pas y lancer de partie), il partage le GPU.

**Référence du gel fonctionnel (2026-10-16)** : `tools/bench/results/bench_2026-10-16_reference.md` (RTX 5080,
Godot 4.7.2, D3D12, éditeur fermé). Extrait (images/s, temps GPU moyen par image) :

| Résolution | Orbite simple | 8 missiles : rentrée | Explosions à l'arrivée (0–4 s) | 10 × 1 Mt à 1 min | 10 × 1 Mt à 6 h |
|---|---|---|---|---|---|
| 1920 × 1080 | 259 im/s (3,7 ms) | 235 im/s (4,1 ms) | 161 im/s (6,1 ms) | 228 im/s (4,3 ms) | 260 im/s (3,7 ms) |
| 2560 × 1440 | 163 im/s (6,0 ms) | 148 im/s (6,6 ms) | 114 im/s (8,7 ms) | 151 im/s (6,5 ms) | 164 im/s (6,0 ms) |
| 3440 × 1440 | 131 im/s (7,5 ms) | 122 im/s (8,1 ms) | 98 im/s (10,1 ms) | 121 im/s (8,1 ms) | 133 im/s (7,4 ms) |
| 5120 × 1440 | 101 im/s (9,7 ms) | 95 im/s (10,4 ms) | 85 im/s (11,7 ms) | 104 im/s (9,5 ms) | 108 im/s (9,1 ms) |

Ce que la référence montre :
- le jeu est **limité par le GPU** (temps CPU ≈ temps GPU + 0,15 ms) et le coût de base suit le nombre de pixels de
  Terre et d'atmosphère à l'écran (3,7 ms en 1080p, 9,7 ms en 5120 × 1440 : la largeur 32:9 ajoute surtout du ciel
  noir, bon marché) ; ~790 appels de dessin en orbite simple (station) ;
- les **explosions figées coûtent peu** (10 × 1 Mt : +0,5 ms au plus en 1080p, +0,25 ms pour les champignons à
  5120 × 1440 ; onde de choc, trous dans les nuages, incendies et fumée dans le bruit de mesure, ±0,2 ms) : avec la
  visée par défaut, elles sont petites à l'écran (près de l'horizon) ;
- les **4 premières secondes** d'une explosion (flash, boule de feu) sont l'effet le plus cher : +2,3 ms en 1080p ;
- **à-coups** : pire image de 146 ms à la première rentrée / première explosion de la partie (compilation des
  shaders), puis 34 à 37 ms à chaque arrivée de salve ; 23 ms à la première sortie de tube (duplication du missile),
  dont les appels de dessin passent à ~1 350 ; un tir de 10 explosions coûte 14 ms d'appels puis une pire image
  de 9 à 10 ms ;
- **l'éditeur Godot ouvert fausse tout**, même sans partie lancée : sa vue 3D redessine en continu les shaders
  animés et ajoutait ~10 ms par image (55 im/s au lieu de 259 en 1080p au premier passage). Le fermer avant de
  mesurer.

**Référence à 50 Mt** (`tools/bench/results/bench_2026-10-16_reference_50Mt.md`, `--yield=50000`, même séance) :
c'est avec les grosses bombes que le jeu s'écroule. Images/s (temps GPU moyen) :

| Résolution | Orbite simple | 8 × 50 Mt à l'arrivée, 0–4 s | 4–20 s | 20–60 s | 10 × 50 Mt à 1 min | 10 × 50 Mt à 6 h |
|---|---|---|---|---|---|---|
| 1920 × 1080 | 247 (3,9 ms) | 108 (9,2 ms) | 104 (9,5 ms) | 187 (5,2 ms) | 183 (5,3 ms) | 68 (14,6 ms) |
| 2560 × 1440 | 153 (6,4 ms) | 62 (15,9 ms) | 61 (16,4 ms) | 122 (8,0 ms) | 124 (8,0 ms) | 42 (23,6 ms) |
| 3440 × 1440 | 125 (7,9 ms) | 62 (16,1 ms) | 59 (16,8 ms) | 105 (9,4 ms) | 107 (9,2 ms) | 34 (29,4 ms) |
| 5120 × 1440 | 102 (9,6 ms) | 61 (16,2 ms) | 58 (17,0 ms) | 88 (11,1 ms) | 92 (10,8 ms) | 29 (34,8 ms) |

- les **20 premières secondes** (flash, boule de feu, début du champignon) coûtaient +5 ms en 1080p et +7 à +10 ms
  au-dessus (le coût ne suit pas le nombre de pixels : ~16 ms GPU de 1440p à 5120 × 1440). Sonde
  `tools/bench/flash_probe.tscn` (10 × 50 Mt figés à 3, 10 et 20 s, chaque composante coupée à tour de rôle dans le
  même état) : tout vient de la **lumière du flash dans les nuages** (`nuke_flash_volume`, appelé à chaque pas de la
  marche des nuages : 3,5 ms sur 8,2 à 1080p), et dans celle-ci de la marche d'auto-ombrage vers le flash (4
  échantillons de densité par flash et par pas) ; lumière au sol, éblouissement, boule de feu, lumière sur la
  station, onde de choc : rien de mesurable. **Corrigé** : une seule marche par pas, vers le flash le plus brillant,
  partagée par les autres (`nuke_flash_shadow_shared`, voir « Lumière et effets d'écran du flash ») : 8,2 → 5,7 ms,
  PSNR 53–61 dB. Réduire les pas de la marche (2 ou 0) dégradait l'image (28–48 dB) ; l'air à 2 pas ne gagnait que
  0,2 ms. Pièges de mesure rencontrés : l'exposition automatique et l'adaptation « œil » de `NukeFlashFX` (temps
  réel) décalent toute l'image entre deux captures — les geler avant de comparer (la sonde le fait) ; et le
  partage entre flashs « de directions proches » ne partageait jamais : à quelques km d'altitude, deux flashs sont
  vus sous des directions très différentes par les nuages (rien à voir avec le soleil). Banc complet après
  (`bench_2026-10-16_flash_50Mt.md`, base « orbite simple » 0,3 à 1 ms plus lente ce passage-là : GPU chauffé),
  8 × 50 Mt à l'arrivée, images/s (GPU), référence → après :

  | Résolution | 0–4 s | 4–20 s |
  |---|---|---|
  | 1920 × 1080 | 108 (9,2 ms) → **149 (6,5 ms)** | 104 (9,5) → **145 (6,7)** |
  | 2560 × 1440 | 62 (15,9) → **97 (10,1)** | 61 (16,4) → **83 (11,9)** |
  | 3440 × 1440 | 62 (16,1) → **81 (12,2)** | 59 (16,8) → **70 (14,1)** |
  | 5120 × 1440 | 61 (16,2) → **75 (13,2)** | 58 (17,0) → **72 (13,6)** |
  ;
- à partir de 20 s et jusqu'à 30 min, 10 × 50 Mt ne coûtent plus que +1,2 à +1,5 ms (champignons 1 ms, onde de
  choc 0,3 à 0,5 ms, reste dans le bruit) ;
- **à 6 h, les champignons volumétriques coûtaient 25,7 ms sur 35,7 à 5120 × 1440** (part de chaque effet : sans
  `Mushroom` 10,0 ms ; fumée, incendies, trous dans les nuages et onde de choc dans le bruit, ±0,5 ms). Cause
  trouvée avec la sonde `tools/bench/mushroom_probe.tscn` (boîtes englobantes en km, couverture écran, temps GPU
  avec un seul volume, A/B des réglages du shader dans le même état, captures) : pas la marche de rayon en soi,
  mais une boîte englobante de ~1 400 km (cisaillement du vent entre le bas et le haut du chapeau) rasterisée sur
  30 à 100 % de l'écran par champignon, marchée en 64 pas presque tous dans le vide. **Corrigé le jour même**
  (saut du vide exact dans le shader, pas de lumière selon la dilution, trous testés en premier ; voir
  « Champignon ») : à 6 h, 7,6 puis 6,6 ms au lieu de 25,7 (image identique, PSNR > 62 dB), soit 17,6 ms par image
  au lieu de 35,7 (57 im/s au lieu de 29). Résultats complets : `bench_2026-10-16_champignons_50Mt.md` (même
  banc, même jour) ; images/s (temps GPU), référence → après :

  | Résolution | 10 × 50 Mt à 1 min | 10 × 50 Mt à 6 h | 8 × 50 Mt, 20–60 s après l'arrivée |
  |---|---|---|---|
  | 1920 × 1080 | 183 (5,3 ms) → 194 (5,0 ms) | 68 (14,6 ms) → **150 (6,5 ms)** | 187 (5,2) → 192 (5,1) |
  | 2560 × 1440 | 124 (8,0) → 133 (7,4) | 42 (23,6) → **93 (10,7)** | 122 (8,0) → 121 (8,1) |
  | 3440 × 1440 | 107 (9,2) → 102 (9,7) | 34 (29,4) → **75 (13,2)** | 105 (9,4) → 100 (9,8) |
  | 5120 × 1440 | 92 (10,8) → 84 (11,8) | 29 (34,8) → **62 (16,1)** | 88 (11,1) → 88 (11,2) |

  Hors 6 h, les écarts (±1 ms) sont ceux de deux lancements (la base « orbite simple » a elle-même bougé de
  0,1 à 0,5 ms) ; l'A/B de la sonde dans le même état donne 5,38 contre 5,32 ms à 1 min (pas de régression).
- le processus plantait (segfault) ou restait bloqué à sa fermeture pendant un bilan de 50 Mt (banc
  `--only-breakdown`, sondes, et en jeu : quitter pendant « bilan : calcul en cours… ») : corrigé le jour même par
  l'abandon et l'attente des tâches de `NukeImpact` à la sortie (voir « Organisation du code ») ; sortie en 4 à 5 s
  dans tous les cas (`tools/bench/quit_probe.tscn`). Les bilans eux-mêmes prennent ~12 s pour 10 × 50 Mt en tâches
  de fond (grille de population sous mutex, retombées sur plus de 1 000 km) : acceptable, « bilan : calcul en
  cours… » le signale.

Mesures historiques (RTX 5080, 1920 × 1080, 2026-10-10, ancien banc : orbite figée, 16 × 1 Mt), avant et après la
refactorisation et les optimisations :

| | Avant | Après |
|---|---|---|
| 16 tirs enchaînés : durée des appels | 996 ms | 20 ms |
| Pire image après ces 16 tirs | 257 ms | 5 ms |
| 0 explosion : temps par image | 4,2 ms (235 im/s) | 4,3 ms (235 im/s) |
| 16 × 1 Mt à 60 s | 8,6 ms (116 im/s) | 6,2 ms (162 im/s) |
| 16 × 1 Mt à 30 min | 7,3 ms (137 im/s) | 7,2 ms (139 im/s) |
| GPU des trous dans les nuages (16 × 1 Mt) | 2,65 ms | 0,17 ms |
| GPU des incendies (16 × 1 Mt) | 0,21 ms | 0,03 ms |

Le jeu est limité par le GPU (temps CPU ≈ temps GPU). Ce qui a été corrigé :
- **à-coups au tir** (la vraie cause des ralentissements ressentis) : chaque `print()` coûte 6 à 9 ms (sortie de
  l'éditeur) et un tir en écrivait 6 à 8 ; le calcul des pertes prenait 4 à 40 ms et les cartes de vent étaient
  chargées au premier tir. Désormais tout le bilan et la console sont dans un thread (`NukeImpact`) et les cartes
  de vent sont préchargées au démarrage (`NukeWind.preload_maps`). Seul le tout premier tir de la partie coûte
  ~17 ms (première création de la scène de l'explosion) ;
- **trous dans les nuages** : chaque échantillon de nuage (marche de rayon et marche vers le soleil) testait toutes
  les explosions. Le shader des nuages calcule maintenant une fois par rayon la liste des explosions dont la zone
  d'influence croise son trajet (`nuke_cloud_events_near_segment`, masque de bits) et n'évalue qu'elles
  (`cloud_density_masked`) ;
- **incendies** : le voile des nuages sur les feux (une marche de nuages par pixel du sol) était calculé sur tout le
  globe dès qu'un feu existait ; il ne l'est plus que là où il y a du feu ;
- **dérive des champignons** (CPU) : pendant les 10 min de montée, 512 interpolations du profil de vent par
  champignon et par image ; le vent est maintenant lu dans une table précalculée (`NukeMushroomDrift`).

Coût restant (16 × 1 Mt à 60 s, GPU) : champignons volumétriques 1,5 ms, anneaux d'onde de choc 0,6 ms. Essayé sans
gain mesurable, donc abandonné : un pas adaptatif pour la marche de rayon du champignon (les rayons traversent
surtout des volumes hauts, où 64 pas restent nécessaires).

- **Paramètres** (`nuke/nuke_params.gd`, Resource `NukeParams`) : `yield_kt` (10 à 50 000), `latitude_deg`,
  `longitude_deg`, `wind_direction_deg` (d'où vient le vent, convention météo) et `wind_speed_m_s`,
  `start_time_s` (instant sur l'horloge `NukeClock`), `burst_height_km` (**règle de jeu : 500 m par défaut**, `NukeScaling.DEFAULT_BURST_HEIGHT_KM` ; 0 = au sol). À
  500 m, la boule de feu touche encore le sol à partir de ~1 Mt (rayon 1,05 km) : retombées locales et poussière
  aspirée ; à 10 kt, c'est une explosion aérienne (pas de retombées locales), et à 100 kt seulement en partie
  (`NukeScaling.low_burst`, 1 au sol, 0 au-dessus de 2 rayons de boule de feu). Jamais de
  cratère,
  `over_ocean` (point zéro sur une mer ou un océan, renseigné au tir, voir « Explosions sur la mer »),
  `country_code` (pays du point zéro, renseigné au tir, voir « Pays touché »).
  - **Vent réel** (`nuke/nuke_wind.gd`) : au tir, le vent est lu au point d'impact dans la même carte que
	l'advection des nuages (`assets/textures/cloud_wind.exr`, vent GFS moyen du jour à 850/700/500 hPa, ~1,5 à
	5,5 km d'altitude, interpolation bilinéaire) : le trou dans la couche nuageuse dérive comme les nuages. Sans
	carte, la direction reste tirée au hasard.
  - **Profil vertical** (`wind_profile`, `NukeWind.sample_profile`) : le vent GFS du même jour à 14 altitudes, de
	~1,5 à ~64 km (`assets/textures/wind_profile.exr`), interpolé linéairement en altitude par
	`NukeParams.wind_at()` (constant sous le premier niveau et au-dessus du dernier ; vide : le vent ci-dessus
	partout). C'est lui qui fait dériver le champignon. Le tir affiche le vent au niveau du chapeau. Exemple, 15 juillet
	à 42° N : vent de sud-ouest de 12 m/s en bas, 19 m/s à 17 km (courant-jet), vents d'est stratosphériques
	au-dessus de ~20 km (43 m/s à 49 km) : un 50 Mt part vers l'ouest quand le trou dans les nuages part vers le
	nord-est.
- **Lois d'échelle** (`nuke/nuke_scaling.gd`, classe statique `NukeScaling`, coefficients en tête de fichier), W en kt :

  | Grandeur | Formule | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|---|
  | Rayon de la boule de feu | 0,066 · W^0,4 km | 0,17 km | 1,05 km | 5,0 km |
  | Rayon de choc de référence | 2 · (W/10)^(1/3) km | 2 km | 9,3 km | 34 km |
  | Sommet du nuage | interpolation (voir ci-dessous) | 8 km | 22,5 km | 65 km |
  | Rayon du chapeau | 0,6 × sommet | 4,8 km | 13,5 km | 39 km |

  Sommet du nuage stabilisé (`CLOUD_TOP_POINTS`, interpolation log-log). Les hauteurs réelles varient beaucoup avec
  la météo et la tropopause (Glasstone & Dolan §2.16) :

  | Puissance | Sommet | Référence |
  |---|---|---|
  | 10 kt | 8 km | choix de jeu, entre l'exemple « typique » de Glasstone & Dolan (19 000 ft, 5,8 km, §2.17) et Nagasaki |
  | 20 kt | 11 km | « 7 miles » (Glasstone) ; Nagasaki (21 kt) : 45 000 ft (13,7 km) |
  | 1 Mt | 22,5 km | « 14 miles » (Glasstone) |
  | 15 Mt | 40 km | Castle Bravo ; Ivy Mike (10,4 Mt) : ~40 km |
  | 50 Mt | 65 km | Tsar Bomba (64 à 67 km) |

  Un champignon de 10 kt (8 km) reste sous le sommet d'une couche nuageuse épaisse (jusqu'à 10 km) : il n'est visible
  que par ciel dégagé ou à travers le trou creusé par l'onde de choc.

  Depuis 400 km, un pixel vaut ~0,5 km au nadir : la boule de feu de 10 kt (0,3 km de diamètre) fait moins d'un
  pixel ; c'est l'éblouissement du flash (billboard de taille angulaire minimale) qui la rend visible.

  Flash (même fichier) : puissance thermique au second maximum **P = 4 · W^0,56 kt/s** (Glasstone & Dolan,
  *The Effects of Nuclear Weapons*, §7.88), rayonnée dans toutes les directions, en « soleils » (1 361 W/m²) à la
  distance de référence de 400 km. **L'atmosphère absorbe ensuite cette lumière** selon le trajet (voir
  « Absorption par l'air » ci-dessous).

  Durées réelles (même source, §7.85) : second maximum thermique à **t_max = 0,0417 · W^0,44 s** ; l'essentiel de
  l'énergie thermique est émis avant 10 t_max. Le minimum entre les deux impulsions tombe à t_min = 0,0025 · W^0,5 s.

  **Entorse au réalisme** : le flash est joué **2 fois plus vite** (`FLASH_TIME_SCALE` = 0,5), avec la même forme
  d'impulsion, et l'onde de choc est ralentie de 1,6 (voir « Onde de choc »). À leurs vitesses réelles, la traîne du
  flash et l'éblouissement masquaient toute la vie de l'anneau de condensation (qui s'évapore vers 0,7 τ : 1,8 s à
  10 kt, 8 s à 1 Mt, 30 s à 50 Mt). Désormais l'anneau survit au flash : il reste visible seul ~2 s à 10 kt, ~9 s à
  1 Mt, ~24 s à 50 Mt.

  | | 10 kt | 1 Mt | 50 Mt |
  |---|---|---|---|
  | Flux au pic à 400 km, sans atmosphère | 0,022 soleil | 0,29 soleil | 2,6 soleils |
  | Second maximum t_max (réel) | 0,12 s | 0,87 s | 4,9 s |
  | Durée réelle (10 t_max) | 1,2 s | 8,7 s | 49 s |
  | Durée jouée (× 0,5) | 0,6 s | 4,4 s | 24 s |

  Le flux décroît en 1/d² : depuis une orbite à 800 km, le flash paraît 4 fois moins fort qu'à 400 km.
- **Absorption par l'air** (`nuke/nuke_atmosphere.gd` pour l'observateur, `nuke_air_transmittance()` dans
  `nuke/shaders/nuke_flash.gdshaderinc` pour le sol et les nuages ; même calcul) : transmittance par canal (r, v, b)
  le long du segment source → récepteur. Elle utilise le modèle de la lumière solaire (`shaders/sun_light.gdshaderinc` :
  Rayleigh, hauteur d'échelle 8 km, et aérosols, 1,2 km), intégré en 8 pas resserrés près de l'extrémité basse.
  L'effet dépend donc de l'altitude du trajet :
  - vers l'espace (station), il traverse peu d'air : ~90 % transmis au nadir ;
  - près du sol (sol et nuages bas lointains), il est fortement atténué et rougi : un nuage à 100 km d'une
	explosion au sol ne reçoit plus qu'une lueur orangée ;
  - une explosion en altitude (`burst_height_km`) est moins atténuée qu'au sol.
- **Effet** (`nuke/nuke_effect.tscn`, script `nuke/nuke_effect.gd`, classe `NukeEffect`) : enfant du nœud `Earth`,
  placé au point (latitude, longitude) sur la sphère. Repère local : **Y = verticale locale**, X = est, −Z = nord,
  origine au point d'impact. Le nœud est mis à l'échelle 0,1 (`SCENE_UNITS_PER_KM`) : **ses enfants travaillent
  directement en km**, avec des coordonnées petites (bonne précision flottante). `get_time_s()` donne le temps
  physique écoulé depuis l'explosion (`time_override_s` ≥ 0 l'impose, pour rejouer l'effet).
  - Marqueurs de debug (`DebugMarkers`, `show_debug_markers`, désactivés par défaut) : boule de feu (sphère
	orange, centrée à la hauteur d'explosion), rayon de choc (anneau jaune au sol), colonne et chapeau du nuage
	(cyan, au sommet calculé). Rendus après les nuages et l'atmosphère (`render_priority` 2), masqués par la station.
- **Flash initial** (`nuke/nuke_flash.tscn`, script `nuke/nuke_flash.gd`, enfant `Flash` de l'effet). En temps
  normalisé u = t / durée jouée du flash (u = 1 ↔ 10 t_max réels), deux courbes `Curve` éditables dans la scène :
  - `intensity_curve` : part du flux au pic, avec la forme de l'impulsion thermique de Glasstone & Dolan :
	- bref premier pic (u = 0,002), puis minimum vers t_min (u ≈ 0,009) ;
	- second maximum à t_max (u = 0,1) ;
	- décroissance : 0,55 à 2 t_max, 0,3 à 3 t_max, 0,12 à 5 t_max, 0,05 à 7 t_max, 0 à 10 t_max ;
  - `growth_curve` : rayon de la boule de feu, en part du rayon final (5 % au départ, 45 % à t_min, 90 % à t_max,
	100 % à 3 t_max).

  Les tangentes des courbes valent la pente entre les points voisins (nulles aux extrema), sinon la courbe
  d'Hermite forme des paliers (l'éclat décroîtrait par marches). Elles sont lues avec `sample()` : la version
  précalculée (`sample_baked()`, 100 points) effacerait le premier pic.

  Il affiche :
  - **la boule de feu** (`nuke/shaders/nuke_fireball_flash.gdshader`) : sphère additive dont la luminance est
	physique, flux / angle solide rapportés au soleil (disque solaire = 40 000), plafonnée à 50 000 (format 16 bits).
	Elle est rendue avant les nuages (`render_priority` −1) : un banc nuageux la voile. Son rayon affiché est d'au
	moins 1,5 pixel (`min_fireball_pixels`), avec la luminance recalculée sur ce rayon (même flux total) : sinon,
	pour 10–100 kt, la sphère plus petite qu'un pixel apparaît et disparaît en défilant sous la station, et le flash
	décroît par saccades ;
  - **l'éblouissement** (`nuke/shaders/nuke_flare.gdshader`) : billboard additif (halo, cœur, étoile à 4 branches)
	construit en espace vue et ramené à mi-distance, pour passer devant la Terre et les nuages tout en restant
	masqué par la station. Taille angulaire et intensité suivent le flux reçu par l'observateur (1/d² ×
	transmittance de l'air, nul si la Terre cache le flash) ; réglages dans le groupe « Éblouissement » du script.
	Le cœur et les branches sont élargis à au moins un pixel (à énergie constante), pour ne pas scintiller quand le
	halo est petit.
- **Onde de choc** (`nuke/nuke_shock.tscn`, script `nuke/nuke_shock.gd`, enfant `Shock` de l'effet). Le front de
  choc ne brille que tant qu'il forme la surface de la boule de feu (première fraction de seconde, cf. le creux du
  double pic du flash). Une fois détaché, il refroidit et devient transparent : à 0,7 bar de surpression, l'air
  n'est chauffé que d'~50 °C. Ce qui brûle au loin, c'est le rayonnement thermique (voir « Incendies »). Depuis
  l'espace, on voit donc seulement :
  - **l'anneau de condensation** (nuage de Wilson) : la détente derrière le front refroidit l'air humide, qui
	condense un bref instant. Il est blanc, éclairé par le soleil (presque invisible de nuit) et suit le front. Il
	apparaît à p = 0,03, culmine à 0,12 et s'évapore à 0,5. Le front monte nettement côté intérieur et se dégrade
	vers l'extérieur ; son épaisseur s'amincit de 5 % à 1,2 % de R_max ;
  - **la jupe de poussière** autour du point zéro, pour les explosions basses (hauteur < ~2 rayons de boule de
	feu). Gris-brun (poussière mêlée de fumée), elle est soulevée par le front dès p = 0,05 et s'étend avec lui
	jusqu'à 60 % de R_max. Elle retombe ensuite lentement (constante de temps 8 τ). Vue en oblique, le voile
	atmosphérique réduit beaucoup son contraste ; elle ressort mieux près du nadir. Sur la mer, ce sont des
	**embruns** (eau pulvérisée) : même jupe, blanche (`spray` du shader).

  Rayon du front **r(t) = R_max · (1 − exp(−t / τ))**, avec une progression p = r / R_max :
  - R_max = `NukeScaling.shock_max_radius_km` = 1,2 × rayon de choc de référence + 4 km (`SHOCK_VISUAL_SCALE`,
	`SHOCK_VISUAL_MIN_KM`) : 6,4 km à 10 kt, 15 km à 1 Mt, 45 km à 50 Mt. **Choix visuel** : plus grand que le rayon
	de référence, surtout pour les petites puissances, pour que le trou creusé dans les nuages se voie (voir
	« Nuages ») ;
  - ce front unique porte l'anneau de condensation, soulève la poussière et **pousse les nuages devant lui** : le
	trou dans la couche nuageuse a exactement le même rayon à chaque instant ;
  - τ = 1,28 s par km de R_max serait la valeur réaliste : le front atteindrait 90 % de R_max à ~0,34 km/s de
	moyenne (la vitesse du son), avec une vitesse initiale de ~0,8 km/s ;
  - **entorse au réalisme** : l'onde est ralentie de `SHOCK_SLOWDOWN` = 1,6 (τ = 2,05 s/km : ~0,5 km/s au départ,
	~0,2 km/s de moyenne), pour que l'anneau de condensation survive au flash (voir « Flash ») ;
  - l'anneau s'évapore vers 2,8 s à 10 kt, 13 s à 1 Mt, 48 s à 50 Mt ; le front atteint 98 % de R_max en ~16 s à
	10 kt, ~74 s à 1 Mt, ~270 s à 50 Mt (temps physique ; au-delà de 20 s, l'horloge accélère progressivement, voir
	« Horloge »).

  Shader unique et réutilisable (`nuke/shaders/nuke_shock_ring.gdshader`) :
  - un quad horizontal surélevé de 30 m, dont le centre est l'origine du maillage ;
  - paramètres par instance : rayon, demi-côté du quad, largeur du front, opacités de condensation et de
	poussière, rayon maximal de la poussière ;
  - matériau éclairé par les lumières de la scène, sans lumière ambiante, irrégularités par un bruit de valeur ;
  - largeurs élargies à au moins un pixel ;
  - rendu avant les nuages (`render_priority` −1) : un banc nuageux le voile.

  Réglages dans le script : groupes « Condensation » et « Poussière », `lift_km`.
- **Incendies et trace au sol** (règle de jeu ; nœud `GroundFX`, classe `NukeGroundFX`, créé par `NukeLauncher` ;
  `nuke/shaders/nuke_fire.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` ; lois dans `NukeScaling`,
  constantes `FIRE_*` et `SCAR_*`). Ils sont allumés par le flash dans le rayon où l'exposition thermique dépasse ~10 cal/cm²
  (inflammation des matériaux courants, Glasstone & Dolan ch. VII), **s'étendent pendant plusieurs jours** et
  laissent une **trace au sol jusqu'à la fin de la partie**.
  - Rayon initial R0 : 12 km · (W / 1 Mt)^0,41, soit ~1,8 km à 10 kt, 12 km à 1 Mt et ~60 km à 50 Mt
	(`NukeScaling.fire_base_radius_km`).
  - Zone du flash, calée sur Hiroshima (tempête de feu formée ~20 min après l'explosion, au plus fort vers 2–3 h) :
	25 % de l'intensité finale dès le flash (foyers allumés par le rayonnement thermique), foyers qui se rejoignent
	entre 2 min et 1 h 30 ; intensité maximale ~0,8 vers 1 h 30.
  - Propagation : le front gagne les terres alentour, rayon R0 · (1 + 1 · (1 − exp(−t / 1 jour)))
	(`FIRE_SPREAD`, `FIRE_SPREAD_S`, `NukeScaling.fire_radius_km`) : 63 % du chemin en 1 jour, 95 % en 3 jours,
	jusqu'à 2 R0 (24 km à 1 Mt) ; au départ ~0,5 km/h pour 1 Mt, l'allure d'un feu de forêt. Un lieu atteint par le
	front s'embrase en 1 h, moins fort que la tempête de feu (30 %) : **un anneau de feu s'éloigne du centre**.
  - Chaque lieu brûle avec une constante de temps d'extinction de 6 h (`FIRE_BURN_S`) : le centre est éteint en
	~1 jour, les derniers feux du front en 4 à 5 jours.
  - **Trace au sol** (règle de jeu : pas de cratère, explosion à 500 m ; la partie dure quelques semaines, aucune
	repousse visible : la trace est **définitive**). Deux causes, toutes deux fonction de la puissance :
	- **le feu** : chaque lieu brûlé noircit en 2 h (`FIRE_CHAR_S`, charbon `nuke_burn_albedo`), puis **brunit**
	  entre 12 h et 4 jours après son passage (`SCAR_BROWN_START_S`, `SCAR_BROWN_END_S` : cendres envolées,
	  végétation morte) : terre brûlée brun sombre (`nuke_scar_albedo`, réflectance de ~5 à 8 % comme les cicatrices
	  de brûlis sur les images satellites, plus sombre qu'un sol aride), sans verdure. Plus marquée dans la zone du
	  flash, motif irrégulier ;
	- **le souffle** : dans le rayon de 5 psi (`SCAR_RUBBLE_PSI` : bâtiments rasés, forêts couchées), gravats et
	  poussière gris-brun (`nuke_rubble_albedo`) dès l'explosion, même sans incendie.

	Mélange jusqu'à 95 % (`nuke_scar_strength`) ; le relief du sol d'origine reste un peu visible
	(`nuke_scar_relief`) ; dans les villes, la trace tire vers le gris des gravats. Seulement sur les terres. Étendue :
	~2 km de rayon à 10 kt (à peine une tache depuis l'orbite), ~24 km à 1 Mt, ~120 km à 50 Mt (une région entière
	meurtrie ; dix 50 Mt couvrent un pays). Vue de biais à plusieurs centaines de km, la brume atmosphérique atténue
	nettement le contraste (comme sur les photos obliques prises depuis l'ISS) ; vue plongeante, la trace est franche.
	Choix du rendu procédural plutôt qu'une image (PNG) plaquée : forme irrégulière propre à chaque tir, taille
	exacte quelle que soit la puissance (de 2 à 120 km), netteté à toutes les distances, sans texture à projeter
	sur la sphère.
  - Toutes les durées sont en temps physique, au rythme du jeu après la première demi-heure (voir « Horloge ») :
	les incendies durent donc plusieurs jours de la partie.
  - Rendu des flammes, en émission sur le sol :
	- la part du sol en feu est forte au centre (l'exposition décroît en 1/d²) ;
	- seulement sur les terres : **une mer ou un océan ne brûle pas**. Masque des terres : la carte des pays
	  (`assets/textures/country_ids.png`, 0 = mer, ~2,4 km par pixel, interpolée pour adoucir la côte,
	  `nuke_land_share` dans `nuke/shaders/nuke_ground.gdshaderinc`) ; le masque d'eau déduit de la couleur du sol ne
	  suffit pas (en espace linéaire, les mers de Blue Marble sont trop sombres pour qu'il les reconnaisse). Une explosion en mer
	  sans aucune terre dans le rayon des incendies (`OceanMask.has_land_within`, `NukeEffect.can_ignite_land`)
	  n'allume rien ; près d'une côte, le flash enflamme les terres à portée ;
	- plus forte et plus vive dans les villes (combustible, lu dans l'image des lumières nocturnes) ;
	- modulée par un motif irrégulier dont l'échelle suit la taille de la zone ;
	- bord très irrégulier, léger scintillement ;
	- voilée par les nuages comme les lumières des villes.
  - Depuis l'orbite (~0,5 km par pixel), on ne voit pas les flammes une à une, mais la lueur moyenne des zones en
	feu. Elle est faible devant un sol au soleil : les incendies se voient surtout de nuit.
  - **Aucun plafond sur le nombre d'explosions** (`NukeGroundFX`, `nuke/shaders/nuke_ground.gdshaderinc`) : chaque
	explosion est une colonne d'une texture de données (centre, temps physique, rayons : zone détruite, panne
	régionale, incendies, portée ; vent de la fumée ; rayon des gravats). Une maille de 1° (360 × 180) indexe les
	explosions dont la portée la touche : un pixel du sol ne teste que les explosions proches. Seuls les temps sont
	renvoyés à chaque image ; la maille est reconstruite à chaque tir. Les mêmes textures servent au black-out et à
	la fumée (qui a sa propre maille, voir ci-dessous).
- **Fumée des incendies** (règle de jeu ; `nuke/shaders/nuke_smoke.gdshaderinc`, inclus dans
  `shaders/earth_surface.gdshader` ; données et maille par `NukeGroundFX` ; lois dans `NukeScaling`, constantes
  `SMOKE_*`). Tant que les incendies brûlent (plusieurs jours), leur fumée est emportée par le vent réel GFS à 4 km
  (`SMOKE_HEIGHT_KM`) en un panache de centaines de km.
  - **Modèle** : panache gaussien intégré sur la verticale (modèle classique de dispersion). La fumée émise à
	l'instant t − a est, à l'instant t, à u · a sous le vent (le long du grand cercle), étalée sur
	σ(a)² = σ0² + 2 K a (σ0 = 0,7 R0, taille du foyer ; K = 5·10⁴ m²/s, diffusion à méso-échelle), et se dépose en
	4 jours (`SMOKE_LIFETIME_S`). Épaisseur optique verticale
	τ = MEE · Q(t − a) · e^(−a/L) / (u · √(2π) · σ) · exp(−y² / 2σ²) ; le panache est tronqué progressivement vers
	2 jours d'âge (`SMOKE_MAX_AGE_S`).
  - **Bords** : le modèle gaussien classique néglige la diffusion dans le sens du vent ; comme l'émission démarre au
	flash, le front du panache (fumée la plus ancienne, à u · t) y serait une coupure droite perpendiculaire au vent.
	Le front est donc étalé sur ±2 σ (même diffusion K que sur les côtés). Les bords sont en outre déformés par un
	bruit à l'échelle de l'étalement (±0,7 σ en distance et en écart latéral : langues et volutes), propre à chaque
	explosion. Au vent du foyer, la fumée ne déborde que de la moitié de la taille du foyer.
  - **Accumulation** : la formule du panache décrit le régime établi (la fumée part avec le vent aussi vite qu'elle
	est émise), atteint quand le vent a balayé le foyer, u · t ≈ √(2π) σ0 (2 à 3 h pour un foyer de 40 km à 10 m/s).
	Avant, la fumée s'accumule au-dessus du foyer (colonne Q · t / 2π σ0²) : le panache s'épaissit progressivement au
	lieu de couvrir d'emblée toute la zone.
  - **Débit** Q = Y · R0² · f(t) / 6 h (`FIRE_BURN_S`), où f est la surface en feu (`NukeScaling.smoke_burning_area`,
	mêmes lois que les incendies, table de 256 valeurs en échelle log, `nuke_smoke_rate`) et Y la fumée par m² en feu,
	**selon ce qui brûle** (`NukeScaling.smoke_yield_kg_m2`, calculée au tir dans le thread de `NukeImpact` : moyenne
	de 24 × 24 points des terres de la zone des incendies, population GHS-POP) :
	- végétation : 2 kg/m² de combustible consumé (`SMOKE_WILDLAND_FUEL_KG_M2` ; herbe 0,3 à 0,5, broussailles 1 à 3,
	  forêt 2 à 5, van der Werf et al. 2017), facteur d'émission 1,2 % (`SMOKE_WILDLAND_EF`, Andreae 2019) ;
	- bâti : 0,011 kg/m² par hab./km² (`SMOKE_URBAN_FUEL_KG_M2_PER_HAB_KM2` : 1,1·10⁷ g par habitant, Toon et al. 2007
	  § 6.1 ; centres-villes mesurés 120 à 470 kg/m²), facteur d'émission 2 % (`SMOKE_URBAN_EF`, Small 1989).

	Mesures : 50 Mt sur la Sardaigne (~70 hab./km²), Y = 0,042 kg/m² ; 1 Mt sur Paris, Y = 1,17 kg/m² (28 fois plus).
	Repère : 100 explosions de 15 kt sur des mégapoles donnent 1 à 5 Tg de suie (Toon et al. 2007). Efficacité
	d'extinction 5 m²/g (`SMOKE_MEE_M2_KG` ; Toon et al. citent 4,4 à 7 m²/g). Une 50 Mt sur une île rurale : voile
	léger à 30 min, épaississement sur 2 à 3 h, panache épais sous le vent ensuite (l'île entière brûle : le rayon
	d'inflammation, ~60 km, couvre presque toute la Sardaigne) ; sur une grande ville, panache bien plus opaque.
	Version précédente (corrigée) : tout sol en feu était traité comme une ville (~0,65 kg/m²), soit ~15 fois trop
	de fumée en campagne, et le panache atteignait d'emblée son régime établi.
  - **Rendu** : couche plate sous les nuages (fumée de 1 à 6 km ; vue de 400 km, sa parallaxe est négligeable). Elle
	voile le sol (albédo gris-brun `nuke_smoke_albedo` éclairé par le soleil, noir la nuit), les reflets de la mer et
	les lumières des villes ; la lueur des incendies la traverse en partie (`nuke_smoke_fire_glow`). Volutes : bruit à
	deux échelles (70 et 18 km) qui module τ de ±70 % et dérive lentement.
  - **Maille de la fumée** (`nuke_smoke_cells`, `nuke_smoke_index`) : chaque panache est couvert par des disques le
	long de son axe, de demi-largeur celle où τ tombe sous 0,005 (au débit maximal) ; reconstruite quand un panache
	s'allonge d'environ 10 % ou disparaît.
  - Limites : vent constant (celui du point zéro le jour du tir) ; fumée sous les nuages (un pyrocumulonimbus qui
	monte au-dessus des nuages n'est pas rendu au-dessus) ; pas d'ombre du panache.
- **Champignon** (`nuke/nuke_mushroom.tscn`, script `nuke/nuke_mushroom.gd`, enfant `Mushroom` de l'effet ;
  shaders `nuke/shaders/nuke_mushroom_volume.gdshader`, `nuke/shaders/nuke_mushroom.gdshader` et
  `nuke/shaders/nuke_smoke.gdshader`).
  - **Rendu volumétrique** (par défaut, `volumetric`) : lancer de rayon dans un champ de densité, sur une boîte
	englobante (nœud `Volume`) recalculée à chaque image autour du nuage, de sa dérive et du nuage de base.
	- Densité : formes analytiques fondues en douceur, érodées par un bruit 3D sur une bande `edge_softness` (bords
	  gazeux) :
	  - chapeau : super-ellipse aplatie (`cap_power` 2,6 : dessus plat, bord arrondi), dessous creusé autour de la
		tige ;
	  - tige : évasée au pied et sous le chapeau, dissoute avec l'âge ;
	  - nuage de base.
	- **Asymétrie** : une déformation basse fréquence du domaine (`warp`) et des lobes autour du chapeau (`lobes`),
	  tirés d'une graine propre à chaque explosion (latitude, longitude, puissance), rendent la silhouette
	  irrégulière. S'y ajoute l'inclinaison par le vent.
	- Éclairage comme les nuages de la couche : marche vers le soleil (5 pas doublés depuis 0,3 km, auto-ombrage,
	  loi de Beer et diffusion multiple approchée), phase double de Henyey-Greenstein, soleil filtré par
	  l'atmosphère, ciel ambiant. La lueur de la boule de feu est émise au cœur du chapeau. Extinction : 1 km⁻¹
	  (`volume_extinction_per_km`). **Pas de lumière selon la dilution** (`NukeMushroom.LIGHT_STEPS_BY_FADE`) : 5
	  tant que la densité `fade` ≥ 0,25, 3 au-dessus de 0,08, 2 en dessous — un voile dilué n'a presque plus d'ombre
	  propre (à 3 % de densité, 2 pas au lieu de 5 : PSNR > 65 dB, pour ~45 % du coût du volume à ce stade).
	- 64 pas par rayon sur la traversée de la boîte englobante, décalage d'échantillonnage fixe par pixel (pas de
	  bruit temporel) : pas de scintillement. **Saut du vide** (`core_interval` du shader, `skip_empty`) : le script
	  fournit aussi la **boîte cœur** (`core_min`/`core_max`, le nuage sans sa dérive) ; la boîte englobante est
	  cette boîte cœur étendue à toutes les dérives des hauteurs occupées, et le cisaillement du vent (vent différent
	  au-dessus et au-dessous du chapeau) peut la rendre énorme : à 6 h d'un 50 Mt, ~1 400 km de long pour un chapeau
	  de ~110 km, surtout vide. La dérive étant linéaire par morceaux en hauteur (32 échantillons), le point « sans
	  dérive » est linéaire en t sur chaque morceau : le shader calcule exactement l'intervalle du rayon qui traverse
	  la boîte cœur (test de boîte 2D par morceau) et ne marche que là, avec le pas de la traversée complète (au
	  moins `min_steps` = 16 pas) ; un rayon qui la manque est rejeté sans aucune lecture de texture. Rendu
	  identique (même champ de densité), mesure à 6 h d'un 50 Mt : volumes 12 → 4 ms en 1080p. Les trous de
	  fragmentation (`breakup`) sont testés avant le bruit fin : dans un trou, rien d'autre n'est calculé.
	- **Perspective aérienne** (`aerial_perspective` dans le shader) : la couleur du champignon est atténuée par l'air
	  traversé entre la caméra et lui (premier point dense), et le voile de l'air diffusé y est ajouté, avec le même
	  modèle que `shaders/atmosphere.gdshader` (Rayleigh, Mie, ozone, étirement ×2,5, intensité solaire 9 ; 12 pas
	  resserrés vers le champignon, lumière reçue par `sun_transmittance_at`). Le volume écrit sa profondeur : la
	  coquille atmosphérique « sol », rendue après, est masquée devant lui ; sans ce calcul, un champignon vu en
	  rasant vers l'horizon restait aussi net qu'à la verticale, alors que le sol derrière lui était voilé.
	- Profondeur écrite par le shader : là où le pixel est presque opaque (alpha total > 0,8, `depth_alpha`), celle
	  du premier point dense (alpha cumulé > 0,35, `depth_first`), sinon le plan lointain (rien n'est masqué derrière
	  le bord ténu ; un point juste au-dessus du sol masquait, vu à l'horizon, le limbe lumineux de l'atmosphère
	  derrière le champignon, dont le bord se détachait alors sur le noir de l'espace : liseré noir). Les nuages
	  et l'atmosphère, rendus après, ne le recouvrent que là où ils sont devant lui : c'est cette profondeur qui rend
	  le champignon visible au-dessus d'un banc nuageux. Un panache ténu (alpha < 0,8) est donc caché par les nuages
	  qu'il survole, mais reste visible au-dessus d'un sol dégagé. Avec l'ancien seuil (0,35 sur l'alpha cumulé), le
	  bord d'un panache qui s'étiole au-dessus des nuages scintillait : chaque pixel y basculait entre « panache sur
	  le sol, nuages masqués » (gris) et « nuages » (blanc), selon le décalage d'échantillonnage. À 0,8, les deux
	  aspects sont proches (mesure : 302 pixels changeant brutalement en 2 s de temps physique à 1 h 30 d'un 10 Mt,
	  contre 2).
	- Coût mesuré (2026-10-16, après le saut du vide, 10 × 50 Mt figés, 5120 × 1440) : ~1,3 ms à 1 min, ~6,6 ms à
	  6 h (25,7 ms avant ; voir « Performances » ; sonde `tools/bench/mushroom_probe.tscn`).
	- Les sections « Maillage de révolution », « Shader » et le nuage de base `BaseSurge` ci-dessous décrivent le
	  rendu par maillage, conservé pour comparaison (`volumetric = false`) ; formes, Curves, couleurs, roulement et
	  dérive sont partagés.
  - **Repère normalisé** : le nœud est mis à l'échelle `cloud_top_km`, tout est exprimé en unités où le sommet
	final vaut 1 (chapeau final de rayon 0,6). Le même champignon fait 8 km de haut à 10 kt, 22,5 km à 1 Mt et
	65 km à 50 Mt, particules comprises.
  - **Maillage de révolution** fixe (96 anneaux × 128 segments). Le profil (méridienne de 48 points : tige au pied et
	au col évasés, puis chapeau à dessous creusé, bord arrondi et dessus aplati) est recalculé à chaque image et
	posé par le vertex shader, qui l'interpole entre ses points.
  - **Dérive au vent** (`nuke/nuke_mushroom_drift.gd`, classe `NukeMushroomDrift` ; `nuke/shaders/nuke_drift.gdshaderinc`) : profil vertical du vent réel GFS
	au point d'impact (`NukeParams.wind_profile`, voir « Paramètres »). Chaque altitude part avec son propre vent :
	- le déplacement est calculé en 32 hauteurs (0 à 1,4 sommet final) et interpolé par les shaders (volume,
	  maillage) et pour les émetteurs de particules ;
	- pendant la montée (10 min), une parcelle garde sa hauteur relative dans le nuage qui monte : son déplacement
	  intègre le vent des altitudes traversées (16 pas). Ensuite, chaque hauteur avance au vent de son altitude ;
	- le pied reste au point zéro : sous le centre du chapeau, la dérive est multipliée par (y / centre)^`drift_shear`
	  (1,5), la tige penche ;
	- **cisaillement** : le vent diffère au-dessus et au-dessous du centre du chapeau. Le chapeau s'étire en panache
	  dans le sens du cisaillement (en « stade » : un disque décalé le long d'une direction) et se tord quand la
	  direction change avec l'altitude. Exemple (1 Mt, 42° N, 15 juillet) : courant-jet vers 13 km, vent presque nul
	  vers 21 km, le panache s'étend sur ~80 km en 1 h ;
	- le bruit fin ne subit que 20 % du cisaillement (`noise_shear`) : étiré sur des dizaines de km, il se
	  décorrélerait d'un pas de la marche à l'autre (grain, stries). La forme le subit en entier.
  - **Dissipation** (« Le nuage peut rester visible une heure ou plus avant d'être dispersé par les vents dans
	l'atmosphère environnante, où il se confond avec les nuages naturels », Glasstone & Dolan §2.16). Après la
	stabilisation (t > 10 min), constantes de `NukeScaling` :
	- **étalement** par la turbulence : R² = R0² + 4 K (t − 10 min), K = 2·10⁴ m²/s (`CLOUD_SPREAD_K_M2_S`, ordre de
	  grandeur de la diffusivité horizontale aux échelles de 10 à 100 km). Rayon du chapeau : 1 Mt, 13,5 km →
	  ~21 km à 1 h, ~36 km à 4 h ; 10 kt, 4,8 km → ~16 km à 1 h ;
	- **amincissement** : épaisseur × (R0 / R)^0,5 (`CLOUD_THIN_EXP`), centre du chapeau fixe ;
	- **dilution** (masse conservée) : densité × (R0 / R)^1,5, soit une épaisseur optique vue de dessus × (R0 / R)² ;
	- **disparition** (évaporation, dépôt, mélange) : × exp(−(t − 10 min) / τ), τ = 1 h pour un chapeau dans la
	  troposphère, 2 h au-dessus de la tropopause (air sec et stable, pas de précipitations), avec un passage
	  progressif sur ±2 km. Tropopause : 17 km à l'équateur, 9 km aux pôles, en cos² de la latitude
	  (`NukeScaling.tropopause_km`) ;
	- **fragmentation** : le nuage dilué se déchire en lambeaux (trous de bruit basse fréquence, seuil 0,55 ×
	  (1 − √densité), `breakup` du shader) ; la déformation verticale du domaine est réduite de R0 / R (couche mince) ;
	- le champignon est masqué sous 1 % de densité : ~2 h après un 10 kt, ~6 h après un 1 Mt (temps physique ;
	  ~1 h 30 et ~5 h 30 d'horloge, soit une à plusieurs orbites). Effet visible : à 1 Mt, chapeau net à 30 min, panache
	  étiré à 1 h, voile ténu à 2 h ;
	- la boîte englobante suit les hauteurs occupées : une fois la tige dissoute, elle ne descend plus jusqu'au sol
	  et ne couvre que la dérive du chapeau (qui peut être à des centaines de km du point zéro) ;
	- rendu par maillage : opacité × la même densité.
  - **Contact avec le sol adouci** : l'opacité du champignon monte depuis 0 au sol jusqu'à 4 % du sommet final
	(`ground_fade` du shader), avec une limite rongée par le bruit.
  - **Nuage de base** (`BaseSurge`, explosions basses) : dôme de poussière bas, même shader et même couleur que le
	champignon.
	- Il s'étend vers l'extérieur avec l'onde de choc : rayon = 0,8 × front de choc (`surge_shock_ratio`), hauteur
	  = 8 % de ce rayon (`surge_aspect`).
	- Translucide (`surge_opacity` 0,6), dense au centre, effiloché au bord.
	- Il s'estompe en même temps que la tige se dissout (même érosion).
  - **Profil piloté par des Curves** (éditables dans la scène), lues en âge a = t / 600 s physiques
	(`MUSHROOM_RISE_S`). Le nuage se stabilise en ~10 min quelle que soit la puissance, soit ~1 min 36 s
	d'horloge avec l'accélération des phases lentes :
	- `height_curve` : sommet, calé sur la montée d'un nuage de 1 Mt (Glasstone & Dolan 1977, §2.12, sommet final
	  14 miles) : 14 % à 18 s, 29 % à 42 s, 43 % à 1 min 06, 71 % à 2 min 30, 86 % à 3 min 48, 96 % à 6 min ;
	- `cap_radius_curve` (rayon du chapeau), `cap_aspect_curve` (épaisseur / diamètre ; 1 = sphère),
	  `stem_curve` (rayon de la tige / rayon du chapeau) ;
	- `erosion_curve` (domaine 0 à 3) : la tige se dissout après la stabilisation.
  - **Boule de feu** : au départ, le chapeau est une sphère de la taille de la boule de feu du flash, centrée à la
	hauteur d'explosion. Le flash s'estompe en la révélant, puis elle monte et s'aplatit en chapeau.
  - **Couleurs selon l'âge** :
	- lueur interne, au cœur du chapeau, `glow_gradient` × `glow_curve` × `glow_hdr` (200) : blanc, jaune,
	  orange, rouge sombre, éteinte. Elle est lue en g = t / 70 t_max (`NukeScaling.fireball_glow_s` : ~8 s à
	  10 kt, ~1 min à 1 Mt, ~5 min 40 s à 50 Mt ; Glasstone & Dolan §2.18) ;
	- albédo (`albedo_gradient`) : roux des oxydes d'azote, puis blanc-gris de la condensation.
  - **Shader** :
	- relief : bruit 3D (3 octaves) et bourgeons « chou-fleur » (bruit en valeur absolue) qui déplacent les
	  sommets ; au pixel, la normale est perturbée par le gradient des bourgeons (`bump`). Ce détail plus fin que le
	  maillage s'efface quand il devient plus petit qu'un pixel (sinon il crénèle en grains sombres). Creux et
	  dessous du chapeau assombris ;
	- éclairage par le soleil seul, en diffus enveloppant, filtré par l'atmosphère au point
	  (`sun_light.gdshaderinc` : rougi au crépuscule, éteint la nuit), plus la lumière du ciel en émission ;
	- silhouette adoucie par effet fresnel, bords rasants effilochés, érosion de la tige ;
	- **roulement toroïdal** : dans chaque plan méridien, le bruit du chapeau est lu en coordonnées tournées
	  autour de l'anneau tourbillonnaire (rayon 0,55 × chapeau). Le motif monte au centre, s'écarte au sommet,
	  redescend au bord et rentre par-dessous. Tour en 15 min physiques au début (`roll_period_s` : circulation de
	  quelques dizaines de m/s autour d'un anneau de plusieurs km ; ~1 min 30 à l'écran avec l'horloge à ×10), puis
	  de plus en plus lent (ω = ω0 / (1 + t / 300 s), intégré : rejouable au scrubber). Le bruit de la tige défile
	  vers le haut à ~35 m/s à 1 Mt, ~100 m/s à 50 Mt (`stem_rise_speed` = 0,0015 × sommet par s) ; bouillonnement
	  lent (`boil_rate`). Vus depuis l'orbite, ces mouvements doivent rester à peine perceptibles. Ces réglages valent
	  pour les deux rendus ;
	- rendu avant les nuages (`render_priority` −1) avec pré-passe de profondeur : les nuages et l'atmosphère ne
	  le recouvrent pas là où il les dépasse, mais un champignon plus bas que la couche nuageuse (10 kt sous un
	  banc épais) reste caché dessous.
  - **Particules** (GPUParticles3D créés par le script, bouffées procédurales par bruit, éclairées comme le nuage) :
	- fumée le long de la tige (rendu par maillage seulement : en volumétrique, elle ferait doublon avec la tige du
	  volume) ;
	- jupon de condensation : anneaux autour de la tige pendant la montée (a de 0,03 à 0,3) ;
	- débris et poussière aspirés au pied (explosions basses, a < 0,5).

	Leur vitesse suit celle du temps physique (`speed_scale` : pause et accélération de l'horloge). Elles ne se
	rejouent pas au scrubber. Pas de *soft particles* : elles liraient la texture de profondeur, peu fiable sous
	D3D12 dans ce projet ; les bords sont adoucis par la forme. Pas de flipbook (aucun dans le projet).
- **Black-out électrique** (règle de jeu ; `nuke/nuke_grid_impact.gd`, classe `NukeGridImpact` ; `nuke/nuke_ground_fx.gd`, classe `NukeGroundFX`, nœud `GroundFX` créé par
  `NukeLauncher` ; `nuke/shaders/nuke_blackout.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` ; lois et
  durées dans `NukeScaling`, constantes `BLACKOUT_*`). **Le black-out dure jusqu'à la fin de la partie** : réseau
  détruit, aucune remise en état pendant une guerre nucléaire. Seules les lumières des villes s'éteignent : **de jour, rien
  ne se voit** ; au crépuscule, les villes s'allument autour d'une zone qui reste noire (la panne multiplie
  l'allumage progressif des lumières, du soleil à +2° jusqu'à −7° sous l'horizon) ; à l'aube tout s'éteint
  ensemble. Une ville éteinte retombe à la lueur de la campagne non éclairée (quasi noire, gris bleuté), pas à une
  version atténuée d'elle-même. Les incendies restent visibles dans le noir. Trois couches :
  1. **Zone détruite** : rayon de 2 psi (`BLACKOUT_DESTROYED_PSI` : réseau, postes, bâtiments ; 1,8 km à 10 kt,
	 8,5 km à 1 Mt, 31 km à 50 Mt), éteinte dès l'explosion et pour de bon, bord irrégulier.
  2. **Panne régionale en cascade** : disque de 120 km · (W / 1 Mt)^(1/3) (`BLACKOUT_REGION_1MT_KM` : ~26 km à
	 10 kt, ~440 km à 50 Mt ; au moins 2 fois la zone détruite). Le front de la panne avance du centre vers le bord
	 (R · (1 − exp(−t / 15 s))), par plaques d'une vingtaine de km (quartiers, communes : bruit fixe), et reste
	 éteint.
  3. **Panne nationale** : au tir, `NukeGridImpact.assess()` (dans le thread de `NukeImpact`) cherche les centrales détruites (rayon de 5 psi,
	 `BLACKOUT_PLANT_PSI`) dans la Global Power Plant Database (`scripts/power_plants.gd`, classe `PowerPlants`,
	 `assets/power_plants.res`). Si elles représentent au moins 10 % de la capacité du pays
	 (`BLACKOUT_NATIONAL_SHARE`), tout le pays s'éteint, à ses frontières (carte `assets/textures/country_ids.png`
	 lue par le shader), par plaques en 5 à 30 s (effondrement de la fréquence), et reste éteint. Repère : la panne
	 de la péninsule ibérique du 28 avril 2025 (Espagne et Portugal éteints en quelques secondes). Le pays retenu est
	 celui du point zéro (en mer : celui qui perd le plus de capacité). Les pays dans le noir sont transmis au shader
	 par une texture indexée par pays (`nuke_ground_countries`), sans limite de nombre.
  - Console :
	```
	  réseau électrique : 2 centrale(s) détruite(s), 2923 MW : DOEL 4 (Nuclear, 2910 MW), Loghidden City (Solar, 13 MW)
		Belgique perd 23,0 % de sa capacité (12693 MW) : black-out national
	```
	Exemples de centrales qui déclenchent seules une panne nationale : Doel (Belgique, 23 %), Paks (Hongrie, 30 %),
	Kozloduy (Bulgarie, 22 %), Guri (Venezuela, 28 %). La France (111 GW recensés), l'Espagne (78 GW) ou le Japon
	(215 GW) ne s'éteignent pas pour une seule centrale.
  - Les plaques basculent sur une fenêtre de temps (5 % de la date, au moins 2 s) : pas de clignotement. Le motif
	des plaques est fixe (centré sur l'explosion, ou en coordonnées planétaires à échelle constante pour un pays).
  - Mesure : 1 Mt sur Anvers, de nuit : Belgique noire à 10 min, et pour le reste de la partie.
  - Limites : la base recense ~70 % de la capacité mondiale (surtout les grosses centrales, qui comptent ici) ; les
	réseaux interconnectés (une panne qui déborde sur les pays voisins) et l'impulsion électromagnétique d'une
	explosion en haute altitude ne sont pas simulés.
- **Pertes humaines** (`nuke/nuke_casualties.gd`, classe `NukeCasualties` ; `nuke/nuke_fallout.gd`, classe
  `NukeFallout` ; règle de jeu). Au tir, le nœud `Impact` (`NukeImpact`) calcule hors du fil principal le bilan final du souffle et de la chaleur
  (`NukeEffect.casualties`), puis les retombées (`NukeEffect.fallout`). Les pertes
  s'affichent **en temps réel** sur l'écran « Bilan des explosions » (voir « Contrôles ») et le bilan en
  console, par pays :
  ```
  NukeLauncher : 1 Mt sur 47.56°, 7.59° (Suisse) (…)
	souffle et chaleur, bilan final (OTA 1979, population 2030) : 222 000 morts, 161 000 blessés, 604 000 personnes à plus de 1 psi
	  Suisse : 200 000 morts, 94 400 blessés, 2,33 % de la population
	  Allemagne : 14 100 morts, 47 600 blessés, 0,02 % de la population
	  France : 8 110 morts, 19 200 blessés, 0,01 % de la population
  ```
  - **Modèle** : celui de l'Office of Technology Assessment (*The Effects of Nuclear War*, 1979, ch. II), tiré des
	pertes d'Hiroshima. Souffle, chaleur et rayonnement initial confondus, la part de tués et de blessés ne dépend
	que de la surpression de crête au sol :

	| Surpression | Tués | Blessés |
	|---|---|---|
	| > 12 psi | 98 % | 2 % |
	| 5 à 12 psi | 50 % | 40 % |
	| 2 à 5 psi | 5 % | 45 % |
	| 1 à 2 psi | 0 | 25 % |

  - **Surpression** : équation de Brode (1986, `NukeScaling.overpressure_psi`, précision ~10 %), selon la puissance,
	la distance et la hauteur d'explosion ; `NukeScaling.overpressure_range_km` en donne les rayons (recherche
	dichotomique). Vérifications : 1 Mt au sol, 5 psi à 4,65 km et 1 psi à 14,3 km ; Hiroshima (15 kt à 580 m),
	5 psi à 1,6 km.

	| Au sol | 12 psi | 5 psi | 2 psi | 1 psi |
	|---|---|---|---|---|
	| 10 kt | 0,6 km | 1,0 km | 1,8 km | 3,1 km |
	| 1 Mt | 2,85 km | 4,65 km | 8,5 km | 14,3 km |
	| 50 Mt | 10,5 km | 17,1 km | 31,5 km | 52,5 km |

  - **Population** : grille GHS-POP 2030 (`scripts/population_grid.gd`, classe `PopulationGrid`, données
	`assets/population_2030.bin`), ~0,9 km par cellule. Fichier découpé en tuiles de 5° : seules celles qui touchent
	la zone sont lues (cache de 24 tuiles). Cellules quantifiées sur 16 bits (habitants = (q / 64)²). Une cellule
	coupée par la limite d'une tranche est découpée en 4 × 4 sous-cellules.
  - **Pays de chaque cellule** : `CountryMask` (mêmes lignes de latitude). Une cellule littorale habitée que le
	trait de côte au 1:10 M place en mer est rattachée au pays le plus proche (jusqu'à 4 cellules).
  - Coût : 5 à 35 ms par tir (10 kt à 50 Mt).
  - Exemples (au sol sauf mention) : Hiroshima 2030 (15 kt à 580 m), ~42 000 morts ; Paris (1 Mt), ~1,3 million
	de morts ; New York (50 Mt), ~6 millions ; Sahara ou pleine mer, aucun.
  - **Chronologie** (`NukeCasualties.snapshot`, constantes `PHASE_*`), du bilan OTA de chaque pays :
	1. **flash** (dès l'explosion) : 30 % des morts (brûlures mortelles, rayonnement initial) ;
	2. **onde de choc** : 50 % des morts et tous les blessés, au passage du front à leur distance (24 anneaux par
	   pays ; `NukeScaling.shock_arrival_s`, celui du front affiché, puis la vitesse du son au-delà) : quelques
	   secondes à une minute ;
	3. **décès différés** : les 20 % restants (grands brûlés, blessés graves, victimes ensevelies), comptés d'abord
	   parmi les blessés, meurent en exp(−t / 6 h).
	Exemple (Paris, 1 Mt au sol) : 403 000 morts à 0,1 s, 828 000 à 5 s, 1,07 million à 40 s, 1,18 million à 3 h,
	1,41 million à 10 jours avec les retombées ; projection à 60 jours : 1,49 million.
  - **Retombées radioactives** (`NukeFallout`, seulement pour une explosion basse, `NukeScaling.low_burst`) :
	- champ de retombées **WSEG-10** (Weapons Systems Evaluation Group, 1959 ; documentation de Hanifen, 1980) :
	  nuage stabilisé déporté par le vent, dépôt le long d'une « ligne chaude » sous le vent, répartition
	  gaussienne en travers, correction au vent arrière. Il donne en chaque point le débit de dose à H+1 (R/h) et
	  l'heure d'arrivée des retombées ;
	- vent : le profil réel GFS au point d'impact, moyenné entre le sol et le centre du nuage (13 km à 1 Mt) ;
	  cisaillement entre les deux ;
	- fraction de fission : 1 sous 50 kt (armes à fission), 0,5 au-delà ;
	- transcription d'après le paquet *glasstone* (MIT), avec trois corrections : hauteur du nuage en mégatonnes et
	  vent en miles par heure (comme chez Hanifen), et l'exposant de la loi de dépôt calculé sans la fraction de
	  fission (déjà comptée dans le débit), sinon le débit près du point zéro était 3 à 5 fois sous les contours
	  idéalisés de Glasstone & Dolan. Vérification (1 Mt de fission, vent de 15 mph) : ~1 500 R/h à 20 miles sous le
	  vent, ~1 000 R/h vers 45 miles, ~440 R/h à 100 miles, du même ordre que ces contours ;
	- dose : débit en t^−1,2 (loi de Way-Wigner), intégré depuis l'arrivée des retombées, divisé par un facteur de
	  protection moyen des bâtiments de 3 (pas d'évacuation) ;
	- effets (irradiation aiguë, sans soins, Glasstone & Dolan ch. XII) : mort selon une loi log-normale de dose
	  médiane 4,5 Gy (écart-type 0,3 en logarithme), mal des rayons au-dessus de ~1,5 Gy (compté avec les blessés) ;
	  les morts surviennent avec un délai (constante de 6 jours), les malades qui en mourront passent des blessés
	  aux morts ;
	- les personnes déjà tuées par le souffle ne sont pas comptées deux fois ; population par blocs de 3 × 3
	  cellules (~2,8 km : le champ est lisse) ; chronologie précalculée en 48 instants (0,25 h à 60 jours) puis
	  interpolée ;
	- coût : ~50 ms à 1 Mt, ~4 s à 50 Mt (thread) ; console : vent, longueur de la zone dangereuse, morts et malades
	  à 60 jours par pays ;
	- exemples (morts à 60 jours) : Kansas City 1 Mt, ~40 000 (en plus de 64 000 pour le souffle) ; Paris 1 Mt
	  (vent de 32 m/s vers le nord-est), ~143 000 ; Paris 50 Mt, ~15 millions jusqu'en Allemagne, en Belgique et aux
	  Pays-Bas.
	- Ces jours sont des jours de la partie : après la première demi-heure, le temps physique suit l'horloge du jeu
	  (1 jour physique ≈ 1 jour d'horloge, moins de temps réel avec les vitesses x2 à x16 du panneau).
  - **Non comptés** : tempête de feu (le modèle de surpression la sous-estime pour les fortes puissances, critique
	de Postol), effets à long terme (cancers), contamination de l'eau et des aliments, évacuation et soins. Le
	modèle de l'OTA vaut pour une ville de faible hauteur ; il est discutable pour les tours modernes.
- **Pays touché** (`scripts/country_mask.gd`, classe `CountryMask`, données `assets/country_mask.res`) : au tir,
  `NukeLauncher` renseigne `NukeParams.country_code` (code ADM0_A3) avec `CountryMask.country_at(latitude,
  longitude)` ; `NukeParams.get_country()` rend la fiche du pays, vide en mer. La console affiche le pays, et l'État
  souverain pour un territoire dépendant (« Gibraltar, Royaume-Uni »).
  - Données : frontières Natural Earth 1:10 M (couche « admin 0 countries », 258 pays et territoires). Ce sont les
	frontières **de fait** : la Crimée compte pour la Russie, le Sahara occidental pour le Maroc, Taïwan comme
	pays. Natural Earth publie aussi des variantes selon le point de vue d'un pays, dont la France
	(`ne_10m_admin_0_countries_fra.geojson`, même outil).
  - Fiche de chaque pays : `code`, `iso_a2`, `name_fr`, `name_en`, `sovereign_code`, `sovereign` et `sovereign_fr`
	(État dont il dépend), `type`, `continent`, population estimée (`pop_est`, `pop_year`, 2019 en général), PIB en
	millions de dollars (`gdp_md`, `gdp_year`), `income_group`.
  - Stockage comme `OceanMask` : 120 lignes de latitude par degré (~0,9 km) ; pour chaque ligne, les longitudes
	exactes où elle franchit une frontière ou une côte, et le pays situé à l'est de chacune. Recherche dichotomique.
	Précision : celle des frontières (quelques centaines de mètres) en longitude, ~0,5 km en latitude. Vérifié :
	Strasbourg / Kehl, Genève / Annemasse, Lille / Tournai, La Línea / Gibraltar, Monaco, Saint-Marin, Andorre,
	Hong Kong (Chine), Groenland (Danemark), Fidji et Tchoukotka (antiméridien), mer et Caspienne (aucun pays).
	Limite : un territoire plus petit qu'une ligne peut être manqué (Vatican, enclaves de Baarle-Hertog).
  - `CountryMask.countries_within(latitude, longitude, rayon_km)` : pays présents dans un disque, du plus proche au
	plus éloigné (Bâle, 30 km : Allemagne, France, Suisse ; détroit de Béring, 60 km : Russie, États-Unis).
  - Chargement : ~0,5 s, lancé en tâche de fond par `NukeLauncher` au démarrage (`OceanMask` aussi) : pas d'à-coup au
	premier tir. Sans le fichier, aucun pays n'est détecté.
- **Explosions sur la mer** (règles de jeu) :
  - **Détection** (`scripts/ocean_mask.gd`, classe `OceanMask`, données `assets/ocean_mask.res`) : au tir,
	`NukeLauncher` demande `OceanMask.is_ocean(latitude, longitude)` et renseigne `NukeParams.over_ocean` (la console
	affiche « en mer »). Le masque vient du trait de côte Natural Earth 1:10 M (couche « ocean » : océans et mers
	reliées, la Caspienne comprise ; les lacs comptent comme de la terre). Il est stocké par lignes de latitude
	(120 par degré, ~0,9 km) : pour chaque ligne, les longitudes exactes où elle croise la côte ; un point est en mer
	si un nombre impair de croisements est à sa gauche. Précision : celle du trait de côte (quelques centaines de
	mètres) en longitude, ~0,5 km en latitude. Vérifié sur l'Atlantique, la Méditerranée, la Manche, la Baltique, la
	rade de Marseille (mer) et Paris, le Léman, le lac Michigan, l'Antarctique (terre), antiméridien compris. Coût :
	chargement ~60 ms au premier tir, puis une recherche dichotomique. Sans le fichier, tout est terre.
  - **Pas d'incendie sur l'eau** : voir « Incendies ». Au large (aucune terre à portée du flash), aucun feu.
  - **Nuage de vapeur d'eau** (explosion basse, même critère que la poussière ; `NukeScaling.low_burst`) : la boule
	de feu vaporise une grande masse d'eau (Glasstone & Dolan §2.50 et suivants). Dans `NukeMushroom` (groupe
	« Explosion sur la mer ») :
	- nuage blanc de vapeur condensée (`steam_albedo`, 85 % de `steam_whiteness`), chapeau en grosse boule
	  (épaisseur / diamètre d'au moins `steam_aspect` = 0,75 au lieu de 0,42) ;
	- nuage de base d'embruns plus large (rayon = front de choc) et plus dense (0,85) ; au pied, des embruns blancs
	  au lieu des débris ; jupe d'embruns blanche sous l'onde de choc ;
	- même montée que sur terre (stabilisation en 10 min), puis **l'eau retombe** : le nuage s'affaisse (hauteurs ×
	  1 − 0,35 · (1 − exp(−(t − 10 min) / 15 min)), `NukeScaling.STEAM_SINK`, `STEAM_SINK_S`) et **disparaît vite**
	  (densité × exp(−(t − 10 min) / 10 min), `STEAM_FADE_S`, en plus de la dissipation ordinaire). À 1 Mt : boule
	  dense à 20 min, voile ténu à 35 min, masqué vers 50 min (temps physique, ~5 min d'horloge), contre ~6 h sur
	  terre.
- **Nuages** (`nuke/nuke_cloud_fx.gd`, nœud `CloudFX` créé par `NukeLauncher` ; `nuke/shaders/nuke_clouds.gdshaderinc`) :
  l'onde de choc creuse un trou dans la couche nuageuse, qui se referme ensuite.
  - **Branchement** : l'include est appelé par `cloud_density()` (`shaders/cloud_density.gdshaderinc` : une ligne
	d'inclusion, un appel). Toute lecture de la densité est donc modifiée : rendu volumétrique, **ombres portées au
	sol**, voilage des lumières nocturnes et des incendies, lumière des flashs dans les nuages. Les ombres suivent
	le trou sans code dédié (vérifié : couche nuageuse masquée, le sol montre un disque éclairé dans la zone
	ombrée, décalé selon la direction du soleil).
  - **Trou** : à l'intérieur du rayon courant du front de choc, la densité est supprimée.
	- Rayon : celui du front qui porte l'anneau de condensation (`NukeScaling.shock_front_radius_km`, voir « Onde
	  de choc ») : le front pousse les nuages devant lui, trou et anneau avancent ensemble.
	- Rayon final : 6,4 km à 10 kt, 15 km à 1 Mt, 45 km à 50 Mt (agrandi par rapport au rayon de choc de
	  référence : un trou plus étroit que l'épaisseur de la couche, jusqu'à 7 km, ne serait qu'un puits sombre vu de
	  biais).
	- **Bord flou** : largeur de 18 % du rayon, au moins 0,6 km (`nuke_cloud_edge_soft`, `nuke_cloud_edge_km`),
	  rendue irrégulière par le bruit 3D des nuages (`nuke_cloud_edge_noise`, période 0,3 × rayon **final**). Le
	  sommet des nuages y descend en pente douce. Le motif est lu en coordonnées centrées sur l'explosion, à
	  l'échelle du rayon final : il est fixe. (Il était lu à l'échelle du rayon courant et en coordonnées
	  planétaires, à ~6 371 km de l'origine : pendant l'expansion, la moindre variation du rayon le décalait de
	  plusieurs périodes, et le bord grouillait à chaque image. Mesure à 50 Mt, 2 min, deux images à 0,5 s
	  d'écart : 9 532 pixels changeant brutalement avant, 0 après.)
  - **Nuages poussés** : la carte est lue plus près du centre, ce qui déplace les nuages radialement vers
	l'extérieur. Le décalage vaut au plus 12 % du rayon du trou (`nuke_cloud_push`) et décroît en exp(−x / w) au-delà
	du bord (x : distance au bord ; w = 8 % du rayon, `nuke_cloud_rim_width`). La matière balayée est tassée contre
	le bord : la carte y est lue jusqu'à 2,5 fois plus serrée. Le niveau de mipmap de la carte est relevé d'autant
	(log2 du tassement, sortie `squeeze` de `nuke_cloud_warp`), sinon ses détails deviennent plus fins qu'un pixel
	et scintillent.
  - **Bourrelet** : densité × (1 + 0,6), sommet relevé de 25 % sur le bord (`nuke_cloud_rim_gain`,
	`nuke_cloud_rim_lift`), même décroissance.
  - **Retour des nuages** sur `recovery_s` (export de `CloudFX`, **1 200 s de temps physique** de l'explosion,
	≈ 2 min d'horloge après l'accélération) :
	- chaque point se referme à partir du passage du front, t = −τ · ln(1 − r / R_max), plafonné à celui de
	  0,98 R_max (~3,9 τ) : le front n'atteint R_max qu'asymptotiquement, et sans ce plafond un anneau très fin
	  restait ouvert au bord jusqu'à la fin (plus fin qu'un pixel, il scintillait, puis disparaissait d'un coup) ;
	- tout est refermé au plus tard à `recovery_s` + 4 τ, quand `CloudFX` retire l'événement (pas de saut) ;
	- le bord se referme 2 fois plus vite que le centre (`nuke_cloud_edge_fill` = 1) : les nuages regagnent le trou
	  du bord vers le centre ;
	- décalage et bourrelet s'estompent sur la même durée.

	Vu en jeu : à 10 kt, trou visible dès 3 s, sol visible au fond à 30 s ; à 1 Mt, ~15 km de rayon à 40 s ; à
	50 Mt, ~40 km à 2 min ; à moitié refermé vers 10 min, disparu vers 20 min.
  - **Dérive** : le centre du trou suit le vent du point d'impact (`NukeParams`, vent réel GFS), le même champ de
	vent que l'advection des nuages : le trou part avec la masse d'air.
  - **Données** : 16 explosions au plus (les plus récentes), deux `vec4` chacune, en tableaux d'uniforms
	`nuke_cloud_a` / `nuke_cloud_b` :
	- a = (centre x, y, z en km dans le repère de la planète, rayon courant du trou) ;
	- b = (rayon final du front R_max, τ, temps physique écoulé, puissance en kt).

	C'est la disposition de deux texels RGBA32F par explosion. Pour passer à une texture de données, seuls
	`nuke_cloud_event()` (shader) et `NukeCloudFX._upload()` changent. Une explosion sort de la liste quand son trou
	est refermé (t > `recovery_s` + 4 τ).
  - Coût : avec 16 trous actifs, la scène reste au plafond de 120 i/s (synchro verticale).
- **Lumière et effets d'écran du flash** (`nuke/nuke_flash_fx.gd`, nœud `FlashFX` créé par `NukeLauncher`), à
  chaque image, pour les flashs actifs :
  - **sol et nuages** : uniforms `nuke_flash_*` (les 4 flashs les plus intenses) de
	`nuke/shaders/nuke_flash.gdshaderinc`, inclus dans `shaders/earth_surface.gdshader` et
	`shaders/cloud_volume.gdshader`. Seul code des explosions hors de `nuke/` (avec celui des trous dans les
	nuages, voir « Nuages ») : une ligne d'inclusion et un appel dans chacun. Les lumières Godot ne conviennent pas ici : le sol a un `light()` propre au soleil, et les nuages
	sont unshaded.
	- Le **sol** reçoit flux × (400 km / d)² × cos(incidence) × transmittance de l'air, en émission (de jour
	  comme de nuit). L'horizon local est respecté (exact sur une sphère), l'ombre des nuages est calculée sur le
	  segment sol → flash (4 échantillons), et une petite part est diffusée par l'air (3 %, portée 60 km).
	- Les **nuages** reçoivent le même flux × transmittance de l'air, nul si la Terre s'interpose, avec
	  auto-ombrage (marche vers le flash : 4 pas doublés depuis 0,3 km, `nuke_flash_shadow_steps`) et diffusion
	  isotrope. Appelé à chaque pas de la marche des nuages, c'est le poste le plus cher des 20 premières secondes
	  d'une salve ; **la marche d'auto-ombrage est faite une seule fois par pas, vers le flash le plus brillant, et
	  partagée par les autres flashs** (`nuke_flash_shadow_shared`) : elle ne couvre que ~4,5 km autour de
	  l'échantillon, c'est la densité locale qui compte, peu la direction, et les flashs moins brillants pèsent
	  moins (10 × 50 Mt, 1080p : 8,2 → 5,7 ms, PSNR 53–61 dB ; voir « Performances »). L'intégrale de l'air
	  (`nuke_flash_air_steps`, 8 pas) est bon marché.
	- Unité : le « soleil » (le sol reçoit `nuke_flash_ground_gain` = 2, comme la lumière `Sun`). L'éclairement
	  est plafonné à 2 000 près de la boule de feu.
  - **station** : `DirectionalLight3D` dirigée depuis le flash le plus intense (à 400 km la source est à l'infini
	pour une station de 3 m). Énergie = flux reçu × 2 (un soleil), ombres portées des montants. Elle n'éclaire que
	la station : `FlashFX` ajoute le calque 20 à tous ses maillages, et la lumière a ce seul calque dans son masque.
  - **éblouissement**, comme un œil : ébloui par la *montée* de la lumière, il s'adapte ensuite même si le flash
	dure (jusqu'à ~12 s joués pour 50 Mt) :
	- l'intensité du glow suit le flux reçu : `glow_intensity` + 2·g, avec g = flux reçu / (flux reçu + 0,2). La
	  source reste éclatante tant qu'elle brille ;
	- le bloom (`glow_bloom` + 0,5·e) et le multiplicateur d'exposition de la caméra (× (1 + 2,5·e)) suivent
	  l'éblouissement e = excès / (excès + 0,2), l'excès étant le flux reçu au-delà d'un niveau d'adaptation qui
	  le rattrape en 1,5 s (temps réel, `adaptation_s`) ;
	- tout revient aux valeurs d'origine à la fin du flash, et l'exposition automatique réagit ensuite d'elle-même ;
	- un 50 Mt sature l'écran à la montée du flash ; un 10 kt laisse un éclat net sans saturation ;
	- **règle : seulement si l'œil voit le flash** (`NukeFlashFX._eye_exposed`) : dans la cupola
	  (`Station.is_in_cupola`) ou hors de la station (`Station.observer_outside`, mis par l'éjection du sas ; ou à
	  plus de 25 m de la station, `outside_distance_m`). Ailleurs dans les modules, la coque le cache : ni glow, ni
	  bloom, ni éblouissement, ni adaptation de l'œil (le flux d'écran est compté nul) ; la lumière du flash sur la
	  station garde, elle, le flux reçu.
- **Horloge** (`nuke/nuke_clock.gd`, autoload `NukeClock`), distincte du temps réel :
  - `time_s` avance au rythme du temps de l'orbite (**Pause, x2… x16 s'appliquent aussi aux explosions**),
	multiplié par `acceleration` (1 par défaut) ;
  - le temps physique d'une explosion défile en temps réel pendant `realtime_phase_s` (20 s : flash, boule de
	feu, onde de choc). Sa vitesse monte ensuite **progressivement** (smoothstep) sur `ramp_s` (40 s d'horloge)
	jusqu'à `slow_phase_acceleration` (×10), pour la montée du champignon et les trous dans les nuages ;
  - quand `slow_phase_end_s` (30 min) de temps physique sont écoulés, la vitesse **redescend** de la même façon
	(smoothstep sur `ramp_s`) jusqu'à 1 : l'explosion vit ensuite **au rythme du jeu**, avec une avance fixe de
	~29 min (`late_offset_s()`, 1 764 s). Sans ce retour, une orbite (92 min) valait ~15 h pour les explosions et
	tout avait disparu au passage suivant ; désormais incendies (jours), dissipation du champignon (heures), décès
	différés et retombées suivent la date de la partie ;
  - les rampes évitent les sauts de vitesse : un effet encore en cours à 20 s ne se met pas à filer d'un coup
	(l'anneau de condensation d'un 50 Mt s'évapore vers 35 s d'horloge, à ×3,8) ;
  - repères : 60 s d'horloge = 240 s physiques, 10 min physiques ≈ 1 min 36 s d'horloge, 30 min ≈ 3 min 36 s,
	fin de la redescente à ~4 min 16 s d'horloge (~34 min physiques) ; au-delà, physique = horloge + 1 764 s ;
  - `to_physical()` (intégrale de la vitesse) et `to_clock()` (réciproque, par dichotomie) convertissent.
- **Tir** (`nuke/nuke_launcher.gd`, nœud `NukeLauncher` de `orbit_view.tscn`, groupe `nuke_launcher`) : rayon partant
  de la caméra par le centre de l'écran, intersecté analytiquement avec la sphère terrestre (6371 km, soit 637,1 u).
  Le point touché est converti dans le repère local du nœud `Earth` (qui tourne avec la planète) et en
  latitude / longitude (même convention que `Orbit` et les UV de la sphère). Si le rayon manque la Terre, rien ne
  se passe. La station n'est pas prise en compte : viser à travers un montant de la Cupola tire quand même.
  - `get_aim()` : point visé (`local`, `latitude`, `longitude`) ou `{}` ;
  - `launch(yield_kt)` : tire sur le point visé et retourne la `NukeEffect` créée ; sans cible, retourne `null`
	sans rien faire ;
  - `launch_at(latitude, longitude, yield_kt)` : tire sur des coordonnées ; `fire(params)` : à partir d'une
	`NukeParams` ;
  - signaux `detonated(effect)` et `effects_changed` ; `get_effects()` (liste tenue à jour, à ne pas modifier),
	`clear_effects()`. Les explosions restent en place jusqu'à la fin de la partie (persistance du monde) : seul
	`clear_effects()` (debug, banc de mesure) les retire.
  - Au démarrage, il lie `NukeClock` au nœud `Orbit` (`orbit_path`).
- **Interface** : commande `Launch` de la tablette (`nuke/launch_control.gd`, tir depuis la cupola seulement, chaîne de tir : tube choisi →
  `Station.launch_missile` → `missile_released` → vol `MissileFlight` (durée selon la distance, chronomètres
  `nuke/impact_timers.gd`) → `NukeLauncher.launch_at` sur le point
  visé à l'appui) : panneau des silos (`nuke/silo_panel.gd`, voyants `nuke/silo_button.gd` dessinés à la main) et,
  en dessous, les boutons de puissance ; à droite, gros bouton rouge (`nuke/big_red_button.gd`, dessiné à la main).
  Au clic, le capuchon s'enfonce, reste un instant en bas puis remonte avec un léger rebond. Réticule au centre de l'écran
  (`nuke/aim_reticle.gd`) : rouge avec la latitude et la longitude du point visé quand la vue vise la Terre, gris
  sinon.
- **Scène de debug** (`nuke/debug/nuke_debug.tscn` : dans l'éditeur, ouvrir la scène puis F6 ; **en jeu, F4** ouvre le même panneau sur la partie en cours, cf. `scripts/ui/fps_overlay.gd` ; instancie `orbit_view.tscn` et ajoute le
  panneau `nuke/debug/nuke_debug_panel.gd` en haut à gauche) :
  - curseur de puissance en échelle logarithmique (10 kt à 50 Mt), avec les tailles calculées ;
  - champs latitude / longitude (Madrid par défaut), bouton **Point visé** (recopie le centre de la vue),
	**Tirer**, **Effacer** ;
  - case **Marqueurs** (marqueurs de taille des explosions) ;
  - menu **Alerte** (aucune / jaune / orange / rouge / plus de lumière) : niveau d'alerte de la station, couleur des luminaires
	intérieurs (`Station.set_alert`, voir « Éclairage intérieur ») ;
  - scrubber du temps physique (0 à 6 h, pour voir la dissipation du champignon ; non linéaire : t = 6 h · v⁵, les
	3 premières secondes occupent 17 % de la course, les 10 premières minutes la moitié) : il suit la dernière explosion tirée depuis ce panneau ; le déplacer (ou cocher
	**Rejouer**) fige toutes les explosions au temps choisi, décocher rend la main à l'horloge.

## Sources des textures

Issues de la NASA, de la NOAA ou de Natural Earth (domaine public, crédit demandé), du WRI (centrales, CC BY 4.0) et du JRC de la Commission
européenne (population, CC BY 4.0) :

| Fichier | Contenu | Source |
|---|---|---|
| `assets/earth_tiles/*.jpg` | Blue Marble Next Generation, juillet 2004, sans relief ombré, 500 m/px (2592 tuiles, ~260 Mo) | NASA Visible Earth / Earth Observatory, image 74092 |
| `assets/textures/earth_bluemarble_16k.jpg` | Même source réduite à 16384 × 8192 | idem |
| `assets/earth_night_tiles/*.jpg` | Black Marble 2016 (lumières nocturnes, composite couleur), 500 m/px (2592 tuiles, ~180 Mo) | NASA Earth Observatory, image 144898 |
| `assets/textures/earth_night_16k.jpg` | Même source réduite à 16384 × 8192 | idem |
| `assets/earth_cloud_tiles/*.webp` | Couverture nuageuse (alpha) du 15 juillet 2023, déduite de VIIRS NOAA-20 Corrected Reflectance True Color, 500 m/px (2592 tuiles, ~350 Mo) | NASA GIBS / Worldview (données LANCE/VIIRS) |
| `assets/textures/earth_clouds_16k.jpg` | Même couverture, 16384 × 8192 | idem |
| `assets/textures/earth_clouds_8k.jpg` | Couverture nuageuse Blue Marble, 8192 × 4096 : utilisée seulement par l'outil, pour combler les zones sans données VIIRS | NASA Visible Earth / Earth Observatory, image 57747 |
| `assets/textures/starmap_4k.exr` | Deep Star Maps 2020, 4096 × 2048, HDR | NASA Scientific Visualization Studio, animation 4851 |
| `assets/textures/cloud_wind.exr` | Vent moyen du 15 juillet 2023 (850–500 hPa), 720 × 360 | NOAA, modèle GFS, analyses 0,25° (NOAA Open Data Dissemination, AWS) |
| `assets/textures/wind_profile.exr` | Profil vertical du vent du même jour (14 niveaux, 850 à 0,1 hPa) et altitude de chaque niveau, 360 × 180 par niveau (~11 Mo) | idem |
| `assets/ocean_mask.res` | Masque mers et océans (croisements du trait de côte par ligne de latitude, ~2,4 Mo) | Natural Earth 1:10 M, couche « ocean » (domaine public) |
| `assets/power_plants.res` | 34 936 centrales électriques (position, puissance, combustible, pays) et capacité de chaque pays (~0,7 Mo) | Global Power Plant Database v1.3, World Resources Institute (CC BY 4.0 ; modifié : pays recalculé sur les frontières Natural Earth) |
| `assets/textures/country_ids.png` | Carte des pays (numéro + 1 sur 16 bits), 8192 × 4096 | dérivée de Natural Earth 1:10 M, « admin 0 countries » |
| `assets/population_2030.bin` | Habitants par cellule de 1/120° en 2030 (projection), tuiles de 5° compressées (~74 Mo) | GHS-POP R2023A, JRC / Commission européenne (CC BY 4.0 ; modifié : recalage, quantification) |
| `assets/country_mask.res` | Masque des pays (changements de pays par ligne de latitude) et fiches des 258 pays et territoires (~3 Mo) | Natural Earth 1:10 M, couche « admin 0 countries » (domaine public) |

Limites des nuages réels : c'est un instantané déplacé par le vent (les nuages ne se forment ni ne se dissipent, et
la journée se répète). On voit quelques raccords entre
passages successifs du satellite (lignes droites dans les champs de nuages), et la banquise arctique est en partie
comptée comme nuage.

## Bibliographie

Ouvrages, articles et jeux de données dont sont tirés les calculs, les modèles de rendu et les images du projet.
**Elle est reprise dans le jeu** : écran de démarrage, bouton **Crédits** (`scenes/ui/credits_menu.tscn`,
`scripts/ui/credits_menu.gd`), onglet **Références** ; l'onglet **Crédits** donne les auteurs (Mickael Houet &
Claude), le moteur et les outils, et les données et contenus importés avec leur licence et l'attribution demandée.
Textes dans le fichier de langue `locale/credits.csv` (5 langues ; les références gardent leur titre d'origine,
seul leur usage est traduit). **Toute nouvelle source ou tout nouveau contenu importé s'ajoute ici et dans
`locale/credits.csv`** (liste des rubriques et des clés : `REFERENCES` et `CREDITS` du script).
Les paragraphes (§) sont ceux des ouvrages ; entre parenthèses, les fichiers du projet qui s'en servent.

### Effets des explosions nucléaires

- Glasstone, S. et Dolan, P. J. (1977). *The Effects of Nuclear Weapons*, 3ᵉ édition. U.S. Department of Defense et
  U.S. Department of Energy, Washington, U.S. Government Printing Office. Source principale de `nuke/` :
  - ch. II : montée du nuage (§2.12), hauteurs du nuage stabilisé et dissipation (§2.16, §2.17), durée de la
	lueur de la boule de feu (§2.18), explosions à la surface de l'eau (§2.50 et suivants) ;
  - ch. III : lois d'échelle de l'onde de choc en racine cubique de la puissance (similitude de Hopkinson-Cranz) ;
  - ch. VII : impulsion thermique (§7.85 à §7.88 : t_max, t_min, puissance au second maximum), seuils
	d'inflammation (~10 cal/cm²), incendies et tempête de feu de Hiroshima ;
  - ch. IX : retombées locales, décroissance du débit de dose en t^−1,2, contours idéalisés de débit de dose
	(vérification de `NukeFallout`), protection offerte par les bâtiments ;
  - ch. XII : effets de l'irradiation aiguë sur l'homme (dose létale médiane de l'ordre de 4,5 Gy sans soins).
- Adamsky, V. et Smirnov, Y. (1994). « Moscow's Biggest Bomb: the 50-Megaton Test of October 1961 ». *Cold War
  International History Project Bulletin*, n° 4, Woodrow Wilson International Center for Scholars. Hauteur du
  nuage de la Tsar Bomba (64 à 67 km).
- Hawthorne, H. A. (dir.) (1979). *Compilation of Local Fallout Data from Test Detonations 1945–1962 Extracted from
  DASA 1251*, DNA 1251-1-EX et 1251-2-EX. Defense Nuclear Agency. Nuages des essais Ivy Mike et Castle Bravo
  (~40 km).
- U.S. Congress, Office of Technology Assessment (1979). *The Effects of Nuclear War*, OTA-NS-89, Washington, U.S.
  Government Printing Office. Ch. II : pertes en fonction de la surpression, tirées d'Hiroshima (`NukeCasualties`).
  Table des tranches recoupée dans « Inaccurate Prediction of Nuclear Weapons Effects and Possible Adverse
  Influences on Nuclear Terrorism Preparedness », *Homeland Security Affairs*, article 97
  (https://www.hsaj.org/articles/97), qui en discute aussi les limites.
- Brode, H. L. (1986). *Airblast From Nuclear Bursts — Analytic Approximations*. Pacific-Sierra Research
  Corporation, p. 60–71. Surpression de crête au sol (`NukeScaling.overpressure_psi`), transcrite du paquet Python
  open source *glasstone* (GOFAI, licence MIT, https://github.com/GOFAI/glasstone).
- Hanifen, D. W. (1980). *Documentation and Analysis of the WSEG-10 Fallout Prediction Model*. Thèse, Air Force
  Institute of Technology. Modèle de retombées WSEG-10 (Weapons Systems Evaluation Group, 1959) de `NukeFallout`,
  transcrit d'après le paquet *glasstone* (fichier `fallout.py`).
- Way, K. et Wigner, E. P. (1948). « The Rate of Decay of Fission Products ». *Physical Review*, 73, p. 1318.
  Décroissance du débit de dose des retombées en t^−1,2 (reprise par Glasstone & Dolan, ch. IX).
- Postol, T. A. (1986). « Possible fatalities from superfires following nuclear attacks in or near urban areas ».
  In *The Medical Implications of Nuclear War*, National Academy Press. Critique du modèle de surpression (non
  retenue : limite documentée).
- Toon, O. B., Turco, R. P., Robock, A., Bardeen, C., Oman, L. et Stenchikov, G. L. (2007). « Atmospheric effects
  and societal consequences of regional scale nuclear conflicts and acts of individual nuclear terrorism ».
  *Atmospheric Chemistry and Physics*, 7, p. 1973–2002, doi:10.5194/acp-7-1973-2007. Charge de combustible urbain
  (1,1·10⁷ g par habitant, 0,0011 g/cm² par hab./km², § 6.1), facteur d'émission de fumée (0,020 g/g, d'après
  Small 1989), 1 à 5 Tg de suie pour 100 explosions de 15 kt (fumée des incendies, `NukeScaling.SMOKE_*`).
- Andreae, M. O. (2019). « Emission of trace gases and aerosols from biomass burning – an updated assessment ».
  *Atmospheric Chemistry and Physics*, 19, p. 8523–8546. Facteurs d'émission de particules des feux de végétation.
- van der Werf, G. R. et al. (2017). « Global fire emissions estimates during 1997–2016 ». *Earth System Science
  Data*, 9, p. 697–720 (GFED4). Ordres de grandeur du combustible consumé par les feux de végétation.

### Réseaux électriques

- Global Energy Observatory, Google, KTH Royal Institute of Technology in Stockholm, Enipedia, World Resources
  Institute (2019). *Global Power Plant Database*, v1.3 (2021). Licence CC BY 4.0. Publié sur Resource Watch et
  Google Earth Engine. Centrales et capacités par pays (`assets/power_plants.res`).
- Byers, L., Friedrich, J., Hennig, R., Kressig, A., Li, X., McCormick, C. et Malaguzzi Valeri, L. (2018). *A Global
  Database of Power Plants*. World Resources Institute, document technique joint à la base.
- U.S.-Canada Power System Outage Task Force (2004). *Final Report on the August 14, 2003 Blackout in the United
  States and Canada: Causes and Recommendations*. Durées de rétablissement d'une panne en cascade (panne
  régionale).
- Panne de la péninsule ibérique du 28 avril 2025 : rapports d'ENTSO-E (Réseau européen des gestionnaires de réseau
  de transport d'électricité) et de Red Eléctrica. Effondrement national en quelques secondes, rétablissement en une
  dizaine d'heures (panne nationale).

### Atmosphère, nuages et éclairage

- Bruneton, É. et Neyret, F. (2008). « Precomputed Atmospheric Scattering ». *Computer Graphics Forum*, 27(4)
  (EGSR 2008). Modèle de diffusion Rayleigh + Mie à densités exponentielles.
- Hillaire, S. (2020). « A Scalable and Production Ready Sky and Atmosphere Rendering Technique ». *Computer
  Graphics Forum*, 39(4) (EGSR 2020). Coefficients de diffusion Rayleigh, Mie et d'absorption de l'ozone
  (`shaders/atmosphere_common.gdshaderinc`, `shaders/sun_light.gdshaderinc`, `nuke/nuke_atmosphere.gd`).
- Henyey, L. G. et Greenstein, J. L. (1941). « Diffuse radiation in the Galaxy ». *The Astrophysical Journal*,
  93, p. 70–83. Fonction de phase des nuages et du champignon.
- Wrenninge, M., Kulla, C. et Lundqvist, V. (2013). « Oz: The Great and Volumetric ». *ACM SIGGRAPH 2013 Talks*.
  Approximation de la diffusion multiple (somme d'octaves d'extinction atténuée) dans les nuages et le champignon.
- Loi de Beer-Lambert : atténuation exponentielle de la lumière dans les nuages, le champignon et l'air.

### Orbite et astronomie

- U.S. Naval Observatory et HM Nautical Almanac Office. *The Astronomical Almanac*, section C, « Low-precision
  formulas for the Sun ». Position du soleil (`scripts/orbit.gd`, précision ~0,01°).
- Capitaine, N., Guinot, B. et McCarthy, D. D. (2000). « Definition of the Celestial Ephemeris Origin and of UT1 in
  the International Celestial Reference Frame ». *Astronomy & Astrophysics*, 355, p. 398–405. Angle de rotation de
  la Terre (IAU 2000).
- Petit, G. et Luzum, B. (dir.) (2010). *IERS Conventions (2010)*, IERS Technical Note n° 36. Repères céleste et
  terrestre, vitesse de rotation sidérale.
- National Imagery and Mapping Agency (2000). *Department of Defense World Geodetic System 1984*, TR8350.2,
  3ᵉ édition. Constante gravitationnelle géocentrique μ = 398 600,4418 km³/s², J2 = 1,08263 × 10⁻³.
- Vallado, D. A. (2013). *Fundamentals of Astrodynamics and Applications*, 4ᵉ édition, Microcosm Press.
  Changements de plan (Δv = 2·v·sin(θ/2), changement de Ω au point d'intersection des plans), transfert de Hohmann,
  précession nodale J2 (`scripts/flight_computer.gd`, `scripts/orbit.gd`).

### Images satellites et données géographiques

- Stöckli, R., Vermote, E., Saleous, N., Simmon, R. et Herring, D. (2005). *The Blue Marble Next Generation – A true
  color Earth dataset including seasonal dynamics from MODIS*. NASA Earth Observatory. Texture de jour (juillet
  2004, Visible Earth image 74092).
- Román, M. O. et al. (2018). « NASA's Black Marble nighttime lights product suite ». *Remote Sensing of
  Environment*, 210, p. 113–143. Lumières nocturnes (composite Black Marble 2016, Visible Earth image 144898).
- NASA EOSDIS, Global Imagery Browse Services (GIBS) et Worldview. *VIIRS NOAA-20 Corrected Reflectance (True
  Color)*, 15 juillet 2023, données LANCE. Couverture nuageuse.
- NASA Visible Earth (2002). *Blue Marble: Clouds*, image 57747. Nuages des zones sans données VIIRS.
- NASA Goddard Scientific Visualization Studio (2020). *Deep Star Maps 2020*, animation 4851 (catalogues Hipparcos-2,
  Tycho-2 et Gaia DR2). Ciel étoilé.
- NOAA National Centers for Environmental Prediction. *Global Forecast System (GFS)*, analyses 0,25° du 15 juillet
  2023, NOAA Open Data Dissemination (AWS). Vent des nuages et profil vertical du vent des champignons.
- Organisation météorologique mondiale. *Manual on Codes* (OMM-n° 306), vol. I.2, format GRIB2 (gabarit 5.3). Décodage
  des fichiers GFS (`tools/build_wind_field.ps1`).
- Natural Earth. *1:10m Physical Vectors – Ocean* (domaine public). Masque mers et océans (`assets/ocean_mask.res`).
- Schiavina, M., Freire, S., Carioli, A. et MacManus, K. (2023). *GHS-POP R2023A – GHS population grid multitemporal
  (1975–2030)*. Commission européenne, Centre commun de recherche (JRC), doi:10.2905/2FF68A52-5B5B-4A22-8F40-C41DA8332CFE.
  Licence CC BY 4.0, © Union européenne 1995-2026. Époque 2030, 30 secondes d'arc. **Modifié** : recalé sur une
  grille alignée sur 1/120° (décalage < 0,05 cellule), quantifié sur 16 bits et découpé en tuiles
  (`assets/population_2030.bin`, `tools/build_population.ps1`).
- Natural Earth. *1:10m Cultural Vectors – Admin 0 – Countries*, version 5 (domaine public). Frontières de fait,
  population estimée et PIB des pays (`assets/country_mask.res`).
- MakeHuman Community. *MakeHuman system assets* (CC0), via l'extension Blender MPFB2 (GPLv3, ressources CC0) : main
  qui tient la tablette ; textures du paquet gardées dans `assets/makehuman/` (dossier ignoré par Godot, voir son
  `LISEZMOI.md`).
- Natural Earth. *1:50m Cultural Vectors – Admin 0 – Countries* (domaine public). Contours de la carte de l'écran
  de pilotage (`assets/world_map_lines.res`, `tools/build_map_lines.gd`).
