class_name StationHatches
extends RefCounted
## Écoutilles, trappes verrouillées et rideaux de la station (composant de Station, scripts/station.gd, qui garde les
## signaux hatch_moving, hatch_changed, curtain_changed et les réglages exportés).
## - Écoutilles : objets Interactif_* d'extras type « ecoutille » (ouvertes au repos) ou « trappe » (verrouillées :
##   sas, nadir ; fermées au repos), charnière extras.charniere, angles et durée lus dans l'animation
##   Fermeture_Ecoutilles (début = ouverte, fin = fermée). Au démarrage, les écoutilles ouvrables sont fermées
##   (Station.start_hatches_closed, sauf start_open_hatches). Volant de verrouillage (extras.volant, volant_tours) :
##   déverrouillé quand elle est ouverte ; ouvrir = déverrouiller puis pousser, fermer = tirer puis verrouiller.
##   Chaque écoutille est pilotée par son Tween (mêmes angles et durée que l'animation).
## - Rideaux : objets d'extras type « rideau » (Habitation_Rideau_WC, Habitation_Rideau_Douche) : forme de base =
##   ouvert (regroupé), clé de forme extras.forme_fermee (« Ferme ») = fermé ; fermés au démarrage
##   (Station.start_curtains_closed). Sans collision (on passe à travers) ; une zone de clic (Area3D sur
##   Station.CURTAIN_LAYER) couvre le tissu et suit son mouvement.

## Écoutille ou trappe : charnière, angles ouvert / fermé, état atteint et visé, volant.
class Hatch:
	var node: Node
	var hinge: Node3D
	var ouvrable := false
	var is_open := false
	## État visé (celui vers lequel elle bouge, ou son état au repos).
	var target := false
	var open := Quaternion.IDENTITY
	var closed := Quaternion.IDENTITY
	var duration := 0.0
	var tween: Tween
	var wheel: Node3D
	var wheel_rest := Quaternion.IDENTITY
	var wheel_unlocked := 0.0
	var wheel_angle := 0.0


## Rideau : clé de forme, poids courant et visé, zone de clic (boîtes ouvert / fermé).
class Curtain:
	var node: MeshInstance3D
	var blend := -1
	var weight := 0.0
	var target := false
	var tween: Tween
	var area: Area3D
	var shape: CollisionShape3D
	var open_box := AABB()
	var closed_box := AABB()

var _station: Station
var _anim: StationAnim
## id -> Hatch.
var _hatches := {}
## id -> Curtain.
var _curtains := {}


func _init(station: Station, anim: StationAnim) -> void:
	_station = station
	_anim = anim
	_collect_hatches()
	_collect_curtains()


# --- Écoutilles ---------------------------------------------------------------------------------------------------

func hatch_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_hatches.keys())
	return ids


func is_hatch_open(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].is_open


func is_hatch_openable(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].ouvrable


## État visé d'une écoutille (celui vers lequel elle bouge, ou son état au repos).
func is_hatch_opening(id: String) -> bool:
	return _hatches.has(id) and _hatches[id].target


## Charnière de l'écoutille (sondes), ou null.
func hatch_hinge(id: String) -> Node3D:
	return _hatches[id].hinge if _hatches.has(id) else null


## Ouvre ou ferme une écoutille (Tween, durée de l'animation Blender). Faux si elle est verrouillée ou inconnue.
func set_hatch_open(id: String, open: bool) -> bool:
	if not is_hatch_openable(id):
		return false
	var hatch: Hatch = _hatches[id]
	# État visé (et non l'état atteint) : une demande inverse en cours de mouvement repart de la position actuelle.
	if hatch.target == open:
		return true
	hatch.target = open
	_station.hatch_moving.emit(id, open)
	_tween_hatch(hatch, open, func() -> void:
		hatch.is_open = open
		_station.hatch_changed.emit(id, open))
	return true


## Ouvre l'écoutille fermée (ou qui se ferme), ferme l'écoutille ouverte (ou qui s'ouvre).
func toggle_hatch(id: String) -> bool:
	return set_hatch_open(id, not is_hatch_opening(id))


## Toutes les écoutilles ouvrables, chacune par son Tween.
func set_all_hatches_open(open: bool) -> void:
	for id: String in _hatches:
		if _hatches[id].ouvrable:
			set_hatch_open(id, open)


## Identifiant de l'écoutille ouvrable à laquelle appartient node (la porte, ou un de ses descendants comme son corps
## de collision), "" sinon.
func hatch_id_for(node: Node) -> String:
	while node and node != _station:
		for id: String in _hatches:
			if _hatches[id].node == node:
				return id if _hatches[id].ouvrable else ""
		node = node.get_parent()
	return ""


