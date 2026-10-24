# Outil hors-jeu : modélise la tablette de l'observateur (scripts/tablet.gd) dans un Blender lancé en arrière-plan
# (sans toucher au Blender ouvert ni à la station), l'enregistre et l'exporte pour Godot.
# Usage (sans --factory-startup : l'extension MPFB2 de MakeHuman doit être installée dans Blender) :
#   blender --background --python tools/blender/build_tablet.py -- <tablet.glb> <tablette.blend> <peau.png> [aperçu.png]
# <peau.png> : texture de peau MakeHuman (paquet « MakeHuman system assets », CC0 :
# https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip,
# skins/young_caucasian_male/young_lightskinned_male_diffuse.png).
# Repères Blender : largeur X, épaisseur Y (écran vers −Y), hauteur Z ; à l'export glTF (+Y en haut), l'écran regarde
# +Z dans Godot : vers la caméra quand la tablette est tenue devant elle. Dimensions d'une tablette de 12 pouces.
# Objets : Tablette_Coque (coque arrondie en aluminium anodisé, face avant en verre noir), Ecran_Tablette (dalle de
# l'écran, UV 0–1 : u vers la droite, v vers le bas de l'image ; matériau remplacé dans Godot par l'interface),
# Tablette_Objectif (caméra frontale), Tablette_Boutons (marche/arrêt, volume), Main_Droite (main droite qui tient
# le coin inférieur droit : main et bas de l'avant-bras d'un humain MakeHuman généré par MPFB2, doigts tendus à plat
# contre le dos, pouce amené par cinématique inverse sur la bordure avant à côté de l'écran, texture de peau CC0) et
# Manche (avant-bras dans la manche bleu marine d'une combinaison de vol, qui descend hors du champ).
import bpy, bmesh, sys, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
GLB, BLEND, SKIN = args[0], args[1], args[2]
PREVIEW = args[3] if len(args) > 3 else ""

WIDTH, HEIGHT, THICK = 0.280, 0.190, 0.0055
CORNER = 0.016          # rayon des coins
RIM = 0.0026            # arrondi du pourtour
BEZEL = 0.0115          # bordure noire autour de l'écran
SCREEN_W, SCREEN_H = WIDTH - 2 * BEZEL, HEIGHT - 2 * BEZEL - 0.002

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)


def material(name, color, metallic, roughness, emission=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    if emission:
        p.inputs["Emission Color"].default_value = (*emission, 1.0)
        p.inputs["Emission Strength"].default_value = 1.0
    return m


shell = material("Tablette_Coque", (0.105, 0.11, 0.12), 0.85, 0.36)
glass = material("Tablette_Verre", (0.008, 0.008, 0.01), 0.0, 0.06)
screen_mat = material("Tablette_Ecran", (0.0, 0.0, 0.0), 0.0, 0.1, emission=(0.05, 0.2, 0.12))
lens = material("Tablette_Objectif", (0.02, 0.025, 0.04), 0.3, 0.15)

# Coque : pavé aux coins arrondis (biseau des arêtes d'épaisseur), pourtour arrondi par un modificateur Biseau.
mesh = bpy.data.meshes.new("Tablette_Coque")
body = bpy.data.objects.new("Tablette_Coque", mesh)
bpy.context.collection.objects.link(body)
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co = Vector((v.co.x * WIDTH, v.co.y * THICK, v.co.z * HEIGHT))
corners = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) > 1e-6]
bmesh.ops.bevel(bm, geom=corners, offset=CORNER, segments=14, profile=0.5, affect='EDGES')
bm.to_mesh(mesh)
bm.free()
mesh.materials.append(shell)
mesh.materials.append(glass)
for poly in mesh.polygons:
    poly.use_smooth = True
    # Face avant (vers −Y) : verre noir.
    if poly.normal.y < -0.99:
        poly.material_index = 1
bevel = body.modifiers.new("Pourtour", 'BEVEL')
bevel.width = RIM
bevel.segments = 5
bevel.limit_method = 'ANGLE'
bevel.angle_limit = math.radians(40.0)
bevel.harden_normals = True

