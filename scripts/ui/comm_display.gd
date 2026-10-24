class_name CommDisplay
extends Control
## Programme COMM.EXE de l'écran de communication (CommConsole, dans un SubViewport) : interface « MS-DOS années 80 »
## façon Norton Commander, en mode texte : grille de COLS × ROWS caractères d'une police à chasse fixe, couleurs de la
## palette CGA (fond bleu, cadres doubles cyan clair, barre de menu cyan, barre des touches de fonction en bas,
## curseur clignotant). Façade de la radio (RadioComms) :
## - ligne d'état : canal, fréquence et bande, liaison (barre de signal, station au sol ; « PAS DE LIAISON »
##   clignotant hors de vue du sol) ;
## - à gauche, les messages reçus (heure de jeu, expéditeur ; non lus en jaune) ; à droite, le message choisi
##   (expéditeur, objet, réception, texte) et ses réponses ([1], [2]…) ;
## - galerie (F5, ou « Galerie » dans la barre de menu ; F5 encore : retour aux messages) : photos de la partie
##   (PhotoArchive) groupées par date, plus récentes en haut ; la photo choisie à droite (date, point survolé, altitude,
##   emprise), agrandie au clic (ou Entrée). Pendant une mission photo de campagne (CampaignDirector.can_send_photo),
##   bouton « Envoyer au sol » (liaison radio requise) : « Photo bien reçue… évaluation en cours… », puis la note de
##   la photo et son verdict (CampaignDirector.photo_evaluated) ; échéance dépassée : mission échouée, 0/20 ;
## - F1 : aide ; F2 : choix du canal (fenêtre) ; F10 : quitter la vue (quit_requested). Flèches : message (ou canal)
##   précédent / suivant ; chiffres : envoyer la réponse correspondante ; Entrée : valider le canal ; Échap : fermer
##   une fenêtre. Tout se fait aussi à la souris (clic sur un message, une réponse, une touche de la barre).
## Tous les libellés sont des clés des fichiers de langue (tr) ; les messages sont résolus par Campaigns.text_of.

signal quit_requested

const COLS := 80
const ROWS := 25
## Colonne du séparateur entre la liste des messages et le message.
const SPLIT := 30
const BLINK_S := 0.5
const FONTS: PackedStringArray = ["Consolas", "Lucida Console", "Courier New", "monospace"]

# Palette CGA.
const BLUE := Color(0.0, 0.0, 0.667)
const CYAN := Color(0.0, 0.667, 0.667)
const BLACK := Color(0.0, 0.0, 0.0)
const GREY := Color(0.667, 0.667, 0.667)
const WHITE := Color(1.0, 1.0, 1.0)
const YELLOW := Color(1.0, 1.0, 0.333)
const LIGHT_CYAN := Color(0.333, 1.0, 1.0)
const LIGHT_GREEN := Color(0.333, 1.0, 0.333)
const LIGHT_RED := Color(1.0, 0.333, 0.333)

enum Overlay { NONE, HELP, CHANNEL, PHOTO }
enum Mode { MESSAGES, GALLERY }

var radio: RadioComms

var _font: SystemFont
var _font_size := 20
var _cell := Vector2(12.0, 24.0)
var _ascent := 18.0
## Tampon de l'écran : caractère, couleur du texte et du fond de chaque case.
var _chars := PackedStringArray()
var _fg: Array[Color] = []
var _bg: Array[Color] = []
## Zones cliquables de l'image courante : [Rect2i (cases), Callable].
var _zones: Array = []
## Première zone de la fenêtre ouverte (aide, canal).
var _modal_from := 0
var _selected := ""
var _list_scroll := 0
var _overlay := Overlay.NONE
var _channel_cursor := 0
var _status := ""
var _status_color := WHITE
var _status_until := 0.0
var _clock := 0.0
var _blink := true
var _mode := Mode.MESSAGES
## Galerie : photo choisie (id, 0 : aucune), défilement de la liste, état de l'envoi (texte, couleur, photo concernée,
## 0 : toutes ; affiché sous cette photo seulement, jusqu'au suivant), image affichée et sa place à l'écran (pixels ; dessinée après le texte).
var _photo_id := 0
var _gallery_scroll := 0
var _photo_status := ""
var _photo_status_color := WHITE
var _photo_status_id := 0
var _image: Texture2D
var _image_rect := Rect2()
var _photos: PhotoArchive
var _director: CampaignDirector


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = SystemFont.new()
	_font.font_names = FONTS
	# Taille de police telle qu'un caractère occupe une case (largeur de l'image / COLS).
	_cell = size / Vector2(COLS, ROWS)
	var probe := _font.get_char_size("M".unicode_at(0), 20).x
	_font_size = maxi(8, floori(20.0 * _cell.x / maxf(probe, 1.0)))
	_ascent = (_cell.y - _font.get_height(_font_size)) * 0.5 + _font.get_ascent(_font_size)
	_chars.resize(COLS * ROWS)
	_fg.resize(COLS * ROWS)
	_bg.resize(COLS * ROWS)
	if radio:
		radio.changed.connect(queue_redraw)
		# Premier message : affiché d'office, mais lu seulement quand on le regarde (mark_shown, ou un clic).
		radio.message_received.connect(func(message: Dictionary) -> void:
			if _selected == "":
				_selected = message.id
			queue_redraw())
		_channel_cursor = radio.channel


