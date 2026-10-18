# Outil hors-jeu : embouchure des tunnels Habitation -> silo dans E:\Blender\nuke_station.blend (Blender ouvert,
# extension MCP de Blender Lab).
#   & ./tools/blender_exec.ps1 -TimeoutS 120 -File tools/blender/fix_missile_tunnels.py
# Défauts corrigés (vus depuis l'intérieur du silo) :
# - le tunnel (Missile_<s>_Tunnel-col, Ø 2,88/3,0 m) dépassait de 1,04 m dans le dôme intérieur (|y| 3,36 -> 4,40) :
#   sa face extérieure (Coque_Silo, non éclairée par les lampes intérieures) formait un contour noir et plat. Il est
#   recoupé au ras du col du dôme intérieur (|y| = NECK_Y) ;
# - la bride extérieure du côté silo (Missile_<s>_Tunnel_Brides, |y| 4,19–4,31) flottait dans le dôme : ramenée
#   dehors, juste avant le dôme (|y| 3,12–3,24) ;
# - collerette Missile_<s>_Collerette_Tunnel-col à l'embouchure (métal intérieur) : boudin arrondi qui couvre la
#   jonction tunnel / dôme, bord rabattu sur le dôme, couronne de vis.
# Rejouable (recoupe et déplacement bornés, collerette recréée). Ne réexporte rien ; enregistre le .blend.
import bpy, bmesh, math
from mathutils import Matrix, Vector

NECK_Y = 3.36            # col du dôme intérieur (rayon 1,5 m)
TUNNEL_END_Y = 4.40      # fin d'origine du tunnel
FLANGE_FROM, FLANGE_TO = 4.19, 3.12   # bride côté silo : début d'origine -> nouveau début
SEGMENTS = 96
BOLTS = 36
DOME_SLOPE = 0.25        # pente du dôme intérieur près du col (dy/dr)
BOLT_SEAT = 0.024       # dessus du bord rabattu au rayon des vis, au-dessus du dôme

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)


def dome_y(r):
    """Surface intérieure du dôme près du col (|y| en fonction du rayon)."""
    return NECK_Y + DOME_SLOPE * (r - 1.5)


# Profil (rayon, |y|) de la collerette, sens trigonométrique dans le plan (r, y) : face côté passage, boudin, bord
# rabattu sur le dôme, retour sous la paroi.
def collar_profile():
    pts = [(1.405, 3.18)]
    # Boudin : quart de cercle (centre 1,475 / 3,43, rayon 0,07) de la face côté passage au dessus.
    for k in range(9):
        a = math.pi - (math.pi / 2) * k / 8
        pts.append((1.475 + 0.07 * math.cos(a), 3.43 + 0.07 * math.sin(a)))
    # Dessus, puis congé vers le bord rabattu.
    for k in range(1, 7):
        a = math.pi / 2 - (math.pi / 2) * k / 6
        pts.append((1.555 + 0.045 * math.cos(a), 3.455 + 0.045 * math.sin(a)))
    r_end = 1.86
    pts += [(1.64, dome_y(1.64) + 0.028), (r_end - 0.012, dome_y(r_end) + 0.022), (r_end, dome_y(r_end) + 0.010),
            (r_end, dome_y(r_end) - 0.02), (1.5, NECK_Y - 0.03), (1.44, 3.18)]
    return pts


def revolve(bm, profile, sign, segments):
    rings = []
    for k in range(segments):
        a = 2 * math.pi * k / segments
        rings.append([bm.verts.new((r * math.cos(a), sign * y, r * math.sin(a))) for r, y in profile])
    n = len(profile)
    for k in range(segments):
        q = (k + 1) % segments
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rings[k][i], rings[k][j], rings[q][j], rings[q][i]))


