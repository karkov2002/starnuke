# Outil hors-jeu : matériaux réalistes texturés (photos PBR ambientCG, licence CC0), impressions (cadrans, plaques
# gravées, étiquettes : textures dessinées par Blender avec de vrais caractères) et extincteur détaillé, partagés par
# build_airlock.py (valve et extincteur du sas), build_arrimage_extinguisher.py et build_arrimage_stowage.py. Chargé
# dans le Blender ouvert par exec(open(".../pbr_kit.py").read()) après props_kit.py (soft_box, cylinder, revolve,
# torus, tube).
# Textures dans E:\Blender\textures\<id>\ (téléchargées depuis https://ambientcg.com, CC0) : PaintedMetal001 (métal
#   peint rayé : recoloré pour la valve), PaintedMetal004 (peinture rouge : extincteurs), Metal012 (acier), Fabric036,
#   Fabric048, Fabric082A (tissus). Images recalculées (couleurs, cartes compressées, impressions) dans
#   E:\Blender\textures\Generated.
# Coordonnées de texture : celles des maillages (en mètres, projection des Builder) ; les pièces imprimées portent les
#   leurs (couche « UVMap » de la pièce, recopiée par les Builder).
import bpy, bmesh, math, os
from mathutils import Matrix, Vector

TEXTURES = r"E:\Blender\textures"
GENERATED = os.path.join(TEXTURES, "Generated")
FONT_REGULAR = r"C:\Windows\Fonts\arial.ttf"
FONT_BOLD = r"C:\Windows\Fonts\arialbd.ttf"


def _image(path, non_color):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None or os.path.normcase(bpy.path.abspath(img.filepath)) != os.path.normcase(path):
        img = bpy.data.images.load(path)
    img.reload()
    img.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    return img


def _save_jpeg(img, out, quality):
    img.filepath_raw = out
    img.file_format = 'JPEG'
    sc = bpy.context.scene
    old = sc.render.image_settings.quality
    sc.render.image_settings.quality = quality
    img.save()
    sc.render.image_settings.quality = old


def _to_srgb(lin):
    import numpy as np
    lin = np.clip(lin, 0.0, 1.0)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def _src(asset, res, kind):
    return os.path.join(TEXTURES, asset, "%s_%s-JPG_%s.jpg" % (asset, res, kind))


def repainted_color(asset, rgb, out_name, keep=0.35, res="1K", chips=1.0):
    """Couleur d'une peinture recalculée dans la teinte rgb (linéaire) : les variations de luminance de la photo sont
    gardées à keep près (rayures, salissures) ; le métal nu (carte Metalness) reste gris acier, dosé par chips (0 :
    peinture intacte). JPEG (qualité 92) dans GENERATED."""
    import numpy as np
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    color = bpy.data.images.load(_src(asset, res, "Color"))
    metal = bpy.data.images.load(_src(asset, res, "Metalness"))
    w, h = color.size
    c = np.array(color.pixels[:], dtype=np.float32).reshape(h, w, 4)
    m = np.array(metal.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., 0:1]
    m = m * chips  # dosage des écaillures (la carte est presque binaire : un seuil ne la réduisait pas)
    lum = (0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2])[..., None]
    rel = np.clip(1.0 + keep * (lum - lum.mean()) / max(float(lum.std()), 1e-4), 0.45, 1.35)
    paint = np.array(rgb, dtype=np.float32)[None, None, :] * rel
    steel = np.clip(lum * 0.9 + 0.25, 0.0, 1.0) * np.array((0.58, 0.59, 0.61), dtype=np.float32)[None, None, :]
    rgb_out = paint * (1.0 - m) + steel * m
    img = bpy.data.images.new(out_name, w, h)
    img.colorspace_settings.name = 'sRGB'
    img.pixels[:] = np.concatenate([_to_srgb(rgb_out), np.ones((h, w, 1), dtype=np.float32)], axis=2).ravel()
    _save_jpeg(img, out, 92)
    bpy.data.images.remove(img)
    bpy.data.images.remove(color)
    bpy.data.images.remove(metal)
    return out


def recolored_fabric(asset, rgb, out_name, keep=0.6, res="2K"):
    """Couleur d'un tissu recalculée dans la teinte rgb (linéaire), relief du tissage gardé à keep près."""
    import numpy as np
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    src = bpy.data.images.load(_src(asset, res, "Color"))
    w, h = src.size
    c = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)
    lum = (0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2])[..., None]
    rel = np.clip(1.0 + keep * (lum - lum.mean()) / max(float(lum.mean()), 1e-4), 0.3, 1.6)
    lin = np.array(rgb, dtype=np.float32)[None, None, :] * rel
    img = bpy.data.images.new(out_name, w, h)
    img.colorspace_settings.name = 'sRGB'
    img.pixels[:] = np.concatenate([_to_srgb(lin), np.ones((h, w, 1), dtype=np.float32)], axis=2).ravel()
    _save_jpeg(img, out, 92)
    bpy.data.images.remove(img)
    bpy.data.images.remove(src)
    return out


