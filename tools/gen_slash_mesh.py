"""Build the melee slash crescent mesh (docs/VFX_WORKFLOW.md). A tapered curved
arc ribbon (fat in the middle, pointed at both ends) in the local XY plane, so a
scroll/gradient material sweeps a glowing energy arc along it. Reconciled VFX
study §11.4: the simple VFX meshes are Blender, not Tripo.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python tools/gen_slash_mesh.py

Exports assets/generated/vfx/slash_arc.glb (unit-ish, ~2 m wide), consumed by
scripts/vfx_kit.gd (slash()).
"""
import bpy, bmesh, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "vfx", "slash_arc.glb")

N = 48                       # segments along the arc
SPAN = math.radians(155)     # arc sweep angle
RC = 1.0                     # centre-line radius
WMAX = 0.55                  # max ribbon width (middle)

bpy.ops.wm.read_factory_settings(use_empty=True)
mesh = bpy.data.meshes.new("slash_arc")
obj = bpy.data.objects.new("slash_arc", mesh)
bpy.context.collection.objects.link(obj)

bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")
cols = []  # (inner_vert, outer_vert, t)
for i in range(N + 1):
    t = i / N
    ang = -SPAN / 2 + SPAN * t
    w = WMAX * math.sin(math.pi * t)          # taper to 0 at both ends -> crescent
    ri, ro = RC - w / 2, RC + w / 2
    s, c = math.sin(ang), math.cos(ang)
    vi = bm.verts.new((s * ri, c * ri, 0.0))
    vo = bm.verts.new((s * ro, c * ro, 0.0))
    cols.append((vi, vo, t))

for i in range(N):
    vi0, vo0, t0 = cols[i]
    vi1, vo1, t1 = cols[i + 1]
    f = bm.faces.new((vi0, vo0, vo1, vi1))
    uvs = {vi0: (t0, 0.0), vo0: (t0, 1.0), vo1: (t1, 1.0), vi1: (t1, 0.0)}
    for loop in f.loops:
        loop[uvl].uv = uvs[loop.vert]

bm.normal_update()
bm.to_mesh(mesh)
bm.free()

# Center the origin on the mesh bounds so VfxKit can place it predictably.
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
obj.location = (0.0, 0.0, 0.0)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                          export_apply=True)
print("EXPORTED", OUT)