# Dalle de l'écran, juste devant le verre. UV : (0, 0) en haut à gauche de l'image vue de face (glTF retourne v).
screen_mesh = bpy.data.meshes.new("Ecran_Tablette")
screen = bpy.data.objects.new("Ecran_Tablette", screen_mesh)
bpy.context.collection.objects.link(screen)
y = -THICK / 2 - 0.00015
hw, hh = SCREEN_W / 2, SCREEN_H / 2
# Vue de face (depuis −Y), la droite est +X et le haut +Z.
screen_mesh.from_pydata([(-hw, y, -hh), (hw, y, -hh), (hw, y, hh), (-hw, y, hh)], [], [(0, 1, 2, 3)])
uv = screen_mesh.uv_layers.new(name="UVMap")
for loop, coords in zip(screen_mesh.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
    uv.data[loop.index].uv = coords
screen_mesh.materials.append(screen_mat)
if screen_mesh.polygons[0].normal.y > 0:
    screen_mesh.flip_normals()

# Caméra frontale, au milieu de la bordure du haut.
bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.0019, depth=0.0006,
                                    location=(0, y - 0.0001, HEIGHT / 2 - BEZEL / 2), rotation=(math.radians(90), 0, 0))
cam = bpy.context.active_object
cam.name = "Tablette_Objectif"
cam.data.materials.append(lens)

# Boutons : marche/arrêt sur la tranche du haut, volume sur la tranche droite.
def button(name, location, size):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    b = bpy.context.active_object
    b.name = name
    b.scale = size
    bpy.ops.object.transform_apply(scale=True)
    mod = b.modifiers.new("Arrondi", 'BEVEL')
    mod.width = min(size) * 0.45
    mod.segments = 4
    b.data.materials.append(shell)
    for poly in b.data.polygons:
        poly.use_smooth = True
    return b

buttons = [button("Tablette_Marche", (WIDTH / 2 - 0.045, 0, HEIGHT / 2 + 0.0006), (0.014, 0.0034, 0.0022)),
           button("Tablette_Volume_Plus", (WIDTH / 2 + 0.0006, 0, HEIGHT / 2 - 0.03), (0.0022, 0.0034, 0.012)),
           button("Tablette_Volume_Moins", (WIDTH / 2 + 0.0006, 0, HEIGHT / 2 - 0.047), (0.0022, 0.0034, 0.012))]
bpy.ops.object.select_all(action='DESELECT')
for b in buttons:
    b.select_set(True)
bpy.context.view_layer.objects.active = buttons[0]
bpy.ops.object.join()
bpy.context.active_object.name = "Tablette_Boutons"


# Main droite : main et bas de l'avant-bras d'un humain MakeHuman (extension MPFB2, CC0), posés sur la tablette.
sleeve_mat = material("Main_Manche", (0.05, 0.07, 0.14), 0.0, 0.85)
BACK = THICK / 2  # dos de la tablette (y > 0), face avant en −BACK
# Repère visé : doigts vers le haut et la gauche, de l'auriculaire vers l'index vers la droite et le haut, paume
# tournée vers la tablette (−Y) ; poignet sous le coin inférieur droit, derrière.
FINGERS_DIR = Vector((-0.5, 0.0, 0.866))
ACROSS_DIR = Vector((0.866, 0.0, 0.5))
# Prise naturelle : la tranche droite repose dans le creux entre le pouce et l'index. La base du pouce (articulation
# métacarpo-phalangienne, tête de l'os finger1-2.R) est posée contre la tranche ; paume et doigts derrière, pouce
# replié vers l'avant sur la bordure (avant : main entière derrière, le pouce devait faire tout le tour de la tranche
# et se déformait).
THUMB_BASE_AT = Vector((0.148, 0.004, -0.085))
# Bout du pouce sur la bordure avant, à droite de l'écran (os : axe du pouce, ~9 mm sous la peau). Bien sur la
# bordure (à 9,5 mm de la tranche) : plus près, il chevauchait la tranche et semblait à côté de la tablette ; il mord
# de quelques mm sur le bord de l'écran (marge réservée par l'interface, TabletDisplay.THUMB_PADDING).
THUMB_TIP_AT = Vector((0.1305, -BACK - 0.0085, -0.030))
# Torsion de la dernière phalange du pouce (degrés), pour laisser voir un peu l'ongle (5e argument pour essayer).
THUMB_TWIST_DEG = float(args[4]) if len(args) > 4 else -50.0
KEEP_GROUPS = ("lowerarm02.R", "wrist.R", "metacarpal", "finger")


