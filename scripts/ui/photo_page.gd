class_name PhotoPage
extends HBoxContainer
## Onglet Photographie de la tablette (TabletDisplay) : la vue au nadir en temps réel (nadir_texture, rendue par la
## tablette seulement quand l'onglet est affiché, légende en incrustation), le bouton « Photo » (flash, puis
## photo_requested : la tablette prend la photo, PhotoArchive) et la galerie des photos prises : « Galerie (n) »
## remplace la vue en direct par la dernière photo (◀ ▶ : précédente, suivante ; légende : numéro, date, point
## survolé, altitude, emprise), « Vue en direct » y revient ; le bouton Photo revient aussi à la vue en direct.

## Bouton Photo pressé : la tablette prend la photo (scripts/tablet.gd).
signal photo_requested

const FLASH_S := 0.35

## Image de la vue au nadir (NadirCamera), fixée avant l'ajout à l'arbre.
var nadir_texture: Texture2D
## Photos prises (galerie) ; réglé par la tablette, en général après la construction.
var archive: PhotoArchive:
	set(value):
		archive = value
		if archive:
			archive.photo_taken.connect(func(_photo: Dictionary) -> void: _show_photo(_photo_index))
			archive.restored.connect(func() -> void: _show_photo(-1))
		if _gallery_button:
			_show_photo(_photo_index)

var _page_size: Vector2
var _side_width: float
var _flash: ColorRect
var _photo_view: TextureRect
var _photo_caption: Label
var _gallery_button: Button
var _previous_button: Button
var _next_button: Button
## Photo affichée dans la galerie (−1 : vue en direct).
var _photo_index := -1


## page_size : taille de la page (pixels) ; side_width : largeur de la colonne du bouton Photo, à droite.
func _init(page_size: Vector2, side_width: float) -> void:
	_page_size = page_size
	_side_width = side_width


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_photo_view = TextureRect.new()
	_photo_view.texture = nadir_texture
	_photo_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_photo_view.custom_minimum_size = Vector2(_page_size.x - _side_width - 16.0, _page_size.y)
	_photo_view.clip_contents = true
	add_child(_photo_view)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_photo_view.add_child(_flash)
	_photo_caption = Label.new()
	_photo_caption.text = "TABLET_NADIR"
	_photo_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_photo_caption.add_theme_font_size_override("font_size", 20)
	_photo_caption.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	_photo_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	# Fond sombre : légende lisible sur une photo claire (nuages, désert).
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	caption_style.set_corner_radius_all(4)
	caption_style.set_content_margin_all(6)
	_photo_caption.add_theme_stylebox_override("normal", caption_style)
	_photo_caption.position = Vector2(8, 6)
	_photo_view.add_child(_photo_caption)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 10)
	add_child(side)
	var shutter := BigRedButton.new()
	shutter.cap_color = Color(0.82, 0.84, 0.86)
	shutter.custom_minimum_size = Vector2(120.0, 112.0)
	shutter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shutter.tooltip_text = "TABLET_PHOTO"
	shutter.pressed.connect(_take_photo)
	side.add_child(shutter)
	var label := Label.new()
	label.text = "TABLET_PHOTO"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", PilotDisplay.COLOR_TEXT)
	side.add_child(label)
	side.add_child(HSeparator.new())
	_gallery_button = Button.new()
	_gallery_button.focus_mode = Control.FOCUS_NONE
	_gallery_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_gallery_button.pressed.connect(func() -> void: _show_photo(-1 if _photo_index >= 0 else _photo_count() - 1))
	side.add_child(_gallery_button)
	var browse := HBoxContainer.new()
	browse.alignment = BoxContainer.ALIGNMENT_CENTER
	browse.add_theme_constant_override("separation", 10)
	side.add_child(browse)
	_previous_button = _make_arrow_button("◀", func() -> void: _show_photo(maxi(_photo_index - 1, 0)))
	_next_button = _make_arrow_button("▶", func() -> void: _show_photo(mini(_photo_index + 1, _photo_count() - 1)))
	browse.add_child(_previous_button)
	browse.add_child(_next_button)
	_show_photo(-1)


static func _make_arrow_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.custom_minimum_size = Vector2(64.0, 44.0)
	button.pressed.connect(action)
	return button


func _photo_count() -> int:
	return archive.photos.size() if archive else 0


## Affiche la photo index de la galerie, ou la vue en direct (index −1).
func _show_photo(index: int) -> void:
	_photo_index = index if index >= 0 and index < _photo_count() else -1
	var count := _photo_count()
	if _photo_index < 0:
		_photo_view.texture = nadir_texture
		_photo_caption.text = tr("TABLET_NADIR")
	else:
		var photo: Dictionary = archive.photos[_photo_index]
		var footprint: Vector2 = photo.footprint_km
		_photo_view.texture = photo.texture
		_photo_caption.text = tr("TABLET_PHOTO_CAPTION").format({"n": _photo_index + 1, "count": count,
				"date": Time.get_datetime_string_from_unix_time(int(photo.utc_unix), true).substr(0, 16),
				"place": GeoMath.format_lat_lon(photo.lat, photo.lon), "altitude": roundi(photo.altitude_km),
				"width": roundi(footprint.x), "height": roundi(footprint.y)})
	_gallery_button.text = tr("TABLET_LIVE") if _photo_index >= 0 else tr("TABLET_GALLERY").format({"count": count})
	_gallery_button.disabled = count == 0 and _photo_index < 0
	_previous_button.disabled = _photo_index <= 0
	_next_button.disabled = _photo_index < 0 or _photo_index >= count - 1


## Bouton Photo : retour à la vue en direct, flash, et prise de vue par la tablette (photo_requested).
func _take_photo() -> void:
	_show_photo(-1)
	_flash.color.a = 0.9
	create_tween().tween_property(_flash, "color:a", 0.0, FLASH_S)
	photo_requested.emit()
