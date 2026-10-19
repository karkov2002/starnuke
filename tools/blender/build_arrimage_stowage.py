# Outil hors-jeu : rangements souples du module Arrimage (le « module de rangement ») dans E:\Blender\nuke_station.blend
# (Blender ouvert, extension MCP de Blender Lab), comme la cuisine de l'Habitation :
#   & ./tools/blender_exec.ps1 -TimeoutS 900 -File tools/blender/build_arrimage_stowage.py
# Les blocs rigides d'Arrimage_Stockage-col (casiers verts Int_Caisse, pavés beiges sous filet Int_Sac_Beige,
# réservoirs d'eau octogonaux Int_Bleu_Eau, et leurs sangles, filets et bandes jaunes) sont retirés une fois
# (propriété « rangement_souple ») ; à leur place, objet Arrimage_Rangement (sans collision) :
# - sacs de transfert souples type CTB (toile tissée blanc cassé ou beige, photo ambientCG Fabric036 recolorée), de
#   tailles variées, gonflés et légèrement froissés, glissière du rabat, poignées et sangle de portage, pastilles
#   velcro, fenêtre d'étiquette ; quelques sacs posés en second rang ;
# - maintien : sangles d'arrimage à boucle à came et platines (casiers), ou filet de cordelette drapé sur les sacs
#   (lancer de rayons sur les sacs), bordé et accroché à la paroi (sols, plafonds, parois, diagonales) ;
# - poches d'eau souples (type CWC : tissu enduit bleuté, Fabric082A recoloré) avec poignées et bouchon ;
# Interactif_Caisse_01–03 et Arrimage_Sacs (maillages remplacés, noms et extras gardés) : caisses moelleuses en
# tissu matelassé (Fabric048), glissière, poignée, sangle jaune, étiquette ; sac CTB.
# Collisions : Arrimage_Rangement_Collision-colonly (pavés simples des volumes occupés).
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math, random
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())
exec(open(r"E:\Projects\starnuke\tools\blender\pbr_kit.py", encoding="utf-8").read())

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)
STOCK = "Arrimage_Stockage-col"
OUT = "Arrimage_Rangement"
COLL = "Arrimage_Rangement_Collision-colonly"
S2 = math.sqrt(0.5)


def plain(name, color, metallic, roughness):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color, 1.0)
    return m


MATS = {
    "ctb_blanc": fabric_material("Int_Toile_CTB", "Fabric036", (0.80, 0.78, 0.72), 3.0, keep=0.5),
    "ctb_beige": fabric_material("Int_Toile_Beige", "Fabric036", (0.56, 0.48, 0.34), 3.0, keep=0.5),
    "sangle": fabric_material("Int_Sangle_Toile", "Fabric036", (0.035, 0.038, 0.045), 6.0, keep=0.8, roughness_scale=1.1),
    "matelasse": fabric_material("Int_Toile_Matelassee", "Fabric048", None, 1.6),
    "cwc": fabric_material("Int_Toile_Enduite", "Fabric082A", (0.70, 0.78, 0.86), 2.0, keep=0.3),
    "cordelette": plain("Int_Cordelette", (0.72, 0.70, 0.62), 0.0, 0.9),
    "boucle": bpy.data.materials["Int_Boucle"],
    "velcro": bpy.data.materials["Int_Velcro_Bleu"],
    "etiquette": bpy.data.materials["Int_Etiquette"],
    "encre": bpy.data.materials["Int_Encre"],
    "glissiere": bpy.data.materials["Int_Glissiere"],
    "jaune": bpy.data.materials["Int_Jaune"],
    "bouchon": plain("Int_Bouchon_CWC", (0.05, 0.18, 0.55), 0.0, 0.4),
    "platine": plain("Int_Platine_Arrimage", (0.55, 0.56, 0.58), 0.8, 0.35),
    "fenetre": plain("Int_Pochette", (0.85, 0.88, 0.9), 0.0, 0.12),
}


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
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
            g.normal_update()
            ax = max(range(3), key=lambda i: abs(g.normal[i]))
            u, v = [i for i in range(3) if i != ax]
            for loop in g.loops:
                loop[self.uv].uv = (loop.vert.co[u], loop.vert.co[v])
        part.free()

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        for m in self.slots:
            me.materials.append(m)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.set_sharp_from_angle(angle=math.radians(50))
        return me