def make_mpfb_hand():
    import addon_utils
    from mathutils import Matrix
    addon_utils.enable("bl_ext.blender_org.mpfb", default_set=True, persistent=False)
    from bl_ext.blender_org.mpfb.services import HumanService
    human = HumanService.create_human(scale=0.1)
    rig = HumanService.add_builtin_rig(human, "default")
    pose = rig.pose.bones

    def head(name):
        return rig.matrix_world @ pose[name].head

    def tail(name):
        return rig.matrix_world @ pose[name].tail

    def update():
        bpy.context.view_layer.update()

    # Doigts tendus dans l'axe de leur métacarpe (main à plat contre le dos de la tablette).
    for finger, metacarpal in [(2, 1), (3, 2), (4, 3), (5, 4)]:
        wanted = (tail("metacarpal%d.R" % metacarpal) - head("metacarpal%d.R" % metacarpal)).normalized()
        for joint in (1, 2, 3):
            bone = pose["finger%d-%d.R" % (finger, joint)]
            current = (tail(bone.name) - head(bone.name)).normalized()
            turn = current.rotation_difference(wanted).to_matrix().to_4x4()
            pivot = bone.head.copy()
            bone.matrix = Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot) @ bone.matrix
            update()

    # Rotation et translation de la main vers le repère visé, d'après le poignet et les jointures.
    wrist = head("wrist.R")
    forward = (head("finger3-1.R") - wrist).normalized()
    across = head("finger2-1.R") - head("finger5-1.R")
    across = (across - forward * across.dot(forward)).normalized()
    source = Matrix((across, -forward.cross(across), forward)).transposed()
    target = Matrix((ACROSS_DIR, -FINGERS_DIR.cross(ACROSS_DIR), FINGERS_DIR)).transposed()
    rotation = target @ source.transposed()
    offset = THUMB_BASE_AT - rotation @ head("finger1-2.R")
    to_target = Matrix.Translation(offset) @ rotation.to_4x4()

    def evaluated_mesh():
        depsgraph = bpy.context.evaluated_depsgraph_get()
        mesh = bpy.data.meshes.new_from_object(human.evaluated_get(depsgraph), preserve_all_data_layers=True,
                                               depsgraph=depsgraph)
        mesh.transform(to_target @ human.matrix_world)
        return mesh

    def group_weight(mesh, vertex, names):
        total = 0.0
        for g in vertex.groups:
            name = human.vertex_groups[g.group].name
            if name.endswith(".R") and any(name.startswith(n) for n in names):
                total += g.weight
        return total

    # Paume et doigts au contact du dos de la tablette.
    probe = evaluated_mesh()
    palm_y = min(v.co.y for v in probe.vertices if group_weight(probe, v, ("metacarpal", "finger2", "finger3",
            "finger4", "finger5")) > 0.5)
    bpy.data.meshes.remove(probe)
    offset.y += BACK + 0.0006 - palm_y
    to_target = Matrix.Translation(offset) @ rotation.to_4x4()
    print("Base du pouce : %s ; poignet : %s" % (tuple(round(c, 4) for c in to_target @ head("finger1-2.R")),
            tuple(round(c, 4) for c in to_target @ head("wrist.R"))))

    # Pouce : cinématique inverse vers son point sur la bordure avant (ramené dans le repère de l'humain).
    goal = bpy.data.objects.new("Cible_Pouce", None)
    bpy.context.collection.objects.link(goal)
    goal.location = to_target.inverted() @ THUMB_TIP_AT
    ik = pose["finger1-3.R"].constraints.new('IK')
    ik.target = goal
    ik.chain_count = 3
    update()
    # Pose du pouce figée (contrainte retirée), puis légère torsion de la dernière phalange sur son axe : l'ongle se
    # tourne un peu vers le joueur sans déplacer la base du pouce ni le contact avec la tablette.
    solved = {n: pose[n].matrix.copy() for n in ("finger1-1.R", "finger1-2.R", "finger1-3.R")}
    pose["finger1-3.R"].constraints.remove(ik)
    for name, matrix in solved.items():
        pose[name].matrix = matrix
        update()
    tip = pose["finger1-3.R"]
    pivot = tip.head.copy()
    twist = Matrix.Rotation(math.radians(THUMB_TWIST_DEG), 4, (tip.tail - tip.head).normalized())
    tip.matrix = Matrix.Translation(pivot) @ twist @ Matrix.Translation(-pivot) @ tip.matrix
    update()
    reached = to_target @ tail("finger1-3.R")
    print("Pouce : bout à %s, cible %s, écart %.1f mm" % (tuple(round(c, 4) for c in reached),
            tuple(round(c, 4) for c in THUMB_TIP_AT), (reached - THUMB_TIP_AT).length * 1000.0))

    mesh = evaluated_mesh()
    # La tablette recule entre le pouce et les doigts, centrée entre eux : la main est avancée (−Y) pour que le pouce
    # (sommets en deçà de la tranche passés derrière le verre) et les doigts (écart au dos) aient le même jeu.
    def in_slab(c):
        return c.x < WIDTH / 2 - 0.004 and c.z > -HEIGHT / 2 + 0.004

    thumb = [v.co for v in mesh.vertices if group_weight(mesh, v, ("finger1-2", "finger1-3")) > 0.5]
    depth = max([c.y + BACK for c in thumb if in_slab(c) and -BACK < c.y < BACK] + [0.0])
    fingers = [v.co for v in mesh.vertices if group_weight(mesh, v, ("finger2", "finger3", "finger4", "finger5")) > 0.5
               and in_slab(v.co)]
    gap = min(c.y for c in fingers) - BACK
    palm = [v.co for v in mesh.vertices if group_weight(mesh, v, ("metacarpal", "finger1-1")) > 0.5 and in_slab(v.co)]
    print("Avant recul : pouce %.1f mm dans le verre, doigts à %.1f mm du dos, paume à %.1f mm du dos"
            % (depth * 1000.0, gap * 1000.0, (min(c.y for c in palm) - BACK) * 1000.0))
    shift = (depth + gap) * 0.5
    mesh.transform(Matrix.Translation((0.0, -shift, 0.0)))
    print("Tablette reculée de %.1f mm entre le pouce et les doigts : jeu au pouce %.1f mm, aux doigts %.1f mm"
            % (shift * 1000.0, (shift - depth) * 1000.0, (gap - shift) * 1000.0))
    arm_dir = (rotation @ (head("lowerarm02.R") - head("wrist.R"))).normalized()
    wrist_at = to_target @ head("wrist.R") - Vector((0.0, shift, 0.0))
    # Ne garder que la main et le bas de l'avant-bras.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    deform = bm.verts.layers.deform.active
    names = [g.name for g in human.vertex_groups]
    drop = []
    for v in bm.verts:
        total = sum(w for g, w in v[deform].items() if names[g].endswith(".R")
                    and any(names[g].startswith(n) for n in KEEP_GROUPS))
        if total < 0.5:
            drop.append(v)
    bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bm.to_mesh(mesh)
    bm.free()
    mesh.name = "Main_Droite"
    for o in (human, rig, goal):
        bpy.data.objects.remove(o)
    return mesh, arm_dir, wrist_at


