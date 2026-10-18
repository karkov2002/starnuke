# Outil hors-jeu : lisse les cadres des écoutilles axiales de E:\Blender\nuke_station.blend (Blender ouvert, extension
# MCP de Blender Lab) : Habitation AR et AV, Commande AR, Arrimage AV et écoutille cargo.
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/smooth_hatch_rings.py
# Chaque cadre a deux anneaux (métal r 0,66–0,76 m, liseré jaune r 0,76–0,80 m) modélisés en 32 segments à section
# carrée, très facettés. Ils sont remplacés, dans le maillage des cloisons, par une révolution d'une section aux coins
# arrondis (96 segments, ombrage lisse), comme ceux des écoutilles des silos (add_missile_hatches.py) : mêmes
# épaisseurs (lues sur les anneaux existants) ; le métal descend à 0,655 m pour couvrir la tranche du passage.
# Rejouable (les anneaux sont retrouvés par matériau et rayons) ; enregistre le .blend, ne réexporte rien.
import bpy, bmesh, math
from mathutils import Vector

OBJECTS = ("Habitation_Cloisons-col", "Commande_Cloisons-col", "Arrimage_Cloisons-col")
SEGMENTS = 96
# matériau -> (rayons de reconnaissance, rayons reconstruits, rayon des coins de la section)
RINGS = {"Int_Metal": ((0.65, 0.77), (0.655, 0.76), 0.03),
         "Int_Jaune": ((0.75, 0.81), (0.755, 0.80), 0.018)}


def rounded_section(r0, r1, x0, x1, c, n=5):
    """Section rectangulaire (rayon r0..r1, x0..x1) aux coins arrondis de rayon c, sens trigonométrique (r, x)."""
    pts = []
    for (cr, cx, a0) in ((r1 - c, x1 - c, 0), (r0 + c, x1 - c, 90), (r0 + c, x0 + c, 180), (r1 - c, x0 + c, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cr + c * math.cos(a), cx + c * math.sin(a)))
    return pts


assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
report = {}
for name in OBJECTS:
    o = bpy.data.objects[name]
    assert all(abs(o.matrix_world[i][j] - (1.0 if i == j else 0.0)) < 1e-6 for i in range(4) for j in range(4)), name
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    seen = set()
    kill, rebuild = [], []
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
        mats = {me.materials[g.material_index].name for g in island}
        if len(mats) != 1 or next(iter(mats)) not in RINGS:
            continue
        mat = next(iter(mats))
        (lo, hi), radii, corner = RINGS[mat]
        pts = [v.co for g in island for v in g.verts]
        r = [math.hypot(p.y, p.z) for p in pts]
        x0, x1 = min(p.x for p in pts), max(p.x for p in pts)
        if not (lo <= min(r) and max(r) <= hi and x1 - x0 < 0.3):
            continue
        kill.extend(island)
        rebuild.append((mat, island[0].material_index, radii, (round(x0, 4), round(x1, 4)), corner))
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    # Anneaux en double (Arrimage : deux copies superposées) : un seul reconstruit par position.
    done = set()
    for mat, idx, (r0, r1), (x0, x1), corner in rebuild:
        if (mat, x0, x1) in done:
            continue
        done.add((mat, x0, x1))
        profile = rounded_section(r0, r1, x0, x1, corner)
        loops = [[bm.verts.new(Vector((x, r * math.cos(a), r * math.sin(a)))) for r, x in profile]
                 for a in (2 * math.pi * k / SEGMENTS for k in range(SEGMENTS))]
        n = len(profile)
        new_faces = []
        for k in range(SEGMENTS):
            q = (k + 1) % SEGMENTS
            for i in range(n):
                j = (i + 1) % n
                g = bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i]))
                g.material_index = idx
                g.smooth = True
                new_faces.append(g)
        bmesh.ops.recalc_face_normals(bm, faces=new_faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    report[name] = {"faces_retirees": len(kill), "anneaux": sorted("%s %.2f..%.2f" % (m, a, b) for m, a, b in done)}
bpy.ops.wm.save_mainfile()
result = {"cadres": report, "enregistre": not bpy.data.is_dirty}