func _process(delta: float) -> void:
	_clock += delta
	var blink := fmod(_clock, BLINK_S * 2.0) < BLINK_S
	if blink != _blink:
		_blink = blink
		queue_redraw()


func _draw() -> void:
	if radio == null:
		return
	_compose()
	# Fonds : bandes de cases de même couleur sur chaque ligne.
	for row in ROWS:
		var start := 0
		for col in range(1, COLS + 1):
			if col == COLS or _bg[row * COLS + col] != _bg[row * COLS + start]:
				draw_rect(Rect2(Vector2(start, row) * _cell, Vector2(col - start, 1) * _cell), _bg[row * COLS + start])
				start = col
	for i in COLS * ROWS:
		var c := _chars[i]
		if c != " " and c != "":
			var at := Vector2(i % COLS, floori(float(i) / COLS)) * _cell + Vector2(0.0, _ascent)
			draw_char(_font, at, c, _font_size, _fg[i])
	if _image and _image_rect.has_area():
		draw_texture_rect(_image, _image_rect, false)


# --- Entrées --------------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := Vector2i((click.position / _cell).floor())
	# Fenêtre ouverte : seules ses zones répondent (ajoutées en dernier) ; un clic à côté la ferme.
	var first := _modal_from if _overlay != Overlay.NONE else 0
	for k in range(_zones.size() - 1, first - 1, -1):
		var zone: Array = _zones[k]
		if (zone[0] as Rect2i).has_point(cell):
			(zone[1] as Callable).call()
			queue_redraw()
			accept_event()
			return
	if _overlay != Overlay.NONE:
		_overlay = Overlay.NONE
		queue_redraw()


## Touche transmise par CommConsole en vue radio ; vrai si elle est utilisée.
func handle_key(key: InputEventKey) -> bool:
	if not key.pressed:
		return false
	var used := true
	match key.keycode:
		KEY_F1:
			_overlay = Overlay.NONE if _overlay == Overlay.HELP else Overlay.HELP
		KEY_F2:
			_toggle_channels()
		KEY_F5:
			_toggle_gallery()
		KEY_F10:
			quit_requested.emit()
		KEY_ESCAPE:
			used = _overlay != Overlay.NONE
			_overlay = Overlay.NONE
		KEY_UP, KEY_DOWN:
			var step := -1 if key.keycode == KEY_UP else 1
			if _overlay == Overlay.CHANNEL:
				_channel_cursor = wrapi(_channel_cursor + step, 0, RadioComms.CHANNELS.size())
			elif _mode == Mode.GALLERY:
				_move_photo(step)
			else:
				_move_selection(step)
		KEY_ENTER, KEY_KP_ENTER:
			if _overlay == Overlay.CHANNEL:
				_choose_channel(_channel_cursor)
			elif _mode == Mode.GALLERY and _overlay == Overlay.NONE and _photo_id > 0:
				_overlay = Overlay.PHOTO
			else:
				used = false
		_:
			var digit := key.keycode - KEY_1 if key.keycode >= KEY_1 and key.keycode <= KEY_9 else \
					(key.keycode - KEY_KP_1 if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9 else -1)
			if digit >= 0 and _overlay == Overlay.NONE and _mode == Mode.MESSAGES:
				_send_reply(digit)
			else:
				used = false
	if used:
		queue_redraw()
	return used


