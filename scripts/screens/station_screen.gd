class_name StationScreen
extends RefCounted
## Dalle d'un écran du modèle (station : Interactif_Ecran_*, ou l'écran de la tablette) : la surface du matériau
## d'écran, mesurée dans le repère du maillage (coin haut gauche de l'image, côté vers la droite, côté vers le bas),
## et tout ce que les écrans partagent : SubViewport aux proportions de la dalle, matériau d'affichage posé sur la
## surface, point de l'écran sous le curseur (rayon de la caméra contre le plan de la dalle), cadrage « assis » face à
## la dalle, luminosité envoyée au shader seulement quand elle change. Utilisé par PilotConsole, CommConsole,
## TvConsole, NukeReportPanel, TechScreens et Tablet.
##
## Mesure : par les UV de la surface (coins (0, 0), (1, 0), (0, 1) ; écrans du modèle exportés avec des UV de 0 à 1),
## ou, pour l'écran du poste de pilotage (UV inexploitables), par la boîte des faces tournées vers une normale.

const NONE := Vector2(-1, -1)
const TECH_SHADER := preload("res://shaders/tech_screen.gdshader")

var mesh_instance: MeshInstance3D
## Surface de la dalle dans le maillage ; -1 : tout le maillage (material_override).
var surface := -1
## Repère du maillage.
var top_left := Vector3.ZERO
var axis_u := Vector3.ZERO
var axis_v := Vector3.ZERO
## Matériau d'affichage posé par apply_shader, et dernière luminosité envoyée.
var material: ShaderMaterial
var _energy_applied := -1.0


## Écran node_name du modèle (descendant de root), mesuré par les UV de la surface de son matériau d'écran
## (extras.materiau_ecran) ; null s'il manque ou si la dalle n'est pas mesurable.
static func find(root: Node, node_name: String) -> StationScreen:
	var mesh := root.find_child(node_name, true, false) as MeshInstance3D if root else null
	if mesh == null or mesh.mesh == null:
		return null
	var screen := StationScreen.new()
	screen.mesh_instance = mesh
	var wanted := String((mesh.get_meta("extras", {}) as Dictionary).get("materiau_ecran", ""))
	var s := surface_of(mesh, wanted)
	return screen if s >= 0 and screen.measure_by_uv(s) else null


## Écran réduit à un maillage entier (une seule surface : tablette), mesuré par ses UV ; null si non mesurable.
static func of_mesh(mesh: MeshInstance3D) -> StationScreen:
	if mesh == null or mesh.mesh == null:
		return null
	var screen := StationScreen.new()
	screen.mesh_instance = mesh
	return screen if screen.measure_by_uv(0) else null


## Indice de la surface du maillage dont le matériau porte ce nom, -1 sinon.
static func surface_of(mesh: MeshInstance3D, material_name: String) -> int:
	for s in mesh.mesh.get_surface_count():
		var candidate := mesh.mesh.surface_get_material(s)
		if candidate and candidate.resource_name == material_name:
			return s
	return -1


## Rectangle de la dalle d'après les UV de la surface s : coin (0, 0) en haut à gauche de l'image, (1, 0) en haut à
## droite, (0, 1) en bas à gauche. surface vaut s ensuite (−1 pour un maillage à une seule surface : override entier).
func measure_by_uv(s: int) -> bool:
	var arrays := mesh_instance.mesh.surface_get_arrays(s)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return false
	var corners := {}
	for k in vertices.size():
		corners[Vector2i(roundi(uvs[k].x), roundi(uvs[k].y))] = vertices[k]
	if not (corners.has(Vector2i(0, 0)) and corners.has(Vector2i(1, 0)) and corners.has(Vector2i(0, 1))):
		return false
	top_left = corners[Vector2i(0, 0)]
	axis_u = corners[Vector2i(1, 0)] - top_left
	axis_v = corners[Vector2i(0, 1)] - top_left
	surface = s if mesh_instance.mesh.get_surface_count() > 1 else -1
	return true


