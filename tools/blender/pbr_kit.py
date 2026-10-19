# Outil hors-jeu : matériaux réalistes texturés (photos PBR ambientCG, licence CC0) et extincteur détaillé, partagés
# par build_airlock.py (valve et extincteur du sas) et build_arrimage_extinguisher.py. Chargé dans le Blender ouvert
# par exec(open(".../pbr_kit.py").read()) après props_kit.py (soft_box, cylinder, revolve, torus, tube).
# Textures (1K, JPG) dans E:\Blender\textures\<id>\ (téléchargées depuis https://ambientcg.com, CC0) :
#   PaintedMetal001 (métal peint rayé, jaune : recoloré pour la valve), PaintedMetal004 (métal peint rouge écaillé :
#   extincteur), Metal012 (acier poli rayé : pièces métalliques). Couleurs recalculées dans E:\Blender\textures\Generated.
# Coordonnées de texture : celles des maillages (en mètres) ; une répétition par mètre.
import bpy, bmesh, math, os
from mathutils import Matrix, Vector

TEXTURES = r"E:\Blender\textures"
GENERATED = os.path.join(TEXTURES, "Generated")


def _image(path, non_color):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None or os.path.normcase(bpy.path.abspath(img.filepath)) != os.path.normcase(path):
        img = bpy.data.images.load(path)
    img.reload()
    img.colorspace_settings.name = 'Non-Color' if non_color else 'sRGB'
    return img


def repainted_color(asset, rgb, out_name, keep=0.35):
    """Couleur d'une peinture rayée recalculée dans la teinte rgb (linéaire) : les variations de luminance de la photo
    sont gardées à keep près (rayures, salissures), le métal nu (carte Metalness) reste gris acier. JPEG enregistré
    dans GENERATED (exporté tel quel dans le glTF)."""
    import numpy as np
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    color = bpy.data.images.load(os.path.join(TEXTURES, asset, asset + "_1K-JPG_Color.jpg"))
    metal = bpy.data.images.load(os.path.join(TEXTURES, asset, asset + "_1K-JPG_Metalness.jpg"))
    w, h = color.size
    c = np.array(color.pixels[:], dtype=np.float32).reshape(h, w, 4)
    m = np.array(metal.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., 0:1]
    lum = (0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2])[..., None]
    rel = np.clip(1.0 + keep * (lum - lum.mean()) / max(float(lum.std()), 1e-4), 0.45, 1.35)
    paint = np.array(rgb, dtype=np.float32)[None, None, :] * rel
    steel = np.clip(lum * 0.9 + 0.25, 0.0, 1.0) * np.array((0.58, 0.59, 0.61), dtype=np.float32)[None, None, :]
    rgb_out = paint * (1.0 - m) + steel * m
    # Les pixels Blender sont linéaires ; l'image enregistrée en sRGB (JPEG) : conversion.
    srgb = np.where(rgb_out <= 0.0031308, rgb_out * 12.92, 1.055 * np.power(np.clip(rgb_out, 0, None), 1 / 2.4) - 0.055)
    pix = np.concatenate([np.clip(srgb, 0, 1), np.ones((h, w, 1), dtype=np.float32)], axis=2)
    img = bpy.data.images.get(out_name) or bpy.data.images.new(out_name, w, h)
    img.scale(w, h)
    img.colorspace_settings.name = 'sRGB'
    img.pixels[:] = pix.ravel()
    img.filepath_raw = out
    img.file_format = 'JPEG'
    sc = bpy.context.scene
    quality = sc.render.image_settings.quality
    sc.render.image_settings.quality = 92
    img.save()
    sc.render.image_settings.quality = quality
    bpy.data.images.remove(img)
    bpy.data.images.remove(color)
    bpy.data.images.remove(metal)
    return out


def _save_jpeg(img, out, quality):
    img.filepath_raw = out
    img.file_format = 'JPEG'
    sc = bpy.context.scene
    old = sc.render.image_settings.quality
    sc.render.image_settings.quality = quality
    img.save()
    sc.render.image_settings.quality = old


