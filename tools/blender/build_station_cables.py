# Outil hors-jeu : câbles, tuyaux et gaines dans les couloirs de E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab).
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -File tools/blender/build_station_cables.py
# Les couloirs ont une section octogonale ; faisceaux et tuyaux suivent les arêtes des panneaux (angles
# 22,5° + k·45° dans le plan YZ, à ~1,35 m de l'axe), posés à la surface trouvée par lancer de rayons. Un tracé
# s'interrompt devant un obstacle (écran, cuisine, casiers, niches : rayon qui ne touche pas le couloir, ou paroi
# trop proche) : le faisceau plonge alors dans la jonction des panneaux et réapparaît plus loin.
# Faisceaux de 3 à 4 câbles de couleurs différentes, légèrement ondulés, serrés par des colliers tous les 0,45 m ;
# tuyaux rigides sur pattes de fixation ; gaine de ventilation annelée orange (comme dans le module Unity de l'ISS).
# Objets <Module>_Cables (sans collision), un par module. Rejouable ; enregistre le .blend ; ne réexporte rien.
import bpy, bmesh, math
from mathutils import Matrix, Vector

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)


def material(name, color, metallic=0.0, roughness=0.6):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color, 1.0)
    return m


MATS = {
    "noir": material("Int_Cable", (0.015, 0.015, 0.016), 0.0, 0.6),
    "gris": material("Int_Cable_Gris", (0.32, 0.33, 0.35), 0.0, 0.55),
    "blanc": material("Int_Cable_Blanc", (0.82, 0.82, 0.8), 0.0, 0.5),
    "bleu": material("Int_Cable_Bleu", (0.05, 0.16, 0.5), 0.0, 0.5),
    "jaune": material("Int_Cable_Jaune", (0.8, 0.6, 0.05), 0.0, 0.5),
    "collier": material("Int_Collier", (0.88, 0.88, 0.86), 0.0, 0.5),
    "tuyau": material("Int_Tuyau", (0.72, 0.73, 0.75), 1.0, 0.32),
    "patte": material("Int_Bras_Anodise", (0.045, 0.047, 0.05), 0.85, 0.42),
    "gaine": material("Int_Gaine_Orange", (0.78, 0.22, 0.04), 0.0, 0.6),
    "manchon": material("Int_Gaine_Manchon", (0.75, 0.6, 0.15), 0.0, 0.55),
}

# Tracés : (objet, collection, x début, x fin, angle (degrés), type). Types : « faisceau », « tuyau », « gaine ».
ROUTES = (
    ("Habitation_Cables", "Int_Habitation", -4.35, -1.7, 337.5, "faisceau"),
    ("Habitation_Cables", "Int_Habitation", -4.35, -1.7, 292.5, "faisceau"),
    ("Habitation_Cables", "Int_Habitation", -4.35, -1.7, 22.5, "tuyau"),
    ("Habitation_Cables", "Int_Habitation", 1.7, 4.35, 247.5, "faisceau"),
    ("Habitation_Cables", "Int_Habitation", 1.7, 4.35, 112.5, "faisceau"),
    ("Habitation_Cables", "Int_Habitation", 1.7, 4.35, 292.5, "gaine"),
    ("Commande_Cables", "Int_Commande", 7.3, 9.95, 67.5, "faisceau"),
    ("Commande_Cables", "Int_Commande", 7.3, 9.95, 247.5, "faisceau"),
    ("Commande_Cables", "Int_Commande", 7.3, 9.95, 157.5, "tuyau"),
    ("Commande_Cables", "Int_Commande", 13.3, 15.9, 112.5, "faisceau"),
    ("Commande_Cables", "Int_Commande", 13.3, 15.9, 292.5, "faisceau"),
    ("Commande_Cables", "Int_Commande", 13.3, 15.9, 202.5, "tuyau"),
    ("Arrimage_Cables", "Int_Arrimage", -15.8, -7.4, 37.0, "faisceau"),
    ("Arrimage_Cables", "Int_Arrimage", -15.8, -7.4, 217.0, "faisceau"),
    ("Arrimage_Cables", "Int_Arrimage", -15.8, -7.4, 143.0, "tuyau"),
    ("Arrimage_Cables", "Int_Arrimage", -15.8, -7.4, 323.0, "gaine"),
)
STEP = 0.05
MIN_RUN = 0.5


