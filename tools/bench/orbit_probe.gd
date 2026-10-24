extends Node
## Sonde de l'orbite (lot 2, étape 7 de l'audit : la séparation modèle / pose de la scène ne doit rien changer) :
## en headless, sans rendu, elle place l'orbite à une date fixe puis relève, à plusieurs instants et après chaque
## commande de l'API (altitude, inclinaison, date, redémarrage, nouveau plan) :
## - le modèle : position ECI, point survolé, sens de passage, période, fraction de soleil, Ω, angle sidéral ;
## - la pose de la scène : transformation de la Terre, orientation et énergie du soleil, rotation du ciel et uniforms
##   du ciel, uniforms des matériaux de la Terre (sun_direction, cloud_utc_day_s), ecef_to_world, ECI → monde ;
## - l'ordinateur de vol (orbite fantôme d'un plan de manœuvre, instant du nœud) et la chronologie du planificateur
##   de missions (campagne officielle) ;
## puis compare à tools/bench/results/orbit_probe_reference.txt (ProbeCompare). Usage :
##   godot --headless --path . res://tools/bench/orbit_probe.tscn [-- ref]      (code 0 si identique)

const ProbeCompare := preload("res://tools/bench/probe_compare.gd")
const REFERENCE := "res://tools/bench/results/orbit_probe_reference.txt"
const TIMES_S: Array[float] = [0.0, 600.0, 2772.0, 5544.0, 43200.0]
const EARTH_UNIFORMS: Array[StringName] = [&"sun_direction", &"cloud_utc_day_s"]

