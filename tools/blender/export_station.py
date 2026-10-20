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
# - textures sorties du .glb après l'export (externalize_images) : fichiers station_spatiale_<image>.png/.jpg
#   versionnés à côté, réécrits seulement s'ils changent (Git LFS ne stocke ainsi que les textures modifiées).
import bpy, os, shutil, json, struct, urllib.parse

DST = r"E:\Projects\starnuke\assets\station"
PATH = os.path.join(DST, "station_spatiale.glb")
NOTICE = r"E:\Blender\LISEZMOI_GODOT.md"
WORK_LIGHTS = ("Soleil", "Reflet_Terre")  # lumières de travail : Godot gère le Soleil et la Terre lui-même
EXPECTED_ANIMATIONS = {"Fermeture_Ecoutilles", "Ouverture_Trappes", "Lancement_Missile", "Balayage_Antennes",
                       "Rotation_Panneaux", "Retraction_Radiateurs", "Separation_Cargo",
                       "Depressurisation_Sas"}

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



# 5) Textures sorties du .glb (fichiers à côté, référencés par URI) : une texture inchangée ne coûte rien de plus
#    dans Git LFS d'un réexport à l'autre. Noms = ceux de l'extraction de Godot (station_spatiale_<image>.<ext>),
#    dont les .import versionnés (UID, compression, normal map) restent valables.
def externalize_images(glb_path):
    with open(glb_path, "rb") as f:
        data = f.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + jlen])
    bin_start = 20 + jlen + 8
    views = gltf["bufferViews"]
    prefix = os.path.splitext(os.path.basename(glb_path))[0] + "_"
    ext_of = {"image/png": ".png", "image/jpeg": ".jpg"}
    written, kept, used = 0, 0, set()
    for img in gltf.get("images", []):
        if "bufferView" not in img:
            continue
        v = views[img.pop("bufferView")]
        start = bin_start + v.get("byteOffset", 0)
        blob = data[start:start + v["byteLength"]]
        name = prefix + img["name"] + ext_of[img.pop("mimeType")]
        assert name not in used, "deux images du même nom : " + name
        used.add(name)
        dst = os.path.join(DST, name)
        if os.path.exists(dst) and open(dst, "rb").read() == blob:
            kept += 1  # fichier inchangé : pas de réimport ni de nouvel objet LFS
        else:
            with open(dst, "wb") as f:
                f.write(blob)
            written += 1
        img["uri"] = urllib.parse.quote(name)

    # Tampon binaire recompacté sans les images ; bufferViews renumérotées.
    referenced = {a["bufferView"] for a in gltf.get("accessors", []) if "bufferView" in a}
    for a in gltf.get("accessors", []):
        sp = a.get("sparse")
        if sp:
            referenced |= {sp["indices"]["bufferView"], sp["values"]["bufferView"]}
    remap, new_views, out = {}, [], bytearray()
    for i, v in enumerate(views):
        if i not in referenced:
            continue
        start = bin_start + v.get("byteOffset", 0)
        out += b"\0" * (-len(out) % 4)
        nv = dict(v, byteOffset=len(out))
        out += data[start:start + v["byteLength"]]
        remap[i] = len(new_views)
        new_views.append(nv)
    for a in gltf.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
        sp = a.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    gltf["bufferViews"] = new_views
    out += b"\0" * (-len(out) % 4)
    gltf["buffers"][0]["byteLength"] = len(out)

    js = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    js += b" " * (-len(js) % 4)
    with open(glb_path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(out), 0x004E4942) + out)

    # Textures d'un export précédent qui ne servent plus.
    removed = []
    for fn in os.listdir(DST):
        if fn.startswith(prefix) and os.path.splitext(fn)[1] in (".png", ".jpg") and fn not in used:
            os.remove(os.path.join(DST, fn))
            if os.path.exists(os.path.join(DST, fn + ".import")):
                os.remove(os.path.join(DST, fn + ".import"))
            removed.append(fn)
    return {"ecrites": written, "inchangees": kept, "retirees": removed}


textures = externalize_images(PATH)
shutil.copy(NOTICE, os.path.join(DST, "LISEZMOI_GODOT.md"))
result = {"glb": PATH, "octets": os.path.getsize(PATH), "textures": textures, "pistes_nla": sorted(tracks),
          "animations_manquantes": missing, "blend_modifie_non_sauve": bpy.data.is_dirty}
