# Outil hors-jeu : fonctions de modélisation procédurale partagées par les scripts d'accessoires (build_wc.py…),
# chargées dans le Blender ouvert par exec(open(".../props_kit.py").read()). Mêmes formes que celles de
# build_habitation_props.py : boîte à coins arrondis maillée finement (soft_box) et ses déformations, tubes lissés,
# solides de révolution, rubans.
import bpy, bmesh, math
from mathutils import Matrix, Vector

T = Matrix.Translation


def material(name, color, metallic=0.0, roughness=0.8):
    """Matériau Principled simple ; créé s'il n'existe pas, réglé sinon (ne pas l'utiliser pour un matériau texturé
    d'origine : le prendre tel quel dans bpy.data.materials)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color, 1.0)
    return m


class Mesh:
    """Accumulateur de pièces (bmesh) à matériaux multiples ; mats : clé -> matériau."""

    def __init__(self, mats):
        self.bm = bmesh.new()
        self.slots = []
        self.mats = mats

    def add(self, part, key, matrix=Matrix(), smooth=True):
        m = self.mats[key]
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

    def write(self, obj_name, collection):
        """Remplace le maillage de obj_name (créé dans collection s'il n'existe pas) ; nom, extras gardés."""
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
            collection.objects.link(obj)
        else:
            old = obj.data
            obj.data = me
            if old.users == 0:
                bpy.data.meshes.remove(old)
        obj.matrix_world = Matrix()
        return obj


def soft_map(half, r, deform=None):
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


def puff(amount, axes=(0, 1, 2)):
    def d(q, n, t):
        a = max(range(3), key=lambda i: abs(n[i]))
        if a not in axes:
            return q
        k = 1.0
        for i in range(3):
            if i != a:
                k *= max(0.0, 1.0 - t[i] * t[i])
        return q + n * amount * k
    return d


def chain(*fns):
    def d(q, n, t):
        for fn in fns:
            q = fn(q, n, t)
        return q
    return d


def wrinkles(amount, seed=0.3):
    def d(q, n, t):
        s = math.sin(q.x * 31 + seed) * math.sin(q.z * 23 + 2 * seed) + 0.5 * math.sin(q.y * 41 + q.x * 17)
        return q + n * amount * s
    return d


def cylinder(r, depth, seg=24, r2=None):
    """Cylindre (ou tronc de cône) d'axe Z centré à l'origine."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    return bm


