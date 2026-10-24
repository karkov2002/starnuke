class_name RepairFrogger
extends RefCounted
## Mini-jeu de réparation des équipements extérieurs (modèle pur, sans dessin : FroggerView le dessine dans le
## panneau de maintenance, EquipmentDisplay le lance et le pilote). Un « Frogger » schématique sur une grille de
## COLS × ROWS cases : la grenouille (une case) part du bas (START_ROW), traverse la route (voitures) puis la rivière
## (troncs, qui la portent ; tomber à l'eau ou sortir de l'écran la tue) et doit entrer dans une des trois baies du
## haut (BAYS). Une mort ramène la grenouille au départ après RESPAWN_S, sans autre pénalité que le temps perdu.
## **Remplir les trois baies répare l'appareil** (state WON) ; **chrono à 0 : échec** (state LOST).
## Difficulté 1 à 3 (celle de la panne, StationEquipment.repair_level) : vitesse des voitures et des troncs et durée
## du chrono (LEVELS, à régler).

enum State { PLAYING, WON, LOST }

const COLS := 20
## Rangées : 0 arrivée (mur et baies), 1–4 rivière, 5 talus, 6–10 route, 11 départ.
const ROWS := 12
const HOME_ROW := 0
const START_ROW := 11
## Première colonne de chaque baie, et sa largeur (cases) ; il suffit que le centre de la grenouille y soit.
const BAYS: Array[int] = [3, 9, 15]
const BAY_WIDTH := 2
## Par difficulté : facteur de vitesse des voies, durée du chrono (s).
const LEVELS := {1: {"speed": 1.0, "time": 90.0}, 2: {"speed": 1.45, "time": 70.0}, 3: {"speed": 2.0, "time": 55.0}}
## Voies : rangée, troncs (sinon voitures), longueur et nombre des objets, vitesse de base (cases/s, + : vers la
## droite). Les objets d'une voie sont régulièrement espacés et reviennent de l'autre côté.
const LANES: Array[Dictionary] = [
	{"row": 1, "log": true, "length": 4, "count": 3, "speed": 1.1},
	{"row": 2, "log": true, "length": 3, "count": 3, "speed": -1.5},
	{"row": 3, "log": true, "length": 5, "count": 2, "speed": 0.9},
	{"row": 4, "log": true, "length": 3, "count": 3, "speed": -1.2},
	{"row": 6, "log": false, "length": 1, "count": 4, "speed": -1.4},
	{"row": 7, "log": false, "length": 2, "count": 3, "speed": 1.0},
	{"row": 8, "log": false, "length": 1, "count": 3, "speed": -2.0},
	{"row": 9, "log": false, "length": 3, "count": 2, "speed": 1.3},
	{"row": 10, "log": false, "length": 1, "count": 4, "speed": -0.9},
]
## Pause (s) après une mort, grenouille clignotante, avant le retour au départ.
const RESPAWN_S := 0.7
## Part de la case occupée par la grenouille pour les collisions avec les voitures (marge de chaque côté).
const FROG_MARGIN := 0.2

var level := 1
var state := State.PLAYING
var time_left := 0.0
## Position de la grenouille : x en cases (bord gauche, réel : portée par les troncs), y = rangée.
var frog := Vector2.ZERO
var bays_filled: Array[bool] = [false, false, false]
## Mort en cours : temps restant avant le retour au départ (0 : vivante).
var dead_s := 0.0
var deaths := 0

var _clock := 0.0
var _speed := 1.0
var _lanes := {}


func _init(difficulty := 1) -> void:
	level = clampi(difficulty, 1, LEVELS.size())
	_speed = float(LEVELS[level].speed)
	time_left = float(LEVELS[level].time)
	for lane in LANES:
		_lanes[int(lane.row)] = lane
	_reset_frog()


## Voie de la rangée row ({} : talus, départ, arrivée).
func lane_at(row: int) -> Dictionary:
	return _lanes.get(row, {})


## Vitesse (cases/s) d'une voie à cette difficulté.
func lane_speed(lane: Dictionary) -> float:
	return float(lane.speed) * _speed


## Objets d'une voie maintenant : Vector2(x du bord gauche, longueur), en cases ; x de −longueur à COLS.
func lane_objects(lane: Dictionary) -> Array[Vector2]:
	var length := float(lane.length)
	var period := COLS + length
	var out: Array[Vector2] = []
	for k in int(lane.count):
		var x := fposmod(_clock * lane_speed(lane) + k * period / int(lane.count) + int(lane.row) * 3.7, period)
		out.append(Vector2(x - length, length))
	return out


## Saut d'une case (flèches) ; sans effet pendant une mort ou la partie finie.
func move(dx: int, dy: int) -> void:
	if state != State.PLAYING or dead_s > 0.0:
		return
	frog.x = clampf(frog.x + dx, 0.0, COLS - 1.0)
	frog.y = clampi(int(frog.y) + dy, HOME_ROW, START_ROW)
	var lane := lane_at(int(frog.y))
	# Hors de la rivière, la grenouille retombe sur la grille.
	if lane.is_empty() or not lane["log"]:
		frog.x = roundf(frog.x)
	if int(frog.y) == HOME_ROW:
		_arrive()


func update(delta: float) -> void:
	if state != State.PLAYING:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.LOST
		return
	_clock += delta
	if dead_s > 0.0:
		dead_s -= delta
		if dead_s <= 0.0:
			dead_s = 0.0
			_reset_frog()
		return
	var lane := lane_at(int(frog.y))
	if lane.is_empty():
		return
	if lane["log"]:
		if not _on_log(lane):
			_die()
			return
		frog.x += lane_speed(lane) * delta
		if frog.x < -0.5 or frog.x > COLS - 0.5:
			_die()
	elif _hit_by_car(lane):
		_die()


func _on_log(lane: Dictionary) -> bool:
	var center := frog.x + 0.5
	for o in lane_objects(lane):
		if center >= o.x and center <= o.x + o.y:
			return true
	return false


func _hit_by_car(lane: Dictionary) -> bool:
	for o in lane_objects(lane):
		if frog.x + 1.0 - FROG_MARGIN > o.x and frog.x + FROG_MARGIN < o.x + o.y:
			return true
	return false


func _arrive() -> void:
	var center := frog.x + 0.5
	for i in BAYS.size():
		if center >= BAYS[i] and center <= BAYS[i] + BAY_WIDTH:
			if bays_filled[i]:
				break
			bays_filled[i] = true
			if not bays_filled.has(false):
				state = State.WON
			else:
				_reset_frog()
			return
	# Contre le mur ou dans une baie déjà prise.
	_die()


func _die() -> void:
	dead_s = RESPAWN_S
	deaths += 1


func _reset_frog() -> void:
	frog = Vector2(floorf(COLS / 2.0), START_ROW)
