# Outil hors-jeu : modélise la console du radar (récepteur goniométrique) du module Commande et, à la demande, la
# pose à la place de l'écran d'ambiance Interactif_Ecran_07 dans E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab, port 9876). RADAR_MODE choisit l'action :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -Code 'RADAR_MODE = "preview"; exec(open(r"E:\Projects\starnuke\tools\blender\build_radar_console.py", encoding="utf-8").read())'
#   - "preview" : dans une scène temporaire du fichier ouvert (la station n'est pas touchée, rien n'est enregistré),
#     construit la console devant une paroi, rend des aperçus dans PREVIEW_DIR, puis retire tout ce qu'il a créé ;
#   - "apply"   : nuke_station.blend ouvert ; remplace le maillage d'Interactif_Ecran_07 (nom, extras et matériau de
#     dalle Ecran_07 gardés, extra type -> « radar ») et crée ou remplace ses trois boutons (objets enfants).
#     Rejouable. Ne réexporte rien : l'export vers Godot (export_station.py) attend le feu vert de l'utilisateur.
#
# Console : caisson gris acier de 90 × 70 cm à 7,5 cm de la paroi, poignées de rack de chaque côté, vis, ouïes,
# voyant ; en haut, la dalle (76 × 43 cm, matériau Ecran_07, UV 0–1) derrière une lèvre noire ; en bas, une bande en
# aluminium brossé avec trois boutons et leurs graduations en relief :
#   - Radar_Bouton_Azimut (gauche) : rotation de l'antenne, 36 graduations ;
#   - Radar_Bouton_Frequence (centre) : accord, 20 graduations ;
#   - Radar_Bouton_Bande (droite) : sélecteur à manette deux positions (VHF à gauche, UHF à droite, ± BAND_DEG).
# Aucun texte sur le modèle (règle des langues) : le jeu écrit le nom des boutons en bas de la dalle.
# Repère de la console (comme les écrans plats, frame_screen) : X vers la droite de l'image, Y vers la paroi (l'image
# regarde −Y), Z vers le haut ; origine au centre de la dalle. Boutons : origine au centre de leur pied, sur la face
# de la bande ; axe de rotation = leur Z local, tourné vers l'observateur ; repère blanc vers leur +Y local (le haut
# à la position zéro). Une rotation positive autour de Z est donc antihoraire vue de face. En jeu,
# scripts/screens/radar_console.gd les fait tourner.
# Boîte à outils : primitives de build_station_devices.py, chargé sans exécuter ses modes.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

RADAR_MODE = globals().get("RADAR_MODE", "preview")
PREVIEW_DIR = globals().get("PREVIEW_DIR", r"E:\Blender\apercus_radar")

MODE = "none"
exec(open(r"E:\Projects\starnuke\tools\blender\build_station_devices.py", encoding="utf-8").read())

# --- Cotes (mètres), repère de la console. ---
DISP_W, DISP_H = 0.76, 0.43                 # dalle
WIN_MARGIN = 0.012                          # lèvre noire autour de la dalle
BOX_W, BOX_H = 0.90, 0.70                   # façade
BOX_TOP = DISP_H / 2 + 0.035                # haut de la façade, au-dessus du centre de la dalle
BOX_BOTTOM = BOX_TOP - BOX_H
BOX_D = 0.075                               # face avant -> paroi
FRONT_Y = -0.003                            # face avant de la façade
FRONT_T = 0.012                             # épaisseur de la façade
STRIP_TOP = -DISP_H / 2 - 0.030             # bande des boutons
STRIP_BOTTOM = BOX_BOTTOM + 0.025
STRIP_Y = FRONT_Y - 0.004                   # face de la bande
KNOB_Z = (STRIP_TOP + STRIP_BOTTOM) / 2
KNOBS = {                                   # nom -> (x, graduations, sorte)
    "Radar_Bouton_Azimut": (-0.27, 36, "rond"),
    "Radar_Bouton_Frequence": (0.0, 20, "rond"),
    "Radar_Bouton_Bande": (0.27, 2, "manette"),
}
BAND_DEG = 40.0