def compact_map(asset, kind, res, out_name, size=None, quality=85):
    """Carte (NormalGL, Roughness…) réenregistrée en JPEG plus compressé, redimensionnée à size (côté) si donné : les
    cartes d'origine pèsent jusqu'à 10 Mo en 2K."""
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    img = bpy.data.images.load(_src(asset, res, kind))
    img.colorspace_settings.name = 'Non-Color'
    _ = img.pixels[0]  # charge les données (sinon « does not have any image data » à l'enregistrement)
    if size:
        img.scale(size, size)
    _save_jpeg(img, out, quality)
    bpy.data.images.remove(img)
    return out


def pbr_material(name, asset, color_path=None, normal_strength=1.0, metal_override=None, roughness_scale=1.0,
                 normal_path=None, rough_path=None, uv_scale=1.0, res="1K"):
    """Matériau Principled à textures : couleur (color_path ou celle de l'asset), rugosité, métallicité, normales
    (OpenGL), uv_scale répétitions par mètre. Recréé à chaque appel (nœuds remplacés)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (400, 0)
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    p.location = (100, 0)
    nt.links.new(p.outputs["BSDF"], out.inputs["Surface"])
    mapping = None
    if uv_scale != 1.0:
        uvmap = nt.nodes.new("ShaderNodeUVMap")
        uvmap.location = (-900, 0)
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.location = (-700, 0)
        mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, 1.0)
        nt.links.new(uvmap.outputs["UV"], mapping.inputs["Vector"])

    def tex(path, non_color, y):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _image(path, non_color)
        t.location = (-400, y)
        if mapping:
            nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
        return t
    col = tex(color_path or _src(asset, res, "Color"), False, 300)
    nt.links.new(col.outputs["Color"], p.inputs["Base Color"])
    rough = tex(rough_path or _src(asset, res, "Roughness"), True, 0)
    if roughness_scale != 1.0:
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = roughness_scale
        mul.location = (-150, 0)
        nt.links.new(rough.outputs["Color"], mul.inputs[0])
        nt.links.new(mul.outputs[0], p.inputs["Roughness"])
    else:
        nt.links.new(rough.outputs["Color"], p.inputs["Roughness"])
    if metal_override is None:
        metal = tex(_src(asset, res, "Metalness"), True, -300)
        nt.links.new(metal.outputs["Color"], p.inputs["Metallic"])
    else:
        p.inputs["Metallic"].default_value = metal_override
    normal = tex(normal_path or _src(asset, res, "NormalGL"), True, -600)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-150, -600)
    nmap.inputs["Strength"].default_value = normal_strength
    nt.links.new(normal.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], p.inputs["Normal"])
    m.diffuse_color = (0.6, 0.6, 0.6, 1.0)
    return m


def fabric_material(name, asset, rgb, uv_scale, keep=0.6, normal_strength=1.0, roughness_scale=1.0):
    """Tissu réaliste : couleur 2K recolorée (rgb), normales 2K compressées, rugosité 1K ; uv_scale répétitions par
    mètre (tissage fin)."""
    color = recolored_fabric(asset, rgb, name + "_Color", keep) if rgb else None
    # Relief et rugosité partagés par tous les matériaux d'un même tissu (une seule image chacun dans le glTF).
    normal = compact_map(asset, "NormalGL", "2K", asset + "_2K_Normal")
    rough = compact_map(asset, "Roughness", "2K", asset + "_1K_Roughness", size=1024)
    if color is None:
        color = compact_map(asset, "Color", "2K", name + "_Color", quality=92)
    return pbr_material(name, asset, color, normal_strength, metal_override=0.0, roughness_scale=roughness_scale,
                        normal_path=normal, rough_path=rough, uv_scale=uv_scale)


def painted_metal_2k(name, asset, rgb, keep=0.2, chips=1.0, metal=0.15, roughness_scale=1.0, normal_strength=0.8,
                     uv_scale=1.0):
    """Métal peint 2K : couleur recalculée (rgb), relief 2K compressé, rugosité 1K (partagés par asset)."""
    color = repainted_color(asset, rgb, name + "_Color", keep, "2K", chips)
    normal = compact_map(asset, "NormalGL", "2K", asset + "_2K_Normal")
    rough = compact_map(asset, "Roughness", "2K", asset + "_1K_Roughness", size=1024)
    return pbr_material(name, asset, color, normal_strength, metal, roughness_scale, normal, rough, uv_scale)


# ------------------------------------------------------------------------------------------------ impressions
def _linear(c):
    return tuple(cc / 12.92 if cc <= 0.04045 else ((cc + 0.055) / 1.055) ** 2.4 for cc in c)


class Print:
    """Dessin 2D rendu en texture (PNG) par Blender : rectangles, arcs, traits et vrais textes (police Arial), en
    unités du dessin (x 0..w, y 0..h, origine en bas à gauche) ; couleurs sRGB."""

    def __init__(self, name, w, h, px_per_unit, background=(1, 1, 1)):
        self.name, self.w, self.h, self.ppu = name, w, h, px_per_unit
        self.scene = bpy.data.scenes.new("_Impression_" + name)
        self.objects = []
        self.mats = {}
        self.z = 0.0
        self.rect(0, 0, w, h, background)

    def _mat(self, color):
        key = tuple(round(c, 4) for c in color)
        if key not in self.mats:
            m = bpy.data.materials.new("_imp_%d" % len(self.mats))
            m.use_nodes = True
            nt = m.node_tree
            nt.nodes.clear()
            o = nt.nodes.new("ShaderNodeOutputMaterial")
            e = nt.nodes.new("ShaderNodeEmission")
            e.inputs["Color"].default_value = (*_linear(color), 1.0)
            e.inputs["Strength"].default_value = 1.0
            nt.links.new(e.outputs[0], o.inputs[0])
            self.mats[key] = m
        return self.mats[key]

    def _mesh(self, verts, faces, color):
        self.z += 0.0005
        me = bpy.data.meshes.new("_imp")
        me.from_pydata([(x, y, self.z) for x, y in verts], [], faces)
        me.materials.append(self._mat(color))
        ob = bpy.data.objects.new("_imp", me)
        self.scene.collection.objects.link(ob)
        self.objects.append(ob)

    def rect(self, x0, y0, x1, y1, color):
        self._mesh([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], [(0, 1, 2, 3)], color)

    def poly(self, pts, color):
        self._mesh(pts, [tuple(range(len(pts)))], color)

    def line(self, x0, y0, x1, y1, width, color):
        d = Vector((x1 - x0, y1 - y0))
        n = Vector((-d.y, d.x)).normalized() * width / 2
        self.poly([(x0 + n.x, y0 + n.y), (x1 + n.x, y1 + n.y), (x1 - n.x, y1 - n.y), (x0 - n.x, y0 - n.y)], color)

    def arc(self, cx, cy, r0, r1, a0, a1, color, seg=64):
        """Couronne de r0 à r1 entre les angles a0 et a1 (radians, sens trigonométrique depuis +x)."""
        verts, faces = [], []
        for k in range(seg + 1):
            a = a0 + (a1 - a0) * k / seg
            verts += [(cx + r0 * math.cos(a), cy + r0 * math.sin(a)), (cx + r1 * math.cos(a), cy + r1 * math.sin(a))]
            if k:
                i = 2 * k
                faces.append((i - 2, i - 1, i + 1, i))
        self._mesh(verts, faces, color)

    def disk(self, cx, cy, r, color, seg=64):
        self.arc(cx, cy, 0.0, r, 0.0, 2 * math.pi, color, seg)

    def text(self, s, x, y, size, color, align='CENTER', bold=False, angle=0.0):
        self.z += 0.0005
        cu = bpy.data.curves.new("_imp_txt", 'FONT')
        cu.body = s
        path = FONT_BOLD if bold else FONT_REGULAR
        if os.path.exists(path):
            font = next((f for f in bpy.data.fonts if os.path.normcase(f.filepath) == os.path.normcase(path)), None)
            cu.font = font or bpy.data.fonts.load(path)
        cu.size = size
        cu.align_x = align
        cu.align_y = 'CENTER'
        cu.materials.append(self._mat(color))
        ob = bpy.data.objects.new("_imp_txt", cu)
        ob.location = (x, y, self.z)
        ob.rotation_euler.z = angle
        self.scene.collection.objects.link(ob)
        self.objects.append(ob)

    def render(self):
        """Rendu orthographique du dessin (EEVEE, transformation de vue « Standard » : couleurs exactes) en PNG."""
        os.makedirs(GENERATED, exist_ok=True)
        out = os.path.join(GENERATED, self.name + ".png")
        sc = self.scene
        cd = bpy.data.cameras.new("_imp_cam")
        cd.type = 'ORTHO'
        cd.ortho_scale = max(self.w, self.h)
        cam = bpy.data.objects.new("_imp_cam", cd)
        cam.location = (self.w / 2, self.h / 2, 10.0)
        sc.collection.objects.link(cam)
        sc.camera = cam
        sc.render.engine = 'BLENDER_EEVEE'
        sc.view_settings.view_transform = 'Standard'
        sc.view_settings.look = 'None'
        sc.render.resolution_x = round(self.w * self.ppu)
        sc.render.resolution_y = round(self.h * self.ppu)
        sc.render.resolution_percentage = 100
        sc.render.film_transparent = False
        sc.render.image_settings.file_format = 'PNG'
        sc.render.image_settings.color_mode = 'RGB'
        sc.render.filepath = out
        if hasattr(sc.eevee, "taa_render_samples"):
            sc.eevee.taa_render_samples = 16
        bpy.ops.render.render(write_still=True, scene=sc.name)
        for ob in self.objects + [cam]:
            data = ob.data
            bpy.data.objects.remove(ob)
            if isinstance(data, bpy.types.Mesh):
                bpy.data.meshes.remove(data)
            elif isinstance(data, bpy.types.Curve):
                bpy.data.curves.remove(data)
        bpy.data.cameras.remove(cd)
        for m in self.mats.values():
            bpy.data.materials.remove(m)
        bpy.data.scenes.remove(sc)
        img = bpy.data.images.get(os.path.basename(out))
        if img:
            img.reload()
        return out


def printed_material(name, png, roughness=0.45, metallic=0.0, clearcoat=False):
    """Matériau d'une impression (couleur = PNG) ; UV de la pièce (0–1)."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    p = nt.nodes.new("ShaderNodeBsdfPrincipled")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _image(png, False)
    t.extension = 'CLIP'
    nt.links.new(t.outputs["Color"], p.inputs["Base Color"])
    nt.links.new(p.outputs["BSDF"], out.inputs["Surface"])
    p.inputs["Roughness"].default_value = roughness
    p.inputs["Metallic"].default_value = metallic
    m.diffuse_color = (0.8, 0.8, 0.8, 1.0)
    return m


