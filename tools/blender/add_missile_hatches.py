# Outil hors-jeu : ajoute dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de Blender Lab) les
# écoutilles des deux modules de missiles, copies exactes de l'écoutille avant du module Habitation, montées sur une
# cloison qui rétrécit le tunnel Habitation -> silo (Ø 2,88 m) au passage standard (Ø 1,32 m).
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/add_missile_hatches.py
# Rejouable : supprime d'abord ce qu'il a créé. Pour chaque silo s (1 : +Y, 2 : −Y) :
# - Missile_<s>_Cloison_Ecoutille-col : disque percé (plaque grise) + cadre : anneaux métal et jaune aux dimensions de
#   ceux de l'écoutille avant de l'Habitation, mais lisses (section arrondie, 96 segments), et paumelle copiée de
#   Habitation_Cloisons-col ; « -col » : collision concave à l'import ;
# - Charniere_Ecoutille_Missile_<s> (pivot, axe Z), Interactif_Ecoutille_Missile_<s> et sa collision
#   « -convcolonly » : copies de l'écoutille Habitation_AV, extras id / charniere mis à jour ;
# - piste NLA « Fermeture_Ecoutilles » : rotation de la charnière de −90° sur les images 1 à 40, comme les autres
#   (image 1 = ouverte : la porte s'ouvre vers le silo).
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math
from mathutils import Matrix, Vector

SOURCE = "Habitation_AV"
SRC_HINGE_X = 4.605          # plan de la porte fermée de l'écoutille source (x), cadre juste avant
BULKHEAD_Y = 2.55            # plan de la porte fermée dans le tunnel (|y|) : au-delà de la lèvre de l'Habitation (2,33)
TUNNEL_R = 1.46              # rayon extérieur de la plaque (paroi du tunnel : 1,44, plaque légèrement engagée)
HOLE_R = 0.66                # passage (comme la source)
PLATE = (-0.135, -0.075)     # épaisseur de la plaque, relative au plan de la porte (faces x = 4,47 et 4,53 de la source)
FRAME_SLICE = (4.38, 4.62)   # tranche de Habitation_Cloisons-col où se trouve le cadre de la porte source
FRAME_R = 0.81               # le cadre (anneaux, gâche) tient dans ce rayon ; au-delà : la cloison de l'Habitation
SEGMENTS = 96
RING_SEGMENTS = 96
# Anneaux du cadre : matériau, rayons, épaisseur (x relatif au plan de la porte fermée), rayon des coins de la section.
# Le métal descend à 0,655 m (un peu sous le passage de 0,66) pour couvrir la tranche intérieure de la plaque.
RING_MATERIALS = ("Int_Metal", "Int_Jaune")
RINGS = (("Int_Metal", (0.655, 0.76), (-0.185, -0.025), 0.03),
         ("Int_Jaune", (0.755, 0.80), (-0.165, -0.045), 0.018))


def rounded_section(r0, r1, x0, x1, c, n=5):
    """Section rectangulaire (rayon r0..r1, x0..x1) aux coins arrondis de rayon c, sens trigonométrique (r, x)."""
    pts = []
    for (cr, cx, a0) in ((r1 - c, x1 - c, 0), (r0 + c, x1 - c, 90), (r0 + c, x0 + c, 180), (r1 - c, x0 + c, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cr + c * math.cos(a), cx + c * math.sin(a)))
    return pts

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
scene = bpy.context.scene
scene.frame_set(1)
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

src_hinge = bpy.data.objects["Charniere_Ecoutille_" + SOURCE]
src_hatch = bpy.data.objects["Interactif_Ecoutille_" + SOURCE]
src_col = bpy.data.objects["Interactif_Ecoutille_" + SOURCE + "-convcolonly"]
src_walls = bpy.data.objects["Habitation_Cloisons-col"]


def remove_previous(s):
    for name in ("Interactif_Ecoutille_Missile_%d-convcolonly" % s, "Interactif_Ecoutille_Missile_%d" % s,
                 "Charniere_Ecoutille_Missile_%d" % s, "Missile_%d_Cloison_Ecoutille-col" % s):
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        data = o.data
        if o.animation_data:
            for t in o.animation_data.nla_tracks:
                for st in t.strips:
                    if st.action and st.action.users <= 1:
                        bpy.data.actions.remove(st.action)
        bpy.data.objects.remove(o)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)


def placement(s):
    """Source -> silo s : plan x = SRC_HINGE_X envoyé sur y = ±BULKHEAD_Y, ouverture vers le silo (+X -> ±Y)."""
    s = 1 if s == 1 else -1
    return Matrix.Translation((0.0, s * BULKHEAD_Y, 0.0)) @ Matrix.Rotation(s * math.pi / 2, 4, 'Z') \
        @ Matrix.Translation((-SRC_HINGE_X, 0.0, 0.0))