def skin_object(name, points, edges, mat, levels=2):
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.from_pydata([p[0] for p in points], edges, [])
    obj.modifiers.new("Skin", 'SKIN').use_smooth_shade = True
    for i, p in enumerate(points):
        mesh.skin_vertices[0].data[i].radius = p[1]
    mesh.skin_vertices[0].data[0].use_root = True
    sub = obj.modifiers.new("Lissage", 'SUBSURF')
    sub.levels = levels
    sub.render_levels = levels
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


hand_mesh, arm_dir, wrist_at = make_mpfb_hand()
hand = bpy.data.objects.new("Main_Droite", hand_mesh)
bpy.context.collection.objects.link(hand)
skin_mat = bpy.data.materials.new("Main_Peau")
skin_mat.use_nodes = True
principled = skin_mat.node_tree.nodes["Principled BSDF"]
principled.inputs["Roughness"].default_value = 0.5
skin_image = skin_mat.node_tree.nodes.new("ShaderNodeTexImage")
skin_image.image = bpy.data.images.load(SKIN)
skin_mat.node_tree.links.new(skin_image.outputs["Color"], principled.inputs["Base Color"])
hand_mesh.materials.clear()
hand_mesh.materials.append(skin_mat)
for poly in hand_mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True
hand.modifiers.new("Lissage", 'SUBSURF').levels = 1