def ribbon(points, side, width, thick):
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


# ------------------------------------------------------------------------------------------------ objets souples
def ctb_bag(b, m, half, rng, key="ctb_blanc"):
    """Sac de transfert souple (repère m : Z = dessus, vers la pièce) : toile gonflée et froissée, glissière du rabat,
    poignées cousues, pastilles velcro, fenêtre d'étiquette."""
    hx, hy, hz = half
    seed = rng.uniform(0, 10)
    # Coins très arrondis et toile bien gonflée, froissée : un sac souple, pas une boîte.
    r = min(0.06, hz * 0.8, hx * 0.45, hy * 0.45)
    deform = chain(puff(min(0.032, hz * 0.3)), wrinkles(0.0035, seed))
    fmap = soft_map(half, r, deform)
    # Maille plus lâche sur les grands sacs (les plis restent lisibles, la texture fait le grain).
    b.add(soft_box(half, r, max(0.02, max(hx, hy) / 9), deform), key, m)
    top = lambda u, v: fmap(Vector((u * hx, v * hy, hz)))
    ring = []
    for k in range(33):
        a = 2 * math.pi * k / 32
        c, s = math.cos(a), math.sin(a)
        k_sq = max(abs(c), abs(s))
        ring.append(m @ (top(c / k_sq * 0.87, s / k_sq * 0.85) + Vector((0, 0, 0.002))))
    b.add(tube(ring, 0.0035, 5), "glissiere")
    # Poignées de portage cousues (deux bandes sur le dessus).
    for sv in (-0.45, 0.45):
        pts = [top(-0.42, sv), top(-0.25, sv) + Vector((0, 0, 0.025)), top(0.25, sv) + Vector((0, 0, 0.025)), top(0.42, sv)]
        b.add(ribbon([m @ p for p in pts], m.to_3x3() @ Vector((0, 1, 0)), 0.03, 0.003), key if rng.random() < 0.5 else "sangle", smooth=False)
    # Pastilles velcro et fenêtre d'étiquette (pochette transparente, carte, texte).
    for su in (-0.6, 0.6):
        b.add(soft_box((0.04, 0.012, 0.0015), 0.004, 0.2), "velcro", m @ Matrix.Translation(top(su, -0.72)))
    lab = m @ Matrix.Translation(top(0.0, 0.1) + Vector((0, 0, 0.002)))
    lw, lh = min(0.07, hx * 0.45), min(0.045, hy * 0.35)
    b.add(soft_box((lw, lh, 0.001), 0.004, 0.2), "etiquette", lab)
    for k in range(3):
        w = lw * (0.8, 0.55, 0.7)[k]
        b.add(soft_box((w, 0.0025, 0.0006), 0.0006, 0.2), "encre", lab @ Matrix.Translation((0, lh * 0.5 - k * lh * 0.45, 0.0012)))


