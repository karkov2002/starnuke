# Outil hors-jeu : hiloires (gros anneaux de passage, style sous-marin) des cloisons intérieures de
# E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de Blender Lab).
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/section_coamings.py
# Quatre cloisons ont un passage de section non circulaire (rayon 1,25 m dans les axes, 1,353 m dans les diagonales,
# là où passent les angles du couloir octogonal) bordé d'un anneau métallique fin (r 1,23–1,30 m) : dans les
# diagonales, on voyait par la fente la face arrière de la cloison, que Godot ne dessine pas (paroi « trouée »).
# Cloisons : Habitation x = ±1,5 (section centrale, départ des tunnels des silos), Commande x = 10,1 et 13,1
# (section de la cupola). L'anneau fin est retiré ; une hiloire le remplace : section aux coins arrondis
# (96 segments, ombrage lisse) qui couvre les fentes, couronne de vis à tête hexagonale (acier bruni, rondelle
# inox) sur chaque face. Objets séparés « <module>_Hiloire_<x>-col » (collision concave à l'import).
# À l'Habitation, l'hiloire est plus mince et moins haute : l'anneau jaune de l'entrée des tunnels est tout près.
# Rejouable ; enregistre le .blend, ne réexporte rien.
import bpy, bmesh, math
from mathutils import Matrix, Vector

SEGMENTS = 96
BOLTS = 32
# (objet de la cloison, x du plan, demi-épaisseur, rayon intérieur, rayon extérieur, rayon des coins)
COAMINGS = (
    ("Habitation_Cloisons-col", -1.5, 0.07, 1.18, 1.40, 0.035),
    ("Habitation_Cloisons-col", 1.5, 0.07, 1.18, 1.40, 0.035),
    ("Commande_Section_Cupola-col", 10.1, 0.10, 1.17, 1.45, 0.045),
    ("Commande_Section_Cupola-col", 13.1, 0.10, 1.17, 1.45, 0.045),
)

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)


def rounded_section(r0, r1, x0, x1, c, n=6):
    """Section rectangulaire (rayon r0..r1, x0..x1) aux coins arrondis de rayon c, sens trigonométrique (r, x)."""
    pts = []
    for (cr, cx, a0) in ((r1 - c, x1 - c, 0), (r0 + c, x1 - c, 90), (r0 + c, x0 + c, 180), (r1 - c, x0 + c, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cr + c * math.cos(a), cx + c * math.sin(a)))
    return pts


def remove_thin_ring(obj, xc):
    """Retire l'anneau métallique fin (Int_Metal, r 1,23–1,30) du plan x = xc ; rend le nombre de faces retirées."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    seen, kill = set(), []
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
        if any(me.materials[g.material_index].name != "Int_Metal" for g in island):
            continue
        pts = [obj.matrix_world @ v.co for g in island for v in g.verts]
        r = [math.hypot(p.y, p.z) for p in pts]
        if all(abs(p.x - xc) < 0.06 for p in pts) and 1.2 < min(r) and max(r) < 1.32:
            kill.extend(island)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(me)
    bm.free()
    me.update()
    return len(kill)


def add_part(bm, part, matrix, material_index):
    bmesh.ops.transform(part, matrix=matrix, verts=part.verts)
    vmap = {v: bm.verts.new(v.co) for v in part.verts}
    for f in part.faces:
        bm.faces.new([vmap[v] for v in f.verts]).material_index = material_index
    part.free()


def build_coaming(name, xc, half, r0, r1, corner, collection):
    old = bpy.data.objects.get(name)
    if old:
        data = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(data)
    me = bpy.data.meshes.new(name.replace("-col", ""))
    bm = bmesh.new()
    profile = rounded_section(r0, r1, xc - half, xc + half, corner)
    loops = [[bm.verts.new((x, r * math.cos(a), r * math.sin(a))) for r, x in profile]
             for a in (2 * math.pi * k / SEGMENTS for k in range(SEGMENTS))]
    n = len(profile)
    for k in range(SEGMENTS):
        q = (k + 1) % SEGMENTS
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i])).smooth = True
    # Vis sur les deux faces planes, au milieu de la partie plane.
    r_bolt = (r0 + corner + r1 - corner) / 2 + 0.02
    for side in (-1, 1):
        axis = Matrix.Rotation(side * math.pi / 2, 4, 'Y')  # Z de la vis -> ±X
        for k in range(BOLTS):
            a = 2 * math.pi * (k + 0.5) / BOLTS
            base = Matrix.Translation((xc + side * half, r_bolt * math.cos(a), r_bolt * math.sin(a)))
            head = bmesh.new()
            bmesh.ops.create_cone(head, cap_ends=True, segments=6, radius1=0.016, radius2=0.016, depth=0.011)
            bmesh.ops.translate(head, vec=(0, 0, 0.0085), verts=head.verts)
            add_part(bm, head, base @ axis @ Matrix.Rotation(a, 4, 'Z'), 1)
            washer = bmesh.new()
            bmesh.ops.create_cone(washer, cap_ends=True, segments=20, radius1=0.023, radius2=0.023, depth=0.004)
            bmesh.ops.translate(washer, vec=(0, 0, 0.001), verts=washer.verts)
            add_part(bm, washer, base @ axis, 2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for mat in ("Int_Metal", "Int_Bras_Anodise", "Int_PC_Inox"):
        me.materials.append(bpy.data.materials[mat])
    bm.to_mesh(me)
    bm.free()
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    return len(me.polygons)


report = {}
for obj_name, xc, half, r0, r1, corner in COAMINGS:
    wall = bpy.data.objects[obj_name]
    module = obj_name.split("_")[0]
    name = "%s_Hiloire_%s-col" % (module, ("%+.1f" % xc).replace("+", "").replace("-", "m").replace(".", "_"))
    removed = remove_thin_ring(wall, xc)
    faces = build_coaming(name, xc, half, r0, r1, corner, wall.users_collection[0])
    report[name] = {"anneau_fin_retire": removed, "faces": faces}
bpy.ops.wm.save_mainfile()
result = {"hiloires": report, "enregistre": not bpy.data.is_dirty}
