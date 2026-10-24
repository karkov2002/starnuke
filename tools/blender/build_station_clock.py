# Outil hors-jeu : modélise l'horloge murale à affichage LCD de la station (date et heure UTC) et, à la demande,
# la pose aux emplacements de TARGETS dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de
# Blender Lab, port 9876). CLOCK_MODE choisit l'action :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -Code 'CLOCK_MODE = "preview"; exec(open(r"E:\Projects\starnuke\tools\blender\build_station_clock.py", encoding="utf-8").read())'
#   - "preview" : dans une scène temporaire du fichier ouvert (la station n'est pas touchée, rien n'est enregistré),
#     construit une horloge sur une paroi, rend des aperçus dans PREVIEW_DIR, puis retire tout ce qu'elle a créé ;
#   - "apply"   : nuke_station.blend ouvert ; crée ou remplace les objets Interactif_Horloge_<id> de TARGETS (extras
#     glTF : type « horloge », id, materiau_ecran ; collection du module), rejouable. Ne réexporte rien : l'export vers
#     Godot (export_station.py) attend le feu vert de l'utilisateur.
#
# Horloge : 20 cm × 8,2 cm × 2,3 cm, boîtier anthracite mat aux coins arrondis sur une platine murale aluminium
# (3 mm), vitre noire brillante affleurante, deux boutons de réglage sur la tranche supérieure, câble d'alimentation
# qui rentre dans la paroi. Repère local (mètres) : X vers la droite de l'affichage, Y vers la paroi (l'affichage
# regarde −Y), Z vers le haut ; origine au centre de la platine, sur la paroi (Y = 0).
# Dalle : la face avant de la vitre, matériau Ecran_Horloge (partagé par toutes les horloges : même heure partout),
# UV 0–1 comme les autres dalles ((0, 0) en haut à gauche une fois dans glTF). En jeu, Godot y dessine la date et
# l'heure UTC de l'horloge du jeu ; pour l'aperçu Blender, une texture de démonstration à chiffres à sept segments
# (DEMO_PNG, rendue par ce script) imite l'affichage : date ISO 8601 (aucune langue), heure, mention « UTC ».
# Boîte à outils : les primitives (Builder, rrect, slab, cyl, tube_along, material…) viennent de
# build_station_devices.py, chargé sans exécuter ses modes.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

CLOCK_MODE = globals().get("CLOCK_MODE", "preview")
PREVIEW_DIR = globals().get("PREVIEW_DIR", r"E:\Blender\apercus_horloge")
DEMO_PNG = r"E:\Blender\textures\horloge_demo.png"
DEMO_DATE, DEMO_TIME = "2035-07-15", "12:34:56"

MODE = "none"   # build_station_devices.py ne doit ni rendre ni remplacer quoi que ce soit.
exec(open(r"E:\Projects\starnuke\tools\blender\build_station_devices.py", encoding="utf-8").read())

# --- Dimensions (mètres). ---
BODY_W, BODY_H, BODY_D = 0.200, 0.082, 0.020     # boîtier : largeur, hauteur, profondeur
BODY_R = 0.011                                   # rayon des coins
PLATE_W, PLATE_H, PLATE_T = 0.150, 0.056, 0.003  # platine murale
GLASS_W, GLASS_H, GLASS_T = 0.184, 0.066, 0.0012 # vitre (dalle)
GLASS_R = 0.006
BUTTON_R, BUTTON_H = 0.0032, 0.0016

