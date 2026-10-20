# Outil hors-jeu : remplace le maillage de la combinaison du sas (Interactif_Combinaison) par le modèle
# « Walking astronaut » (E:\Blender\astronaute\source\Walking astronaut.glb, hors du dépôt), dans
# E:\Blender\nuke_station.blend (Blender ouvert, extension MCP de Blender Lab) :
#   & ./tools/blender_exec.ps1 -TimeoutS 600 -File tools/blender/build_suit_model.py
# À rejouer après build_airlock.py (qui recrée l'ancienne combinaison procédurale). Rejouable.
# - Personnage animé (squelette de 90 os, 4 animations) figé dans sa pose de repos (debout, droit), bras abaissés de
#   ARMS_DOWN depuis la pose en T ; squelette et animations supprimés : la combinaison est un objet statique.
# - Visière : faces noires du casque trouvées par lancer de rayons devant le visage, puis étendues aux faces noires
#   voisines ; matériau Int_Combi_Visiere_Or (pare-soleil doré des sorties extravéhiculaires).
# - Mise à l'échelle sur la hauteur de l'ancienne combinaison, dos contre son support (paroi +Y), face à l'axe (−Y).
# - L'objet garde son nom, ses propriétés (interactif, type, id, porte) et sa collection : station.gd n'y voit rien.
#   L'ancien maillage procédural est gardé hors scène (Interactif_Combinaison_Procedurale, faux utilisateur) : pour
#   revenir en arrière, le réaffecter à l'objet.
# Ne réexporte rien (export_station.py attend le feu vert de l'utilisateur) ; enregistre le .blend.
import bpy, bmesh, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

SRC = r"E:\Blender\astronaute\source\Walking astronaut.glb"
SUIT = "Interactif_Combinaison"
ARMS_DOWN = math.radians(72)    # bras abaissés depuis la pose en T
ARMS_FORWARD = math.radians(12) # puis ramenés vers l'avant (l'épaule est en arrière du torse)
UPPER_ARM, FOREARM = 0.99, 0.825  # bras et avant-bras raccourcis (mains vers le haut des cuisses, plus aux genoux)
VISOR_DEPTH = 0.235             # la visière s'arrête à 23,5 cm sous le sommet du casque (anneau du cou dessous)
HEIGHT = 1.934                   # hauteur de l'ancienne combinaison (m)
DARK = 0.06                      # luminance maximale d'une face de visière (texture de base)
TMP = "Tmp_Astronaute"
BACKUP = "Interactif_Combinaison_Procedurale"   # maillage de build_airlock.py, gardé hors scène

sc = bpy.context.scene
suit = bpy.data.objects[SUIT]

# Ancienne boîte englobante (monde) : position cible.
bb = [suit.matrix_world @ Vector(c) for c in suit.bound_box]
old_min = Vector([min(v[i] for v in bb) for i in range(3)])
old_max = Vector([max(v[i] for v in bb) for i in range(3)])