class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []

    def add(self, part, key, smooth=True):
        m = MATS[key]
        if m not in self.slots:
            self.slots.append(m)
        idx = self.slots.index(m)
        vmap = {v: self.bm.verts.new(v.co) for v in part.verts}
        for f in part.faces:
            try:
                g = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            g.material_index = idx
            g.smooth = smooth
        part.free()


def tube(points, r, seg=8, radius_fn=None):
    """Tube lissé le long d'une polyligne ; radius_fn(abscisse) module le rayon (gaine annelée)."""
    pts = [Vector(p) for p in points]
    smooth = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        steps = max(2, int((p2 - p1).length / (0.006 if radius_fn else 0.03)))
        for k in range(steps):
            t = k / steps
            smooth.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    smooth.append(pts[-1])
    bm = bmesh.new()
    rings, s = [], 0.0
    a = None
    for i, p in enumerate(smooth):
        if i:
            s += (p - smooth[i - 1]).length
        tg = (smooth[min(i + 1, len(smooth) - 1)] - smooth[max(i - 1, 0)]).normalized()
        # Repère transporté parallèlement (la normale précédente projetée) : pas de vrillage du tube.
        if a is None:
            a = tg.cross(Vector((0, 0, 1)) if abs(tg.z) < 0.9 else Vector((1, 0, 0))).normalized()
        else:
            a = (a - tg * a.dot(tg)).normalized()
        b = tg.cross(a)
        rr = radius_fn(s) if radius_fn else r
        rings.append([bm.verts.new(p + rr * (math.cos(2 * math.pi * k / seg) * a + math.sin(2 * math.pi * k / seg) * b))
                      for k in range(seg)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(seg):
            q = (k + 1) % seg
            bm.faces.new((r0[k], r0[q], r1[q], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def box(center, size, axes):
    """Pavé centré, axes = (X, Y, Z) unitaires."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    m = Matrix((axes[0] * size[0], axes[1] * size[1], axes[2] * size[2])).transposed().to_4x4()
    m.translation = Vector(center)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


# Anciens câbles retirés avant le lancer de rayons (sinon ils feraient obstacle).
for name in {r[0] for r in ROUTES}:
    old = bpy.data.objects.get(name)
    if old:
        data = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(data)
bpy.context.view_layer.update()
DG = bpy.context.evaluated_depsgraph_get()


def wall(x, angle_deg):
    a = math.radians(angle_deg)
    d = Vector((0.0, math.cos(a), math.sin(a)))
    ok, loc, n, _i, ob, _m = bpy.context.scene.ray_cast(DG, Vector((x, 0.0, 0.0)), d)
    if not ok:
        return None
    good = "Couloir" in ob.name and (loc - Vector((x, 0, 0))).length > 1.2
    return loc, d, good


def runs(x0, x1, angle):
    """Portions continues de paroi dégagée : listes de (point de paroi, direction radiale)."""
    out, cur = [], []
    n = int(abs(x1 - x0) / STEP)
    for i in range(n + 1):
        x = x0 + (x1 - x0) * i / n
        w = wall(x, angle)
        if w and w[2]:
            cur.append((w[0], w[1]))
        else:
            if len(cur) * STEP >= MIN_RUN:
                out.append(cur)
            cur = []
    if len(cur) * STEP >= MIN_RUN:
        out.append(cur)
    return out


def bundle(mesh, run, seed):
    """Faisceau de câbles : 3 ou 4 câbles parallèles, ondulation douce, colliers tous les 0,45 m, plongée dans la
    jonction des panneaux aux deux bouts."""
    colors = (("gris", "noir", "blanc"), ("noir", "bleu", "gris", "blanc"), ("blanc", "gris", "jaune"))[seed % 3]
    radii = (0.0062, 0.005, 0.0056, 0.0045)
    tang = Vector((1, 0, 0))
    for k, col in enumerate(colors):
        pts = []
        for i, (p, d) in enumerate(run):
            side = d.cross(tang).normalized()
            off = (k - (len(colors) - 1) / 2) * 0.0135
            wob = 0.002 * math.sin(i * 0.9 + k * 1.7 + seed)
            pts.append(p - d * (radii[k] + 0.012 + wob) + side * off)
        p0, d0 = run[0]
        p1, d1 = run[-1]
        pts = [pts[0] + d0 * 0.06 - tang * 0.01] + pts[::3] + [pts[-1] + d1 * 0.06 + tang * 0.01]
        mesh.add(tube(pts, radii[k], 8), col)
    for i in range(0, len(run), int(0.45 / STEP)):
        p, d = run[i]
        side = d.cross(tang).normalized()
        width = 0.0135 * len(colors) + 0.01
        mesh.add(box(p - d * 0.016, (0.008, width, 0.016), (tang, side, d)), "collier", smooth=False)
        mesh.add(box(p - d * 0.004, (0.016, width + 0.012, 0.008), (tang, side, d)), "collier", smooth=False)


def pipe(mesh, run):
    """Tuyau rigide (Ø 22 mm) sur pattes de fixation tous les 0,6 m ; coudes vers la paroi aux deux bouts."""
    r = 0.011
    tang = Vector((1, 0, 0))
    pts = [p - d * (r + 0.03) for p, d in run[::2]]
    p0, d0 = run[0]
    p1, d1 = run[-1]
    pts = [p0 + d0 * 0.03, p0 - d0 * 0.012] + pts + [p1 - d1 * 0.012, p1 + d1 * 0.03]
    mesh.add(tube(pts, r, 14), "tuyau")
    for i in range(0, len(run), int(0.6 / STEP)):
        p, d = run[i]
        side = d.cross(tang).normalized()
        mesh.add(box(p - d * 0.016, (0.02, 0.012, 0.032), (tang, side, d)), "patte", smooth=False)
        mesh.add(box(p - d * (r + 0.03), (0.016, 0.03, 0.03), (tang, side, d)), "patte", smooth=False)


def duct(mesh, run):
    """Gaine de ventilation annelée orange (Ø 9 cm), manchons aux deux bouts."""
    R = 0.045
    tang = Vector((1, 0, 0))
    pts = [p - d * (R + 0.012) + d.cross(tang).normalized() * 0.01 * math.sin(i * 0.4) for i, (p, d) in
           enumerate(run[::2])]
    mesh.add(tube(pts, R, 16, radius_fn=lambda s: R + 0.0035 * math.sin(2 * math.pi * s / 0.022)), "gaine")
    for (p, d), sgn in ((run[0], 1), (run[-1], -1)):
        c = p - d * (R + 0.012)
        mesh.add(tube([c - tang * sgn * 0.02, c + tang * sgn * 0.05], R + 0.008, 16), "manchon")


meshes = {}
report = {}
for obj_name, col_name, x0, x1, angle, kind in ROUTES:
    mesh = meshes.setdefault(obj_name, (Mesh(), col_name))[0]
    found = runs(x0, x1, angle)
    report.setdefault(obj_name, []).append((angle, kind, [round(len(r) * STEP, 2) for r in found]))
    for i, run in enumerate(found):
        if kind == "faisceau":
            bundle(mesh, run, int(angle) + i)
        elif kind == "tuyau":
            pipe(mesh, run)
        else:
            duct(mesh, run)

for obj_name, (mesh, col_name) in meshes.items():
    me = bpy.data.meshes.new(obj_name)
    for m in mesh.slots:
        me.materials.append(m)
    mesh.bm.normal_update()
    mesh.bm.to_mesh(me)
    mesh.bm.free()
    me.set_sharp_from_angle(angle=math.radians(45))
    ob = bpy.data.objects.new(obj_name, me)
    bpy.data.collections[col_name].objects.link(ob)
    report[obj_name].append(("faces", len(me.polygons)))
bpy.ops.wm.save_mainfile()
result = {"cables": report, "enregistre": not bpy.data.is_dirty}