# Emplacements dans la station (coordonnées monde de nuke_station.blend, parois relevées par lancer de rayons) :
# id -> (collection, centre de la platine sur la paroi, normale de la paroi (vers l'observateur), haut de l'affichage).
TARGETS = {
    # Pied de la couchette : panneau gris du fond de la niche (x 1,80, y 1,28–1,60, z ±0,5), vu par le dormeur allongé
    # la tête vers +X (son « haut » est −Y, la paroi du lit vers le bas) ; un peu à gauche de l'axe, comme demandé.
    "Couchette": ("Int_Habitation", (1.80, 1.43, -0.15), (1, 0, 0), (0, -1, 0)),
    # Cuisine : paroi +Y (y 1,25) au-dessus de la jonction réchauffeur / distributeur d'eau, entre les deux sachets
    # repas de la rangée haute (x −3,28 et −2,60), sous le faisceau de câbles (z 0,50).
    "Cuisine": ("Int_Habitation", (-2.95, 1.25, 0.42), (0, -1, 0), (0, 0, 1)),
    # Poste de pilotage : cloison avant (x 16,07) au-dessus du grand écran (qui monte à z 0,53), dans l'axe.
    "Pilotage": ("Int_Commande", (16.07, 0.0, 0.72), (-1, 0, 0), (0, 0, 1)),
    # Sas : paroi +X de la chambre basse (x −8,98), au-dessus du manomètre et de la valve (équipements jusqu'à
    # z −3,48), sous le rétrécissement du tube (z −3,1).
    "Sas": ("Int_Sas", (-8.98, 0.0, -3.25), (-1, 0, 0), (0, 0, 1)),
}
# Filtre facultatif (mode « apply ») : ONLY = ["Interactif_Horloge_Couchette"].
CLOCK_ONLY = globals().get("CLOCK_ONLY")


# ------------------------------------------------------------------------------------------------ matériaux
def clock_materials():
    return {
        "coque": material("Int_Horloge_Coque", (0.030, 0.031, 0.034), 0.0, 0.58),
        "vitre": material("Int_Horloge_Vitre", (0.004, 0.004, 0.005), 0.0, 0.12),
        "bouton": material("Int_Horloge_Bouton", (0.012, 0.012, 0.013), 0.0, 0.75),
        "plaque": material("Int_Bras_Plaque", (0.30, 0.31, 0.33), 0.9, 0.45),
        "inox": material("Int_PC_Inox", (0.62, 0.62, 0.63), 1.0, 0.28),
        "port": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
        "cable": material("Int_Cable", (0.015, 0.015, 0.016), 0.0, 0.6),
    }


