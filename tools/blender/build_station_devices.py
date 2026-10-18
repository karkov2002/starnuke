# Outil hors-jeu : modélise les ordinateurs portables et les écrans plats de la station (bras articulés, charnières,
# supports muraux compris), puis, à la demande, remplace les objets Interactif_Ordinateur_* et Interactif_Ecran_* de
# E:\Blender\nuke_station.blend (sauf Interactif_Ecran_Principal, l'écran du poste de pilotage, qui reste tel quel).
# Lancement dans le Blender ouvert (extension MCP de Blender Lab, port 9876) ; MODE choisit l'action :
#   & ./tools/blender_exec.ps1 -TimeoutS 600 -Code 'MODE = "preview"; exec(open(r"E:\Projects\starnuke\tools\blender\build_station_devices.py", encoding="utf-8").read())'
#   - "preview" : fichier vide uniquement ; construit un portable et les trois formats d'écran à l'origine, rend des
#     aperçus dans PREVIEW_DIR et enregistre E:\Blender\equipements_station.blend (contrôle avant intégration) ;
#   - "apply"   : nuke_station.blend ouvert ; remplace le maillage des objets visés en gardant leur nom, leurs
#     propriétés (extras glTF : type, id, materiau_ecran) et leur matériau d'écran Ecran_XX ; l'objet reçoit le repère
#     de l'appareil (transformation d'objet, maillage en coordonnées locales). Rejouable : le repère vient de TARGETS.
# Ne réexporte rien : l'export vers Godot (export_station.py) attend le feu vert de l'utilisateur.
#
# Repères locaux (mètres) :
# - portable : X vers la droite du clavier, Y vers la charnière (arrière), Z normale du clavier ; origine au centre
#   du dessous de la base. Le bras descend selon −Z jusqu'à la paroi (Z = −ARM_LENGTH).
# - écran : X vers la droite de l'image, Y vers la paroi (l'image regarde −Y), Z vers le haut de l'image ; origine
#   au centre de la dalle. Le support mural s'arrête sur la paroi (Y = WALL_GAP).
# Dalle d'écran : matériau Ecran_XX de l'objet, UV 0–1 (u vers la droite, (0, 0) en haut à gauche de l'image vue de
# face une fois dans glTF, qui retourne v), comme la tablette.
# Matériaux nouveaux préfixés « Int_ » (station.gd range les matériaux Int_ et Ecran_ à l'intérieur).
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

MODE = globals().get("MODE", "preview")
PREVIEW_DIR = globals().get("PREVIEW_DIR", r"E:\Blender\apercus_equipements")
PREVIEW_BLEND = r"E:\Blender\equipements_station.blend"
LEGEND_PNG = r"E:\Blender\textures\clavier_legendes.png"

# --- Portable : 14 pouces, dalle 16:10, dans l'esprit des ThinkPad noirs utilisés à bord de l'ISS. ---
PC_W, PC_D, PC_T = 0.330, 0.228, 0.0190      # base : largeur, profondeur, épaisseur
PC_CORNER = 0.009
LID_T = 0.0065
DISP_W, DISP_H = 0.3016, 0.1885              # zone active 14" 16:10
BEZEL_SIDE, BEZEL_TOP, BEZEL_BOTTOM = 0.0142, 0.0120, 0.0170
LID_H = DISP_H + BEZEL_TOP + BEZEL_BOTTOM
LID_OPEN_DEG = 105.0
HINGE_Y = PC_D / 2 - 0.0075                  # axe des charnières
HINGE_Z = PC_T - 0.0005
HINGE_R = 0.0068
KEY_U = 0.0187                               # pas des touches
KB_COLS = 15.0
KB_W = KB_COLS * KEY_U
KB_ROWS_H = [0.62, 1, 1, 1, 1, 1]            # rangée des fonctions moins haute
KB_D = sum(KB_ROWS_H) * KEY_U
KB_CY = 0.031                                # centre du clavier (Y)
KEY_COLOR = 0.03                             # teinte linéaire des touches (fond de la texture des légendes)
ARM_LENGTH = 0.36                            # dessous de la base -> paroi (montage d'origine)

# --- Écran plat : bordures fines, coque arrière bombée, fixation VESA, support mural inclinable. ---
SCR_BEZEL, SCR_CHIN = 0.0115, 0.0200
SCR_FRONT_T = 0.0150                         # épaisseur de la coque avant
SCR_BACK_T = 0.0200                          # bombé arrière
WALL_GAP = 0.055                             # dalle -> paroi (écrans d'origine : 5,5 cm)

