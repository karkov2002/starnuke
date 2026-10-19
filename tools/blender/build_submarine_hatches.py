# Outil hors-jeu : remplace les portes des écoutilles axiales de E:\Blender\nuke_station.blend (Blender ouvert, extension
# MCP de Blender Lab) par le modèle de l'écoutille du sas de sortie (build_airlock.py), « façon sous-marin », mis à
# l'échelle de leur passage (Ø 1,32 m, cadre métal r 0,655–0,76 et liseré jaune r 0,755–0,80) :
#   & ./tools/blender_exec.ps1 -TimeoutS 600 -File tools/blender/build_submarine_hatches.py
# Rejouable (les volants, pivots et paumelles sont recréés ; la porte garde son objet, son nom et ses extras).
# - porte centrée sur l'axe du passage (les anciennes étaient décalées de 4 cm) : disque gris, bague métal satiné au
#   pourtour (r PORTE_R), bagues de l'axe, poignées en U jaunes sur les deux faces, nœuds de charnière ; la face arrière
#   s'arrête juste devant le cadre ;
# - volant (face avant) et contre-volant (face arrière) sur un même axe : Volant_<id> sous Pivot_Volant_<id> (axe Z =
#   normale de la porte), extras de la porte « volant », « volant_tours » : station.gd le tourne avant l'ouverture et
#   après la fermeture ; l'écoutille cargo (verrouillée, sans charnière) garde un volant fixe dans sa porte ;
# - charnière (Charniere_<id>) déplacée hors du bord de la porte (r PORTE_R + 0,02, à mi-épaisseur) : la porte ne
#   mord plus dans le cadre en pivotant ; l'animation Fermeture_Ecoutilles (rotations seules) est inchangée ;
# - Paumelle_<id> (fixe) : deux nœuds et leurs pattes vissées sur le cadre ;
# - collision « -convcolonly » : cylindre de la porte.
# Repère canonique d'une écoutille : origine au centre du passage, dans le plan de la porte fermée ; Z = normale côté
# ouverture (avant de la porte), X = vers la charnière, Y = Z × X.
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())

HATCHES = ("Arrimage_AV", "Habitation_AR", "Habitation_AV", "Commande_AR", "Missile_1", "Missile_2", "Cargo")
PORTE_R = 0.74                 # porte : repose sur la bague métal du cadre (r 0,655–0,76), dans le liseré jaune
Z0, Z1 = -0.02, 0.05           # faces arrière et avant (le cadre s'arrête à −0,025)
S = PORTE_R / 0.49             # échelle par rapport à l'écoutille du sas (r 0,49)
HINGE = Vector((PORTE_R + 0.02, 0.0, (Z0 + Z1) / 2))
WHEEL_TURNS = 1.25
SEG = 96

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
scene = bpy.context.scene
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

MATS = {
    "gris": bpy.data.materials["Int_Panneau_Gris"],
    "metal": material("Int_Metal_Satine", (0.60, 0.61, 0.63), 0.6, 0.35),
    "jaune": bpy.data.materials["Int_Jaune"],
}