def screen_material(demo=False):
    """Matériau de la dalle : noir brillant ; en aperçu, la texture de démonstration en émission."""
    m = material("Ecran_Horloge", (0.0, 0.0, 0.0), 0.0, 0.10)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    if demo and os.path.exists(DEMO_PNG):
        tex = nt.nodes.get("Demo") or nt.nodes.new("ShaderNodeTexImage")
        tex.name = "Demo"
        tex.location = (-400, 0)
        img = bpy.data.images.get(os.path.basename(DEMO_PNG)) or bpy.data.images.load(DEMO_PNG)
        img.reload()
        tex.image = img
        nt.links.new(tex.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = 1.6
    else:
        tex = nt.nodes.get("Demo")
        if tex:
            nt.nodes.remove(tex)
        p.inputs["Emission Strength"].default_value = 0.0
    return m


# ------------------------------------------------------------------------------------------------ texture de démo
# Segments d'un chiffre à sept segments (a haut, b haut droit, c bas droit, d bas, e bas gauche, f haut gauche,
# g milieu), chiffres 0–9 et tiret.
SEGMENTS = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
            "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""}


def segment_polys(ch, cx, cz, h, t):
    """Polygones (listes de (x, z)) des sept segments d'un caractère : (allumé, points). Hauteur h, trait t."""
    w = h * 0.52
    hw, hh = w / 2, h / 2
    g = t * 0.18                                     # jeu entre segments
    def horiz(zc, half):
        return [(-half + g, zc), (-half + t / 2 + g, zc + t / 2), (half - t / 2 - g, zc + t / 2),
                (half - g, zc), (half - t / 2 - g, zc - t / 2), (-half + t / 2 + g, zc - t / 2)]
    def vert(xc, z0, z1):
        return [(xc, z0 + g), (xc + t / 2, z0 + t / 2 + g), (xc + t / 2, z1 - t / 2 - g), (xc, z1 - g),
                (xc - t / 2, z1 - t / 2 - g), (xc - t / 2, z0 + t / 2 + g)]
    lit = SEGMENTS.get(ch, "")
    polys = {
        "a": horiz(hh - t / 2, hw - t / 2), "d": horiz(-hh + t / 2, hw - t / 2), "g": horiz(0.0, hw - t / 2),
        "b": vert(hw - t / 2, 0.0, hh), "c": vert(hw - t / 2, -hh, 0.0),
        "f": vert(-hw + t / 2, 0.0, hh), "e": vert(-hw + t / 2, -hh, 0.0),
    }
    slant = 0.06                                     # légère italique, comme les afficheurs
    out = []
    for key, pts in polys.items():
        out.append((key in lit, [(cx + x + slant * z, cz + z) for x, z in pts]))
    return out


def build_demo_texture():
    """Rend DEMO_PNG : fond sombre, segments éteints à peine visibles, segments allumés clairs ; date en haut, heure en
    grand, « UTC » à droite de la date."""
    scene = bpy.data.scenes.new("_Horloge_Demo")
    world = bpy.data.worlds.new("_Horloge_Demo")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.010, 0.012, 0.014, 1)
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.resolution_x = 1024
    scene.render.resolution_y = int(round(1024 * GLASS_H / GLASS_W))
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = DEMO_PNG
    on = material("_Segment_On", (0, 0, 0), 0.0, 1.0, emission=(0.80, 0.93, 1.0), strength=1.0)
    off = material("_Segment_Off", (0, 0, 0), 0.0, 1.0, emission=(0.032, 0.036, 0.042), strength=1.0)
    ink = material("_Encre_UTC", (0, 0, 0), 0.0, 1.0, emission=(0.80, 0.93, 1.0), strength=0.8)
    made = []

    def polys_object(name, polys, mat):
        bm = bmesh.new()
        for pts in polys:
            bm.faces.new([bm.verts.new((x, 0.0, z)) for x, z in pts])
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        scene.collection.objects.link(ob)
        made.append(ob)

    def digits(text, cx, cz, h, pitch, colon_h=None):
        lit_polys, off_polys = [], []
        n = len(text)
        x = cx - (n - 1) * pitch / 2
        for ch in text:
            if ch == ":":
                r = h * 0.07
                for dz in (h * 0.22, -h * 0.22):
                    lit_polys.append([(x + r * math.cos(a), cz + dz + r * math.sin(a))
                                      for a in [2 * math.pi * k / 12 for k in range(12)]])
            else:
                for is_lit, pts in segment_polys(ch, x, cz, h, h * 0.12):
                    (lit_polys if is_lit else off_polys).append(pts)
            x += pitch
        polys_object("_on", lit_polys, on)
        polys_object("_off", off_polys, off)

    # Date (petits chiffres) en haut, à gauche ; heure (grands chiffres) en bas.
    digits(DEMO_DATE, -0.022, 0.0170, 0.0150, 0.0105)
    digits(DEMO_TIME, 0.0, -0.0110, 0.0290, 0.0198)
    font = bpy.data.fonts.load(r"C:\Windows\Fonts\arialbd.ttf", check_existing=True) \
        if os.path.exists(r"C:\Windows\Fonts\arialbd.ttf") else None
    cu = bpy.data.curves.new("_utc", 'FONT')
    cu.body = "UTC"
    cu.size = 0.0115
    cu.align_x = 'RIGHT'
    cu.align_y = 'CENTER'
    if font:
        cu.font = font
    cu.materials.append(ink)
    ob = bpy.data.objects.new("_utc", cu)
    ob.location = (GLASS_W / 2 - 0.010, 0, 0.0170)
    ob.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(ob)
    made.append(ob)
    cam_data = bpy.data.cameras.new("_Horloge_Demo")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = GLASS_W
    cam = bpy.data.objects.new("_Horloge_Demo", cam_data)
    cam.location = (0, -0.1, 0)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    window = bpy.context.window
    previous = window.scene if window else None
    if window:
        window.scene = scene
    bpy.ops.render.render(write_still=True, scene=scene.name)
    if window and previous:
        window.scene = previous
    for ob in made:
        data = ob.data
        bpy.data.objects.remove(ob)
        if isinstance(data, bpy.types.Mesh):
            bpy.data.meshes.remove(data)
        else:
            bpy.data.curves.remove(data)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    bpy.data.scenes.remove(scene)
    bpy.data.worlds.remove(world)
    for m in (on, off, ink):
        bpy.data.materials.remove(m)


