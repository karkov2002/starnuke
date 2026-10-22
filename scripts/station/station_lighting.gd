class_name StationLighting
extends RefCounted
## Éclairage intérieur de la station (composant de Station, scripts/station.gd, qui garde les réglages exportés et
## le signal alert_changed) : lampes Lum_* (calque Station.INTERIOR_LAYER), émission propre des luminaires (matériaux
## Int_Lumiere*) et des écrans (matériaux Ecran_*), niveau d'alerte (teinte fondue, pulsation en alerte rouge) et
## « plus de lumière » (Station.Alert.BLACKOUT : luminaires et écrans éteints, LED de secours, ambiance du ciel
## coupée), tout fondu en alert_fade_s. Puissance comme un potentiomètre : réglage du modèle × GameSettings.interior_light
## × night_light_ratio dans l'ombre de la Terre. Les matériaux du modèle sont partagés et persistent d'une partie à
## l'autre : l'émission d'origine est gardée en métadonnée. Appliqué à chaque image seulement si quelque chose change.

## Niveau d'alerte courant (Station.Alert).
var alert := Station.Alert.NONE
## Part de l'extinction (0 : luminaires normaux, 1 : « plus de lumière »), fondue : écrans animés (TechScreens).
var dark := 0.0

var _station: Station
var _orbit: OrbitSimulation
var _environment: Environment
var _interior_lights: Array[OmniLight3D] = []
var _lamp_materials: Array[BaseMaterial3D] = []
var _screen_materials: Array[BaseMaterial3D] = []
## Teinte appliquée (fondue) et horloge de la pulsation.
var _alert_tint := Color.WHITE
var _alert_time := 0.0
## Dernières valeurs appliquées aux lumières et matériaux.
var _applied_factor := -1.0
var _applied_tint := Color.BLACK
var _applied_dark := -1.0


## Lampes et matériaux relevés une fois dans le modèle (après la séparation des calques intérieurs) ; orbit donne
## l'ensoleillement, environment (facultatif) l'ambiance du ciel coupée au black-out.
func _init(station: Station, orbit: OrbitSimulation, environment: Environment) -> void:
	_station = station
	_orbit = orbit
	_environment = environment
	if _environment and not _environment.has_meta(&"base_ambient_energy"):
		# Ressource partagée d'une partie à l'autre : l'ambiance d'origine est gardée en métadonnée.
		_environment.set_meta(&"base_ambient_energy", _environment.ambient_light_energy)
	for light: OmniLight3D in station.find_children("Lum_*", "OmniLight3D", true, false):
		light.light_cull_mask = Station.INTERIOR_LAYER
		light.light_energy = station.interior_light_energy
		light.omni_range = station.interior_light_range
		light.omni_attenuation = station.interior_light_attenuation
		light.light_color = Color.WHITE
		light.light_temperature = station.interior_light_temperature
		light.light_specular = station.interior_light_specular
		light.shadow_enabled = station.interior_shadows
		_interior_lights.append(light)
	var done := {}
	for mesh_instance: MeshInstance3D in station.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for s in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(s) as BaseMaterial3D
			if material == null or not material.emission_enabled or done.has(material):
				continue
			var lamp := material.resource_name.begins_with("Int_Lumiere")
			var screen := material.resource_name.begins_with("Ecran_")
			if not lamp and not screen:
				continue
			done[material] = true
			if not material.has_meta(&"base_emission"):
				material.set_meta(&"base_emission", material.emission_energy_multiplier)
				material.set_meta(&"base_emission_color", material.emission)
				material.set_meta(&"base_albedo", material.albedo_color)
			if lamp:
				_lamp_materials.append(material)
			else:
				_screen_materials.append(material)
	update(0.0)


## Niveau d'alerte (couleur des luminaires, voir Station.alert_colors) ; vrai s'il change.
func set_alert(level: Station.Alert) -> bool:
	if level == alert:
		return false
	alert = level
	return true


## Fondus et application (seulement si le facteur, la teinte ou l'extinction a changé).
func update(delta: float) -> void:
	var sunlight := _orbit.get_sunlight_fraction() if _orbit else 1.0
	var factor := GameSettings.interior_light * lerpf(_station.night_light_ratio, 1.0, sunlight)
	# Fondus (teinte, extinction) : l'état avance à chaque image et s'accroche à la cible une fois tout près — sinon,
	# à haute cadence, les petits pas par image bloquaient le fondu à mi-course.
	var colors := _station.alert_colors
	var target := colors[alert] if alert < colors.size() else Color.WHITE
	var blend := 1.0 - exp(-delta / maxf(_station.alert_fade_s, 1e-3)) if delta > 0.0 else 1.0
	_alert_tint = target if _alert_tint.is_equal_approx(target) else _alert_tint.lerp(target, blend)
	if alert == Station.Alert.RED:
		_alert_time += delta
		factor *= 1.0 - 0.5 * _station.red_alert_pulse * (1.0 - cos(TAU * _alert_time / maxf(_station.red_alert_period_s, 0.1)))
	else:
		_alert_time = 0.0
	# Extinction (« plus de lumière ») : les luminaires s'éteignent pendant que les LED de secours s'allument.
	var dark_target := 1.0 if alert == Station.Alert.BLACKOUT else 0.0
	dark = dark_target if absf(dark - dark_target) < 0.001 else lerpf(dark, dark_target, blend)
	var tint := _alert_tint
	factor *= 1.0 - dark
	if absf(factor - _applied_factor) < 0.001 and tint.is_equal_approx(_applied_tint) and absf(dark - _applied_dark) < 0.001:
		return
	_applied_factor = factor
	_applied_tint = tint
	_applied_dark = dark
	if _environment:
		_environment.ambient_light_energy = float(_environment.get_meta(&"base_ambient_energy")) * (1.0 - dark)
	var every := maxi(_station.emergency_light_every, 1)
	for i in _interior_lights.size():
		var light := _interior_lights[i]
		var emergency := dark * _station.emergency_light_energy if i % every == 0 else 0.0
		light.light_energy = _station.interior_light_energy * factor + emergency
		light.light_color = tint.lerp(_station.emergency_light_color, dark)
	for material in _lamp_materials:
		material.emission_energy_multiplier = float(material.get_meta(&"base_emission")) * factor
		# Seuls les luminaires blancs changent de couleur (les feux rouges des rails gardent la leur).
		if material.resource_name == "Int_Lumiere":
			material.emission = (material.get_meta(&"base_emission_color") as Color) * tint
		# Éteint, un luminaire est gris sombre (son albédo blanc paraîtrait encore allumé sous les LED de secours).
		material.albedo_color = (material.get_meta(&"base_albedo") as Color).lerp(Color(0.06, 0.06, 0.06), dark)
	for material in _screen_materials:
		material.emission_energy_multiplier = float(material.get_meta(&"base_emission")) * (1.0 - dark)
		material.albedo_color = (material.get_meta(&"base_albedo") as Color).lerp(Color(0.02, 0.02, 0.02), dark)
