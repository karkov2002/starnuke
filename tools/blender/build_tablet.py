# Outil hors-jeu : modélise la tablette de l'observateur (scripts/tablet.gd) dans un Blender lancé en arrière-plan
# (sans toucher au Blender ouvert ni à la station), l'enregistre et l'exporte pour Godot.
# Usage :
#   blender --background --factory-startup --python tools/blender/build_tablet.py -- <tablet.glb> <tablette.blend> [aperçu.png]
# Repères Blender : largeur X, épaisseur Y (écran vers −Y), hauteur Z ; à l'export glTF (+Y en haut), l'écran regarde
# +Z dans Godot : vers la caméra quand la tablette est tenue devant elle. Dimensions d'une tablette de 12 pouces.
# Objets : Tablette_Coque (coque arrondie en aluminium anodisé, face avant en verre noir), Ecran_Tablette (dalle de
# l'écran, UV 0–1 : u vers la droite, v vers le bas de l'image ; matériau remplacé dans Godot par l'interface),
# Tablette_Objectif (caméra frontale), Tablette_Boutons (marche/arrêt, volume), Main_Droite (main droite qui tient
# le coin inférieur droit : paume et doigts à plat contre le dos, pouce passé par-dessus la tranche droite, posé sur
# la bordure avant à côté de l'écran ; modélisée par le modificateur Skin sur un squelette de sommets à rayons, puis
# lissée) et Manche (avant-bras dans la manche bleu marine d'une combinaison de vol, qui descend hors du champ).
import bpy, bmesh, sys, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
GLB, BLEND = args[0], args[1]
PREVIEW = args[2] if len(args) > 2 else ""

WIDTH, HEIGHT, THICK = 0.280, 0.190, 0.0085
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


# Main droite : squelette (sommets, arêtes, rayons x / y des sommets) habillé par le modificateur Skin, puis lissé.
skin_mat = material("Main_Peau", (0.78, 0.56, 0.45), 0.0, 0.48)
skin_mat.node_tree.nodes["Principled BSDF"].inputs["Subsurface Weight"].default_value = 0.25
sleeve_mat = material("Main_Manche", (0.05, 0.07, 0.14), 0.0, 0.85)
BACK = THICK / 2  # dos de la tablette (y > 0), face avant en −BACK


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


hand_points = []
hand_edges = []


def chain(start_index, pts):
    # Ajoute une chaîne de sommets reliée au sommet start_index ; renvoie l'indice du dernier.
    previous = start_index
    for co, radius in pts:
        hand_points.append((co, radius))
        index = len(hand_points) - 1
        if previous is not None:
            hand_edges.append((previous, index))
        previous = index
    return previous

# Avant-bras (racine, dans la manche) et poignet, sous le coin, derrière ; base et centre de la paume derrière la
# tablette.
forearm = chain(None, [((0.124, 0.040, -0.165), (0.026, 0.021))])
wrist = chain(forearm, [((0.112, 0.032, -0.128), (0.025, 0.018))])
palm_base = chain(wrist, [((0.100, 0.026, -0.102), (0.030, 0.016))])
palm = chain(palm_base, [((0.086, 0.022, -0.074), (0.034, 0.014))])
# Doigts serrés, presque parallèles, vers le haut et la gauche, à plat contre le dos ; jointures alignées en travers
# de la paume (index au plus près du pouce, à droite).
up_left = Vector((-0.5, 0.0, 0.866))
across = Vector((0.866, 0.0, 0.5))
palm_center = Vector(hand_points[palm][0])
fingers = [(0.028, -0.03, 0.078), (0.009, 0.0, 0.088), (-0.010, 0.03, 0.082), (-0.028, 0.07, 0.064)]
for offset, spread, length in fingers:  # (décalage en travers, écart angulaire en radians, longueur)
    d = (up_left + across * spread).normalized()
    k = palm_center + up_left * 0.040 + across * offset
    y_rest = BACK + 0.0078
    pts = [((k.x, y_rest + 0.002, k.z), (0.0098, 0.0088))]
    for step, radius in [(0.42, 0.0090), (0.72, 0.0082), (1.0, 0.0070)]:
        p = k + d * length * step
        pts.append(((p.x, y_rest, p.z), (radius, radius * 0.92)))
    chain(palm, pts)
# Pouce : de la paume, par-dessus la tranche droite, puis à plat sur la bordure avant, vers le haut.
FRONT = -BACK - 0.0085
chain(palm_base, [((0.124, 0.022, -0.086), (0.015, 0.013)),
                  ((0.147, 0.006, -0.072), (0.0115, 0.0105)),
                  ((0.1395, FRONT, -0.055), (0.0098, 0.0090)),
                  ((0.1365, FRONT, -0.037), (0.0090, 0.0082)),
                  ((0.1350, FRONT + 0.0006, -0.028), (0.0072, 0.0066))])
hand = skin_object("Main_Droite", hand_points, hand_edges, skin_mat, levels=3)

# Avant-bras dans la manche : du poignet (qu'elle recouvre) vers le bas, l'arrière et la droite (hors du champ).
sleeve = skin_object("Manche", [((0.110, 0.031, -0.122), (0.030, 0.024)),
                                ((0.128, 0.044, -0.175), (0.036, 0.031)),
                                ((0.155, 0.066, -0.270), (0.040, 0.035)),
                                ((0.185, 0.090, -0.380), (0.043, 0.038))], [(0, 1), (1, 2), (2, 3)], sleeve_mat, levels=2)

bpy.ops.wm.save_as_mainfile(filepath=BLEND)
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', export_apply=True, export_yup=True,
                          export_cameras=False, export_lights=False, export_texcoords=True, export_normals=True,
                          export_materials='EXPORT', export_draco_mesh_compression_enable=False)

if PREVIEW:
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
print("OK", GLB)