def revolve(profile, seg=32):
    """Solide de révolution autour de Z d'un profil (r, z) ; un point sur l'axe ferme le solide."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z))
              for k in range(seg)] for r, z in profile]
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            q = (k + 1) % seg
            bm.faces.new((a[k], a[q], b[q], b[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def torus(R, r, seg=32, ring=10):
    """Tore d'axe Z (rayon R, section r)."""
    prof = [(R + r * math.cos(2 * math.pi * k / ring), r * math.sin(2 * math.pi * k / ring)) for k in range(ring)]
    bm = bmesh.new()
    rings = [[bm.verts.new((pr * math.cos(2 * math.pi * k / seg), pr * math.sin(2 * math.pi * k / seg), pz))
              for pr, pz in prof] for k in range(seg)]
    for k in range(seg):
        q = (k + 1) % seg
        for i in range(ring):
            j = (i + 1) % ring
            bm.faces.new((rings[k][i], rings[k][j], rings[q][j], rings[q][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def tube(points, r, seg=10, radius_fn=None):
    """Tube lissé (Catmull-Rom) le long d'une polyligne, repère transporté parallèlement (pas de vrillage),
    extrémités fermées ; radius_fn(abscisse) module le rayon (flexible annelé)."""
    pts = [Vector(p) for p in points]
    smooth = []
    for i in range(len(pts) - 1):
        p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
        steps = max(2, int((p2 - p1).length / (0.004 if radius_fn else 0.02)))
        for k in range(steps):
            t = k / steps
            smooth.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    smooth.append(pts[-1])
    bm = bmesh.new()
    rings, s, a = [], 0.0, None
    for i, p in enumerate(smooth):
        if i:
            s += (p - smooth[i - 1]).length
        tg = (smooth[min(i + 1, len(smooth) - 1)] - smooth[max(i - 1, 0)]).normalized()
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


def corrugated(points, r, pitch=0.012, depth=0.0025, seg=12):
    """Flexible annelé."""
    return tube(points, r, seg, radius_fn=lambda s: r + depth * math.sin(2 * math.pi * s / pitch))


# ------------------------------------------------------------------------------------------------ rideau à anneaux
def build_curtain(name, cid, x0, x1, collection, mats, gather="left", y_rail=-1.285, z_top=0.495, z_bot=-0.49,
                  n_cols=48, n_rows=26, open_w=0.16):
    """Rideau plissé à anneaux sur rail (plan y = y_rail, de x0 à x1, du rail z_top au bas z_bot), objet name
    (recréé) : forme de base = ouvert, regroupé contre le bord gather (« left » : x0, « right » : x1) ; clé de forme
    « Ferme » = déployé sur toute l'ouverture. Deux couches de tissu à 3 mm (vu des deux côtés), anneaux qui suivent
    le tissu, rail et supports fixes. mats : « rideau » et « metal ». Extras : type « rideau », id cid.
    scripts/station.gd anime la clé de forme (poids exporté : 0, ouvert)."""
    def point(i, j, closed, layer):
        u = i / n_cols
        v = j / n_rows
        width = (x1 - x0 - 0.02) if closed else open_w
        amp = 0.016 if closed else 0.032
        x = x0 + 0.01 + width * u if gather == "left" else x1 - 0.01 - width * (1 - u)
        z = z_top - 0.03 - (z_top - z_bot - 0.03) * v
        pleat = amp * math.sin(math.pi * i / 2)
        # Bas du rideau un peu libre : ondulation et léger évasement quand il est regroupé.
        sway = (0.004 if closed else 0.012) * v * math.sin(3.1 * u + 2 * v)
        if not closed:
            x += 0.03 * v * v * ((u - 0.3) if gather == "left" else (u - 0.7))
        return Vector((x, y_rail + pleat + sway + (0.0015 if layer else -0.0015), z))

    old = bpy.data.objects.get(name)
    if old:
        data = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(data)
    bm = bmesh.new()
    keyed = []        # (sommet, position fermée)
    grids = []
    for layer in (0, 1):
        g = [[None] * (n_rows + 1) for _ in range(n_cols + 1)]
        for i in range(n_cols + 1):
            for j in range(n_rows + 1):
                v = bm.verts.new(point(i, j, False, layer))
                keyed.append((v, point(i, j, True, layer)))
                g[i][j] = v
        grids.append(g)
        for i in range(n_cols):
            for j in range(n_rows):
                q = (g[i][j], g[i + 1][j], g[i + 1][j + 1], g[i][j + 1])
                bm.faces.new(q if layer else tuple(reversed(q))).smooth = True
    # Tranches (bords et ourlets) entre les deux couches.
    g0, g1 = grids
    border = [(i, 0) for i in range(n_cols + 1)] + [(n_cols, j) for j in range(1, n_rows + 1)] + \
             [(i, n_rows) for i in range(n_cols - 1, -1, -1)] + [(0, j) for j in range(n_rows - 1, 0, -1)]
    for (a, b_), (c, d) in zip(border, border[1:] + border[:1]):
        bm.faces.new((g0[a][b_], g0[c][d], g1[c][d], g1[a][b_])).smooth = True

    def merge(part, closed_of):
        vmap = {v: bm.verts.new(v.co) for v in part.verts}
        for f in part.faces:
            g = bm.faces.new([vmap[v] for v in f.verts])
            g.material_index = 1
            g.smooth = True
        for v in vmap.values():
            keyed.append((v, closed_of(v.co)))
        part.free()

    # Anneaux sur le rail (une colonne sur quatre, aux creux des plis) : suivent le rideau.
    for i in range(0, n_cols + 1, 4):
        po, pc = point(i, 0, False, 0), point(i, 0, True, 0)
        ring = torus(0.011, 0.0025, 16, 6)
        bmesh.ops.transform(ring, matrix=T((po.x, y_rail, z_top - 0.008)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'),
                            verts=ring.verts)
        dx = pc.x - po.x
        merge(ring, lambda co, dx=dx: co + Vector((dx, 0, 0)))
    # Rail et ses trois supports (fixes).
    fixed = Mesh(mats)
    fixed.add(tube([(x0 - 0.005, y_rail, z_top), (x1 + 0.005, y_rail, z_top)], 0.0065, 12), "metal")
    for x in (x0 + 0.01, (x0 + x1) / 2, x1 - 0.01):
        fixed.add(soft_box((0.008, 0.008, 0.02), 0.003, 0.006), "metal", T((x, y_rail, z_top + 0.022)))
    part = fixed.bm
    merge(part, lambda co: co.copy())
    bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f.material_index == 1])
    bm.verts.index_update()
    closed = {v.index: co for v, co in keyed}
    me = bpy.data.meshes.new(name)
    me.materials.append(mats["rideau"])
    me.materials.append(mats["metal"])
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    collection.objects.link(obj)
    obj.shape_key_add(name="Basis")
    key = obj.shape_key_add(name="Ferme")
    for i, co in closed.items():
        key.data[i].co = co
    key.value = 0.0  # poids par défaut exporté dans le glTF : rideau ouvert au démarrage
    obj["interactif"] = True
    obj["type"] = "rideau"
    obj["id"] = cid
    obj["forme_fermee"] = "Ferme"
    return obj
