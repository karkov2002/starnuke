class_name PowerPlants
extends Resource
## Centrales électriques du monde (assets/power_plants.res, généré par tools/build_power_plants.gd à partir de la
## Global Power Plant Database du World Resources Institute, v1.3, licence CC BY 4.0) : position, puissance installée,
## combustible principal, pays (indice de CountryMask, -1 en mer : éoliennes en mer), et capacité totale de chaque
## pays (somme de ses centrales).

const PATH := "res://assets/power_plants.res"

@export var names := PackedStringArray()
@export var fuels := PackedStringArray()
@export var latitudes := PackedFloat32Array()
@export var longitudes := PackedFloat32Array()
@export var capacities_mw := PackedFloat32Array()
@export var countries := PackedInt32Array()
## Capacité installée de chaque pays (MW), indexée comme CountryMask.countries.
@export var country_capacity_mw := PackedFloat32Array()

## Base chargée une fois (null si le fichier manque).
static func get_plants() -> PowerPlants:
	return DataResource.cached(PATH, "tools/build_power_plants.gd") as PowerPlants


## Indices des centrales à moins de radius_km du point (degrés).
func within(latitude_deg: float, longitude_deg: float, radius_km: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var dlat := radius_km / GeoMath.KM_PER_DEGREE
	var km_per_lon := GeoMath.KM_PER_DEGREE * maxf(cos(deg_to_rad(latitude_deg)), 1e-3)
	for i in latitudes.size():
		var lat := latitudes[i]
		if absf(lat - latitude_deg) > dlat:
			continue
		var dx := wrapf(longitudes[i] - longitude_deg, -180.0, 180.0) * km_per_lon
		var dy := (lat - latitude_deg) * GeoMath.KM_PER_DEGREE
		if dx * dx + dy * dy <= radius_km * radius_km:
			result.append(i)
	return result
