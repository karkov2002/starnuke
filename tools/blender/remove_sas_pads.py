# Outil hors-jeu : retire de E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de Blender Lab) les
# plaquettes blanches (Int_Panneau_Blanc, 2 à 6 faces, rayon ~0,7 m) posées au milieu des sas entre modules.
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/remove_sas_pads.py
# Au repos du modèle, les écoutilles sont ouvertes et la porte vient se plaquer sur ces plaquettes, qui restaient
# cachées ; depuis que le jeu ferme les écoutilles au démarrage, elles flottaient seules dans le sas. Seules celles
# éloignées du plan d'une charnière (> FAR_M) sont retirées : la plaquette jumelle, contre le cadre à côté de la
# charnière (paumelle), est gardée. Rejouable ; enregistre le .blend, ne réexporte rien.
import bpy, bmesh, math

HINGE_PLANES = (4.605, 6.995)    # |x| des plans des écoutilles axiales
FAR_M = 0.3
OBJECTS = ("Habitation_Cloisons-col", "Commande_Cloisons-col", "Arrimage_Cloisons-col")

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
removed = {}
for name in OBJECTS:
    o = bpy.data.objects[name]
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    seen = set()
    kill = []
    for f in bm.faces:
        if f in seen:
            continue
        stack, island = [f], []
        while stack:
            g = stack.pop()
            if g in seen:
                continue
            seen.add(g)
            island.append(g)
            for e in g.edges:
                stack.extend(h for h in e.link_faces if h not in seen)
        if len(island) > 6 or any(me.materials[g.material_index].name != "Int_Panneau_Blanc" for g in island):
            continue
        pts = [o.matrix_world @ v.co for g in island for v in g.verts]
        r = [math.hypot(p.y, p.z) for p in pts]
        x = sum(abs(p.x) for p in pts) / len(pts)
        if 0.65 < min(r) and max(r) < 0.8 and min(abs(x - h) for h in HINGE_PLANES) > FAR_M:
            kill.extend(island)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    removed[name] = len(kill)
bpy.ops.wm.save_mainfile()
result = {"faces_retirees": removed, "enregistre": not bpy.data.is_dirty}