## On s'installe devant l'écran (CommConsole) : le message affiché est lu.
func mark_shown() -> void:
	if _selected != "":
		radio.mark_read(_selected)


func _select(message_id: String) -> void:
	_selected = message_id
	radio.mark_read(message_id)


func _move_selection(step: int) -> void:
	var count := radio.inbox.size()
	if count == 0:
		return
	var index := _selected_index()
	index = clampi(count - 1 if index < 0 else index + step, 0, count - 1)
	_select(radio.inbox[index].id)


func _selected_index() -> int:
	for k in radio.inbox.size():
		if radio.inbox[k].id == _selected:
			return k
	return -1


func _toggle_channels() -> void:
	_overlay = Overlay.NONE if _overlay == Overlay.CHANNEL else Overlay.CHANNEL
	_channel_cursor = radio.channel


func _choose_channel(index: int) -> void:
	radio.set_channel(index)
	_overlay = Overlay.NONE


func _send_reply(choice: int) -> void:
	var message := radio.find(_selected)
	if message.is_empty() or message.answer >= 0 or choice >= (message.replies as Array).size():
		return
	if radio.reply(_selected, choice):
		_set_status(tr("COMM_SENT").format({"reply": _reply_text(message, choice)}), LIGHT_GREEN)
	else:
		_set_status(tr("COMM_SEND_FAILED"), LIGHT_RED)


func _set_status(text: String, color: Color) -> void:
	_status = text
	_status_color = color
	_status_until = _clock + 4.0


# --- Galerie --------------------------------------------------------------------------------------------------------

func _set_mode(mode: Mode) -> void:
	_mode = mode
	_overlay = Overlay.NONE
	if mode == Mode.GALLERY and _photo_id == 0:
		var photos := _sorted_photos()
		if not photos.is_empty():
			_photo_id = int(photos[0].id)


func _toggle_gallery() -> void:
	_set_mode(Mode.MESSAGES if _mode == Mode.GALLERY else Mode.GALLERY)


## Photos de la partie, plus récentes en premier (vide sans archive).
func _sorted_photos() -> Array[Dictionary]:
	if _photos == null:
		_photos = get_tree().get_first_node_in_group(PhotoArchive.GROUP) as PhotoArchive
		if _photos:
			_photos.photo_taken.connect(func(_photo: Dictionary) -> void: queue_redraw())
			_photos.restored.connect(func() -> void:
				_photo_id = 0
				queue_redraw())
	var photos: Array[Dictionary] = []
	if _photos:
		photos.assign(_photos.photos)
	photos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.utc_unix) > float(b.utc_unix))
	return photos


func _find_photo(photo_id: int) -> Dictionary:
	for photo in _sorted_photos():
		if int(photo.id) == photo_id:
			return photo
	return {}


func _move_photo(step: int) -> void:
	var photos := _sorted_photos()
	if photos.is_empty():
		return
	var index := photos.find(_find_photo(_photo_id))
	index = clampi(0 if index < 0 else index + step, 0, photos.size() - 1)
	_photo_id = int(photos[index].id)


## Directeur de campagne (mode campagne seulement : null sinon), abonné une fois à l'envoi des photos.
func _get_director() -> CampaignDirector:
	if _director == null:
		var director := get_tree().get_first_node_in_group(CampaignDirector.GROUP) as CampaignDirector
		if director == null or not director.is_active():
			return null
		_director = director
		_director.photo_received.connect(func(sent_id: int) -> void:
			_set_photo_status(tr("COMM_PHOTO_RECEIVED"), YELLOW, sent_id))
		_director.photo_evaluated.connect(_on_photo_evaluated)
		_director.mission_finished.connect(func(_mission: String, result: Dictionary) -> void:
			if result.get("expired", false):
				_set_photo_status(tr("COMM_PHOTO_EXPIRED"), LIGHT_RED, 0))
	return _director


func _can_send_photo() -> bool:
	var director := _get_director()
	return director != null and director.can_send_photo() and _photo_id > 0 and not director.sent_photos.has(_photo_id)