# Cibles dans la station (coordonnées monde de nuke_station.blend, relevées sur les objets d'origine).
# Portables : origine (dessous de la base), normale du clavier n, direction de la charnière h.
LAPTOPS = {
    "Interactif_Ordinateur_01": ((13.5, 0.89, 0.0), (0, -1, 0), (0, 0, 1)),
    "Interactif_Ordinateur_02": ((14.7, 0.89, 0.0), (0, -1, 0), (0, 0, 1)),
    "Interactif_Ordinateur_03": ((8.4, 0.0, -0.89), (0, 0, 1), (0, -1, 0)),
    "Interactif_Ordinateur_04": ((9.4, 0.0, 0.89), (0, 0, -1), (0, -1, 0)),
}
# Écrans : centre de la dalle, normale n (vers l'observateur), haut de l'image u, taille de la dalle (l, h).
S2 = math.sqrt(0.5)
SCREENS = {
    "Interactif_Ecran_01": ((8.2, 1.195, 0.0), (0, -1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_02": ((9.4, 1.195, 0.0), (0, -1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_03": ((8.2, -1.195, 0.0), (0, 1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_04": ((9.4, -1.195, 0.0), (0, 1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_05": ((13.5, 0.0, 1.195), (0, 0, -1), (-1, 0, 0), (0.80, 0.50)),
    "Interactif_Ecran_06": ((14.7, 0.0, 1.195), (0, 0, -1), (-1, 0, 0), (0.80, 0.50)),
    "Interactif_Ecran_07": ((13.5, -1.195, 0.0), (0, 1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_08": ((14.7, -1.195, 0.0), (0, 1, 0), (0, 0, 1), (0.80, 0.50)),
    "Interactif_Ecran_13": ((9.0, 0.847, 0.847), (0, -S2, -S2), (0, -S2, S2), (1.00, 0.296)),
    "Interactif_Ecran_14": ((14.1, 0.845, -0.845), (0, -S2, S2), (0, S2, S2), (1.00, 0.296)),
    "Interactif_Ecran_16": ((16.015, -1.04, 0.05), (-1, 0, 0), (0, 0, 1), (0.30, 0.80)),
    "Interactif_Ecran_17": ((16.015, 1.04, 0.05), (-1, 0, 0), (0, 0, 1), (0.30, 0.80)),
}


# ------------------------------------------------------------------------------------------------ matériaux
def material(name, color, metallic, roughness, emission=None, strength=1.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    if emission:
        p.inputs["Emission Color"].default_value = (*emission, 1.0)
        p.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*color, 1.0)
    return m


def materials():
    return {
        "coque": material("Int_PC_Coque", (0.028, 0.028, 0.030), 0.0, 0.62),
        "touche": legend_material(),
        "noir": material("Int_PC_Noir", (0.006, 0.006, 0.007), 0.0, 0.42),
        "pave": material("Int_PC_Pave", (0.035, 0.035, 0.038), 0.0, 0.40),
        "rouge": material("Int_PC_Trackpoint", (0.42, 0.03, 0.03), 0.0, 0.85),
        "caoutchouc": material("Int_PC_Caoutchouc", (0.012, 0.012, 0.012), 0.0, 0.9),
        "port": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
        "inox": material("Int_PC_Inox", (0.62, 0.62, 0.63), 1.0, 0.28),
        "alu": material("Int_Bras_Alu", (0.55, 0.56, 0.58), 1.0, 0.38),
        "alu_noir": material("Int_Bras_Anodise", (0.045, 0.047, 0.05), 0.85, 0.42),
        "molette": material("Int_Bras_Molette", (0.02, 0.02, 0.022), 0.0, 0.55),
        "cable": material("Int_Cable", (0.015, 0.015, 0.016), 0.0, 0.6),
        "led": material("Int_PC_Led", (0.05, 0.6, 0.15), 0.0, 0.3, emission=(0.1, 1.0, 0.25), strength=4.0),
        "cadre": material("Int_Ecran_Cadre", (0.022, 0.022, 0.024), 0.0, 0.55),
        "dos": material("Int_Ecran_Dos", (0.05, 0.051, 0.054), 0.0, 0.5),
        "plaque": material("Int_Bras_Plaque", (0.30, 0.31, 0.33), 0.9, 0.45),
    }


def legend_material():
    """Touches noires, légendes gris clair (texture rendue par build_legend_texture)."""
    m = material("Int_PC_Touches", (KEY_COLOR, KEY_COLOR, KEY_COLOR * 1.06), 0.0, 0.48)
    if os.path.exists(LEGEND_PNG):
        nt = m.node_tree
        p = nt.nodes["Principled BSDF"]
        tex = nt.nodes.get("Legendes") or nt.nodes.new("ShaderNodeTexImage")
        tex.name = "Legendes"
        tex.location = (-400, 200)
        img = bpy.data.images.get("clavier_legendes.png") or bpy.data.images.load(LEGEND_PNG)
        img.reload()
        tex.image = img
        nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m


# ------------------------------------------------------------------------------------------------ géométrie
class Builder:
    """Accumule des pièces (bmesh séparés, biseautés puis placés) dans un seul maillage à matériaux multiples."""

    def __init__(self, mats):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []
        self.mats = mats

    def slot(self, key):
        m = self.mats[key] if isinstance(key, str) and key in self.mats else key
        if m not in self.slots:
            self.slots.append(m)
        return self.slots.index(m)

    def add(self, part, key, matrix=Matrix(), uv_fn=None):
        """Ajoute le bmesh `part` (libéré ensuite) avec le matériau `key`, transformé par `matrix` ; `uv_fn(co, face)`
        reçoit les coordonnées de la pièce avant transformation."""
        part.normal_update()
        uvs = [[uv_fn(l.vert.co, f) if uv_fn else (0.0, 0.0) for l in f.loops] for f in part.faces]
        bmesh.ops.transform(part, matrix=matrix, verts=part.verts)
        idx = self.slot(key)
        # Copie directe (BMesh.from_mesh sur un bmesh non vide remet à zéro les attributs des pièces précédentes).
        vmap = {v: self.bm.verts.new(v.co) for v in part.verts}
        new_faces = []
        for f, face_uvs in zip(part.faces, uvs):
            try:
                g = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:  # face en double (pièce dégénérée) : ignorée
                continue
            g.material_index = idx
            g.smooth = True
            for loop, uv in zip(g.loops, face_uvs):
                loop[self.uv].uv = uv
            new_faces.append(g)
        part.free()
        return new_faces

    def finish(self, mesh, sharp_deg=32.0):
        self.bm.normal_update()
        # Emplacements d'abord : materials.clear() après coup effacerait l'attribut material_index.
        mesh.materials.clear()
        for m in self.slots:
            mesh.materials.append(m)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for p in mesh.polygons:
            p.use_smooth = True
        mesh.set_sharp_from_angle(angle=math.radians(sharp_deg))
        mesh.update()


def rrect(w, h, r, seg=5, cx=0.0, cy=0.0):
    """Rectangle aux coins arrondis (plan XY), sens trigonométrique."""
    r = max(min(r, w / 2 - 1e-5, h / 2 - 1e-5), 1e-5)
    pts = []
    for (sx, sy, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ox, oy = cx + sx * (w / 2 - r), cy + sy * (h / 2 - r)
        for i in range(seg + 1):
            a = math.radians(a0 + 90.0 * i / seg)
            pts.append((ox + r * math.cos(a), oy + r * math.sin(a)))
    return pts


def slab(pts, z0, z1, bevel=0.0, bseg=2, bevel_bottom=None):
    """Prisme d'un contour XY entre z0 et z1 ; arêtes du dessus (et du dessous) biseautées."""
    bm = bmesh.new()
    n = len(pts)
    lo = [bm.verts.new((x, y, z0)) for x, y in pts]
    hi = [bm.verts.new((x, y, z1)) for x, y in pts]
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bb = bevel if bevel_bottom is None else bevel_bottom
    edges = []
    if bevel > 0:
        edges += [e for e in bm.edges if all(abs(v.co.z - z1) < 1e-9 for v in e.verts)]
    if bb > 0:
        edges += [e for e in bm.edges if all(abs(v.co.z - z0) < 1e-9 for v in e.verts)]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=min(max(bevel, bb), abs(z1 - z0) * 0.49), segments=bseg,
                        profile=0.5, affect='EDGES', clamp_overlap=True)
    return bm


def box(sx, sy, sz, r=0.0, bevel=0.0, bseg=2, seg=4):
    """Pavé centré à l'origine, coins verticaux arrondis de rayon r, arêtes biseautées."""
    return slab(rrect(sx, sy, r, seg) if r > 0 else [(sx / 2, sy / 2), (-sx / 2, sy / 2), (-sx / 2, -sy / 2),
                                                    (sx / 2, -sy / 2)], -sz / 2, sz / 2, bevel, bseg)


def cyl(r, depth, seg=20, r2=None, bevel=0.0, bseg=2):
    """Cylindre (ou tronc de cône) d'axe Z centré à l'origine."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    if bevel > 0:
        caps = [e for e in bm.edges if abs(abs(e.verts[0].co.z) - depth / 2) < 1e-9
                and abs(abs(e.verts[1].co.z) - depth / 2) < 1e-9 and abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-9]
        bmesh.ops.bevel(bm, geom=caps, offset=bevel, segments=bseg, profile=0.5, affect='EDGES', clamp_overlap=True)
    return bm


def knob(r, depth, lobes=7, seg=56):
    """Molette de serrage crantée (lobes arrondis), axe Z."""
    pts = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        rr = r * (0.86 + 0.14 * max(0.0, math.cos(lobes * a)) ** 0.6)
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    return slab(pts, -depth / 2, depth / 2, bevel=min(depth * 0.25, 0.002), bseg=2)


def align(p0, p1):
    """Matrice qui envoie l'axe Z (pièce centrée, longueur |p1 − p0|) sur le segment p0 -> p1."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    return Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()


def at(x, y, z, rx=0.0, ry=0.0, rz=0.0):
    return Matrix.Translation((x, y, z)) @ Matrix.Rotation(rz, 4, 'Z') @ Matrix.Rotation(ry, 4, 'Y') \
        @ Matrix.Rotation(rx, 4, 'X')


def tube_along(points, r, seg=12):
    """Câble souple : tube le long d'une polyligne lissée (Catmull-Rom), extrémités fermées."""
    pts = [Vector(p) for p in points]
    smooth = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, len(pts) - 1)]
        for k in range(6):
            t = k / 6
            smooth.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    smooth.append(pts[-1])
    bm = bmesh.new()
    rings = []
    ref = Vector((0, 0, 1))
    for i, p in enumerate(smooth):
        t = (smooth[min(i + 1, len(smooth) - 1)] - smooth[max(i - 1, 0)]).normalized()
        if abs(t.dot(ref)) > 0.95:
            ref = Vector((1, 0, 0))
        a = t.cross(ref).normalized()
        b = t.cross(a)
        rings.append([bm.verts.new(p + r * (math.cos(2 * math.pi * k / seg) * a + math.sin(2 * math.pi * k / seg) * b))
                      for k in range(seg)])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((r0[k], r0[(k + 1) % seg], r1[(k + 1) % seg], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def screws(b, centers, normal_matrix, r=0.0028, head=0.0018, key="inox"):
    """Vis à tête cylindrique et six pans creux (empreinte noire) ; normal_matrix oriente l'axe Z de la vis."""
    for c in centers:
        m = Matrix.Translation(c) @ normal_matrix
        b.add(cyl(r, head, 16, bevel=head * 0.35), key, m @ Matrix.Translation((0, 0, head / 2)))
        b.add(cyl(r * 0.45, 0.0004, 6), "port", m @ Matrix.Translation((0, 0, head + 0.0001)))


# ------------------------------------------------------------------------------------------------ clavier
def keyboard_layout():
    """Touches (étiquette(s), x gauche en unités, rangée, largeur, hauteur relative, décalage vertical)."""
    rows = [
        [("Esc", 1)] + [("F%d" % i, 1) for i in range(1, 13)] + [("Home", 1), ("End", 1)],
        [("~\n`", 1), ("!\n1", 1), ("@\n2", 1), ("#\n3", 1), ("$\n4", 1), ("%\n5", 1), ("^\n6", 1), ("&\n7", 1),
         ("*\n8", 1), ("(\n9", 1), (")\n0", 1), ("_\n-", 1), ("+\n=", 1), ("Backspace", 2)],
        [("Tab", 1.5)] + [(c, 1) for c in "QWERTYUIOP"] + [("{\n[", 1), ("}\n]", 1), ("|\n\\", 1.5)],
        [("Caps Lock", 1.75)] + [(c, 1) for c in "ASDFGHJKL"] + [(":\n;", 1), ("\"\n'", 1), ("Enter", 2.25)],
        [("Shift", 2.25)] + [(c, 1) for c in "ZXCVBNM"] + [("<\n,", 1), (">\n.", 1), ("?\n/", 1), ("Shift", 2.75)],
        [("Fn", 1), ("Ctrl", 1.25), ("Opt", 1), ("Alt", 1.25), ("", 4.5), ("Alt", 1), ("PrtSc", 1), ("Ctrl", 1)],
    ]
    keys = []
    for r, row in enumerate(rows):
        x = 0.0
        scale = KB_COLS / sum(w for _, w in row) if r == 0 else 1.0
        for label, w in row:
            keys.append((label, x, r, w * scale, 1.0, 0.0))
            x += w * scale
    # Flèches : gauche et droite pleine hauteur, haut et bas en demi-touches superposées.
    keys += [("\u25C4", 12.0, 5, 1, 1.0, 0.0), ("\u25B2", 13.0, 5, 1, 0.5, 0.0), ("\u25BC", 13.0, 5, 1, 0.5, 0.5),
             ("\u25BA", 14.0, 5, 1, 1.0, 0.0)]
    return keys


def key_rect(x, r, w, hrel, voff):
    """Rectangle (x0, y0, x1, y1) d'une touche dans le repère du clavier (Y vers l'arrière, rangée 0 au fond)."""
    top = KB_D / 2 - sum(KB_ROWS_H[:r]) * KEY_U
    rh = KB_ROWS_H[r] * KEY_U
    y1 = top - voff * rh
    y0 = y1 - hrel * rh
    x0 = -KB_W / 2 + x * KEY_U
    return x0, y0, x0 + w * KEY_U, y1


def build_legend_texture():
    """Rend les légendes du clavier (gris clair sur la teinte des touches, vue orthographique) dans LEGEND_PNG ; UV
    des dessus de touches = position dans le rectangle du clavier, flancs sur un coin sans texte."""
    scene = bpy.data.scenes.new("_Legendes")
    world = bpy.data.worlds.new("_Legendes")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (KEY_COLOR, KEY_COLOR, KEY_COLOR * 1.06, 1)
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.resolution_x = 2048
    scene.render.resolution_y = int(2048 * KB_D / KB_W)
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = LEGEND_PNG
    ink = material("_Encre", (0, 0, 0), 0.0, 1.0, emission=(1, 1, 1), strength=0.5)
    font = bpy.data.fonts.load(r"C:\Windows\Fonts\arial.ttf", check_existing=True) \
        if os.path.exists(r"C:\Windows\Fonts\arial.ttf") else None
    made = []

    def text(body, x, y, size, align_x='CENTER'):
        cu = bpy.data.curves.new("_t", 'FONT')
        cu.body = body
        cu.size = size
        cu.align_x = align_x
        cu.align_y = 'CENTER'
        if font:
            cu.font = font
        ob = bpy.data.objects.new("_t", cu)
        ob.location = (x, y, 0)
        cu.materials.append(ink)
        scene.collection.objects.link(ob)
        made.append(ob)

    for label, x, r, w, hrel, voff in keyboard_layout():
        if not label:
            continue
        x0, y0, x1, y1 = key_rect(x, r, w, hrel, voff)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        if "\n" in label:
            top, bottom = label.split("\n")
            text(top, cx, cy + 0.0034, 0.0042)
            text(bottom, cx, cy - 0.0030, 0.0042)
        elif len(label) == 1:
            text(label, cx - (0.0 if r == 5 else 0.0032), cy + (0.0 if r == 5 else 0.0028),
                 0.0034 if r == 5 else 0.0052)
        elif r == 0:
            text(label, cx, cy, 0.0026)
        else:
            text(label, x0 + 0.0022 if r in (2, 3, 4) and x < 7 else cx, cy - 0.0028, 0.0030,
                 'LEFT' if r in (2, 3, 4) and x < 7 else 'CENTER')
    cam_data = bpy.data.cameras.new("_Legendes")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = KB_W
    cam = bpy.data.objects.new("_Legendes", cam_data)
    cam.location = (0, 0, 0.1)
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
        cu = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.curves.remove(cu)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    bpy.data.scenes.remove(scene)
    bpy.data.worlds.remove(world)
    bpy.data.materials.remove(ink)


# ------------------------------------------------------------------------------------------------ portable
def build_laptop(b, screen_mat):
    """Portable ouvert sur son bras articulé ; `screen_mat` : matériau de la dalle."""
    deck = PC_T
    # Base : coque inférieure (dessous légèrement plus petit) et repose-mains, arêtes arrondies.
    b.add(slab(rrect(PC_W, PC_D, PC_CORNER, 8), 0.0015, deck, bevel=0.0022, bseg=3, bevel_bottom=0.0), "coque")
    b.add(slab(rrect(PC_W - 0.004, PC_D - 0.004, PC_CORNER - 0.002, 8), 0.0, 0.0016, bevel=0.0, bevel_bottom=0.0012),
          "coque")
    # Cuvette du clavier : plaque noire très légèrement en retrait sous les touches.
    kb_mat = Matrix.Translation((0, KB_CY, 0))
    b.add(slab(rrect(KB_W + 0.004, KB_D + 0.004, 0.003, 4), deck - 0.0006, deck + 0.0001), "noir",
          kb_mat)

    # Touches : dessus légèrement arrondi, UV = position dans le rectangle du clavier (texture des légendes).
    def key_uv(co, face):
        if face.normal.z > 0.7:
            return ((co.x + KB_W / 2) / KB_W, (co.y - KB_CY + KB_D / 2) / KB_D)
        return (0.002, 0.002)

    gap = 0.0030
    for label, x, r, w, hrel, voff in keyboard_layout():
        x0, y0, x1, y1 = key_rect(x, r, w, hrel, voff)
        kw, kh = x1 - x0 - gap, y1 - y0 - (gap if hrel == 1.0 else gap * 0.6)
        part = slab(rrect(kw, kh, 0.0014, 3), deck, deck + 0.0016, bevel=0.0007, bseg=2, bevel_bottom=0.0)
        bmesh.ops.translate(part, vec=((x0 + x1) / 2, (y0 + y1) / 2 + KB_CY, 0), verts=part.verts)
        b.add(part, "touche", uv_fn=key_uv)
    # TrackPoint entre G, H et B ; boutons du pavé (gauche, milieu strié, droite) ; pavé tactile ; lecteur
    # d'empreintes ; bouton marche ; voyants.
    tp_x = -KB_W / 2 + 6.75 * KEY_U
    tp_y = KB_CY + KB_D / 2 - (KB_ROWS_H[0] + 3) * KEY_U
    b.add(cyl(0.0032, 0.0034, 18, r2=0.0028, bevel=0.0009), "rouge", Matrix.Translation((tp_x, tp_y, deck + 0.0011)))
    btn_y = KB_CY - KB_D / 2 - 0.0085
    for bx, bw in ((-0.0335, 0.033), (0.0, 0.030), (0.0335, 0.033)):
        b.add(box(bw - 0.0012, 0.0105, 0.0014, r=0.0012, bevel=0.0005), "touche",
              Matrix.Translation((bx, btn_y, deck + 0.0003)))
    b.add(box(0.0012, 0.006, 0.0006), "rouge", Matrix.Translation((-0.0505, btn_y, deck + 0.0009)))
    b.add(box(0.0012, 0.006, 0.0006), "rouge", Matrix.Translation((0.0505, btn_y, deck + 0.0009)))
    pad_y = btn_y - 0.0060 - 0.0300
    b.add(slab(rrect(0.100, 0.0570, 0.004, 5), deck - 0.0004, deck + 0.0002, bevel=0.0003), "pave",
          Matrix.Translation((0, pad_y, 0)))
    b.add(box(0.0125, 0.0105, 0.0004, r=0.002), "noir", Matrix.Translation((0.118, pad_y - 0.004, deck + 0.0001)))
    b.add(cyl(0.0042, 0.0008, 24, bevel=0.0003), "noir",
          Matrix.Translation((KB_W / 2 - 0.004, KB_CY + KB_D / 2 + 0.0085, deck + 0.0002)))
    b.add(cyl(0.0007, 0.0004, 10), "led",
          Matrix.Translation((KB_W / 2 - 0.004, KB_CY + KB_D / 2 + 0.0085, deck + 0.0007)))
    for i in range(3):
        b.add(box(0.0016, 0.0009, 0.0003), "led", Matrix.Translation((-0.13 + i * 0.004, -PC_D / 2 + 0.008, deck)))
    # Grilles des haut-parleurs de part et d'autre du clavier (perçages en rangées).
    for sx in (-1, 1):
        for i in range(5):
            for j in range(16):
                b.add(cyl(0.00045, 0.0004, 6), "port",
                      Matrix.Translation((sx * (KB_W / 2 + 0.0075 + i * 0.0018), KB_CY - KB_D / 2 + 0.006 + j * 0.0055,
                                          deck)))

    # Connectique sur les tranches (empreintes noires légèrement saillantes) : USB-C x2, HDMI, USB-A à gauche ;
    # USB-A, RJ45, jack audio, encoche antivol à droite ; grille d'aération à l'arrière gauche.
    zc = deck * 0.48
    left = [(-0.070, 0.0090, 0.0034), (-0.054, 0.0090, 0.0034), (-0.030, 0.0150, 0.0060), (0.000, 0.0130, 0.0055)]
    right = [(0.040, 0.0130, 0.0055), (0.010, 0.0160, 0.0120), (-0.025, 0.0055, 0.0055), (-0.075, 0.0070, 0.0035)]
    for side, ports in ((-1, left), (1, right)):
        for py, pw, ph in ports:
            b.add(box(0.0014, pw, ph, r=min(pw, ph) * 0.3), "port",
                  Matrix.Translation((side * (PC_W / 2 - 0.0006), py, zc)))
    for i in range(14):
        b.add(box(0.0016, 0.0022, 0.0080, r=0.0008), "port",
              Matrix.Translation((-PC_W / 2 + 0.0006, 0.035 + i * 0.0040, zc)))
    # Patins caoutchouc sous la base.
    for fx, fy in ((-0.14, -0.09), (0.14, -0.09), (-0.14, 0.09), (0.14, 0.09)):
        b.add(slab(rrect(0.022, 0.006, 0.003, 3), -0.0012, 0.0002, bevel=0.0, bevel_bottom=0.0008), "caoutchouc",
              Matrix.Translation((fx, fy, 0)))

    # Charnières : deux fûts métalliques à bague noire, carter central (passage des câbles de la dalle).
    for sx in (-1, 1):
        hx = sx * 0.112
        b.add(cyl(HINGE_R, 0.034, 24, bevel=0.0012), "coque", at(hx, HINGE_Y, HINGE_Z, ry=math.pi / 2))
        b.add(cyl(HINGE_R * 0.55, 0.0365, 16), "inox", at(hx, HINGE_Y, HINGE_Z, ry=math.pi / 2))
    b.add(cyl(HINGE_R * 0.92, 0.180, 24, bevel=0.0015), "coque", at(0, HINGE_Y, HINGE_Z, ry=math.pi / 2))

    # Écran : couvercle tourné autour de l'axe des charnières (droit = 90°, puis basculé vers l'arrière).
    tilt = math.radians(LID_OPEN_DEG - 90.0)
    lid_m = Matrix.Translation((0, HINGE_Y, HINGE_Z)) @ Matrix.Rotation(-tilt, 4, 'X')
    # Repère du couvercle : X largeur, Z le long du couvercle (0 = charnière), Y épaisseur (face écran vers −Y).
    z0 = HINGE_R * 0.4
    lid_part = slab(rrect(PC_W - 0.004, LID_H, PC_CORNER, 8), -LID_T / 2, LID_T / 2, bevel=0.0018, bseg=3)
    b.add(lid_part, "coque", lid_m @ Matrix.Translation((0, 0, z0 + LID_H / 2)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    face_y = -LID_T / 2
    disp_cz = z0 + BEZEL_BOTTOM + DISP_H / 2
    # Cadre de la dalle (noir mat, légèrement saillant) et joint caoutchouc.
    frame = slab(rrect(PC_W - 0.0085, LID_H - 0.0045, PC_CORNER - 0.002, 8), 0.0, 0.0006, bevel=0.0002)
    b.add(frame, "cadre", lid_m @ Matrix.Translation((0, face_y, z0 + LID_H / 2)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))

    def disp_uv(co, face):
        return (co.x / DISP_W + 0.5, co.y / DISP_H + 0.5)

    disp = bmesh.new()
    hw, hh = DISP_W / 2, DISP_H / 2
    vs = [disp.verts.new(p) for p in ((-hw, -hh, 0), (hw, -hh, 0), (hw, hh, 0), (-hw, hh, 0))]
    disp.faces.new(vs)
    # Dalle (plan XY, normale +Z) -> face écran : +Z local devient −Y du couvercle.
    to_lid = lid_m @ Matrix.Translation((0, face_y - 0.00075, disp_cz)) @ Matrix.Rotation(math.pi / 2, 4, 'X')
    b.add(disp, screen_mat, to_lid, uv_fn=disp_uv)
    # Webcam (objectif, anneau, voyant) et micros ; butées caoutchouc de la bordure.
    cam_z = z0 + LID_H - BEZEL_TOP / 2
    b.add(cyl(0.0024, 0.0004, 20), "noir", lid_m @ Matrix.Translation((0, face_y - 0.0008, cam_z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cyl(0.0011, 0.0004, 16), "inox", lid_m @ Matrix.Translation((0, face_y - 0.0011, cam_z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cyl(0.0005, 0.0003, 8), "led", lid_m @ Matrix.Translation((0.006, face_y - 0.0008, cam_z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    for mx in (-0.03, 0.03):
        b.add(cyl(0.0005, 0.0003, 8), "port", lid_m @ Matrix.Translation((mx, face_y - 0.0007, cam_z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    for bx in (-0.135, 0.135):
        for bz in (z0 + LID_H - 0.006, z0 + 0.012):
            b.add(cyl(0.0022, 0.0009, 12, bevel=0.0003), "caoutchouc",
                  lid_m @ Matrix.Translation((bx, face_y - 0.0004, bz)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))

    build_laptop_arm(b)


def build_laptop_arm(b):
    """Bras de fixation articulé (dans l'esprit des bras de portables de l'ISS) : plateau à griffes sous la base,
    rotule de tête à molette, deux segments en aluminium à articulations à chape et molettes de serrage, embase
    pivotante sur platine murale vissée ; câble d'alimentation le long du bras."""
    L = ARM_LENGTH
    # Plateau support sous le portable : tôle à bords tombés, trous d'allègement, quatre griffes.
    tray_z = -0.0045
    b.add(slab(rrect(0.250, 0.170, 0.008, 5), tray_z - 0.0025, tray_z + 0.0025, bevel=0.0008), "alu_noir")
    for hx in (-0.075, 0.075):
        for hy in (-0.045, 0.045):
            b.add(slab(rrect(0.050, 0.030, 0.008, 5), tray_z + 0.0025, tray_z + 0.0027), "port",
                  Matrix.Translation((hx, hy, 0)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            # Griffe : patte verticale le long de la tranche + bec rabattu sur le bord du repose-mains.
            gx, gy = sx * (PC_W / 2 + 0.0022), sy * 0.060
            b.add(box(0.0035, 0.018, PC_T + 0.008, r=0.0008, bevel=0.0006), "alu_noir",
                  Matrix.Translation((gx, gy, (PC_T + 0.008) / 2 - 0.007)))
            b.add(box(0.008, 0.018, 0.0022, r=0.0008, bevel=0.0006), "caoutchouc",
                  Matrix.Translation((gx - sx * 0.0030, gy, PC_T + 0.0011)))
            b.add(cyl(0.0022, 0.004, 12), "inox", at(gx + sx * 0.0018, gy, -0.002, ry=math.pi / 2))
    # Tête : rotule (sphère) + chape de basculement à molette.
    head_z = tray_z - 0.0025
    b.add(cyl(0.022, 0.006, 32, bevel=0.0015), "alu_noir", Matrix.Translation((0, 0, head_z - 0.003)))
    screws(b, [(0.015 * math.cos(a), 0.015 * math.sin(a), head_z - 0.006) for a in (0.4, 2.0, 3.6, 5.2)],
           Matrix.Rotation(math.pi, 4, 'X'), r=0.0020, head=0.0012)
    elbow = Vector((0.0, -0.085, -L * 0.52))
    head_pivot = Vector((0, 0, head_z - 0.030))
    wall_pivot = Vector((0, 0, -L + 0.040))
    b.add(cyl(0.012, 0.022, 24, bevel=0.002), "alu", Matrix.Translation((0, 0, head_z - 0.017)))
    sphere = bmesh.new()
    bmesh.ops.create_uvsphere(sphere, u_segments=24, v_segments=14, radius=0.0145)
    b.add(sphere, "alu", Matrix.Translation(head_pivot))
    for p0, p1 in ((head_pivot, elbow), (elbow, wall_pivot)):
        d = (p1 - p0)
        n = d.normalized()
        # Segment : tube rond en aluminium avec embouts usinés aux deux extrémités.
        b.add(cyl(0.0115, d.length - 0.034, 24), "alu", align(p0 + n * 0.017, p1 - n * 0.017))
        for e, s in ((p0, 1), (p1, -1)):
            b.add(cyl(0.0135, 0.018, 24, bevel=0.0015), "alu_noir", align(e + n * s * 0.012, e + n * s * 0.030))
    # Articulations à chape : deux joues, axe, molette de serrage d'un côté, écrou de l'autre (axe X).
    for j, pivot in enumerate((elbow, wall_pivot)):
        for sx in (-1, 1):
            b.add(cyl(0.019, 0.006, 28, bevel=0.0012), "alu_noir", at(pivot.x + sx * 0.0115, pivot.y, pivot.z,
                                                                     ry=math.pi / 2))
        b.add(cyl(0.0045, 0.040, 12), "inox", at(pivot.x, pivot.y, pivot.z, ry=math.pi / 2))
        b.add(knob(0.021, 0.012), "molette", at(pivot.x + 0.023, pivot.y, pivot.z, ry=math.pi / 2))
        b.add(cyl(0.010, 0.004, 24, bevel=0.0008), "alu", at(pivot.x + 0.0305, pivot.y, pivot.z, ry=math.pi / 2))
        b.add(cyl(0.007, 0.005, 6, bevel=0.0006), "inox", at(pivot.x - 0.0175, pivot.y, pivot.z, ry=math.pi / 2))
    # Molette de la rotule de tête (vers l'avant).
    b.add(knob(0.016, 0.010), "molette", at(0, -0.024, head_pivot.z, rx=math.pi / 2))
    b.add(cyl(0.006, 0.012, 16), "inox", at(0, -0.015, head_pivot.z, rx=math.pi / 2))
    # Embase pivotante et platine murale (vis à six pans creux aux quatre coins).
    b.add(cyl(0.024, 0.026, 32, bevel=0.002), "alu_noir", Matrix.Translation((0, 0, -L + 0.020)))
    b.add(cyl(0.030, 0.005, 32, bevel=0.0012), "alu", Matrix.Translation((0, 0, -L + 0.0085)))
    b.add(slab(rrect(0.110, 0.110, 0.010, 5), -L, -L + 0.006, bevel=0.0015), "plaque")
    screws(b, [(sx * 0.042, sy * 0.042, -L + 0.006) for sx in (-1, 1) for sy in (-1, 1)], Matrix())
    # Câble d'alimentation : sort à l'arrière gauche, longe le bras (colliers), rentre dans la platine.
    cable = [(-PC_W / 2 - 0.004, 0.075, 0.008), (-PC_W / 2 - 0.016, 0.070, -0.006), (-0.06, 0.04, -0.03),
             (-0.016, 0.004, head_pivot.z - 0.01), (-0.016, elbow.y * 0.5, (head_pivot.z + elbow.z) / 2),
             (-0.017, elbow.y + 0.004, elbow.z + 0.02), (-0.017, elbow.y * 0.5 - 0.002, (elbow.z + wall_pivot.z) / 2),
             (-0.034, 0.0, -L + 0.045), (-0.040, -0.030, -L + 0.012), (-0.040, -0.040, -L + 0.004)]
    b.add(tube_along(cable, 0.0026, 10), "cable")
    for t in (0.35, 0.7):
        for p0, p1 in ((head_pivot, elbow), (elbow, wall_pivot)):
            c = p0.lerp(p1, t)
            b.add(cyl(0.0145, 0.006, 20), "molette", align(c - (p1 - p0).normalized() * 0.003,
                                                           c + (p1 - p0).normalized() * 0.003))


# ------------------------------------------------------------------------------------------------ écran plat
def build_monitor(b, screen_mat, disp_w, disp_h):
    """Écran plat sur support mural inclinable (repère : image vers −Y, paroi à Y = WALL_GAP)."""
    W, H = disp_w + 2 * SCR_BEZEL, disp_h + SCR_BEZEL + SCR_CHIN
    cz = (SCR_CHIN - SCR_BEZEL) / 2               # centre du boîtier (le menton est plus haut que la bordure)
    to_front = Matrix.Rotation(math.pi / 2, 4, 'X')   # +Z de la pièce -> −Y (vers l'observateur)
    to_back = Matrix.Rotation(-math.pi / 2, 4, 'X')   # +Z de la pièce -> +Y (vers la paroi)
    # Coque avant (cadre), face avant à Y = 0.
    shell = slab(rrect(W, H, 0.006, 6), 0.0, SCR_FRONT_T, bevel=0.0025, bseg=3, bevel_bottom=0.0012)
    b.add(shell, "cadre", Matrix.Translation((0, 0, -cz)) @ to_back)
    # Lèvre du cadre autour de la dalle (1 mm) : la dalle est légèrement en retrait.
    lip = bmesh.new()
    outer = rrect(disp_w + 0.006, disp_h + 0.006, 0.0025, 4)
    inner = rrect(disp_w + 0.0005, disp_h + 0.0005, 0.0006, 4)
    for z0, z1 in ((0.0, 0.0011),):
        o0 = [lip.verts.new((x, y, z0)) for x, y in outer]
        o1 = [lip.verts.new((x, y, z1)) for x, y in outer]
        i1 = [lip.verts.new((x, y, z1)) for x, y in inner]
        i0 = [lip.verts.new((x, y, z0)) for x, y in inner]
        n = len(outer)
        for k in range(n):
            q = (k + 1) % n
            lip.faces.new((o0[k], o0[q], o1[q], o1[k]))
            lip.faces.new((o1[k], o1[q], i1[q], i1[k]))
            lip.faces.new((i1[k], i1[q], i0[q], i0[k]))
    bmesh.ops.recalc_face_normals(lip, faces=lip.faces)
    b.add(lip, "cadre", to_front)

    def disp_uv(co, face):
        return (co.x / disp_w + 0.5, co.z / disp_h + 0.5)

    disp = bmesh.new()
    hw, hh = disp_w / 2, disp_h / 2
    vs = [disp.verts.new(p) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]
    f = disp.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    b.add(disp, screen_mat, Matrix.Translation((0, -0.0002, 0)), uv_fn=disp_uv)
    # Menton : badge métallique (sans marque), voyant de marche ; boutons de réglage sous la tranche inférieure.
    chin_z = -disp_h / 2 - SCR_CHIN / 2
    b.add(box(min(0.05, W * 0.2), 0.004, 0.0006, r=0.001), "inox", Matrix.Translation((0, -0.0002, chin_z)) @ to_front)
    b.add(cyl(0.0011, 0.0006, 12), "led", at(W / 2 - 0.022, -0.0002, chin_z, rx=math.pi / 2))
    bottom_y = -H / 2 - cz
    for i in range(5):
        b.add(cyl(0.0028, 0.0016, 16, bevel=0.0005), "cadre",
              Matrix.Translation((W / 2 - 0.035 - i * 0.012, SCR_FRONT_T * 0.45, bottom_y - 0.0004)))
    # Ouïes d'aération sur la tranche supérieure.
    top_z = H / 2 - cz
    nslots = max(6, int((W - 0.12) / 0.012))
    for i in range(nslots):
        x = -(nslots - 1) * 0.006 + i * 0.012
        b.add(box(0.008, 0.0045, 0.0006, r=0.0012), "port", Matrix.Translation((x, SCR_FRONT_T * 0.55, top_z)))
    # Coque arrière bombée (pente sur le pourtour), plaque VESA et vis.
    bw, bh = W - min(0.08, W * 0.25), H - min(0.08, H * 0.25)
    back = slab(rrect(bw, bh, 0.02, 6), SCR_FRONT_T - 0.001, SCR_FRONT_T + SCR_BACK_T, bevel=SCR_BACK_T * 0.7,
                bseg=4, bevel_bottom=0.0)
    b.add(back, "dos", Matrix.Translation((0, 0, -cz)) @ to_back)
    back_y = SCR_FRONT_T + SCR_BACK_T
    vesa = 0.100 if min(bw, bh) > 0.13 else 0.075
    b.add(slab(rrect(vesa + 0.02, vesa + 0.02, 0.004, 3), 0, 0.003, bevel=0.0006), "plaque",
          Matrix.Translation((0, back_y, -cz)) @ to_back)
    screws(b, [(sx * vesa / 2, back_y + 0.003, -cz + sz * vesa / 2) for sx in (-1, 1) for sz in (-1, 1)], to_back,
           r=0.0032, head=0.0022)
    # Support mural inclinable : platine murale, deux bras à chape (axe horizontal X) et molettes de blocage,
    # rails verticaux fixés sur la plaque VESA.
    wall_y = WALL_GAP
    gap = wall_y - back_y - 0.003
    rail_h = vesa + 0.05
    for sx in (-1, 1):
        x = sx * (vesa / 2 + 0.006)
        b.add(box(0.012, 0.010, rail_h, r=0.002, bevel=0.0008), "alu_noir",
              Matrix.Translation((x, back_y + 0.003 + 0.005, -cz)))
        piv = Vector((x, back_y + 0.003 + gap * 0.55, -cz))
        b.add(box(0.010, gap * 0.60, 0.024, r=0.002, bevel=0.0008), "alu_noir",
              Matrix.Translation((x, wall_y - gap * 0.30, -cz)))
        b.add(cyl(0.0105, 0.014, 24, bevel=0.0012), "alu", at(piv.x, piv.y, piv.z, ry=math.pi / 2))
        b.add(knob(0.0125, 0.009), "molette", at(piv.x + sx * 0.0115, piv.y, piv.z, ry=math.pi / 2))
        b.add(cyl(0.004, 0.034, 10), "inox", at(piv.x, piv.y, piv.z, ry=math.pi / 2))
    plate_w, plate_h = vesa + 0.06, vesa + 0.03
    b.add(slab(rrect(plate_w, plate_h, 0.006, 4), -0.004, 0.0, bevel=0.001), "plaque",
          Matrix.Translation((0, wall_y, -cz)) @ to_back)
    screws(b, [(sx * (plate_w / 2 - 0.010), wall_y - 0.004, -cz + sz * (plate_h / 2 - 0.010))
               for sx in (-1, 1) for sz in (-1, 1)], Matrix.Rotation(math.pi / 2, 4, 'X'), r=0.0030, head=0.0020)
    # Câbles vidéo et alimentation : sortent du bas de la coque arrière et rentrent dans la paroi.
    for i, cx in enumerate((-0.025, -0.012)):
        y0 = back_y - 0.006
        z0 = -cz - bh / 2 + 0.03
        b.add(tube_along([(cx, y0, z0), (cx, y0 + 0.006, z0 - 0.025), (cx + 0.004 * i, wall_y - 0.012, z0 - 0.05),
                          (cx + 0.006 * i, wall_y - 0.002, z0 - 0.06), (cx + 0.006 * i, wall_y + 0.004, z0 - 0.062)],
                         0.0030 if i == 0 else 0.0024, 10), "cable")


# ------------------------------------------------------------------------------------------------ assemblage
def frame_laptop(origin, n, h):
    n, h = Vector(n).normalized(), Vector(h).normalized()
    x = h.cross(n)
    m = Matrix((x, h, n)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def frame_screen(center, n, up):
    n, up = Vector(n).normalized(), Vector(up).normalized()
    x = up.cross(n)
    m = Matrix((x, -n, up)).transposed().to_4x4()
    m.translation = Vector(center)
    return m


def make_device(obj_name, kind, screen_mat, size=None, mats=None):
    mats = mats or materials()
    b = Builder(mats)
    if kind == "laptop":
        build_laptop(b, screen_mat)
    else:
        build_monitor(b, screen_mat, *size)
    obj = bpy.data.objects.get(obj_name)
    old = obj.data if obj else None
    mesh = bpy.data.meshes.new(obj_name)
    b.finish(mesh)
    if obj is None:
        obj = bpy.data.objects.new(obj_name, mesh)
        bpy.context.scene.collection.objects.link(obj)
    else:
        obj.data = mesh
        if old and old.users == 0:
            bpy.data.meshes.remove(old)
    return obj


def screen_material_of(obj):
    name = obj.get("materiau_ecran")
    return bpy.data.materials.get(name) if name else None


if MODE == "preview":
    assert "nuke_station" not in bpy.data.filepath, "aperçu : ouvrir un fichier vide, pas la station"
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(LEGEND_PNG), exist_ok=True)
    build_legend_texture()
    mats = materials()
    demo_screen = material("Ecran_Demo", (0.0, 0.0, 0.0), 0.0, 0.08, emission=(0.12, 0.35, 0.55), strength=1.2)
    laptop = make_device("Portable", "laptop", demo_screen, mats=mats)
    laptop.matrix_world = Matrix.Translation((0, 0, ARM_LENGTH))
    wall = bpy.data.objects.new("Paroi", bpy.data.meshes.new("Paroi"))
    wall.data.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    wall.data.materials.append(material("Paroi", (0.6, 0.6, 0.58), 0.0, 0.7))
    bpy.context.scene.collection.objects.link(wall)
    monitors = []
    for name, x, size in (("Ecran_Mural", 1.2, (0.80, 0.50)), ("Ecran_Bandeau", 2.4, (1.00, 0.296)),
                          ("Ecran_Portrait", 3.3, (0.30, 0.80))):
        mon = make_device(name, "monitor", demo_screen, size=size, mats=mats)
        mon.matrix_world = Matrix.Translation((x, -WALL_GAP + 3.0, 0.5))
        monitors.append(mon)
    wall2 = bpy.data.objects.new("Paroi_Ecrans", bpy.data.meshes.new("Paroi_Ecrans"))
    wall2.data.from_pydata([(0.5, 3.0, -0.5), (4.0, 3.0, -0.5), (4.0, 3.0, 1.5), (0.5, 3.0, 1.5)], [], [(0, 1, 2, 3)])
    wall2.data.materials.append(bpy.data.materials["Paroi"])
    bpy.context.scene.collection.objects.link(wall2)
    stats = {o.name: len(o.data.polygons) for o in [laptop] + monitors}
    # Éclairage de studio et rendus.
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x, scene.render.resolution_y = 1280, 800
    scene.view_settings.view_transform = 'AgX'
    if scene.world is None:
        scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.055, 0.06, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    for nm, loc, energy, size in (("Cle", (1.2, -1.4, 1.8), 220, 1.2), ("Contre", (-1.5, 1.2, 1.4), 120, 1.0),
                                  ("Ecrans", (2.3, 1.5, 1.4), 300, 1.5)):
        ld = bpy.data.lights.new(nm, 'AREA')
        ld.energy, ld.size = energy, size
        lo = bpy.data.objects.new(nm, ld)
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0.3)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        if nm == "Ecrans":
            lo.rotation_euler = (Vector((2.3, 3.0, 0.5)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        scene.collection.objects.link(lo)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.clip_start = 0.005
    shots = {
        "portable_3-4": ((0.42, -0.62, 0.78), (0, 0.0, 0.40), 40),
        "portable_clavier": ((0.05, -0.16, 0.58), (0, 0.02, 0.37), 30),
        "portable_bras": ((0.70, -0.30, 0.25), (0, -0.02, 0.18), 38),
        "portable_charniere": ((0.30, 0.30, 0.48), (0.10, 0.10, 0.37), 45),
        "ecrans_face": ((2.3, 0.6, 0.55), (2.3, 3.0, 0.5), 22),
        "ecran_cote": ((1.95, 2.55, 0.15), (1.45, 2.98, 0.5), 30),
        "ecran_support": ((0.55, 2.90, 0.02), (1.0, 2.97, 0.40), 24),
        "ecran_dessous": ((1.55, 2.80, -0.05), (1.55, 2.97, 0.30), 20),
    }
    for nm, (loc, target, lens) in shots.items():
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        cam.data.lens = lens
        scene.render.filepath = os.path.join(PREVIEW_DIR, nm + ".png")
        bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=PREVIEW_BLEND)
    result = {"faces": stats, "apercus": PREVIEW_DIR}

elif MODE == "apply":
    assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
    if not os.path.exists(LEGEND_PNG):
        build_legend_texture()
    mats = materials()
    done = {}
    for name, (origin, n, h) in LAPTOPS.items():
        obj = bpy.data.objects[name]
        make_device(name, "laptop", screen_material_of(obj), mats=mats)
        obj.matrix_world = frame_laptop(origin, n, h)
        done[name] = len(obj.data.polygons)
    for name, (center, n, up, size) in SCREENS.items():
        obj = bpy.data.objects[name]
        make_device(name, "monitor", screen_material_of(obj), size=size, mats=mats)
        obj.matrix_world = frame_screen(center, n, up)
        done[name] = len(obj.data.polygons)
    result = {"remplaces": done}
