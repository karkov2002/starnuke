class_name NukeGroundFX
extends Node
## Effets durables des explosions au sol, créé par NukeLauncher (nœud GroundFX) : incendies (qui s'étendent sur
## plusieurs jours), fumée des incendies, trace au sol (sol brûlé puis brun, gravats) et black-out électrique, qui
## persistent jusqu'à la fin de la partie (règles de jeu ; lois et durées dans NukeScaling, constantes FIRE_*, SCAR_*,
## SMOKE_* et BLACKOUT_*). Le rendu est fait par le shader du sol (nuke/shaders/nuke_fire.gdshaderinc,
## nuke/shaders/nuke_smoke.gdshaderinc, nuke/shaders/nuke_blackout.gdshaderinc), dans les matériaux de la Terre qui
## déclarent nuke_ground_count.
##
## Aucun plafond sur le nombre d'explosions : elles sont transmises par des textures de données
## (nuke/shaders/nuke_ground.gdshaderinc) :
## - nuke_ground_events (RGBAF, une colonne par explosion, ROWS lignes) : ligne 0 = (centre en km dans le repère de la
##   planète, temps physique écoulé en s) ; ligne 1 = (rayon détruit, rayon de la panne régionale, rayon initial des
##   incendies (0 : rien ne brûle), portée de l'explosion) en km ; ligne 2 = (direction où va le vent de la fumée,
##   vecteur unitaire du repère de la planète, vitesse en m/s) ; ligne 3 = (rayon des gravats en km, fumée par m²
##   de sol en feu en kg/m² (négative tant que NukeImpact ne l'a pas calculée : pas encore de fumée), inutilisés) ;
## - nuke_ground_cells (RGF, maille de 1° en longitude × latitude) : (début, nombre) de la liste des explosions dont la
##   portée touche la maille, rangée dans nuke_ground_index (RF, INDEX_WIDTH de large) : un pixel du sol ne teste que
##   les explosions proches ;
## - nuke_smoke_cells, nuke_smoke_index : même maille pour les panaches de fumée (qui s'étendent sous le vent, sur des
##   centaines de km), reconstruite quand un panache s'allonge nettement ou disparaît ;
## - nuke_smoke_rate (RF, NukeScaling.SMOKE_TABLE_SIZE) : surface en feu f(t), commune à toutes les puissances ;
## - nuke_ground_countries (RF, indice CountryMask + 1) : temps physique écoulé depuis la panne nationale (s), 0 sinon.
## Seuls les temps changent à chaque image (la texture des événements est renvoyée entière) ; la liste et l'index sont
## reconstruits quand la liste des explosions change (NukeLauncher.effects_changed : tir, effacement).

const INDEX_WIDTH := 4096
const CELLS_X := 360
const CELLS_Y := 180
const ROWS := 4
const MIN_CAPACITY := 64
const COUNTRY_IDS := preload("res://assets/textures/country_ids.png")
## Pas (km) des disques qui couvrent un panache dans la maille de la fumée.
const SMOKE_CELL_STEP_KM := 60.0
## Le panache est indexé jusqu'où son épaisseur optique tombe sous SMOKE_CELL_MIN_TAU (au débit maximal des incendies :
## la maille reste valable quand le débit varie).
const SMOKE_CELL_MIN_TAU := 0.005

var _launcher: NukeLauncher
var _materials: Array[ShaderMaterial] = []
## Explosions transmises, dans l'ordre des colonnes de nuke_ground_events ; _dirty : liste à reconstruire.
var _effects: Array[NukeEffect] = []
var _dirty := true
## Contenu de nuke_ground_events (RGBAF, _capacity × ROWS), et temps physiques envoyés (pour ne renvoyer que s'ils
## changent).
var _data := PackedFloat32Array()
var _capacity := 0
var _times := PackedFloat64Array()
## Données fixes d'une explosion (lignes 1 à 3), calculées une fois : instance_id -> Array[Vector4].
var _statics := {}
## État des panaches à la dernière construction de leur maille (une clé par explosion, cf. _smoke_key).
var _smoke_keys := PackedInt32Array()
## Fin des incendies (s, temps physique) : au-delà, plus de fumée émise ; surface en feu maximale (R0²).
var _fire_end_s := 0.0
var _burning_peak := 0.0
var _events_texture := ImageTexture.new()
var _cells_texture := ImageTexture.new()
var _index_texture := ImageTexture.new()
var _smoke_cells_texture := ImageTexture.new()
var _smoke_index_texture := ImageTexture.new()
var _countries_texture := ImageTexture.new()
var _country_times := PackedFloat32Array()


