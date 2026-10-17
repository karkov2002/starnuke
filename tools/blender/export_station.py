# Outil hors-jeu : exporte la station du Blender ouvert vers le projet Godot (assets/station/station_spatiale.glb).
# RÈGLE : aucun réexport vers le projet Godot sans le feu vert explicite de l'utilisateur.
# Lancement (Blender ouvert sur E:\Blender\nuke_station.blend, extension MCP de Blender Lab active, port 9876) :
#   & ./tools/blender_exec.ps1 -File tools/blender/export_station.py -TimeoutS 300
# Puis, éditeur Godot ouvert : rescan (MCP rescan_filesystem) ; le .import et tools/import/station_import.gd
# s'appliquent à la réimportation.
# Réglages repris de l'export fait depuis Claude Desktop. À ne pas changer sans raison :
# - export_apply applique les modificateurs, PAS les transformations d'objet : les pivots (Pivot_*, Charniere_*,
#   Radiateur_*_Articulation_*) portent les axes de rotation des animations et des Tweens de station.gd ; ne jamais
#   appliquer leurs rotations ou échelles (Ctrl+A).
# - une piste NLA nommée = une animation ; animations attendues : EXPECTED_ANIMATIONS.
# - custom properties -> glTF « extras » (get_meta("extras") dans Godot) ; suffixes de collision -col et
#   -convcolonly conservés dans les noms ; Draco désactivé (Godot ne le décode pas).
import bpy, os, shutil

DST = r"E:\Projects\starnuke\assets\station"
PATH = os.path.join(DST, "station_spatiale.glb")
NOTICE = r"E:\Blender\LISEZMOI_GODOT.md"
WORK_LIGHTS = ("Soleil", "Reflet_Terre")  # lumières de travail : Godot gère le Soleil et la Terre lui-même
EXPECTED_ANIMATIONS = {"Fermeture_Ecoutilles", "Ouverture_Trappes", "Lancement_Missile", "Balayage_Antennes",
                       "Rotation_Panneaux", "Retraction_Radiateurs"}

# 1) État de scène : pose de repos (image 1), mode objet.
sc = bpy.context.scene
sc.frame_set(1)
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')

# 2) Contrôle des pistes NLA avant export.
tracks = set()
for o in bpy.data.objects:
    if o.animation_data:
        tracks.update(t.name for t in o.animation_data.nla_tracks)
missing = sorted(EXPECTED_ANIMATIONS - tracks)

# 3) Lumières de travail masquées le temps de l'export.
hidden = []
for n in WORK_LIGHTS:
    o = bpy.data.objects.get(n)
    if o and not o.hide_get():
        o.hide_set(True)
        hidden.append(o)

try:
    bpy.ops.export_scene.gltf(
        filepath=PATH,
        export_format='GLB',
        use_visible=True,
        export_cameras=False,
        export_lights=True,                  # lumières intérieures Lum_* (KHR_lights_punctual)
        export_extras=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_force_sampling=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_image_format='AUTO',
        export_draco_mesh_compression_enable=False,
    )
finally:
    # 4) Restauration.
    for o in hidden:
        o.hide_set(False)

shutil.copy(NOTICE, os.path.join(DST, "LISEZMOI_GODOT.md"))
result = {"glb": PATH, "octets": os.path.getsize(PATH), "pistes_nla": sorted(tracks), "animations_manquantes": missing,
          "blend_modifie_non_sauve": bpy.data.is_dirty}