def recolored_fabric(asset, rgb, out_name, keep=0.6, res="2K"):
    """Couleur d'un tissu (photo ambientCG) recalculée dans la teinte rgb (linéaire) : le relief du tissage (variations
    de luminance) est gardé à keep près. JPEG (qualité 92) dans GENERATED."""
    import numpy as np
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    src = bpy.data.images.load(os.path.join(TEXTURES, asset, "%s_%s-JPG_Color.jpg" % (asset, res)))
    w, h = src.size
    c = np.array(src.pixels[:], dtype=np.float32).reshape(h, w, 4)
    lum = (0.2126 * c[..., 0] + 0.7152 * c[..., 1] + 0.0722 * c[..., 2])[..., None]
    rel = np.clip(1.0 + keep * (lum - lum.mean()) / max(float(lum.mean()), 1e-4), 0.3, 1.6)
    lin = np.clip(np.array(rgb, dtype=np.float32)[None, None, :] * rel, 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    img = bpy.data.images.new(out_name, w, h)
    img.colorspace_settings.name = 'sRGB'
    img.pixels[:] = np.concatenate([srgb, np.ones((h, w, 1), dtype=np.float32)], axis=2).ravel()
    _save_jpeg(img, out, 92)
    bpy.data.images.remove(img)
    bpy.data.images.remove(src)
    return out


def compact_map(asset, kind, res, out_name, size=None, quality=85):
    """Carte (NormalGL, Roughness…) réenregistrée en JPEG plus compressé, redimensionnée à size (côté) si donné : les
    cartes d'origine pèsent jusqu'à 10 Mo en 2K."""
    os.makedirs(GENERATED, exist_ok=True)
    out = os.path.join(GENERATED, out_name + ".jpg")
    img = bpy.data.images.load(os.path.join(TEXTURES, asset, "%s_%s-JPG_%s.jpg" % (asset, res, kind)))
    img.colorspace_settings.name = 'Non-Color'
    _ = img.pixels[0]  # charge les données (sinon « does not have any image data » à l'enregistrement)
    if size:
        img.scale(size, size)
    _save_jpeg(img, out, quality)
    bpy.data.images.remove(img)
    return out


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


def pbr_material(name, asset, color_path=None, normal_strength=1.0, metal_override=None, roughness_scale=1.0,
                 normal_path=None, rough_path=None, uv_scale=1.0):
    """Matériau Principled à textures : couleur (color_path ou celle de l'asset), rugosité, métallicité, normales
    (OpenGL), uv_scale répétitions par mètre. Recréé à chaque appel (nœuds remplacés)."""
    base = os.path.join(TEXTURES, asset, asset + "_1K-JPG_")
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
    col = tex(color_path or base + "Color.jpg", False, 300)
    nt.links.new(col.outputs["Color"], p.inputs["Base Color"])
    rough = tex(rough_path or base + "Roughness.jpg", True, 0)
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
        metal = tex(base + "Metalness.jpg", True, -300)
        nt.links.new(metal.outputs["Color"], p.inputs["Metallic"])
    else:
        p.inputs["Metallic"].default_value = metal_override
    normal = tex(normal_path or base + "NormalGL.jpg", True, -600)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.location = (-150, -600)
    nmap.inputs["Strength"].default_value = normal_strength
    nt.links.new(normal.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], p.inputs["Normal"])
    m.diffuse_color = (0.6, 0.6, 0.6, 1.0)
    return m