def build_bulkhead(s, T, collection):
    me = bpy.data.meshes.new("Missile_%d_Cloison_Ecoutille" % s)
    bm = bmesh.new()
    slots = []

    def slot(mat):
        if mat not in slots:
            slots.append(mat)
        return slots.index(mat)

    # Paumelle copiée de la source (plaquette blanche contre le cadre, à côté de la charnière).
    src = bmesh.new()
    src.from_mesh(src_walls.data)
    src.transform(src_walls.matrix_world)
    for f in src.faces:
        mat = src_walls.data.materials[f.material_index]
        if mat.name in RING_MATERIALS:
            continue
        if all(FRAME_SLICE[0] <= v.co.x <= FRAME_SLICE[1] and math.hypot(v.co.y, v.co.z) <= FRAME_R for v in f.verts):
            g = bm.faces.new([bm.verts.new(T @ v.co) for v in f.verts])
            g.material_index = slot(mat)
    src.free()
    # Anneaux du cadre (métal, puis liseré jaune), mêmes encombrements que ceux de la source (32 segments à section
    # carrée, très facettés) : révolution d'une section aux coins arrondis, RING_SEGMENTS segments, ombrage lisse.
    for mat_name, (r0, r1), (x0, x1), corner in RINGS:
        idx = slot(bpy.data.materials[mat_name])
        profile = rounded_section(r0, r1, SRC_HINGE_X + x0, SRC_HINGE_X + x1, corner)
        loops = [[bm.verts.new(T @ Vector((x, r * math.cos(a), r * math.sin(a)))) for r, x in profile]
                 for a in (2 * math.pi * k / RING_SEGMENTS for k in range(RING_SEGMENTS))]
        n = len(profile)
        for k in range(RING_SEGMENTS):
            q = (k + 1) % RING_SEGMENTS
            for i in range(n):
                j = (i + 1) % n
                g = bm.faces.new((loops[k][i], loops[k][j], loops[q][j], loops[q][i]))
                g.material_index = idx
                g.smooth = True
    # Plaque : couronne HOLE_R -> TUNNEL_R, deux faces et tranches.
    grey = slot(bpy.data.materials["Int_Panneau_Gris"])
    rings = {}
    for side, dy in (("a", PLATE[0]), ("b", PLATE[1])):
        for key, r in (("in", HOLE_R), ("out", TUNNEL_R)):
            rings[side + key] = [bm.verts.new(T @ Vector((SRC_HINGE_X + dy, r * math.cos(a), r * math.sin(a))))
                                 for a in (2 * math.pi * k / SEGMENTS for k in range(SEGMENTS))]
    for k in range(SEGMENTS):
        q = (k + 1) % SEGMENTS
        for loop in (("ain", "aout"), ("bout", "bin"), ("aout", "bout"), ("bin", "ain")):
            r0, r1 = rings[loop[0]], rings[loop[1]]
            g = bm.faces.new((r0[k], r0[q], r1[q], r1[k]))
            g.material_index = grey
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for m in slots:
        me.materials.append(m)
    bm.to_mesh(me)
    bm.free()
    me.set_sharp_from_angle(angle=math.radians(35))
    ob = bpy.data.objects.new("Missile_%d_Cloison_Ecoutille-col" % s, me)
    collection.objects.link(ob)
    return ob


def copy_object(src, name, collection, parent=None):
    ob = src.copy()
    if src.data is not None:
        ob.data = src.data.copy()
        ob.data.name = name
    ob.animation_data_clear()
    ob.name = name
    collection.objects.link(ob)
    if parent is not None:
        ob.parent = parent
        ob.matrix_parent_inverse = src.matrix_parent_inverse.copy()
    return ob


def animate_hinge(hinge, open_z):
    """Fermeture_Ecoutilles : image 1 ouverte (open_z), image 40 fermée (open_z − 90°), interpolation de la source."""
    src_action = src_hinge.animation_data.nla_tracks["Fermeture_Ecoutilles"].strips[0].action
    src_keys = None
    for layer in src_action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if fc.data_path == "rotation_euler" and fc.array_index == 2:
                        src_keys = list(fc.keyframe_points)
    hinge.rotation_euler.z = open_z
    hinge.keyframe_insert("rotation_euler", index=2, frame=1)
    hinge.rotation_euler.z = open_z - math.pi / 2
    hinge.keyframe_insert("rotation_euler", index=2, frame=40)
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
    hinge.rotation_euler.z = open_z


created = {}
for s in (1, 2):
    remove_previous(s)
    collection = bpy.data.collections["Int_Missile_%d" % s]
    T = placement(s)
    bulkhead = build_bulkhead(s, T, collection)
    hinge = copy_object(src_hinge, "Charniere_Ecoutille_Missile_%d" % s, collection)
    hinge.matrix_world = T @ src_hinge.matrix_world
    hatch = copy_object(src_hatch, "Interactif_Ecoutille_Missile_%d" % s, collection, parent=hinge)
    hatch["id"] = "Ecoutille_Missile_%d" % s
    hatch["charniere"] = hinge.name
    col = copy_object(src_col, "Interactif_Ecoutille_Missile_%d-convcolonly" % s, collection, parent=hatch)
    animate_hinge(hinge, hinge.rotation_euler.z)
    created[s] = {"cloison": bulkhead.name, "faces_cloison": len(bulkhead.data.polygons), "charniere": hinge.name,
                  "pivot": [round(c, 3) for c in hinge.matrix_world.translation],
                  "rot_z_deg": round(math.degrees(hinge.rotation_euler.z), 1), "porte": hatch.name, "collision": col.name}
scene.frame_set(1)
bpy.ops.wm.save_mainfile()
result = {"crees": created, "enregistre": not bpy.data.is_dirty}