def padded_case(b, m, half, rng):
    """Caisse moelleuse (repère m : Z = dessus) : tissu matelassé gonflé, couvercle à glissière, sangle jaune de
    ceinture, poignée, étiquette."""
    hx, hy, hz = half
    deform = chain(puff(0.012), wrinkles(0.0015, rng.uniform(0, 10)))
    fmap = soft_map(half, 0.06, deform)
    b.add(soft_box(half, 0.06, 0.02, deform), "matelasse", m)
    ring = []
    for k in range(65):
        a = 2 * math.pi * k / 64
        ring.append(m @ fmap(Vector((hx * 1.2 * math.cos(a), hy * 1.2 * math.sin(a), hz * 0.62))))
    b.add(tube(ring, 0.004, 6), "glissiere")
    belt = [m @ (fmap(Vector((hx * 1.3 * math.cos(a), hy * 1.3 * math.sin(a), -hz * 0.1))) * 1.0) for a in
            (2 * math.pi * k / 64 for k in range(65))]
    b.add(ribbon(belt, m.to_3x3() @ Vector((0, 0, 1)), 0.035, 0.004), "jaune", smooth=False)
    top = lambda u, v: fmap(Vector((u * hx, v * hy, hz)))
    pts = [top(-0.35, 0), top(-0.2, 0) + Vector((0, 0, 0.03)), top(0.2, 0) + Vector((0, 0, 0.03)), top(0.35, 0)]
    b.add(ribbon([m @ p for p in pts], m.to_3x3() @ Vector((0, 1, 0)), 0.032, 0.004), "sangle", smooth=False)
    lab = m @ Matrix.Translation(fmap(Vector((0, -hy, hz * 0.2))) + Vector((0, -0.002, 0))) @ Matrix.Rotation(math.pi / 2, 4, 'X')
    b.add(soft_box((0.06, 0.035, 0.001), 0.004, 0.2), "etiquette", lab)
    for k in range(3):
        b.add(soft_box((0.045 - 0.01 * k, 0.0025, 0.0006), 0.0006, 0.2), "encre", lab @ Matrix.Translation((0, 0.018 - 0.015 * k, 0.0012)))


def water_bag(b, m, half, rng):
    """Poche d'eau souple (type CWC, repère m : Z = dessus) : tissu enduit très gonflé, poignées, bouchon bleu."""
    hx, hy, hz = half
    deform = chain(puff(hz * 0.35, axes=(2,)), wrinkles(0.002, rng.uniform(0, 10)))
    b.add(soft_box(half, min(hy, hz) * 0.85, 0.03, deform), "cwc", m)
    fmap = soft_map(half, min(hy, hz) * 0.85, deform)
    for su in (-0.75, 0.75):
        p0, p1 = fmap(Vector((su * hx - 0.05, 0, hz))), fmap(Vector((su * hx + 0.05, 0, hz)))
        pts = [p0, p0.lerp(p1, 0.3) + Vector((0, 0, 0.03)), p0.lerp(p1, 0.7) + Vector((0, 0, 0.03)), p1]
        b.add(ribbon([m @ p for p in pts], m.to_3x3() @ Vector((0, 1, 0)), 0.028, 0.003), "sangle", smooth=False)
    cap = fmap(Vector((hx * 0.35, hy * 0.3, hz)))
    b.add(cylinder(0.022, 0.03, 24), "bouchon", m @ Matrix.Translation(cap + Vector((0, 0, 0.01))))
    lab = m @ Matrix.Translation(fmap(Vector((-hx * 0.2, -hy * 0.2, hz))) + Vector((0, 0, 0.002)))
    b.add(soft_box((0.08, 0.04, 0.001), 0.004, 0.2), "etiquette", lab)
    b.add(soft_box((0.06, 0.003, 0.0006), 0.0006, 0.2), "encre", lab @ Matrix.Translation((0, 0.015, 0.0012)))


# ------------------------------------------------------------------------------------------------ zones
# Repère d'une zone : origine au centre de sa face contre la paroi ; X le long du module, Y dans le plan de la paroi,
# Z = normale vers la pièce ; dimensions (X, Y, profondeur) ; maintien « sangles » ou « filet ».
def frame(origin, normal):
    z = Vector(normal).normalized()
    x = Vector((1.0, 0.0, 0.0))
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


