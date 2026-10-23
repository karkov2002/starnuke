class_name PressureGauges
extends Node
## Témoins de pression des modules (nœud PressureGauges de scenes/orbit_view.tscn) : dans chaque module, près de son
## écoutille d'entrée, un petit afficheur mural construit ici (boîtier, écran, valeur en bar, voyant, plaque
## « CABIN PRESSURE »), enfant de la station (Temoin_Pression_<module>). Pression : StationAtmosphere. Voyant et chiffres : vert au-dessus de
## warn_pressure, orange au-dessous, rouge clignotant sous danger_pressure (on y perd connaissance sans combinaison :
## AirlockHazard.death_pressure). Valeurs et marquages du matériel, sans langue (hors fichiers de langue). Le sas a
## déjà le manomètre de sa valve. Emplacements : StationLayout.GAUGES (coordonnées Blender).

const GAUGES := StationLayout.GAUGES
const GREEN := Color(0.3, 1.0, 0.45)
const AMBER := Color(1.0, 0.68, 0.1)
const RED := Color(1.0, 0.16, 0.1)

@export var station_path: NodePath = ^"../Station/StationSpatiale"
@export var atmosphere_path: NodePath = ^"../StationAir"
## Pression d'un module plein (bar) : l'affichage vaut pression relative × full_bar.
@export var full_bar := 1.0
@export var warn_pressure := 0.9
@export var danger_pressure := 0.3
@export var blink_s := 0.6
## Taille de l'afficheur (1 : boîtier de 17 × 11 cm ; agrandi pour se lire à travers le module).
@export var gauge_scale := 2.0
## Émission du voyant allumé.
@export var led_energy := 4.0

var _atmosphere: StationAtmosphere
## Module → {label, led (StandardMaterial3D), shown (texte affiché)}.
var _gauges := {}
var _time := 0.0


func _ready() -> void:
	var station := get_node_or_null(station_path) as Node3D
	_atmosphere = get_node_or_null(atmosphere_path) as StationAtmosphere
	if station == null or _atmosphere == null:
		set_process(false)
		return
	for zone: String in GAUGES:
		_gauges[zone] = _build(station, zone, GAUGES[zone][0], GAUGES[zone][1])


## Témoins rafraîchis à refresh_hz (les pressions varient lentement) ; texte, couleur et témoin ne sont réécrits
## que s'ils changent.
@export var refresh_hz := 10.0
var _since := INF


func _process(delta: float) -> void:
	_time = fmod(_time + delta, blink_s)
	_since += delta
	if _since < 1.0 / refresh_hz:
		return
	_since = 0.0
	var lit := _time < blink_s * 0.5
	for zone: String in _gauges:
		var gauge: Dictionary = _gauges[zone]
		var pressure := _atmosphere.pressure_of(zone)
		var text := "%.2f bar" % (pressure * full_bar)
		var color := GREEN if pressure >= warn_pressure else (AMBER if pressure >= danger_pressure else RED)
		if text != gauge.shown:
			gauge.shown = text
			(gauge.label as Label3D).text = text
		var energy := led_energy if color != RED or lit else 0.0
		if color != gauge.get("color", Color.TRANSPARENT) or energy != gauge.get("energy", -1.0):
			gauge.color = color
			gauge.energy = energy
			(gauge.label as Label3D).modulate = color
			var led: StandardMaterial3D = gauge.led
			led.albedo_color = color
			led.emission = color
			led.emission_energy_multiplier = energy


## Afficheur posé sur la paroi (position et normale en coordonnées Blender), face vers l'intérieur, haut vers le
## plafond du modèle (+Z Blender) projeté sur la paroi.
func _build(station: Node3D, zone: String, blender_position: Vector3, blender_normal: Vector3) -> Dictionary:
	var normal := StationLayout.to_godot(blender_normal).normalized()
	var up := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	if up.length() < 0.1:
		up = Vector3.RIGHT
	var root := Node3D.new()
	root.name = "Temoin_Pression_" + zone
	station.add_child(root)
	root.transform = Transform3D(Basis(up.cross(normal), up, normal).scaled_local(Vector3.ONE * gauge_scale),
			StationLayout.to_godot(blender_position) + normal * 0.002)
	var housing := _material(Color(0.16, 0.17, 0.18), 0.6, 0.45)
	_box(root, Vector3(0.17, 0.11, 0.03), Vector3(0, 0, 0.015), housing)
	_box(root, Vector3(0.136, 0.064, 0.004), Vector3(0, 0.012, 0.031), _material(Color(0.05, 0.05, 0.055), 0.3, 0.5))
	_box(root, Vector3(0.126, 0.054, 0.002), Vector3(0, 0.012, 0.0335), _material(Color(0.005, 0.008, 0.006), 0.0, 0.15))
	for x in [-0.075, 0.075]:
		for y in [-0.045, 0.045]:
			_box(root, Vector3(0.008, 0.008, 0.003), Vector3(x, y, 0.0315), _material(Color(0.55, 0.56, 0.58), 1.0, 0.3))
	var label := _label(root, "1.00 bar", 64, Vector3(0, 0.012, 0.0348), GREEN)
	_label(root, "CABIN PRESSURE", 22, Vector3(-0.012, -0.034, 0.0305), Color(0.75, 0.76, 0.78))
	var led := _material(GREEN, 0.0, 0.3)
	led.emission_enabled = true
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.006
	sphere.height = 0.012
	bulb.mesh = sphere
	bulb.material_override = led
	bulb.position = Vector3(0.062, -0.034, 0.031)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)
	return {"label": label, "led": led, "shown": ""}


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = position
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(box)


func _label(parent: Node3D, text: String, font_size: int, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0004
	label.outline_size = 0
	label.modulate = color
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.position = position
	parent.add_child(label)
	return label