## Évaluation d'une photo déjà envoyée au sol ({} : jamais envoyée ; CampaignDirector.sent_photos).
func _sent_evaluation(photo_id: int) -> Dictionary:
	var director := _get_director()
	return director.sent_photos.get(photo_id, {}) if director else {}


## « Envoyer au sol » : il faut la liaison radio ; la suite vient du directeur (photo_received, photo_evaluated).
func _send_photo() -> void:
	if not _can_send_photo():
		return
	if radio.link <= 0.0:
		_set_photo_status(tr("COMM_PHOTO_NO_LINK"), LIGHT_RED, _photo_id)
		return
	_director.send_photo(_find_photo(_photo_id))


func _on_photo_evaluated(evaluation: Dictionary) -> void:
	var photo_id := int(evaluation.photo_id)
	if evaluation.expired:
		_set_photo_status(tr("COMM_PHOTO_EXPIRED"), LIGHT_RED, photo_id)
		return
	var key := "COMM_PHOTO_INVALID"
	if evaluation.valid:
		key = "COMM_PHOTO_VALID" if evaluation.complete else "COMM_PHOTO_VALID_MORE"
	_set_photo_status(_score_text(key, evaluation), LIGHT_GREEN if evaluation.valid else LIGHT_RED, photo_id)


## Texte de la clé key avec la note et la distance à la cible d'une évaluation (CampaignDirector.send_photo).
func _score_text(key: String, evaluation: Dictionary) -> String:
	var distance := float(evaluation.get("distance_km", -1.0))
	var shown := "%.1f" % distance if distance < 100.0 else NumberFormat.group(roundi(distance), " ")
	return tr(key).format({"score": "%.1f" % float(evaluation.score), "distance": shown if distance >= 0.0 else "?"})


## État de l'envoi, affiché sous la photo photo_id (0 : sous toutes).
func _set_photo_status(text: String, color: Color, photo_id: int) -> void:
	_photo_status = text
	_photo_status_color = color
	_photo_status_id = photo_id
	queue_redraw()


# --- Composition de l'écran -----------------------------------------------------------------------------------------

func _compose() -> void:
	_zones.clear()
	_fill(Rect2i(0, 0, COLS, ROWS), " ", WHITE, BLUE)
	_menu_bar()
	_status_line()
	_frame(Rect2i(0, 2, COLS, 21), LIGHT_CYAN, BLUE)
	_put(SPLIT, 2, "╤", LIGHT_CYAN, BLUE)
	_put(SPLIT, 22, "╧", LIGHT_CYAN, BLUE)
	for row in range(3, 22):
		_put(SPLIT, row, "│", LIGHT_CYAN, BLUE)
	_image = null
	_image_rect = Rect2()
	if _mode == Mode.GALLERY:
		_gallery_list()
		_gallery_view()
	else:
		_message_list()
		_message_view()
	if _clock < _status_until:
		_put(1, 23, _fit(_status, COLS - 2), _status_color, BLUE)
	_key_bar()
	_modal_from = _zones.size()
	match _overlay:
		Overlay.HELP:
			_help_window()
		Overlay.CHANNEL:
			_channel_window()
		Overlay.PHOTO:
			_photo_window()


func _menu_bar() -> void:
	_fill(Rect2i(0, 0, COLS, 1), " ", BLACK, CYAN)
	_put(1, 0, "COMM.EXE  v1.2", BLACK, CYAN)
	# Menus : Messages, Galerie (le menu ouvert en surbrillance).
	var x := 17
	for entry: Array in [[Mode.MESSAGES, "COMM_MENU_MESSAGES"], [Mode.GALLERY, "COMM_MENU_GALLERY"]]:
		var label := " %s " % tr(entry[1])
		var open: bool = _mode == entry[0]
		_put(x, 0, label, WHITE if open else BLACK, BLACK if open else CYAN)
		var mode: Mode = entry[0]
		_zones.append([Rect2i(x, 0, label.length(), 1), func() -> void: _set_mode(mode)])
		x += label.length() + 1
	var clock := Time.get_datetime_string_from_unix_time(int(radio.now_unix()), true) + " UTC"
	_put(COLS - 1 - clock.length(), 0, clock, BLACK, CYAN)