def build_collar(s, sign, collection):
    name = "Missile_%d_Collerette_Tunnel-col" % s
    old = bpy.data.objects.get(name)
    if old:
        data = old.data
        bpy.data.objects.remove(old)
        bpy.data.meshes.remove(data)
    me = bpy.data.meshes.new(name.replace("-col", ""))
    bm = bmesh.new()
    revolve(bm, collar_profile(), sign, SEGMENTS)
    for f in bm.faces:
        f.smooth = True
    # Vis à tête hexagonale sur le bord rabattu, normale à la pente du dôme.
    normal = Vector((-DOME_SLOPE, 1.0, 0.0)).normalized()
    r_bolt = 1.76
    for k in range(BOLTS):
        a = 2 * math.pi * (k + 0.5) / BOLTS
        head = bmesh.new()
        # Tête hexagonale (1 cm) sur une rondelle (3 mm), posées sur le dessus du bord rabattu.
        bmesh.ops.create_cone(head, cap_ends=True, segments=6, radius1=0.015, radius2=0.015, depth=0.010)
        bmesh.ops.translate(head, vec=(0, 0, 0.008), verts=head.verts)
        washer = bmesh.new()
        bmesh.ops.create_cone(washer, cap_ends=True, segments=20, radius1=0.021, radius2=0.021, depth=0.003)
        bmesh.ops.translate(washer, vec=(0, 0, 0.0015), verts=washer.verts)
        wmap = {v: head.verts.new(v.co) for v in washer.verts}
        for f in washer.faces:
            head.faces.new([wmap[v] for v in f.verts]).material_index = 2
        washer.free()
        # Axe Z de la vis -> normale locale du dôme (dans le plan méridien), puis rotation autour de l'axe du tunnel.
        local_n = Vector((normal.x, normal.y * sign, 0.0))
        m = Matrix.Rotation(-a, 4, 'Y') @ Matrix.Translation((r_bolt, sign * (dome_y(r_bolt) + BOLT_SEAT), 0.0)) \
            @ local_n.to_track_quat('Z', 'Y').to_matrix().to_4x4()
        bmesh.ops.transform(head, matrix=m, verts=head.verts)
        vmap = {v: bm.verts.new(v.co) for v in head.verts}
        for f in head.faces:
            g = bm.faces.new([vmap[v] for v in f.verts])
            g.material_index = f.material_index or 1
        head.free()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Collerette en métal intérieur ; têtes de vis en acier bruni (sombres : sur le métal clair, une tête de même teinte
    # ne laissait voir que ses flancs ombrés) ; rondelles inox.
    for mat in ("Int_Metal", "Int_Bras_Anodise", "Int_PC_Inox"):
        me.materials.append(bpy.data.materials[mat])
    bm.to_mesh(me)
    bm.free()
    me.set_sharp_from_angle(angle=math.radians(40))
    ob = bpy.data.objects.new(name, me)
    collection.objects.link(ob)
    return len(me.polygons)


report = {}
for s, sign in ((1, 1.0), (2, -1.0)):
    tunnel = bpy.data.objects["Missile_%d_Tunnel-col" % s]
    flanges = bpy.data.objects["Missile_%d_Tunnel_Brides" % s]
    moved = trimmed = 0
    for v in tunnel.data.vertices:
        w = tunnel.matrix_world @ v.co
        if abs(w.y) > NECK_Y + 1e-4:
            w.y = sign * NECK_Y
            v.co = tunnel.matrix_world.inverted() @ w
            trimmed += 1
    for v in flanges.data.vertices:
        w = flanges.matrix_world @ v.co
        if abs(w.y) > FLANGE_FROM - 0.05:
            w.y -= sign * (FLANGE_FROM - FLANGE_TO)
            v.co = flanges.matrix_world.inverted() @ w
            moved += 1
    tunnel.data.update()
    flanges.data.update()
    collection = tunnel.users_collection[0]
    report[s] = {"sommets_tunnel_recoupes": trimmed, "sommets_bride_deplaces": moved,
                 "faces_collerette": build_collar(s, sign, collection), "collection": collection.name}
bpy.ops.wm.save_mainfile()
result = {"silos": report, "enregistre": not bpy.data.is_dirty}
