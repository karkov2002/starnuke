# Outil hors-jeu : module « sas de sortie » sous le module Arrimage, dans E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab) :
#   & ./tools/blender_exec.ps1 -TimeoutS 600 -File tools/blender/build_airlock.py
# Rejouable : supprime d'abord ce qu'il a créé (collections Module_Sas et Int_Sas, lampes Lum_Sas_*). Les retouches du
# module Arrimage sont faites une fois (propriété « trou_sas » sur les objets percés).
# - Arrimage : l'ancienne trappe verrouillée du plancher (Interactif_Trappe_Nadir) et le port nadir extérieur
#   (Arrimage_Port_Nadir, _Bride) sont retirés ; plancher et coque percés (Ø 0,86 m) sur l'axe du sas.
# - Puits Ø 0,80 m (passage des écoutilles russes) du plancher (z −1,25) au plafond du sas (z −3,08), fermé en haut par
#   Interactif_Ecoutille_Sas_Haut (s'ouvre vers le haut, dans l'Arrimage ; charnière d'axe Y).
# - Module Ø 2,5 m (les autres : 4,2 m), coque Coque_Silo, cerclages et bride Metal_Furtif, de z −2,91 à −5,97 ;
#   intérieur Ø 2,24 m : parois blanches, montants, mains courantes, deux luminaires au plafond (lampes Lum_Sas_1, _2).
# - Porte extérieure Interactif_Ecoutille_Sas_Bas au fond (Ø 1,20 m, passage Ø 1,00 m) : hublot central (Vitrage), face
#   intérieure Int_, face extérieure Metal_Furtif ; s'ouvre vers le bas, vers la Terre (charnière d'axe X, −100°).
# - Interactif_Combinaison : scaphandre type EMU (bottes, jambes et bras à soufflets, bandes rouges, torse rigide,
#   module de commande poitrine, sac dorsal, casque à visière dorée et lampes) sur son support mural, paroi +Y.
# - Sas_Equipements : sacs CTB sous sandows (paroi −Y), extincteur, bouteille d'oxygène et masque, longes, batteries,
#   sacoche d'outils, fiche de procédure.
# Les deux écoutilles suivent la convention de Fermeture_Ecoutilles (image 1 ouverte, image 40 fermée) ; station.gd
# les ferme au démarrage. Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())

X0, Y0 = -10.1, 0.0             # axe du sas (port nadir de l'Arrimage)
FLOOR_Z = -1.25                 # plancher de l'Arrimage
CUT_R = 0.43                    # perçage du plancher et de la coque
TUNNEL_R = 0.40                 # puits
CEIL_Z = -3.08                  # plafond intérieur du sas
IN_R, WALL_BOT = 1.12, -5.40    # paroi intérieure
PASS_R, PASS_Z = 0.50, -5.78    # passage de la porte extérieure (bas du cône intérieur)
HULL_R, TOP_Z = 1.25, -2.91     # coque extérieure
SEAT_Z = -5.90                  # appui de la porte extérieure (face intérieure de la porte)
DOOR_R, DOOR_T = 0.60, 0.07
SEG = 96

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
scene = bpy.context.scene
scene.frame_set(1)
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

MATS = {
    # Matériaux d'origine (texturés ou partagés) : pris tels quels.
    "coque": bpy.data.materials["Coque_Silo"],
    "furtif": bpy.data.materials["Metal_Furtif"],
    "vitrage": bpy.data.materials["Vitrage"],
    "panneau": bpy.data.materials["Int_Panneau_Blanc"],
    "gris": bpy.data.materials["Int_Panneau_Gris"],
    "metal": bpy.data.materials["Int_Metal"],
    "jaune": bpy.data.materials["Int_Jaune"],
    "main": bpy.data.materials["Int_Main_Courante"],
    "lumiere": bpy.data.materials["Int_Lumiere"],
    "ctb": bpy.data.materials["Int_Sac_CTB"],
    "sangle_ctb": bpy.data.materials["Int_Sangle_CTB"],
    "velcro": bpy.data.materials["Int_Velcro_Bleu"],
    "etiquette": bpy.data.materials["Int_Etiquette"],
    "encre": bpy.data.materials["Int_Encre"],
    "glissiere": bpy.data.materials["Int_Glissiere"],
    "sandow": bpy.data.materials["Int_Sandow"],
    "crochet": bpy.data.materials["Int_Crochet"],
    "sangle": bpy.data.materials["Int_Sangle_Noire"],
    "alu_sombre": bpy.data.materials["Int_Alu_Sombre"],
    "sac_blanc": bpy.data.materials["Int_Sac_Blanc"],
    # Nouveaux.
    "tissu": material("Int_Combi_Tissu", (0.80, 0.80, 0.77), 0.0, 0.88),
    "dur": material("Int_Combi_Coque", (0.84, 0.84, 0.83), 0.0, 0.32),
    "bague": material("Int_Combi_Bague", (0.60, 0.62, 0.66), 1.0, 0.28),
    "rouge": material("Int_Combi_Rouge", (0.62, 0.04, 0.03), 0.0, 0.7),
    "gant": material("Int_Combi_Gant", (0.42, 0.42, 0.41), 0.0, 0.85),
    "semelle": material("Int_Combi_Semelle", (0.035, 0.035, 0.035), 0.0, 0.9),
    "visiere": material("Int_Combi_Visiere", (1.0, 0.70, 0.28), 1.0, 0.07),
    "noir": material("Int_Combi_Noir", (0.012, 0.012, 0.013), 0.0, 0.4),
    "optique": material("Int_Combi_Optique", (0.85, 0.86, 0.9), 0.0, 0.08),
    "extincteur": material("Int_Extincteur", (0.55, 0.05, 0.03), 0.2, 0.45),
    "oxygene": material("Int_Bouteille_O2", (0.12, 0.38, 0.16), 0.2, 0.45),
    "masque": material("Int_Masque", (0.85, 0.87, 0.9), 0.0, 0.15),
    "longe": material("Int_Longe", (0.08, 0.30, 0.12), 0.0, 0.8),
    "poignee_ext": material("Poignee_EVA", (0.55, 0.42, 0.06), 0.3, 0.55),
}


