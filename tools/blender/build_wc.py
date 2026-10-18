# Outil hors-jeu : WC et rideau du module Habitation dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP
# de Blender Lab), d'après le WC russe de l'ISS (photo « Space Toilet ») :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -File tools/blender/build_wc.py
# - Interactif_WC (maillage remplacé, nom et extras gardés), posé sur le fond de la niche (y = −1,9, assise vers le
#   couloir) : réservoir à déchets blanc dans son arceau tubulaire, cuvette à lunette et couvercle relevé (intérieur
#   jaune, disque gris), boîtier de commande (trappes rondes, rivets), entonnoir urinaire jaune sur flexible, flexibles
#   annelés gris vers la paroi, poire en caoutchouc orange, cale-cuisses, lingettes sur la cloison ;
# - Habitation_Rideau_WC (nouvel objet, extras type « rideau », id « Rideau_WC ») : rail et rideau plissé à anneaux
#   devant l'ouverture de la niche du WC (x 1,82–3,21, y −1,29). Forme de base : ouvert, regroupé contre le bord
#   gauche ; clé de forme « Ferme » : déployé sur toute l'ouverture (scripts/station.gd l'anime). Sans collision
#   (pas de suffixe -col) : le jeu lui ajoute une zone de clic.
# Rejouable ; enregistre le .blend ; ne réexporte rien (export_station.py attend le feu vert de l'utilisateur).
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())
assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)
COLL = bpy.data.collections["Int_Habitation"]

MATS = {
    "blanc": material("Int_WC_Blanc", (0.84, 0.83, 0.79), 0.0, 0.38),
    "jaune": material("Int_WC_Jaune", (0.88, 0.62, 0.02), 0.0, 0.4),
    "gris": material("Int_WC_Gris", (0.55, 0.56, 0.58), 0.6, 0.4),
    "flex": material("Int_Flexible_Gris", (0.42, 0.43, 0.45), 0.0, 0.6),
    "orange": material("Int_Caoutchouc_Orange", (0.5, 0.13, 0.03), 0.0, 0.5),
    "laiton": material("Int_Laiton", (0.7, 0.52, 0.25), 1.0, 0.35),
    "noir": material("Int_WC_Joint", (0.02, 0.02, 0.02), 0.0, 0.6),
    "lingettes": material("Int_Lingettes", (0.75, 0.88, 0.75), 0.0, 0.5),
    "metal": bpy.data.materials["Int_Metal"],
    "rideau": bpy.data.materials["Int_Rideau"],
    "etiquette": material("Int_Etiquette", (0.93, 0.93, 0.9), 0.0, 0.6),
}


