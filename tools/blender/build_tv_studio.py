# Outil hors-jeu : image provisoire du plateau des chaînes d'information (assets/tv/studio.png), rendue par un Blender
# lancé en arrière-plan (le Blender ouvert sur la station n'est pas touché) :
#   blender --background --factory-startup --python tools/blender/build_tv_studio.py -- assets/tv/studio.png
# Plateau stylisé : fond bleu nuit avec un globe lumineux et des bandes, bureau courbe, deux présentateurs simplifiés
# (buste, tête, cheveux, veste, cravate / foulard). Image 1280 × 800 (16:10, proportions des écrans). Pas de texte :
# le nom de la chaîne est incrusté par le jeu (scripts/ui/tv_display.gd).
import bpy, math, sys
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x, scene.render.resolution_y = 1280, 800
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = -0.6
scene.render.filepath = out


def mat(name, color, emission=0.0, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emission:
        p.inputs["Emission Color"].default_value = (*color, 1)
        p.inputs["Emission Strength"].default_value = emission
    return m


def add(obj, material):
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


def sphere(loc, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    return add(o, material)


def box(loc, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.active_object
    o.scale = scale
    if bevel:
        m = o.modifiers.new("b", 'BEVEL')
        m.width = bevel
        m.segments = 4
    return add(o, material)


def cylinder(loc, radius, depth, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=64, radius=radius, depth=depth, location=loc, rotation=rot)
    return add(bpy.context.active_object, material)


# Décor : fond, globe, bandes lumineuses.
box((0, 6, 2), (12, 0.1, 6), mat("Fond", (0.01, 0.025, 0.07), 0.25))
globe = sphere((0, 5.6, 2.6), (2.6, 0.2, 2.6), mat("Globe", (0.05, 0.25, 0.7), 0.9))
for i, z in enumerate((0.9, 1.15, 4.2)):
    box((0, 5.5, z), (12, 0.02, 0.02), mat("Bande%d" % i, (0.2, 0.6, 1.0), 6.0))
for x in (-4.2, 4.2):
    box((x, 5.4, 2.4), (0.9, 0.05, 1.5), mat("Ecran%d" % x, (0.06, 0.15, 0.35), 0.7), 0.05)
# Bureau courbe (anneau) et plateau.
desk = mat("Bureau", (0.85, 0.87, 0.9), 0.0, 0.25, 0.3)
cylinder((0, 1.2, 0.45), 3.4, 0.9, desk)
cylinder((0, 1.2, 0.93), 3.5, 0.06, mat("Plateau", (0.05, 0.06, 0.08), 0.0, 0.15, 0.6))

box((0, -0.15, 0.62), (3.0, 0.03, 0.12), mat("Liseré", (0.2, 0.6, 1.0), 5.0))


def presenter(x, skin, hair, jacket, accent, long_hair):
    box((x, 1.9, 1.5), (0.5, 0.25, 0.45), jacket, 0.18)                      # buste (épaules carrées)
    box((x, 1.65, 1.55), (0.06, 0.02, 0.32), accent)                         # cravate / foulard
    cylinder((x, 1.9, 2.05), 0.11, 0.25, skin)                               # cou
    sphere((x, 1.9, 2.42), (0.24, 0.26, 0.31), skin)                         # tête
    sphere((x, 1.97, 2.55), (0.26, 0.27, 0.27), hair)                        # cheveux
    if long_hair:
        sphere((x, 2.05, 2.25), (0.3, 0.22, 0.4), hair)
    for dx in (-0.45, 0.45):                                                 # bras posés sur le bureau
        sphere((x + dx, 1.45, 1.05), (0.16, 0.42, 0.13), jacket)


presenter(-1.15, mat("Peau1", (0.62, 0.44, 0.34)), mat("Cheveux1", (0.05, 0.035, 0.03)),
          mat("Veste1", (0.04, 0.05, 0.12)), mat("Cravate", (0.6, 0.05, 0.05)), False)
presenter(1.15, mat("Peau2", (0.75, 0.58, 0.47)), mat("Cheveux2", (0.35, 0.22, 0.1)),
          mat("Veste2", (0.45, 0.05, 0.08)), mat("Foulard", (0.85, 0.85, 0.82)), True)

# Lumières de plateau et caméra.
for loc, energy in (((-3, -4, 4), 450), ((3, -4, 4), 450), ((0, 3, 6), 250)):
    light = bpy.data.lights.new("L", 'AREA')
    light.energy = energy
    light.size = 3
    lo = bpy.data.objects.new("L", light)
    lo.location = loc
    lo.rotation_euler = (Vector((0, 1.5, 1.5)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(lo)
cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
cam.location = (0, -7.5, 2.6)
cam.rotation_euler = (Vector((0, 2.0, 1.75)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 42
scene.collection.objects.link(cam)
scene.camera = cam
scene.world = bpy.data.worlds.new("W")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
bpy.ops.render.render(write_still=True)
