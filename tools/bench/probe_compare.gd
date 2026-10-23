# Pas de class_name : tools/ est ignoré par l'éditeur (.gdignore), les sondes le chargent par preload.
extends RefCounted
## Comparaison d'un relevé de sonde (dictionnaire de valeurs : nombres, vecteurs, transformations, tableaux,
## textures…) à une référence écrite par var_to_str (tools/bench/results/*.txt) : écarts listés avec leur chemin,
## tolérance relative sur les flottants. Partagé par nuke_probe et orbit_probe.


## Compare record à la référence path ; write : la (ré)écrit à la place. Rend {written, missing, diffs}.
static func check(record: Dictionary, path: String, write: bool) -> Dictionary:
	var result := {"written": false, "missing": false, "diffs": [] as Array[String]}
	if write:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(var_to_str(record))
		result.written = true
	elif FileAccess.file_exists(path):
		var reference: Variant = str_to_var(FileAccess.get_file_as_string(path))
		diff(reference, record, "", result.diffs)
	else:
		result.missing = true
	return result


## Valeur comparable et sérialisable : une texture est remplacée par la taille et le hachage de ses données.
static func portable(value: Variant) -> Variant:
	if value is Texture2D:
		var image: Image = (value as Texture2D).get_image()
		if image == null:
			return "texture sans image"
		return {"size": image.get_size(), "format": image.get_format(), "hash": hash(image.get_data())}
	return value


## Écarts entre deux valeurs (tolérance relative sur les flottants), listés avec leur chemin.
static func diff(a: Variant, b: Variant, path: String, out: Array[String]) -> void:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				out.append(path + "/" + str(k) + " : absent")
			else:
				diff(a[k], b[k], path + "/" + str(k), out)
		for k in b:
			if not a.has(k):
				out.append(path + "/" + str(k) + " : nouveau")
		return
	var fa := flatten(a)
	var fb := flatten(b)
	if fa.size() != fb.size():
		out.append("%s : %d valeur(s) contre %d" % [path, fa.size(), fb.size()])
		return
	for i in fa.size():
		var x: Variant = fa[i]
		var y: Variant = fb[i]
		if x is float or y is float:
			if not is_equal_approx(float(x), float(y)) and absf(float(x) - float(y)) > 1e-5 * maxf(1.0, absf(float(x))):
				out.append("%s[%d] : %s contre %s" % [path, i, str(x), str(y)])
				return
		elif x != y:
			out.append("%s[%d] : %s contre %s" % [path, i, str(x), str(y)])
			return


## Toute valeur en liste plate de nombres, booléens et chaînes (dictionnaires par clés triées : var_to_str les écrit
## dans l'ordre des clés, pas d'insertion).
static func flatten(value: Variant) -> Array:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return [value]
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_AABB:
			return flatten(value.position) + flatten(value.size)
		TYPE_BASIS:
			return flatten(value.x) + flatten(value.y) + flatten(value.z)
		TYPE_TRANSFORM3D:
			return flatten(value.basis) + flatten(value.origin)
		TYPE_PROJECTION:
			return flatten(value.x) + flatten(value.y) + flatten(value.z) + flatten(value.w)
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_INT32_ARRAY, \
				TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
				TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			var out := []
			for item in value:
				out.append_array(flatten(item))
			return out
		TYPE_DICTIONARY:
			var out := []
			# Tri par le texte des clés : String et StringName (clé créée par « dict.cle = … ») se mélangent.
			var keys: Array = value.keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			for k in keys:
				out.append(str(k))
				out.append_array(flatten(value[k]))
			return out
	return [str(value)]
