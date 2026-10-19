# Outil hors-jeu : repère de départ du joueur Point_Vue_Couchette (collection Reperes_Jeu) dans
# E:\Blender\nuke_station.blend : allongé dans la couchette de l'Habitation (paroi +Y, oreiller côté +X), l'œil au-dessus
# de l'oreiller, le regard vers les pieds, un peu plongé vers le sac de couchage.
#   & ./tools/blender_exec.ps1 -File tools/blender/add_bunk_view.py
# Axes du repère : +Y = direction du regard, +Z = haut de la vue (après conversion glTF : −Z et +Y dans Godot, soit
# directement la base d'une Camera3D ; scripts/observer.gd y place la caméra au démarrage). Rejouable.
import bpy
from mathutils import Matrix, Vector

EYE = Vector((3.40, 1.33, 0.0))      # au-dessus de l'oreiller (x 3,34–3,60), à 0,28 m du sac de couchage (y 1,615)
TARGET = Vector((2.15, 1.66, 0.0))   # pieds, sur le sac de couchage
FACE = Vector((0.0, -1.0, 0.0))      # dos contre la paroi +Y : le visage regarde −Y

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
name = "Point_Vue_Couchette"
old = bpy.data.objects.get(name)
if old:
    bpy.data.objects.remove(old)
forward = (TARGET - EYE).normalized()
up = (FACE - forward * FACE.dot(forward)).normalized()
right = forward.cross(up)
m = Matrix((right, forward, up)).transposed().to_4x4()
m.translation = EYE
marker = bpy.data.objects.new(name, None)
marker.empty_display_type = 'ARROWS'
marker.empty_display_size = 0.2
bpy.data.collections["Reperes_Jeu"].objects.link(marker)
marker.matrix_world = m
marker["note"] = "depart du joueur : +Y = regard, +Z = haut de la vue (Godot : -Z et +Y)"
bpy.ops.wm.save_mainfile()
result = {"repere": name, "regard": [round(v, 3) for v in forward], "haut": [round(v, 3) for v in up]}
