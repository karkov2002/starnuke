# Outil hors-jeu : vidéos des chaînes d'information (plateau de télévision), rendues par un Blender lancé en
# arrière-plan (le Blender ouvert sur la station n'est pas touché). Appelé par tools/build_tv_videos.ps1 :
#   blender --background --factory-startup --python tools/blender/build_tv_studio.py -- <mode> <source> <frames>
# - mode "explosion" : scène « Explosion » (champignon atomique stylisé, volumes EEVEE) rendue en images
#   <frames>/explosion/####.png (1000 × 400, le format du mur vidéo du plateau) ; le script PowerShell en fait
#   <source>/explosion.mp4. Ce fichier peut être remplacé par d'autres images (même format) avant le mode "studio".
# - mode "studio" : scènes « Studio_Normal » (deux présentateurs, têtes animées calmement, globe lumineux) et
#   « Studio_Alerte » (édition spéciale : têtes agitées qui se tournent vers le mur, bandes rouges qui pulsent, mur
#   vidéo de six dalles qui diffuse <source>/explosion.mp4), enregistrées dans <source>/tv_studio.blend (à retoucher
#   dans Blender), rendues en <frames>/normal/ et <frames>/alert/ (960 × 600, 16:10 comme les écrans).
# Boucles de LOOP_S secondes : les mouvements sont des sommes de sinus à nombre entier de périodes par boucle (pas de
# saut au raccord). Pas de texte dans les images : le nom de la chaîne et les bandeaux sont incrustés par le jeu
# (scripts/ui/tv_display.gd, fichiers de langue).
import bpy, math, os, sys
from mathutils import Vector

FPS = 25
LOOP_S = 12
FRAMES = FPS * LOOP_S

args = sys.argv[sys.argv.index("--") + 1:]
mode, source, frames_dir = args[0], os.path.abspath(args[1]), os.path.abspath(args[2])
EXPLOSION_MP4 = os.path.join(source, "explosion.mp4")


def new_scene(name, width, height):
    scene = bpy.data.scenes.new(name)
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.fps = FPS
    scene.frame_start, scene.frame_end = 1, FRAMES
    scene.view_settings.view_transform = 'AgX'
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new(name + "_Monde")
    scene.world.use_nodes = True
    return scene


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


