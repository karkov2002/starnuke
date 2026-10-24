# Outil hors-jeu : modélise les afficheurs muraux à cristaux liquides de la station et, à la demande, les pose aux
# emplacements de TARGETS dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de Blender Lab, port 9876) :
# - horloge (KIND « horloge ») : date ISO 8601 et heure UTC ;
# - afficheur de position (KIND « position ») : latitude et longitude de la station en temps réel, même boîtier,
#   avec une petite antenne GPS (galette) sur la tranche supérieure.
# CLOCK_MODE choisit l'action :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -Code 'CLOCK_MODE = "preview"; exec(open(r"E:\Projects\starnuke\tools\blender\build_station_clock.py", encoding="utf-8").read())'
#   - "preview" : dans une scène temporaire du fichier ouvert (la station n'est pas touchée, rien n'est enregistré),
#     construit les deux appareils sur une paroi, rend des aperçus dans PREVIEW_DIR, puis retire tout ce qu'il a créé ;
#   - "apply"   : nuke_station.blend ouvert ; crée ou remplace les objets de TARGETS (extras glTF : type, id,
#     materiau_ecran ; collection du module), rejouable. Ne réexporte rien : l'export vers Godot (export_station.py)
#     attend le feu vert de l'utilisateur.
#
# Boîtier (cotes nominales, multipliées par SCALE) : 20 cm × 8,2 cm × 2,3 cm, anthracite mat aux coins arrondis, sur
# une platine murale aluminium (3 mm), vitre noire brillante affleurante, deux boutons de réglage sur la tranche
# supérieure, voyant vert, câble d'alimentation qui rentre dans la paroi. SCALE = 1,4 (24/10/2026, demande de
# l'utilisateur : lisible depuis la couchette au réveil) : 28 × 11,5 × 3,2 cm.
# Repère local (mètres) : X vers la droite de l'affichage, Y vers la paroi (l'affichage regarde −Y), Z vers le haut ;
# origine au centre de la platine, sur la paroi (Y = 0).
# Dalle : la face avant de la vitre, matériau Ecran_Horloge (horloges) ou Ecran_Position (afficheur de position),
# partagé par les appareils d'une même sorte, UV 0–1 comme les autres dalles ((0, 0) en haut à gauche une fois dans
# glTF). En jeu, Godot y dessine l'affichage (scripts/screens/station_clocks.gd, station_position.gd) ; pour l'aperçu
# Blender, des textures de démonstration à chiffres à sept segments (DEMO_PNG) imitent l'affichage, avec la même
# disposition (cotes nominales de la dalle, origine au centre, communes aux scripts Godot).
# Boîte à outils : les primitives (Builder, rrect, slab, cyl, tube_along, material…) viennent de
# build_station_devices.py, chargé sans exécuter ses modes.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

CLOCK_MODE = globals().get("CLOCK_MODE", "preview")
PREVIEW_DIR = globals().get("PREVIEW_DIR", r"E:\Blender\apercus_horloge")
DEMO_PNG = {"horloge": r"E:\Blender\textures\horloge_demo.png", "position": r"E:\Blender\textures\position_demo.png"}
DEMO_DATE, DEMO_TIME = "2035-07-15", "12:34:56"
DEMO_LAT, DEMO_LON = 48.857, 2.352

MODE = "none"   # build_station_devices.py ne doit ni rendre ni remplacer quoi que ce soit.
exec(open(r"E:\Projects\starnuke\tools\blender\build_station_devices.py", encoding="utf-8").read())

# --- Dimensions nominales (mètres), multipliées par SCALE à la construction. ---
SCALE = 1.4
BODY_W, BODY_H, BODY_D = 0.200, 0.082, 0.020     # boîtier : largeur, hauteur, profondeur
BODY_R = 0.011                                   # rayon des coins
PLATE_W, PLATE_H, PLATE_T = 0.150, 0.056, 0.003  # platine murale
GLASS_W, GLASS_H, GLASS_T = 0.184, 0.066, 0.0012 # vitre (dalle)
GLASS_R = 0.006
BUTTON_R, BUTTON_H = 0.0032, 0.0016

