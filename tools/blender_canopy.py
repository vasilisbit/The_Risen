"""Headless Blender: build a bold curved cockpit canopy / windshield frame and export
GLB.  Run:  "<blender.exe>" --background --python tools/blender_canopy.py

The frame sits JUST INSIDE the cockpit window (opening x[-2.5,2.5], y[1,4] at z=-5),
framing it from the interior. It bulges forward in the middle (a shallow parabola in
XZ) for a canopy read: thick side pillars, vertical mullions, top/mid/bottom rails and
a chunky brow beam. Dark grungy metal with a teal accent mid-rail.
Output: assets/generated/interior/cockpit_canopy.glb
"""
import bpy, math, os

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd()
PROJECT = os.path.dirname(HERE)
OUT = os.path.join(PROJECT, "assets", "generated", "interior", "cockpit_canopy.glb")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

# window frame geometry
HW = 2.85              # half width of the frame (a bit wider than the opening)
Y0, Y1 = 0.8, 4.25     # sill / brow heights
ZBASE = -4.45          # frame z at the sides (just inside the window)
BULGE = 0.85           # how far the centre bulges forward (toward -Z)


def zf(x):
    # shallow forward parabola: centre bulges to ZBASE-BULGE, sides at ZBASE
    return ZBASE - BULGE * (1.0 - (x / HW) ** 2)


def mat(name, rgb, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = 0.9
    b.inputs["Roughness"].default_value = 0.42
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*rgb, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    return m


METAL = mat("CanopyMetal", (0.055, 0.065, 0.08))
TEAL = mat("CanopyTeal", (0.2, 0.72, 0.95), emit=4.0)
parts = []


def cube(g_loc, g_scale, g_yaw=0.0, m=METAL):
    # Inputs are in GODOT coords (x=width, y=height, z=depth toward -Z). glTF export
    # converts Blender Z-up -> Y-up, so build in Blender coords: (x, -z, y), and a yaw
    # about Godot's up (Y) becomes a rotation about Blender's up (Z).
    b_loc = (g_loc[0], -g_loc[2], g_loc[1])
    b_scale = (g_scale[0], g_scale[2], g_scale[1])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=b_loc)
    o = bpy.context.active_object
    o.scale = b_scale
    o.rotation_euler = (0, 0, g_yaw)
    o.data.materials.append(m)
    parts.append(o)


def beam_along(x0, x1, y, thick, m=METAL):
    # a horizontal beam following the curve between two x positions at height y
    z0, z1 = zf(x0), zf(x1)
    mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
    length = math.dist((x0, z0), (x1, z1))
    yaw = math.atan2(x1 - x0, z1 - z0)
    cube((mx, y, mz), (thick, thick, length / 2 + thick), yaw, m)


# vertical mullions (outer two are the thick pillars)
xs = [-HW, -HW / 2, 0.0, HW / 2, HW]
for i, x in enumerate(xs):
    thick = 0.16 if i in (0, len(xs) - 1) else 0.09
    cube((x, (Y0 + Y1) / 2, zf(x)), (thick, (Y1 - Y0) / 2, thick))

# horizontal rails at sill / middle (teal) / brow, following the curve
seg = 10
for yi, y in enumerate((Y0, (Y0 + Y1) / 2, Y1)):
    m = TEAL if yi == 1 else METAL
    thick = 0.07 if yi == 1 else 0.11
    for s in range(seg):
        x0 = -HW + (2 * HW) * s / seg
        x1 = -HW + (2 * HW) * (s + 1) / seg
        beam_along(x0, x1, y, thick, m)

# chunky brow beam over the top
for s in range(seg):
    x0 = -HW + (2 * HW) * s / seg
    x1 = -HW + (2 * HW) * (s + 1) / seg
    beam_along(x0, x1, Y1 + 0.18, 0.2)

# join + export
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
bpy.context.active_object.name = "CockpitCanopy"

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("CANOPY_EXPORTED", OUT)