def gauge_print(name, span_deg, vmax, majors, minors, labels, red, green, unit, title, maker, px=1024):
    """Cadran de manomètre : graduations sur span_deg (centré en haut, sens horaire), valeurs 0..vmax, zones rouge et
    verte (listes de (v0, v1)), unité, titre, marque. Rend le PNG."""
    p = Print(name, 2.0, 2.0, px / 2.0, (0.93, 0.93, 0.91))
    cx = cy = 1.0
    ang = lambda v: math.radians(90.0 + span_deg / 2 - span_deg * v / vmax)
    p.arc(cx, cy, 0.965, 1.0, 0, 2 * math.pi, (0.18, 0.18, 0.18), 96)
    for v0, v1 in red:
        p.arc(cx, cy, 0.70, 0.80, ang(v1), ang(v0), (0.80, 0.08, 0.06))
    for v0, v1 in green:
        p.arc(cx, cy, 0.70, 0.80, ang(v1), ang(v0), (0.10, 0.62, 0.22))
    for k in range(minors + 1):
        v = vmax * k / minors
        a = ang(v)
        major = any(abs(v - mv) < 1e-6 for mv in majors)
        r0 = 0.74 if major else 0.81
        p.line(cx + r0 * math.cos(a), cy + r0 * math.sin(a), cx + 0.9 * math.cos(a), cy + 0.9 * math.sin(a),
               0.022 if major else 0.01, (0.05, 0.05, 0.05))
    for v, s in labels:
        a = ang(v)
        p.text(s, cx + 0.58 * math.cos(a), cy + 0.58 * math.sin(a), 0.13, (0.05, 0.05, 0.05), bold=True)
    p.text(unit, cx, cy - 0.32, 0.14, (0.05, 0.05, 0.05), bold=True)
    p.text(title, cx, cy + 0.34, 0.085, (0.15, 0.15, 0.15))
    p.text(maker, cx, cy - 0.55, 0.065, (0.35, 0.35, 0.35))
    return p.render()


