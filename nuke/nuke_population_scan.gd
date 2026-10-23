class_name NukePopulationScan
extends RefCounted
## Balayage de la grille de population GHS-POP (PopulationGrid) autour d'un point, partagé par les bilans qui
## comptent des habitants (NukeCasualties : cellule par cellule ; NukeFallout : blocs de cellules) : lignes de
## latitude utiles, colonnes autour du méridien du point, distances en km dans le plan local (x vers l'est, y vers le
## nord), et entrée de pays des bilans. Calcul pur, sûr depuis un autre thread (lectures seules).

## Abandon des calculs en cours (NukeCasualties.estimate, NukeFallout.estimate), testé à chaque ligne de la grille :
## levé par NukeImpact à la fin de la partie, avant d'attendre ses tâches.
static var abort := false


## Parcourt les cellules (block = 1) ou les blocs de block × block cellules (repérés par leur coin nord-ouest, lignes
## et colonnes multiples de block) dont le centre est à moins de reach_km du point (lat0, lon0), à une marge d'un
## pas près en latitude ; en longitude, la bande fait le tour du globe au besoin. Pour chacun :
## visitor.call(row, col, dx_km, dy_km, km_x), avec dx_km, dy_km : décalage du centre du bloc par rapport au point
## (est, nord) et km_x : km par degré de longitude sur cette ligne. Rend faux si le balayage a été abandonné.
static func scan(lat0: float, lon0: float, reach_km: float, block: int, visitor: Callable) -> bool:
	var cells_per_degree := PopulationGrid.CELLS_PER_DEGREE
	var step_deg := float(block) / cells_per_degree
	var km_y := GeoMath.KM_PER_DEGREE
	var first_row := PopulationGrid.row_of(minf(lat0 + reach_km / km_y, 90.0))
	var last_row := mini(PopulationGrid.row_of(maxf(lat0 - reach_km / km_y, -90.0)), PopulationGrid.row_count() - 1)
	first_row -= first_row % block
	var center_col := PopulationGrid.col_of(lon0)
	center_col -= center_col % block
	# Centre d'un bloc : à (block − 1) / 2 cellules du coin nord-ouest.
	var half := 0.5 * (block - 1) / float(cells_per_degree)
	for row in range(first_row, last_row + 1, block):
		if abort:
			return false
		var lat := PopulationGrid.cell_latitude(row) - half
		var km_x := km_y * maxf(cos(deg_to_rad(lat)), 1e-3)
		var dy := (lat - lat0) * km_y
		if absf(dy) > reach_km + km_y * step_deg:
			continue
		var half_cols := int(ceil(minf(reach_km / km_x, 180.0) / step_deg)) + 1
		for k in range(-half_cols, half_cols + 1):
			var col := center_col + k * block
			var lon := PopulationGrid.cell_longitude(col) + half
			var dx := wrapf(lon - lon0, -180.0, 180.0) * km_x
			visitor.call(row, col, dx, dy, km_x)
	return true


## Habitants d'un bloc de block × block cellules de coin nord-ouest (row, col).
static func block_population(row: int, col: int, block: int) -> float:
	var total := 0.0
	for r in block:
		for c in block:
			total += PopulationGrid.cell_population(row + r, col + c)
	return total


## Entrée de pays d'un bilan : {code, name_fr, sovereign_fr, pop_est} du pays d'indice owner dans le masque
## (CountryMask.get_mask()), ou « (hors pays) » pour −1.
static func country_entry(owner: int, mask: Variant) -> Dictionary:
	var entry := {"code": "", "name_fr": "(hors pays)", "sovereign_fr": "", "pop_est": 0}
	if owner >= 0 and mask:
		var c: Dictionary = mask.countries[owner]
		entry.code = c.code
		entry.name_fr = c.name_fr
		entry.sovereign_fr = c.sovereign_fr
		entry.pop_est = c.pop_est
	return entry
