# Outil hors-jeu : modélise les équipements extérieurs réparables de la station et leurs écrans de maintenance, et
# les pose sous le module Commande (le radar sous l'Habitation) dans E:\Blender\nuke_station.blend (Blender
# ouvert, extension MCP de Blender Lab, port 9876) :
# - caméra de photographie (Equipement_Camera) : tourelle gyrostabilisée façon boule optronique (couronne crantée,
#   fourche, boule à quatre optiques : grand objectif infrarouge, objectif visible, petit objectif, télémètre), ~1 m,
#   pendue sous la coque, optiques vers le nadir ;
# - antenne radio (Equipement_Antenne) : antenne log-périodique (deux tubes, dix brins de longueur décroissante)
#   pointée vers le nadir, sous un rotateur d'azimut ;
# - radar de réception (Equipement_Radar), sous l'Habitation : parabole d'environ 1,1 m tournée vers le nadir sur une
#   monture azimut-élévation, source au foyer sur trois bras ;
# - pour chacun, un panneau de maintenance (Interactif_Panneau_Camera, _Antenne, _Radar) : boîtier blanc
#   durci à poignées EVA, sur une jambe de force, écran monochrome (dalle, matériau Ecran_Panneau_EVA, partagé)
#   tourné vers l'arrivée depuis le sas et vers le bas : accessible seulement en sortie extravéhiculaire.
# EVA_MODE choisit l'action :
#   & ./tools/blender_exec.ps1 -TimeoutS 600 -Code 'EVA_MODE = "apply"; exec(open(r"E:\Projects\starnuke\tools\blender\build_eva_equipment.py", encoding="utf-8").read())'
#   - "apply"  : crée ou remplace les objets de TARGETS (extras glTF : interactif, type, id, materiau_ecran pour les
#     panneaux ; equipement pour les appareils ; collection Module_Commande), plus leurs volumes de collision
#     (suffixe -convcolonly), rejouable. N'enregistre ni n'exporte rien ;
#   - "render" : rendus en situation dans PREVIEW_DIR (caméra et lumières temporaires, image de démonstration sur
#     les dalles), puis retire tout ce qu'il a ajouté pour le rendu ;
#   - "remove" : retire les objets de TARGETS (retour à l'état d'avant).
# L'export vers Godot (export_station.py) attend le feu vert de l'utilisateur.
# Repère local de chaque objet (mètres) : Z vers la coque (« haut »), l'appareil pend vers −Z ; X le long du module
# (vers l'avant, +X Blender) ; origine sur la coque. Panneaux : repère de frame_screen (affichage vers −Y local).
# Boîte à outils : primitives de build_station_devices.py (Builder, rrect, slab, cyl, tube_along, material…),
# chargé sans exécuter ses modes.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

EVA_MODE = globals().get("EVA_MODE", "render")
PREVIEW_DIR = globals().get("PREVIEW_DIR", r"E:\Blender\apercus_eva")
DEMO_PNG = r"E:\Blender\textures\panneau_eva_demo.png"

MODE = "none"   # build_station_devices.py ne doit ni rendre ni remplacer quoi que ce soit.
exec(open(r"E:\Projects\starnuke\tools\blender\build_station_devices.py", encoding="utf-8").read())

HULL_Z = -2.10            # dessous de la coque du module Commande (rayon 2,10 m, relevé par lancer de rayons)
CAMERA_X = 14.70          # entre la cupola (x 10,4–13,2) et l'anneau avant (x 16)
ANTENNA_X = 8.40          # de l'autre côté de la cupola, après la jonction avec l'Habitation (x 7,1)
RADAR_X = 1.00            # sous l'Habitation (coque x −4,3 à 4,3, à z −2,10 ; dessous dégagé)
RADAR_PANEL_DX = 1.45     # la parabole déborde de 0,62 m (fourche) : panneau plus écarté
PANEL_DX = 0.95           # écart appareil – panneau le long du module
# Orientation de l'affichage des panneaux : vers le bas et vers le sas (−X) ou vers l'avant du module (+X).
FACING_AFT = Vector((-0.55, 0.0, -0.835)).normalized()
FACING_FORE = Vector((0.55, 0.0, -0.835)).normalized()
SCREEN_MATERIAL = "Ecran_Panneau_EVA"