func setup(launcher: NukeLauncher, earth: Node3D) -> void:
	_launcher = launcher
	_launcher.effects_changed.connect(func() -> void: _dirty = true)
	_materials = NukeFXMaterials.find(earth, &"nuke_ground_count")
	var table := NukeScaling.smoke_table()
	for value in table:
		_burning_peak = maxf(_burning_peak, value)
	var scale := log(1.0 + NukeScaling.SMOKE_TABLE_MAX_S / 60.0)
	for i in table.size():
		if table[i] > 1e-3 * _burning_peak:
			_fire_end_s = 60.0 * (exp(float(i + 1) / float(table.size() - 1) * scale) - 1.0)
	var rate := ImageTexture.create_from_image(Image.create_from_data(table.size(), 1, false, Image.FORMAT_RF,
			table.to_byte_array()))
	for material in _materials:
		material.set_shader_parameter("nuke_ground_count", 0)
		material.set_shader_parameter("nuke_smoke_count", 0)
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
		material.set_shader_parameter("nuke_scar_brown_s", Vector2(NukeScaling.SCAR_BROWN_START_S,
				NukeScaling.SCAR_BROWN_END_S))
		material.set_shader_parameter("nuke_smoke_rate", rate)
		material.set_shader_parameter("nuke_smoke_rate_scale", scale)
		material.set_shader_parameter("nuke_smoke_physics", Vector4(NukeScaling.FIRE_BURN_S,
				NukeScaling.SMOKE_MEE_M2_KG, NukeScaling.SMOKE_SPREAD_K_M2_S, NukeScaling.SMOKE_LIFETIME_S))
		material.set_shader_parameter("nuke_smoke_source", Vector2(NukeScaling.SMOKE_SOURCE_SIGMA,
				NukeScaling.SMOKE_MAX_AGE_S))


func _process(_delta: float) -> void:
	if _launcher == null:
		return
	if _dirty:
		_dirty = false
		_rebuild(_launcher.get_effects())
	var changed := false
	var smoke_changed := false
	for i in _effects.size():
		var t := _effects[i].get_time_s()
		if t != _times[i]:
			_times[i] = t
			_data[i * 4 + 3] = t
			changed = true
			var key := _smoke_key(i)
			if key != _smoke_keys[i]:
				smoke_changed = true
		# Fumée par m² en feu, calculée par NukeImpact quelques ms après le tir.
		var statics: Array = _statics[_effects[i].get_instance_id()]
		var row3: Vector4 = statics[2]
		if row3.y < 0.0 and _effects[i].smoke_yield_kg_m2 >= 0.0:
			row3.y = _effects[i].smoke_yield_kg_m2
			statics[2] = row3
			_write(i, 3, row3)
			changed = true
			smoke_changed = true
	if changed:
		_events_texture.update(Image.create_from_data(_capacity, ROWS, false, Image.FORMAT_RGBAF,
				_data.to_byte_array()))
	if smoke_changed:
		_rebuild_smoke()
	_update_countries()


## Renvoie tout aux matériaux à la prochaine image (après qu'un autre a modifié leurs paramètres, cf. banc de mesure).
func refresh() -> void:
	_dirty = true
	_country_times = PackedFloat32Array()


