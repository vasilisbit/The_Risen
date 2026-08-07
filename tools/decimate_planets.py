"""Decimate the fal.ai planet GLBs in place (headless Blender).

The Tripo image-to-3d planet spheres come in at ~126 k verts / ~10 MB each - far more
than a distant / menu planet needs, and heavy enough to choke Godot's importer. This
collapses each to ~16 k verts (still a smooth sphere at any distance we show it) and
re-exports the GLB with its textures embedded, overwriting the file.

Run:  & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background \
        --python tools/decimate_planets.py
"""
import bpy, os

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "assets", "generated", "planets")
TARGET_VERTS = 16000

for name in ("planet_earth", "planet_mars", "planet_venus"):
    path = os.path.join(BASE, name + ".glb")
    if not os.path.exists(path):
        print("SKIP (missing)", path)
        continue
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    before = sum(len(m.data.vertices) for m in meshes)
    for o in meshes:
        vcount = len(o.data.vertices)
        if vcount > TARGET_VERTS * 1.25:
            bpy.context.view_layer.objects.active = o
            mod = o.modifiers.new("Dec", "DECIMATE")
            mod.decimate_type = "COLLAPSE"
            mod.ratio = min(1.0, float(TARGET_VERTS) / float(vcount))
            bpy.ops.object.modifier_apply(modifier="Dec")
    after = sum(len(m.data.vertices) for m in bpy.data.objects if m.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False)
    print("DONE %s: %d -> %d verts, %d KB" % (name, before, after, os.path.getsize(path) // 1024))

print("ALL DONE")