func _status_line() -> void:
	var ch: Dictionary = RadioComms.CHANNELS[radio.channel]
	var tuned := "%s %d  %.3f MHz  %s" % [tr("COMM_CHANNEL").to_upper(), radio.channel + 1, ch.mhz, ch.band]
	_put(1, 1, tuned, WHITE, BLUE)
	_zones.append([Rect2i(1, 1, tuned.length(), 1), _toggle_channels])
	var x := 1 + tuned.length() + 4
	_put(x, 1, tr("COMM_LINK").to_upper() + " ", WHITE, BLUE)
	x += tr("COMM_LINK").length() + 1
	if radio.link <= 0.0:
		if _blink:
			_put(x, 1, tr("COMM_NO_LINK"), YELLOW, BLUE)
		return
	var bars := 10
	var filled := clampi(roundi(radio.link * bars), 1, bars)
	_put(x, 1, "█".repeat(filled), LIGHT_GREEN, BLUE)
	_put(x + filled, 1, "░".repeat(bars - filled), GREY, BLUE)
	_put(x + bars + 1, 1, "%3d%%  %s" % [roundi(radio.link * 100.0), radio.link_station], WHITE, BLUE)


func _message_list() -> void:
	var title := "%s (%d)" % [tr("COMM_MESSAGES").to_upper(), radio.inbox.size()]
	_put(2, 3, _fit(title, SPLIT - 3), YELLOW, BLUE)
	var rows := 17
	var count := radio.inbox.size()
	if count == 0:
		_put(2, 5, _fit(tr("COMM_NO_MESSAGE"), SPLIT - 3), GREY, BLUE)
		return
	# Plus récents en haut ; la liste suit la sélection.
	var index := _selected_index()
	var line_of_selected := count - 1 - index if index >= 0 else 0
	_list_scroll = clampi(_list_scroll, maxi(0, line_of_selected - rows + 1), line_of_selected)
	for line in range(_list_scroll, mini(count, _list_scroll + rows)):
		var message: Dictionary = radio.inbox[count - 1 - line]
		var row := 5 + line - _list_scroll
		var chosen: bool = message.id == _selected
		var fg := YELLOW if not message.read else WHITE
		var bg := CYAN if chosen else BLUE
		if chosen:
			fg = BLACK
		var hour := Time.get_time_string_from_unix_time(int(message.received_unix)).substr(0, 5)
		var text := "%s%s %s" % ["►" if chosen else ("•" if not message.read else " "), hour,
				Campaigns.text_of(message, "from")]
		_fill(Rect2i(1, row, SPLIT - 1, 1), " ", fg, bg)
		_put(1, row, _fit(text, SPLIT - 1), fg, bg)
		var id: String = message.id
		_zones.append([Rect2i(1, row, SPLIT - 1, 1), func() -> void: _select(id)])


func _message_view() -> void:
	var left := SPLIT + 2
	var width := COLS - 2 - left
	var message := radio.find(_selected)
	if message.is_empty():
		var hint := tr("COMM_NO_MESSAGE") if radio.inbox.is_empty() else ""
		_put(left + floori((width - hint.length()) * 0.5), 12, hint, GREY, BLUE)
		return
	var labels := [tr("COMM_FROM"), tr("COMM_SUBJECT"), tr("COMM_RECEIVED")]
	var pad := 0
	for label: String in labels:
		pad = maxi(pad, label.length())
	var ch: Dictionary = RadioComms.CHANNELS[int(message.get("received_channel", radio.channel))]
	var received := "%s UTC  %.3f MHz" % [Time.get_datetime_string_from_unix_time(int(message.received_unix), true)
			.substr(0, 16), ch.mhz]
	var values := [Campaigns.text_of(message, "from"), Campaigns.text_of(message, "subject"), received]
	for k in 3:
		_put(left, 3 + k, (labels[k] as String).rpad(pad) + " : ", YELLOW, BLUE)
		_put(left + pad + 3, 3 + k, _fit(values[k], width - pad - 3), WHITE, BLUE)
	_put(left, 6, "─".repeat(width), LIGHT_CYAN, BLUE)
	var row := 7
	var lines := _wrap(Campaigns.text_of(message, "body"), width)
	for k in lines.size():
		if row > 20:
			break
		_put(left, row, lines[k], WHITE, BLUE)
		# Curseur clignotant au bout du texte.
		if k == lines.size() - 1 and _blink:
			_put(left + lines[k].length(), row, "█", WHITE, BLUE)
		row += 1
	var replies: Array = message.replies
	if replies.is_empty():
		return
	row += 1
	if message.answer >= 0:
		_put(left, row, _fit(tr("COMM_SENT").format({"reply": _reply_text(message, message.answer)}), width),
				LIGHT_GREEN, BLUE)
		return
	_put(left, row, tr("COMM_REPLIES").to_upper(), YELLOW, BLUE)
	row += 1
	for k in replies.size():
		var reply_lines := _wrap("[%d] %s" % [k + 1, _reply_text(message, k)], width)
		for line in reply_lines:
			if row > 21:
				return
			_put(left, row, line, LIGHT_CYAN, BLUE)
			var choice := k
			_zones.append([Rect2i(left, row, width, 1), func() -> void: _send_reply(choice)])
			row += 1


