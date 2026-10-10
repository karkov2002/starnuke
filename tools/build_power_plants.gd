extends SceneTree
## Outil hors-jeu : construit assets/power_plants.res (classe PowerPlants) à partir de la Global Power Plant Database
## (World Resources Institute, v1.3, global_power_plant_database.csv). Chaque centrale est rattachée au pays de
## CountryMask qui la contient (assets/country_mask.res doit exister), plutôt qu'au code pays de la base : les
## capacités par pays sont ainsi cohérentes avec les frontières du jeu. Usage :
##   godot --headless --path <projet> --script res://tools/build_power_plants.gd -- <global_power_plant_database.csv>

const PowerPlantsScript := preload("res://scripts/power_plants.gd")
const CountryMaskScript := preload("res://scripts/country_mask.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var file := FileAccess.open(args[0], FileAccess.READ) if not args.is_empty() else null
	if file == null:
		push_error("Usage : -- <global_power_plant_database.csv>")
		quit(1)
		return
	var mask: Resource = load(CountryMaskScript.PATH)
	var header := file.get_csv_line()
	var col := {}
	for i in header.size():
		col[header[i]] = i
	var plants: Resource = PowerPlantsScript.new()
	var capacity := PackedFloat32Array()
	capacity.resize(mask.countries.size())
	var at_sea := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size():
			continue
		var lat := float(row[col.latitude])
		var lon := float(row[col.longitude])
		var mw := float(row[col.capacity_mw])
		var index := _country_near(mask, lat, lon)
		plants.names.append(row[col.name])
		plants.fuels.append(row[col.primary_fuel])
		plants.latitudes.append(lat)
		plants.longitudes.append(lon)
		plants.capacities_mw.append(mw)
		plants.countries.append(index)
		if index >= 0:
			capacity[index] += mw
		else:
			at_sea += 1
	plants.country_capacity_mw = capacity
	var error := ResourceSaver.save(plants, PowerPlantsScript.PATH, ResourceSaver.FLAG_COMPRESS)
	var total := 0.0
	for c in capacity:
		total += c
	print("%d centrales (%d hors pays : en mer ou sur une côte), %.0f GW -> %s (%s)" % [plants.names.size(), at_sea,
			total / 1000.0, PowerPlantsScript.PATH, error_string(error)])
	quit(0 if error == OK else 1)


## Pays au point ; à défaut (centrale côtière que le trait de côte au 1:10 M place en mer), le plus proche à moins de
## COAST_SEARCH lignes de 1/120° (~15 km). -1 au large (éoliennes en mer).
const COAST_SEARCH := 16


func _country_near(mask: Resource, lat: float, lon: float) -> int:
	var row: int = CountryMaskScript._row_of(lat)
	var step := 1.0 / CountryMaskScript.ROWS_PER_DEGREE
	for radius in COAST_SEARCH + 1:
		for dr in range(-radius, radius + 1):
			for dc in range(-radius, radius + 1):
				if maxi(absi(dr), absi(dc)) != radius:
					continue
				var r := clampi(row + dr, 0, CountryMaskScript.row_count() - 1)
				var index: int = mask.index_at_row(r, wrapf(lon + dc * step, -180.0, 180.0))
				if index >= 0:
					return index
	return -1
