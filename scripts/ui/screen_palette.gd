class_name ScreenPalette
extends RefCounted
## Couleurs des écrans « verts » du jeu (poste de pilotage, carte, tablette, commande de poussée) : une seule source,
## référencée par les écrans (PilotDisplay, OrbitalMap, TabletDisplay, BurnControl).

## Texte principal, texte atténué, cadres.
const TEXT := Color(0.85, 1.0, 0.88)
const DIM := Color(0.45, 0.6, 0.5)
const FRAME := Color(0.35, 0.5, 0.4)
## Orbite visée, trace fantôme, compte à rebours : cyan.
const GHOST := Color(0.3, 0.85, 1.0)
## Fonds des panneaux et boutons des cartes (repos, actif).
const PANEL := Color(0.04, 0.06, 0.05, 0.85)
const PANEL_ACTIVE := Color(0.12, 0.3, 0.2, 0.95)
## Fonds des onglets de la tablette (repos, actif).
const TAB := Color(0.06, 0.09, 0.08)
const TAB_ACTIVE := Color(0.12, 0.3, 0.2)
