class_name NukeMushroomMesh
extends RefCounted
## Rendu par maillage du champignon (composant de NukeMushroom, conservé pour comparaison avec le rendu
## volumétrique) : le nuage (nœud Cloud de nuke/nuke_mushroom.tscn) et le nuage de base (BaseSurge, créé ici), deux
## maillages de révolution fixes dont les positions sont posées par le vertex shader (nuke/shaders/nuke_mushroom.gdshader)
## d'après un profil (méridienne de PROFILE_POINTS points, tige puis chapeau) recalculé à chaque image.
## Nuage de base (explosions basses) : dôme de poussière au pied, même shader et même couleur, qui s'étend avec
## l'onde de choc (surge_shock_ratio × rayon du front) et s'estompe quand la tige se dissout ; aussi utilisé par le
## rendu volumétrique (rayon, hauteur, opacité rendus par update_surge).

const PROFILE_POINTS := 48
const STEM_POINTS := 16
## Maillage : anneaux (le profil est interpolé entre ses points) × segments autour de l'axe.
const RINGS := 96
const SEGMENTS := 128

static var _mesh: ArrayMesh

var cloud: MeshInstance3D
var surge: MeshInstance3D
var material: ShaderMaterial
var surge_material: ShaderMaterial
var _m: NukeMushroom


## Prend le nœud Cloud du champignon m (son matériau est dupliqué) et crée BaseSurge à côté.
func _init(m: NukeMushroom, cloud_node: MeshInstance3D) -> void:
	_m = m
	cloud = cloud_node
	material = (cloud.material_override as ShaderMaterial).duplicate() as ShaderMaterial
	cloud.material_override = material
	cloud.mesh = _get_mesh()
	# Uniforms constants, posés une fois.
	material.set_shader_parameter("stem_fraction", float(STEM_POINTS - 1) / float(PROFILE_POINTS - 1))
	material.set_shader_parameter("ground_fade", 0.04)
	material.set_shader_parameter("drift_top", NukeMushroomDrift.TOP)
	surge_material = material.duplicate() as ShaderMaterial
	surge_material.set_shader_parameter("stem_fraction", 0.0)
	surge_material.set_shader_parameter("edge_erosion", 0.6)
	surge = MeshInstance3D.new()
	surge.name = "BaseSurge"
	surge.mesh = cloud.mesh
	surge.material_override = surge_material
	surge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surge.extra_cull_margin = cloud.extra_cull_margin
	m.add_child(surge)


## Nuage : profil, mouvements, couleurs, repère de la planète et soleil (sun_dir seulement si has_sun).
func update(s: NukeMushroomShape, to_planet: Transform3D, sun_dir: Vector3, has_sun: bool) -> void:
	material.set_shader_parameter("opacity", s.fade)
	material.set_shader_parameter("profile", _profile(s.yc, 0.5 * s.hc, s.rc, s.rs, s.y_neck, s.h))
	material.set_shader_parameter("ring", Vector2(0.55 * s.rc, s.yc))
	material.set_shader_parameter("roll_angle", s.roll_angle(_m))
	material.set_shader_parameter("rise_offset", s.rise_offset(_m))
	material.set_shader_parameter("boil", _m.boil_rate * s.t)
	material.set_shader_parameter("erosion", s.erosion)
	material.set_shader_parameter("albedo", s.albedo_vec())
	material.set_shader_parameter("glow", s.glow_vec())
	material.set_shader_parameter("local_to_planet_km", Projection(to_planet))
	if has_sun:
		material.set_shader_parameter("sun_dir_planet", sun_dir)


## Nuage de base : dôme de poussière bas, rayon = surge_shock_ratio × front de choc, qui s'estompe avec l'érosion de
## la tige. Seulement pour les explosions basses. Retourne (rayon, hauteur, opacité), nuls sans nuage de base ; sert
## au rendu volumétrique comme au maillage (apply_surge).
func surge_state(s: NukeMushroomShape, yield_kt: float, steam: float) -> Vector3:
	var radius := lerpf(_m.surge_shock_ratio, _m.steam_surge_ratio, steam) \
			* NukeScaling.shock_front_radius_km(yield_kt, s.t) / s.top_km
	var fade := lerpf(_m.surge_opacity, _m.steam_surge_opacity, steam) * smoothstep(0.0, 0.02, s.a) \
			* (1.0 - smoothstep(0.0, 0.7, s.erosion))
	if not (s.yb < 2.0 * s.rf and radius > 0.002 and fade > 0.005):
		return Vector3.ZERO
	return Vector3(radius, _m.surge_aspect * radius, fade)