ZONES = [
    # Anciennes rangées de casiers verts (paroi −Y) : sacs empilés, sangles d'arrimage.
    ("casiers_ar", frame((-14.40, -1.25, 0.0), (0, 1, 0)), (2.76, 0.90, 0.48), "sangles"),
    ("casiers_av", frame((-8.50, -1.25, 0.0), (0, 1, 0)), (1.76, 0.90, 0.44), "sangles"),
    # Filets : sol, plafond, paroi +Y, diagonales.
    ("filet_sol", frame((-13.90, 0.0, -1.25), (0, 0, 1)), (3.80, 0.96, 0.32), "filet"),
    ("filet_plafond", frame((-11.70, 0.0, 1.25), (0, 0, -1)), (1.80, 0.96, 0.32), "filet"),
    ("filet_paroi", frame((-8.50, 1.25, 0.0), (0, -1, 0)), (1.80, 0.96, 0.28), "filet"),
    ("filet_diag_plafond", frame((-12.00, -0.884, 0.884), (0, S2, -S2)), (1.20, 0.62, 0.24), "filet"),
    ("filet_diag_sol_ar", frame((-14.90, -0.884, -0.884), (0, S2, S2)), (1.40, 0.62, 0.24), "filet"),
    ("filet_diag_sol_av", frame((-8.65, 0.884, -0.884), (0, -S2, S2)), (1.30, 0.62, 0.24), "filet"),
]
WATER = [
    # Poches d'eau (anciens réservoirs bleus) : paroi +Y (deux) et diagonale +Y / plafond (râtelier de l'extincteur).
    (frame((-11.75, 1.25, -0.22), (0, -1, 0)), (0.80, 0.19, 0.15)),
    (frame((-11.75, 1.25, 0.22), (0, -1, 0)), (0.80, 0.19, 0.15)),
    (frame((-13.25, 0.95, 0.82), (0, -0.79, -0.61)), (0.42, 0.12, 0.10)),
]


def fill_zone(b, m, size, rng):
    """Sacs sur la zone : grille irrégulière (longueur, largeur), profondeur variable, rotation légère ; second rang
    de petits sacs çà et là. Rend les boîtes (centre local, demi-tailles) pour les collisions."""
    L, W, D = size
    n = max(1, round(L / rng.uniform(0.5, 0.62)))
    cuts = sorted(rng.uniform(0.12, 0.88) for _ in range(n - 1))
    xs = [-L / 2] + [-L / 2 + L * (i + 1) / n + rng.uniform(-0.05, 0.05) for i in range(n - 1)] + [L / 2]
    rows = 1 if W < 0.62 else 2
    boxes = []
    for i in range(n):
        x0, x1 = xs[i], xs[i + 1]
        ys = [-W / 2, W / 2] if rows == 1 else [-W / 2, rng.uniform(-0.06, 0.06), W / 2]
        for j in range(rows):
            y0, y1 = ys[j], ys[j + 1]
            hx, hy = (x1 - x0) / 2 - 0.012, (y1 - y0) / 2 - 0.012
            hz = D / 2 * rng.uniform(0.55, 0.9)
            mm = m @ Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, hz + 0.004)) @ Matrix.Rotation(rng.uniform(-0.04, 0.04), 4, 'Z')
            ctb_bag(b, mm, (hx, hy, hz), rng, "ctb_beige" if rng.random() < 0.3 else "ctb_blanc")
            boxes.append((((x0 + x1) / 2, (y0 + y1) / 2, hz + 0.004), (hx, hy, hz)))
            if D - 2 * hz > 0.12 and rng.random() < 0.45:
                h2 = (min(hx, 0.22) * rng.uniform(0.6, 0.85), min(hy, 0.18) * rng.uniform(0.6, 0.85), (D - 2 * hz) / 2 * 0.8)
                m2 = mm @ Matrix.Translation((rng.uniform(-0.05, 0.05), rng.uniform(-0.03, 0.03), hz + h2[2] + 0.004)) \
                    @ Matrix.Rotation(rng.uniform(-0.3, 0.3), 4, 'Z')
                ctb_bag(b, m2, h2, rng, "ctb_blanc")
    return boxes


def surface_depth(bvh, m, x, y, depth):
    """Hauteur (repère de zone) de la surface des sacs en (x, y) : rayon lancé de l'avant vers la paroi."""
    start = m @ Vector((x, y, depth + 0.2))
    direction = (m.to_3x3() @ Vector((0, 0, -1))).normalized()
    loc, *_ = bvh.ray_cast(start, direction, depth + 0.25)
    if loc is None:
        return 0.01
    return (m.inverted() @ loc).z


