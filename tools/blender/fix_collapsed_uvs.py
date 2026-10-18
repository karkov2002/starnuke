# Outil Blender (session ouverte sur E:\Blender\nuke_station.blend, via tools/blender_exec.ps1 -File) : déplie les
# faces « sans coordonnées de texture » des matériaux à texture de relief (normal map).
#
# Symptôme corrigé : une face dont tous les coins ont la même coordonnée UV n'a pas de tangente valide ; dans Godot,
# la normal map l'éclaire alors n'importe comment (porte de l'écoutille du cargo sombre de près et claire de loin :
# les LOD générés à l'import, vus de loin, passent par d'autres sommets).
#
# Pour chaque face fautive (aire UV nulle, matériau avec un nœud Normal Map) : projection « en boîte » sur l'axe
# dominant de sa normale, en coordonnées du monde (la texture se raccorde d'un objet à l'autre), à la densité des faces
# déjà dépliées du même matériau (TILE_M par défaut si aucune). Seules ces faces sont touchées ; les autres gardent
# leurs UV. MODE = "report" : liste seulement ; "apply" : déplie. Le code assigne result (tools/blender_exec.ps1).
import bpy
import math
from mathutils import Vector

MODE = "apply"
TILE_M = 1.0
MIN_FACE_AREA = 1e-6


def has_normal_map(material):
    return material is not None and material.node_tree is not None and any(
        node.type == "NORMAL_MAP" for node in material.node_tree.nodes)


def uv_area(uv_layer, polygon):
    uvs = [uv_layer.data[li].uv for li in polygon.loop_indices]
    return abs(sum(uvs[i].x * uvs[(i + 1) % len(uvs)].y - uvs[(i + 1) % len(uvs)].x * uvs[i].y
                   for i in range(len(uvs)))) * 0.5


def meshes():
    for obj in bpy.data.objects:
        if obj.type == "MESH" and not obj.name.endswith("colonly") and obj.data.uv_layers.active:
            yield obj


# 1. Densité de texture par matériau (UV par m², sur les faces correctes, en surface monde).
density = {}
for obj in meshes():
    scale = abs(obj.matrix_world.to_3x3().determinant()) ** (2.0 / 3.0)
    uv_layer = obj.data.uv_layers.active
    for polygon in obj.data.polygons:
        material = obj.material_slots[polygon.material_index].material if obj.material_slots else None
        if not has_normal_map(material) or polygon.area < MIN_FACE_AREA:
            continue
        area = uv_area(uv_layer, polygon)
        if area > 1e-9:
            d = density.setdefault(material.name, [0.0, 0.0])
            d[0] += area
            d[1] += polygon.area * scale
tile = {name: (1.0 / math.sqrt(d[0] / d[1]) if d[0] > 0.0 else TILE_M) for name, d in density.items()}

# 2. Faces fautives, dépliées en boîte (coordonnées du monde).
fixed = {}
for obj in meshes():
    mesh = obj.data
    uv_layer = mesh.uv_layers.active
    to_world = obj.matrix_world
    normal_matrix = to_world.to_3x3().inverted().transposed()
    count = 0
    for polygon in mesh.polygons:
        material = obj.material_slots[polygon.material_index].material if obj.material_slots else None
        if not has_normal_map(material) or polygon.area < MIN_FACE_AREA or uv_area(uv_layer, polygon) > 1e-9:
            continue
        count += 1
        if MODE != "apply":
            continue
        size = tile.get(material.name, TILE_M)
        n = (normal_matrix @ polygon.normal).normalized()
        axis = max(range(3), key=lambda i: abs(n[i]))
        for li in polygon.loop_indices:
            p = to_world @ mesh.vertices[mesh.loops[li].vertex_index].co
            if axis == 0:
                u, v = (p.y if n.x > 0 else -p.y), p.z
            elif axis == 1:
                u, v = (-p.x if n.y > 0 else p.x), p.z
            else:
                u, v = p.x, (p.y if n.z > 0 else -p.y)
            uv_layer.data[li].uv = (u / size, v / size)
    if count:
        fixed[obj.name] = count
        if MODE == "apply":
            mesh.update()

result = {"mode": MODE, "objects": len(fixed), "faces": sum(fixed.values()),
          "tile_m": {k: round(v, 3) for k, v in tile.items()},
          "top": sorted(fixed.items(), key=lambda kv: -kv[1])[:12]}
