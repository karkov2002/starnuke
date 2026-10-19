# Outil hors-jeu : rend le vaisseau cargo détachable dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP
# de Blender Lab).
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/build_cargo_undock.py
# Rejouable. Les 9 objets de la collection Vaisseau_Cargo deviennent enfants d'un pivot Pivot_Cargo placé sur le plan
# d'amarrage (avant de l'anneau Cargo_Anneau, contre Arrimage_Port_Adaptateur) ; le pivot porte la piste NLA
# « Separation_Cargo » : recul de SEPARATION_M le long de −X (axe des modules) en DURATION_S, départ et arrivée en
# douceur (courbe de Bézier aux poignées automatiques : ressorts de séparation, puis freinage). Image 1 = amarré.
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy
from mathutils import Matrix, Vector

PIVOT = "Pivot_Cargo"
TRACK = "Separation_Cargo"
SEPARATION_M = 10.0
DURATION_S = 30.0

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
scene = bpy.context.scene
scene.frame_set(1)
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
collection = bpy.data.collections["Vaisseau_Cargo"]
parts = [o for o in collection.objects if o.name != PIVOT]

# Repli d'un passage précédent : pièces détachées du pivot (transformation monde gardée), pivot et action supprimés.
old = bpy.data.objects.get(PIVOT)
if old is not None:
    for o in parts:
        if o.parent == old:
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
    if old.animation_data:
        for t in old.animation_data.nla_tracks:
            for st in t.strips:
                if st.action and st.action.users <= 1:
                    bpy.data.actions.remove(st.action)
    bpy.data.objects.remove(old)

# Plan d'amarrage : face avant (+X) de l'anneau du cargo.
ring = bpy.data.objects["Cargo_Anneau"]
front_x = max((ring.matrix_world @ Vector(c)).x for c in ring.bound_box)
pivot = bpy.data.objects.new(PIVOT, None)
pivot.empty_display_type = 'ARROWS'
pivot.empty_display_size = 1.0
collection.objects.link(pivot)
pivot.location = (front_x, 0.0, 0.0)
pivot["note"] = "pivot du vaisseau cargo : animation Separation_Cargo (recul de %g m selon -X)" % SEPARATION_M
bpy.context.view_layer.update()
inv = pivot.matrix_world.inverted()
for o in parts:
    mw = o.matrix_world.copy()
    o.parent = pivot
    o.matrix_parent_inverse = inv
    o.matrix_world = mw

end = 1 + round(DURATION_S * scene.render.fps)
pivot.keyframe_insert("location", index=0, frame=1)
pivot.location.x = front_x - SEPARATION_M
pivot.keyframe_insert("location", index=0, frame=end)
action = pivot.animation_data.action
action.name = TRACK + "__" + PIVOT
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for k in fc.keyframe_points:
                    k.interpolation = 'BEZIER'
                    k.handle_left_type = k.handle_right_type = 'AUTO_CLAMPED'
                fc.update()
track = pivot.animation_data.nla_tracks.new()
track.name = TRACK
strip = track.strips.new(TRACK, 1, action)
strip.name = TRACK
pivot.animation_data.action = None
pivot.location.x = front_x
scene.frame_set(1)
bpy.ops.wm.save_mainfile()
result = {"pivot": [round(c, 3) for c in pivot.location], "enfants": sorted(o.name for o in pivot.children),
          "images": [1, end], "enregistre": not bpy.data.is_dirty}