func _key_bar() -> void:
	# Libellés de 6 caractères au plus (9 premières touches), 6 pour F10.
	var keys := {1: "COMM_KEY_HELP", 2: "COMM_KEY_CHANNEL",
			5: "COMM_KEY_INBOX" if _mode == Mode.GALLERY else "COMM_KEY_GALLERY", 10: "COMM_KEY_QUIT"}
	var actions := {
		1: func() -> void: _overlay = Overlay.NONE if _overlay == Overlay.HELP else Overlay.HELP,
		2: _toggle_channels,
		5: _toggle_gallery,
		10: func() -> void: quit_requested.emit(),
	}
	_fill(Rect2i(0, 24, COLS, 1), " ", BLACK, BLACK)
	var slot := floori(COLS * 0.1)
	for n in range(1, 11):
		var x := (n - 1) * slot
		var digit := str(n)
		_put(x, 24, digit, WHITE, BLACK)
		var label := tr(keys[n]) if keys.has(n) else ""
		# Une colonne noire entre les touches, sauf après la dernière.
		var width := slot - digit.length() - (1 if n < 10 else 0)
		_fill(Rect2i(x + digit.length(), 24, width, 1), " ", BLACK, CYAN)
		_put(x + digit.length(), 24, _fit(label, width), BLACK, CYAN)
		if actions.has(n):
			_zones.append([Rect2i(x, 24, slot, 1), actions[n]])


func _help_window() -> void:
	var box := Rect2i(10, 3, 60, 19)
	_window(box, tr("COMM_KEY_HELP"))
	var row := box.position.y + 2
	for line in _wrap(tr("COMM_HELP_TEXT"), box.size.x - 4):
		if row >= box.end.y - 2:
			break
		_put(box.position.x + 2, row, line, BLACK, GREY)
		row += 1
	var ok := "[ OK ]"
	var x := box.position.x + floori((box.size.x - ok.length()) * 0.5)
	_put(x, box.end.y - 2, ok, WHITE, BLACK)
	_zones.append([box, func() -> void: _overlay = Overlay.NONE])


func _channel_window() -> void:
	var count := RadioComms.CHANNELS.size()
	var box := Rect2i(24, 6, 32, count + 4)
	_window(box, tr("COMM_CHANNEL_TITLE"))
	# Clic dans la fenêtre hors des canaux : rien (elle reste ouverte).
	_zones.append([box, func() -> void: pass])
	for k in count:
		var ch: Dictionary = RadioComms.CHANNELS[k]
		var row := box.position.y + 2 + k
		var chosen := k == _channel_cursor
		var text := "%s %d  %9.3f MHz  %-3s" % ["►" if k == radio.channel else " ", k + 1, ch.mhz, ch.band]
		var fg := WHITE if chosen else BLACK
		var bg := BLACK if chosen else GREY
		_fill(Rect2i(box.position.x + 1, row, box.size.x - 2, 1), " ", fg, bg)
		_put(box.position.x + 2, row, text, fg, bg)
		var index := k
		_zones.append([Rect2i(box.position.x + 1, row, box.size.x - 2, 1), func() -> void: _choose_channel(index)])