def placard_print(name, text, w, h, size, px=1024, color=(0.92, 0.92, 0.9), back=(0.04, 0.04, 0.045), arrow=None):
    """Plaque gravée (aluminium anodisé noir, texte blanc), proportions w × h ; flèche facultative ('right', 'down')."""
    p = Print(name, w, h, px / w, back)
    p.rect(0.02 * h, 0.02 * h, w - 0.02 * h, h - 0.02 * h, (0.075, 0.075, 0.08))
    tx = w / 2 if arrow is None else w * 0.42
    p.text(text, tx, h / 2, size, color, bold=True)
    if arrow == 'right':
        x0 = w * 0.78
        p.poly([(x0, h * 0.3), (x0 + h * 0.35, h * 0.5), (x0, h * 0.7)], color)
    elif arrow == 'down':
        x0 = w * 0.84
        p.poly([(x0 - h * 0.2, h * 0.68), (x0 + h * 0.2, h * 0.68), (x0, h * 0.28)], color)
    return p.render()


def extinguisher_label_print(name, px=1600):
    """Étiquette d'extincteur à poudre (portrait, 0,124 × 0,18 m) : bandeau rouge, désignation, pictogrammes des
    classes de feu, mode d'emploi en quatre étapes, mentions légales, code-barres."""
    W, H = 0.69, 1.0
    p = Print(name, W, H, px / H, (0.97, 0.97, 0.95))
    red, black, grey = (0.78, 0.06, 0.05), (0.05, 0.05, 0.05), (0.45, 0.45, 0.45)
    p.rect(0, 0.80, W, 1.0, red)
    p.text("FIRE", W / 2, 0.93, 0.085, (1, 1, 1), bold=True)
    p.text("EXTINGUISHER", W / 2, 0.85, 0.07, (1, 1, 1), bold=True)
    p.text("ABC DRY POWDER  6 kg", W / 2, 0.755, 0.042, black, bold=True)
    p.line(0.04, 0.725, W - 0.04, 0.725, 0.004, black)
    for k, (letter, icon) in enumerate((("A", "bois"), ("B", "liquide"), ("C", "gaz"))):
        x = 0.12 + k * 0.225
        p.rect(x - 0.085, 0.56, x + 0.085, 0.70, black)
        p.rect(x - 0.078, 0.567, x + 0.078, 0.693, (1, 1, 1))
        p.text(letter, x - 0.045, 0.665, 0.045, black, bold=True)
        if icon == "bois":
            for j in range(3):
                p.rect(x - 0.03 + j * 0.022, 0.585, x - 0.016 + j * 0.022, 0.64, (0.45, 0.28, 0.12))
            p.poly([(x - 0.035, 0.635), (x + 0.03, 0.635), (x, 0.672)], (0.9, 0.35, 0.05))
        elif icon == "liquide":
            p.poly([(x + 0.01, 0.675), (x - 0.025, 0.615), (x + 0.045, 0.615)], (0.9, 0.35, 0.05))
            p.disk(x + 0.01, 0.605, 0.035, (0.9, 0.35, 0.05), 32)
        else:
            p.rect(x - 0.01, 0.58, x + 0.035, 0.63, grey)
            p.poly([(x - 0.005, 0.63), (x + 0.03, 0.63), (x + 0.0125, 0.678)], (0.9, 0.35, 0.05))
    steps = ("1  PULL THE PIN", "2  AIM AT THE BASE OF THE FIRE", "3  SQUEEZE THE LEVER", "4  SWEEP SIDE TO SIDE")
    for k, s in enumerate(steps):
        p.text(s, 0.05, 0.505 - k * 0.055, 0.031, black, align='LEFT', bold=(k % 2 == 0))
    for k in range(6):
        p.rect(0.05, 0.255 - k * 0.025, 0.05 + (0.58 if k % 3 else 0.42), 0.262 - k * 0.025, grey)
    p.text("-20 °C / +60 °C   ISS-PFE-06   CO2 FREE", W / 2, 0.075, 0.022, black)
    x = 0.12
    import random as _r
    rr = _r.Random(6)
    while x < 0.57:
        w = rr.choice((0.003, 0.005, 0.008))
        p.rect(x, 0.015, x + w, 0.05, black)
        x += w + rr.choice((0.003, 0.004, 0.006))
    return p.render()