func _collect_hatches() -> void:
	var hatch_anim := _anim.animation(Station.ANIM_HATCHES)
	for node in _station.find_children("Interactif_*", "", true, false):
		# Les corps de collision des portes portent le même nom que leur porte.
		if node is CollisionObject3D:
			continue
		var extras: Dictionary = node.get_meta("extras", {})
		var type := String(extras.get("type", ""))
		if type != "ecoutille" and type != "trappe":
			continue
		var hatch := Hatch.new()
		hatch.node = node
		hatch.hinge = _station.get_node_or_null(NodePath(String(extras.get("charniere", "")))) as Node3D \
				if extras.has("charniere") else null
		hatch.ouvrable = extras.get("ouvrable", hatch.hinge != null) and hatch.hinge != null
		# Au repos : écoutilles ouvertes ; trappes verrouillées (sas, nadir) fermées.
		hatch.is_open = type == "ecoutille"
		var id := String(extras.get("id", node.name))
		if hatch.hinge and hatch_anim:
			# Début de Fermeture_Ecoutilles = ouverte.
			var range := _anim.hinge_range(hatch_anim, hatch.hinge)
			hatch.ouvrable = hatch.ouvrable and range.animated
			hatch.open = range.start
			hatch.closed = range.end
			hatch.duration = range.duration
			if _station.start_hatches_closed and hatch.ouvrable and hatch.is_open and not id in _station.start_open_hatches:
				hatch.hinge.quaternion = hatch.closed
				hatch.is_open = false
		hatch.target = hatch.is_open
		_collect_wheel(hatch, node, extras)
		Station.fit_door_collision(node)
		_hatches[id] = hatch


## Volant de verrouillage de l'écoutille (pivot extras.volant, enfant de la porte ; axe Z Blender = Y local dans
## Godot) : déverrouillé (volant_tours tours) quand elle est ouverte, verrouillé (0) fermée.
func _collect_wheel(hatch: Hatch, door: Node, extras: Dictionary) -> void:
	var wheel_name := String(extras.get("volant", ""))
	var wheel := door.find_child(wheel_name, true, false) as Node3D if wheel_name != "" else null
	if wheel == null:
		return
	hatch.wheel = wheel
	hatch.wheel_rest = wheel.quaternion
	hatch.wheel_unlocked = float(extras.get("volant_tours", 1.0)) * TAU
	_set_wheel_angle(hatch, hatch.wheel_unlocked if hatch.is_open else 0.0)


static func _set_wheel_angle(hatch: Hatch, angle: float) -> void:
	hatch.wheel_angle = angle
	hatch.wheel.quaternion = hatch.wheel_rest * Quaternion(Vector3.UP, angle)


