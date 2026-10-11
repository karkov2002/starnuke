class_name NukeGroundFX
extends Node
## Effets durables des explosions au sol, créé par NukeLauncher (nœud GroundFX) : incendies (qui s'étendent sur
## plusieurs jours), sol calciné et black-out électrique, qui persistent jusqu'à la fin de la partie (règles de jeu ;
## lois et durées dans NukeScaling, constantes FIRE_* et BLACKOUT_*). Le rendu est fait par le shader du sol
## (nuke/shaders/nuke_fire.gdshaderinc, nuke/shaders/nuke_blackout.gdshaderinc), dans les matériaux de la Terre qui
## déclarent nuke_ground_count.
##
## Aucun plafond sur le nombre d'explosions : elles sont transmises par des textures de données
## (nuke/shaders/nuke_ground.gdshaderinc) :
## - nuke_ground_events (RGBAF, une colonne par explosion) : ligne 0 = (centre en km dans le repère de la planète,
##   temps physique écoulé en s), ligne 1 = (rayon détruit, rayon de la panne régionale, rayon initial des incendies
##   (0 : rien ne brûle), portée de l'explosion), en km ;
## - nuke_ground_cells (RGF, maille de 1° en longitude × latitude) : (début, nombre) de la liste des explosions dont la
##   portée touche la maille, rangée dans nuke_ground_index (RF, INDEX_WIDTH de large) : un pixel du sol ne teste que
##   les explosions proches ;
## - nuke_ground_countries (RF, indice CountryMask + 1) : temps physique écoulé depuis la panne nationale (s), 0 sinon.
## Seuls les temps changent à chaque image (ligne 0 renvoyée) ; la liste et l'index sont reconstruits quand la liste
## des explosions change (tir, effacement).

const INDEX_WIDTH := 4096
const CELLS_X := 360
const CELLS_Y := 180
const MIN_CAPACITY := 64
const COUNTRY_IDS := preload("res://assets/textures/country_ids.png")

var _launcher: NukeLauncher
var _materials: Array[ShaderMaterial] = []
## Explosions transmises, dans l'ordre des colonnes de nuke_ground_events.
var _effects: Array[NukeEffect] = []
## Contenu de nuke_ground_events (RGBAF, _capacity × 2), et temps physiques envoyés (pour ne renvoyer que s'ils changent).
var _data := PackedFloat32Array()
var _capacity := 0
var _times := PackedFloat64Array()
## Rayons d'une explosion (ligne 1), calculés une fois : instance_id -> Vector4.
var _radii := {}
var _events_texture := ImageTexture.new()
var _cells_texture := ImageTexture.new()
var _index_texture := ImageTexture.new()
var _countries_texture := ImageTexture.new()
var _country_times := PackedFloat32Array()


func setup(launcher: NukeLauncher, earth: Node3D) -> void:
	_launcher = launcher
	_materials = NukeFXMaterials.find(earth, &"nuke_ground_count")
	for material in _materials:
		material.set_shader_parameter("nuke_ground_count", 0)
		material.set_shader_parameter("nuke_ground_country_count", 0)
		material.set_shader_parameter("nuke_country_ids", COUNTRY_IDS)
		# Lois : une seule source, NukeScaling.
		material.set_shader_parameter("nuke_blackout_cascade_tau_s", NukeScaling.BLACKOUT_CASCADE_TAU_S)
		material.set_shader_parameter("nuke_blackout_national_off_s", NukeScaling.BLACKOUT_NATIONAL_OFF_S)
		material.set_shader_parameter("nuke_fire_growth_s", Vector3(NukeScaling.FIRE_FIRST_SHARE,
				NukeScaling.FIRE_GROWTH_START_S, NukeScaling.FIRE_GROWTH_END_S))
		material.set_shader_parameter("nuke_fire_spread", Vector2(NukeScaling.FIRE_SPREAD, NukeScaling.FIRE_SPREAD_S))
		material.set_shader_parameter("nuke_fire_front", Vector2(NukeScaling.FIRE_FRONT_SHARE,
				NukeScaling.FIRE_FRONT_RISE_S))
		material.set_shader_parameter("nuke_fire_burn_s", Vector2(NukeScaling.FIRE_BURN_S, NukeScaling.FIRE_CHAR_S))
		material.set_shader_parameter("nuke_fire_edge_noise", NukeScaling.FIRE_EDGE_NOISE)


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	var effects := _launcher.get_effects()
	if effects != _effects:
		_rebuild(effects)
	var changed := false
	for i in _effects.size():
		var t := _effects[i].get_time_s()
		if t != _times[i]:
			_times[i] = t
			_data[i * 4 + 3] = t
			changed = true
	if changed:
		_events_texture.update(Image.create_from_data(_capacity, 2, false, Image.FORMAT_RGBAF, _data.to_byte_array()))
	_update_countries()