# ------------------------------------------------------------------------------------------------ matériaux
def _plain(name, color, metallic, roughness):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    if p is None:
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        p = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(p.outputs["BSDF"], out.inputs["Surface"])
    for link in list(nt.links):
        if link.to_node == p and link.to_socket.name in ("Base Color", "Metallic", "Roughness"):
            nt.links.remove(link)
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color, 1.0)
    return m


def pbr_materials():
    """Matériaux réalistes de la valve et des extincteurs (clés pour les Builder des scripts)."""
    mats = {
        # Peintures 2K : usure modérée, métallicité faible et uniforme (le métal nu des écaillures, très
        # réfléchissant, faisait des traînées noires sous l'éclairage intérieur).
        "valve_orange": painted_metal_2k("Int_Valve_Orange", "PaintedMetal001", (0.80, 0.20, 0.0), keep=0.12, chips=0.0,
                                         normal_strength=0.6),
        "valve_jaune": painted_metal_2k("Int_Valve_Cadre", "PaintedMetal001", (0.85, 0.62, 0.02), keep=0.12, chips=0.0,
                                        normal_strength=0.6),
        # Extincteur : laque rouge brillante, quelques écaillures discrètes.
        "peinture_rouge": painted_metal_2k("Int_Extincteur", "PaintedMetal004", (0.62, 0.025, 0.015), keep=0.1,
                                           chips=0.12, metal=0.1, roughness_scale=0.55, normal_strength=0.35),
        # Acier satiné 2K (poli d'origine : il ne reflétait que du noir).
        "acier": pbr_material("Int_Acier_Poli", "Metal012", None, 0.7, 0.75, 2.4,
                              compact_map("Metal012", "NormalGL", "2K", "Metal012_2K_Normal"),
                              compact_map("Metal012", "Roughness", "2K", "Metal012_1K_Roughness", size=1024),
                              res="2K"),
        "chrome": _plain("Int_Chrome_Brillant", (0.86, 0.87, 0.88), 1.0, 0.12),
        "laiton": _plain("Int_Laiton_Brut", (0.78, 0.58, 0.28), 1.0, 0.32),
        "caoutchouc": _plain("Int_Caoutchouc_Noir", (0.015, 0.015, 0.016), 0.0, 0.82),
        "plastique_noir": _plain("Int_Plastique_Noir", (0.02, 0.02, 0.022), 0.0, 0.45),
        "anodise_noir": _plain("Int_Anodise_Noir", (0.03, 0.03, 0.034), 0.6, 0.38),
        "etiquette": bpy.data.materials["Int_Etiquette"],
        "encre": bpy.data.materials["Int_Encre"],
        "scelle": _plain("Int_Scelle_Jaune", (0.9, 0.7, 0.05), 0.0, 0.4),
        "vitrage": bpy.data.materials["Vitrage"],
    }
    # Impressions (textures dessinées) : cadrans, plaques gravées, étiquette.
    mats["cadran_valve"] = printed_material("Int_Cadran_Valve", gauge_print(
        "Cadran_Valve", 270.0, 1.2, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2], 24,
        [(0.0, "0"), (0.2, "0.2"), (0.4, "0.4"), (0.6, "0.6"), (0.8, "0.8"), (1.0, "1.0"), (1.2, "1.2")],
        [(0.0, 0.15)], [(0.95, 1.05)], "bar", "AIRLOCK PRESSURE", "EQV-3  ABS"), 0.35)
    mats["cadran_extincteur"] = printed_material("Int_Cadran_Extincteur", gauge_print(
        "Cadran_Extincteur", 120.0, 1.0, [0.0, 0.5, 1.0], 10, [], [(0.0, 0.35), (0.65, 1.0)], [(0.35, 0.65)],
        "", "", "", 512), 0.3)
    for key, text, w, size, arrow in (("plaque_titre", "AIRLOCK EQUALIZATION VALVE", 6.0, 0.42, None),
                                      ("plaque_fermee", "CLOSED", 2.4, 0.45, 'right'),
                                      ("plaque_vent", "VENT", 2.4, 0.45, 'down'),
                                      ("plaque_press", "PRESS", 2.0, 0.5, None),
                                      ("plaque_vac", "VAC", 2.0, 0.5, None)):
        mats[key] = printed_material("Int_" + key.capitalize(), placard_print(key.capitalize(), text, w, 1.0, size),
                                     0.35, 0.5)
    mats["etiquette_extincteur"] = printed_material("Int_Etiquette_Extincteur",
                                                    extinguisher_label_print("Etiquette_Extincteur"), 0.4)
    return mats