# ------------------------------------------------------------------------------------------------ horloge
def build_clock(b, screen_mat):
    """Horloge sur sa platine (repère : affichage vers −Y, paroi à Y = 0)."""
    to_front = Matrix.Rotation(math.pi / 2, 4, 'X')    # +Z de la pièce -> −Y (vers l'observateur)
    # Platine murale (3 mm d'épaisseur, cachée derrière le boîtier : visible de profil comme une entretoise).
    b.add(slab(rrect(PLATE_W, PLATE_H, 0.006, 4), 0.0, PLATE_T, bevel=0.0006), "plaque", to_front)
    # Boîtier : prisme aux coins arrondis, arête avant biseautée (2,5 mm), arrière à peine cassée.
    body = slab(rrect(BODY_W, BODY_H, BODY_R, 8), 0.0, BODY_D, bevel=0.0025, bseg=3, bevel_bottom=0.0008)
    b.add(body, "coque", Matrix.Translation((0, -PLATE_T, 0)) @ to_front)
    # Vitre affleurante (0,8 mm en avant du boîtier) : flancs noirs brillants, face avant = dalle (UV 0–1).
    front_y = -PLATE_T - BODY_D
    glass = slab(rrect(GLASS_W, GLASS_H, GLASS_R, 6), 0.0, GLASS_T, bevel=0.0005, bseg=2)
    glass_faces = b.add(glass, "vitre", Matrix.Translation((0, front_y + 0.0004, 0)) @ to_front)

    def disp_uv(co, face):
        return (co.x / GLASS_W + 0.5, co.z / GLASS_H + 0.5)

    disp = bmesh.new()
    hw, hh = GLASS_W / 2 - 0.0008, GLASS_H / 2 - 0.0008
    vs = [disp.verts.new(p) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]
    f = disp.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    b.add(disp, screen_mat, Matrix.Translation((0, front_y + 0.0004 - GLASS_T - 0.0001, 0)), uv_fn=disp_uv)
    # Boutons de réglage (mode, réglage) sur la tranche supérieure, à droite.
    top_z = BODY_H / 2
    for x in (0.058, 0.074):
        b.add(cyl(BUTTON_R, BUTTON_H, 16, bevel=0.0005), "bouton",
              Matrix.Translation((x, -PLATE_T - BODY_D * 0.5, top_z + BUTTON_H / 2 - 0.0002)))
    # Voyant de synchronisation (vert) dans le coin inférieur droit du boîtier, sous la vitre.
    b.add(cyl(0.0009, 0.0005, 10), "led", Matrix.Translation((GLASS_W / 2 - 0.004, front_y - 0.0002,
                                                               -GLASS_H / 2 - 0.0045)) @ to_front)
    # Câble d'alimentation : sort du bas du boîtier et rentre dans la paroi.
    z0 = -BODY_H / 2
    b.add(tube_along([(0.052, -PLATE_T - BODY_D * 0.5, z0 + 0.004), (0.053, -PLATE_T - BODY_D * 0.45, z0 - 0.010),
                      (0.056, -0.009, z0 - 0.030), (0.058, -0.002, z0 - 0.040), (0.058, 0.004, z0 - 0.042)],
                     0.0022, 10), "cable")
    return glass_faces


def make_clock(obj_name, screen_mat, mats=None):
    mats = mats or clock_materials()
    mats["led"] = material("Int_PC_Led", (0.05, 0.6, 0.15), 0.0, 0.3, emission=(0.1, 1.0, 0.25), strength=4.0)
    b = Builder(mats)
    build_clock(b, screen_mat)
    obj = bpy.data.objects.get(obj_name)
    old = obj.data if obj else None
    mesh = bpy.data.meshes.new(obj_name)
    b.finish(mesh)
    if obj is None:
        obj = bpy.data.objects.new(obj_name, mesh)
    else:
        obj.data = mesh
        if old and old.users == 0:
            bpy.data.meshes.remove(old)
    return obj