func _gallery_list() -> void:
	var photos := _sorted_photos()
	_put(2, 3, _fit("%s (%d)" % [tr("COMM_MENU_GALLERY").to_upper(), photos.size()], SPLIT - 3), YELLOW, BLUE)
	if photos.is_empty():
		var empty_row := 5
		for line in _wrap(tr("COMM_GALLERY_EMPTY"), SPLIT - 3):
			_put(2, empty_row, line, GREY, BLUE)
			empty_row += 1
		return
	# Lignes : date (en-tête), puis ses photos ; la liste suit la photo choisie.
	var lines: Array[Dictionary] = []
	var date := ""
	var selected_line := 0
	for photo in photos:
		var day := Time.get_date_string_from_unix_time(int(photo.utc_unix))
		if day != date:
			date = day
			lines.append({"date": day})
		if int(photo.id) == _photo_id:
			selected_line = lines.size()
		lines.append({"photo": photo})
	var rows := 17
	_gallery_scroll = clampi(_gallery_scroll, maxi(0, selected_line - rows + 1), selected_line)
	for line in range(_gallery_scroll, mini(lines.size(), _gallery_scroll + rows)):
		var row := 5 + line - _gallery_scroll
		var entry := lines[line]
		if entry.has("date"):
			var header := "─ %s " % entry.date
			_put(1, row, header + "─".repeat(SPLIT - 1 - header.length()), LIGHT_CYAN, BLUE)
			continue
		var photo: Dictionary = entry.photo
		var chosen := int(photo.id) == _photo_id
		var fg := BLACK if chosen else WHITE
		var bg := CYAN if chosen else BLUE
		var hour := Time.get_time_string_from_unix_time(int(photo.utc_unix)).substr(0, 5)
		var text := "%s%s %s" % ["►" if chosen else " ", hour, GeoMath.format_lat_lon(photo.lat, photo.lon)]
		_fill(Rect2i(1, row, SPLIT - 1, 1), " ", fg, bg)
		_put(1, row, _fit(text, SPLIT - 1), fg, bg)
		var id := int(photo.id)
		_zones.append([Rect2i(1, row, SPLIT - 1, 1), func() -> void: _photo_id = id])


func _gallery_view() -> void:
	var left := SPLIT + 2
	var width := COLS - 2 - left
	var photo := _find_photo(_photo_id)
	if photo.is_empty():
		return
	var stamp := Time.get_datetime_string_from_unix_time(int(photo.utc_unix), true) + " UTC"
	_put(left, 3, tr("COMM_PHOTO_TITLE").format({"n": photo.id}).to_upper(), YELLOW, BLUE)
	_put(COLS - 2 - stamp.length(), 3, stamp, WHITE, BLUE)
	var footprint: Vector2 = photo.footprint_km
	_put(left, 4, _fit(tr("COMM_PHOTO_DETAILS").format({"position": GeoMath.format_lat_lon(photo.lat, photo.lon),
			"altitude": roundi(float(photo.altitude_km)), "width": roundi(footprint.x),
			"height": roundi(footprint.y)}), width), WHITE, BLUE)
	_put(left, 5, "─".repeat(width), LIGHT_CYAN, BLUE)
	# Photo : rangées 6 à 17, centrée ; un clic l'agrandit.
	var area := _place_image(photo.texture, Rect2i(left, 6, width, 12))
	_zones.append([area, func() -> void: _overlay = Overlay.PHOTO])
	# Rangées 18 à 21 : bouton d'envoi, ou note d'une photo déjà envoyée, ou aide ; puis l'état de l'envoi de cette photo.
	var row := 18
	var lines: Array[Array] = []
	var sent := _sent_evaluation(int(photo.id))
	if _can_send_photo():
		var label := "[ %s ]" % tr("COMM_PHOTO_SEND").to_upper()
		var x := left + floori((width - label.length()) * 0.5)
		_put(x, row, label, BLACK, LIGHT_GREEN)
		_zones.append([Rect2i(x, row, label.length(), 1), _send_photo])
		row += 1
	elif not sent.is_empty() and not sent.expired:
		# Son message d'évaluation, s'il est encore affiché, dit déjà la note.
		if _photo_status_id != int(photo.id):
			lines.append([_score_text("COMM_PHOTO_SENT", sent), LIGHT_CYAN])
	else:
		lines.append([tr("COMM_PHOTO_ENLARGE"), GREY])
	if _photo_status_id == 0 or _photo_status_id == int(photo.id):
		lines.append([_photo_status, _photo_status_color])
	for entry in lines:
		for line in _wrap(entry[0], width):
			if row > 21:
				break
			_put(left, row, line, entry[1], BLUE)
			row += 1