# objet -> (sorte, origine monde[, orientation de l'affichage d'un panneau[, collection]])
TARGETS = {
    "Equipement_Camera": ("camera", (CAMERA_X, 0.0, HULL_Z)),
    # Tourné vers l'avant du module (24/10/2026, demande de l'utilisateur) : vers le sas, il regardait la caméra et
    # restait inaccessible.
    "Interactif_Panneau_Camera": ("panneau_camera", (CAMERA_X + PANEL_DX, 0.0, HULL_Z), FACING_FORE),
    "Equipement_Antenne": ("antenne", (ANTENNA_X, 0.0, HULL_Z)),
    # Côté sas : de l'autre côté, il serait collé contre la cupola.
    "Interactif_Panneau_Antenne": ("panneau_antenne", (ANTENNA_X - PANEL_DX, 0.0, HULL_Z), FACING_AFT),
    "Equipement_Radar": ("radar", (RADAR_X, 0.0, HULL_Z), None, "Module_Habitation"),
    "Interactif_Panneau_Radar": ("panneau_radar", (RADAR_X - RADAR_PANEL_DX, 0.0, HULL_Z), FACING_AFT, "Module_Habitation"),
}
COLLECTION = "Module_Commande"


# ------------------------------------------------------------------------------------------------ matériaux
def eva_materials():
    return {
        "noir": material("Ext_Camera_Noir", (0.020, 0.021, 0.023), 0.55, 0.38),
        "couronne": material("Ext_Camera_Couronne", (0.045, 0.046, 0.050), 0.75, 0.32),
        "joint": material("Ext_Camera_Joint", (0.008, 0.008, 0.009), 0.0, 0.7),
        "grille": material("Ext_Camera_Grille", (0.004, 0.004, 0.005), 0.0, 0.8),
        "verre_ir": material("Ext_Optique_IR", (0.26, 0.30, 0.46), 0.35, 0.05),
        "verre": material("Ext_Optique", (0.010, 0.011, 0.014), 0.2, 0.04),
        "verre_clair": material("Ext_Optique_Clair", (0.06, 0.07, 0.08), 0.8, 0.05),
        "inox": material("Int_PC_Inox", (0.62, 0.62, 0.63), 1.0, 0.28),
        "port": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
        "alu": material("Int_Bras_Alu", (0.55, 0.56, 0.58), 1.0, 0.38),
        "blanc": material("Ext_Equipement_Blanc", (0.70, 0.70, 0.68), 0.0, 0.55),
        "gris": material("Ext_Equipement_Gris", (0.22, 0.225, 0.23), 0.6, 0.45),
        "brin": material("Ext_Antenne_Brin", (0.60, 0.61, 0.62), 1.0, 0.30),
        "isolant": material("Ext_Antenne_Isolant", (0.75, 0.73, 0.66), 0.0, 0.6),
        "cable": material("Int_Cable", (0.015, 0.015, 0.016), 0.0, 0.6),
        "cadre": material("Int_Ecran_Cadre", (0.022, 0.022, 0.024), 0.0, 0.55),
        "vitre": material("Int_Horloge_Vitre", (0.004, 0.004, 0.005), 0.0, 0.12),
        "poignee": bpy.data.materials.get("Poignee_EVA") or material("Poignee_EVA", (0.85, 0.62, 0.05), 0.0, 0.5),
        "led": material("Int_PC_Led", (0.05, 0.6, 0.15), 0.0, 0.3, emission=(0.1, 1.0, 0.25), strength=4.0),
    }


def screen_material(demo=False):
    """Dalle des panneaux : noir brillant ; pour les rendus, l'image de démonstration en émission."""
    m = material(SCREEN_MATERIAL, (0.0, 0.0, 0.0), 0.0, 0.10)
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.get("Demo")
    if demo and os.path.exists(DEMO_PNG):
        tex = tex or nt.nodes.new("ShaderNodeTexImage")
        tex.name = "Demo"
        tex.location = (-400, 0)
        img = bpy.data.images.get(os.path.basename(DEMO_PNG)) or bpy.data.images.load(DEMO_PNG)
        img.reload()
        tex.image = img
        nt.links.new(tex.outputs["Color"], p.inputs["Emission Color"])
        p.inputs["Emission Strength"].default_value = 1.4
    else:
        if tex:
            nt.nodes.remove(tex)
        p.inputs["Emission Strength"].default_value = 0.0
        img = bpy.data.images.get(os.path.basename(DEMO_PNG))
        if img and img.users == 0:
            bpy.data.images.remove(img)
    return m