var _failures := 0
var _record := {}


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FAIL ") + what)
	if not ok:
		_failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	var write_reference := OS.get_cmdline_user_args().has("ref")
	var view: Node = load("res://scenes/orbit_view.tscn").instantiate()
	add_child(view)
	await _frames(30)
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var computer := view.get_node("FlightComputer") as FlightComputer
	orbit.time_scale = 0.0
	orbit.place(CampaignData.parse_utc("2035-07-15T06:00:00Z"), 400.0, 51.6, 40.4, -3.7, true)
	await _frames(2)
	_check(absf(orbit.get_subsatellite_point().x - 40.4) < 0.05, "placée au-dessus de Madrid")

	print("- Instants")
	var start := orbit.sim_time_s
	for t in TIMES_S:
		orbit.sim_time_s = start + t
		await _frames(2)
		_snapshot(view, "t%s" % t)
	orbit.sim_time_s = start
	await _frames(2)

	print("- Commandes")
	var steps := [
		["altitude", func() -> void: orbit.altitude_km = 500.0],
		["inclinaison", func() -> void: orbit.inclination_deg = 65.0],
		["date", func() -> void: orbit.set_utc_unix_s(CampaignData.parse_utc("2035-07-18T11:15:00Z"))],
		["plan", func() -> void: orbit.set_orbit_plane(55.0, 1.0, 420.0, orbit.sim_time_s)],
		["redémarrage", func() -> void: orbit.restart(12.0)],
	]
	for step: Array in steps:
		var before := orbit.get_subsatellite_point()
		(step[1] as Callable).call()
		await _frames(2)
		_snapshot(view, str(step[0]))
		var after := orbit.get_subsatellite_point()
		if step[0] == "altitude" or step[0] == "inclinaison" or step[0] == "date":
			_check(before.distance_to(after) < 0.05, "%s : point survolé conservé (%.3f°)" % [step[0], before.distance_to(after)])
		print("  %s : %s" % [step[0], GeoMath.format_lat_lon(after.x, after.y)])

	print("- Ordinateur de vol")
	computer.target_altitude_km = 450.0
	computer.target_inclination_deg = 60.0
	computer.target_node_shift_deg = 10.0
	await _frames(2)
	_record["flight/ghost"] = computer.get_ghost()
	_record["flight/node_time_s"] = computer.get_node_time_s()
	_record["flight/has_plan"] = computer.has_plan()
	print("  nœud à %.0f s, orbite fantôme %s" % [computer.get_node_time_s(), str(computer.get_ghost())])
	computer.reset_target()

	print("- Planificateur")
	var campaign := CampaignData.parse(Campaigns.read(Campaigns.OFFICIAL))
	_record["planner/timeline"] = MissionPlanner.timeline(campaign)
	var state := MissionPlanner.state_of(orbit)
	var objectives: Array = campaign.mission("test_rivne").objectives
	var started := Time.get_ticks_usec()
	_record["planner/earliest"] = MissionPlanner.earliest(state, objectives, 0.0, 6.0 * 3600.0)
	var cost_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("  %d ligne(s) de chronologie, passage au plus tôt %.0f s (calcul : %.1f ms)" % [
			_record["planner/timeline"].size(), _record["planner/earliest"].time, cost_ms])

	_check_firing_cone(orbit)
	_check_debug_orbit(computer)

	print("- Référence")
	var result := ProbeCompare.check(_record, REFERENCE, write_reference)
	if result.written:
		print("  référence écrite : " + ProjectSettings.globalize_path(REFERENCE))
	elif result.missing:
		_check(false, "pas de référence (lancer avec -- ref)")
	else:
		for d: String in result.diffs.slice(0, 40):
			print("  ≠ " + d)
		_check(result.diffs.is_empty(), "identique à la référence (%d écart(s))" % result.diffs.size())
	print("=== %d échec(s) au total" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Debug : changer l'altitude ou l'inclinaison au curseur ne crée pas de manœuvre (pas d'orbite fantôme affichée).
func _check_debug_orbit(computer: FlightComputer) -> void:
	print("- Debug de l'orbite")
	computer.reset_target()
	var section := OrbitDebugSection.new()
	add_child(section)
	(section.get("_altitude") as HSlider).value = 520.0
	(section.get("_inclination") as HSlider).value = 45.0
	_check(is_equal_approx(computer.get_orbit().altitude_km, 520.0) and not computer.has_plan(),
			"altitude et inclinaison changées sans manœuvre")
	section.queue_free()


## Cône de tir (FiringCone, hors référence) : ouverture et portée selon l'altitude, cibles devant, sur le côté, derrière,
## trop loin ; maillage du HUD (FiringConeMarker).
func _check_firing_cone(orbit: OrbitSimulation) -> void:
	print("- Cône de tir")
	_check(is_equal_approx(FiringCone.aperture_deg(400.0), 70.0) and is_equal_approx(FiringCone.aperture_deg(800.0), 100.0)
			and is_equal_approx(FiringCone.aperture_deg(600.0), 85.0), "ouverture 70° à 400 km, 100° à 800 km")
	var range_km := FiringCone.range_km(400.0)
	_check(range_km > 1700.0 and range_km < 1800.0, "portée à 400 km : %.0f km (80 %% de l'horizon)" % range_km)
	orbit.place(CampaignData.parse_utc("2035-07-15T06:00:00Z"), 400.0, 51.6, 40.4, -3.7, true)
	var here := orbit.get_subsatellite_point()
	var later := orbit.get_subsatellite_point(orbit.sim_time_s + FiringCone.HEADING_STEP_S)
	var heading := GeoMath.initial_bearing_deg(here.x, here.y, later.x, later.y)
	var cases := [[0.0, 1000.0, FiringCone.Status.OK, "devant"], [30.0, 1000.0, FiringCone.Status.OK, "à 30° de la trace"],
			[-40.0, 1000.0, FiringCone.Status.OUT_OF_CONE, "à 40° de la trace"],
			[180.0, 500.0, FiringCone.Status.OUT_OF_CONE, "derrière"],
			[0.0, range_km + 50.0, FiringCone.Status.OUT_OF_RANGE, "au-delà de la portée"]]
	for c: Array in cases:
		var target := GeoMath.destination(here.x, here.y, heading + c[0], c[1])
		_check(FiringCone.status(orbit, target.x, target.y) == c[2], "cible %s" % c[3])
	var mesh := FiringConeMarker.build(400.0)
	_check(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) > 0, "maillage du cône (HUD)")


## Modèle et pose de la scène à l'instant courant.
func _snapshot(view: Node, key: String) -> void:
	var orbit := view.get_node("Orbit") as OrbitSimulation
	var earth := view.get_node("Earth") as Node3D
	var sun := view.get_node("Sun") as DirectionalLight3D
	var environment := (view.get_node("WorldEnvironment") as WorldEnvironment).environment
	var t := orbit.sim_time_s
	_record[key + "/model"] = {"utc": orbit.get_utc_unix_s(), "eci": orbit.get_position_eci(t),
			"ecef": orbit.get_position_ecef(t), "point": orbit.get_subsatellite_point(), "ascending": orbit.is_ascending(),
			"period_s": orbit.get_period_s(), "sunlight": orbit.get_sunlight_fraction(), "raan": orbit.get_raan(t),
			"arg_lat": orbit.get_argument_of_latitude(t), "sidereal": orbit.get_sidereal_angle(t),
			"sun_eci": orbit.get_sun_direction_eci(t), "altitude": orbit.altitude_km,
			"inclination": orbit.inclination_deg, "solar_hour": orbit.get_local_solar_hour(-3.7)}
	var sky_material := environment.sky.sky_material as ShaderMaterial if environment.sky else null
	_record[key + "/scene"] = {"earth": earth.global_transform, "sun_basis": sun.global_basis,
			"sun_energy": sun.light_energy, "sky_rotation": environment.sky_rotation,
			"sky_sun": sky_material.get_shader_parameter("sun_direction") if sky_material else null,
			"sky_observer": sky_material.get_shader_parameter("observer_km") if sky_material else null,
			"ecef_to_world": orbit.ecef_to_world, "eci_to_world": orbit.get_eci_to_world()}
	var materials := {}
	for child in earth.get_children():
		var geometry := child as GeometryInstance3D
		if geometry and geometry.material_override is ShaderMaterial:
			var material := geometry.material_override as ShaderMaterial
			var values := {}
			for name in EARTH_UNIFORMS:
				values[name] = material.get_shader_parameter(name)
			materials[child.name] = values
	_record[key + "/materials"] = materials