def remove_collection(name):
    c = bpy.data.collections.get(name)
    if not c:
        return
    for o in list(c.all_objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(c)


# 1) Import dans une collection temporaire.
remove_collection("Import_Astronaute")   # essais d'aperçu
remove_collection(TMP)
tmp = bpy.data.collections.new(TMP)
sc.collection.children.link(tmp)
bpy.context.view_layer.active_layer_collection = bpy.context.view_layer.layer_collection.children[TMP]
before_obj, before_act, before_img, before_mat = (set(bpy.data.objects), set(bpy.data.actions), set(bpy.data.images),
                                                  set(bpy.data.materials))
bpy.ops.import_scene.gltf(filepath=SRC)
new_actions = [a for a in bpy.data.actions if a not in before_act]
new_images = [i for i in bpy.data.images if i not in before_img]
new_mats = [m for m in bpy.data.materials if m not in before_mat]
arm = next(o for o in tmp.all_objects if o.type == "ARMATURE")
parts = [o for o in tmp.all_objects if o.type == "MESH" and o.data.materials and o.find_armature()]

# 2) Pose figée : pose de repos (debout, droite) bras abaissés depuis l'épaule (rotation autour de l'axe avant-arrière
#    de l'armature, pivot à la tête de l'os) ; maillages évalués recopiés en coordonnées monde.
arm.data.pose_position = "POSE"
arm.animation_data_clear()
for pb in arm.pose.bones:
    pb.matrix_basis = Matrix()
for side, sign in (("L_", 1), ("R_", -1)):
    # Armature (en cm) : Z vers le haut, −Y vers l'avant ; en pose en T, le bras suit ±X. Avant-bras du modèle trop
    # long (45 cm pour 32 au bras : mains aux genoux) : chaque os de la chaîne est recalé le long de X (bras et
    # avant-bras raccourcis, main décalée sans changer de taille), puis tout le bras tourne autour de l'épaule.
    shoulder, elbow, wrist = (next(b for b in arm.data.bones if b.name.startswith(side + n)).head_local.copy()
                              for n in ("Arm.", "Elbow.", "Wrist."))
    def along(x, x0=shoulder.x, x1=elbow.x, x2=wrist.x):
        d = sign * (x - x0)                       # distance à l'épaule le long du bras
        e1, e2 = sign * (x1 - x0), sign * (x2 - x0)
        if d <= e1:
            return x0 + sign * d * UPPER_ARM, UPPER_ARM
        if d <= e2:
            return x0 + sign * (e1 * UPPER_ARM + (d - e1) * FOREARM), FOREARM
        return x0 + sign * (e1 * UPPER_ARM + (e2 - e1) * FOREARM + d - e2), 1.0

    rot = (Matrix.Translation(shoulder) @ Matrix.Rotation(-ARMS_FORWARD, 4, "X")
           @ Matrix.Rotation(sign * ARMS_DOWN, 4, "Y") @ Matrix.Translation(-shoulder))
    root = next(p for p in arm.pose.bones if p.name.startswith(side + "Arm."))
    for pb in [root] + [p for p in arm.pose.bones if p.bone in root.bone.children_recursive]:  # parents d'abord
        h = pb.bone.head_local
        x, k = along(h.x)
        squash = Matrix.Diagonal(Vector((k, 1, 1, 1)))
        pb.matrix = (rot @ Matrix.Translation(Vector((x - h.x, 0, 0))) @ Matrix.Translation(h) @ squash
                     @ Matrix.Translation(-h) @ pb.bone.matrix_local)
        bpy.context.view_layer.update()
frame0 = sc.frame_current
dg = bpy.context.evaluated_depsgraph_get()
head_world = arm.matrix_world @ arm.pose.bones[next(b.name for b in arm.pose.bones if b.name.startswith("head"))].head
bm = bmesh.new()
mats = []
for o in parts:
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(o.matrix_world)
    base = len(mats)
    mats += list(me.materials)
    for p in me.polygons:
        p.material_index += base
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
sc.frame_set(frame0)

# 3) Faces détachées dans le fichier source : sommets soudés (les UV restent par coin).
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.faces.ensure_lookup_table()
uv = bm.loops.layers.uv.active


# 4) Visière : luminance de la texture de base sous chaque face.
def base_pixels(mat):
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            links = n.inputs["Base Color"].links
            while links:
                fn = links[0].from_node
                if fn.type == "TEX_IMAGE":
                    w, h = fn.image.size
                    px = np.empty(w * h * 4, dtype=np.float32)
                    fn.image.pixels.foreach_get(px)
                    return px.reshape(h, w, 4), w, h
                links = next((i.links for i in fn.inputs if i.links), None)
    return None


pix = [base_pixels(m) for m in mats]


def luminance(f):
    p = pix[f.material_index]
    if p is None:
        return 1.0
    img, w, h = p
    c = Vector((0, 0))
    for l in f.loops:
        c += l[uv].uv
    c /= len(f.loops)
    rgb = img[int((c.y % 1) * h) % h, int((c.x % 1) * w) % w, :3]
    return float(rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32))


top = max(v.co.z for v in bm.verts)
s = HEIGHT / (top - min(v.co.z for v in bm.verts))
visor_low = top - VISOR_DEPTH / s       # plus bas : anneau du cou, sombre lui aussi


def visor_face(f):
    return f.calc_center_median().z > visor_low and luminance(f) < DARK


bvh = BVHTree.FromBMesh(bm)
seeds = set()
for i in range(-12, 13):
    for k in range(-12, 13):
        o = head_world + Vector((i * 0.012, -0.8, k * 0.012))
        hit = bvh.ray_cast(o, Vector((0, 1, 0)))
        if hit[2] is not None and visor_face(bm.faces[hit[2]]):
            seeds.add(hit[2])
visor, stack = set(seeds), list(seeds)
while stack:
    f = bm.faces[stack.pop()]
    for e in f.edges:
        for g in e.link_faces:
            if g.index not in visor and (g.calc_center_median() - head_world).length < 0.35 and visor_face(g):
                visor.add(g.index)
                stack.append(g.index)