# ------------------------------------------------------------------------------------------------ géométrie
def sphere(r, seg=40, rings=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    return bm


def facing(direction, distance):
    """Matrice qui pose une pièce d'axe Z le long de direction (unitaire), à distance du centre."""
    d = Vector(direction).normalized()
    return Matrix.Translation(d * distance) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()


def build_camera(b):
    """Tourelle optronique pendue sous la coque (origine sur la coque, appareil vers −Z), ~1,0 m."""
    # Platine de fixation sur la coque, vissée, et adaptateur.
    b.add(cyl(0.40, 0.03, 48, bevel=0.006), "gris", Matrix.Translation((0, 0, -0.015)))
    screws(b, [Vector((0.355 * math.cos(a), 0.355 * math.sin(a), -0.03))
               for a in (2 * math.pi * k / 12 for k in range(12))],
           Matrix.Rotation(math.pi, 4, 'X'), r=0.009, head=0.006)
    b.add(cyl(0.28, 0.06, 40, bevel=0.008), "noir", Matrix.Translation((0, 0, -0.06)))
    # Couronne : bord crénelé (créneaux arrondis), puis fût légèrement conique avec une gorge.
    crown = []
    n = 26
    for i in range(n * 6):
        a = 2 * math.pi * i / (n * 6)
        bump = max(0.0, math.cos(n * a)) ** 0.5
        r = 0.352 + 0.018 * bump
        crown.append((r * math.cos(a), r * math.sin(a)))
    b.add(slab(crown, -0.13, -0.09, bevel=0.004), "couronne")
    b.add(cyl(0.365, 0.07, 64, r2=0.36, bevel=0.006), "couronne", Matrix.Translation((0, 0, -0.165)))
    b.add(cyl(0.358, 0.012, 64), "joint", Matrix.Translation((0, 0, -0.205)))
    b.add(cyl(0.362, 0.07, 64, r2=0.345, bevel=0.008), "couronne", Matrix.Translation((0, 0, -0.245)))
    for k in range(16):
        a = 2 * math.pi * (k + 0.5) / 16
        d = Vector((math.cos(a), math.sin(a), 0))
        m = Matrix.Translation(d * 0.364 + Vector((0, 0, -0.165))) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        b.add(cyl(0.007, 0.004, 12, bevel=0.0015), "inox", m)
    # Fourche : deux bras (profil arrondi en bas) de part et d'autre de la boule, sur l'axe X ; grilles d'aération.
    ball_z = -0.66
    arm = rrect(0.40, 0.50, 0.12, 8, cx=0.0, cy=-0.04)
    for side in (-1, 1):
        x0 = side * 0.315
        m = Matrix.Translation((x0, 0, -0.50)) @ Matrix.Rotation(math.pi / 2, 4, 'Y') @ \
            Matrix.Rotation(math.pi / 2, 4, 'Z')
        b.add(slab(arm, -0.035, 0.035, bevel=0.010, bseg=3, bevel_bottom=0.010), "noir", m)
        for j in range(7):
            z = -0.34 - j * 0.026
            b.add(box(0.008, 0.20, 0.010, bevel=0.002), "grille", Matrix.Translation((x0 + side * 0.035, 0, z)))
        # Moyeu du pivot d'élévation.
        b.add(cyl(0.085, 0.05, 32, bevel=0.008), "couronne",
              Matrix.Translation((x0 + side * 0.03, 0, ball_z)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        screws(b, [Vector((x0 + side * 0.056, 0.05 * math.cos(a), ball_z + 0.05 * math.sin(a)))
                   for a in (2 * math.pi * k / 6 for k in range(6))],
               Matrix.Rotation(side * math.pi / 2, 4, 'Y'), r=0.006, head=0.003)
    # Traverse qui relie les bras sous la couronne.
    b.add(box(0.66, 0.30, 0.05, r=0.05, bevel=0.01), "noir", Matrix.Translation((0, 0, -0.30)))
    # Boule (rayon 0,27), optiques tournées vers le nadir (−Z) ; « haut » de la grappe : +Y.
    ball_r = 0.27
    b.add(sphere(ball_r, 48, 24), "noir", Matrix.Translation((0, 0, ball_z)))
    b.add(cyl(ball_r * 1.005, 0.010, 64), "joint", Matrix.Translation((0, 0, ball_z)) @
          Matrix.Rotation(math.pi / 2, 4, 'Y'))
    center = Vector((0, 0, ball_z))
    # (direction depuis le centre, rayon de l'optique, matériau du verre, profondeur de la monture)
    optics = [
        ((0.0, -0.36, -1.0), 0.105, "verre_ir"),     # grand objectif infrarouge (bleu violacé)
        ((0.0, 0.40, -1.0), 0.080, "verre"),         # objectif visible (noir)
        ((0.40, 0.08, -1.0), 0.052, "verre_clair"),  # petit objectif à reflets
    ]
    for direction, r, glass in optics:
        d = Vector(direction).normalized()
        base = Matrix.Translation(center) @ facing(d, ball_r - 0.012)
        b.add(cyl(r + 0.016, 0.036, 48, bevel=0.006), "joint", base)
        b.add(cyl(r, 0.006, 48), glass, base @ Matrix.Translation((0, 0, 0.0185)))
        if glass != "verre_ir":
            b.add(cyl(r * 0.45, 0.002, 32), "verre_clair" if glass == "verre" else "verre",
                  base @ Matrix.Translation((0, 0, 0.0218)))
    # Télémètre : petite fenêtre carrée à deux pupilles.
    d = Vector((-0.42, 0.02, -1.0)).normalized()
    base = Matrix.Translation(center) @ facing(d, ball_r - 0.008)
    b.add(box(0.11, 0.09, 0.03, r=0.012, bevel=0.004), "joint", base)
    for dx in (-0.025, 0.025):
        b.add(cyl(0.017, 0.004, 24), "verre", base @ Matrix.Translation((dx, 0.0, 0.0155)))


def build_antenna(b):
    """Antenne log-périodique pointée vers le nadir, sous un rotateur d'azimut (origine sur la coque)."""
    b.add(cyl(0.22, 0.025, 40, bevel=0.005), "gris", Matrix.Translation((0, 0, -0.0125)))
    screws(b, [Vector((0.19 * math.cos(a), 0.19 * math.sin(a), -0.025))
               for a in (2 * math.pi * k / 8 for k in range(8))],
           Matrix.Rotation(math.pi, 4, 'X'), r=0.008, head=0.005)
    # Rotateur : carter blanc, couronne grise.
    b.add(cyl(0.15, 0.20, 40, bevel=0.012), "blanc", Matrix.Translation((0, 0, -0.125)))
    b.add(cyl(0.13, 0.04, 40, bevel=0.006), "gris", Matrix.Translation((0, 0, -0.245)))
    # Mât, puis chape qui porte les deux tubes (boom) de l'antenne.
    b.add(cyl(0.035, 0.30, 24), "alu", Matrix.Translation((0, 0, -0.415)))
    b.add(box(0.10, 0.16, 0.06, r=0.01, bevel=0.006), "gris", Matrix.Translation((0, 0, -0.59)))
    top, bottom = -0.60, -1.70
    for y in (-0.045, 0.045):
        b.add(box(0.03, 0.03, top - bottom, bevel=0.003), "alu", Matrix.Translation((0, y, (top + bottom) / 2)))
    # Dix brins de longueur décroissante (rapport 0,86), alternés d'un tube à l'autre, isolants au pied.
    count = 10
    z = top - 0.06
    half = 0.70
    for k in range(count):
        side = 1 if k % 2 == 0 else -1
        y = side * 0.045
        for sx in (-1, 1):
            # Brin : du tube vers l'extérieur ; les deux moitiés d'un dipôle sur deux tubes opposés.
            ys = y if sx > 0 else -y
            p0 = Vector((0.0, ys, z))
            p1 = Vector((sx * half, ys, z))
            b.add(cyl(0.008, half, 12), "brin", align(p0, p1))
            b.add(cyl(0.012, 0.05, 12), "isolant", align(p0 + Vector((sx * 0.02, 0, 0)), p0 + Vector((sx * 0.07, 0, 0))))
        z -= 0.11
        half *= 0.86
    # Pointe (bouchon du boom) et câble coaxial du rotateur à la coque.
    b.add(box(0.13, 0.13, 0.03, r=0.01, bevel=0.005), "gris", Matrix.Translation((0, 0, bottom - 0.01)))
    b.add(tube_along([(0.10, 0.0, -0.20), (0.16, 0.03, -0.16), (0.20, 0.05, -0.08), (0.24, 0.06, -0.01)],
                     0.012, 10), "cable")
    b.add(tube_along([(0.035, 0.0, -0.35), (0.07, -0.02, -0.40), (0.06, -0.06, -0.55), (0.0, -0.06, -0.60)],
                     0.010, 10), "cable")


def lathe(profile, seg=64):
    """Solide de révolution autour de Z : profile, liste fermée de (rayon, z) parcourue une fois."""
    bm = bmesh.new()
    rings = []
    for k in range(seg):
        a = 2 * math.pi * k / seg
        c, s = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * c, r * s, z)) for r, z in profile])
    n = len(profile)
    for k in range(seg):
        r0, r1 = rings[k], rings[(k + 1) % seg]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((r0[i], r1[i], r1[j], r0[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_radar(b):
    """Radar de réception : parabole (Ø 1,1 m) tournée vers le nadir sur une monture azimut-élévation, source au
    foyer sur trois bras (origine sur la coque), ~1,05 m."""
    b.add(cyl(0.30, 0.03, 48, bevel=0.006), "gris", Matrix.Translation((0, 0, -0.015)))
    screws(b, [Vector((0.26 * math.cos(a), 0.26 * math.sin(a), -0.03))
               for a in (2 * math.pi * k / 10 for k in range(10))],
           Matrix.Rotation(math.pi, 4, 'X'), r=0.009, head=0.006)
    # Socle d'azimut : carter blanc, couronne grise.
    b.add(cyl(0.17, 0.26, 48, bevel=0.012), "blanc", Matrix.Translation((0, 0, -0.16)))
    b.add(cyl(0.20, 0.035, 48, bevel=0.006), "gris", Matrix.Translation((0, 0, -0.305)))
    # Fourche d'élévation : traverse, deux bras jusqu'aux pivots, de part et d'autre de la parabole.
    pivot_z = -0.66
    b.add(box(1.30, 0.14, 0.06, r=0.02, bevel=0.008), "gris", Matrix.Translation((0, 0, -0.35)))
    for side in (-1, 1):
        x = side * 0.62
        b.add(box(0.06, 0.12, abs(pivot_z + 0.35) + 0.06, r=0.015, bevel=0.006), "gris",
              Matrix.Translation((x, 0, (pivot_z - 0.35) / 2)))
        b.add(cyl(0.065, 0.06, 32, bevel=0.006), "couronne",
              Matrix.Translation((x + side * 0.02, 0, pivot_z)) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
        # Tourillon de la parabole jusqu'au pivot.
        b.add(box(0.07, 0.07, 0.07, bevel=0.006), "alu", Matrix.Translation((side * 0.575, 0, pivot_z)))
    # Réflecteur : paraboloïde (rayon R, profondeur d), coque de 2 cm, sommet en haut (vers la coque), creux vers le
    # nadir ; nervures au dos ; moyeu central.
    R, depth, top = 0.55, 0.16, -0.50
    f = R * R / (4 * depth)
    n = 14
    front = [(0.07 + (R - 0.07) * i / n, top - 0.02 - (0.07 + (R - 0.07) * i / n) ** 2 / (4 * f)) for i in range(n + 1)]
    back = [(r, z + 0.02) for r, z in reversed(front)]
    b.add(lathe([(R + 0.012, front[-1][1] + 0.01)] + back + front), "blanc")
    b.add(cyl(0.09, 0.10, 32, bevel=0.008), "gris", Matrix.Translation((0, 0, top - 0.02)))
    for k in range(8):
        a = 2 * math.pi * k / 8
        d = Vector((math.cos(a), math.sin(a), 0))
        # Nervure en quatre tronçons qui suivent le dos courbe (une corde droite le traverserait).
        pts = [d * r + Vector((0, 0, top + 0.016 - r * r / (4 * f))) for r in (0.10, 0.21, 0.32, 0.43, R - 0.03)]
        for p0, p1 in zip(pts, pts[1:]):
            b.add(box(0.012, 0.024, (p1 - p0).length + 0.01, bevel=0.003), "alu", align(p0, p1))
    # Source au foyer, tenue par trois bras depuis le bord ; câble le long d'un bras.
    focus = Vector((0, 0, top - 0.02 - f))
    b.add(cyl(0.05, 0.10, 24, r2=0.075, bevel=0.004), "gris", Matrix.Translation(focus + Vector((0, 0, 0.0))))
    b.add(cyl(0.062, 0.006, 24), "joint", Matrix.Translation(focus + Vector((0, 0, -0.053))))
    rim_z = front[-1][1]
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        rim = Vector((0.52 * math.cos(a), 0.52 * math.sin(a), rim_z))
        b.add(cyl(0.011, (focus - rim).length, 12), "alu", align(rim, focus + Vector((0, 0, 0.04))))
    b.add(tube_along([(0.0, 0.17, -0.30), (0.0, 0.30, -0.42), (0.0, 0.42, -0.60), (0.0, 0.47, rim_z)],
                     0.010, 10), "cable")



PANEL_W, PANEL_H, PANEL_D = 0.46, 0.36, 0.10
DISP_W, DISP_H = 0.32, 0.24


def build_panel(b, screen_mat):
    """Panneau de maintenance (repère frame_screen : affichage vers −Y, haut +Z, origine au centre du dos)."""
    to_front = Matrix.Rotation(math.pi / 2, 4, 'X')     # +Z de la pièce -> −Y
    b.add(slab(rrect(PANEL_W, PANEL_H, 0.03, 6), 0.0, PANEL_D, bevel=0.012, bseg=3, bevel_bottom=0.006),
          "blanc", to_front)
    front = -PANEL_D
    # Cadre noir, vitre, dalle (UV 0–1, (0, 0) en haut à gauche une fois dans glTF).
    b.add(slab(rrect(DISP_W + 0.04, DISP_H + 0.04, 0.012, 4), 0.0, 0.006, bevel=0.002), "cadre",
          Matrix.Translation((0, front, 0.01)) @ to_front)
    b.add(slab(rrect(DISP_W + 0.006, DISP_H + 0.006, 0.004, 3), 0.0, 0.002), "vitre",
          Matrix.Translation((0, front - 0.006, 0.01)) @ to_front)

    def disp_uv(co, face):
        return (co.x / DISP_W + 0.5, co.z / DISP_H + 0.5)

    disp = bmesh.new()
    hw, hh = DISP_W / 2, DISP_H / 2
    vs = [disp.verts.new(p) for p in ((-hw, 0, -hh), (hw, 0, -hh), (hw, 0, hh), (-hw, 0, hh))]
    f = disp.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    b.add(disp, screen_mat, Matrix.Translation((0, front - 0.0085, 0.01)), uv_fn=disp_uv)
    # Poignées EVA (jaunes) de part et d'autre, et voyant.
    for side in (-1, 1):
        x = side * (PANEL_W / 2 + 0.035)
        b.add(tube_along([(side * (PANEL_W / 2 - 0.02), -0.05, 0.13), (x, -0.06, 0.12), (x, -0.06, -0.12),
                          (side * (PANEL_W / 2 - 0.02), -0.05, -0.13)], 0.012, 12), "poignee")
    b.add(cyl(0.006, 0.004, 12), "led", Matrix.Translation((PANEL_W / 2 - 0.04, front - 0.001, -PANEL_H / 2 + 0.03))
          @ to_front)
    screws(b, [Vector((sx * (PANEL_W / 2 - 0.022), front, sz * (PANEL_H / 2 - 0.022)))
               for sx in (-1, 1) for sz in (-1, 1)], to_front, r=0.007, head=0.003)


def build_panel_strut(b, panel_matrix_local):
    """Jambe de force du panneau : platine sur la coque, tube jusqu'au dos du panneau (repère de l'objet)."""
    back = panel_matrix_local @ Vector((0, 0.0, 0.0))
    b.add(cyl(0.09, 0.02, 32, bevel=0.004), "gris", Matrix.Translation((0, 0, -0.01)))
    b.add(cyl(0.03, abs(back.z) + 0.02, 20), "alu",
          Matrix.Translation((0, 0, back.z / 2)))


def make_object(name, build, *args, collection=COLLECTION):
    mats = eva_materials()
    b = Builder(mats)
    build(b, *args)
    obj = bpy.data.objects.get(name)
    old = obj.data if obj else None
    mesh = bpy.data.meshes.new(name)
    b.finish(mesh)
    if obj is None:
        obj = bpy.data.objects.new(name, mesh)
    else:
        obj.data = mesh
        if old and old.users == 0:
            bpy.data.meshes.remove(old)
    col = bpy.data.collections[collection]
    if obj.name not in col.objects:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        col.objects.link(obj)
    return obj


def make_collider(name, parent, size, center, collection=COLLECTION):
    """Volume de collision convexe (boîte), enfant de parent : -convcolonly à l'import Godot."""
    cname = name + "-convcolonly"
    obj = bpy.data.objects.get(cname)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    mesh = bpy.data.meshes.new(cname)
    bm.to_mesh(mesh)
    bm.free()
    if obj is None:
        obj = bpy.data.objects.new(cname, mesh)
        bpy.data.collections[collection].objects.link(obj)
    else:
        old = obj.data
        obj.data = mesh
        if old.users == 0:
            bpy.data.meshes.remove(old)
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix()
    obj.matrix_local = Matrix()
    # Visible pour l'export (use_visible), en fil de fer et hors des rendus.
    obj.display_type = 'WIRE'
    obj.hide_render = True
    return obj


# Panneau : dos au bout de la jambe de force (PANEL_DROP sous la coque), affichage tourné vers facing.
PANEL_DROP = 0.30


def panel_matrix_local(facing):
    """Pose du panneau dans le repère de son objet (origine sur la coque)."""
    n = facing
    up = Vector((0, 0, 1))
    up = (up - n * up.dot(n)).normalized()
    m = frame_screen((0, 0, 0), n, up)
    # Le dos du panneau (Y local = 0) au bout de la jambe de force.
    m.translation = Vector((0, 0, -PANEL_DROP))
    return m


def build_panel_with_strut(b, screen_mat, facing):
    pm = panel_matrix_local(facing)
    sub = Builder(b.mats)
    build_panel(sub, screen_mat)
    # Fusion : pièces du panneau transformées dans le repère de l'objet.
    sub.bm.normal_update()
    uv_src = sub.uv
    vmap = {}
    for v in sub.bm.verts:
        vmap[v] = b.bm.verts.new(pm @ v.co)
    for f in sub.bm.faces:
        g = b.bm.faces.new([vmap[v] for v in f.verts])
        g.material_index = b.slot(sub.slots[f.material_index])
        g.smooth = True
        for lg, lf in zip(g.loops, f.loops):
            lg[b.uv].uv = lf[uv_src].uv
    sub.bm.free()
    build_panel_strut(b, pm)


def apply():
    assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
    screen = screen_material(demo=False)
    done = {}
    for name, (kind, origin, *extra) in TARGETS.items():
        facing = (extra[0] if extra else None) or FACING_AFT
        col = extra[1] if len(extra) > 1 else COLLECTION
        if kind == "camera":
            obj = make_object(name, build_camera, collection=col)
            make_collider(name, obj, (0.76, 0.76, 0.95), (0, 0, -0.48), col)
        elif kind == "antenne":
            obj = make_object(name, build_antenna, collection=col)
            make_collider(name, obj, (0.30, 0.30, 0.62), (0, 0, -0.31), col)
        elif kind == "radar":
            obj = make_object(name, build_radar, collection=col)
            make_collider(name, obj, (1.32, 1.20, 1.06), (0, 0, -0.53), col)
        else:
            obj = make_object(name, build_panel_with_strut, screen, facing, collection=col)
            obj["interactif"] = True
            obj["type"] = "panneau_eva"
            obj["materiau_ecran"] = SCREEN_MATERIAL
            make_collider(name, obj, (0.50, 0.40, 0.55), (0, 0, -0.30), col)
        obj["id"] = name.split("_", 1)[1]
        if kind in ("camera", "antenne", "radar"):
            obj["equipement"] = kind
        else:
            obj["equipement"] = kind.removeprefix("panneau_")
        obj.matrix_world = Matrix.Translation(origin)
        done[name] = len(obj.data.polygons)
    return done


def remove():
    gone = []
    for name in TARGETS:
        for n in (name + "-convcolonly", name):
            obj = bpy.data.objects.get(n)
            if obj:
                mesh = obj.data
                bpy.data.objects.remove(obj)
                if mesh and mesh.users == 0:
                    bpy.data.meshes.remove(mesh)
                gone.append(n)
    return gone


# ------------------------------------------------------------------------------------------------ démonstration
def build_demo_texture():
    """Image de démonstration de l'écran : style MS-DOS monochrome (noir et blanc), bouton [ ON ]."""
    scene = bpy.data.scenes.new("_Panneau_Demo")
    world = bpy.data.worlds.new("_Panneau_Demo")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.0, 0.0, 0.0, 1)
    scene.world = world
    scene.render.engine = 'BLENDER_EEVEE'
    scene.view_settings.view_transform = 'Standard'
    scene.render.resolution_x, scene.render.resolution_y = 640, 480
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = DEMO_PNG
    ink = material("_Encre_EVA", (0, 0, 0), 0.0, 1.0, emission=(0.85, 0.85, 0.85), strength=1.0)
    font_path = r"C:\Windows\Fonts\consola.ttf"
    font = bpy.data.fonts.load(font_path, check_existing=True) if os.path.exists(font_path) else None
    lines = ["CAMERA.EXE  v1.2          MAINTENANCE", "=" * 36, "", "  Etat      : EN SERVICE",
             "  Capteur   : NADIR", "", "        [  ON  ]   [ OFF ]", "", "=" * 36, " F1 Aide         Esc Quitter"]
    made = []
    for i, text in enumerate(lines):
        cu = bpy.data.curves.new("_txt", 'FONT')
        cu.body = text
        cu.size = 0.0115
        cu.align_x = 'LEFT'
        if font:
            cu.font = font
        cu.materials.append(ink)
        ob = bpy.data.objects.new("_txt", cu)
        ob.location = (-0.152, 0, 0.098 - i * 0.021)
        ob.rotation_euler = (math.pi / 2, 0, 0)
        scene.collection.objects.link(ob)
        made.append(ob)
    cam_data = bpy.data.cameras.new("_Panneau_Demo")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = DISP_W
    cam = bpy.data.objects.new("_Panneau_Demo", cam_data)
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
        bpy.data.curves.remove(data)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(cam_data)
    bpy.data.scenes.remove(scene)
    bpy.data.worlds.remove(world)
    bpy.data.materials.remove(ink)


def render_views():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(DEMO_PNG), exist_ok=True)
    build_demo_texture()
    screen_material(demo=True)
    sc = bpy.context.scene
    r = sc.render
    saved = (sc.camera, r.resolution_x, r.resolution_y, r.filepath)
    created = []
    try:
        cam = bpy.data.objects.new("_Eva_Camera", bpy.data.cameras.new("_Eva_Camera"))
        sc.collection.objects.link(cam)
        created.append(cam)
        cam.data.clip_start = 0.02
        sc.camera = cam
        # Éclairage d'appoint (le dessous de la station est dans l'ombre) : lampes de casque d'un astronaute.
        for nm, loc, target, energy in (("_Eva_Cle", (12.0, -3.0, -5.0), (14.7, 0, -2.6), 900),
                                        ("_Eva_Cle2", (6.0, -3.0, -5.0), (8.4, 0, -2.8), 900),
                                        ("_Eva_Cle3", (-2.0, -3.5, -5.0), (0.5, 0, -2.8), 900),
                                        ("_Eva_Contre", (17.0, 3.0, -4.5), (12.0, 0, -2.6), 400)):
            ld = bpy.data.lights.new(nm, 'AREA')
            ld.energy, ld.size = energy, 2.0
            lo = bpy.data.objects.new(nm, ld)
            lo.location = loc
            lo.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            sc.collection.objects.link(lo)
            created.append(lo)
        r.resolution_x, r.resolution_y = 1280, 720
        shots = {
            "situation": ((8.0, -7.5, -6.5), (12.0, 0.0, -2.8), 22),
            "camera_34": ((13.0, -2.2, -3.6), (14.75, 0.0, -2.65), 35),
            "camera_dessous": ((14.4, -0.6, -4.6), (14.7, 0.0, -2.7), 30),
            "panneau_camera": ((17.6, -0.6, -3.6), (15.65, 0.0, -2.45), 35),
            "antenne_34": ((5.2, -3.2, -3.9), (8.4, 0.0, -2.9), 30),
            "panneau_antenne": ((5.6, -0.9, -3.5), (7.45, 0.0, -2.45), 35),
            "radar_34": ((-1.6, -3.2, -4.2), (1.0, 0.0, -2.75), 30),
            "radar_dessous": ((1.4, -1.6, -5.2), (1.0, 0.0, -2.8), 28),
            "panneau_radar": ((-2.2, -0.9, -3.5), (-0.45, 0.0, -2.45), 35),
        }
        for nm, (loc, target, lens) in shots.items():
            cam.location = loc
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            cam.data.lens = lens
            r.filepath = os.path.join(PREVIEW_DIR, nm + ".png")
            bpy.ops.render.render(write_still=True)
    finally:
        sc.camera, r.resolution_x, r.resolution_y, r.filepath = saved
        for ob in created:
            data = ob.data
            bpy.data.objects.remove(ob)
            if isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)
        screen_material(demo=False)
    return PREVIEW_DIR


if EVA_MODE == "apply":
    result = {"objets": apply()}
elif EVA_MODE == "render":
    result = {"apercus": render_views()}
elif EVA_MODE == "remove":
    result = {"retires": remove()}