# ------------------------------------------------------------------------------------------------ outils
class Builder:
    """Pièces bmesh à matériaux multiples, coordonnées de texture en mètres (projection en boîte selon la normale, ou
    cylindrique autour de l'axe du sas pour les parois)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def add(self, part, key, matrix=Matrix(), smooth=True, uv="box"):
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
            n = g.normal
            for loop in g.loops:
                co = loop.vert.co
                if uv == "cyl" and abs(n.z) < 0.7:
                    a = math.atan2(co.y - Y0, co.x - X0)
                    loop[self.uv].uv = (a * math.hypot(co.x - X0, co.y - Y0), co.z)
                else:
                    ax = max(range(3), key=lambda i: abs(n[i]))
                    u, v = [i for i in range(3) if i != ax]
                    loop[self.uv].uv = (co[u], co[v])
        part.free()

    def write(self, name, collection, sharp=40):
        me = bpy.data.meshes.new(name)
        for m in self.slots:
            me.materials.append(m)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.set_sharp_from_angle(angle=math.radians(sharp))
        ob = bpy.data.objects.new(name, me)
        collection.objects.link(ob)
        return ob


def surface(profile, hint, seg=SEG, a0=0.0, a1=2 * math.pi):
    """Surface de révolution ouverte autour de l'axe du sas, profil [(r, z)] ; hint(centre) donne le côté visible
    (direction attendue de la normale)."""
    bm = bmesh.new()
    full = abs(a1 - a0 - 2 * math.pi) < 1e-9
    n = seg if full else seg + 1
    rings = [[bm.verts.new((X0 + r * math.cos(a0 + (a1 - a0) * k / seg), Y0 + r * math.sin(a0 + (a1 - a0) * k / seg), z))
              for k in range(n)] for r, z in profile]
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            q = (k + 1) % n
            if a[k].co == a[q].co and b[k].co == b[q].co:
                continue
            f = bm.faces.new((a[k], a[q], b[q], b[k]))
            f.normal_update()
            if f.normal.dot(hint(f.calc_center_median())) < 0:
                f.normal_flip()
    return bm


def away(p):
    p = Vector(p)
    return lambda c: c - p


def toward(p):
    p = Vector(p)
    return lambda c: p - c


def radial(sign):
    return lambda c: Vector((c.x - X0, c.y - Y0, 0.0)) * sign


def rounded_section(r0, r1, z0, z1, c, n=5):
    pts = []
    for (cr, cz, a0) in ((r1 - c, z1 - c, 0), (r0 + c, z1 - c, 90), (r0 + c, z0 + c, 180), (r1 - c, z0 + c, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cr + c * math.cos(a), cz + c * math.sin(a)))
    return pts


def ring(r0, r1, z0, z1, c, seg=SEG, center=(X0, Y0)):
    """Anneau plein d'axe Z (section rectangulaire aux coins arrondis), autour de center."""
    prof = rounded_section(r0, r1, z0, z1, c)
    bm = bmesh.new()
    loops = [[bm.verts.new((center[0] + r * math.cos(2 * math.pi * k / seg), center[1] + r * math.sin(2 * math.pi * k / seg), z))
              for r, z in prof] for k in range(seg)]
    m = len(prof)
    for k in range(seg):
        q = (k + 1) % seg
        for i in range(m):
            j = (i + 1) % m
            bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def solid_disk(r, z0, z1, seg=SEG, center=(X0, Y0), r_in=0.0):
    """Disque (ou couronne si r_in) plein d'axe Z."""
    prof = [(r_in, z1), (r, z1), (r, z0), (r_in, z0)] if r_in else [(0.0, z1), (r, z1), (r, z0), (0.0, z0)]
    bm = bmesh.new()
    loops = [[bm.verts.new((center[0] + rr * math.cos(2 * math.pi * k / seg), center[1] + rr * math.sin(2 * math.pi * k / seg), z))
              for rr, z in prof] for k in range(seg)]
    closed = bool(r_in)
    for k in range(seg):
        q = (k + 1) % seg
        for i in range(len(prof) if closed else len(prof) - 1):
            j = (i + 1) % len(prof)
            bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


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


def sphere(r, seg=32, rings_=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings_, radius=r)
    return bm


def wall_point(az_deg, z, inset=0.0, r=IN_R):
    a = math.radians(az_deg)
    d = Vector((math.cos(a), math.sin(a), 0.0))
    return Vector((X0, Y0, z)) + d * (r - inset), -d


def wall_frame(az_deg, z, inset=0.0):
    """Repère posé sur la paroi intérieure : X vertical (+Z monde), Z normale vers l'axe, Y = Z × X."""
    p, n = wall_point(az_deg, z, inset)
    x = Vector((0, 0, 1))
    y = n.cross(x)
    m = Matrix((x, y, n)).transposed().to_4x4()
    m.translation = p
    return m


