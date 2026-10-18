# Outil hors-jeu : coin douche du module Habitation dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP
# de Blender Lab), dans la niche à droite du WC (x 3,27–4,30, fond y = −1,9, ouverture y = −1,25, z ±0,52) :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -File tools/blender/build_shower.py
# - Interactif_Douche (maillage remplacé, nom et extras gardés) : fond en inox brossé à joint, bouche d'aspiration
#   perforée au sol et son flexible d'aspiration (l'eau ne s'écoule pas en apesanteur), deux passe-pieds, mitigeur
#   (deux molettes chaud / froid, afficheur, bouton), douchette sur son support et flexible métallique annelé,
#   miroir, poignée de maintien, serviettes roulées sous sangle et serviette pliée sur sa barre, produits de toilette
#   (shampoing sans rinçage, savon, dentifrice) sous sandow ;
# - Habitation_Rideau_Douche (extras type « rideau », id « Rideau_Douche ») : même rideau que le WC
#   (props_kit.build_curtain), devant l'ouverture x 3,29–4,28, regroupé à droite.
# Rejouable ; enregistre le .blend ; ne réexporte rien (export_station.py attend le feu vert de l'utilisateur).
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())
assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)
COLL = bpy.data.collections["Int_Habitation"]

MATS = {
    "inox": material("Int_Douche_Inox", (0.7, 0.71, 0.72), 1.0, 0.3),
    "joint": material("Int_Douche_Joint", (0.55, 0.56, 0.58), 0.0, 0.6),
    "grille": material("Int_Douche_Grille", (0.35, 0.36, 0.38), 1.0, 0.4),
    "trou": material("Int_PC_Port", (0.003, 0.003, 0.003), 0.0, 0.5),
    "flex": material("Int_Flexible_Gris", (0.42, 0.43, 0.45), 0.0, 0.6),
    "chrome": material("Int_Chrome", (0.88, 0.89, 0.9), 1.0, 0.28),
    "serviette_blanche": material("Int_Serviette_Blanche", (0.82, 0.8, 0.74), 0.0, 0.97),
    "lampe": bpy.data.materials["Int_Lumiere"],
    "miroir": material("Int_Miroir", (0.92, 0.93, 0.95), 1.0, 0.03),
    "noir": material("Int_WC_Joint", (0.02, 0.02, 0.02), 0.0, 0.6),
    "rouge": material("Int_Repere_Rouge", (0.7, 0.06, 0.04), 0.0, 0.5),
    "bleu": material("Int_Repere_Bleu", (0.05, 0.25, 0.65), 0.0, 0.5),
    "lcd": material("Int_LCD", (0.03, 0.07, 0.05), 0.0, 0.15),
    "vert": bpy.data.materials["Int_Voyant_Vert"],
    "sangle": material("Int_Sangle_Noire", (0.02, 0.02, 0.022), 0.0, 0.8),
    "sandow": material("Int_Sandow", (0.06, 0.12, 0.42), 0.0, 0.7),
    "serviette": bpy.data.materials["Int_Serviette"],
    "serviette_bleue": material("Int_Serviette_Bleue", (0.12, 0.25, 0.5), 0.0, 0.95),
    "flacon": material("Int_Flacon", (0.9, 0.9, 0.88), 0.0, 0.35),
    "bouchon": material("Int_Bouchon_Bleu", (0.08, 0.3, 0.7), 0.0, 0.4),
    "savon": material("Int_Savon", (0.85, 0.75, 0.55), 0.0, 0.45),
    "tube": material("Int_Tube_Dentifrice", (0.92, 0.92, 0.94), 0.0, 0.3),
    "jaune": bpy.data.materials["Int_Jaune"],
    "metal": bpy.data.materials["Int_Metal"],
    "rideau": bpy.data.materials["Int_Rideau"],
    "etiquette": material("Int_Etiquette", (0.93, 0.93, 0.9), 0.0, 0.6),
}
X0, X1, BACK, FLOOR, TOP = 3.27, 4.30, -1.9, -0.52, 0.52
XC = (X0 + X1) / 2
RX = Matrix.Rotation(-math.pi / 2, 4, 'X')     # axe Z d'une pièce -> +Y (hors du fond, vers l'ouverture)
RY = Matrix.Rotation(math.pi / 2, 4, 'Y')      # axe Z -> +X