def link(scene, obj, material=None):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    scene.collection.objects.link(obj)
    if material:
        obj.data.materials.append(material)
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def sphere(scene, loc, scale, material, segments=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=segments // 2, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    return link(scene, o, material)


def box(scene, loc, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.active_object
    o.scale = scale
    if bevel:
        m = o.modifiers.new("b", 'BEVEL')
        m.width = bevel
        m.segments = 4
    return link(scene, o, material)


def cylinder(scene, loc, radius, depth, material, vertices=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    return link(scene, bpy.context.active_object, material)


def torus(scene, loc, major, minor, material):
    bpy.ops.mesh.primitive_torus_add(location=loc, major_radius=major, minor_radius=minor, major_segments=64,
                                     minor_segments=24)
    return link(scene, bpy.context.active_object, material)


def camera(scene, loc, target, lens):
    cam = bpy.data.objects.new(scene.name + "_Camera", bpy.data.cameras.new(scene.name + "_Camera"))
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def area_light(scene, loc, target, energy, color=(1, 1, 1), size=3.0):
    light = bpy.data.lights.new("Lumiere", 'AREA')
    light.energy = energy
    light.size = size
    light.color = color
    lo = bpy.data.objects.new("Lumiere", light)
    lo.location = loc
    lo.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(lo)
    return lo


def wave(t, terms):
    # Somme de sinus (amplitude, nombre de périodes par boucle, phase) : boucle sans raccord visible.
    return sum(a * math.sin(2 * math.pi * n * t / LOOP_S + p) for a, n, p in terms)


def key_socket(socket, frame, value):
    socket.default_value = value
    socket.keyframe_insert("default_value", frame=frame)


# --- Explosion -----------------------------------------------------------------------------------------------------

def volume_material(name, color, density, emission_color, contrast=6.0, noise_scale=5.0):
    # Volume bruité : densité = bruit 4D (W animé : la matière bouillonne) seuillé ; émission réglée par image.
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    out = nt.nodes["Material Output"]
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (*color, 1)
    vol.inputs["Emission Color"].default_value = (*emission_color, 1)
    vol.inputs["Emission Strength"].default_value = 0.0
    coords = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.noise_dimensions = '4D'
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 6.0
    noise.inputs["Roughness"].default_value = 0.6
    nt.links.new(coords.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.36
    ramp.inputs["From Max"].default_value = 0.36 + 1.0 / contrast
    ramp.inputs["To Max"].default_value = density
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], vol.inputs["Density"])
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    return m, noise.inputs["W"], vol.inputs["Emission Strength"], ramp.inputs["To Max"]


def build_explosion():
    scene = new_scene("Explosion", 1000, 400)
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.012, 0.018, 0.04, 1)
    # Sol (plaine sombre) et ligne d'horizon de collines.
    ground = mat("Sol", (0.05, 0.045, 0.04), 0.0, 0.9)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 60, 0))
    link(scene, bpy.context.active_object, ground)
    for i in range(14):
        x = -60 + i * 9.5
        sphere(scene, (x, 70 + (i % 3) * 6, -2.5), (7 + (i % 4) * 2, 4, 3.2 + (i % 5) * 0.6), ground, 24)
    # Boule de feu → calotte du champignon, colonne, anneau de la calotte et nuage de poussière au sol.
    fire_mat, fire_w, fire_emit, fire_density = volume_material("Boule", (0.32, 0.26, 0.22), 2.5, (1.0, 0.35, 0.06), 3.0)
    fireball = sphere(scene, (0, 0, 0.6), (0.1, 0.1, 0.1), fire_mat, 32)
    ring_mat, ring_w, ring_emit, ring_density = volume_material("Anneau", (0.3, 0.25, 0.22), 2.0, (1.0, 0.3, 0.06), 3.0)
    ring = torus(scene, (0, 0, 3), 1.0, 0.45, ring_mat)
    stem_mat, stem_w, stem_emit, stem_density = volume_material("Colonne", (0.3, 0.25, 0.22), 1.6, (1.0, 0.35, 0.08),
                                                                3.0, 7.0)
    stem = cylinder(scene, (0, 0, 1), 1.0, 2.0, stem_mat, 32)
    dust_mat, dust_w, dust_emit, dust_density = volume_material("Poussiere", (0.3, 0.27, 0.24), 0.8, (1.0, 0.4, 0.1),
                                                                4.0, 3.0)
    dust = torus(scene, (0, 0, 0.15), 1.0, 0.5, dust_mat)
    # Éclair : sphère blanche et lumière ponctuelle, sur les premières images.
    flash_mat = mat("Eclair", (1.0, 0.95, 0.85), 0.0)
    flash = sphere(scene, (0, 0, 0.6), (0.7, 0.7, 0.7), flash_mat, 32)
    flash_emit = flash_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"]
    flash_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 0.95, 0.85, 1)
    glow = bpy.data.lights.new("Lueur", 'POINT')
    glow.color = (1.0, 0.55, 0.25)
    glow.shadow_soft_size = 2.0
    glow_obj = bpy.data.objects.new("Lueur", glow)
    scene.collection.objects.link(glow_obj)
    cam = camera(scene, (0, -34, 1.6), (0, 0, 4.3), 58)

    for f in range(1, FRAMES + 1):
        t = (f - 1) / FPS
        rise = 1.0 - math.exp(-t / 3.5)
        z_cap = 0.8 + 5.2 * rise
        growth = 1.0 - math.exp(-t / 0.5)
        width = 1.3 * growth + 0.16 * t
        flatten = 1.0 - 0.45 * min(t / 5.0, 1.0)
        fireball.location = (0, 0, z_cap)
        fireball.scale = (width, width, width * flatten)
        fireball.keyframe_insert("location", frame=f)
        fireball.keyframe_insert("scale", frame=f)
        heat = 14.0 * math.exp(-t / 0.7) + 1.2 * math.exp(-t / 4.0) + 0.06
        key_socket(fire_emit, f, heat)
        key_socket(fire_w, f, t * 0.35)
        # Anneau autour de la calotte, qui apparaît après 2 s.
        ring_on = min(max((t - 1.8) / 1.5, 0.0), 1.0)
        ring.location = (0, 0, z_cap - 0.25 * width)
        ring.scale = (width * 0.95, width * 0.95, width * 0.7 * flatten)
        ring.keyframe_insert("location", frame=f)
        ring.keyframe_insert("scale", frame=f)
        key_socket(ring_density, f, 2.0 * ring_on)
        key_socket(ring_emit, f, (0.5 * math.exp(-t / 4.0) + 0.03) * ring_on)
        key_socket(ring_w, f, 10 + t * 0.3)
        # Colonne : du sol jusque sous la calotte, de plus en plus large.
        stem_on = min(max((t - 1.0) / 2.0, 0.0), 1.0)
        top = max(z_cap - 0.6 * width * flatten, 0.2)
        radius = 0.22 + 0.035 * t
        stem.location = (0, 0, top / 2)
        stem.scale = (radius, radius, top / 2)
        stem.keyframe_insert("location", frame=f)
        stem.keyframe_insert("scale", frame=f)
        key_socket(stem_density, f, 1.6 * stem_on)
        key_socket(stem_emit, f, (0.4 * math.exp(-t / 4.0) + 0.04) * stem_on)
        key_socket(stem_w, f, 20 + t * 0.5)
        # Poussière soulevée au sol : anneau plat qui s'élargit.
        spread = 0.6 + 4.5 * (1.0 - math.exp(-t / 4.0))
        dust.scale = (spread, spread, 0.35 + 0.05 * t)
        dust.keyframe_insert("scale", frame=f)
        key_socket(dust_density, f, 0.8 * min(t / 1.5, 1.0))
        key_socket(dust_emit, f, 0.25 * math.exp(-t / 2.0))
        key_socket(dust_w, f, 30 + t * 0.25)
        # Éclair, lueur sur le sol et la scène.
        key_socket(flash_emit, f, 60.0 * math.exp(-t / 0.08))
        flash.scale = (0.3 + 3.0 * t,) * 3 if t < 0.4 else (0.001,) * 3
        flash.keyframe_insert("scale", frame=f)
        glow_obj.location = (0, -1.0, max(z_cap - 1.1 * width * flatten, 0.3))
        glow_obj.keyframe_insert("location", frame=f)
        glow.energy = 3.0e5 * math.exp(-t / 0.15) + 3.0e3 * math.exp(-t / 3.0) + 300.0
        glow.keyframe_insert("energy", frame=f)
        key_socket(bg.inputs["Strength"], f, 1.0 + 12.0 * math.exp(-t / 0.12))
        # Caméra à l'épaule : léger tremblement, secousse à l'arrivée de l'onde.
        shake = 0.02 + 0.12 * math.exp(-max(t - 2.0, 0.0) / 0.6) * (t > 2.0)
        cam.location = (0.15 * math.sin(t * 1.3) + shake * math.sin(t * 37), -34, 1.6 + shake * math.sin(t * 29 + 1))
        cam.keyframe_insert("location", frame=f)
    scene.eevee.volumetric_tile_size = '2'
    scene.eevee.volumetric_samples = 96
    scene.eevee.use_volumetric_shadows = True
    sun = bpy.data.lights.new("Soleil", 'SUN')
    sun.energy = 2.5
    sun.color = (1.0, 0.75, 0.55)
    sun_obj = bpy.data.objects.new("Soleil", sun)
    sun_obj.rotation_euler = (math.radians(70), 0, math.radians(-60))
    scene.collection.objects.link(sun_obj)
    scene.eevee.volumetric_end = 120.0
    scene.eevee.taa_render_samples = 16
    scene.render.filepath = os.path.join(frames_dir, "explosion", "")
    return scene