# Emplacement dans la station (coordonnées Blender, relevées par lancer de rayons) : paroi −Y du module Commande à
# y = −1,25, plate de x 13,20 (hiloire de la cupola) à 14,25 (écran 08) et de z −0,46 à 0,46. Haut de la façade à
# z 0,27 (comme l'écran 08), centre en x 13,70.
TOP_Z = 0.27
TARGET = ((13.70, -1.25 + BOX_D, TOP_Z - BOX_TOP), (0, 1, 0), (0, 0, 1))
SCREEN_OBJECT = "Interactif_Ecran_07"


def radar_materials():
    mats = materials()
    mats.update({
        "panneau": material("Int_Radar_Panneau", (0.075, 0.080, 0.088), 0.65, 0.42),
        "bande": material("Int_Radar_Bande", (0.42, 0.43, 0.45), 1.0, 0.34),
        "bouton": material("Int_Radar_Bouton", (0.018, 0.018, 0.020), 0.0, 0.50),
        "repere": material("Int_Radar_Repere", (0.85, 0.85, 0.82), 0.0, 0.45),
    })
    return mats


TO_FRONT = Matrix.Rotation(math.pi / 2, 4, 'X')     # +Z d'une pièce -> −Y (vers l'observateur), +Y -> +Z
TO_BACK = Matrix.Rotation(-math.pi / 2, 4, 'X')     # +Z d'une pièce -> +Y (vers la paroi)