def pbr_materials():
    """Matériaux réalistes de la valve et des extincteurs (clés pour les Builder des scripts)."""
    def plain(name, color, metallic, roughness):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = (*color, 1.0)
        p.inputs["Metallic"].default_value = metallic
        p.inputs["Roughness"].default_value = roughness
        m.diffuse_color = (*color, 1.0)
        return m
    # Peintures : usure modérée (variations de teinte atténuées) ; métallicité faible et uniforme (le métal nu des
    # écaillures, très réfléchissant, faisait des traînées noires sous l'éclairage intérieur).
    orange = repainted_color("PaintedMetal001", (0.80, 0.20, 0.0), "Valve_Orange_Color", keep=0.2)
    yellow = repainted_color("PaintedMetal001", (0.85, 0.62, 0.02), "Valve_Jaune_Color", keep=0.2)
    return {
        "valve_orange": pbr_material("Int_Valve_Orange", "PaintedMetal001", orange, 0.8, metal_override=0.15),
        "valve_jaune": pbr_material("Int_Valve_Cadre", "PaintedMetal001", yellow, 0.8, metal_override=0.15),
        # Acier satiné (poli d'origine : il ne reflétait que du noir).
        "acier": pbr_material("Int_Acier_Poli", "Metal012", roughness_scale=2.4, metal_override=0.75),
        "peinture_rouge": pbr_material("Int_Extincteur", "PaintedMetal004", None, 0.7, metal_override=0.15),
        "laiton": plain("Int_Laiton_Brut", (0.78, 0.58, 0.28), 1.0, 0.32),
        "caoutchouc": plain("Int_Caoutchouc_Noir", (0.015, 0.015, 0.016), 0.0, 0.82),
        "plastique_noir": plain("Int_Plastique_Noir", (0.02, 0.02, 0.022), 0.0, 0.45),
        "etiquette": bpy.data.materials["Int_Etiquette"],
        "encre": bpy.data.materials["Int_Encre"],
        "etiquette_rouge": plain("Int_Etiquette_Rouge", (0.62, 0.03, 0.02), 0.0, 0.55),
        "scelle": plain("Int_Scelle_Jaune", (0.9, 0.7, 0.05), 0.0, 0.4),
        "cadran": bpy.data.materials.get("Int_Cadran") or plain("Int_Cadran", (0.9, 0.9, 0.88), 0.0, 0.4),
        "vert_marque": bpy.data.materials.get("Int_Marque_Verte") or plain("Int_Marque_Verte", (0.05, 0.5, 0.12), 0.0, 0.5),
        "rouge_marque": plain("Int_Marque_Rouge", (0.7, 0.04, 0.03), 0.0, 0.5),
    }


# ------------------------------------------------------------------------------------------------ extincteur
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