# --- Plateau -------------------------------------------------------------------------------------------------------

def presenter(scene, x, skin, hair, jacket, accent, long_hair):
    box(scene, (x, 1.9, 1.5), (0.5, 0.25, 0.45), jacket, 0.18)                # buste (épaules carrées)
    box(scene, (x, 1.65, 1.55), (0.06, 0.02, 0.32), accent)                   # cravate / foulard
    cylinder(scene, (x, 1.9, 2.05), 0.11, 0.25, skin)                         # cou
    for dx in (-0.45, 0.45):                                                  # bras posés sur le bureau
        sphere(scene, (x + dx, 1.45, 1.05), (0.16, 0.42, 0.13), jacket)
    # Tête : pivot à la base du crâne (empty), tête et cheveux enfants.
    pivot = bpy.data.objects.new("Tete_%s" % ("G" if x < 0 else "D"), None)
    pivot.location = (x, 1.9, 2.15)
    scene.collection.objects.link(pivot)
    parts = [sphere(scene, (x, 1.9, 2.42), (0.24, 0.26, 0.31), skin),
             sphere(scene, (x, 1.97, 2.55), (0.26, 0.27, 0.27), hair)]
    if long_hair:
        parts.append(sphere(scene, (x, 2.05, 2.25), (0.3, 0.22, 0.4), hair))
    for part in parts:
        part.parent = pivot
        part.location -= pivot.location
    return pivot