# Avant-bras dans la manche : à partir de quelques cm du poignet, dans l'axe de l'avant-bras (hors du champ).
sleeve_points = [(wrist_at + arm_dir * d, (r, r * 0.85)) for d, r in [(0.035, 0.032), (0.09, 0.036), (0.2, 0.04),
                                                                     (0.32, 0.043)]]
sleeve = skin_object("Manche", sleeve_points, [(0, 1), (1, 2), (2, 3)], sleeve_mat, levels=2)

# Variante « combinaison » (montrée par Godot à la place de la main nue quand la combinaison du sas est portée :
# Tablet) : gant blanc de la combinaison (la même main, lissée pour effacer le relief des phalanges et des
# articulations, puis gonflée de GLOVE_THICK le long des normales : tissu épais, doigts boudinés), bague de poignet
# métallique (raccord gant-manche) et manche blanche, plus large que celle de la combinaison de vol.
GLOVE_THICK = 0.0045
GLOVE_SMOOTH = (6, 0.8)    # lissage laplacien (itérations, facteur), volume conservé
# Au contact de la tablette, le tissu est comprimé : gonflement et lissage nuls contre elle, entiers à GLOVE_FREE (m)
# de sa surface (sinon la paume traversait l'écran près de la tranche et le pouce se décollait de la bordure).
GLOVE_FREE = 0.008
glove_mat = material("Gant_Tissu", (0.80, 0.82, 0.86), 0.0, 0.78)
ring_mat = material("Gant_Bague", (0.62, 0.64, 0.67), 1.0, 0.28)
suit_sleeve_mat = material("Gant_Manche", (0.86, 0.86, 0.85), 0.0, 0.85)
glove = bpy.data.objects.new("Gant_Droit", hand_mesh.copy())
bpy.context.collection.objects.link(glove)
glove.data.materials.clear()
glove.data.materials.append(glove_mat)
free = glove.vertex_groups.new(name="Gant_Libre")
for v in glove.data.vertices:
    outside = Vector((max(abs(v.co.x) - WIDTH / 2, 0.0), max(abs(v.co.y) - BACK, 0.0), max(abs(v.co.z) - HEIGHT / 2, 0.0)))
    t = min(outside.length / GLOVE_FREE, 1.0)
    free.add([v.index], t * t * (3 - 2 * t), 'REPLACE')