# Emplacements dans la station (coordonnées monde de nuke_station.blend, parois relevées par lancer de rayons) :
# objet -> (sorte, collection, centre de la platine sur la paroi, normale de la paroi (vers l'observateur), haut de
# l'affichage). Taille posée : 28 × 11,5 cm.
TARGETS = {
    # Pied de la couchette : panneau gris du fond de la niche (x 1,80, y 1,28–1,60, z ±0,5), vu par le dormeur allongé
    # la tête vers +X (son « haut » est −Y, la paroi du lit vers le bas). Horloge à gauche, position à droite, 6 cm
    # d'écart.
    "Interactif_Horloge_Couchette": ("horloge", "Int_Habitation", (1.80, 1.43, -0.17), (1, 0, 0), (0, -1, 0)),
    "Interactif_Position_Couchette": ("position", "Int_Habitation", (1.80, 1.43, 0.17), (1, 0, 0), (0, -1, 0)),
    # Cuisine : paroi +Y (y 1,25) au-dessus de la jonction réchauffeur / distributeur d'eau (qui montent à z 0,31),
    # entre les deux sachets repas de la rangée haute (bords à x −3,20 et −2,675), sous le faisceau de câbles (z 0,50).
    "Interactif_Horloge_Cuisine": ("horloge", "Int_Habitation", (-2.95, 1.25, 0.41), (0, -1, 0), (0, 0, 1)),
    # Poste de pilotage : cloison avant (x 16,07) au-dessus du grand écran (qui monte à z 0,53), dans l'axe.
    "Interactif_Horloge_Pilotage": ("horloge", "Int_Commande", (16.07, 0.0, 0.72), (-1, 0, 0), (0, 0, 1)),
    # Sas : paroi +X de la chambre basse (x −8,98, plate sur |y| ≤ 0,15), au-dessus du manomètre et de la valve,
    # sous le rétrécissement du tube (z −3,1).
    "Interactif_Horloge_Sas": ("horloge", "Int_Sas", (-8.98, 0.0, -3.25), (-1, 0, 0), (0, 0, 1)),
}
SCREEN_MATERIAL = {"horloge": "Ecran_Horloge", "position": "Ecran_Position"}
# Filtre facultatif (mode « apply ») : CLOCK_ONLY = ["Interactif_Position_Couchette"].
CLOCK_ONLY = globals().get("CLOCK_ONLY")


# ------------------------------------------------------------------------------------------------ matériaux
def clock_materials():
    return {
        "coque": material("Int_Horloge_Coque", (0.030, 0.031, 0.034), 0.0, 0.58),
        "vitre": material("Int_Horloge_Vitre", (0.004, 0.004, 0.005), 0.0, 0.12),
        "bouton": material("Int_Horloge_Bouton", (0.012, 0.012, 0.013), 0.0, 0.75),
        "antenne": material("Int_Horloge_Antenne", (0.62, 0.63, 0.60), 0.0, 0.55),
        "plaque": material("Int_Bras_Plaque", (0.30, 0.31, 0.33), 0.9, 0.45),
        "inox": material("Int_PC_Inox", (0.62, 0.62, 0.63), 1.0, 0.28),
        "port": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
        "cable": material("Int_Cable", (0.015, 0.015, 0.016), 0.0, 0.6),
        "led": material("Int_PC_Led", (0.05, 0.6, 0.15), 0.0, 0.3, emission=(0.1, 1.0, 0.25), strength=4.0),
    }


def screen_material(kind, demo=False):
    """Matériau de la dalle : noir brillant ; en aperçu, la texture de démonstration en émission."""
    m = material(SCREEN_MATERIAL[kind], (0.0, 0.0, 0.0), 0.0, 0.10)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    path = DEMO_PNG[kind]
    if demo and os.path.exists(path):
        tex = nt.nodes.get("Demo") or nt.nodes.new("ShaderNodeTexImage")
        tex.name = "Demo"
        tex.location = (-400, 0)
        img = bpy.data.images.get(os.path.basename(path)) or bpy.data.images.load(path)
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


def drop_demo(kind):
    """Retire la texture de démonstration du matériau (l'export doit partir d'une dalle noire) et l'image orpheline."""
    screen_material(kind, demo=False)
    img = bpy.data.images.get(os.path.basename(DEMO_PNG[kind]))
    if img and img.users == 0:
        bpy.data.images.remove(img)


