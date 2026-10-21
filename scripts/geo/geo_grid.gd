class_name GeoGrid
extends RefCounted
## Découpage commun des données au sol en cellules de 1/CELLS_PER_DEGREE de degré (~0,9 km) : grille de population
## (PopulationGrid), masques des pays et des mers (CountryMask, OceanMask : une ligne de la grille = une ligne du
## masque). Ligne 0 = 90° N, colonne 0 = 180° O ; centres des cellules à mi-pas. Fonctions pures, sûres en thread.

const CELLS_PER_DEGREE := 120


static func row_count() -> int:
	return 180 * CELLS_PER_DEGREE


static func col_count() -> int:
	return 360 * CELLS_PER_DEGREE


## Ligne de la latitude (degrés), bornée à la grille.
static func row_of(latitude_deg: float) -> int:
	return clampi(int(floor((90.0 - latitude_deg) * CELLS_PER_DEGREE)), 0, row_count() - 1)


## Colonne de la longitude (degrés), qui boucle.
static func col_of(longitude_deg: float) -> int:
	return posmod(int(floor((wrapf(longitude_deg, -180.0, 180.0) + 180.0) * CELLS_PER_DEGREE)), col_count())


## Latitude (degrés) du centre d'une ligne.
static func row_latitude(row: int) -> float:
	return 90.0 - (row + 0.5) / CELLS_PER_DEGREE


## Longitude (degrés) du centre d'une colonne.
static func col_longitude(col: int) -> float:
	return -180.0 + (posmod(col, col_count()) + 0.5) / CELLS_PER_DEGREE