# ------------------------------------------------------------------------------------------------ WC
def build_wc():
    b = Mesh(MATS)
    O = Vector((2.52, -1.9, -0.06))  # repère local : X = +x, Y = sortie de la paroi (+y), Z = +z
    L = lambda x, y, z: T(O + Vector((x, y, z)))
    ry = Matrix.Rotation(-math.pi / 2, 4, 'X')  # axe Z d'une pièce -> +Y local
    # Embase sur la paroi.
    b.add(soft_box((0.2, 0.008, 0.21), 0.006, 0.02), "gris", L(0.02, 0.008, -0.01))
    # Réservoir à déchets : cylindre blanc, cerclages, couvercle bombé, colliers.
    b.add(revolve([(0.0, 0.0), (0.11, 0.0), (0.12, 0.01), (0.12, 0.2), (0.115, 0.215), (0.0, 0.215)], 40), "blanc",
          L(-0.03, 0.016, -0.03) @ ry)
    for yy in (0.05, 0.19):
        b.add(torus(0.121, 0.005, 40, 8), "gris", L(-0.03, 0.016 + yy, -0.03) @ ry)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        b.add(soft_box((0.008, 0.012, 0.006), 0.002, 0.004), "gris",
              L(-0.03 + 0.124 * math.cos(a), 0.205, -0.03 + 0.124 * math.sin(a)))
    # Arceau tubulaire autour du réservoir (deux U blancs) jusque sous la cuvette.
    for sz in (-1, 1):
        z = -0.03 + sz * 0.15
        b.add(tube([O + Vector(p) for p in ((-0.19, 0.016, z), (-0.19, 0.2, z), (-0.17, 0.25, z * 0.9),
                    (0.13, 0.25, z * 0.9), (0.15, 0.2, z), (0.15, 0.016, z))], 0.009, 10), "blanc")
    # Cuvette : boîtier blanc, lunette (tore), cône d'aspiration gris, joint noir.
    seat = Vector((-0.04, 0.3, 0.0))
    b.add(soft_box((0.16, 0.045, 0.155), 0.03, 0.02), "blanc", L(seat.x, 0.27, 0.0))
    top = 0.315
    b.add(torus(0.085, 0.016, 40, 10), "blanc", L(seat.x, top + 0.006, -0.02) @ ry)
    b.add(revolve([(0.072, 0.0), (0.045, -0.035), (0.02, -0.05), (0.0, -0.05)], 32), "gris",
          L(seat.x, top + 0.004, -0.02) @ ry)
    b.add(torus(0.072, 0.003, 40, 6), "noir", L(seat.x, top + 0.004, -0.02) @ ry)
    # Couvercle relevé (charnière en haut de la cuvette), intérieur jaune, disque gris ; vérin.
    hinge = Vector((seat.x, top + 0.01, 0.15))
    lid = L(*hinge) @ Matrix.Rotation(math.radians(120), 4, 'X')  # couvercle relevé, renversé vers le haut de la niche (dégage le rideau)
    b.add(soft_box((0.135, 0.008, 0.125), 0.02, 0.02), "blanc", lid @ T((0, 0.004, -0.125)))
    b.add(soft_box((0.115, 0.003, 0.108), 0.015, 0.02), "jaune", lid @ T((0, -0.006, -0.125)))
    b.add(cylinder(0.045, 0.012, 32), "gris", lid @ T((0, -0.012, -0.14)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cylinder(0.03, 0.016, 32), "blanc", lid @ T((0, -0.018, -0.14)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
    b.add(cylinder(0.01, 0.3, 14), "blanc", L(seat.x, top + 0.012, 0.15) @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    # Boîtier de commande à droite : trappes rondes, rivets, plaque, levier.
    box = Vector((0.2, 0.27, -0.02))
    b.add(soft_box((0.075, 0.045, 0.13), 0.02, 0.02), "blanc", L(*box))
    for zz in (-0.06, 0.04):
        b.add(cylinder(0.034, 0.008, 28), "blanc", L(box.x, box.y + 0.047, box.z + zz) @ ry)
        b.add(torus(0.034, 0.003, 28, 6), "gris", L(box.x, box.y + 0.05, box.z + zz) @ ry)
    for sx in (-1, 1):
        for sz in (-1, 1):
            b.add(cylinder(0.004, 0.004, 8), "gris", L(box.x + sx * 0.06, box.y + 0.046, box.z + sz * 0.115) @ ry)
    b.add(soft_box((0.03, 0.001, 0.012), 0.002, 0.005), "etiquette", L(box.x, box.y + 0.046, box.z + 0.1))
    b.add(soft_box((0.008, 0.035, 0.01), 0.004, 0.005), "gris", L(box.x + 0.05, box.y + 0.08, box.z + 0.12))
    # Entonnoir urinaire jaune sur son bras, flexible annelé gris jusqu'au boîtier.
    f0 = Vector((box.x + 0.02, box.y + 0.06, box.z + 0.17))
    b.add(soft_box((0.012, 0.035, 0.012), 0.005, 0.006), "gris", L(f0.x, f0.y - 0.02, f0.z - 0.03))
    b.add(revolve([(0.0, 0.0), (0.012, 0.0), (0.014, 0.04), (0.05, 0.1), (0.047, 0.102), (0.012, 0.045), (0.0, 0.045)],
                  32), "jaune", L(*f0) @ Matrix.Rotation(-math.radians(60), 4, 'X'))
    b.add(corrugated([O + f0 - Vector((0, 0.01, 0.02)), O + f0 + Vector((0.08, -0.05, -0.1)),
                      O + box + Vector((0.09, 0.0, -0.05)), O + box + Vector((0.075, -0.02, -0.08))], 0.013), "flex")
    # Flexibles annelés vers la paroi (réservoir et boîtier), raccords en laiton.
    for p0, p1 in ((Vector((-0.15, 0.12, -0.03)), Vector((-0.27, 0.01, -0.12))),
                   (Vector((0.2, 0.22, -0.15)), Vector((0.32, 0.01, -0.22)))):
        b.add(corrugated([O + p0, O + p0.lerp(p1, 0.4) + Vector((-0.02, 0.05, -0.02)), O + p1 + Vector((0, 0.04, 0)),
                          O + p1], 0.016), "flex")
        b.add(cylinder(0.022, 0.03, 20), "laiton", T(O + p0) @ (p1 - p0).to_track_quat('Z', 'Y').to_matrix().to_4x4())
    # Poire en caoutchouc orange (côtelée) sur un flexible fin.
    pear = O + Vector((0.32, 0.16, -0.12))
    b.add(tube([O + box + Vector((0.07, -0.01, -0.12)), pear + Vector((-0.02, 0.0, 0.05)), pear + Vector((0.0, 0.0, 0.03))],
               0.005, 8), "flex")
    prof = [(0.0, 0.0)] + [(0.035 * math.sin(math.pi * k / 10) ** 0.8, -0.09 * k / 10) for k in range(1, 10)] + [(0.0, -0.09)]
    pb = revolve(prof, 24)
    for v in pb.verts:
        a = math.atan2(v.co.y, v.co.x)
        v.co.x *= 1 + 0.08 * math.cos(8 * a)
        v.co.y *= 1 + 0.08 * math.cos(8 * a)
    b.add(pb, "orange", T(pear + Vector((0, 0, 0.03))))
    # Cale-cuisses (barres en L depuis la paroi, mousse noire).
    for sz in (-1, 1):
        z = sz * 0.31
        b.add(tube([(2.2, -1.9, z), (2.2, -1.48, z), (2.78, -1.48, z)], 0.012, 12), "metal")
        b.add(tube([(2.32, -1.48, z), (2.66, -1.48, z)], 0.022, 14), "noir")
    # Lingettes collées au velcro sur la cloison de droite.
    b.add(soft_box((0.005, 0.07, 0.05), 0.004, 0.012, puff(0.006, axes=(0,))), "lingettes", T((3.212, -1.55, 0.2)))
    b.add(soft_box((0.003, 0.025, 0.015), 0.002, 0.006), "etiquette", T((3.205, -1.55, 0.22)))
    return b



wc = build_wc().write("Interactif_WC", COLL)
# Rideau : ouverture de la niche x 1,82–3,21, regroupé à gauche (props_kit.build_curtain).
curtain = build_curtain("Habitation_Rideau_WC", "Rideau_WC", 1.82, 3.21, COLL, MATS, gather="left")
bpy.ops.wm.save_mainfile()
result = {"wc": len(wc.data.polygons), "rideau": len(curtain.data.polygons), "enregistre": not bpy.data.is_dirty}
