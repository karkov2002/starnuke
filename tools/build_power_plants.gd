extends SceneTree
## Outil hors-jeu : construit assets/power_plants.res (classe PowerPlants) à partir de la Global Power Plant Database
## (World Resources Institute, v1.3, global_power_plant_database.csv). Chaque centrale est rattachée au pays de
## CountryMask qui la contient (assets/country_mask.res doit exister), plutôt qu'au code pays de la base : les
## capacités par pays sont ainsi cohérentes avec les frontières du jeu. Usage :
##   godot --headless --path <projet> --script res://tools/build_power_plants.gd -- <global_power_plant_database.csv>

const PowerPlantsScript := preload("res://scripts/power_plants.gd")
const CountryMaskScript := preload("res://scripts/country_mask.gd")
## Recherche du pays d'une centrale côtière : 16 lignes de 1/120° (~15 km).
const COAST_SEARCH := 16


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
		# Centrale côtière que le trait de côte au 1:10 M place en mer : pays le plus proche à moins de ~15 km.
		var index: int = mask.index_near(CountryMaskScript._row_of(lat), lon, COAST_SEARCH)
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