def build_studio(name, alert):
    scene = new_scene(name, 960, 600)
    scene.view_settings.exposure = -0.6
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    box(scene, (0, 6, 2), (12, 0.1, 6), mat(name + "_Fond", (0.01, 0.025, 0.07), 0.25))
    band_color = (1.0, 0.08, 0.05) if alert else (0.2, 0.6, 1.0)
    band_mat = mat(name + "_Bandes", band_color, 6.0)
    for z in (0.9, 1.15, 4.2):
        box(scene, (0, 5.5, z), (12, 0.02, 0.02), band_mat)
    if alert:
        # Mur vidéo : six dalles (joints sombres) qui diffusent explosion.mp4 (1000 × 400, même rapport que le mur).
        wall = mat(name + "_MurVideo", (0, 0, 0))
        nt = wall.node_tree
        nt.nodes.remove(nt.nodes["Principled BSDF"])
        emission = nt.nodes.new("ShaderNodeEmission")
        emission.inputs["Strength"].default_value = 1.6
        tex = nt.nodes.new("ShaderNodeTexImage")
        image = bpy.data.images.load(EXPLOSION_MP4)
        image.source = 'MOVIE'
        tex.image = image
        tex.image_user.frame_duration = FRAMES
        tex.image_user.frame_start = 1
        tex.image_user.use_cyclic = True
        tex.image_user.use_auto_refresh = True
        nt.links.new(tex.outputs["Color"], emission.inputs["Color"])
        nt.links.new(emission.outputs["Emission"], nt.nodes["Material Output"].inputs["Surface"])
        bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 5.45, 2.75), rotation=(math.pi / 2, 0, 0))
        plane = bpy.context.active_object
        plane.scale = (11.0, 4.4, 1)
        link(scene, plane, wall)
        seam = mat(name + "_Joints", (0.005, 0.005, 0.01))
        for x in (-1.83, 1.83):
            box(scene, (x, 5.4, 2.75), (0.025, 0.01, 2.2), seam)
        box(scene, (0, 5.4, 2.75), (5.5, 0.01, 0.025), seam)
    else:
        sphere(scene, (0, 5.6, 2.6), (2.6, 0.2, 2.6), mat(name + "_Globe", (0.05, 0.25, 0.7), 0.9))
        for x in (-4.2, 4.2):
            box(scene, (x, 5.4, 2.4), (0.9, 0.05, 1.5), mat(name + "_Ecran", (0.06, 0.15, 0.35), 0.7), 0.05)
    desk = mat(name + "_Bureau", (0.85, 0.87, 0.9), 0.0, 0.25, 0.3)
    cylinder(scene, (0, 1.2, 0.45), 3.4, 0.9, desk)
    cylinder(scene, (0, 1.2, 0.93), 3.5, 0.06, mat(name + "_Plateau", (0.05, 0.06, 0.08), 0.0, 0.15, 0.6))
    box(scene, (0, -0.15, 0.62), (3.0, 0.03, 0.12), mat(name + "_Liseré", band_color, 5.0))
    left = presenter(scene, -1.15, mat(name + "_Peau1", (0.62, 0.44, 0.34)), mat(name + "_Cheveux1", (0.05, 0.035, 0.03)),
                     mat(name + "_Veste1", (0.04, 0.05, 0.12)), mat(name + "_Cravate", (0.6, 0.05, 0.05)), False)
    right = presenter(scene, 1.15, mat(name + "_Peau2", (0.75, 0.58, 0.47)), mat(name + "_Cheveux2", (0.35, 0.22, 0.1)),
                      mat(name + "_Veste2", (0.45, 0.05, 0.08)), mat(name + "_Foulard", (0.85, 0.85, 0.82)), True)
    for loc, energy in (((-3, -4, 4), 450), ((3, -4, 4), 450), ((0, 3, 6), 250)):
        area_light(scene, loc, (0, 1.5, 1.5), energy)
    red = area_light(scene, (0, -2, 5), (0, 1.5, 1.5), 0.0, (1.0, 0.1, 0.05), 5.0) if alert else None
    camera(scene, (0, -7.5, 2.6), (0, 2.0, 1.75), 42)

    # Têtes (rotation X : hochement, Z : tourner, Y : pencher). Normal : calme, chacun regarde la caméra et un peu
    # son voisin. Alerte : mouvements amples et rapides, coups d'œil vers le mur vidéo (derrière, sur le côté).
    for f in range(1, FRAMES + 1):
        t = (f - 1) / FPS
        for pivot, side, phase in ((left, -1, 0.0), (right, 1, 1.7)):
            if alert:
                turn = side * (0.25 + 0.25 * max(math.sin(2 * math.pi * 2 * t / LOOP_S + phase), 0.0) ** 3 * 4.0) \
                    + wave(t, [(0.08, 7, phase), (0.04, 19, phase * 2)])
                nod = wave(t, [(0.09, 9, phase), (0.05, 23, phase + 1)]) - 0.06
                tilt = wave(t, [(0.06, 5, phase), (0.03, 13, phase)])
            else:
                turn = side * 0.08 + wave(t, [(0.12, 1, phase), (0.05, 3, phase + 0.5)])
                nod = wave(t, [(0.05, 2, phase), (0.03, 7, phase + 1)])
                tilt = wave(t, [(0.04, 2, phase + 2)])
            pivot.rotation_euler = (nod, tilt, -turn)
            pivot.keyframe_insert("rotation_euler", frame=f)
        if alert:
            pulse = abs(math.sin(math.pi * 4 * t / LOOP_S * 3))
            key_socket(band_mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"], f, 2.0 + 10.0 * pulse)
            red.data.energy = 300.0 * pulse
            red.data.keyframe_insert("energy", frame=f)
    scene.render.filepath = os.path.join(frames_dir, "alert" if alert else "normal", "")
    return scene


def linear(scene):
    for obj in scene.objects:
        for data in (obj, obj.data):
            anim = getattr(data, "animation_data", None)
            if anim and anim.action:
                for fc in getattr(anim.action, "fcurves", []):
                    for k in fc.keyframe_points:
                        k.interpolation = 'LINEAR'


# Aperçu (5ᵉ argument facultatif, ex. "1,50,150") : seulement ces images, en fichiers fixes, pour mise au point.
preview = [int(v) for v in args[3].split(",")] if len(args) > 3 else None


def render(scene):
    if preview is None:
        bpy.ops.render.render(animation=True, scene=scene.name)
        return
    base = scene.render.filepath
    for f in preview:
        scene.frame_set(f)
        scene.render.filepath = base + "apercu_%04d" % f
        bpy.ops.render.render(write_still=True, scene=scene.name)
    scene.render.filepath = base


default = bpy.context.scene
if mode == "explosion":
    scene = build_explosion()
    bpy.data.scenes.remove(default)
    render(scene)
elif mode == "studio":
    scenes = [build_studio("Studio_Normal", False), build_studio("Studio_Alerte", True)]
    bpy.data.scenes.remove(default)
    for scene in scenes:
        linear(scene)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(source, "tv_studio.blend"), relative_remap=True)
    for scene in scenes:
        render(scene)
else:
    raise SystemExit("mode inconnu : " + mode)