## Liste des explosions changée : colonnes, maille et index reconstruits.
func _rebuild(effects: Array[NukeEffect]) -> void:
	_effects = effects.duplicate()
	var count := _effects.size()
	var kept := {}
	for effect in _effects:
		var id := effect.get_instance_id()
		kept[id] = _statics[id] if _statics.has(id) else _compute_statics(effect)
	_statics = kept
	_set_parameter("nuke_ground_count", count)
	if count == 0:
		_smoke_keys = PackedInt32Array()
		_set_parameter("nuke_smoke_count", 0)
		return

	_capacity = maxi(MIN_CAPACITY, nearest_po2(count))
	_data = PackedFloat32Array()
	_data.resize(_capacity * ROWS * 4)
	_times = PackedFloat64Array()
	_times.resize(count)
	var lists := {} # maille -> PackedInt32Array des explosions qui la touchent
	for i in count:
		var effect := _effects[i]
		var pos := effect.position / OrbitSimulation.SCENE_UNITS_PER_KM
		var t := effect.get_time_s()
		var statics: Array = _statics[effect.get_instance_id()]
		_times[i] = t
		_write(i, 0, Vector4(pos.x, pos.y, pos.z, t))
		for row in range(1, ROWS):
			_write(i, row, statics[row - 1])
		var reach: float = statics[0].w
		for cell in _cells_within(effect.params.latitude_deg, effect.params.longitude_deg, reach):
			_add_to_cell(lists, cell, i)

	_events_texture.set_image(Image.create_from_data(_capacity, ROWS, false, Image.FORMAT_RGBAF, _data.to_byte_array()))
	_upload_index(lists, _cells_texture, _index_texture)
	_set_parameter("nuke_ground_events", _events_texture)
	_set_parameter("nuke_ground_cells", _cells_texture)
	_set_parameter("nuke_ground_index", _index_texture)
	_rebuild_smoke()


## Données fixes d'une explosion (lignes 1 à 3 de nuke_ground_events).
func _compute_statics(effect: NukeEffect) -> Array:
	var params := effect.params
	var w := params.yield_kt
	var h := params.burst_height_km
	var destroyed := NukeScaling.blackout_destroyed_km(w, h)
	var region := NukeScaling.blackout_region_km(w, h)
	var fire := NukeScaling.fire_base_radius_km(w) if effect.can_ignite_land() else 0.0
	var rubble := NukeScaling.overpressure_range_km(w, NukeScaling.SCAR_RUBBLE_PSI, h)
	# Portée : celle du test du shader pour la panne régionale (1,2 R) et extension finale des incendies.
	var reach := maxf(region * 1.2, NukeScaling.fire_reach_km(w) if fire > 0.0 else 0.0)
	# Vent de la fumée (vers l'est, vers le nord) dans le repère de la planète.
	var basis := effect.transform.basis
	var east := basis.x.normalized()
	var north := -basis.z.normalized()
	var wind := params.wind_at(NukeScaling.SMOKE_HEIGHT_KM)
	var speed := maxf(wind.length(), NukeScaling.SMOKE_MIN_WIND_M_S)
	var direction := (east * wind.x + north * wind.y).normalized() if wind.length() > 1e-3 else east
	return [Vector4(destroyed, region, fire, reach), Vector4(direction.x, direction.y, direction.z, speed),
			Vector4(rubble, effect.smoke_yield_kg_m2, 0.0, 0.0)]


## Âges (s) de la fumée encore présente dans le panache de l'explosion i : (plus jeune, plus vieille) ; vide si elle
## n'en a plus (ou n'en a jamais : rien ne brûle). Fumée émise de 0 à _fire_end_s, gardée jusqu'à SMOKE_MAX_AGE_S.
func _smoke_ages(i: int) -> Vector2:
	var statics: Array = _statics[_effects[i].get_instance_id()]
	var t := _times[i]
	# Rien ne brûle, ou fumée par m² pas encore calculée (NukeImpact).
	if statics[0].z <= 0.0 or statics[2].y <= 0.0 or t <= 0.0:
		return Vector2.ZERO
	var youngest := maxf(t - _fire_end_s, 0.0)
	var oldest := minf(t, NukeScaling.SMOKE_MAX_AGE_S)
	return Vector2(youngest, oldest) if oldest > youngest else Vector2.ZERO


