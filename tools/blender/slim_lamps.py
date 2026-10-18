# Outil hors-jeu : affine les lampes des couloirs de E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de
# Blender Lab) et vérifie que rien ne les recouvre.
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/slim_lamps.py
# Les 32 lampes des couloirs (Arrimage, Habitation, Commande ; matériau Int_Lumiere, pavés de 6 faces sur les panneaux
# diagonaux) mesuraient 0,74 m de long sur 0,43 m de haut : la hauteur (en travers du panneau) est ramenée à
# LAMP_HEIGHT, longueur, position et matériau inchangés (même luminosité ; les lumières Lum_* ne bougent pas).
# Rejouable (une lampe déjà affinée n'est pas retouchée). Contrôle : liste des objets dont un sommet tombe dans le
# volume d'une lampe (marge MARGIN tout autour, jusqu'à 0,15 m devant sa face). Enregistre le .blend.
import bpy, bmesh, math
from mathutils import Vector

LAMP_HEIGHT = 0.15
MARGIN = 0.02
LAMP_OBJECTS = ("Arrimage_Couloir-col", "Habitation_Couloir-col", "Commande_Couloir-col")

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"


def lamp_islands(bm, me):
    idx = {i for i, m in enumerate(me.materials) if m and m.name == "Int_Lumiere"}
    seen = set()
    for f in bm.faces:
        if f in seen or f.material_index not in idx:
            continue
        stack, island = [f], []
        while stack:
            g = stack.pop()
            if g in seen:
                continue
            seen.add(g)
            island.append(g)
            for e in g.edges:
                stack.extend(h for h in e.link_faces if h not in seen and h.material_index in idx)
        yield island


lamps = []      # (centre, axe X, travers, normale radiale, demi-longueur, demi-hauteur)
slimmed = 0
for name in LAMP_OBJECTS:
    o = bpy.data.objects[name]
    me = o.data
    mw, inv = o.matrix_world, o.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(me)
    for island in list(lamp_islands(bm, me)):
        verts = {v for f in island for v in f.verts}
        pts = {v: mw @ v.co for v in verts}
        c = sum(pts.values(), Vector()) / len(pts)
        radial = Vector((0, c.y, c.z)).normalized()
        across = Vector((1, 0, 0)).cross(radial).normalized()
        height = max(p.dot(across) for p in pts.values()) - min(p.dot(across) for p in pts.values())
        if height > LAMP_HEIGHT + 0.01:
            s = LAMP_HEIGHT / height
            for v, p in pts.items():
                d = (p - c).dot(across)
                v.co = inv @ (p - across * d * (1 - s))
            slimmed += 1
            height = LAMP_HEIGHT
        length = max(p.x for p in pts.values()) - min(p.x for p in pts.values())
        lamps.append((c, across, radial, length / 2, height / 2))
    bm.to_mesh(me)
    bm.free()
    me.update()

# Contrôle : rayons lancés depuis toute la face d'une lampe (grille, marge MARGIN) vers l'intérieur du module, sur
# 0,15 m : tout objet touché (autre que le couloir) la recouvre. Une lampe recouverte (par un équipement fixe :
# rangements, casiers, écrans) est déplacée le long du couloir (pas de 5 cm, au plus SHIFT_MAX) jusqu'à la place
# libre la plus proche, sur la paroi du couloir. Les lumières Lum_* (sur l'axe, une par groupe de 4 lampes) ne
# bougent pas : éclairage inchangé.
SHIFT_MAX = 1.6
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()


def blockers(c, across, radial, hl, hh):
    found = set()
    for i in range(21):
        for j in range(7):
            u = -(hl + MARGIN) + 2 * (hl + MARGIN) * i / 20
            w = -(hh + MARGIN) + 2 * (hh + MARGIN) * j / 6
            origin = c + Vector((u, 0, 0)) + across * w - radial * 0.012
            ok, _loc, _n, _i, ob, _m = bpy.context.scene.ray_cast(dg, origin, -radial, distance=0.15)
            if ok and ob.name not in LAMP_OBJECTS:
                found.add(ob.name)
    return found