if CLOCK_MODE == "preview":
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(DEMO_PNG), exist_ok=True)
    build_demo_texture()
    window = bpy.context.window
    previous_scene = window.scene if window else None
    scene = bpy.data.scenes.new("_Horloge_Apercu")
    if window:
        window.scene = scene
    created = []
    try:
        mats = clock_materials()
        clock = make_clock("_Horloge", screen_material(demo=True), mats=mats)
        scene.collection.objects.link(clock)
        created.append(clock)
        wall = bpy.data.objects.new("_Paroi", bpy.data.meshes.new("_Paroi"))
        wall.data.from_pydata([(-1, 0, -1), (1, 0, -1), (1, 0, 1), (-1, 0, 1)], [], [(0, 1, 2, 3)])
        wall.data.materials.append(material("_Paroi", (0.62, 0.62, 0.60), 0.0, 0.7))
        scene.collection.objects.link(wall)
        created.append(wall)
        faces = len(clock.data.polygons)
        scene.render.engine = 'BLENDER_EEVEE'
        scene.render.resolution_x, scene.render.resolution_y = 1280, 800
        scene.view_settings.view_transform = 'AgX'
        world = bpy.data.worlds.new("_Horloge_Apercu")
        world.use_nodes = True
        world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.055, 0.06, 1)
        scene.world = world
        for nm, loc, energy, size in (("_Cle", (0.5, -0.7, 0.6), 14, 0.8), ("_Contre", (-0.6, -0.5, -0.2), 5, 0.6),
                                      ("_Haut", (0.0, -0.3, 0.8), 7, 0.8)):
            ld = bpy.data.lights.new(nm, 'AREA')
            ld.energy, ld.size = energy, size
            lo = bpy.data.objects.new(nm, ld)
            lo.location = loc
            lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            scene.collection.objects.link(lo)
            created.append(lo)
        cam = bpy.data.objects.new("_Camera", bpy.data.cameras.new("_Camera"))
        scene.collection.objects.link(cam)
        created.append(cam)
        scene.camera = cam
        cam.data.clip_start = 0.005
        shots = {
            "horloge_face": ((0.0, -0.42, 0.0), (0, 0, 0), 50),
            "horloge_3-4": ((0.26, -0.34, 0.14), (0, 0, -0.005), 50),
            "horloge_cote": ((0.30, -0.12, 0.05), (0.0, -0.01, 0.0), 60),
            "horloge_dessus": ((0.05, -0.20, 0.22), (0.02, 0, 0.02), 50),
            "horloge_cadrage_station": ((-0.6, -1.3, -0.3), (0, 0, 0), 35),
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
        for ob in created:
            data = ob.data
            bpy.data.objects.remove(ob)
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
        bpy.data.scenes.remove(scene)
        if "_Horloge_Apercu" in bpy.data.worlds:
            bpy.data.worlds.remove(bpy.data.worlds["_Horloge_Apercu"])
        for name in ("_Paroi",):
            if name in bpy.data.materials:
                bpy.data.materials.remove(bpy.data.materials[name])
        # Matériaux de l'horloge : retirés s'ils n'existent que pour l'aperçu (le mode « apply » les recrée).
        for name in ("Int_Horloge_Coque", "Int_Horloge_Vitre", "Int_Horloge_Bouton", "Ecran_Horloge"):
            m = bpy.data.materials.get(name)
            if m and m.users == 0:
                bpy.data.materials.remove(m)
        if os.path.basename(DEMO_PNG) in bpy.data.images and bpy.data.images[os.path.basename(DEMO_PNG)].users == 0:
            bpy.data.images.remove(bpy.data.images[os.path.basename(DEMO_PNG)])
    result = {"faces": faces, "apercus": PREVIEW_DIR, "scene_restauree": window.scene.name if window else ""}

elif CLOCK_MODE == "apply":
    assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
    mats = clock_materials()
    screen = screen_material(demo=False)
    done = {}
    for cid, (col_name, center, n, up) in TARGETS.items():
        name = "Interactif_Horloge_" + cid
        if CLOCK_ONLY and name not in CLOCK_ONLY:
            continue
        obj = make_clock(name, screen, mats=mats)
        if obj.name not in bpy.data.collections[col_name].objects:
            for col in list(obj.users_collection):
                col.objects.unlink(obj)
            bpy.data.collections[col_name].objects.link(obj)
        obj["interactif"] = True
        obj["type"] = "horloge"
        obj["id"] = "Horloge_" + cid
        obj["materiau_ecran"] = "Ecran_Horloge"
        obj.matrix_world = frame_screen(center, n, up)
        done[name] = len(obj.data.polygons)
    result = {"horloges": done}
