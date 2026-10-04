extends SceneTree
## Outil hors-jeu : convertit les tuiles JPEG d'un dossier en WebP avec perte (niveaux de gris), ~2 fois plus
## légères que le JPEG à qualité comparable, puis supprime les JPEG. Utilisé pour les tuiles de couverture
## nuageuse (assets/earth_cloud_tiles). Usage :
##   godot --headless --path <projet> --script res://tools/convert_tiles_webp.gd -- <dossier>


func _init() -> void:
	var count := 0
	for dir in OS.get_cmdline_user_args():
		for file in DirAccess.get_files_at(dir):
			if file.get_extension().to_lower() != "jpg":
				continue
			var path := dir.path_join(file)
			var image := Image.load_from_file(path)
			if image == null:
				push_error("Lecture impossible : " + path)
				continue
			image.convert(Image.FORMAT_L8)
			if image.save_webp(path.get_basename() + ".webp", true, 0.8) == OK:
				DirAccess.remove_absolute(path)
				count += 1
	print("%d tuile(s) converties" % count)
	quit(0)