# ------------------------------------------------------------------------------------------------ pièces imprimées
def uv_quad(w, h, t=0.0012):
    """Plaque mince (w × h, épaisseur t) centrée, face avant +Z avec UV 0–1 (u vers +X, v vers +Y)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    corners = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    front = [bm.verts.new((x, y, t / 2)) for x, y in corners]
    back = [bm.verts.new((x, y, -t / 2)) for x, y in corners]
    f = bm.faces.new(front)
    for loop, (x, y) in zip(f.loops, corners):
        loop[uv].uv = (x / w + 0.5, y / h + 0.5)
    bm.faces.new(list(reversed(back)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((front[i], back[i], back[j], front[j]))
    for face in bm.faces:
        if face is not f:
            for loop in face.loops:
                loop[uv].uv = (0.02, 0.02)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def uv_disk(r, t=0.001, seg=64):
    """Disque mince d'axe Z (rayon r), face +Z à UV planaire 0–1 (u vers +X, v vers +Y)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    top = [bm.verts.new((r * math.cos(2 * math.pi * k / seg), r * math.sin(2 * math.pi * k / seg), t / 2)) for k in range(seg)]
    bot = [bm.verts.new((v.co.x, v.co.y, -t / 2)) for v in top]
    f = bm.faces.new(top)
    for loop in f.loops:
        loop[uv].uv = (loop.vert.co.x / (2 * r) + 0.5, loop.vert.co.y / (2 * r) + 0.5)
    bm.faces.new(list(reversed(bot)))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    for face in bm.faces:
        if face is not f:
            for loop in face.loops:
                loop[uv].uv = (0.5, 0.98)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _label_band(r, a0, a1, z0, z1, t, seg=48):
    """Étiquette enroulée sur un cylindre d'axe Z (rayon r → r + t), angles a0..a1, hauteur z0..z1 ; face extérieure à
    UV 0–1 (u de a0 vers a1 : le sens trigonométrique, lu de gauche à droite vue de l'extérieur ; v vers le haut)."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    outer, inner = [], []
    for k in range(seg + 1):
        a = a0 + (a1 - a0) * k / seg
        c, s = math.cos(a), math.sin(a)
        outer.append((bm.verts.new(((r + t) * c, (r + t) * s, z0)), bm.verts.new(((r + t) * c, (r + t) * s, z1)), k / seg))
        inner.append((bm.verts.new((r * c, r * s, z0)), bm.verts.new((r * c, r * s, z1))))
    for k in range(seg):
        (b0, t0, u0), (b1, t1, u1) = outer[k], outer[k + 1]
        f = bm.faces.new((b0, b1, t1, t0))
        for loop, uvv in zip(f.loops, ((u0, 0), (u1, 0), (u1, 1), (u0, 1))):
            loop[uv].uv = uvv
        ib0, it0 = inner[k]
        ib1, it1 = inner[k + 1]
        g = bm.faces.new((ib1, ib0, it0, it1))
        bm.faces.new((b0, t0, it0, ib0)) if k == 0 else None
        if k == seg - 1:
            bm.faces.new((t1, b1, ib1, it1))
        for loop in g.loops:
            loop[uv].uv = (0.5, 0.5)
    for face in bm.faces:
        for loop in face.loops:
            if loop[uv].uv.length == 0:
                loop[uv].uv = (0.5, 0.5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def _arc_band(r, a0, a1, z0, z1, t, seg=24):
    """Bande courbe plaquée sur un cylindre d'axe Z (rayon r → r + t), angles a0..a1 (0 = +X), hauteur z0..z1."""
    bm = bmesh.new()
    rows = []
    for k in range(seg + 1):
        a = a0 + (a1 - a0) * k / seg
        c, s = math.cos(a), math.sin(a)
        rows.append([bm.verts.new((rr * c, rr * s, z)) for rr, z in ((r, z0), (r + t, z0), (r + t, z1), (r, z1))])
    for a, b in zip(rows, rows[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# ------------------------------------------------------------------------------------------------ extincteur
def build_extinguisher(b, M, s=1.0):
    """Extincteur à poudre réaliste (6 kg) dans le repère M : pied en z = 0, axe Z, dos (support mural) vers +Y,
    face (étiquette, manomètre) vers −Y ; s : échelle. Corps embouti en acier laqué rouge (soudure d'épaulement,
    fond serti), pied en caoutchouc, col fileté en laiton, tête de robinet chromée (bouchon moleté), levier de
    percussion et poignée de portage à gaine caoutchouc, goupille et scellé plastique à plaquette, manomètre imprimé
    (zone verte), flexible à bagues serties et lance à cornet clipsés sur le côté, étiquette imprimée enroulée
    (désignation, classes de feu, mode d'emploi, code-barres), colliers et platine murale vissée."""
    S = Matrix.Scale(s, 4)
    T = lambda x, y, z: M @ S @ Matrix.Translation((x, y, z))
    R = 0.065
    body = [(0.0, 0.004), (0.045, 0.004), (0.058, 0.012), (0.064, 0.03), (R, 0.05), (R, 0.36), (0.063, 0.38),
            (0.056, 0.398), (0.044, 0.41), (0.03, 0.416), (0.022, 0.418), (0.0, 0.419)]
    b.add(revolve(body, 72), "peinture_rouge", M @ S)
    b.add(torus(0.0628, 0.0014, 72, 6), "peinture_rouge", T(0, 0, 0.383))          # soudure d'épaulement
    b.add(torus(0.0605, 0.0018, 72, 6), "peinture_rouge", T(0, 0, 0.022))          # sertissage du fond
    b.add(revolve([(0.0, 0.0), (0.06, 0.0), (0.066, 0.006), (0.066, 0.026), (0.061, 0.03), (0.0, 0.03)], 72),
          "caoutchouc", M @ S)
    front = -math.pi / 2
    b.add(_label_band(R + 0.0002, front - 0.95, front + 0.95, 0.13, 0.31, 0.0008), "etiquette_extincteur", M @ S)
    # Col fileté (laiton), tête de robinet chromée, bouchon moleté.
    b.add(cylinder(0.024, 0.018, 48), "laiton", T(0, 0, 0.427))
    for k in range(4):
        b.add(torus(0.0245, 0.0015, 48, 6), "laiton", T(0, 0, 0.42 + 0.004 * k))
    b.add(soft_box((0.022, 0.026, 0.024), 0.006, 0.006), "chrome", T(0, 0, 0.458))
    b.add(cylinder(0.014, 0.012, 24), "chrome", T(0, 0, 0.486))
    for k in range(16):
        a = 2 * math.pi * k / 16
        b.add(soft_box((0.0012, 0.0012, 0.006), 0.0004, 0.004), "chrome", T(0.0145 * math.cos(a), 0.0145 * math.sin(a), 0.486))
    b.add(cylinder(0.012, 0.03, 24), "chrome", T(0, -0.035, 0.455) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cylinder(0.009, 0.012, 6), "laiton", T(0, -0.052, 0.455) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    # Poignée de portage (dessous, gaine caoutchouc) et levier de percussion (dessus), tôle emboutie.
    b.add(soft_box((0.013, 0.065, 0.004), 0.002, 0.004), "acier", T(0, 0.045, 0.468) @ Matrix.Rotation(-0.12, 4, 'X'))
    b.add(soft_box((0.016, 0.03, 0.008), 0.006, 0.004), "caoutchouc", T(0, 0.085, 0.463) @ Matrix.Rotation(-0.12, 4, 'X'))
    b.add(soft_box((0.013, 0.07, 0.004), 0.002, 0.004), "plastique_noir", T(0, 0.05, 0.492) @ Matrix.Rotation(0.32, 4, 'X'))
    b.add(cylinder(0.005, 0.034, 12), "acier", T(0, 0.0, 0.478) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    # Goupille (anneau), scellé plastique et sa plaquette.
    b.add(cylinder(0.0025, 0.05, 8), "acier", T(0.0, 0.012, 0.479) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    b.add(torus(0.012, 0.0022, 24, 6), "acier", T(0.037, 0.012, 0.479) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    b.add(tube([(0.03, 0.012, 0.479), (0.034, 0.03, 0.47), (0.02, 0.04, 0.476)], 0.0016, 6), "scelle", M @ S)
    b.add(soft_box((0.008, 0.001, 0.006), 0.0008, 0.004), "scelle", T(0.018, 0.043, 0.468))
    # Manomètre (face avant) : boîtier chromé serti, cadran imprimé, verre, aiguille.
    g = T(0.024, -0.012, 0.455) @ Matrix.Rotation(-math.pi / 2, 4, 'X') @ Matrix.Rotation(0.6, 4, 'Y')
    b.add(cylinder(0.016, 0.01, 32), "chrome", g)
    b.add(torus(0.0155, 0.0015, 32, 6), "chrome", g @ Matrix.Translation((0, 0, 0.005)))
    b.add(uv_disk(0.0135, 0.0008, 32), "cadran_extincteur", g @ Matrix.Translation((0, 0, 0.0055)))
    b.add(soft_box((0.0006, 0.0055, 0.0004), 0.0002, 0.004), "encre", g @ Matrix.Translation((0.0, 0.0045, 0.0066)))
    b.add(cylinder(0.0135, 0.0006, 32), "vitrage", g @ Matrix.Translation((0, 0, 0.0075)))
    # Flexible : du robinet, contourne le corps par le côté (−X, l'étiquette reste dégagée) ; bagues serties ; lance à
    # cornet clipsée en bas.
    hose = [(0.0, -0.058, 0.455), (-0.02, -0.07, 0.43), (-0.06, -0.05, 0.39), (-0.078, -0.005, 0.33),
            (-0.078, 0.0, 0.2), (-0.077, 0.0, 0.13)]
    b.add(tube(hose, 0.0075, 14), "caoutchouc", M @ S)
    b.add(cylinder(0.0095, 0.02, 16), "chrome", T(-0.004, -0.062, 0.452) @ Matrix.Rotation(0.6, 4, 'X'))
    b.add(cylinder(0.0095, 0.018, 16), "chrome", T(-0.077, 0.0, 0.128))
    b.add(cylinder(0.011, 0.05, 20, 0.015), "plastique_noir", T(-0.077, 0.0, 0.095))
    b.add(cylinder(0.015, 0.025, 20, 0.019), "plastique_noir", T(-0.077, 0.0, 0.058))
    b.add(soft_box((0.006, 0.01, 0.006), 0.002, 0.004), "plastique_noir", T(-0.069, 0.0, 0.11))
    # Colliers et platine murale vissée.
    for z in (0.12, 0.30):
        b.add(_arc_band(R, -math.pi / 2 + 0.95, 1.5 * math.pi - 0.95, z - 0.012, z + 0.012, 0.003, 48), "acier", M @ S)
    b.add(soft_box((0.04, 0.008, 0.13), 0.004, 0.01), "acier", T(0, R + 0.012, 0.21))
    b.add(soft_box((0.032, 0.025, 0.012), 0.004, 0.01), "acier", T(0, R + 0.02, 0.028))
    for z in (0.11, 0.31):
        b.add(cylinder(0.005, 0.004, 12), "chrome", T(0, R + 0.0205, z) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