## Photo choisie agrandie, sur presque tout l'écran ; un clic ou Échap la ferme.
func _photo_window() -> void:
	var photo := _find_photo(_photo_id)
	if photo.is_empty():
		_overlay = Overlay.NONE
		return
	var box := Rect2i(1, 1, COLS - 2, ROWS - 2)
	_window(box, tr("COMM_PHOTO_TITLE").format({"n": photo.id}))
	_place_image(photo.texture, Rect2i(box.position.x + 1, box.position.y + 1, box.size.x - 2, box.size.y - 2))
	_zones.append([Rect2i(0, 0, COLS, ROWS), func() -> void: _overlay = Overlay.NONE])


## Image dans un cadre de cases (fond noir), à ses proportions, centrée ; dessinée par _draw. Rend les cases couvertes.
func _place_image(texture: Texture2D, cells: Rect2i) -> Rect2i:
	_fill(cells, " ", BLACK, BLACK)
	if texture == null:
		return cells
	var frame := Rect2(Vector2(cells.position) * _cell, Vector2(cells.size) * _cell)
	var image_size := texture.get_size()
	var fit := minf(frame.size.x / image_size.x, frame.size.y / image_size.y)
	var shown := image_size * fit
	_image = texture
	_image_rect = Rect2(frame.position + (frame.size - shown) * 0.5, shown)
	return cells


## Fenêtre grise à cadre double blanc, titre centré, ombre noire.
func _window(box: Rect2i, title: String) -> void:
	_fill(Rect2i(box.position + Vector2i(2, 1), box.size), " ", BLACK, BLACK)
	_fill(box, " ", BLACK, GREY)
	_frame(box, WHITE, GREY)
	var label := " %s " % title
	_put(box.position.x + floori((box.size.x - label.length()) * 0.5), box.position.y, label, BLACK, GREY)


# --- Tampon ---------------------------------------------------------------------------------------------------------

func _put(x: int, y: int, text: String, fg: Color, bg: Color) -> void:
	if y < 0 or y >= ROWS:
		return
	for k in text.length():
		var col := x + k
		if col < 0 or col >= COLS:
			continue
		var i := y * COLS + col
		_chars[i] = text[k]
		_fg[i] = fg
		_bg[i] = bg


func _fill(rect: Rect2i, c: String, fg: Color, bg: Color) -> void:
	for y in range(maxi(rect.position.y, 0), mini(rect.end.y, ROWS)):
		_put(rect.position.x, y, c.repeat(rect.size.x), fg, bg)


func _frame(rect: Rect2i, fg: Color, bg: Color) -> void:
	var x0 := rect.position.x
	var y0 := rect.position.y
	var x1 := rect.end.x - 1
	var y1 := rect.end.y - 1
	_put(x0, y0, "╔" + "═".repeat(rect.size.x - 2) + "╗", fg, bg)
	_put(x0, y1, "╚" + "═".repeat(rect.size.x - 2) + "╝", fg, bg)
	for y in range(y0 + 1, y1):
		_put(x0, y, "║", fg, bg)
		_put(x1, y, "║", fg, bg)


func _reply_text(message: Dictionary, choice: int) -> String:
	return Campaigns.text_of({"reply": (message.replies as Array)[choice]}, "reply")


static func _fit(text: String, width: int) -> String:
	return text if text.length() <= width else text.substr(0, maxi(width - 1, 0)) + "…"


## Coupe un texte en lignes d'au plus width caractères (aux espaces, et aux retours à la ligne).
static func _wrap(text: String, width: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			while word.length() > width:
				if line != "":
					lines.append(line)
					line = ""
				lines.append(word.substr(0, width))
				word = word.substr(width)
			if line == "":
				line = word
			elif line.length() + 1 + word.length() <= width:
				line += " " + word
			else:
				lines.append(line)
				line = word
		lines.append(line)
	return lines
