extends SceneTree
## Outil hors-jeu : carte réduite de la couverture nuageuse (assets/cloud_cover.res, Image L8 1440 × 720,
## équirectangulaire, 0,25°), tirée de assets/textures/earth_clouds_16k.jpg (même instantané VIIRS que les nuages
## affichés). Lue côté CPU par CloudWeather (météo du bandeau de la télévision). Usage :
##   godot --headless --path <projet> --script res://tools/build_cloud_cover.gd

const SOURCE := "res://assets/textures/earth_clouds_16k.jpg"
const OUTPUT := "res://assets/cloud_cover.res"
const SIZE := Vector2i(1440, 720)


func _init() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	if image == null or image.is_empty():
		push_error("Lecture impossible : " + SOURCE)
		quit(1)
		return
	image.convert(Image.FORMAT_L8)
	# Réduction par moitiés (moyenne de 2 × 2 à chaque pas), puis à la taille finale.
	while image.get_width() > SIZE.x * 2:
		image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)
	var error := ResourceSaver.save(image, OUTPUT)
	print("%s : %d × %d (%s)" % [OUTPUT, image.get_width(), image.get_height(), error_string(error)])
	quit(0 if error == OK else 1)