smooth = glove.modifiers.new("Gant_Lisse", 'LAPLACIANSMOOTH')
smooth.iterations, smooth.lambda_factor = GLOVE_SMOOTH
smooth.use_volume_preserve = True
smooth.use_normalized = True
smooth.vertex_group = "Gant_Libre"
puff = glove.modifiers.new("Epaisseur", 'DISPLACE')
puff.strength = GLOVE_THICK
puff.mid_level = 0.0
puff.vertex_group = "Gant_Libre"
glove.modifiers.new("Lissage", 'SUBSURF').levels = 1
ring_points = [(wrist_at + arm_dir * d, (r, r)) for d, r in [(0.028, 0.041), (0.046, 0.041)]]
ring = skin_object("Gant_Bague", ring_points, [(0, 1)], ring_mat, levels=1)
suit_sleeve_points = [(wrist_at + arm_dir * d, (r, r * 0.9)) for d, r in [(0.044, 0.044), (0.1, 0.05), (0.2, 0.054),
                                                                           (0.32, 0.056)]]
suit_sleeve = skin_object("Manche_Combinaison", suit_sleeve_points, [(0, 1), (1, 2), (2, 3)], suit_sleeve_mat,
                          levels=2)
BARE = (hand, sleeve)
SUITED = (glove, ring, suit_sleeve)

bpy.ops.wm.save_as_mainfile(filepath=BLEND)
if GLB != "-":  # « - » : fichier .blend et aperçus seulement (mise au point dans Blender)
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=True, export_yup=True,
                              export_cameras=False, export_lights=False, export_texcoords=True, export_normals=True,
                              export_materials='EXPORT', export_draco_mesh_compression_enable=False)

if PREVIEW:
    for o in SUITED:  # aperçus de la main nue d'abord
        o.hide_render = True
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Apercu")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.27, 0.3, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world
    bpy.ops.object.light_add(type='AREA', location=(0.35, -0.45, 0.4))
    light = bpy.context.active_object
    light.data.energy = 60.0
    light.data.size = 0.5
    light.rotation_euler = (math.radians(55), 0, math.radians(35))
    bpy.ops.object.light_add(type='AREA', location=(-0.4, -0.2, -0.1))
    fill = bpy.context.active_object
    fill.data.energy = 15.0
    fill.data.size = 0.8
    fill.rotation_euler = (math.radians(100), 0, math.radians(-60))
    bpy.ops.object.camera_add(location=(0.23, -0.42, 0.16))
    camera = bpy.context.active_object
    direction = Vector((0, 0, 0)) - camera.location
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    camera.data.lens = 50
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 64
    scene.cycles.device = 'CPU'
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 800
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    # Deuxième aperçu, de dos et d'en dessous (la main ; de face, seul le pouce dépasse).
    camera.location = (0.42, 0.38, -0.22)
    direction = Vector((0.06, 0.0, -0.05)) - camera.location
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = PREVIEW.replace(".png", "_dos.png")
    bpy.ops.render.render(write_still=True)
    # Vue du joueur (de face, l'œil en haut à gauche de la tablette) et vue de la tranche droite (le pouce).
    for suffix, location, target in [("_joueur", (-0.12, -0.42, 0.12), (0.03, 0.0, -0.02)),
                                     ("_cote", (0.40, -0.06, -0.03), (0.13, 0.0, -0.05)),
                                     ("_pouce", (0.03, -0.16, 0.06), (0.135, 0.0, -0.05))]:
        camera.location = location
        direction = Vector(target) - camera.location
        camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = PREVIEW.replace(".png", suffix + ".png")
        bpy.ops.render.render(write_still=True)
    # Variante combinaison (gant, bague, manche blanche) : vues du joueur, du pouce et de dos.
    for o in BARE:
        o.hide_render = True
    for o in SUITED:
        o.hide_render = False
    for suffix, location, target in [("_gant_joueur", (-0.12, -0.42, 0.12), (0.03, 0.0, -0.02)),
                                     ("_gant_pouce", (0.03, -0.16, 0.06), (0.135, 0.0, -0.05)),
                                     ("_gant_dos", (0.42, 0.38, -0.22), (0.06, 0.0, -0.05))]:
        camera.location = location
        direction = Vector(target) - camera.location
        camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = PREVIEW.replace(".png", suffix + ".png")
        bpy.ops.render.render(write_still=True)
print("OK", GLB)