def along(p0, p1):
    """Matrice qui envoie l'axe Z local sur le segment p0 -> p1 (origine au milieu)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m = d.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    m.translation = (p0 + p1) / 2
    return m


# ------------------------------------------------------------------------------------------------ nettoyage
def remove_object(o):
    data = o.data
    if o.animation_data:
        for t in o.animation_data.nla_tracks:
            for st in t.strips:
                if st.action and st.action.users <= 1:
                    bpy.data.actions.remove(st.action)
    bpy.data.objects.remove(o)
    if isinstance(data, bpy.types.Mesh) and data.users == 0:
        bpy.data.meshes.remove(data)
    elif isinstance(data, bpy.types.Light) and data.users == 0:
        bpy.data.lights.remove(data)


parent_col = next(c for c in bpy.data.collections if "Module_Arrimage" in c.children)
cols = {}
for cname in ("Module_Sas", "Int_Sas"):
    c = bpy.data.collections.get(cname)
    if c is None:
        c = bpy.data.collections.new(cname)
        parent_col.children.link(c)
    for o in list(c.objects):
        remove_object(o)
    cols[cname] = c
for o in list(bpy.data.objects):
    if o.name.startswith("Lum_Sas_"):
        remove_object(o)
for name in ("Interactif_Trappe_Nadir", "Arrimage_Port_Nadir", "Arrimage_Port_Nadir_Bride"):
    o = bpy.data.objects.get(name)
    if o:
        remove_object(o)


# ------------------------------------------------------------------------------------------------ perçage de l'Arrimage
CUT_SIDES = 32
CUT_Z = (-2.65, -1.15)


def cut_hole(obj):
    """Trou polygonal (CUT_SIDES côtés, rayon inscrit CUT_R) d'axe Z sur l'axe du sas, entre CUT_Z : les faces voisines
    sont recoupées par les plans des côtés (coordonnées de texture interpolées), celles de l'intérieur supprimées.
    (Un booléen exact ruinait le couloir, maillage ouvert : la moitié de ses faces disparaissait.)"""
    if obj.get("trou_sas"):
        return "deja"
    M = obj.matrix_world
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(M)
    before = len(bm.faces)
    axis = Vector((X0, Y0, 0.0))

    def near(f, reach):
        # Boîte englobante de la face contre la région du trou (les faces de la coque sont plus grandes que lui).
        lo = [min(v.co[i] for v in f.verts) for i in range(3)]
        hi = [max(v.co[i] for v in f.verts) for i in range(3)]
        return lo[2] <= CUT_Z[1] and hi[2] >= CUT_Z[0] and lo[0] <= X0 + reach and hi[0] >= X0 - reach \
            and lo[1] <= Y0 + reach and hi[1] >= Y0 - reach
    for k in range(CUT_SIDES):
        a = 2 * math.pi * (k + 0.5) / CUT_SIDES
        n = Vector((math.cos(a), math.sin(a), 0.0))
        faces = [f for f in bm.faces if near(f, 1.0)]
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=axis + n * CUT_R, plane_no=n, dist=1e-5)
    normals = [Vector((math.cos(2 * math.pi * (k + 0.5) / CUT_SIDES), math.sin(2 * math.pi * (k + 0.5) / CUT_SIDES), 0.0))
               for k in range(CUT_SIDES)]
    inside = [f for f in bm.faces
              if CUT_Z[0] <= f.calc_center_median().z <= CUT_Z[1]
              and all((f.calc_center_median() - axis).dot(n) < CUT_R - 1e-4 for n in normals)]
    bmesh.ops.delete(bm, geom=inside, context='FACES')
    bm.transform(M.inverted())
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj["trou_sas"] = True
    return [before, len(obj.data.polygons), len(inside)]


def clear_floor(obj):
    """Retire du plancher, autour de l'écoutille, les îlots posés sur l'ancienne trappe verrouillée : sac beige et ses
    deux sangles, petite main courante et ses pieds, ferrure de l'ancienne trappe (les dalles du plancher restent)."""
    if obj.get("sas_degage"):
        return "deja"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    M = obj.matrix_world
    seen, doomed = set(), []
    clutter = ({"Int_Sac_Beige"}, {"Int_Noir"}, {"Int_Main_Courante"}, {"Int_Jaune", "Int_Main_Courante"}, {"Int_Metal"})
    for f in bm.faces:
        if f in seen:
            continue
        stack, isl = [f], []
        seen.add(f)
        while stack:
            g = stack.pop()
            isl.append(g)
            for v in g.verts:
                for h in v.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        pts = [M @ v.co for g in isl for v in g.verts]
        lo = [min(p[i] for p in pts) for i in range(3)]
        hi = [max(p[i] for p in pts) for i in range(3)]
        mats = {obj.data.materials[g.material_index].name for g in isl}
        if mats in clutter and lo[0] > X0 - 0.85 and hi[0] < X0 + 0.97 and max(abs(lo[1]), abs(hi[1])) < 0.5 \
                and lo[2] > FLOOR_Z - 0.01 and hi[2] < -1.0:
            doomed += isl
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    obj["sas_degage"] = True
    return len(doomed)


cuts = {n: cut_hole(bpy.data.objects[n]) for n in ("Arrimage_Couloir-col", "Arrimage_Coque-col")}
cuts["degagement"] = clear_floor(bpy.data.objects["Arrimage_Couloir-col"])