## Clé de l'état d'un panache : la maille de la fumée est reconstruite quand une clé change (allongement de ~10 %,
## fin de l'émission, disparition).
func _smoke_key(i: int) -> int:
	var ages := _smoke_ages(i)
	if ages == Vector2.ZERO:
		return -1
	return floori(log(1.0 + ages.y / 600.0) * 10.0) * 1000 + floori(log(1.0 + ages.x / 600.0) * 10.0)


func _rebuild_smoke() -> void:
	_smoke_keys.resize(_effects.size())
	var lists := {}
	var active := 0
	for i in _effects.size():
		_smoke_keys[i] = _smoke_key(i)
		var ages := _smoke_ages(i)
		if ages == Vector2.ZERO:
			continue
		active += 1
		var statics: Array = _statics[_effects[i].get_instance_id()]
		var fire_km: float = statics[0].z
		var wind: Vector4 = statics[1]
		var smoke_yield: float = statics[2].y
		var origin := (_effects[i].position / OrbitSimulation.SCENE_UNITS_PER_KM).normalized()
		var direction := Vector3(wind.x, wind.y, wind.z)
		var start_km := wind.w * ages.x / 1000.0
		var end_km := wind.w * ages.y / 1000.0 + 2.0 * NukeScaling.smoke_sigma_m(fire_km, ages.y) / 1000.0
		var steps := maxi(ceili((end_km - start_km) / SMOKE_CELL_STEP_KM), 1)
		for s in steps + 1:
			var along := lerpf(start_km, end_km, float(s) / steps)
			var age := along * 1000.0 / wind.w
			# Demi-largeur où τ tombe sous le seuil : τ_axe · exp(−y² / 2σ²) = SMOKE_CELL_MIN_TAU.
			var sigma := NukeScaling.smoke_sigma_m(fire_km, age)
			var axis_tau := NukeScaling.SMOKE_MEE_M2_KG * smoke_yield * 1.0e6 * fire_km * fire_km * _burning_peak \
					/ NukeScaling.FIRE_BURN_S * exp(-age / NukeScaling.SMOKE_LIFETIME_S) / (wind.w * sqrt(TAU) * sigma)
			var half_width := sigma * sqrt(2.0 * log(maxf(axis_tau / SMOKE_CELL_MIN_TAU, 1.0)))
			# Marge : front étalé et bords déformés par le bruit du shader (jusqu'à ~0,7 σ), front à ±2 σ.
			var radius := (half_width + 2.0 * sigma) / 1000.0 + SMOKE_CELL_STEP_KM
			# Point du grand cercle à la distance along, dans la direction du vent (repère du maillage).
			var angle := along / OrbitSimulation.EARTH_RADIUS_KM
			var p := origin * cos(angle) + direction * sin(angle)
			var lat := rad_to_deg(asin(clampf(p.y, -1.0, 1.0)))
			var lon := rad_to_deg(atan2(-p.x, -p.z))
			for cell in _cells_within(lat, lon, radius):
				_add_to_cell(lists, cell, i)
	_upload_index(lists, _smoke_cells_texture, _smoke_index_texture)
	_set_parameter("nuke_smoke_cells", _smoke_cells_texture)
	_set_parameter("nuke_smoke_index", _smoke_index_texture)
	_set_parameter("nuke_smoke_count", active)


static func _add_to_cell(lists: Dictionary, cell: int, event: int) -> void:
	if not lists.has(cell):
		lists[cell] = PackedInt32Array()
	var ids: PackedInt32Array = lists[cell]
	if ids.is_empty() or ids[-1] != event:
		ids.append(event)
		lists[cell] = ids


## Maille (début, nombre) et liste des explosions par maille, envoyées dans deux textures.
static func _upload_index(lists: Dictionary, cells_texture: ImageTexture, index_texture: ImageTexture) -> void:
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
	cells_texture.set_image(Image.create_from_data(CELLS_X, CELLS_Y, false, Image.FORMAT_RGF, cells.to_byte_array()))
	index_texture.set_image(Image.create_from_data(INDEX_WIDTH, rows, false, Image.FORMAT_RF, index.to_byte_array()))


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
