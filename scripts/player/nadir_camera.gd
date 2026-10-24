class_name NadirCamera
extends SubViewport
## Vue au nadir de la station (onglet Photographie de la tablette, scripts/tablet.gd, qui la crée) : SubViewport qui
## partage le monde de la scène (Terre, nuages, atmosphère), caméra à offset_m sous la caméra de la vue (la Terre est
## posée sous elle : centre de l'image = point survolé, Orbit.get_subsatellite_point), visée vers le centre de la Terre,
## haut de l'image dans le sens du vol ; même réglage d'exposition que la vue (attributs de la caméra
## principale). Rendue seulement quand active (tablette sortie sur l'onglet Photographie), en LIVE_SIZE.
## L'image est affichée par l'écran de la tablette, puis vue par la caméra principale, qui applique déjà le mappage
## tonal (ACES) et le halo : avec ceux de l'environnement, ils l'étaient deux fois (image délavée). La caméra a donc
## une copie de l'environnement en mappage linéaire, sans halo.
## capture_photo() : photo satellite, rendue une fois en PHOTO_SIZE avec le rendu final du jeu (environnement
## d'origine), puis une seconde image au rendu de la vue en direct pour la galerie (sur l'écran, le rendu final
## serait délavé) ; la vue revient ensuite en l'état. Ni l'une ni l'autre n'a la surimpression du HUD (calque
## Hud.OVERLAY_LAYER : cibles, cône de tir, orbite visée), visible seulement dans la vue en direct.
## Anticrénelage : celui des paramètres (GameSettings.apply_anti_aliasing), suivi à chaque changement.
## Mode infrarouge (infrared, choisi sur la tablette) : la caméra ne voit que la Terre thermique (ThermalSurface,
## shaders/earth_thermal.gdshader, cachée hors de ce mode), sur fond noir, sans exposition automatique ; capteur en
## résolution réduite (IR_SCALE : image plus douce), la photo est agrandie en PHOTO_SIZE.

const LIVE_SIZE := Vector2i(600, 470)
const PHOTO_SIZE := Vector2i(1600, 1253)
const IR_SCALE := 0.5

## Champ vertical de la caméra (degrés) et distance sous la station (m, sous la coque).
var fov_deg := 22.0
var offset_m := 15.0
## Rendu de la vue en direct (et suivi de la station).
var active := false:
	set(value):
		active = value
		if not _capturing:
			render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
		_update_thermal()
## Infrarouge thermique (voir l'en-tête) ; visible sinon.
var infrared := false:
	set(value):
		infrared = value
		if not _capturing:
			_apply_mode()

var _camera: Camera3D
var _earth: Node3D
var _world_environment: WorldEnvironment
var _station: Node3D
## Caméra de la vue : la Terre est posée sous elle (EarthSceneDriver), c'est donc d'elle que part la verticale du
## point survolé (Orbit.get_subsatellite_point) ; depuis l'origine de la station, la visée serait décalée de
## ~100 km au sol (10 m de station × 10 000).
var _reference: Node3D
var _capturing := false
## Réglages du mode visible (calques, environnement de la vue en direct, exposition) et du mode infrarouge.
var _visible_mask := 0xFFFFF
var _visible_environment: Environment
var _visible_attributes: CameraAttributes
var _ir_environment: Environment
var _ir_attributes: CameraAttributesPractical
var _thermal: ThermalSurface


## main_camera : caméra de la vue (exposition, calques) ; earth, world_environment : nœuds de la scène.
func _init(main_camera: Camera3D, earth: Node3D, world_environment: WorldEnvironment, fov := 22.0, offset := 15.0) -> void:
	name = "Nadir"
	size = LIVE_SIZE
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	fov_deg = fov
	offset_m = offset
	_earth = earth
	_world_environment = world_environment
	_camera = Camera3D.new()
	_camera.fov = fov
	_camera.near = 0.5
	_camera.far = 3000.0
	_reference = main_camera
	if main_camera:
		_visible_attributes = main_camera.attributes
		_visible_mask = main_camera.cull_mask
	_visible_mask &= ~ThermalSurface.LAYER
	if world_environment and world_environment.environment:
		_visible_environment = world_environment.environment.duplicate() as Environment
		_visible_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_visible_environment.glow_enabled = false
	_ir_environment = Environment.new()
	_ir_environment.background_mode = Environment.BG_COLOR
	_ir_environment.background_color = Color.BLACK
	_ir_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_ir_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_ir_attributes = CameraAttributesPractical.new()
	_ir_attributes.auto_exposure_enabled = false
	_camera.current = true
	add_child(_camera)
	_apply_mode()


