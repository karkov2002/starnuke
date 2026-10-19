# Outil hors-jeu : remplace l'extincteur sommaire du module Arrimage (cylindre rouge Int_Rouge du maillage
# Arrimage_Stockage-col, couché sur la paroi diagonale +Y / plafond) par l'extincteur réaliste de pbr_kit.py
# (objet Arrimage_Extincteur, sans collision), dans E:\Blender\nuke_station.blend (Blender ouvert, extension MCP) :
#   & ./tools/blender_exec.ps1 -TimeoutS 300 -File tools/blender/build_arrimage_extinguisher.py
# Rejouable : le cylindre est retiré une fois (propriété « extincteur_remplace ») ; l'objet est recréé.
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math
from mathutils import Matrix, Vector

exec(open(r"E:\Projects\starnuke\tools\blender\props_kit.py", encoding="utf-8").read())
exec(open(r"E:\Projects\starnuke\tools\blender\pbr_kit.py", encoding="utf-8").read())

SCALE = 1.35                     # extincteur de 9 kg (Ø 0,18 m, 0,66 m hors tout)
STOCK = "Arrimage_Stockage-col"
NAME = "Arrimage_Extincteur"

assert bpy.data.filepath.lower().endswith("nuke_station.blend"), "ouvrir E:\\Blender\\nuke_station.blend"
bpy.context.scene.frame_set(1)
MATS = pbr_materials()


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def add(self, part, key, matrix=Matrix(), smooth=True):
        m = MATS[key]
        if m not in self.slots:
            self.slots.append(m)
        idx = self.slots.index(m)
        bmesh.ops.transform(part, matrix=matrix, verts=part.verts)
        vmap = {v: self.bm.verts.new(v.co) for v in part.verts}
        for f in part.faces:
            try:
                g = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            g.material_index = idx
            g.smooth = smooth
            g.normal_update()
            ax = max(range(3), key=lambda i: abs(g.normal[i]))
            u, v = [i for i in range(3) if i != ax]
            for loop in g.loops:
                loop[self.uv].uv = (loop.vert.co[u], loop.vert.co[v])
        part.free()


stock = bpy.data.objects[STOCK]
removed = "deja"
box = stock.get("extincteur_ancien")
if not stock.get("extincteur_remplace"):
    bm = bmesh.new()
    bm.from_mesh(stock.data)
    M = stock.matrix_world
    red = [i for i, m in enumerate(stock.data.materials) if m and m.name == "Int_Rouge"]
    faces = [f for f in bm.faces if f.material_index in red]
    pts = [M @ v.co for f in faces for v in f.verts]
    box = [min(p.x for p in pts), max(p.x for p in pts), min(p.y for p in pts), max(p.y for p in pts),
           min(p.z for p in pts), max(p.z for p in pts)]
    bmesh.ops.delete(bm, geom=faces, context='FACES')
    bm.to_mesh(stock.data)
    bm.free()
    stock["extincteur_remplace"] = True
    stock["extincteur_ancien"] = box
    removed = len(faces)
box = list(box)

# Paroi derrière l'ancien cylindre : rayon lancé depuis l'axe du module vers le centre de sa boîte.
center = Vector(((box[0] + box[1]) / 2, (box[2] + box[3]) / 2, (box[4] + box[5]) / 2))
out = Vector((0.0, center.y, center.z)).normalized()
dg = bpy.context.evaluated_depsgraph_get()
old = bpy.data.objects.get(NAME)
if old:
    data = old.data
    bpy.data.objects.remove(old)
    bpy.data.meshes.remove(data)
dg.update()
hit, loc, n, *_ = bpy.context.scene.ray_cast(dg, Vector((center.x, 0, 0)), out, distance=3.0)
wall = (loc - Vector((center.x, 0, 0))).dot(out) if hit else 1.25
axis_r = wall - (0.065 + 0.02) * SCALE
length = 0.50 * SCALE
# Couché le long du module (axe Z local → +X monde), dos (+Y local) vers la paroi, pied côté −X.
z_axis = Vector((1.0, 0.0, 0.0))
y_axis = out
x_axis = y_axis.cross(z_axis)
m = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
m.translation = Vector((center.x - length / 2, 0, 0)) + out * axis_r
b = Builder()
build_extinguisher(b, m, SCALE)
me = bpy.data.meshes.new(NAME)
for mat in b.slots:
    me.materials.append(mat)
b.bm.normal_update()
b.bm.to_mesh(me)
b.bm.free()
me.set_sharp_from_angle(angle=math.radians(40))
obj = bpy.data.objects.new(NAME, me)
stock.users_collection[0].objects.link(obj)
bpy.ops.wm.save_mainfile()
result = {"cylindre_retire": removed, "ancien": [round(v, 2) for v in box], "paroi_m": round(wall, 3),
          "origine": [round(v, 3) for v in m.translation]}