def straps(b, m, size, bvh):
    """Deux sangles d'arrimage le long de la zone, plaquées sur les sacs, boucle à came au milieu, platines aux bouts."""
    L, W, D = size
    for y in (-W / 4, W / 4):
        pts = []
        for k in range(41):
            x = -L / 2 + L * k / 40
            h = surface_depth(bvh, m, x, y, D) + 0.006 if 0 < k < 40 else 0.02
            pts.append(m @ Vector((x, y, h)))
        b.add(ribbon(pts, m.to_3x3() @ Vector((0, 1, 0)), 0.035, 0.003), "sangle", smooth=False)
        mid = pts[20]
        b.add(soft_box((0.03, 0.025, 0.008), 0.004, 0.01), "boucle", Matrix.Translation(mid) @ m.to_3x3().to_4x4())
        for end in (-1, 1):
            p = m @ Vector((end * (L / 2 + 0.02), y, 0.008))
            b.add(soft_box((0.03, 0.035, 0.008), 0.004, 0.01), "platine", Matrix.Translation(p) @ m.to_3x3().to_4x4())


def net(b, m, size, bvh):
    """Filet de cordelette drapé sur les sacs (mailles de 11 cm), bordure plus épaisse et crochets aux coins."""
    L, W, D = size
    step = 0.11
    nx, ny = max(2, round(L / step)), max(2, round(W / step))

    def point(x, y, edge):
        h = 0.012 if edge else surface_depth(bvh, m, x, y, D) + 0.006
        return m @ Vector((x, y, h))
    for i in range(nx + 1):
        x = -L / 2 + L * i / nx
        edge_line = i in (0, nx)
        pts = [point(x, -W / 2 + W * k / (ny * 2), edge_line or k in (0, ny * 2)) for k in range(ny * 2 + 1)]
        b.add(tube(pts, 0.005 if edge_line else 0.003, 4), "cordelette")
    for j in range(ny + 1):
        y = -W / 2 + W * j / ny
        edge_line = j in (0, ny)
        pts = [point(-L / 2 + L * k / (nx * 2), y, edge_line or k in (0, nx * 2)) for k in range(nx * 2 + 1)]
        b.add(tube(pts, 0.005 if edge_line else 0.003, 4), "cordelette")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = m @ Vector((sx * L / 2, sy * W / 2, 0.012))
            b.add(torus(0.014, 0.004, 16, 6), "platine", Matrix.Translation(p) @ m.to_3x3().to_4x4())


# ------------------------------------------------------------------------------------------------ nettoyage
stock = bpy.data.objects[STOCK]
removed = "deja"
if not stock.get("rangement_souple"):
    bm = bmesh.new()
    bm.from_mesh(stock.data)
    M = stock.matrix_world
    mats = stock.data.materials
    seen, islands = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        st, cur = [f], []
        seen.add(f)
        while st:
            g = st.pop()
            cur.append(g)
            for v in g.verts:
                for h in v.link_faces:
                    if h not in seen:
                        seen.add(h)
                        st.append(h)
        pts = [M @ v.co for g in cur for v in g.verts]
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        islands.append((cur, lo, hi, {mats[g.material_index].name for g in cur}))
    soft = {"Int_Caisse", "Int_Sac_Beige", "Int_Bleu_Eau"}
    regions = [(lo - Vector((0.05,) * 3), hi + Vector((0.05,) * 3)) for _, lo, hi, ms in islands if ms & soft]
    doomed = []
    for cur, lo, hi, ms in islands:
        if ms & soft or (ms <= {"Int_Noir", "Int_Jaune"} and any(all(r[0][i] <= lo[i] and hi[i] <= r[1][i] for i in range(3)) for r in regions)):
            doomed += cur
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(stock.data)
    bm.free()
    stock["rangement_souple"] = True
    removed = len(doomed)