func _ready() -> void:
	GameSettings.apply_anti_aliasing(self)
	GameSettings.changed.connect(func() -> void: GameSettings.apply_anti_aliasing(self))


func _process(_delta: float) -> void:
	if not active or _earth == null:
		return
	if _station == null:
		_station = get_tree().get_first_node_in_group(Station.GROUP) as Node3D
	var origin := _reference.global_position if _reference else (_station.global_position if _station else Vector3.ZERO)
	var down := (_earth.global_position - origin).normalized()
	# Haut de l'image : sens du vol (−Z de la station), rendu perpendiculaire à la visée.
	var ahead := -_station.global_basis.z if _station else Vector3.FORWARD
	ahead = (ahead - down * ahead.dot(down)).normalized()
	_camera.global_transform = Transform3D(Basis.looking_at(down, ahead), origin + down * offset_m)


## Calques, environnement, exposition et taille de la vue en direct selon le mode (visible ou infrarouge).
func _apply_mode() -> void:
	_camera.cull_mask = ThermalSurface.LAYER if infrared else _visible_mask
	_camera.environment = _ir_environment if infrared else _visible_environment
	_camera.attributes = _ir_attributes if infrared else _visible_attributes
	size = _live_size()
	_update_thermal()


func _live_size() -> Vector2i:
	return Vector2i(Vector2(LIVE_SIZE) * IR_SCALE) if infrared else LIVE_SIZE


## Terre thermique dessinée seulement quand la vue infrarouge est rendue (ou en cours de photo).
func _update_thermal() -> void:
	if _thermal == null and _earth:
		_thermal = _earth.get_node_or_null(^"ThermalSurface") as ThermalSurface
	if _thermal:
		_thermal.visible = infrared and (active or _capturing)


## Emprise au sol (km, largeur × hauteur) d'une photo prise à altitude_km : hauteur = 2 h tan(champ / 2), largeur
## selon les proportions de l'image.
func footprint_km(altitude_km: float) -> Vector2:
	var height_km := 2.0 * altitude_km * tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2(height_km * float(PHOTO_SIZE.x) / PHOTO_SIZE.y, height_km)


## Photo satellite : {image : rendu final en PHOTO_SIZE, screen_image : rendu de la vue en direct, deux images plus
## tard (~250 m de vol), infrared : mode de la prise de vue} ; vide si une capture est déjà en cours. En infrarouge,
## l'image est rendue en PHOTO_SIZE × IR_SCALE (capteur) puis agrandie.
func capture_photo() -> Dictionary:
	if _capturing:
		return {}
	_capturing = true
	var shot_infrared := infrared
	_update_thermal()
	var live_mask := _camera.cull_mask
	# Pas de surimpression (cibles, cône de tir, orbite visée) sur une photo : seulement dans la vue en direct.
	_camera.cull_mask = live_mask & ~Hud.OVERLAY_LAYER
	if _world_environment and not shot_infrared:
		_camera.environment = _world_environment.environment
	size = Vector2i(Vector2(PHOTO_SIZE) * IR_SCALE) if shot_infrared else PHOTO_SIZE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Deux images : la première au nouveau format, la seconde lue une fois le rendu terminé.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_texture().get_image()
	if shot_infrared:
		image.resize(PHOTO_SIZE.x, PHOTO_SIZE.y, Image.INTERPOLATE_BILINEAR)
	_camera.environment = _ir_environment if shot_infrared else _visible_environment
	size = _live_size()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var screen_image := get_texture().get_image()
	_camera.cull_mask = live_mask
	_capturing = false
	# Mode changé pendant la prise de vue : appliqué maintenant.
	_apply_mode()
	active = active
	return {"image": image, "screen_image": screen_image, "infrared": shot_infrared}
