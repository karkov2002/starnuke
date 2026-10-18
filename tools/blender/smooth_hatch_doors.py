# Outil hors-jeu : lisse la tranche des portes d'écoutille de E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab).
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/smooth_hatch_doors.py
# Chaque porte (Interactif_Ecoutille_*) est faite de cylindres facettés : disque (32 côtés), panneaux en relief sur
# les deux faces (32 côtés), plaques de manœuvre (16 côtés). Chaque cylindre (îlot de s + 2 faces et 2·s sommets) est
# reconstruit au même endroit et aux mêmes dimensions : 96 côtés (48 pour les petits), tranche arrondie (congé),
# ombrage lisse, faces planes nettes. Le reste (paumelle…) est gardé. Les maillages traités sont marqués
# (propriété « tranche_lisse ») : rejouable. Les portes des silos sont des copies de la porte Habitation_AV
# (add_missile_hatches.py) : traitées ici aussi. Enregistre le .blend, ne réexporte rien.
import bpy, bmesh, math
from mathutils import Matrix, Vector

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"


def islands(bm):
    seen = set()
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
        yield island


def cylinder_frame(island):
    """(centre, axe, rayon, demi-épaisseur, nb de côtés) si l'îlot est un cylindre fermé (éventuellement déjà
    biseauté : plusieurs rangées de sommets), sinon None. Faces planes : les deux faces à s côtés (s ≥ 8)."""
    verts = {v for f in island for v in f.verts}
    caps = [f for f in island if len(f.verts) >= 8]
    if len(caps) != 2 or len(caps[0].verts) != len(caps[1].verts):
        return None
    sides = len(caps[0].verts)
    if len(verts) % sides or len(island) != 2 + sides * (len(verts) // sides - 1):
        return None
    c0, c1 = caps[0].calc_center_median(), caps[1].calc_center_median()
    axis = (c1 - c0).normalized()
    heights = [(v.co - c0).dot(axis) for v in verts]
    center = c0 + axis * (max(heights) + min(heights)) / 2
    radius = max(((v.co - center) - axis * (v.co - center).dot(axis)).length for v in verts)
    return center, axis, radius, (max(heights) - min(heights)) / 2, sides


def rounded_cylinder(bm, center, axis, radius, half, segments, material_index):
    """Cylindre plein à tranche arrondie (congé de rayon f) : révolution du profil, faces planes en éventail."""
    f = min(half * 0.8, radius * 0.25, 0.012)
    prof = [(radius - f, -half)]
    for i in range(1, 6):
        a = -math.pi / 2 + (math.pi / 2) * i / 6
        prof.append((radius - f + f * math.cos(a), -half + f + f * math.sin(a)))
    prof.append((radius, -half + f))
    prof.append((radius, half - f))
    for i in range(1, 6):
        a = (math.pi / 2) * i / 6
        prof.append((radius - f + f * math.cos(a), half - f + f * math.sin(a)))
    prof.append((radius - f, half))
    rot = axis.to_track_quat('Z', 'Y').to_matrix()
    u, w = rot.col[0], rot.col[1]
    rings = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        radial = u * math.cos(a) + w * math.sin(a)
        rings.append([bm.verts.new(center + radial * r + axis * h) for r, h in prof])
    n = len(prof)
    faces = []
    for k in range(segments):
        q = (k + 1) % segments
        for i in range(n - 1):
            faces.append(bm.faces.new((rings[k][i], rings[q][i], rings[q][i + 1], rings[k][i + 1])))
    for end, h in ((0, -half), (n - 1, half)):
        hub = bm.verts.new(center + axis * h)
        for k in range(segments):
            q = (k + 1) % segments
            faces.append(bm.faces.new((hub, rings[q][end], rings[k][end])))
    for g in faces:
        g.material_index = material_index
        g.smooth = True
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    return len(faces)


report = {}
done_meshes = set()
for o in bpy.data.objects:
    if o.type != "MESH" or not o.name.startswith("Interactif_Ecoutille_") or o.name.endswith("-convcolonly"):
        continue
    me = o.data
    if me.name in done_meshes or me.get("tranche_lisse"):
        continue
    bm = bmesh.new()
    bm.from_mesh(me)
    rebuilt = []
    for island in list(islands(bm)):
        frame = cylinder_frame(island)
        if frame is None:
            continue
        rebuilt.append((frame, island[0].material_index))
        bmesh.ops.delete(bm, geom=island, context='FACES')
    count = 0
    for (center, axis, radius, half, sides), idx in rebuilt:
        count += rounded_cylinder(bm, center, axis, radius, half, 96 if radius > 0.3 else 48, idx)
    bm.to_mesh(me)
    bm.free()
    me.set_sharp_from_angle(angle=math.radians(40))
    if rebuilt:
        me["tranche_lisse"] = True
    me.update()
    done_meshes.add(me.name)
    report[o.name] = {"cylindres": len(rebuilt), "faces": count}
bpy.ops.wm.save_mainfile()
result = {"portes": report, "enregistre": not bpy.data.is_dirty}
