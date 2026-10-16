class_name FpsOverlay
extends CanvasLayer
## Compteur de performances en haut à droite de l'écran (outil de développement, nœud FpsOverlay de orbit_view.tscn) :
## images par seconde, temps CPU moyen par image, temps GPU moyen (RenderingServer, mesure du viewport principal),
## nombre d'appels de dessin et mémoire vidéo. Moyennes sur REFRESH_S. F3 l'affiche ou le masque.

const REFRESH_S := 0.5
const KEY_TOGGLE := KEY_F3

var _label: Label
var _frames := 0
var _since_usec := 0
var _gpu_sum := 0.0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.offset_top = 4.0
	_label.offset_right = -12.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_TOGGLE:
		visible = not visible
		get_viewport().set_input_as_handled()


## Temps réel (ticks), indépendant de la pause et de la vitesse du temps.
func _process(_delta: float) -> void:
	_frames += 1
	_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var elapsed := (Time.get_ticks_usec() - _since_usec) / 1e6
	if elapsed < REFRESH_S:
		return
	_label.text = "%d fps · CPU %.1f ms · GPU %.1f ms · %d draw · VRAM %d Mo" % [roundi(_frames / elapsed),
			1000.0 * elapsed / _frames, _gpu_sum / _frames,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)]
	_frames = 0
	_since_usec = Time.get_ticks_usec()
	_gpu_sum = 0.0