## Renvoie tout aux matériaux à la prochaine image (après qu'un autre a modifié leurs paramètres, cf. banc de mesure).
func refresh() -> void:
	_effects.clear()
	_country_times = PackedFloat32Array()


## Liste des explosions changée : colonnes, maille et index reconstruits.
func _rebuild(effects: Array[NukeEffect]) -> void:
	_effects = effects.duplicate()
	var count := _effects.size()
	var kept := {}
	for effect in _effects:
		var id := effect.get_instance_id()
		kept[id] = _radii[id] if _radii.has(id) else _compute_radii(effect)
	_radii = kept
	_set_parameter("nuke_ground_count", count)
	if count == 0:
		return

	_capacity = maxi(MIN_CAPACITY, nearest_po2(count))
	_data = PackedFloat32Array()
	_data.resize(_capacity * 2 * 4)
	_times = PackedFloat64Array()
	_times.resize(count)
	var lists := {} # maille -> PackedInt32Array des explosions qui la touchent
	for i in count:
		var effect := _effects[i]
		var pos := effect.position / OrbitSimulation.SCENE_UNITS_PER_KM
		var t := effect.get_time_s()
		var radii: Vector4 = _radii[effect.get_instance_id()]
		_times[i] = t
		_write(i, 0, Vector4(pos.x, pos.y, pos.z, t))
		_write(i, 1, radii)
		for cell in _cells_within(effect.params.latitude_deg, effect.params.longitude_deg, radii.w):
			if not lists.has(cell):
				lists[cell] = PackedInt32Array()
			lists[cell].append(i)

	var cells := PackedFloat32Array()
	cells.resize(CELLS_X * CELLS_Y * 2)
	var index := PackedFloat32Array()
	for cell: int in lists:
		var ids: PackedInt32Array = lists[cell]
		cells[cell * 2] = index.size()
		cells[cell * 2 + 1] = ids.size()
		for id in ids:
			index.append(id)
	var rows := maxi(ceili(index.size() / float(INDEX_WIDTH)), 1)
	index.resize(rows * INDEX_WIDTH)

	_events_texture.set_image(Image.create_from_data(_capacity, 2, false, Image.FORMAT_RGBAF, _data.to_byte_array()))
	_cells_texture.set_image(Image.create_from_data(CELLS_X, CELLS_Y, false, Image.FORMAT_RGF, cells.to_byte_array()))
	_index_texture.set_image(Image.create_from_data(INDEX_WIDTH, rows, false, Image.FORMAT_RF, index.to_byte_array()))
	_set_parameter("nuke_ground_events", _events_texture)
	_set_parameter("nuke_ground_cells", _cells_texture)
	_set_parameter("nuke_ground_index", _index_texture)