def wall_depth(x, radial, owner, hl):
    """Distance à l'axe de la paroi du couloir (owner) derrière une lampe centrée en x, si elle est plane sur toute la
    longueur de la lampe, sinon None."""
    depths = []
    for px in (x - hl, x, x + hl):
        ok, loc, _n, _i, ob, _m = bpy.context.scene.ray_cast(dg, Vector((px, 0, 0)), radial)
        if not ok or ob.name != owner:
            return None
        depths.append((loc - Vector((px, 0, 0))).length)
    return depths[1] if max(depths) - min(depths) < 0.01 else None


moved, stuck = [], []
for name in LAMP_OBJECTS:
    o = bpy.data.objects[name]
    me = o.data
    mw, inv = o.matrix_world, o.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(me)
    others = []
    for island in lamp_islands(bm, me):
        others.append(sum((mw @ v.co for f in island for v in f.verts), Vector()) / sum(len(f.verts) for f in island))
    for island in list(lamp_islands(bm, me)):
        verts = {v for f in island for v in f.verts}
        pts = {v: mw @ v.co for v in verts}
        c = sum(pts.values(), Vector()) / len(pts)
        radial = Vector((0, c.y, c.z)).normalized()
        across = Vector((1, 0, 0)).cross(radial).normalized()
        hl = (max(p.x for p in pts.values()) - min(p.x for p in pts.values())) / 2
        hh = LAMP_HEIGHT / 2
        first = blockers(c, across, radial, hl, hh)
        if not first:
            continue
        depth0 = max(p.dot(radial) for p in pts.values())  # dos de la lampe = surface de la paroi
        best = None
        for k in range(1, int(SHIFT_MAX / 0.05) + 1):
            for s in (1, -1):
                dx = s * k * 0.05
                d = wall_depth(c.x + dx, radial, name, hl)
                # Paroi nue au même niveau que le dos de la lampe (une « saillie » serait un élément du couloir :
                # barres, rails…), plane sur toute la longueur.
                if d is None or abs(d - depth0) > 0.015:
                    continue
                c2 = c + Vector((dx, 0, 0))
                far = all(abs((q - c2).x) > 2 * hl + 0.1 or (q - c2).dot(radial) < 0.5 for q in others if (q - c).length > 1e-3)
                if far and not blockers(c2, across, radial, hl, hh):
                    best = c2 - c
                    break
            if best is not None:
                break
        if best is None:
            # Panneau occupé sur toute sa longueur (casiers) : la lampe, invisible, est retirée ; l'éclairage
            # (Lum_* sur l'axe) ne change pas.
            bmesh.ops.delete(bm, geom=island, context='FACES')
            stuck.append((name, round(c.x, 2), round(math.degrees(math.atan2(c.z, c.y)) % 360), sorted(first)))
            continue
        for v, p in pts.items():
            v.co = inv @ (p + best)
        moved.append((name, round(c.x, 2), round(math.degrees(math.atan2(c.z, c.y)) % 360),
                      [round(x, 3) for x in best], sorted(first)))
    bm.to_mesh(me)
    bm.free()
    me.update()
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
overlaps = {}
for name in LAMP_OBJECTS:
    o = bpy.data.objects[name]
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for island in lamp_islands(bm, o.data):
        pts = [o.matrix_world @ v.co for f in island for v in f.verts]
        c = sum(pts, Vector()) / len(pts)
        radial = Vector((0, c.y, c.z)).normalized()
        across = Vector((1, 0, 0)).cross(radial).normalized()
        hl = (max(p.x for p in pts) - min(p.x for p in pts)) / 2
        for ob in blockers(c, across, radial, hl, LAMP_HEIGHT / 2):
            overlaps.setdefault(ob, []).append((round(c.x, 2), round(math.degrees(math.atan2(c.z, c.y)) % 360)))
    bm.free()
bpy.ops.wm.save_mainfile()
result = {"lampes": len(lamps), "affinees": slimmed, "deplacees": moved, "retirees": stuck,
          "recouvrements_restants": overlaps}