# ------------------------------------------------------------------------------------------------ textures de démo
# Segments d'un chiffre à sept segments (a haut, b haut droit, c bas droit, d bas, e bas gauche, f haut gauche,
# g milieu), chiffres 0–9, tiret et blanc. Mêmes formes que scripts/ui/segment_display.gd.
SEGMENTS = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
            "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""}
SLANT = 0.06
NARROW = {".": 0.45, "°": 0.5}     # largeur relative au pas des caractères étroits


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
    return [(key in lit, [(cx + x + SLANT * z, cz + z) for x, z in pts]) for key, pts in polys.items()]


def text_width(text, pitch):
    return sum(NARROW.get(ch, 1.0) * pitch for ch in text)


def circle(cx, cz, r, n=12):
    return [(cx + r * math.cos(2 * math.pi * k / n), cz + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def ring(cx, cz, r, t, n=16):
    """Anneau (symbole degré) découpé en trapèzes."""
    out = []
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        out.append([(cx + r * math.cos(a0), cz + r * math.sin(a0)), (cx + r * math.cos(a1), cz + r * math.sin(a1)),
                    (cx + (r - t) * math.cos(a1), cz + (r - t) * math.sin(a1)),
                    (cx + (r - t) * math.cos(a0), cz + (r - t) * math.sin(a0))])
    return out


def digit_polys(text, x_left, cz, h, pitch):
    """Polygones (allumés, éteints) d'une suite de caractères à sept segments partant de x_left, centrée en cz :
    chiffres, tiret, blanc (segments éteints), « : » (deux points, pas plein), « . » et « ° » (étroits)."""
    lit, off = [], []
    x = x_left
    for ch in text:
        w = NARROW.get(ch, 1.0) * pitch
        cx = x + w / 2
        if ch == ":":
            for dz in (h * 0.22, -h * 0.22):
                lit.append(circle(cx + SLANT * dz, cz + dz, h * 0.07))
        elif ch == ".":
            lit.append(circle(cx + SLANT * (-h * 0.44), cz - h * 0.44, h * 0.065))
        elif ch == "°":
            lit += ring(cx + SLANT * h * 0.34, cz + h * 0.34, h * 0.13, h * 0.055)
        else:
            for is_lit, pts in segment_polys(ch, cx, cz, h, h * 0.12):
                (lit if is_lit else off).append(pts)
        x += w
    return lit, off


def demo_layout(kind):
    """Disposition de l'affichage (cotes nominales de la dalle, origine au centre, z vers le haut) : liste de
    (« digits », texte, x_gauche, z_centre, hauteur, pas) et de (« font », texte, x, z_centre, taille, alignement)."""
    if kind == "horloge":
        date, time = DEMO_DATE, DEMO_TIME
        return [("digits", date, -0.022 - text_width(date, 0.0105) / 2, 0.0170, 0.0150, 0.0105),
                ("digits", time, -text_width(time, 0.0198) / 2, -0.0110, 0.0290, 0.0198),
                ("font", "UTC", GLASS_W / 2 - 0.010, 0.0170, 0.0115, 'RIGHT')]
    lat = "%7.3f°" % abs(DEMO_LAT)
    lon = "%07.3f°" % abs(DEMO_LON)
    return [("font", "N" if DEMO_LAT >= 0 else "S", -0.078, 0.0150, 0.0170, 'LEFT'),
            ("digits", lat, -0.052, 0.0150, 0.0260, 0.0168),
            ("font", "E" if DEMO_LON >= 0 else "W", -0.078, -0.0165, 0.0170, 'LEFT'),
            ("digits", lon, -0.052, -0.0165, 0.0260, 0.0168)]


def build_demo_texture(kind):
    """Rend DEMO_PNG[kind] : fond sombre, segments éteints à peine visibles, segments allumés clairs."""
    scene = bpy.data.scenes.new("_Afficheur_Demo")
    world = bpy.data.worlds.new("_Afficheur_Demo")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.010, 0.012, 0.014, 1)
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.resolution_x = 1024
    scene.render.resolution_y = int(round(1024 * GLASS_H / GLASS_W))
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = DEMO_PNG[kind]
    on = material("_Segment_On", (0, 0, 0), 0.0, 1.0, emission=(0.80, 0.93, 1.0), strength=1.0)
    off = material("_Segment_Off", (0, 0, 0), 0.0, 1.0, emission=(0.032, 0.036, 0.042), strength=1.0)
    ink = material("_Encre", (0, 0, 0), 0.0, 1.0, emission=(0.80, 0.93, 1.0), strength=0.8)
    font = bpy.data.fonts.load(r"C:\Windows\Fonts\arialbd.ttf", check_existing=True) \
        if os.path.exists(r"C:\Windows\Fonts\arialbd.ttf") else None
    made = []

    def polys_object(name, polys, mat):
        if not polys:
            return
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

    for item in demo_layout(kind):
        if item[0] == "digits":
            _, text, x_left, cz, h, pitch = item
            lit, unlit = digit_polys(text, x_left, cz, h, pitch)
            polys_object("_on", lit, on)
            polys_object("_off", unlit, off)
        else:
            _, text, x, cz, size, align = item
            cu = bpy.data.curves.new("_txt", 'FONT')
            cu.body = text
            cu.size = size
            cu.align_x = align
            cu.align_y = 'CENTER'
            if font:
                cu.font = font
            cu.materials.append(ink)
            ob = bpy.data.objects.new("_txt", cu)
            ob.location = (x, 0, cz)
            ob.rotation_euler = (math.pi / 2, 0, 0)
            scene.collection.objects.link(ob)
            made.append(ob)
    cam_data = bpy.data.cameras.new("_Afficheur_Demo")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = GLASS_W
    cam = bpy.data.objects.new("_Afficheur_Demo", cam_data)
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


# ------------------------------------------------------------------------------------------------ appareil
def build_device(b, screen_mat, kind):
    """Afficheur sur sa platine, cotes nominales (repère : affichage vers −Y, paroi à Y = 0)."""
    to_front = Matrix.Rotation(math.pi / 2, 4, 'X')    # +Z de la pièce -> −Y (vers l'observateur)
    # Platine murale (3 mm d'épaisseur, cachée derrière le boîtier : visible de profil comme une entretoise).
    b.add(slab(rrect(PLATE_W, PLATE_H, 0.006, 4), 0.0, PLATE_T, bevel=0.0006), "plaque", to_front)
    # Boîtier : prisme aux coins arrondis, arête avant biseautée (2,5 mm), arrière à peine cassée.
    body = slab(rrect(BODY_W, BODY_H, BODY_R, 8), 0.0, BODY_D, bevel=0.0025, bseg=3, bevel_bottom=0.0008)
    b.add(body, "coque", Matrix.Translation((0, -PLATE_T, 0)) @ to_front)
    # Vitre affleurante (0,4 mm en avant du boîtier) : flancs noirs brillants, face avant = dalle (UV 0–1).
    front_y = -PLATE_T - BODY_D
    glass = slab(rrect(GLASS_W, GLASS_H, GLASS_R, 6), 0.0, GLASS_T, bevel=0.0005, bseg=2)
    b.add(glass, "vitre", Matrix.Translation((0, front_y + 0.0004, 0)) @ to_front)

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
    mid_y = -PLATE_T - BODY_D * 0.5
    for x in (0.058, 0.074):
        b.add(cyl(BUTTON_R, BUTTON_H, 16, bevel=0.0005), "bouton",
              Matrix.Translation((x, mid_y, top_z + BUTTON_H / 2 - 0.0002)))
    if kind == "position":
        # Antenne GPS : galette blanc cassé sur un pied court, à gauche de la tranche supérieure.
        b.add(cyl(0.0035, 0.004, 14), "coque", Matrix.Translation((-0.060, mid_y, top_z + 0.0018)))
        b.add(cyl(0.0105, 0.0055, 28, r2=0.0085, bevel=0.0012), "antenne",
              Matrix.Translation((-0.060, mid_y, top_z + 0.0060)))
    # Voyant (vert) dans le coin inférieur droit du boîtier, sous la vitre.
    b.add(cyl(0.0009, 0.0005, 10), "led", Matrix.Translation((GLASS_W / 2 - 0.004, front_y - 0.0002,
                                                               -GLASS_H / 2 - 0.0045)) @ to_front)
    # Câble d'alimentation : sort du bas du boîtier et rentre dans la paroi.
    z0 = -BODY_H / 2
    b.add(tube_along([(0.052, mid_y, z0 + 0.004), (0.053, -PLATE_T - BODY_D * 0.45, z0 - 0.010),
                      (0.056, -0.009, z0 - 0.030), (0.058, -0.002, z0 - 0.040), (0.058, 0.004, z0 - 0.042)],
                     0.0022, 10), "cable")


def make_device(obj_name, kind, screen_mat, mats=None):
    """Objet obj_name (créé s'il manque, maillage remplacé sinon), cotes multipliées par SCALE."""
    b = Builder(mats or clock_materials())
    build_device(b, screen_mat, kind)
    bmesh.ops.scale(b.bm, vec=(SCALE, SCALE, SCALE), verts=b.bm.verts)
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
    for kind in DEMO_PNG:
        os.makedirs(os.path.dirname(DEMO_PNG[kind]), exist_ok=True)
        build_demo_texture(kind)
    window = bpy.context.window
    previous_scene = window.scene if window else None
    scene = bpy.data.scenes.new("_Horloge_Apercu")
    if window:
        window.scene = scene
    created = []
    faces = {}
    try:
        mats = clock_materials()
        for name, kind, x in (("_Horloge", "horloge", -0.17), ("_Position", "position", 0.17)):
            obj = make_device(name, kind, screen_material(kind, demo=True), mats=mats)
            obj.location = (x, 0, 0)
            scene.collection.objects.link(obj)
            created.append(obj)
            faces[kind] = len(obj.data.polygons)
        wall = bpy.data.objects.new("_Paroi", bpy.data.meshes.new("_Paroi"))
        wall.data.from_pydata([(-1, 0, -1), (1, 0, -1), (1, 0, 1), (-1, 0, 1)], [], [(0, 1, 2, 3)])
        wall.data.materials.append(material("_Paroi", (0.62, 0.62, 0.60), 0.0, 0.7))
        scene.collection.objects.link(wall)
        created.append(wall)
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
            "paire_face": ((0.0, -0.95, 0.0), (0, 0, 0), 50),
            "position_face": ((0.17, -0.55, 0.0), (0.17, 0, 0), 50),
            "position_3-4": ((0.50, -0.45, 0.20), (0.17, 0, 0.0), 50),
            "position_dessus": ((0.12, -0.25, 0.28), (0.12, 0, 0.04), 50),
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
        if "_Paroi" in bpy.data.materials:
            bpy.data.materials.remove(bpy.data.materials["_Paroi"])
        for kind in DEMO_PNG:
            drop_demo(kind)
        # Matériaux propres aux afficheurs : retirés s'ils n'existent que pour l'aperçu (le mode « apply » les recrée).
        for name in ("Int_Horloge_Coque", "Int_Horloge_Vitre", "Int_Horloge_Bouton", "Int_Horloge_Antenne",
                     "Ecran_Horloge", "Ecran_Position"):
            m = bpy.data.materials.get(name)
            if m and m.users == 0:
                bpy.data.materials.remove(m)
    result = {"faces": faces, "apercus": PREVIEW_DIR, "scene_restauree": window.scene.name if window else ""}

elif CLOCK_MODE == "apply":
    assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
    mats = clock_materials()
    done = {}
    for name, (kind, col_name, center, n, up) in TARGETS.items():
        if CLOCK_ONLY and name not in CLOCK_ONLY:
            continue
        obj = make_device(name, kind, screen_material(kind, demo=False), mats=mats)
        if obj.name not in bpy.data.collections[col_name].objects:
            for col in list(obj.users_collection):
                col.objects.unlink(obj)
            bpy.data.collections[col_name].objects.link(obj)
        obj["interactif"] = True
        obj["type"] = kind
        obj["id"] = name.removeprefix("Interactif_")
        obj["materiau_ecran"] = SCREEN_MATERIAL[kind]
        obj.matrix_world = frame_screen(center, n, up)
        done[name] = len(obj.data.polygons)
    result = {"afficheurs": done}