def build_extinguisher(b, M, s=1.0):
    """Extincteur à poudre réaliste (6 kg) dans le repère M : pied en z = 0, axe Z, dos (support mural) vers +Y,
    face (étiquette, manomètre) vers −Y ; s : échelle. Corps embouti en acier peint (texture écaillée), col fileté en
    laiton, tête de robinet chromée avec levier de percussion et poignée de portage, goupille de sécurité et scellé
    jaune, manomètre (zone verte), flexible et lance clipsés, pied en caoutchouc, étiquette (bandeau rouge, consignes,
    pictogrammes), collier et platine murale."""
    S = Matrix.Scale(s, 4)
    T = lambda x, y, z: M @ S @ Matrix.Translation((x, y, z))
    R = 0.065
    # Corps (fond bombé, épaulement arrondi) et pied.
    body = [(0.0, 0.004), (0.045, 0.004), (0.058, 0.012), (0.064, 0.03), (R, 0.05), (R, 0.36), (0.062, 0.385),
            (0.052, 0.403), (0.036, 0.414), (0.022, 0.418), (0.0, 0.419)]
    b.add(revolve(body, 48), "peinture_rouge", M @ S)
    b.add(revolve([(0.0, 0.0), (0.06, 0.0), (0.066, 0.006), (0.066, 0.026), (0.061, 0.03), (0.0, 0.03)], 48), "caoutchouc", M @ S)
    # Étiquette (face avant, −Y) : fond blanc, bandeau rouge, lignes de consignes, pictogrammes des classes de feu.
    front = -math.pi / 2
    b.add(_arc_band(R, front - 0.95, front + 0.95, 0.13, 0.31, 0.0012, 32), "etiquette", M @ S)
    b.add(_arc_band(R + 0.0012, front - 0.95, front + 0.95, 0.27, 0.305, 0.0006, 32), "etiquette_rouge", M @ S)
    for k, (w, z) in enumerate(((0.75, 0.25), (0.6, 0.238), (0.7, 0.226), (0.45, 0.214), (0.65, 0.2))):
        b.add(_arc_band(R + 0.0012, front - w * 0.55, front + w * 0.55, z, z + 0.004, 0.0004, 12), "encre", M @ S)
    for k in range(3):
        a = front - 0.45 + 0.45 * k
        b.add(_arc_band(R + 0.0012, a - 0.17, a + 0.17, 0.145, 0.185, 0.0005, 8), "encre" if k != 1 else "etiquette_rouge", M @ S)
        b.add(_arc_band(R + 0.0018, a - 0.12, a + 0.12, 0.15, 0.18, 0.0004, 8), "etiquette", M @ S)
    # Col fileté (laiton) et tête de robinet chromée.
    b.add(cylinder(0.024, 0.018, 32), "laiton", T(0, 0, 0.427))
    for k in range(4):
        b.add(torus(0.0245, 0.0015, 32, 6), "laiton", T(0, 0, 0.42 + 0.004 * k))
    b.add(soft_box((0.022, 0.026, 0.024), 0.006, 0.006), "acier", T(0, 0, 0.458))
    b.add(cylinder(0.012, 0.03, 20), "acier", T(0, -0.035, 0.455) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    # Poignée de portage (fixe, dessous) et levier de percussion (dessus), tôle emboutie noire.
    b.add(soft_box((0.013, 0.065, 0.004), 0.002, 0.004), "plastique_noir",
          T(0, 0.045, 0.468) @ Matrix.Rotation(-0.12, 4, 'X'))
    b.add(soft_box((0.013, 0.07, 0.004), 0.002, 0.004), "plastique_noir",
          T(0, 0.05, 0.492) @ Matrix.Rotation(0.32, 4, 'X'))
    b.add(cylinder(0.005, 0.034, 12), "acier", T(0, 0.0, 0.478) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    # Goupille de sécurité (anneau) et scellé jaune.
    b.add(cylinder(0.0025, 0.05, 8), "acier", T(0.0, 0.012, 0.479) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    b.add(torus(0.012, 0.0022, 20, 6), "acier", T(0.037, 0.012, 0.479) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    b.add(tube([(0.03, 0.012, 0.479), (0.034, 0.03, 0.47), (0.02, 0.04, 0.476)], 0.0018, 6), "scelle", M @ S)
    # Manomètre (face avant) : boîtier chromé, cadran, zone verte, aiguille.
    g = T(0.024, -0.012, 0.455) @ Matrix.Rotation(-math.pi / 2, 4, 'X') @ Matrix.Rotation(0.6, 4, 'Y')
    b.add(cylinder(0.016, 0.01, 24), "acier", g)
    b.add(cylinder(0.0135, 0.001, 24), "cadran", g @ Matrix.Translation((0, 0, 0.0055)))
    for k in range(5):
        a = math.radians(50 + 20 * k)
        b.add(soft_box((0.0012, 0.0035, 0.0004), 0.0003, 0.002), "vert_marque" if 1 <= k <= 3 else "rouge_marque",
              g @ Matrix.Translation((0.009 * math.cos(a), 0.009 * math.sin(a), 0.0062)) @ Matrix.Rotation(a - math.pi / 2, 4, 'Z'))
    b.add(soft_box((0.0007, 0.0055, 0.0004), 0.0002, 0.002), "encre",
          g @ Matrix.Translation((0.0, 0.0045, 0.0066)))
    # Flexible : du robinet, contourne le corps par le côté (−X, l'étiquette reste dégagée), lance clipsée en bas.
    hose = [(0.0, -0.05, 0.455), (-0.02, -0.07, 0.43), (-0.06, -0.05, 0.39), (-0.078, -0.005, 0.33),
            (-0.078, 0.0, 0.2), (-0.077, 0.0, 0.12)]
    b.add(tube(hose, 0.0075, 12), "caoutchouc", M @ S)
    b.add(cylinder(0.011, 0.07, 16, 0.016), "plastique_noir", T(-0.077, 0.0, 0.085))
    b.add(torus(0.0105, 0.0025, 16, 6), "acier", T(-0.077, 0.0, 0.124))
    b.add(soft_box((0.006, 0.01, 0.006), 0.002, 0.004), "plastique_noir", T(-0.069, 0.0, 0.11))
    # Collier et platine murale (support à sangle).
    for z in (0.12, 0.30):
        b.add(_arc_band(R, -math.pi / 2 + 0.95, 1.5 * math.pi - 0.95, z - 0.012, z + 0.012, 0.003, 32), "acier", M @ S)
    b.add(soft_box((0.04, 0.008, 0.13), 0.004, 0.01), "acier", T(0, R + 0.012, 0.21))
    b.add(soft_box((0.032, 0.025, 0.012), 0.004, 0.01), "acier", T(0, R + 0.02, 0.028))
    for z in (0.11, 0.31):
        b.add(cylinder(0.005, 0.004, 12), "acier", T(0, R + 0.0205, z) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