## Maillage du nuage de base (rendu par maillage) : profil, mouvements et couleur du champignon.
func apply_surge(s: NukeMushroomShape, state: Vector3, to_planet: Transform3D, sun_dir: Vector3) -> void:
	surge.visible = state != Vector3.ZERO
	if not surge.visible:
		return
	var radius := state.x
	var height := state.y
	var fade := state.z
	var points := PackedVector2Array()
	points.resize(PROFILE_POINTS)
	for i in PROFILE_POINTS:
		var phi := PI * 0.5 * float(i) / float(PROFILE_POINTS - 1)
		points[i] = Vector2(radius * pow(maxf(cos(phi), 0.0), 0.35), height * sin(phi))
	var m := surge_material
	m.set_shader_parameter("profile", points)
	m.set_shader_parameter("ring", Vector2(0.6 * radius, 0.4 * height))
	m.set_shader_parameter("roll_angle", -0.5 * material.get_shader_parameter("roll_angle"))
	m.set_shader_parameter("boil", material.get_shader_parameter("boil"))
	m.set_shader_parameter("opacity", fade)
	m.set_shader_parameter("ground_fade", height)
	m.set_shader_parameter("albedo", s.albedo_vec())
	m.set_shader_parameter("glow", s.glow_vec() * 0.03)
	m.set_shader_parameter("local_to_planet_km", Projection(to_planet))
	m.set_shader_parameter("sun_dir_planet", sun_dir)


## Dérive au vent (profil vertical) des deux maillages.
func set_drift(samples: Variant) -> void:
	material.set_shader_parameter("drift_profile", samples)
	surge_material.set_shader_parameter("drift_profile", samples)


## Boîte englobante du nuage.
func set_bounds(aabb: AABB) -> void:
	cloud.custom_aabb = aabb


## Maillages cachés (rendu volumétrique) : plus rien n'est posé sur leurs matériaux tant qu'ils le restent.
func hide() -> void:
	cloud.visible = false
	surge.visible = false


## Méridienne : tige (STEM_POINTS points, du sol au col, pied et col évasés) puis chapeau (dessous, bord arrondi,
## dessus jusqu'à l'axe). Ordre de bas en haut le long de la surface extérieure : la normale (t.y, −t.x) est sortante.
func _profile(yc: float, b: float, rc: float, rs: float, y_neck: float, h: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(PROFILE_POINTS)
	var r_neck := minf(rs * _m.neck_flare, rc)
	var y0 := minf(0.0, y_neck)
	for i in STEM_POINTS:
		var s := float(i) / float(STEM_POINTS - 1)
		var y := lerpf(y0, y_neck, s)
		var r := rs * (1.0 + _m.base_flare * exp(-(y - y0) / maxf(_m.base_flare_height * h, 1e-4)))
		points[i] = Vector2(lerpf(r, r_neck, smoothstep(0.7, 1.0, s)), y)
	var cap_points := PROFILE_POINTS - STEM_POINTS
	var under := (yc - y_neck) / maxf(b, 1e-6)
	for k in cap_points:
		var phi := -PI * 0.5 + PI * float(k + 1) / float(cap_points)
		var c := maxf(cos(phi), 0.0)
		if phi < 0.0:
			points[STEM_POINTS + k] = Vector2(r_neck + (rc - r_neck) * pow(c, _m.cap_under_exponent),
					yc + b * under * sin(phi))
		else:
			points[STEM_POINTS + k] = Vector2(rc * pow(c, _m.cap_top_exponent), yc + b * sin(phi))
	return points


## Maillage de révolution fixe : RINGS anneaux de SEGMENTS + 1 sommets (UV.x = angle, UV.y = position sur le profil,
## interpolé entre ses points) ; les positions sont posées par le vertex shader. Faces avant dans le sens horaire
## (convention Godot).
static func _get_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in RINGS:
		for j in SEGMENTS + 1:
			vertices.append(Vector3.ZERO)
			normals.append(Vector3.UP)
			uvs.append(Vector2(float(j) / SEGMENTS, float(i) / (RINGS - 1)))
	for i in RINGS - 1:
		for j in SEGMENTS:
			var v := i * (SEGMENTS + 1) + j
			var above := v + SEGMENTS + 1
			indices.append_array([v, v + 1, above, v + 1, above + 1, above])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh.custom_aabb = AABB(Vector3(-1.2, -0.3, -1.2), Vector3(2.4, 1.6, 2.4))
	return _mesh