## Rayons d'une explosion (km) : (zone détruite, panne régionale, incendies (0 sans terre à portée), portée totale).
func _compute_radii(effect: NukeEffect) -> Vector4:
	var params := effect.params
	var destroyed := NukeScaling.blackout_destroyed_km(params.yield_kt, params.burst_height_km)
	var region := NukeScaling.blackout_region_km(params.yield_kt, params.burst_height_km)
	var fire := NukeScaling.fire_base_radius_km(params.yield_kt) if effect.can_ignite_land() else 0.0
	# Portée : celle du test du shader pour la panne régionale (1,2 R) et extension finale des incendies.
	var reach := maxf(region * 1.2, NukeScaling.fire_reach_km(params.yield_kt) if fire > 0.0 else 0.0)
	return Vector4(destroyed, region, fire, reach)


func _write(column: int, row: int, value: Vector4) -> void:
	var k := (row * _capacity + column) * 4
	_data[k] = value.x
	_data[k + 1] = value.y
	_data[k + 2] = value.z
	_data[k + 3] = value.w


## Mailles (indice ligne × CELLS_X + colonne ; ligne 0 au nord) que touche le disque de rayon radius_km centré en
## (latitude, longitude) : bande de latitudes, et longitudes de la calotte sphérique (asin(sin α / cos φ)).
static func _cells_within(latitude_deg: float, longitude_deg: float, radius_km: float) -> PackedInt32Array:
	var result := PackedInt32Array()
	var alpha := radius_km / OrbitSimulation.EARTH_RADIUS_KM
	var alpha_deg := rad_to_deg(alpha)
	var first_row := clampi(floori(90.0 - (latitude_deg + alpha_deg)), 0, CELLS_Y - 1)
	var last_row := clampi(floori(90.0 - (latitude_deg - alpha_deg)), 0, CELLS_Y - 1)
	var first_col := 0
	var last_col := CELLS_X - 1
	var cos_lat := cos(deg_to_rad(latitude_deg))
	if latitude_deg + alpha_deg < 90.0 and latitude_deg - alpha_deg > -90.0 and sin(alpha) < cos_lat:
		var dlon := rad_to_deg(asin(sin(alpha) / cos_lat))
		var lon := wrapf(longitude_deg, -180.0, 180.0) + 180.0
		first_col = floori(lon - dlon)
		last_col = floori(lon + dlon)
	for row in range(first_row, last_row + 1):
		for col in range(first_col, last_col + 1):
			result.append(row * CELLS_X + posmod(col, CELLS_X))
	return result


## Pannes nationales (décidées au tir par NukeGridImpact, NukeEffect.grid, connues quelques ms plus tard) : temps
## physique depuis la panne la plus ancienne de chaque pays.
func _update_countries() -> void:
	var times := {}
	for effect in _effects:
		if effect.grid.is_empty() or effect.grid.national < 0:
			continue
		var t := effect.get_time_s()
		if t > 0.0:
			times[effect.grid.national + 1] = maxf(times.get(effect.grid.national + 1, 0.0), t)
	if times.is_empty() and _country_times.is_empty():
		return
	if _country_times.is_empty():
		# Premier pays plongé dans le noir : CountryMask est déjà chargé (NukeGridImpact l'a lu).
		var mask := CountryMask.get_mask()
		_country_times.resize((mask.countries.size() if mask else 0) + 1)
		_countries_texture.set_image(Image.create_from_data(_country_times.size(), 1, false, Image.FORMAT_RF,
				_country_times.to_byte_array()))
		_set_parameter("nuke_ground_countries", _countries_texture)
	var changed := false
	for id in _country_times.size():
		var t: float = times.get(id, 0.0)
		if not is_equal_approx(_country_times[id], t):
			_country_times[id] = t
			changed = true
	if changed:
		_countries_texture.update(Image.create_from_data(_country_times.size(), 1, false, Image.FORMAT_RF,
				_country_times.to_byte_array()))
		_set_parameter("nuke_ground_country_count", times.size())


func _set_parameter(parameter: StringName, value: Variant) -> void:
	for material in _materials:
		material.set_shader_parameter(parameter, value)