class Builder:
    """Pièces bmesh à matériaux multiples, coordonnées de texture en mètres (projection en boîte selon la normale)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def add(self, part, key, matrix=Matrix()):
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
            g.smooth = True
            g.normal_update()
            ax = max(range(3), key=lambda i: abs(g.normal[i]))
            u, v = [i for i in range(3) if i != ax]
            for loop in g.loops:
                loop[self.uv].uv = (loop.vert.co[u], loop.vert.co[v])
        part.free()

    def transform(self, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=self.bm.verts)

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        for m in self.slots:
            me.materials.append(m)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        me.set_sharp_from_angle(angle=math.radians(35))
        return me


def rounded_section(r0, r1, z0, z1, c, n=5):
    pts = []
    for (cr, cz, a0) in ((r1 - c, z1 - c, 0), (r0 + c, z1 - c, 90), (r0 + c, z0 + c, 180), (r1 - c, z0 + c, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cr + c * math.cos(a), cz + c * math.sin(a)))
    return pts


def ring(r0, r1, z0, z1, c, seg=SEG):
    prof = rounded_section(r0, r1, z0, z1, c)
    bm = bmesh.new()
    loops = [[bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), z)) for r, z in prof]
             for k in range(seg)]
    for k in range(seg):
        q = (k + 1) % seg
        for i in range(len(prof)):
            j = (i + 1) % len(prof)
            bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def disk(r, z0, z1, seg=SEG):
    bm = cylinder(r, z1 - z0, seg)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, (z0 + z1) / 2))
    return bm


def lock_wheel(b, z, up, r):
    """Volant (repère canonique) : jante, moyeu, trois rayons ; face up = +1 avant, −1 arrière."""
    b.add(torus(r, 0.011 * S, 40, 10), "metal", Matrix.Translation((0, 0, z + up * 0.035 * S)))
    b.add(cylinder(0.028 * S, 0.05 * S, 24), "metal", Matrix.Translation((0, 0, z + up * 0.02 * S)))
    for k in range(3):
        a = 2 * math.pi * k / 3
        b.add(tube([(0, 0, z + up * 0.035 * S), (r * math.cos(a), r * math.sin(a), z + up * 0.035 * S)], 0.008 * S, 8), "metal")


def door_parts(with_wheel):
    """Porte (repère canonique) ; le volant à part (wheel) sauf with_wheel (porte verrouillée : volant fixe)."""
    b = Builder()
    rim_in = PORTE_R - 0.07 * S
    b.add(disk(rim_in + 0.005 * S, Z0 + 0.008 * S, Z1 - 0.008 * S), "gris")
    b.add(ring(rim_in, PORTE_R, Z0, Z1, 0.012 * S), "metal")
    for zz, s in ((Z1, 1), (Z0, -1)):
        b.add(cylinder(0.04 * S, 0.008 * S, 32), "metal", Matrix.Translation((0, 0, zz + s * 0.002 * S)))
        # Poignée en U, côté opposé à la charnière.
        x = -0.3 * S
        pts = [(x, -0.12 * S, zz), (x, -0.12 * S, zz + s * 0.05 * S), (x, 0.12 * S, zz + s * 0.05 * S), (x, 0.12 * S, zz)]
        b.add(tube(pts, 0.011 * S, 10), "jaune")
    # Nœuds de charnière mobiles et leurs pattes sur la face avant.
    for y in (-0.08 * S, 0.08 * S):
        b.add(cylinder(0.022 * S, 0.09 * S, 20), "metal", Matrix.Translation((HINGE.x, y, HINGE.z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        b.add(soft_box((0.035, 0.04 * S, 0.008), 0.004, 0.02), "metal", Matrix.Translation((PORTE_R - 0.005, y, Z1 + 0.004)))
    w = b if with_wheel else Builder()
    lock_wheel(w, Z1, 1, 0.09 * S)
    lock_wheel(w, Z0, -1, 0.07 * S)
    w.add(cylinder(0.014 * S, Z1 - Z0 + 0.03 * S, 16), "metal", Matrix.Translation((0, 0, (Z0 + Z1) / 2)))
    w.add(cylinder(0.012 * S, 0.045 * S, 16), "jaune", Matrix.Translation((0.09 * S, 0, Z1 + 0.06 * S)))
    return b, (None if with_wheel else w)


def hinge_leaf_parts():
    """Paumelle fixe (repère canonique) : deux nœuds sur l'axe, pattes vissées sur le cadre (derrière la porte)."""
    b = Builder()
    for y in (-0.19 * S, 0.19 * S):
        b.add(cylinder(0.022 * S, 0.10 * S, 20), "metal", Matrix.Translation((HINGE.x, y, HINGE.z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        b.add(soft_box((0.03, 0.04 * S, 0.03), 0.006, 0.02), "metal", Matrix.Translation((HINGE.x + 0.02, y, HINGE.z - 0.035)))
        for dy in (-0.025 * S, 0.025 * S):
            b.add(cylinder(0.006, 0.006, 6), "metal", Matrix.Translation((HINGE.x + 0.04, y + dy, HINGE.z - 0.02)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    return b


def canonical_frame(door, hinge):
    """Repère canonique (porte fermée, image 40) : centre sur l'axe du passage, normale côté ouverture, X vers la charnière."""
    scene.frame_set(40)
    pts = [door.matrix_world @ Vector(c) for c in door.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    size = hi - lo
    axis = min(range(2), key=lambda i: size[i])            # épaisseur : X (modules) ou Y (tunnels des silos)
    center = Vector((0.0, 0.0, 0.0))
    center[axis] = (lo[axis] + hi[axis]) / 2
    normal = Vector((0.0, 0.0, 0.0))
    if hinge:
        closed_c = (lo + hi) / 2
        scene.frame_set(1)
        pts = [door.matrix_world @ Vector(c) for c in door.bound_box]
        open_c = Vector([(min(p[i] for p in pts) + max(p[i] for p in pts)) / 2 for i in range(3)])
        scene.frame_set(40)
        normal[axis] = 1.0 if open_c[axis] > closed_c[axis] else -1.0
        radial = hinge.matrix_world.translation - center
        radial[axis] = 0.0
    else:
        normal[axis] = 1.0 if center[axis] < 0 else -1.0  # porte cargo : face vers l'intérieur de la station
        radial = Vector((0.0, 1.0, 0.0)) if axis == 0 else Vector((1.0, 0.0, 0.0))
    x = radial.normalized()
    z = normal
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = center
    return m


def replace_mesh(obj, me):
    old = obj.data
    me.name = obj.name
    obj.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)


def remove(name):
    o = bpy.data.objects.get(name)
    if o is None:
        return
    for c in list(o.children):
        remove(c.name)
    data = o.data
    bpy.data.objects.remove(o)
    if isinstance(data, bpy.types.Mesh) and data.users == 0:
        bpy.data.meshes.remove(data)


done = {}
for key in HATCHES:
    hid = "Ecoutille_" + key
    door = bpy.data.objects["Interactif_" + hid]
    hinge = bpy.data.objects.get(door.get("charniere", "")) if door.get("charniere") else None
    col = door.users_collection[0]
    remove("Pivot_Volant_" + hid)
    remove("Volant_" + hid)
    C = canonical_frame(door, hinge)
    if hinge:
        assert hinge.parent is None, hinge.name
        hinge.location = C @ HINGE
        bpy.context.view_layer.update()
        door.matrix_parent_inverse = hinge.matrix_world.inverted()
        door.matrix_basis = Matrix()
    else:
        door.matrix_world = Matrix()
    bpy.context.view_layer.update()
    # Porte (coordonnées monde = coordonnées de l'objet : porte à l'identité, image 40).
    body, wheel = door_parts(with_wheel=hinge is None)
    body.transform(C)
    replace_mesh(door, body.mesh(door.name))
    # Collision : cylindre de la porte.
    coll = bpy.data.objects.get(door.name + "-convcolonly")
    cb = Builder()
    cb.add(disk(PORTE_R, Z0, Z1, 24), "metal")
    cb.transform(C)
    if coll:
        replace_mesh(coll, cb.mesh(coll.name))
        coll.matrix_parent_inverse = door.matrix_world.inverted()
        coll.matrix_basis = Matrix()
    else:
        cb.bm.free()
    # Volant et son pivot (axe Z = normale de la porte).
    if wheel:
        pivot = bpy.data.objects.new("Pivot_Volant_" + hid, None)
        pivot.empty_display_type = 'ARROWS'
        pivot.empty_display_size = 0.2
        col.objects.link(pivot)
        pivot.parent = door
        pivot.matrix_parent_inverse = door.matrix_world.inverted()
        pivot.matrix_world = C @ Matrix.Translation((0, 0, (Z0 + Z1) / 2))
        bpy.context.view_layer.update()
        wheel.transform(C)
        wobj = bpy.data.objects.new("Volant_" + hid, wheel.mesh("Volant_" + hid))
        col.objects.link(wobj)
        wobj.parent = pivot
        wobj.matrix_parent_inverse = pivot.matrix_world.inverted()
        door["volant"] = pivot.name
        door["volant_tours"] = WHEEL_TURNS
    # Paumelle fixe (remplacée).
    leaf_name = "Paumelle_" + hid
    old_leaf = bpy.data.objects.get(leaf_name)
    leaf_col = old_leaf.users_collection[0] if old_leaf else col
    remove(leaf_name)
    lb = hinge_leaf_parts()
    lb.transform(C)
    leaf = bpy.data.objects.new(leaf_name, lb.mesh(leaf_name))
    leaf_col.objects.link(leaf)
    done[hid] = {"centre": [round(v, 3) for v in C.translation], "normale": [round(v, 2) for v in C.col[2][:3]],
                 "charniere": [round(v, 3) for v in hinge.location] if hinge else None}

scene.frame_set(1)
bpy.ops.wm.save_mainfile()
result = {"ecoutilles": done}