## Rectangle de la dalle : boîte des sommets de la surface du matériau material_name dont la normale est normal (la
## face tournée vers l'observateur), dans le plan perpendiculaire à normal, haut vers +Y du maillage et droite de
## l'image à droite d'un observateur qui regarde la dalle. Poste de pilotage : normale −X.
func measure_by_normal(material_name: String, normal: Vector3) -> bool:
	var s := surface_of(mesh_instance, material_name)
	if s < 0:
		return false
	var arrays := mesh_instance.mesh.surface_get_arrays(s)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for k in vertices.size():
		if normals[k].dot(normal) > 0.99:
			lo = lo.min(vertices[k])
			hi = hi.max(vertices[k])
	if lo == Vector3.INF:
		return false
	var right := Vector3.UP.cross(normal).normalized()
	var extent := hi - lo
	var center := (lo + hi) * 0.5
	var half_u := right * (absf(extent.dot(right)) * 0.5)
	var half_v := Vector3.DOWN * (extent.y * 0.5)
	top_left = center - half_u - half_v
	axis_u = half_u * 2.0
	axis_v = half_v * 2.0
	surface = s
	return true


## Rapport largeur / hauteur de la dalle.
func aspect() -> float:
	return axis_u.length() / maxf(axis_v.length(), 1e-6)


## SubViewport 2D aux proportions de la dalle, de hauteur height (pixels), nommé « Screen », rendu à chaque image.
func make_viewport(height: int, embed_subwindows := false) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Screen"
	viewport.size = Vector2i(roundi(height * aspect()), height)
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = embed_subwindows
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport


## Matériau d'affichage (shader, texture dans screen_texture, autres paramètres) posé sur la surface de la dalle (ou
## sur tout le maillage) ; gardé dans material pour set_energy.
func apply_shader(shader: Shader, texture: Texture2D, params := {}) -> ShaderMaterial:
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("screen_texture", texture)
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	if surface >= 0:
		mesh_instance.set_surface_override_material(surface, material)
	else:
		mesh_instance.material_override = material
	_energy_applied = float(params.get("energy", -1.0))
	return material


## Luminosité (paramètre energy du shader), envoyée seulement si elle change.
func set_energy(value: float) -> void:
	if material == null or is_equal_approx(value, _energy_applied):
		return
	_energy_applied = value
	material.set_shader_parameter("energy", value)


## Émission d'origine du matériau de la dalle (1 sans émission) : base de la luminosité des écrans du poste.
func base_emission() -> float:
	if surface < 0:
		return 1.0
	var original := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
	return original.emission_energy_multiplier if original and original.emission_enabled else 1.0


## Point de l'écran (0–1, origine en haut à gauche) sous la position screen_pos de la vue de camera, NONE hors de la
## dalle ou au-delà de max_distance (m) de la caméra.
func uv_at(camera: Camera3D, screen_pos: Vector2, max_distance := INF) -> Vector2:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var to_world := mesh_instance.global_transform
	var corner := to_world * top_left
	var u := to_world.basis * axis_u
	var v := to_world.basis * axis_v
	var normal := u.cross(v).normalized()
	var facing := direction.dot(normal)
	if absf(facing) < 1e-4:
		return NONE
	var distance := (corner - origin).dot(normal) / facing
	if distance <= 0.0 or distance > max_distance:
		return NONE
	var offset := origin + direction * distance - corner
	var uv := Vector2(offset.dot(u) / u.length_squared(), offset.dot(v) / v.length_squared())
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return NONE
	return uv


## Centre de la dalle (coordonnées globales).
func center_global() -> Vector3:
	return mesh_instance.global_transform * (top_left + (axis_u + axis_v) * 0.5)


## Distance (m) d'un point global au centre de la dalle (pas au pivot du maillage, qui peut être à l'origine du
## modèle : les pivots ne sont jamais appliqués à l'export).
func distance_to(point: Vector3) -> float:
	return center_global().distance_to(point)


## Cadrage « assis » : œil face au centre de la dalle, à la distance où elle occupe fill de la vue de camera (en
## hauteur ou en largeur selon les proportions de la vue, view_aspect), regard vers la dalle, haut de l'image en
## haut. Rend {eye : position globale, look : Basis globale de la caméra}.
func seat_pose(camera: Camera3D, view_aspect: float, fill: float) -> Dictionary:
	var to_world := mesh_instance.global_transform
	var u := to_world.basis * axis_u
	var v := to_world.basis * axis_v
	var toward_viewer := v.cross(u).normalized()
	var half_tan := tan(deg_to_rad(camera.fov) * 0.5)
	var distance := maxf(v.length() / (2.0 * half_tan * fill), u.length() / (2.0 * half_tan * view_aspect * fill))
	return {"eye": center_global() + toward_viewer * distance, "look": Basis.looking_at(-toward_viewer, -v.normalized())}
