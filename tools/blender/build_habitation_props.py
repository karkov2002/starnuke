# Outil hors-jeu : accessoires souples du module Habitation dans E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab), d'après la cuisine de l'ISS (photo de Thomas Pesquet) :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -File tools/blender/build_habitation_props.py
# - Interactif_Couchette (maillage remplacé, nom et extras gardés) : matelas molletonné, sac de couchage matelassé à
#   coins doux (canaux de rembourrage, col roulé, fermeture à glissière), oreiller, deux sangles de maintien à boucle ;
# - Habitation_Sacs (maillage remplacé) : sacs de transfert souples type CTB (toile blanche, pastilles velcro bleues,
#   étiquette, poignée, glissière, sandow et crochets), aux places des anciens sacs ;
# - équipements de la cuisine (maillages remplacés, noms et extras gardés) : Interactif_Rechauffeur (mallette en
#   aluminium : couvercle, joint, loquets, charnière, poignée, panneau de commande, câble), Interactif_Distributeur_Eau
#   (PWD : boîtier, écran, clavier, repères chaud / ambiant, sortie à aiguille, flexible), Habitation_Cuisine-col
#   (contenants souples à rabat et sangles, boîtes repas en plastique sous sandow, table de repas au plafond : plateau,
#   rails, sandows, velcro, couverts) ;
# - Habitation_Cuisine_Accessoires (nouvel objet) : sachets repas en aluminium, poches à boire avec paille et pince,
#   filet garni, bouteilles de condiments tenues par un sandow, rouleau d'adhésif.
# Tous les volumes souples partent d'une boîte aux coins arrondis maillée finement (soft_box), puis gonflée,
# matelassée ou froissée. Les objets sont posés sur les parois par lancer de rayons. Rejouable ; enregistre le .blend ;
# ne réexporte rien (export_station.py attend le feu vert de l'utilisateur).
import bpy, bmesh, math
from mathutils import Matrix, Vector

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)
OWN = ("Interactif_Couchette", "Habitation_Sacs", "Habitation_Cuisine_Accessoires")


# ------------------------------------------------------------------------------------------------ matériaux
def material(name, color, metallic=0.0, roughness=0.8):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color, 1.0)
    return m


MATS = {
    "couchage": material("Int_Couchage", (0.035, 0.06, 0.15), 0.0, 0.95),
    "doublure": material("Int_Couchage_Doublure", (0.32, 0.37, 0.45), 0.0, 0.95),
    "matelas": material("Int_Matelas", (0.52, 0.54, 0.57), 0.0, 0.92),
    "oreiller": material("Int_Oreiller", (0.82, 0.82, 0.8), 0.0, 0.9),
    "sangle": material("Int_Sangle_Noire", (0.02, 0.02, 0.022), 0.0, 0.8),
    "boucle": material("Int_Boucle", (0.55, 0.56, 0.58), 1.0, 0.35),
    "sangle_ctb": material("Int_Sangle_CTB", (0.6, 0.6, 0.58), 0.0, 0.85),
    "ctb": material("Int_Sac_CTB", (0.80, 0.80, 0.78), 0.0, 0.92),
    "velcro": material("Int_Velcro_Bleu", (0.04, 0.09, 0.30), 0.0, 0.97),
    "etiquette": material("Int_Etiquette", (0.93, 0.93, 0.9), 0.0, 0.6),
    "encre": material("Int_Encre", (0.03, 0.03, 0.03), 0.0, 0.6),
    "glissiere": material("Int_Glissiere", (0.08, 0.08, 0.09), 0.3, 0.5),
    "sandow": material("Int_Sandow", (0.06, 0.12, 0.42), 0.0, 0.7),
    "crochet": material("Int_Crochet", (0.6, 0.6, 0.62), 1.0, 0.3),
    "mylar": material("Int_Mylar", (0.82, 0.82, 0.84), 0.85, 0.38),
    "sachet": material("Int_Sachet", (0.86, 0.88, 0.9), 0.0, 0.35),
    "paille": material("Int_Paille", (0.9, 0.9, 0.92), 0.0, 0.3),
    "pince": material("Int_Pince", (0.75, 0.08, 0.06), 0.0, 0.5),
    "filet": material("Int_Filet", (0.9, 0.9, 0.88), 0.0, 0.8),
    "rouge": material("Int_Emballage_Rouge", (0.7, 0.05, 0.04), 0.0, 0.45),
    "jaune": material("Int_Emballage_Jaune", (0.85, 0.65, 0.05), 0.0, 0.45),
    "vert": material("Int_Emballage_Vert", (0.25, 0.5, 0.15), 0.0, 0.45),
    "sauce": material("Int_Sauce", (0.32, 0.1, 0.03), 0.0, 0.25),
    "moutarde": material("Int_Moutarde", (0.7, 0.55, 0.08), 0.0, 0.25),
    "piment": material("Int_Piment", (0.6, 0.06, 0.02), 0.0, 0.25),
    "bouchon": material("Int_Bouchon", (0.9, 0.9, 0.88), 0.0, 0.4),
    "adhesif": material("Int_Adhesif", (0.88, 0.88, 0.86), 0.0, 0.55),
    "carton": material("Int_Carton", (0.55, 0.45, 0.32), 0.0, 0.9),
    "alu": material("Int_Alu_Brosse", (0.74, 0.75, 0.77), 0.55, 0.42),
    "alu_sombre": material("Int_Alu_Sombre", (0.33, 0.34, 0.36), 1.0, 0.4),
    "pwd": material("Int_PWD", (0.74, 0.75, 0.76), 0.0, 0.5),
    "lcd": material("Int_LCD", (0.03, 0.07, 0.05), 0.0, 0.15),
    "bouton": material("Int_Bouton", (0.07, 0.07, 0.075), 0.0, 0.45),
    "repere_rouge": material("Int_Repere_Rouge", (0.7, 0.06, 0.04), 0.0, 0.5),
    "repere_bleu": material("Int_Repere_Bleu", (0.05, 0.25, 0.65), 0.0, 0.5),
    "flexible": material("Int_Flexible", (0.85, 0.86, 0.88), 0.0, 0.35),
    "table": material("Int_Table_Verte", (0.05, 0.1, 0.07), 0.0, 0.55),
    "boite_rouge": material("Int_Boite_Rouge", (0.62, 0.08, 0.05), 0.0, 0.35),
    "boite_bleue": material("Int_Boite_Bleue", (0.12, 0.3, 0.6), 0.0, 0.35),
    "couvercle": material("Int_Couvercle", (0.86, 0.86, 0.84), 0.0, 0.4),
}
# Matériaux d'origine de la station (texturés ou émissifs) : réutilisés tels quels, jamais réécrits.
MATS["voyant"] = bpy.data.materials["Int_Voyant_Vert"]
MATS["panneau"] = bpy.data.materials["Int_Panneau_Blanc"]
MATS["noir"] = bpy.data.materials["Int_Noir"]


