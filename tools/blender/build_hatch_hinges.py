# Outil hors-jeu : charnières réalistes des écoutilles ouvrables de E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab), à la place du pavé de 8 × 10 × 50 cm sur l'axe de rotation.
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/build_hatch_hinges.py
# Charnière à cinq nœuds sur l'axe Z de la charnière (Charniere_*) :
# - dans le maillage de la porte (tourne avec elle) : nœuds 1, 3, 5, pattes vissées sur les deux faces de la porte,
#   capuchons bombés de l'axe en haut et en bas, graisseur ;
# - objet fixe Paumelle_<id> (collection de l'écoutille) : nœuds 2 et 4 (des cylindres sur l'axe : la rotation de la
#   porte ne les déplacerait pas, mais leur patte, si) et leur patte vissée, dirigée vers le cadre (plaquette blanche
#   d'origine, à côté de l'axe).
# Pièces de révolution à arêtes arrondies (props_kit.revolve), 32 segments. Rejouable (le pavé d'origine est retiré
# s'il est encore là ; Paumelle_<id> recréé ; les pièces de la porte sont repérées par le matériau Int_Charniere).
# Enregistre le .blend ; ne réexporte rien.
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())
assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)

MATS = {
    "charniere": material("Int_Charniere", (0.5, 0.51, 0.53), 1.0, 0.33),
    "vis": material("Int_PC_Inox", (0.62, 0.62, 0.63), 1.0, 0.28),
    "trou": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
    "graisseur": material("Int_Laiton", (0.7, 0.52, 0.25), 1.0, 0.35),
}
R = 0.026                 # rayon des nœuds
GAP = 0.004               # jeu entre nœuds
KNUCKLES = (-0.25, -0.15, -0.05, 0.05, 0.15, 0.25)   # bornes des 5 nœuds (z, repère de la charnière)
DOOR_T = 0.037            # demi-épaisseur de la porte (panneaux)
LEAF_T = 0.006            # épaisseur des pattes


def knuckle(z0, z1, r=R):
    c = 0.004
    return revolve([(0.0, z0), (r - c, z0), (r, z0 + c), (r, z1 - c), (r - c, z1), (0.0, z1)], 32)


def leaf(length, width, thick):
    """Patte (plat aux coins arrondis) : de l'axe (x = 0) à x = length, largeur selon Z, épaisseur selon Y."""
    return soft_box((length / 2, thick / 2, width / 2), min(0.008, width / 2 - 0.001), 0.01)


def screw(m, b):
    b.add(revolve([(0.0, 0.0), (0.0075, 0.0), (0.0075, 0.0015), (0.005, 0.0035), (0.0, 0.004)], 20), "vis", m)
    b.add(soft_box((0.0045, 0.0007, 0.0007), 0.0003, 0.004), "trou", m @ Matrix.Translation((0, 0, 0.004)))
    b.add(soft_box((0.0007, 0.0045, 0.0007), 0.0003, 0.004), "trou", m @ Matrix.Translation((0, 0, 0.004)))


def door_parts(b, s):
    """Pièces de la porte (repère de la porte = repère de la charnière) ; s : côté de la porte (+1 : x > 0)."""
    for k in (0, 2, 4):
        z0, z1 = KNUCKLES[k] + GAP / 2, KNUCKLES[k + 1] - GAP / 2
        b.add(knuckle(z0, z1), "charniere")
        for face in (-1, 1):
            length, width = 0.17, (z1 - z0) * 0.9
            y = face * (DOOR_T + LEAF_T / 2)
            b.add(leaf(length, width, LEAF_T), "charniere", Matrix.Translation((s * (length / 2), y, (z0 + z1) / 2)))
            # Deux vis par patte, tête vers l'extérieur de la face.
            rot = Matrix.Rotation(-face * math.pi / 2, 4, 'X')
            for x in (0.075, 0.135):
                screw(Matrix.Translation((s * x, face * (DOOR_T + LEAF_T), (z0 + z1) / 2)) @ rot, b)
    # Capuchons bombés de l'axe, graisseur sur le nœud du milieu.
    for z, sign in ((KNUCKLES[0], -1), (KNUCKLES[-1], 1)):
        cap = revolve([(0.0, 0.0), (0.018, 0.0), (0.018, 0.006), (0.012, 0.011), (0.0, 0.013)], 24)
        b.add(cap, "charniere", Matrix.Translation((0, 0, z)) @ Matrix.Diagonal((1, 1, sign, 1)))
    b.add(revolve([(0.0, 0.0), (0.004, 0.0), (0.004, 0.008), (0.0055, 0.009), (0.0055, 0.013), (0.0, 0.014)], 12),
          "graisseur", Matrix.Translation((0, 0, 0)) @ Matrix.Rotation(-s * math.pi / 2, 4, 'Y')
          @ Matrix.Translation((0, 0, R - 0.002)))