def ring_xz(outer, inner, y0, y1):
    """Plaque percée dans le plan XZ entre y0 (avant) et y1 (arrière) ; outer et inner : contours (x, z) de même
    nombre de points, parcourus dans le même ordre (rrect au même seg)."""
    bm = bmesh.new()
    n = len(outer)
    of = [bm.verts.new((x, y0, z)) for x, z in outer]
    ob = [bm.verts.new((x, y1, z)) for x, z in outer]
    inf = [bm.verts.new((x, y0, z)) for x, z in inner]
    inb = [bm.verts.new((x, y1, z)) for x, z in inner]
    for k in range(n):
        q = (k + 1) % n
        bm.faces.new((of[k], of[q], inf[q], inf[k]))
        bm.faces.new((ob[k], inb[k], inb[q], ob[q]))
        bm.faces.new((of[k], ob[k], ob[q], of[q]))
        bm.faces.new((inf[k], inf[q], inb[q], inb[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_console(b, screen_mat):
    cz = (BOX_TOP + BOX_BOTTOM) / 2
    seg = 6
    # Façade percée d'une fenêtre pour la dalle, caisson jusqu'à la paroi.
    outer = rrect(BOX_W, BOX_H, 0.018, seg, 0.0, cz)
    window = rrect(DISP_W + 2 * WIN_MARGIN, DISP_H + 2 * WIN_MARGIN, 0.008, seg)
    b.add(ring_xz(outer, window, FRONT_Y, FRONT_Y + FRONT_T), "panneau")
    b.add(slab(rrect(BOX_W - 0.02, BOX_H - 0.02, 0.02, seg), 0.0, BOX_D - FRONT_T + FRONT_Y, bevel=0.004), "dos",
          Matrix.Translation((0, FRONT_Y + FRONT_T - 0.001, cz)) @ TO_BACK)
    # Lèvre noire de la fenêtre, dalle juste derrière.
    lip_out = rrect(DISP_W + 2 * WIN_MARGIN, DISP_H + 2 * WIN_MARGIN, 0.008, seg)
    lip_in = rrect(DISP_W + 0.001, DISP_H + 0.001, 0.002, seg)
    b.add(ring_xz(lip_out, lip_in, FRONT_Y - 0.002, FRONT_Y + 0.0015), "cadre")

    def disp_uv(co, face):
        return (co.x / DISP_W + 0.5, co.z / DISP_H + 0.5)

    disp = bmesh.new()
    hw, hh = DISP_W / 2, DISP_H / 2
    vs = [disp.verts.new(p) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]
    f = disp.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    b.add(disp, screen_mat, Matrix.Translation((0, FRONT_Y + 0.001, 0)), uv_fn=disp_uv)
    # Bande des boutons : aluminium brossé rapportée et vissée.
    sh = STRIP_TOP - STRIP_BOTTOM
    b.add(slab(rrect(BOX_W - 0.08, sh, 0.008, 4), 0.0, FRONT_Y - STRIP_Y, bevel=0.0012), "bande",
          Matrix.Translation((0, FRONT_Y, KNOB_Z)) @ TO_FRONT)
    screws(b, [(sx * (BOX_W / 2 - 0.055), STRIP_Y, KNOB_Z + sz * (sh / 2 - 0.016))
               for sx in (-1, 1) for sz in (-1, 1)], TO_FRONT, r=0.0035, head=0.0018)
    # Graduations en relief autour des boutons, deux repères pour le sélecteur de bande.
    for name, (x, ticks, kind) in KNOBS.items():
        if kind == "manette":
            for ang in (-BAND_DEG, BAND_DEG):
                a = math.radians(ang)
                b.add(cyl(0.0042, 0.0012, 16), "repere",
                      Matrix.Translation((x + 0.050 * math.sin(a), STRIP_Y - 0.0004, KNOB_Z + 0.050 * math.cos(a)))
                      @ TO_FRONT)
            continue
        for k in range(ticks):
            ang = 2 * math.pi * k / ticks
            major = k % (ticks // 4) == 0 if ticks % 4 == 0 else k % (ticks // 2) == 0
            r0, r1 = 0.045, (0.058 if major else 0.052)
            w = 0.0024 if major else 0.0014
            mid = (r0 + r1) / 2
            m = Matrix.Translation((x + mid * math.sin(ang), STRIP_Y - 0.0004, KNOB_Z + mid * math.cos(ang))) \
                @ Matrix.Rotation(ang, 4, 'Y') @ TO_FRONT
            b.add(box(w, r1 - r0, 0.0012), "repere", m)
    # Ouïes d'aération en haut à droite, voyant de marche en haut à gauche.
    for i in range(14):
        b.add(box(0.004, 0.0016, 0.022, r=0.0015), "port",
              Matrix.Translation((BOX_W / 2 - 0.200 + i * 0.011, FRONT_Y - 0.0004, BOX_TOP - 0.0175)))
    b.add(cyl(0.0035, 0.002, 16), "led", Matrix.Translation((-BOX_W / 2 + 0.040, FRONT_Y, BOX_TOP - 0.0175)) @ TO_FRONT)
    # Vis de façade aux quatre coins.
    screws(b, [(sx * (BOX_W / 2 - 0.016), FRONT_Y, cz + sz * (BOX_H / 2 - 0.016)) for sx in (-1, 1) for sz in (-1, 1)],
           TO_FRONT, r=0.0040, head=0.0020)
    # Poignées de rack (U) de chaque côté.
    for sx in (-1, 1):
        hx = sx * (BOX_W / 2 - 0.020)
        top, bot = cz + 0.17, cz - 0.17
        pts = [(hx, FRONT_Y - 0.002, top), (hx, FRONT_Y - 0.026, top - 0.012), (hx, FRONT_Y - 0.034, top - 0.045),
               (hx, FRONT_Y - 0.034, bot + 0.045), (hx, FRONT_Y - 0.026, bot + 0.012), (hx, FRONT_Y - 0.002, bot)]
        b.add(tube_along(pts, 0.0065, 14), "alu")
        for z in (top, bot):
            b.add(cyl(0.011, 0.004, 20, bevel=0.001), "alu_noir",
                  Matrix.Translation((hx, FRONT_Y - 0.002, z)) @ TO_FRONT)
    # Câbles d'alimentation et de données : sortent sous le caisson et rentrent dans la paroi.
    for i, dx in enumerate((-0.30, -0.27)):
        z0 = BOX_BOTTOM + 0.012
        b.add(tube_along([(dx, BOX_D * 0.45, z0), (dx, BOX_D * 0.5, z0 - 0.03),
                          (dx - 0.01 * i, BOX_D * 0.85, z0 - 0.06), (dx - 0.01 * i, BOX_D + 0.005, z0 - 0.07)],
                         0.0045 if i == 0 else 0.0035, 10), "cable")


def build_knob(b, kind):
    """Bouton dans son repère : axe Z vers l'observateur, origine au pied (face de la bande), repère vers +Y."""
    if kind == "manette":
        # Sélecteur à manette : embase ronde, barre effilée, trait blanc vers +Y.
        b.add(cyl(0.024, 0.010, 32, bevel=0.002), "bouton", Matrix.Translation((0, 0, 0.005)))
        bar = slab([(-0.009, -0.032), (0.009, -0.032), (0.006, 0.040), (0.0, 0.046), (-0.006, 0.040)], 0.010, 0.034,
                   bevel=0.003, bseg=3)
        b.add(bar, "bouton")
        b.add(box(0.0035, 0.034, 0.0010), "repere", Matrix.Translation((0, 0.020, 0.0345)))
        return
    # Bouton d'instrument : jupe, corps cannelé, chapeau alu, traits blancs vers +Y.
    b.add(cyl(0.040, 0.004, 48, bevel=0.0012), "bouton", Matrix.Translation((0, 0, 0.002)))
    b.add(box(0.0030, 0.008, 0.0008), "repere", Matrix.Translation((0, 0.0355, 0.0042)))
    b.add(knob(0.031, 0.026, lobes=24, seg=96), "bouton", Matrix.Translation((0, 0, 0.004 + 0.013)))
    b.add(cyl(0.0265, 0.003, 48, r2=0.0255, bevel=0.001), "bande", Matrix.Translation((0, 0, 0.0315)))
    b.add(box(0.0032, 0.020, 0.0010), "repere", Matrix.Translation((0, 0.014, 0.0335)))


def knob_local(x):
    return Matrix.Translation((x, STRIP_Y, KNOB_Z)) @ TO_FRONT


def mesh_object(name, builder, collection=None):
    obj = bpy.data.objects.get(name)
    old = obj.data if obj else None
    mesh = bpy.data.meshes.new(name)
    builder.finish(mesh)
    if obj is None:
        obj = bpy.data.objects.new(name, mesh)
        if collection:
            collection.objects.link(obj)
    else:
        obj.data = mesh
        if old and old.users == 0:
            bpy.data.meshes.remove(old)
    return obj


def make_console(console_name, screen_mat, collection=None):
    mats = radar_materials()
    b = Builder(mats)
    build_console(b, screen_mat)
    console = mesh_object(console_name, b, collection)
    knobs = []
    for name, (x, ticks, kind) in KNOBS.items():
        kb = Builder(mats)
        build_knob(kb, kind)
        obj = mesh_object(name, kb, collection)
        obj.parent = console
        obj.matrix_parent_inverse = Matrix()
        # Sélecteur de bande au départ sur VHF (à gauche : rotation antihoraire vue de face), comme le jeu.
        turn = math.radians(BAND_DEG) if kind == "manette" else 0.0
        obj.matrix_basis = knob_local(x) @ Matrix.Rotation(turn, 4, 'Z')
        knobs.append(obj)
    return console, knobs


if RADAR_MODE == "preview":
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    window = bpy.context.window
    previous_scene = window.scene if window else None
    scene = bpy.data.scenes.new("_Radar_Apercu")
    if window:
        window.scene = scene
    created = []
    faces = {}
    try:
        demo = material("_Radar_Demo", (0.0, 0.0, 0.0), 0.0, 0.1, emission=(0.03, 0.22, 0.10), strength=1.0)
        console, knobs = make_console("_Radar", demo)
        for ob in [console] + knobs:
            scene.collection.objects.link(ob)
            created.append(ob)
        console.matrix_world = Matrix.Translation((0, -BOX_D, 0))
        faces = {o.name: len(o.data.polygons) for o in [console] + knobs}
        wall = bpy.data.objects.new("_Paroi", bpy.data.meshes.new("_Paroi"))
        wall.data.from_pydata([(-2, 0, -2), (2, 0, -2), (2, 0, 2), (-2, 0, 2)], [], [(0, 1, 2, 3)])
        wall.data.materials.append(material("_Paroi_R", (0.62, 0.62, 0.60), 0.0, 0.7))
        scene.collection.objects.link(wall)
        created.append(wall)
        scene.render.engine = 'BLENDER_EEVEE'
        scene.render.resolution_x, scene.render.resolution_y = 1280, 900
        scene.view_settings.view_transform = 'AgX'
        world = bpy.data.worlds.new("_Radar_Apercu")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.055, 0.06, 1)
        scene.world = world
        for nm, loc, energy, size in (("_Cle", (1.2, -1.6, 1.2), 90, 1.2), ("_Contre", (-1.4, -1.0, -0.4), 30, 1.0),
                                      ("_Haut", (0.0, -0.8, 1.5), 40, 1.2)):
            ld = bpy.data.lights.new(nm, 'AREA')
            ld.energy, ld.size = energy, size
            lo = bpy.data.objects.new(nm, ld)
            lo.location = loc
            lo.rotation_euler = (Vector((0, -0.1, -0.05)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            scene.collection.objects.link(lo)
            created.append(lo)
        cam = bpy.data.objects.new("_Camera", bpy.data.cameras.new("_Camera"))
        scene.collection.objects.link(cam)
        created.append(cam)
        scene.camera = cam
        cam.data.clip_start = 0.005
        fy = -BOX_D
        shots = {
            "radar_face": ((0.0, -2.0, -0.05), (0, fy, -0.05), 50),
            "radar_3-4": ((0.9, -1.5, 0.35), (0, fy, -0.05), 45),
            "radar_boutons": ((0.10, -0.55, KNOB_Z + 0.12), (0.0, fy, KNOB_Z), 40),
            "radar_cote": ((0.75, -0.30, -0.05), (0.2, fy * 0.5, -0.05), 35),
        }
        for nm, (loc, target, lens) in shots.items():
            cam.location = loc
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam.data.lens = lens
            scene.render.filepath = os.path.join(PREVIEW_DIR, nm + ".png")
            bpy.ops.render.render(write_still=True, scene=scene.name)
    finally:
        if window and previous_scene:
            window.scene = previous_scene
        for ob in reversed(created):
            data = ob.data
            bpy.data.objects.remove(ob)
            if isinstance(data, bpy.types.Mesh) and data.users == 0:
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
        bpy.data.scenes.remove(scene)
        if "_Radar_Apercu" in bpy.data.worlds:
            bpy.data.worlds.remove(bpy.data.worlds["_Radar_Apercu"])
        for name in ("_Paroi_R", "_Radar_Demo", "Int_Radar_Panneau", "Int_Radar_Bande", "Int_Radar_Bouton",
                     "Int_Radar_Repere"):
            m = bpy.data.materials.get(name)
            if m and m.users == 0:
                bpy.data.materials.remove(m)
    result = {"faces": faces, "apercus": PREVIEW_DIR}

elif RADAR_MODE == "apply":
    assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
    obj = bpy.data.objects[SCREEN_OBJECT]
    screen = bpy.data.materials[obj["materiau_ecran"]]
    collection = obj.users_collection[0]
    console, knobs = make_console(SCREEN_OBJECT, screen, collection)
    center, n, up = TARGET
    console.matrix_world = frame_screen(center, n, up)
    console["type"] = "radar"
    result = {"console": len(console.data.polygons), "boutons": {k.name: len(k.data.polygons) for k in knobs},
              "centre": [round(v, 3) for v in console.matrix_world.translation]}