if not stock.get("sangles_casiers_retirees"):
    # Longues sangles noires devant les anciennes rangées de casiers (elles traversaient plusieurs casiers : aucune
    # zone ne les contenait entières) ; remplacées par les sangles d'arrimage.
    bm = bmesh.new()
    bm.from_mesh(stock.data)
    M = stock.matrix_world
    noir = [i for i, mt in enumerate(stock.data.materials) if mt and mt.name == "Int_Noir"]
    doomed = [f for f in bm.faces if f.material_index in noir and -0.82 < (M @ f.calc_center_median()).y < -0.70
              and abs((M @ f.calc_center_median()).z) < 0.3]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(stock.data)
    bm.free()
    stock["sangles_casiers_retirees"] = True

col = stock.users_collection[0]
for name in (OUT, COLL):
    o = bpy.data.objects.get(name)
    if o:
        d = o.data
        bpy.data.objects.remove(o)
        bpy.data.meshes.remove(d)

# ------------------------------------------------------------------------------------------------ construction
rng = random.Random(1307)
bags = Builder()
zone_boxes = []
for name, m, size, hold in ZONES:
    for c, h in fill_zone(bags, m, size, rng):
        zone_boxes.append((m, c, h))
for m, half in WATER:
    mm = m @ Matrix.Translation((0, 0, half[2] + 0.004))
    water_bag(bags, mm, half, rng)
    zone_boxes.append((m, (0, 0, half[2] + 0.004), half))
bvh = BVHTree.FromBMesh(bags.bm)
for name, m, size, hold in ZONES:
    (straps if hold == "sangles" else net)(bags, m, size, bvh)
out = bpy.data.objects.new(OUT, bags.mesh(OUT))
col.objects.link(out)

# Collisions : un pavé par sac du premier rang (repère de zone).
cbm = bmesh.new()
for m, c, h in zone_boxes:
    part = bmesh.new()
    bmesh.ops.create_cube(part, size=1.0)
    bmesh.ops.scale(part, vec=(2 * h[0], 2 * h[1], 2 * h[2]), verts=part.verts)
    bmesh.ops.transform(part, matrix=m @ Matrix.Translation(c), verts=part.verts)
    vmap = {v: cbm.verts.new(v.co) for v in part.verts}
    for f in part.faces:
        cbm.faces.new([vmap[v] for v in f.verts])
    part.free()
cme = bpy.data.meshes.new(COLL)
cbm.to_mesh(cme)
cbm.free()
coll_obj = bpy.data.objects.new(COLL, cme)
col.objects.link(coll_obj)

# Caisses et sac existants (noms et extras gardés), même encombrement.
specials = {}
for name, centre, normal, half, kind in (
        ("Interactif_Caisse_01", (-12.375, -1.25, 0.0), (0, 1, 0), (0.22, 0.21, 0.21), "case"),
        ("Interactif_Caisse_02", (-9.075, 0.0, -1.25), (0, 0, 1), (0.22, 0.21, 0.21), "case"),
        ("Interactif_Caisse_03", (-15.425, 0.884, -0.884), (0, -S2, S2), (0.17, 0.22, 0.2), "case"),
        ("Arrimage_Sacs", (-11.60, -1.25, 0.0), (0, 1, 0), (0.44, 0.28, 0.11), "bag")):
    o = bpy.data.objects[name]
    b = Builder()
    m = frame(centre, normal) @ Matrix.Translation((0, 0, half[2] + 0.004))
    (padded_case if kind == "case" else ctb_bag)(b, m, half, rng)
    old = o.data
    me = b.mesh(name)
    o.data = me
    o.matrix_world = Matrix()
    if old.users == 0:
        bpy.data.meshes.remove(old)
    specials[name] = len(me.polygons)

bpy.ops.wm.save_mainfile()
result = {"retire": removed, "rangement_faces": len(out.data.polygons), "collisions": len(zone_boxes), "objets": specials}