def frame_parts(b, frame_dir):
    """Pièces fixes (repère de la charnière) : nœuds 2 et 4 et leur patte vers le cadre (frame_dir, plan XY)."""
    a = math.atan2(frame_dir.y, frame_dir.x)
    rot = Matrix.Rotation(a, 4, 'Z')
    for k in (1, 3):
        z0, z1 = KNUCKLES[k] + GAP / 2, KNUCKLES[k + 1] - GAP / 2
        b.add(knuckle(z0, z1), "charniere")
        length, width = 0.075, (z1 - z0) * 0.9
        b.add(leaf(length, width, 0.012), "charniere", rot @ Matrix.Translation((length / 2 + R * 0.4, 0, (z0 + z1) / 2)))
        for x in (0.045, 0.07):
            screw(rot @ Matrix.Translation((x, 0.006, (z0 + z1) / 2)) @ Matrix.Rotation(-math.pi / 2, 4, 'X'), b)


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


def plaquette_center(pivot):
    """Centre de la plaquette blanche du cadre (paumelle d'origine) la plus proche de l'axe, repère monde."""
    best, dist = None, 0.25
    for o in bpy.data.objects:
        if o.type != "MESH" or not o.name.endswith("Cloisons-col") and "Cloison_Ecoutille" not in o.name:
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        for island in islands(bm):
            if len(island) > 6 or o.data.materials[island[0].material_index].name != "Int_Panneau_Blanc":
                continue
            c = sum((v.co for f in island for v in f.verts), Vector()) / sum(len(f.verts) for f in island)
            if (c - pivot).length < dist:
                best, dist = c, (c - pivot).length
        bm.free()
    return best


report = {}
for door in [o for o in bpy.data.objects if o.name.startswith("Interactif_Ecoutille_") and o.type == "MESH"
             and not o.name.endswith("-convcolonly") and o.get("ouvrable") in (True, 1, "True")]:
    hinge = bpy.data.objects[door["charniere"]]
    me = door.data
    bm = bmesh.new()
    bm.from_mesh(me)
    hinge_idx = {i for i, m in enumerate(me.materials) if m and m.name == "Int_Charniere"}
    # Côté de la porte : celui de son centre (la porte s'étend d'un seul côté de l'axe).
    side = 1.0 if sum(v.co.x for v in bm.verts) > 0 else -1.0
    kill = []
    for island in list(islands(bm)):
        pts = [v.co for f in island for v in f.verts]
        box = len(island) == 6 and me.materials[island[0].material_index].name == "Int_Metal" \
            and max(abs(p.z) for p in pts) < 0.26 and max(abs(p.x) for p in pts) < 0.08
        if box or island[0].material_index in hinge_idx:
            kill.extend(island)
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    b = Mesh(MATS)
    door_parts(b, side)
    slots = list(me.materials)
    for m in b.slots:
        if m not in slots:
            me.materials.append(m)
            slots.append(m)
    remap = [slots.index(m) for m in b.slots]
    vmap = {v: bm.verts.new(v.co) for v in b.bm.verts}
    for f in b.bm.faces:
        g = bm.faces.new([vmap[v] for v in f.verts])
        g.material_index = remap[f.material_index]
        g.smooth = True
    b.bm.free()
    bm.to_mesh(me)
    bm.free()
    me.update()
    # Pièces fixes, dans le repère de la charnière à l'image 1 (l'axe Z ne bouge pas).
    pivot = hinge.matrix_world.translation.copy()
    q = plaquette_center(pivot)
    inv = hinge.matrix_world.inverted()
    local = (inv @ q) if q else Vector((-side, 0, 0))
    frame_dir = Vector((local.x, local.y, 0.0)).normalized()
    fb = Mesh(MATS)
    frame_parts(fb, frame_dir)
    for f in fb.bm.faces:
        f.smooth = True
    bmesh.ops.transform(fb.bm, matrix=hinge.matrix_world, verts=fb.bm.verts)
    name = "Paumelle_" + door["id"]
    obj = fb.write(name, door.users_collection[0])
    report[door.name] = {"cote": side, "cadre": [round(c, 2) for c in frame_dir], "fixe": len(obj.data.polygons)}
bpy.ops.wm.save_mainfile()
result = {"charnieres": report, "enregistre": not bpy.data.is_dirty}