# ------------------------------------------------------------------------------------------------ géométrie
class Mesh:
    """Accumulateur de pièces (bmesh) à matériaux multiples."""

    def __init__(self):
        self.bm = bmesh.new()
        self.slots = []

    def add(self, part, key, matrix=Matrix(), smooth=True):
        m = MATS[key]
        if m not in self.slots:
            self.slots.append(m)
        idx = self.slots.index(m)
        bmesh.ops.transform(part, matrix=matrix, verts=part.verts)
        vmap = {v: self.bm.verts.new(v.co) for v in part.verts}
        for f in part.faces:
            try:
                g = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            g.material_index = idx
            g.smooth = smooth
        part.free()

    def write(self, obj_name, collection=None):
        obj = bpy.data.objects.get(obj_name)
        me = bpy.data.meshes.new(obj_name)
        for m in self.slots:
            me.materials.append(m)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.set_sharp_from_angle(angle=math.radians(50))
        if obj is None:
            obj = bpy.data.objects.new(obj_name, me)
            (collection or bpy.data.collections["Int_Habitation"]).objects.link(obj)
        else:
            old = obj.data
            obj.data = me
            if old.users == 0:
                bpy.data.meshes.remove(old)
        obj.matrix_world = Matrix()
        return obj


def soft_map(half, r, deform=None):
    """Fonction qui envoie un point de la boîte (demi-dimensions half) sur la surface arrondie (rayon r) puis la
    déforme : deform(p, n, t) avec n la normale et t les coordonnées normalisées (-1..1)."""
    hv = Vector(half)
    r = min(r, min(half))

    def f(p):
        inner = Vector([max(-(h - r), min(h - r, p[i])) for i, h in enumerate(hv)])
        d = p - inner
        n = d.normalized() if d.length > 1e-9 else Vector((0, 0, 1))
        q = inner + n * r
        if deform:
            t = Vector([q[i] / hv[i] for i in range(3)])
            q = deform(q, n, t)
        return q
    return f


def soft_box(half, r, cell=0.02, deform=None):
    """Boîte aux arêtes et coins arrondis (rayon r), maillée finement, éventuellement déformée."""
    bm = bmesh.new()
    counts = [max(2, math.ceil(2 * h / cell)) for h in half]
    for axis in range(3):
        b, c = [i for i in range(3) if i != axis]
        for s in (-1, 1):
            nb, nc = counts[b], counts[c]
            grid = []
            for i in range(nb + 1):
                row = []
                for j in range(nc + 1):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = s * half[axis]
                    p[b] = -half[b] + 2 * half[b] * i / nb
                    p[c] = -half[c] + 2 * half[c] * j / nc
                    row.append(bm.verts.new(p))
                grid.append(row)
            for i in range(nb):
                for j in range(nc):
                    bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    fmap = soft_map(half, r, deform)
    for v in bm.verts:
        v.co = fmap(Vector(v.co))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def puff(amount, axes=(0, 1, 2), exponent=1.0):
    """Gonflement des faces : maximal au centre de chaque face, nul sur les arêtes."""
    def d(q, n, t):
        a = max(range(3), key=lambda i: abs(n[i]))
        if a not in axes:
            return q
        k = 1.0
        for i in range(3):
            if i != a:
                k *= max(0.0, 1.0 - t[i] * t[i])
        return q + n * amount * (k ** exponent)
    return d


def chain(*fns):
    def d(q, n, t):
        for fn in fns:
            q = fn(q, n, t)
        return q
    return d


def crinkle(amount, seed=1.0):
    """Froissé (sachets) : somme de sinus de directions et phases variées."""
    def d(q, n, t):
        s = 0.0
        for k in range(5):
            a = seed * 1.7 + k * 2.1
            s += math.sin((q.x * math.cos(a) + q.z * math.sin(a)) * (60 + 23 * k) + seed * k)
        return q + n * amount * s / 5
    return d


def wrinkles(amount, seed=0.3):
    def d(q, n, t):
        s = math.sin(q.x * 31 + seed) * math.sin(q.z * 23 + 2 * seed) + 0.5 * math.sin(q.y * 41 + q.x * 17)
        return q + n * amount * s
    return d