# Le bord bas de la visière est courbe (plus bas au milieu) : la coupe en hauteur en laisse une pointe. Complément par
# la zone de texture : faces sombres du même matériau dont le centre UV tombe dans celle des faces déjà trouvées.
def uv_center(f):
    c = Vector((0, 0))
    for l in f.loops:
        c += l[uv].uv
    return c / len(f.loops)


core = [bm.faces[i] for i in visor]
visor_mat = max({f.material_index for f in core}, key=lambda m: sum(f.material_index == m for f in core))
ucs = [uv_center(f) for f in core if f.material_index == visor_mat]
umin = Vector((min(c.x for c in ucs), min(c.y for c in ucs))) - Vector((0.01, 0.01))
umax = Vector((max(c.x for c in ucs), max(c.y for c in ucs))) + Vector((0.01, 0.01))
for f in bm.faces:
    if f.index in visor or f.material_index != visor_mat:
        continue
    c = uv_center(f)
    if (umin.x <= c.x <= umax.x and umin.y <= c.y <= umax.y and luminance(f) < DARK
            and (f.calc_center_median() - head_world).length < 0.35):
        visor.add(f.index)

gold = bpy.data.materials.get("Int_Combi_Visiere_Or") or bpy.data.materials.new("Int_Combi_Visiere_Or")
gold.use_nodes = True
bsdf = next(n for n in gold.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Base Color"].default_value = (1.0, 0.71, 0.29, 1.0)    # or (réflectance mesurée, sRGB linéaire)
bsdf.inputs["Metallic"].default_value = 0.85     # un peu de diffus : reste doré même sans rien de clair à refléter
bsdf.inputs["Roughness"].default_value = 0.22
gold_index = len(mats)
mats.append(gold)
for i in visor:
    bm.faces[i].material_index = gold_index

# 5) Échelle et place : hauteur de l'ancienne combinaison, centrée en X, dos contre le support, pieds à la même cote.
mn = Vector([min(v.co[i] for v in bm.verts) for i in range(3)])
mx = Vector([max(v.co[i] for v in bm.verts) for i in range(3)])
bmesh.ops.transform(bm, matrix=Matrix.Scale(s, 4), verts=bm.verts)
mn *= s; mx *= s
offset = Vector(((old_min.x + old_max.x) / 2 - (mn.x + mx.x) / 2, old_max.y - mx.y, old_min.z - mn.z))
bmesh.ops.translate(bm, vec=offset, verts=bm.verts)

# 6) Nouveau maillage de la combinaison (objet, propriétés et collection inchangés).
me = bpy.data.meshes.new(SUIT)
bm.to_mesh(me)
bm.free()
for m in mats:
    me.materials.append(m)
me.shade_smooth()
old = suit.data
suit.data = me
if BACKUP in bpy.data.meshes:
    bpy.data.meshes.remove(old)          # rejeu : l'ancienne combinaison procédurale est déjà gardée
else:
    old.name = BACKUP                    # gardée hors scène (faux utilisateur) : retour arrière possible
    old.use_fake_user = True

# Noms stables (Int_Combi_Astro_<n>, Combi_Astro_<n>) : ceux d'un passage précédent, désormais orphelins, sont
# supprimés d'abord. Les noms des images deviennent ceux des textures exportées (station_spatiale_Combi_Astro_*).
for coll_, items, prefix, src in ((bpy.data.materials, new_mats, "Int_Combi_Astro_", "Material_"),
                                  (bpy.data.images, new_images, "Combi_Astro_", "Image_")):
    for x in [x for x in coll_ if x.name.startswith(prefix) and x.users == 0 and x not in items]:
        coll_.remove(x)
    for x in items:
        x.name = prefix + x.name.replace(src, "").replace(".", "_")

# 7) Ménage : squelette, animations et objets importés.
remove_collection(TMP)
for a in new_actions:
    bpy.data.actions.remove(a)
for d in (bpy.data.meshes, bpy.data.armatures):
    for x in [x for x in d if x.users == 0]:
        d.remove(x)

bpy.ops.wm.save_mainfile()
result = {"triangles": sum(len(p.vertices) - 2 for p in me.polygons), "faces_visiere": len(visor),
          "graines_visiere": len(seeds), "echelle": round(s, 4), "materiaux": [m.name for m in me.materials],
          "images": [i.name + " %dx%d" % tuple(i.size) for i in new_images],
          "boite": [[round(c, 3) for c in old_min + Vector()], [round(c, 3) for c in old_max]]}