## Écoutille vers open : sans volant, la charnière seule ; avec volant, déverrouillage puis ouverture, ou fermeture
## puis verrouillage (le volant repart de son angle courant).
func _tween_hatch(hatch: Hatch, open: bool, done: Callable) -> void:
	var target := hatch.open if open else hatch.closed
	if hatch.tween:
		hatch.tween.kill()
	var finish := func() -> void:
		hatch.tween = null
		done.call()
	if hatch.wheel == null:
		hatch.tween = _anim.tween_hinge(hatch.hinge, target, hatch.duration, finish)
		return
	var hinge := hatch.hinge
	var start := hinge.quaternion
	var wheel_from := hatch.wheel_angle
	var wheel_to := hatch.wheel_unlocked if open else 0.0
	var wheel_s := _station.hatch_wheel_s * absf(wheel_to - wheel_from) / maxf(hatch.wheel_unlocked, 1e-3)
	var turn := func(angle: float) -> void: _set_wheel_angle(hatch, angle)
	var swing := func(w: float) -> void: hinge.quaternion = start.slerp(target, w)
	hatch.tween = _station.create_tween()
	if open and wheel_s > 0.0:
		hatch.tween.tween_method(turn, wheel_from, wheel_to, wheel_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hatch.tween.tween_method(swing, 0.0, 1.0, hatch.duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not open and wheel_s > 0.0:
		hatch.tween.tween_method(turn, wheel_from, wheel_to, wheel_s).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hatch.tween.tween_callback(finish)


# --- Rideaux --------------------------------------------------------------------------------------------------------

func curtain_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_curtains.keys())
	return ids


## État visé d'un rideau (celui vers lequel il bouge, ou son état au repos).
func is_curtain_closing(id: String) -> bool:
	return _curtains.has(id) and _curtains[id].target


func set_curtain_closed(id: String, closed: bool) -> bool:
	if not _curtains.has(id):
		return false
	var curtain: Curtain = _curtains[id]
	if curtain.target == closed:
		return true
	curtain.target = closed
	if curtain.tween:
		curtain.tween.kill()
	var from := curtain.weight
	var to := 1.0 if closed else 0.0
	curtain.tween = _station.create_tween()
	curtain.tween.tween_method(func(w: float) -> void: _set_curtain_weight(curtain, w), from, to,
			_station.curtain_duration_s * absf(to - from)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	curtain.tween.tween_callback(func() -> void:
		curtain.tween = null
		_station.curtain_changed.emit(id, closed))
	return true


func toggle_curtain(id: String) -> bool:
	return set_curtain_closed(id, not is_curtain_closing(id))


## Identifiant du rideau auquel appartient node (sa zone de clic), "" sinon.
func curtain_id_for(node: Node) -> String:
	for id: String in _curtains:
		if _curtains[id].area == node:
			return id
	return ""


static func _set_curtain_weight(curtain: Curtain, w: float) -> void:
	curtain.weight = w
	curtain.node.set_blend_shape_value(curtain.blend, w)
	var center := curtain.open_box.get_center().lerp(curtain.closed_box.get_center(), w)
	(curtain.shape.shape as BoxShape3D).size = curtain.open_box.size.lerp(curtain.closed_box.size, w)
	curtain.shape.position = center


func _collect_curtains() -> void:
	for node: MeshInstance3D in _station.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = node.get_meta("extras", {})
		if String(extras.get("type", "")) != "rideau" or node.mesh == null:
			continue
		var blend := node.find_blend_shape_by_name(StringName(String(extras.get("forme_fermee", "Ferme"))))
		if blend < 0:
			push_error("Station : rideau %s sans clé de forme fermée" % node.name)
			continue
		var boxes := _curtain_boxes(node.mesh, blend)
		var curtain := Curtain.new()
		curtain.node = node
		curtain.blend = blend
		curtain.target = _station.start_curtains_closed
		curtain.open_box = boxes[0]
		curtain.closed_box = boxes[1]
		curtain.area = Area3D.new()
		curtain.area.name = "Zone_Clic"
		curtain.area.collision_layer = Station.CURTAIN_LAYER
		curtain.area.collision_mask = 0
		curtain.area.monitoring = false
		curtain.shape = CollisionShape3D.new()
		curtain.shape.shape = BoxShape3D.new()
		curtain.area.add_child(curtain.shape)
		node.add_child(curtain.area)
		_set_curtain_weight(curtain, 1.0 if curtain.target else 0.0)
		_curtains[String(extras.get("id", node.name))] = curtain


## Boîtes (repère du maillage) du tissu ouvert et fermé : sommets de la surface du rideau (matériau « Rideau »), de la
## forme de base et de la clé de forme ; épaissies à CURTAIN_PICK_DEPTH pour le clic.
static func _curtain_boxes(mesh: Mesh, blend: int) -> Array[AABB]:
	var open_box := mesh.get_aabb()
	var closed_box := open_box
	var array_mesh := mesh as ArrayMesh
	if array_mesh:
		for s in array_mesh.get_surface_count():
			var material := array_mesh.surface_get_material(s)
			if material == null or not material.resource_name.contains("Rideau"):
				continue
			var base: PackedVector3Array = array_mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var shapes := array_mesh.surface_get_blend_shape_arrays(s)
			if base.is_empty() or shapes.size() <= blend:
				break
			# Positions absolues de la forme fermée (l'import glTF ajoute les décalages à la base).
			var target: PackedVector3Array = shapes[blend][Mesh.ARRAY_VERTEX]
			open_box = _points_aabb(base)
			closed_box = _points_aabb(target) if target.size() == base.size() else open_box
			break
	var result: Array[AABB] = []
	for box: AABB in [open_box, closed_box]:
		# Épaisseur du tissu (plus petite dimension) portée à CURTAIN_PICK_DEPTH, pour viser facilement.
		var axis := box.get_shortest_axis_index()
		var grow := Vector3.ZERO
		grow[axis] = maxf(0.0, Station.CURTAIN_PICK_DEPTH - box.size[axis]) / 2.0
		result.append(AABB(box.position - grow, box.size + 2.0 * grow))
	return result


static func _points_aabb(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box