# ------------------------------------------------------------------------------------------------ coque extérieure
def build_hull():
    b = Builder()
    C = (X0, Y0, -4.4)
    # Col du puits (sous la coque de l'Arrimage) et bride d'amarrage.
    b.add(surface([(0.85, -1.95), (0.85, -2.80)], radial(1)), "coque", uv="cyl")
    b.add(ring(0.80, 1.00, -2.92, -2.78, 0.02), "furtif")
    # Module : dessus, arrondi, flanc, cône, fond (appui de la porte).
    prof = [(0.84, TOP_Z)]
    for i in range(7):
        a = math.radians(90 - 90 * i / 6)
        prof.append((HULL_R - 0.12 + 0.12 * math.cos(a), TOP_Z - 0.12 + 0.12 * math.sin(a)))
    prof += [(HULL_R, -3.6), (HULL_R, -4.4), (HULL_R, -5.2), (HULL_R, -5.42)]
    for i in range(1, 6):
        t = i / 5
        prof.append((HULL_R - (HULL_R - 0.72) * t, -5.42 + (SEAT_Z + 0.04 + 5.42) * t))
    b.add(surface(prof, away(C)), "coque", uv="cyl")
    # Cerclages.
    for z in (-3.12, -5.22):
        b.add(ring(HULL_R - 0.02, HULL_R + 0.045, z - 0.06, z + 0.06, 0.015), "furtif")
    # Cadre de la porte : lèvre d'appui (Ø 1,00 -> 1,46) sur le fond.
    b.add(ring(PASS_R, 0.73, SEAT_Z, SEAT_Z + 0.05, 0.012), "furtif")
    # Paumelles fixes de la porte extérieure (axe X, côté −Y).
    for x in (-0.36, 0.0, 0.36):
        b.add(cylinder(0.028, 0.10, 24), "furtif",
              Matrix.Translation((X0 + x, Y0 - DOOR_R - 0.005, SEAT_Z - DOOR_T / 2)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        b.add(soft_box((0.05, 0.05, 0.012), 0.006, 0.02), "furtif",
              Matrix.Translation((X0 + x, Y0 - DOOR_R - 0.04, SEAT_Z + 0.01)))
    # Mains courantes extérieures pour la sortie (flanc et fond).
    for az in (40, 140, 220, 320):
        a = math.radians(az)
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = []
        for z in (-3.35, -3.35, -5.05, -5.05):
            pts.append(Vector((X0, Y0, z)) + d * (HULL_R + (0.0 if len(pts) in (0, 3) else 0.09)))
        b.add(tube(pts, 0.017, 12), "poignee_ext")
    for az in (0, 180):
        a = math.radians(az)
        d = Vector((math.cos(a), math.sin(a), 0))
        t = Vector((-math.sin(a), math.cos(a), 0))
        base = Vector((X0, Y0, -5.72)) + d * 0.93
        nrm = (d * 0.4 + Vector((0, 0, -0.55))).normalized()
        pts = [base - t * 0.25, base - t * 0.25 + nrm * 0.08, base + t * 0.25 + nrm * 0.08, base + t * 0.25]
        b.add(tube(pts, 0.017, 12), "poignee_ext")
    return b.write("Sas_Coque-col", cols["Module_Sas"])


# ------------------------------------------------------------------------------------------------ intérieur
def build_interior():
    b = Builder()
    C = (X0, Y0, -4.4)
    # Cadre de l'écoutille du plancher (métal et liseré jaune, comme les autres écoutilles).
    b.add(ring(TUNNEL_R - 0.005, 0.47, FLOOR_Z - 0.03, FLOOR_Z + 0.04, 0.015), "metal")
    b.add(ring(0.465, 0.50, FLOOR_Z - 0.02, FLOOR_Z + 0.025, 0.01), "jaune")
    # Puits : paroi, deux nervures, main courante.
    b.add(surface([(TUNNEL_R, FLOOR_Z - 0.01), (TUNNEL_R, CEIL_Z)], radial(-1), 64), "panneau", uv="cyl")
    for z in (-1.85, -2.55):
        b.add(ring(TUNNEL_R - 0.025, TUNNEL_R + 0.002, z - 0.025, z + 0.025, 0.008, 64), "metal")
    for az in (90, 270):
        a = math.radians(az)
        d = Vector((math.cos(a), math.sin(a), 0))
        p = lambda z, r: Vector((X0, Y0, z)) + d * r
        b.add(tube([p(-1.45, TUNNEL_R), p(-1.48, TUNNEL_R - 0.07), p(-2.85, TUNNEL_R - 0.07), p(-2.88, TUNNEL_R)],
                   0.014, 12), "main")
    # Paumelles fixes de l'écoutille du haut (axe Y, côté −X).
    for y in (-0.19, 0.19):
        b.add(cylinder(0.022, 0.10, 20), "metal",
              Matrix.Translation((X0 - 0.475, Y0 + y, FLOOR_Z + 0.04)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        b.add(soft_box((0.05, 0.045, 0.01), 0.005, 0.02), "metal", Matrix.Translation((X0 - 0.52, Y0 + y, FLOOR_Z + 0.045)))
    # Plafond, hiloire du puits.
    b.add(surface([(TUNNEL_R, CEIL_Z), (IN_R, CEIL_Z)], toward((X0, Y0, -10.0))), "gris")
    b.add(ring(TUNNEL_R - 0.015, 0.50, CEIL_Z - 0.05, CEIL_Z + 0.01, 0.015), "metal")
    b.add(ring(0.495, 0.53, CEIL_Z - 0.035, CEIL_Z + 0.005, 0.01), "jaune")
    # Paroi, cône du fond, col du passage.
    b.add(surface([(IN_R, CEIL_Z), (IN_R, -3.6), (IN_R, -4.4), (IN_R, -5.0), (IN_R, WALL_BOT)], toward(C)), "panneau", uv="cyl")
    cone = [(IN_R - (IN_R - PASS_R) * i / 6, WALL_BOT - (WALL_BOT - PASS_Z) * i / 6) for i in range(7)]
    b.add(surface(cone, toward((X0, Y0, -4.0))), "gris")
    b.add(surface([(PASS_R, PASS_Z), (PASS_R, SEAT_Z)], radial(-1)), "metal", uv="cyl")
    b.add(ring(PASS_R - 0.02, PASS_R + 0.06, PASS_Z - 0.01, PASS_Z + 0.03, 0.01), "jaune")
    # Nervures circulaires et montants (jonctions des panneaux).
    for z in (-3.62, -4.86):
        b.add(ring(IN_R - 0.035, IN_R + 0.002, z - 0.03, z + 0.03, 0.01), "gris")
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        d = Vector((math.cos(a), math.sin(a), 0))
        t = Vector((-math.sin(a), math.cos(a), 0))
        m = Matrix((d, t, Vector((0, 0, 1)))).transposed().to_4x4()
        m.translation = Vector((X0, Y0, (CEIL_Z + WALL_BOT) / 2)) + d * (IN_R - 0.012)
        b.add(soft_box((0.014, 0.022, (WALL_BOT - CEIL_Z) / -2 - 0.01), 0.006, 0.05), "gris", m)
    # Mains courantes (quatre montants verticaux sur pattes).
    for az in (45, 135, 225, 315):
        pts = [wall_point(az, z, ins)[0] for z, ins in ((-3.35, 0.0), (-3.38, 0.09), (-5.12, 0.09), (-5.15, 0.0))]
        b.add(tube(pts, 0.016, 12), "main")
        for z in (-3.37, -4.25, -5.13):
            p, n = wall_point(az, z, 0.045)
            b.add(soft_box((0.018, 0.018, 0.045), 0.006, 0.02), "metal", Matrix.Translation(p) @ n.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    # Luminaires du plafond (plaques minces, rien ne les recouvre).
    for x in (-0.78, 0.78):
        b.add(soft_box((0.075, 0.26, 0.012), 0.006, 0.02), "metal", Matrix.Translation((X0 + x, Y0, CEIL_Z - 0.012)))
        b.add(soft_box((0.06, 0.245, 0.004), 0.003, 0.02), "lumiere", Matrix.Translation((X0 + x, Y0, CEIL_Z - 0.024)))
    return b.write("Sas_Paroi-col", cols["Int_Sas"])


# ------------------------------------------------------------------------------------------------ écoutilles
def hinge_empty(name, loc):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'
    e.empty_display_size = 0.3
    e.location = loc
    cols["Int_Sas"].objects.link(e)
    return e


def door_object(builder, name, hinge, hatch_id, note):
    ob = builder.write(name, cols["Int_Sas"], sharp=35)
    bpy.context.view_layer.update()
    ob.parent = hinge
    ob.matrix_parent_inverse = hinge.matrix_world.inverted()
    ob["interactif"] = True
    ob["type"] = "ecoutille"
    ob["id"] = hatch_id
    ob["animation"] = "Fermeture_Ecoutilles"
    ob["charniere"] = hinge.name
    ob["ouvrable"] = True
    ob["note"] = note
    return ob


def door_collision(name, door, r, z0, z1):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=r, radius2=r, depth=z1 - z0)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(X0, Y0, (z0 + z1) / 2))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    col = bpy.data.objects.new(name, me)
    cols["Int_Sas"].objects.link(col)
    col.parent = door
    col.matrix_parent_inverse = door.matrix_world.inverted()
    return col


def animate_hinge(hinge, axis, open_angle):
    """Fermeture_Ecoutilles : image 1 ouverte, image 40 fermée (angle 0), interpolation de l'écoutille Habitation_AV."""
    src = bpy.data.objects["Charniere_Ecoutille_Habitation_AV"].animation_data.nla_tracks["Fermeture_Ecoutilles"].strips[0].action
    src_keys = None
    for layer in src.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if fc.data_path == "rotation_euler" and fc.array_index == 2:
                        src_keys = list(fc.keyframe_points)
    hinge.rotation_euler[axis] = open_angle
    hinge.keyframe_insert("rotation_euler", index=axis, frame=1)
    hinge.rotation_euler[axis] = 0.0
    hinge.keyframe_insert("rotation_euler", index=axis, frame=40)
    action = hinge.animation_data.action
    action.name = "Fermeture_Ecoutilles__" + hinge.name
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for k, ref in zip(fc.keyframe_points, src_keys or []):
                        k.interpolation = ref.interpolation
                        k.easing = ref.easing
                    fc.update()
    track = hinge.animation_data.nla_tracks.new()
    track.name = "Fermeture_Ecoutilles"
    strip = track.strips.new("Fermeture_Ecoutilles", 1, action)
    strip.name = "Fermeture_Ecoutilles"
    hinge.animation_data.action = None
    hinge.rotation_euler[axis] = open_angle


def lock_wheel(b, z, up, r=0.09):
    """Volant de verrouillage au centre d'une porte (face up = +1 dessus, −1 dessous)."""
    m = Matrix.Translation((X0, Y0, z + up * 0.035))
    b.add(torus(r, 0.011, 40, 10), "metal", m)
    b.add(cylinder(0.028, 0.05, 24), "metal", Matrix.Translation((X0, Y0, z + up * 0.02)))
    for k in range(3):
        a = 2 * math.pi * k / 3
        b.add(tube([(X0, Y0, z + up * 0.035), (X0 + r * math.cos(a), Y0 + r * math.sin(a), z + up * 0.035)], 0.008, 8), "metal")


def build_top_hatch():
    hinge = hinge_empty("Charniere_Ecoutille_Sas_Haut", (X0 - 0.475, Y0, FLOOR_Z + 0.04))
    b = Builder()
    z0, z1 = FLOOR_Z + 0.04, FLOOR_Z + 0.09
    b.add(solid_disk(0.49, z0 + 0.008, z1 - 0.008), "gris")
    b.add(ring(0.42, 0.49, z0, z1, 0.012), "metal")
    lock_wheel(b, z1, 1)
    lock_wheel(b, z0, -1, 0.07)
    # Poignée en U, dessus (côté opposé à la charnière) et dessous.
    for zz, s in ((z1, 1), (z0, -1)):
        pts = [(X0 + 0.3, Y0 - 0.12, zz), (X0 + 0.3, Y0 - 0.12, zz + s * 0.05), (X0 + 0.3, Y0 + 0.12, zz + s * 0.05), (X0 + 0.3, Y0 + 0.12, zz)]
        b.add(tube(pts, 0.011, 10), "jaune")
    # Nœuds de charnière mobiles et pattes.
    for y in (-0.08, 0.08):
        b.add(cylinder(0.022, 0.09, 20), "metal",
              Matrix.Translation((X0 - 0.475, Y0 + y, FLOOR_Z + 0.04)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        b.add(soft_box((0.05, 0.04, 0.008), 0.004, 0.02), "metal", Matrix.Translation((X0 - 0.43, Y0 + y, z1 + 0.004)))
    door = door_object(b, "Interactif_Ecoutille_Sas_Haut", hinge, "Ecoutille_Sas_Haut",
                       "plancher de l'Arrimage -> sas de sortie ; s'ouvre vers le haut (dans l'Arrimage)")
    door_collision("Interactif_Ecoutille_Sas_Haut-convcolonly", door, 0.48, z0, z1)
    # Ouverture : rotation de −90° autour de Y (la porte se dresse côté −X).
    animate_hinge(hinge, 1, -math.pi / 2)
    return door


def build_bottom_hatch():
    zc = SEAT_Z - DOOR_T / 2
    hinge = hinge_empty("Charniere_Ecoutille_Sas_Bas", (X0, Y0 - DOOR_R - 0.005, zc))
    b = Builder()
    zi, ze = SEAT_Z, SEAT_Z - DOOR_T
    WIN = 0.13
    # Corps : face intérieure Int_, face extérieure et tranche Metal_Furtif ; ouverture du hublot.
    b.add(surface([(WIN, zi), (DOOR_R - 0.02, zi)], lambda c: Vector((0, 0, 1))), "gris")
    b.add(surface([(DOOR_R - 0.02, zi), (DOOR_R, zi - 0.02), (DOOR_R, ze + 0.02), (DOOR_R - 0.02, ze), (WIN, ze)],
                  away((X0, Y0, zi + 0.2))), "furtif")
    b.add(surface([(WIN, zi), (WIN, ze)], radial(-1), 48), "metal", uv="cyl")
    # Hublot : vitre au milieu de l'épaisseur, bagues intérieure et extérieure.
    b.add(solid_disk(WIN + 0.005, zc - 0.004, zc + 0.004, 48), "vitrage")
    b.add(ring(WIN - 0.012, WIN + 0.05, zi - 0.002, zi + 0.025, 0.008, 48), "metal")
    b.add(ring(WIN - 0.012, WIN + 0.045, ze - 0.018, ze + 0.002, 0.006, 48), "furtif")
    for k in range(8):
        a = 2 * math.pi * (k + 0.5) / 8
        b.add(cylinder(0.006, 0.006, 6), "metal", Matrix.Translation((X0 + (WIN + 0.03) * math.cos(a), Y0 + (WIN + 0.03) * math.sin(a), zi + 0.028)))
    # Face intérieure : deux poignées jaunes, levier de verrouillage, joint.
    for y in (-0.36, 0.36):
        pts = [(X0 - 0.13, Y0 + y, zi), (X0 - 0.13, Y0 + y, zi + 0.06), (X0 + 0.13, Y0 + y, zi + 0.06), (X0 + 0.13, Y0 + y, zi)]
        b.add(tube(pts, 0.012, 10), "jaune")
    b.add(soft_box((0.03, 0.18, 0.015), 0.008, 0.02), "metal", Matrix.Translation((X0 + 0.32, Y0 + 0.18, zi + 0.02)))
    b.add(cylinder(0.035, 0.04, 24), "metal", Matrix.Translation((X0 + 0.32, Y0 + 0.02, zi + 0.02)))
    b.add(ring(DOOR_R - 0.10, DOOR_R - 0.075, zi - 0.002, zi + 0.006, 0.003), "noir")
    # Face extérieure : poignée de sortie.
    pts = [(X0 - 0.15, Y0 + 0.3, ze), (X0 - 0.15, Y0 + 0.3, ze - 0.06), (X0 + 0.15, Y0 + 0.3, ze - 0.06), (X0 + 0.15, Y0 + 0.3, ze)]
    b.add(tube(pts, 0.013, 10), "poignee_ext")
    # Nœuds de charnière mobiles et pattes (côté −Y).
    for x in (-0.18, 0.18):
        b.add(cylinder(0.028, 0.16, 24), "furtif",
              Matrix.Translation((X0 + x, Y0 - DOOR_R - 0.005, zc)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        b.add(soft_box((0.07, 0.06, 0.012), 0.006, 0.02), "furtif", Matrix.Translation((X0 + x, Y0 - DOOR_R + 0.04, ze - 0.004)))
    door = door_object(b, "Interactif_Ecoutille_Sas_Bas", hinge, "Ecoutille_Sas_Bas",
                       "porte exterieure du sas, a hublot ; s'ouvre vers le bas (vers la Terre)")
    door_collision("Interactif_Ecoutille_Sas_Bas-convcolonly", door, DOOR_R - 0.01, ze, zi)
    # Ouverture : −100° autour de X (la porte bascule vers −Z, au-delà de la verticale).
    animate_hinge(hinge, 0, -math.radians(100))
    return door


# ------------------------------------------------------------------------------------------------ scaphandre
def build_suit():
    """Scaphandre type EMU, repère local : pieds en z = 0, haut du casque vers +Z, face vers −Y, dos (sac) vers +Y."""
    b = Builder()
    for sx in (-1, 1):
        x = 0.115 * sx
        # Bottes : semelle, tige.
        b.add(soft_box((0.056, 0.135, 0.016), 0.012, 0.012), "semelle", Matrix.Translation((x, -0.03, 0.016)))
        b.add(soft_box((0.062, 0.128, 0.05), 0.035, 0.015, puff(0.006)), "tissu", Matrix.Translation((x, -0.025, 0.075)))
        b.add(cylinder(0.074, 0.12, 28), "tissu", Matrix.Translation((x, 0.0, 0.16)))
        b.add(torus(0.077, 0.012, 32, 8), "bague", Matrix.Translation((x, 0.0, 0.22)))
        # Jambe à soufflets (genou), légère flexion.
        leg = [(x, 0.0, 0.22), (x, -0.012, 0.36), (x, -0.035, 0.53), (x, -0.012, 0.70), (x * 1.06, 0.0, 0.87)]

        def leg_r(s):
            r = 0.073 + 0.024 * min(1.0, s / 0.66)
            if 0.24 < s < 0.40:
                r += 0.007 * math.sin(math.pi * (s - 0.24) / 0.16) * (0.5 + 0.5 * math.cos(2 * math.pi * (s - 0.24) / 0.032))
            return r
        b.add(tube(leg, 0.08, 24, radius_fn=leg_r), "tissu")
        # Bandes rouges (identification du chef de sortie).
        for z, s in ((0.31, 0.09), (0.64, 0.42), (0.74, 0.52)):
            r = leg_r(s)
            b.add(ring(r - 0.004, r + 0.0035, z - 0.022, z + 0.022, 0.003, 32, (x, -0.02 if z < 0.6 else -0.025)), "rouge")
        b.add(torus(0.10, 0.013, 32, 8), "bague", Matrix.Translation((x * 1.06, 0.0, 0.87)))
    # Culotte (partie basse du torse), bague de taille.
    b.add(soft_box((0.19, 0.135, 0.12), 0.07, 0.02, puff(0.015)), "tissu", Matrix.Translation((0, 0.0, 0.98)))
    b.add(torus(0.17, 0.016, 48, 8), "bague", Matrix.Translation((0, 0.0, 1.11)) @ Matrix.Diagonal((1.05, 0.82, 1.0, 1.0)))
    # Torse rigide (HUT) recouvert de tissu, épaules.
    b.add(soft_box((0.215, 0.15, 0.19), 0.09, 0.02, puff(0.02)), "tissu", Matrix.Translation((0, 0.02, 1.32)))
    # Bras : bague d'épaule, soufflets du coude, bague de poignet, gant.
    for sx in (-1, 1):
        sh = Vector((0.245 * sx, 0.0, 1.40))
        b.add(torus(0.078, 0.014, 32, 8), "bague", Matrix.Translation(sh) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        arm = [sh + Vector((0.015 * sx, 0, 0)), Vector((0.30 * sx, -0.02, 1.24)), Vector((0.325 * sx, -0.05, 1.08)),
               Vector((0.315 * sx, -0.12, 0.95)), Vector((0.30 * sx, -0.165, 0.86))]

        def arm_r(s):
            r = 0.072 - 0.016 * min(1.0, s / 0.62)
            if 0.27 < s < 0.40:
                r += 0.006 * math.sin(math.pi * (s - 0.27) / 0.13) * (0.5 + 0.5 * math.cos(2 * math.pi * (s - 0.27) / 0.026))
            return r
        b.add(tube(arm, 0.07, 22, radius_fn=arm_r), "tissu")
        wrist = arm[-1]
        d = (arm[-1] - arm[-2]).normalized()
        q = d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        b.add(torus(0.058, 0.013, 28, 8), "bague", Matrix.Translation(wrist) @ q)
        b.add(cylinder(0.052, 0.07, 24, 0.048), "gant", Matrix.Translation(wrist + d * 0.04) @ q)
        b.add(soft_box((0.042, 0.055, 0.07), 0.03, 0.012, puff(0.006)), "gant", Matrix.Translation(wrist + d * 0.13) @ q)
        b.add(soft_box((0.016, 0.018, 0.035), 0.014, 0.008), "gant",
              Matrix.Translation(wrist + d * 0.10 + Vector((-0.045 * sx, -0.02, 0))) @ q @ Matrix.Rotation(0.5 * sx, 4, 'Y'))
    # Bague de cou, casque (coque blanche, visière dorée, lampes).
    b.add(torus(0.128, 0.016, 48, 8), "bague", Matrix.Translation((0, -0.01, 1.52)))
    hc = Vector((0, -0.02, 1.69))
    b.add(sphere(0.185, 40, 20), "dur", Matrix.Translation(hc))
    vis = bmesh.new()
    rows, cols_ = 14, 30
    grid = []
    for i in range(rows + 1):
        el = math.radians(-38 + 70 * i / rows)
        row = []
        for j in range(cols_ + 1):
            az = math.radians(-78 + 156 * j / cols_)
            dvec = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
            row.append(vis.verts.new(dvec * 0.192))
        grid.append(row)
    for i in range(rows):
        for j in range(cols_):
            vis.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    vis.normal_update()
    for f in vis.faces:
        if f.normal.dot(f.calc_center_median()) < 0:
            f.normal_flip()
    bmesh.ops.solidify(vis, geom=vis.faces[:], thickness=0.004)
    b.add(vis, "visiere", Matrix.Translation(hc))
    b.add(ring(0.17, 0.198, -0.02, 0.02, 0.008, 48, (0, 0)), "dur",
          Matrix.Translation(hc + Vector((0, 0, -0.055))) @ Matrix.Rotation(-0.35, 4, 'X'))
    for sx in (-1, 1):
        lp = hc + Vector((0.175 * sx, -0.05, 0.07))
        b.add(soft_box((0.022, 0.05, 0.03), 0.01, 0.01), "dur", Matrix.Translation(lp))
        b.add(cylinder(0.018, 0.012, 20), "optique", Matrix.Translation(lp + Vector((0, -0.055, 0))) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    # Sac dorsal (PLSS) sous housse, antenne.
    b.add(soft_box((0.235, 0.105, 0.30), 0.06, 0.025, puff(0.008)), "tissu", Matrix.Translation((0, 0.265, 1.25)))
    b.add(soft_box((0.20, 0.07, 0.07), 0.03, 0.02), "tissu", Matrix.Translation((0, 0.25, 0.90)))
    b.add(cylinder(0.008, 0.16, 8), "noir", Matrix.Translation((0.17, 0.33, 1.62)))
    # Module de commande poitrine (DCM) : boîtier, afficheur, molettes, flexibles vers le sac.
    b.add(soft_box((0.14, 0.055, 0.065), 0.015, 0.012), "dur", Matrix.Translation((0, -0.22, 1.27)))
    b.add(soft_box((0.05, 0.03, 0.002), 0.004, 0.01), "noir", Matrix.Translation((0.06, -0.24, 1.336)))
    for k, x in enumerate((-0.10, -0.06, -0.02)):
        b.add(cylinder(0.014, 0.018, 16), "noir" if k else "rouge", Matrix.Translation((x, -0.25, 1.34)))
    b.add(cylinder(0.022, 0.03, 20), "bague",
          Matrix.Translation((0.12, -0.24, 1.27)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    for sx in (-1, 1):
        b.add(tube([(0.13 * sx, -0.20, 1.25), (0.20 * sx, -0.16, 1.18), (0.25 * sx, -0.02, 1.13), (0.23 * sx, 0.18, 1.12)],
                   0.012, 10), "tissu")
    # Support mural : plaque du sac et deux bras jusqu'à la paroi.
    b.add(soft_box((0.17, 0.02, 0.22), 0.01, 0.03), "metal", Matrix.Translation((0, 0.39, 1.25)))
    for z in (1.10, 1.40):
        b.add(soft_box((0.20, 0.03, 0.02), 0.008, 0.03), "metal", Matrix.Translation((0, 0.41, z)))
    return b


def build_equipment():
    b = Builder()
    # Sacs CTB sur la paroi −Y, tenus par deux sandows.
    seeds = iter((0.7, 2.2, 3.9, 5.1))
    for z, half in ((-3.72, (0.21, 0.17, 0.10)), (-4.25, (0.19, 0.15, 0.085)), (-4.83, (0.24, 0.18, 0.11))):
        m = wall_frame(270, z) @ Matrix.Translation((0, 0, half[2] + 0.004))
        ctb_bag(b, m, half, next(seeds))
    for z in (-3.95, -4.62):
        a, _ = wall_point(270 - 17, z, 0.01)
        c, _ = wall_point(270 + 17, z, 0.01)
        over = Vector((X0, Y0 - IN_R + 0.235, z))
        bungee(b, a, c, over, Vector((0, 1, 0)))
    # Extincteur (paroi +X) dans ses deux colliers.
    p, n = wall_point(0, -4.45, 0.085)
    b.add(cylinder(0.062, 0.38, 32), "extincteur", Matrix.Translation(p))
    b.add(revolve([(0.0, 0.19), (0.062, 0.19), (0.05, 0.22), (0.02, 0.235), (0.0, 0.235)], 24), "extincteur", Matrix.Translation(p))
    b.add(cylinder(0.018, 0.05, 16), "metal", Matrix.Translation(p + Vector((0, 0, 0.255))))
    b.add(soft_box((0.012, 0.06, 0.008), 0.004, 0.01), "noir", Matrix.Translation(p + Vector((0, 0.03, 0.285))))
    b.add(tube([p + Vector((0, 0.02, 0.27)), p + Vector((-0.02, 0.07, 0.25)), p + Vector((-0.03, 0.075, 0.10))], 0.009, 10), "noir")
    b.add(cylinder(0.014, 0.05, 12, 0.006), "noir", Matrix.Translation(p + Vector((-0.03, 0.075, 0.075))))
    for z in (-0.11, 0.11):
        b.add(ring(0.062, 0.072, z - 0.015, z + 0.015, 0.003, 32, (p.x, p.y)), "metal", Matrix.Translation((0, 0, p.z)))
        b.add(soft_box((0.025, 0.03, 0.015), 0.005, 0.01), "metal", Matrix.Translation(p + Vector((0.075, 0, z))))
    # Bouteille d'oxygène portable et masque (paroi −X).
    p, n = wall_point(180, -4.45, 0.08)
    b.add(cylinder(0.058, 0.32, 32), "oxygene", Matrix.Translation(p))
    b.add(revolve([(0.0, 0.16), (0.058, 0.16), (0.03, 0.2), (0.0, 0.2)], 24), "oxygene", Matrix.Translation(p))
    b.add(cylinder(0.02, 0.06, 16), "metal", Matrix.Translation(p + Vector((0, 0, 0.22))))
    b.add(tube([p + Vector((0, 0, 0.24)), p + Vector((0.03, 0.06, 0.28)), p + Vector((0.07, 0.10, 0.18)), p + Vector((0.07, 0.09, 0.05))],
               0.007, 8), "noir")
    b.add(revolve([(0.0, 0.0), (0.05, 0.0), (0.06, 0.03), (0.045, 0.07), (0.0, 0.08)], 24), "masque",
          Matrix.Translation(p + Vector((0.07, 0.09, 0.0))) @ Matrix.Rotation(math.pi, 4, 'X'))
    for z in (-0.10, 0.10):
        b.add(ring(0.058, 0.068, z - 0.015, z + 0.015, 0.003, 32, (p.x, p.y)), "metal", Matrix.Translation((0, 0, p.z)))
    # Longes de sécurité accrochées à la main courante 315° : enrouleur et mousquetons.
    p, n = wall_point(315, -3.70, 0.13)
    b.add(soft_box((0.05, 0.035, 0.07), 0.015, 0.012), "dur", Matrix.Translation(p + n * 0.02))
    b.add(torus(0.028, 0.006, 16, 6), "metal", Matrix.Translation(p + Vector((0, 0, 0.085))) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    loop = [p + Vector((0, 0, -0.07))]
    for k in range(1, 9):
        loop.append(p + n * (0.03 + 0.04 * math.sin(k / 2.0)) + Vector((0.03 * math.cos(k), 0.03 * math.sin(k), -0.07 - 0.05 * k)))
    b.add(tube(loop, 0.006, 8), "longe")
    b.add(torus(0.022, 0.005, 16, 6), "metal", Matrix.Translation(loop[-1] + Vector((0, 0, -0.02))) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    # Batteries de rechange sous sangle (paroi 135°), sacoche d'outils blanche (paroi 210°).
    for k, z in enumerate((-4.98, -4.80)):
        m = wall_frame(135, z) @ Matrix.Translation((0, 0, 0.045))
        b.add(soft_box((0.075, 0.11, 0.04), 0.008, 0.015), "alu_sombre", m)
        b.add(soft_box((0.03, 0.05, 0.001), 0.003, 0.01), "etiquette", m @ Matrix.Translation((0.02, 0, 0.041)))
    m = wall_frame(135, -4.89)
    b.add(ribbon([m @ Vector((0, -0.16, 0.0)), m @ Vector((0, -0.12, 0.095)), m @ Vector((0, 0.12, 0.095)), m @ Vector((0, 0.16, 0.0))],
                 m.to_3x3() @ Vector((1, 0, 0)), 0.03, 0.003), "sangle")
    m = wall_frame(205, -5.05) @ Matrix.Translation((0, 0, 0.07))
    b.add(soft_box((0.12, 0.17, 0.065), 0.03, 0.02, chain(puff(0.01), wrinkles(0.002, 1.3))), "sac_blanc", m)
    b.add(soft_box((0.13, 0.008, 0.06), 0.004, 0.01), "velcro", m @ Matrix.Translation((0, -0.15, 0.03)))
    # Fiche de procédure (paroi 60°).
    m = wall_frame(60, -3.62) @ Matrix.Translation((0, 0, 0.004))
    b.add(soft_box((0.14, 0.10, 0.002), 0.004, 0.01), "etiquette", m)
    for k in range(7):
        w = (0.09, 0.07, 0.10, 0.06, 0.08, 0.10, 0.05)[k]
        b.add(soft_box((0.004, w, 0.0008), 0.0008, 0.01), "encre", m @ Matrix.Translation((0.11 - 0.032 * k, -0.09 + w, 0.002)))
    return b


def ctb_bag(b, m, half, seed=0.0):
    """Sac de transfert souple (repère local : Z = dessus), comme ceux de l'Habitation (build_habitation_props.py)."""
    hx, hy, hz = half
    deform = chain(puff(0.012), wrinkles(0.002, seed))
    fmap = soft_map(half, 0.03, deform)
    b.add(soft_box(half, 0.03, 0.02, deform), "ctb", m)
    top = lambda u, v: fmap(Vector((u * hx, v * hy, hz)))
    for su in (-0.55, 0.55):
        b.add(soft_box((0.05, 0.012, 0.0015), 0.004, 0.01), "velcro", m @ Matrix.Translation(top(su, -0.78)))
    p = fmap(Vector((hx, 0.0, 0.0)))
    lm = m @ Matrix.Translation(p + Vector((0.002, 0, 0))) @ Matrix.Rotation(math.pi / 2, 4, 'Y')
    b.add(soft_box((0.032, min(0.07, hy * 0.5), 0.0012), 0.003, 0.01), "etiquette", lm)
    ring_pts = []
    for k in range(65):
        a = 2 * math.pi * k / 64
        c, s = math.cos(a), math.sin(a)
        k_sq = max(abs(c), abs(s))
        ring_pts.append(top(c / k_sq * 0.86, s / k_sq * 0.84) + Vector((0, 0, 0.0025)))
    b.add(tube(ring_pts, 0.0035, 6), "glissiere", m)
    strap = [top(-0.98, 0.25) + Vector((0, 0, 0.002)), top(-0.5, 0.25) + Vector((0, 0, 0.003)),
             top(0.0, 0.25) + Vector((0, 0, 0.003)), top(0.5, 0.25) + Vector((0, 0, 0.003)),
             top(0.98, 0.25) + Vector((0, 0, 0.002))]
    b.add(ribbon([m @ v for v in strap], m.to_3x3() @ Vector((0, 1, 0)), 0.026, 0.003), "sangle_ctb", smooth=False)


def bungee(b, a, c, over, hook_normal):
    a, c, over = Vector(a), Vector(c), Vector(over)
    b.add(tube([a, a.lerp(over, 0.5) + (over - (a + c) / 2) * 0.3, over, c.lerp(over, 0.5) + (over - (a + c) / 2) * 0.3, c],
               0.0045, 8), "sandow")
    for p in (a, c):
        b.add(cylinder(0.008, 0.012, 12), "crochet",
              Matrix.Translation(p) @ Vector(hook_normal).to_track_quat('Z', 'Y').to_matrix().to_4x4())


# ------------------------------------------------------------------------------------------------ assemblage
hull = build_hull()
interior = build_interior()
top_door = build_top_hatch()
bottom_door = build_bottom_hatch()
suit_b = build_suit()
# Combinaison debout contre la paroi +Y, face à l'axe ; pieds au-dessus du cône du fond.
SUIT_AT = Matrix.Translation((X0, Y0 + IN_R - 0.425, -5.33))
bmesh.ops.transform(suit_b.bm, matrix=SUIT_AT, verts=suit_b.bm.verts)
suit = suit_b.write("Interactif_Combinaison", cols["Int_Sas"])
suit["interactif"] = True
suit["type"] = "combinaison"
suit["id"] = "Combinaison_Sas"
equipment = build_equipment().write("Sas_Equipements", cols["Int_Sas"])

# Lampes : copies de Lum_Arrimage_2 (mêmes réglages ; station.gd recalibre toutes les Lum_*).
src_lum = bpy.data.objects["Lum_Arrimage_2"]
lums = []
for k, z in enumerate((-3.55, -4.95), 1):
    lo = src_lum.copy()
    lo.data = src_lum.data.copy()
    lo.name = lo.data.name = "Lum_Sas_%d" % k
    lo.animation_data_clear()
    bpy.data.collections["Lumieres_Interieures"].objects.link(lo)
    lo.location = (X0, Y0, z)
    lums.append(lo.name)

scene.frame_set(1)
bpy.ops.wm.save_mainfile()
result = {"percages": cuts, "objets": {o.name: len(o.data.polygons) for o in (hull, interior, top_door, bottom_door, suit, equipment)},
          "lampes": lums, "enregistre": True}