def cylinder(r, depth, seg=24, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    return bm


def revolve(profile, seg=32):
    """Solide de révolution autour de Z d'un profil (r, z) ouvert (les extrémités sur l'axe ferment)."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z))
              for k in range(seg)] for r, z in profile]
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            q = (k + 1) % seg
            bm.faces.new((a[k], a[q], b[q], b[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.faces.ensure_lookup_table()
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def tube(points, r, seg=10):
    """Tube lissé (Catmull-Rom) le long d'une polyligne, extrémités fermées."""
    pts = [Vector(p) for p in points]
    smooth = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        steps = max(2, int((p2 - p1).length / 0.02))
        for k in range(steps):
            t = k / steps
            smooth.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    smooth.append(pts[-1])
    bm = bmesh.new()
    rings = []
    a = None
    for i, p in enumerate(smooth):
        tg = (smooth[min(i + 1, len(smooth) - 1)] - smooth[max(i - 1, 0)]).normalized()
        # Repère transporté parallèlement (la normale précédente projetée) : pas de vrillage du tube.
        if a is None:
            a = tg.cross(Vector((0, 0, 1)) if abs(tg.z) < 0.9 else Vector((1, 0, 0))).normalized()
        else:
            a = (a - tg * a.dot(tg)).normalized()
        b = tg.cross(a)
        rings.append([bm.verts.new(p + r * (math.cos(2 * math.pi * k / seg) * a + math.sin(2 * math.pi * k / seg) * b))
                      for k in range(seg)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(seg):
            q = (k + 1) % seg
            bm.faces.new((r0[k], r0[q], r1[q], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ribbon(points, side, width, thick):
    """Sangle plate : ruban de largeur width (direction side) et d'épaisseur thick le long d'une polyligne."""
    bm = bmesh.new()
    side = Vector(side).normalized()
    pts = [Vector(p) for p in points]
    rows = []
    for i, p in enumerate(pts):
        tg = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = tg.cross(side).normalized()
        rows.append([bm.verts.new(p + side * sw * width / 2 + nrm * st * thick / 2)
                     for sw, st in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for a, b in zip(rows, rows[1:]):
        for k in range(4):
            q = (k + 1) % 4
            bm.faces.new((a[k], a[q], b[q], b[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def frame(origin, x_axis, y_axis):
    """Repère : X, Y donnés (Y = normale sortante de la paroi), Z = X × Y."""
    x = Vector(x_axis).normalized()
    y = Vector(y_axis).normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


# ------------------------------------------------------------------------------------------------ équipements
# Construits avant les accessoires : sachets et poches se posent ensuite sur leurs surfaces (lancer de rayons).
# Repère monde : paroi de la cuisine à y ≈ 1,25 (faces avant vers −Y), plafond à z ≈ 1,25.
T = Matrix.Translation


def rounded_rect_path(cx, cz, hw, hh, r, y, n=6):
    """Contour d'un rectangle aux coins arrondis dans un plan y = cste (x, z)."""
    pts = []
    for (ox, oz, a0) in ((hw - r, hh - r, 0), (-(hw - r), hh - r, 90), (-(hw - r), -(hh - r), 180),
                         (hw - r, -(hh - r), 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append(Vector((cx + ox + r * math.cos(a), y, cz + oz + r * math.sin(a))))
    pts.append(pts[0])
    return pts


def build_food_warmer():
    """Réchauffeur de repas : mallette en aluminium (comme le « food warmer » de l'ISS), fermée."""
    b = Mesh()
    cx, cy, cz = -3.325, 1.14, 0.0
    hx, hy, hz = 0.31, 0.105, 0.26
    front = cy - hy
    b.add(soft_box((hx, hy, hz), 0.028, 0.02, chain(puff(0.002), wrinkles(0.0004))), "alu", T((cx, cy, cz)))
    # Joint du couvercle (gorge sombre tout autour de la face avant) et cadre du couvercle.
    b.add(tube(rounded_rect_path(cx, cz, hx - 0.012, hz - 0.012, 0.02, front + 0.004), 0.0035, 6), "noir")
    b.add(tube(rounded_rect_path(cx, cz, hx - 0.04, hz - 0.04, 0.03, front - 0.001), 0.0025, 6), "alu_sombre")
    # Panneau de commande : bandeau noir, afficheur, voyant vert, deux boutons, plaque signalétique.
    b.add(soft_box((0.2, 0.004, 0.032), 0.003, 0.01), "noir", T((cx + 0.02, front - 0.003, 0.185)))
    b.add(soft_box((0.05, 0.002, 0.018), 0.002, 0.008), "lcd", T((cx - 0.08, front - 0.007, 0.185)))
    b.add(soft_box((0.008, 0.004, 0.008), 0.003, 0.004), "voyant", T((cx + 0.04, front - 0.008, 0.185)))
    for bx in (0.1, 0.15):
        b.add(cylinder(0.011, 0.008, 20), "bouton", T((cx + bx, front - 0.008, 0.185)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(soft_box((0.06, 0.001, 0.022), 0.002, 0.01), "etiquette", T((cx, front - 0.002, -0.08)))
    # Loquets de fermeture et charnière en bas de la face avant.
    for lx in (-0.19, 0.19):
        b.add(soft_box((0.025, 0.012, 0.035), 0.006, 0.006), "alu_sombre", T((cx + lx, front - 0.008, -0.2)))
        b.add(cylinder(0.006, 0.05, 12), "alu", T((cx + lx, front - 0.016, -0.2)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    b.add(cylinder(0.009, 2 * hx - 0.08, 16), "alu_sombre", T((cx, front + 0.004, -hz + 0.006)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    # Poignée de transport sur le dessus.
    h = [Vector((cx - 0.12, cy - 0.02, hz + 0.0)), Vector((cx - 0.1, cy - 0.02, hz + 0.04)),
         Vector((cx + 0.1, cy - 0.02, hz + 0.04)), Vector((cx + 0.12, cy - 0.02, hz + 0.0))]
    b.add(tube(h, 0.009, 12), "noir")
    for sx in (-0.12, 0.12):
        b.add(soft_box((0.016, 0.016, 0.01), 0.004, 0.006), "alu_sombre", T((cx + sx, cy - 0.02, hz + 0.004)))
    # Câble d'alimentation : sort du flanc droit et rentre dans la paroi.
    c0 = Vector((cx + hx, cy + 0.04, -0.1))
    b.add(tube([c0, c0 + Vector((0.04, 0.0, -0.02)), c0 + Vector((0.07, 0.05, -0.08)), Vector((cx + hx + 0.09, 1.26, -0.2))],
               0.005, 8), "noir")
    return b


def build_water_dispenser():
    """Distributeur d'eau potable (PWD de l'ISS) : boîtier, écran, clavier, sortie à aiguille, flexible."""
    b = Mesh()
    cx, cy, cz = -2.55, 1.135, 0.03
    hx, hy, hz = 0.19, 0.105, 0.265
    front = cy - hy
    b.add(soft_box((hx, hy, hz), 0.03, 0.02, puff(0.002)), "pwd", T((cx, cy, cz)))
    # Façade : cadre sombre, écran LCD, clavier 2 × 3, repères chaud (rouge) et ambiant (bleu).
    b.add(soft_box((0.15, 0.004, 0.12), 0.012, 0.01), "alu_sombre", T((cx, front - 0.002, cz + 0.1)))
    b.add(soft_box((0.1, 0.002, 0.035), 0.004, 0.008), "lcd", T((cx, front - 0.007, cz + 0.16)))
    for i in range(3):
        for j in range(2):
            b.add(cylinder(0.012, 0.01, 20), "bouton",
                  T((cx - 0.06 + 0.06 * i, front - 0.009, cz + 0.085 - 0.045 * j)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(soft_box((0.018, 0.0015, 0.006), 0.002, 0.004), "repere_rouge", T((cx - 0.06, front - 0.007, cz + 0.115)))
    b.add(soft_box((0.018, 0.0015, 0.006), 0.002, 0.004), "repere_bleu", T((cx, front - 0.007, cz + 0.115)))
    b.add(soft_box((0.05, 0.001, 0.015), 0.002, 0.006), "etiquette", T((cx + 0.08, front - 0.002, cz - 0.04)))
    # Bloc de sortie en bas : saillie, raccord rapide et aiguille de remplissage pointée vers le bas.
    ny = front - 0.04
    b.add(soft_box((0.06, 0.04, 0.045), 0.015, 0.01), "alu_sombre", T((cx, ny, cz - 0.17)))
    b.add(cylinder(0.014, 0.03, 20), "alu", T((cx, ny - 0.01, cz - 0.23)))
    b.add(cylinder(0.009, 0.012, 16), "noir", T((cx, ny - 0.01, cz - 0.25)))
    b.add(cylinder(0.003, 0.05, 10, r2=0.0015), "alu", T((cx, ny - 0.01, cz - 0.28)))
    # Flexible : du flanc gauche au bloc de sortie, en boucle.
    h0 = Vector((cx - hx, cy - 0.02, cz - 0.12))
    b.add(tube([h0, h0 + Vector((-0.05, -0.03, -0.02)), h0 + Vector((-0.06, -0.09, -0.08)),
                Vector((cx - 0.06, ny - 0.03, cz - 0.17))], 0.007, 10), "flexible")
    return b


def build_galley():
    """Rangements de la cuisine et table de repas (objet Habitation_Cuisine-col, collision concave)."""
    b = Mesh()
    # Contenants souples (ex-boîtes grises) contre la paroi : toile, rabat à velcro, deux sangles à boucle.
    for cx in (-2.075, -1.775):
        cy, hz = 1.19, 0.39
        b.add(soft_box((0.12, 0.055, hz), 0.03, 0.02, chain(puff(0.01), wrinkles(0.0015, cx * 7))), "ctb", T((cx, cy, 0.0)))
        b.add(soft_box((0.115, 0.008, 0.07), 0.006, 0.012, puff(0.003)), "ctb", T((cx, cy - 0.065, hz - 0.08)))
        b.add(soft_box((0.09, 0.002, 0.012), 0.002, 0.006), "velcro", T((cx, cy - 0.074, hz - 0.13)))
        b.add(soft_box((0.05, 0.001, 0.03), 0.002, 0.006), "etiquette", T((cx, cy - 0.066, -0.05)))
        for sz in (-0.22, 0.12):
            path = [Vector((cx - 0.125, 1.25, sz)), Vector((cx - 0.128, cy - 0.03, sz)), Vector((cx - 0.1, cy - 0.066, sz)),
                    Vector((cx + 0.1, cy - 0.066, sz)), Vector((cx + 0.128, cy - 0.03, sz)), Vector((cx + 0.125, 1.25, sz))]
            b.add(ribbon(path, (0, 0, 1), 0.028, 0.003), "sangle", smooth=False)
            b.add(soft_box((0.016, 0.005, 0.018), 0.003, 0.004), "boucle", T((cx, cy - 0.07, sz)))
    # Boîtes repas en plastique (ex-blocs rouges et bleus) sur la paroi diagonale haute, couvercle et étiquette,
    # retenues par un sandow.
    n = Vector((0, -1, -1)).normalized()       # normale de la paroi diagonale (vers l'axe)
    up = Vector((0, -1, 1)).normalized()       # le long de la paroi
    surface = Vector((0, 0.933, 0.933))        # paroi diagonale à 1,32 m de l'axe
    axes = Matrix((Vector((1, 0, 0)), -n, up)).transposed()  # X, Y (vers la paroi), Z (le long)
    for i, (cx, mat) in enumerate(((-3.71, "boite_rouge"), (-3.46, "boite_bleue"), (-3.21, "boite_rouge"),
                                   (-2.96, "boite_bleue"))):
        hd = 0.07
        center = Vector((cx, 0, 0)) + surface + n * (hd + 0.002)
        m = T(center) @ axes.to_4x4()
        b.add(soft_box((0.088, hd, 0.098), 0.012, 0.012), "couvercle", m)
        b.add(soft_box((0.092, 0.012, 0.102), 0.008, 0.012), mat, m @ T((0, -hd + 0.006, 0)))
        b.add(soft_box((0.04, 0.001, 0.025), 0.002, 0.006), "etiquette", m @ T((0, -hd - 0.007, 0.03)))
    a = Vector((-3.84, 0, 0)) + surface + n * 0.005
    c = Vector((-2.83, 0, 0)) + surface + n * 0.005
    mid = (a + c) / 2 + n * 0.16
    b.add(tube([a, a.lerp(mid, 0.3) + n * 0.03, mid, c.lerp(mid, 0.3) + n * 0.03, c], 0.0045, 8), "sandow")
    for p in (a, c):
        b.add(cylinder(0.008, 0.012, 12), "crochet", T(p) @ n.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    # Table de repas au plafond : support blanc, plateau vert sombre, rails en aluminium, sandows, velcro, couverts.
    tx, thx, thy = -2.8, 1.08, 0.42
    b.add(soft_box((thx, thy, 0.055), 0.02, 0.03), "panneau", T((tx, 0.0, 1.19)))
    b.add(soft_box((thx - 0.02, thy - 0.02, 0.016), 0.012, 0.025), "table", T((tx, 0.0, 1.118)))
    for sy in (-1, 1):
        y = sy * (thy - 0.005)
        b.add(tube([Vector((tx - thx + 0.03, y, 1.095)), Vector((tx + thx - 0.03, y, 1.095))], 0.01, 14), "alu")
        for k in range(5):
            x = tx - thx + 0.08 + k * (2 * thx - 0.16) / 4
            b.add(soft_box((0.012, 0.012, 0.012), 0.004, 0.006), "alu_sombre", T((x, y, 1.105)))
    for bx in (-0.7, 0.0, 0.7):
        x = tx + bx
        b.add(tube([Vector((x, -thy + 0.005, 1.093)), Vector((x + 0.02, -0.15, 1.085)), Vector((x + 0.02, 0.15, 1.085)),
                    Vector((x, thy - 0.005, 1.093))], 0.0045, 8), "sandow")
    for (vx, vy) in ((-0.35, -0.2), (-0.35, 0.2), (0.35, -0.2), (0.35, 0.2), (0.9, 0.0)):
        b.add(soft_box((0.05, 0.02, 0.0012), 0.003, 0.01), "velcro", T((tx + vx, vy, 1.101)))
    # Couverts sous le sandow central : cuillère, fourchette, ciseaux.
    x0 = tx + 0.02
    b.add(ribbon([Vector((x0 - 0.01, -0.12, 1.098)), Vector((x0 - 0.01, 0.02, 1.098))], (1, 0, 0), 0.012, 0.0025), "alu", smooth=False)
    b.add(soft_box((0.02, 0.028, 0.004), 0.004, 0.006), "alu", T((x0 - 0.01, 0.045, 1.097)))
    b.add(ribbon([Vector((x0 + 0.04, -0.12, 1.098)), Vector((x0 + 0.04, 0.03, 1.098))], (1, 0, 0), 0.01, 0.0025), "alu", smooth=False)
    for k in range(4):
        b.add(ribbon([Vector((x0 + 0.033 + 0.0045 * k, 0.03, 1.098)), Vector((x0 + 0.033 + 0.0045 * k, 0.07, 1.098))],
                     (1, 0, 0), 0.0025, 0.002), "alu", smooth=False)
    sx = tx + 0.3
    for sy in (-1, 1):
        ring = [Vector((sx + 0.018 * math.cos(a), sy * 0.02 - 0.09 + 0.012 * math.sin(a), 1.098)) for a in
                (2 * math.pi * k / 16 for k in range(17))]
        b.add(tube(ring, 0.003, 6), "repere_rouge")
        b.add(ribbon([Vector((sx, sy * 0.012 - 0.075, 1.098)), Vector((sx + sy * 0.004, 0.03, 1.098))], (1, 0, 0), 0.008, 0.002),
              "alu", smooth=False)
    return b


build_galley().write("Habitation_Cuisine-col")
build_food_warmer().write("Interactif_Rechauffeur")
build_water_dispenser().write("Interactif_Distributeur_Eau")


# ------------------------------------------------------------------------------------------------ lancer de rayons
hidden = []
for name in OWN:
    o = bpy.data.objects.get(name)
    if o and not o.hide_viewport:
        o.hide_viewport = True
        hidden.append(o)
bpy.context.view_layer.update()
DG = bpy.context.evaluated_depsgraph_get()


def hit(origin, direction):
    ok, loc, n, _i, ob, _m = bpy.context.scene.ray_cast(DG, Vector(origin), Vector(direction).normalized())
    if not ok:
        raise RuntimeError("rien touché depuis %s vers %s" % (origin, direction))
    return loc, n.normalized(), ob.name


# ------------------------------------------------------------------------------------------------ couchette
def build_couchette():
    b = Mesh()
    # Repère du lit (monde) : longueur selon X (tête vers +X), paroi du fond à y = 1,88, face visible vers −Y.
    def at(x, y, z):
        return Matrix.Translation((x, y, z))

    # Matelas molletonné, plaqué contre la paroi.
    b.add(soft_box((0.80, 0.06, 0.295), 0.05, 0.02, chain(puff(0.012), wrinkles(0.0015))), "matelas",
          at(2.775, 1.815, 0.0))
    # Sac de couchage : volume gonflé, canaux de rembourrage tous les 0,15 m (coutures transversales), plis.
    x0 = 2.655
    def quilt(q, n, t):
        if n.y < -0.4:  # face avant
            g = abs(math.sin(math.pi * (q.x - (-0.0)) / 0.15))
            q = q + n * 0.028 * (g ** 0.7) * max(0.0, 1 - t.z * t.z) ** 0.5
        return q
    b.add(soft_box((0.66, 0.05, 0.255), 0.05, 0.016, chain(puff(0.012), quilt, wrinkles(0.002, 1.1))), "couchage",
          at(x0, 1.705, 0.0))
    # Col roulé (doublure claire) à l'ouverture, côté tête.
    b.add(soft_box((0.045, 0.06, 0.245), 0.044, 0.015, chain(puff(0.01), wrinkles(0.0015, 2.0))), "doublure",
          at(3.33, 1.70, 0.0))
    # Oreiller.
    def dimple(q, n, t):
        if n.y < -0.4:
            q = q + n * (-0.012) * math.exp(-((t.x * 1.6) ** 2 + (t.z * 1.3) ** 2))
        return q
    b.add(soft_box((0.10, 0.045, 0.185), 0.044, 0.014, chain(puff(0.03), dimple)), "oreiller", at(3.47, 1.735, 0.0))
    # Fermeture à glissière le long du bord haut du sac, avec son curseur.
    zip_pts = [(2.02, 1.665, 0.226), (2.6, 1.662, 0.232), (3.25, 1.665, 0.228)]
    b.add(tube(zip_pts, 0.004, 8), "glissiere")
    b.add(soft_box((0.012, 0.006, 0.008), 0.003, 0.004), "boucle", at(3.1, 1.66, 0.236))
    b.add(soft_box((0.004, 0.003, 0.02), 0.0015, 0.003), "boucle", at(3.1, 1.655, 0.212))
    # Sangles de maintien : passent devant le sac, contournent le lit et rentrent dans la paroi ; boucle au milieu.
    for xs in (2.32, 3.02):
        path = [(xs, 1.88, -0.33), (xs, 1.78, -0.335), (xs, 1.69, -0.315), (xs, 1.635, -0.25), (xs, 1.618, -0.12),
                (xs, 1.613, 0.0), (xs, 1.618, 0.12), (xs, 1.635, 0.25), (xs, 1.69, 0.315), (xs, 1.78, 0.335),
                (xs, 1.88, 0.33)]
        b.add(ribbon(path, (1, 0, 0), 0.042, 0.004), "sangle", smooth=False)
        b.add(soft_box((0.03, 0.006, 0.022), 0.004, 0.004), "boucle", at(xs, 1.606, 0.0))
        b.add(soft_box((0.022, 0.003, 0.012), 0.002, 0.003), "sangle", at(xs, 1.599, 0.0))
    return b


# ------------------------------------------------------------------------------------------------ sacs CTB
def ctb_bag(b, m, half, seed=0.0, label=True):
    """Sac de transfert souple (repère local : Z = dessus) : toile gonflée, pastilles velcro, étiquette, poignée,
    glissière autour du rabat."""
    hx, hy, hz = half
    deform = chain(puff(0.012), wrinkles(0.002, seed))
    fmap = soft_map(half, 0.03, deform)
    b.add(soft_box(half, 0.03, 0.02, deform), "ctb", m)
    top = lambda u, v: fmap(Vector((u * hx, v * hy, hz)))
    # Bandes velcro bleues le long d'un bord du rabat (fermeture, accroche des étiquettes).
    for su in (-0.55, 0.55):
        p = top(su, -0.78)
        b.add(soft_box((0.05, 0.012, 0.0015), 0.004, 0.01), "velcro", m @ Matrix.Translation(p))
    if label:
        p = fmap(Vector((0.0, -hy, -0.15 * hz)))
        lm = m @ Matrix.Translation(p + Vector((0, -0.002, 0))) @ Matrix.Rotation(math.pi / 2, 4, 'X')
        b.add(soft_box((min(0.07, hx * 0.5), 0.032, 0.0012), 0.003, 0.01), "etiquette", lm)
        for k in range(3):
            w = (0.045, 0.03, 0.05)[k]
            b.add(soft_box((w, 0.0035, 0.0008), 0.0008, 0.004), "encre",
                  lm @ Matrix.Translation((-0.012 + 0.006 * k, 0.016 - 0.012 * k, 0.0012)))
    # Glissière du rabat (pourtour du dessus) et poignée cousue.
    # Glissière du rabat : suit le pourtour du dessus, juste à l'intérieur des arêtes.
    ring = []
    for k in range(65):
        a = 2 * math.pi * k / 64
        c, s = math.cos(a), math.sin(a)
        k_sq = max(abs(c), abs(s))  # carré arrondi
        ring.append(top(c / k_sq * 0.86, s / k_sq * 0.84) + Vector((0, 0, 0.0025)))
    b.add(tube(ring, 0.0035, 6), "glissiere", m)
    # Poignée cousue sur la tranche (côté +X), et une sangle de portage sur le dessus.
    side = lambda v, w: fmap(Vector((hx, v * hy, w * hz)))
    h0, h1 = side(-0.4, 0.1), side(0.4, 0.1)
    handle = [h0, h0.lerp(h1, 0.2) + Vector((0.03, 0, 0)), h0.lerp(h1, 0.5) + Vector((0.038, 0, 0)),
              h0.lerp(h1, 0.8) + Vector((0.03, 0, 0)), h1]
    b.add(ribbon(handle, (0, 0, 1), 0.028, 0.004), "sangle_ctb", m, smooth=False)
    strap = [top(-0.98, 0.25) + Vector((0, 0, 0.002)), top(-0.5, 0.25) + Vector((0, 0, 0.003)),
             top(0.0, 0.25) + Vector((0, 0, 0.003)), top(0.5, 0.25) + Vector((0, 0, 0.003)),
             top(0.98, 0.25) + Vector((0, 0, 0.002))]
    b.add(ribbon(strap, (0, 1, 0), 0.026, 0.003), "sangle_ctb", m, smooth=False)


def bungee(b, a, c, over, hook_normal):
    """Sandow tendu de a à c en passant par over ; crochets aux deux bouts."""
    a, c, over = Vector(a), Vector(c), Vector(over)
    b.add(tube([a, a.lerp(over, 0.5) + (over - (a + c) / 2) * 0.3, over, c.lerp(over, 0.5) + (over - (a + c) / 2) * 0.3,
                c], 0.0045, 8), "sandow")
    for p in (a, c):
        b.add(cylinder(0.008, 0.012, 12), "crochet",
              Matrix.Translation(p) @ Vector(hook_normal).to_track_quat('Z', 'Y').to_matrix().to_4x4())


def build_bags():
    b = Mesh()
    placements = []
    # Sols (paroi −Z) et plafond (+Z) des anciennes places (x −4,0 et x 2,0), touchés par rayon depuis l'axe.
    for x, zdir, stack in ((-4.0, -1, 2), (2.0, -1, 1), (2.0, 1, 1)):
        loc, n, _ = hit((x, 0.0, 0.0), (0, 0, zdir))
        placements.append((x, loc, n, stack))
    seeds = iter((0.3, 1.7, 2.9, 4.1, 5.3, 6.7))
    for x, loc, n, stack in placements:
        up = n  # normale de la paroi, vers l'intérieur
        half = (0.25, 0.20, 0.115)
        m = frame(loc + up * (half[2] + 0.003), (1, 0, 0), (0, 1, 0)) if up.z > 0 else \
            frame(loc + up * (half[2] + 0.003), (1, 0, 0), (0, -1, 0))
        ctb_bag(b, m, half, next(seeds))
        top_center = loc + up * (2 * half[2] + 0.01)
        if stack > 1:
            half2 = (0.16, 0.13, 0.085)
            m2 = m @ Matrix.Translation((0.04, -0.02, half[2] + half2[2] + 0.004)) @ Matrix.Rotation(0.22, 4, 'Z')
            ctb_bag(b, m2, half2, next(seeds))
            top_center = top_center + up * (2 * half2[2])
        # Sandow en travers, accroché à la paroi de part et d'autre.
        side = Vector((0, 1, 0))
        a = loc + side * 0.42 + up * 0.01
        c = loc - side * 0.42 + up * 0.01
        bungee(b, a, c, top_center + up * 0.006, up)
    return b


# ------------------------------------------------------------------------------------------------ cuisine
def pouch(b, m, w, h, kind="mylar", seed=1.0, straw=False):
    """Sachet scellé (repère : Y = normale sortante de la paroi) : poche gonflée et froissée, bord soudé plat."""
    depth = 0.008
    if kind == "mylar":
        deform = chain(puff(0.012, axes=(1,)), crinkle(0.0015, seed))
        mat = "mylar"
    else:
        deform = chain(puff(0.016, axes=(1,)), wrinkles(0.0012, seed))
        mat = "sachet"
    b.add(soft_box((w / 2, depth, h / 2), 0.006, 0.01, deform), mat, m @ Matrix.Translation((0, depth + 0.006, 0)))
    b.add(soft_box((w / 2 + 0.009, 0.0015, h / 2 + 0.009), 0.0014, 0.012, crinkle(0.0006, seed + 1)), mat,
          m @ Matrix.Translation((0, 0.006, 0)))
    if kind != "mylar":
        b.add(soft_box((w * 0.32, 0.0008, h * 0.18), 0.0008, 0.01), "etiquette",
              m @ Matrix.Translation((0, 2 * depth + 0.006 + 0.012, -h * 0.12)))
    # Velcro au dos (visible sur la tranche).
    b.add(soft_box((0.02, 0.003, 0.02), 0.002, 0.008), "velcro", m @ Matrix.Translation((0, 0.003, h * 0.25)))
    if straw:
        top = Vector((w * 0.25, depth + 0.006, h / 2 + 0.006))
        b.add(tube([top, top + Vector((0.005, 0.004, 0.05)), top + Vector((0.02, 0.012, 0.085))], 0.0032, 8), "paille", m)
        b.add(soft_box((0.008, 0.007, 0.012), 0.003, 0.004), "pince", m @ Matrix.Translation(top + Vector((0.004, 0.003, 0.03))))


def bottle(b, m, kind):
    """Bouteille de condiment (axe local Z) : corps, épaule, bouchon verseur, étiquette."""
    r, h = (0.021, 0.12) if kind != "piment" else (0.016, 0.13)
    prof = [(0.0, 0.0), (r * 0.9, 0.0), (r, 0.008), (r, h * 0.7), (r * 0.8, h * 0.8), (r * 0.45, h * 0.88),
            (r * 0.42, h * 0.95), (0.0, h * 0.95)]
    b.add(revolve(prof, 24), kind, m)
    b.add(revolve([(0.0, h * 0.94), (r * 0.5, h * 0.94), (r * 0.5, h * 1.02), (r * 0.25, h * 1.06), (0.0, h * 1.08)], 16),
          "bouchon" if kind != "piment" else "vert", m)
    b.add(revolve([(r * 1.012, h * 0.2), (r * 1.012, h * 0.55)], 24), "etiquette", m)


def net_bag(b, m, w, h, depth=0.05):
    """Filet de rangement garni (repère : Y = normale sortante) : fond, emballages colorés, mailles."""
    b.add(soft_box((w / 2, 0.006, h / 2), 0.005, 0.015), "ctb", m @ Matrix.Translation((0, 0.006, 0)))
    for (px, pz, k, s) in ((-0.06, 0.02, "rouge", 0.05), (0.05, -0.03, "jaune", 0.045), (0.0, 0.06, "rouge", 0.04),
                           (0.08, 0.05, "vert", 0.035), (-0.08, -0.05, "jaune", 0.04)):
        b.add(soft_box((s, 0.022, s * 0.8), 0.015, 0.012, chain(puff(0.01), crinkle(0.001, px * 40))), k,
              m @ Matrix.Translation((px, 0.03, pz)))
    surf = lambda u, v: Vector((u * w / 2, 0.012 + depth * max(0.0, 1 - u * u) ** 0.6 * max(0.0, 1 - v * v) ** 0.6,
                                v * h / 2))
    for i in range(9):
        u = -1 + 2 * i / 8
        b.add(tube([surf(u, -1 + 2 * k / 10) for k in range(11)], 0.0012, 4), "filet", m)
    for j in range(8):
        v = -1 + 2 * j / 7
        b.add(tube([surf(-1 + 2 * k / 10, v) for k in range(11)], 0.0012, 4), "filet", m)
    b.add(tube([surf(-1, 1), surf(0, 1) + Vector((0, 0.01, 0.006)), surf(1, 1)], 0.0035, 6), "sandow", m)


def tape_roll(b, m):
    b.add(revolve([(0.034, -0.025), (0.052, -0.025), (0.052, 0.025), (0.034, 0.025), (0.034, -0.025)], 40), "adhesif", m)
    b.add(revolve([(0.031, -0.026), (0.035, -0.026), (0.035, 0.026), (0.031, 0.026), (0.031, -0.026)], 40), "carton", m)
    tail = [(0.052, 0.0, 0.0), (0.05, -0.03, 0.0), (0.045, -0.07, 0.0)]
    b.add(ribbon([Vector(p) for p in tail], (0, 0, 1), 0.05, 0.0008), "adhesif", m, smooth=False)


def wall_frame(x, z, direction=(0, 1, 0)):
    """Repère posé sur la paroi touchée depuis (x, 0, z) : Y = normale de la paroi (vers l'intérieur)."""
    loc, n, ob = hit((x, 0.0, z), direction)
    return frame(loc, (1, 0, 0), n), ob


def build_kitchen():
    b = Mesh()
    report = []
    rot = lambda m, a: m @ Matrix.Rotation(a, 4, 'Y')
    # Sachets repas (aluminium) à gauche du réchauffeur, en grappe ; deux autres au-dessus du distributeur d'eau.
    for (x, z, w, h, a, s) in ((-4.12, 0.18, 0.14, 0.2, 0.12, 1.0), (-3.96, 0.02, 0.13, 0.19, -0.08, 2.3),
                               (-4.2, -0.12, 0.12, 0.17, 0.2, 3.1), (-2.6, 0.43, 0.15, 0.11, 0.05, 4.4),
                               (-3.28, 0.42, 0.16, 0.12, -0.04, 5.2)):
        m, ob = wall_frame(x, z)
        pouch(b, rot(m, a), w, h, "mylar", s)
        report.append(("sachet", round(x, 2), ob))
    # Poches à boire (plastique, paille et pince) sur la façade des boîtes de rangement.
    for (x, z, a, s) in ((-2.05, 0.22, 0.06, 6.0), (-1.82, 0.16, -0.1, 7.1)):
        m, ob = wall_frame(x, z)
        pouch(b, rot(m, a), 0.1, 0.16, "sachet", s, straw=True)
        report.append(("poche", round(x, 2), ob))
    # Filet garni à gauche, sous les sachets.
    m, ob = wall_frame(-4.12, -0.36)
    net_bag(b, m, 0.26, 0.2)
    report.append(("filet", ob))
    # Rouleau d'adhésif sous le réchauffeur, sur un crochet.
    m, ob = wall_frame(-3.3, -0.43)
    tape_roll(b, m @ Matrix.Translation((0, 0.05, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cylinder(0.006, 0.05, 10), "crochet", m @ Matrix.Translation((0, 0.025, 0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    report.append(("adhesif", ob))
    # Bouteilles de condiments sur la paroi diagonale (coin haut, côté cuisine), tenues par un sandow.
    d = Vector((0, 1, 1)).normalized()
    kinds = ("sauce", "moutarde", "piment", "sauce", "piment", "moutarde")
    base = None
    for i, k in enumerate(kinds):
        x = -2.72 + i * 0.062
        loc, n, ob = hit((x, 0.0, 0.0), d)
        up = Vector((0, -1, 1)).normalized()  # le long de la paroi diagonale, vers le plafond
        x_axis = Vector((1, 0, 0))
        bm = Matrix((x_axis, up.cross(x_axis), up)).transposed().to_4x4()  # axe Z de la bouteille -> « up »
        bm.translation = loc + n * 0.023 - up * 0.075
        bottle(b, bm, k)
        base = (loc, n, up) if base is None else base
        report.append(("bouteille", k, ob))
    loc0, n0, up0 = base
    a = loc0 + Vector((-0.06, 0, 0)) - up0 * 0.03
    c = loc0 + Vector((0.06 * len(kinds) + 0.01, 0, 0)) - up0 * 0.03
    bungee(b, a, c, (a + c) / 2 + n0 * 0.05, n0)
    return b, report


# ------------------------------------------------------------------------------------------------ assemblage
try:
    couch = build_couchette()
    bags = build_bags()
    kitchen, kitchen_report = build_kitchen()
finally:
    for o in hidden:
        o.hide_viewport = False
c_obj = couch.write("Interactif_Couchette")
s_obj = bags.write("Habitation_Sacs")
k_obj = kitchen.write("Habitation_Cuisine_Accessoires")
bpy.ops.wm.save_mainfile()
result = {"couchette": len(c_obj.data.polygons), "sacs": len(s_obj.data.polygons),
          "cuisine": len(k_obj.data.polygons), "poses": kitchen_report[:20], "enregistre": not bpy.data.is_dirty}