def build_shower():
    b = Mesh(MATS)
    # Fond inox brossé et son joint périphérique.
    b.add(soft_box((0.47, 0.004, 0.47), 0.003, 0.03), "inox", T((XC, BACK + 0.004, 0.0)))
    edge = [Vector((XC + 0.47 * math.cos(a) / max(abs(math.cos(a)), abs(math.sin(a))) * 0.99, BACK + 0.008,
                    0.47 * math.sin(a) / max(abs(math.cos(a)), abs(math.sin(a))) * 0.99))
            for a in (2 * math.pi * k / 64 for k in range(65))]
    b.add(tube(edge, 0.006, 8), "joint")
    # Bouche d'aspiration perforée au sol et flexible d'aspiration vers le fond.
    b.add(soft_box((0.3, 0.13, 0.005), 0.004, 0.02), "grille", T((XC, -1.62, FLOOR + 0.005)))
    for i in range(14):
        for j in range(6):
            b.add(cylinder(0.006, 0.004, 10), "trou", T((XC - 0.26 + 0.04 * i, -1.72 + 0.04 * j, FLOOR + 0.009)))
    b.add(corrugated([(XC + 0.25, -1.74, FLOOR + 0.02), (XC + 0.3, -1.8, FLOOR + 0.05), (XC + 0.33, -1.86, FLOOR + 0.09),
                      (XC + 0.36, BACK + 0.01, FLOOR + 0.1)], 0.02, 0.014, 0.003), "flex")
    # Passe-pieds (sangles en arceau sur le sol).
    for x in (XC - 0.13, XC + 0.13):
        path = [Vector((x, -1.82 + 0.3 * t, FLOOR + 0.01 + 0.07 * math.sin(math.pi * t))) for t in (k / 10 for k in range(11))]
        b.add(tube(path, 0.002, 4), "sangle")
        for t in (0, 10):
            b.add(soft_box((0.025, 0.012, 0.006), 0.003, 0.006), "metal", T(path[t] - Vector((0, 0, 0.004))))
        # Sangle plate : succession de petits pavés arrondis le long de l'arceau.
        for k in range(10):
            p0, p1 = path[k], path[k + 1]
            m = T((p0 + p1) / 2) @ (p1 - p0).to_track_quat('Y', 'Z').to_matrix().to_4x4()
            b.add(soft_box((0.022, (p1 - p0).length / 2 + 0.002, 0.002), 0.0015, 0.01), "sangle", m)
    # Mitigeur : plaque, deux molettes (repères chaud / froid), afficheur, bouton.
    mx, mz = XC + 0.22, 0.02
    b.add(soft_box((0.1, 0.008, 0.075), 0.01, 0.015), "inox", T((mx, BACK + 0.016, mz)))
    for dx, mark in ((-0.05, "rouge"), (0.05, "bleu")):
        b.add(revolve([(0.0, 0.0), (0.028, 0.0), (0.03, 0.006), (0.024, 0.03), (0.0, 0.032)], 32), "chrome",
              T((mx + dx, BACK + 0.024, mz - 0.02)) @ RX)
        b.add(torus(0.03, 0.003, 32, 6), mark, T((mx + dx, BACK + 0.027, mz - 0.02)) @ RX)
    b.add(soft_box((0.035, 0.002, 0.012), 0.002, 0.006), "lcd", T((mx - 0.02, BACK + 0.025, mz + 0.045)))
    b.add(cylinder(0.008, 0.008, 16), "vert", T((mx + 0.05, BACK + 0.026, mz + 0.045)) @ RX)
    # Douchette sur son support (en haut à gauche), flexible métallique annelé jusqu'au mitigeur.
    hx, hz = XC - 0.25, 0.26
    b.add(soft_box((0.025, 0.02, 0.03), 0.008, 0.008), "inox", T((hx, BACK + 0.02, hz)))
    head_axis = Vector((0.0, 0.25, 1.0)).normalized()
    hm = T((hx, BACK + 0.05, hz)) @ head_axis.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    b.add(revolve([(0.0, -0.09), (0.013, -0.09), (0.016, -0.02), (0.02, 0.02), (0.05, 0.05), (0.052, 0.062),
                   (0.0, 0.064)], 32), "chrome", hm)
    b.add(cylinder(0.044, 0.002, 32), "joint", hm @ T((0, 0, 0.064)))
    for r, n in ((0.012, 6), (0.024, 12), (0.036, 18)):
        for k in range(n):
            a = 2 * math.pi * k / n
            b.add(cylinder(0.0022, 0.003, 6), "trou", hm @ T((r * math.cos(a), r * math.sin(a), 0.066)))
    h_end = hm @ Vector((0, 0, -0.09))
    m_out = Vector((mx, BACK + 0.03, mz - 0.075))
    b.add(corrugated([m_out, m_out + Vector((-0.02, 0.06, -0.12)), Vector((XC, -1.62, -0.28)),
                      Vector((hx + 0.05, -1.66, -0.08)), h_end + Vector((0, 0.02, -0.06)), h_end], 0.011, 0.006,
                     0.0015, 12), "chrome")
    # Petite lampe de niche en haut à gauche (comme celle du WC), dégagée de la douchette.
    b.add(soft_box((0.14, 0.02, 0.03), 0.006, 0.02), "lampe", T((X0 + 0.25, BACK + 0.02, 0.44)))
    # Miroir en haut à droite, cadre inox.
    b.add(soft_box((0.09, 0.005, 0.07), 0.01, 0.015), "inox", T((XC + 0.24, BACK + 0.012, 0.33)))
    b.add(soft_box((0.08, 0.002, 0.06), 0.006, 0.015), "miroir", T((XC + 0.24, BACK + 0.018, 0.33)))
    # Poignée de maintien jaune (verticale, à gauche), sur deux pattes.
    for z in (-0.2, 0.12):
        b.add(soft_box((0.012, 0.025, 0.012), 0.004, 0.006), "metal", T((X0 + 0.07, BACK + 0.025, z)))
    b.add(tube([(X0 + 0.07, BACK + 0.05, -0.23), (X0 + 0.07, BACK + 0.05, 0.15)], 0.012, 14), "jaune")
    # Serviettes roulées sous sangle (paroi droite) et serviette pliée sur sa barre.
    for z, mat in ((0.3, "serviette_blanche"), (0.2, "serviette_bleue")):
        roll = revolve([(0.0, -0.11)] + [(0.045 + 0.003 * math.sin(k), -0.11 + 0.22 * k / 8) for k in range(9)] +
                       [(0.0, 0.11)], 24)
        b.add(roll, mat, T((X1 - 0.05, -1.62, z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        # Élastique noir autour du rouleau, accroché à la paroi.
        b.add(torus(0.049, 0.004, 32, 6), "noir", T((X1 - 0.05, -1.62, z)) @ Matrix.Rotation(math.pi / 2, 4, 'X'))
        b.add(soft_box((0.004, 0.012, 0.008), 0.002, 0.004), "noir", T((X1 - 0.003, -1.62, z)))
    b.add(tube([(X1 - 0.02, -1.86, -0.08), (X1 - 0.02, -1.42, -0.08)], 0.008, 12), "chrome")
    for y in (-1.86, -1.42):
        b.add(soft_box((0.012, 0.01, 0.012), 0.004, 0.006), "chrome", T((X1 - 0.008, y, -0.08)))
    b.add(soft_box((0.012, 0.19, 0.11), 0.01, 0.015, chain(puff(0.006, axes=(0,)), wrinkles(0.0015, 2.2))),
          "serviette", T((X1 - 0.035, -1.64, -0.19)))
    b.add(soft_box((0.02, 0.19, 0.016), 0.012, 0.015), "serviette", T((X1 - 0.025, -1.64, -0.085)))
    # Produits de toilette sous sandow sur la cloison de gauche (shampoing sans rinçage, savon, dentifrice).
    side = X0 + 0.003
    b.add(revolve([(0.0, 0.0), (0.024, 0.0), (0.025, 0.01), (0.025, 0.11), (0.012, 0.125), (0.0, 0.125)], 24), "flacon",
          T((side + 0.026, -1.75, -0.02)))
    b.add(revolve([(0.0, 0.122), (0.011, 0.122), (0.011, 0.145), (0.0, 0.147)], 16), "bouchon", T((side + 0.026, -1.75, -0.02)))
    b.add(revolve([(0.0255, 0.03), (0.0255, 0.08)], 24), "etiquette", T((side + 0.026, -1.75, -0.02)))
    b.add(soft_box((0.012, 0.04, 0.03), 0.01, 0.01, puff(0.004)), "savon", T((side + 0.013, -1.65, 0.03)))
    tb = revolve([(0.0, 0.0), (0.016, 0.0), (0.017, 0.1), (0.008, 0.112), (0.0, 0.112)], 20)
    for v in tb.verts:
        v.co.x *= 0.5 + 0.5 * (1 - min(1.0, v.co.z / 0.1)) ** 0.5 if v.co.z < 0.1 else 1.0
        v.co.y *= 1.0 + 0.5 * min(1.0, v.co.z / 0.1)
    b.add(tb, "tube", T((side + 0.012, -1.56, -0.03)))
    b.add(revolve([(0.0, -0.012), (0.007, -0.012), (0.007, 0.0), (0.0, 0.0)], 16), "bouchon", T((side + 0.012, -1.56, -0.03)))
    a, c = Vector((side + 0.004, -1.84, 0.04)), Vector((side + 0.004, -1.48, 0.04))
    b.add(tube([a, a.lerp(c, 0.3) + Vector((0.035, 0, 0.005)), a.lerp(c, 0.7) + Vector((0.035, 0, 0.005)), c],
               0.0045, 8), "sandow")
    for p in (a, c):
        b.add(cylinder(0.008, 0.012, 12), "metal", T(p) @ RY)
    return b


shower = build_shower().write("Interactif_Douche", COLL)
curtain = build_curtain("Habitation_Rideau_Douche", "Rideau_Douche", 3.29, 4.28, COLL, MATS, gather="right")
vs = [shower.matrix_world @ v.co for v in shower.data.vertices]
bpy.ops.wm.save_mainfile()
result = {"douche": len(shower.data.polygons), "rideau": len(curtain.data.polygons),
          "y_max": round(max(v.y for v in vs), 3), "x": [round(min(v.x for v in vs), 3), round(max(v.x for v in vs), 3)],
          "z": [round(min(v.z for v in vs), 3), round(max(v.z for v in vs), 3)], "enregistre": not bpy.data.is_dirty}
