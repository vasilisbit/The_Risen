"""Build the cockpit canopy / windshield frame and export GLB.

Runs either headless (`blender.exe --background --python tools/blender_canopy.py`)
or pasted through the live Blender MCP `execute_blender_code`. A SOLID frame around
the cockpit window (opening x[-2.5,2.5], y[1,4] at z=-5): chunky brow + sill + side
pillars, two mullions + one mid-divider splitting it into panes, a subtle teal accent
along the brow. Hull-matching gunmetal (NOT near-black) so it doesn't read as harsh
black/white lines. Bulges forward in the middle for a canopy read.

Godot is Y-up, Blender Z-up: geometry is authored in GODOT coords and converted on
creation (loc (x,y,z)->(x,-z,y)), so the export lands upright at the window.
Output: assets/generated/interior/cockpit_canopy.glb
"""
import bpy, math, os

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd()
OUT = os.path.join(os.path.dirname(HERE), "assets", "generated", "interior", "cockpit_canopy.glb")

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

HW = 2.75
Y0, Y1 = 0.85, 4.2
ZBASE = -4.5
BULGE = 0.8


def zf(x):
    return ZBASE - BULGE * (1.0 - (x / HW) ** 2)


def mat(name, rgb, metallic=0.85, rough=0.4, emit=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*rgb, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    return m


METAL = mat("CanopyMetal", (0.19, 0.20, 0.23))
TEAL = mat("CanopyTeal", (0.15, 0.55, 0.72), emit=1.4)
parts = []


def cube(g_loc, g_scale, g_yaw=0.0, m=METAL):
    # Godot (x=width,y=height,z=depth) -> Blender (x,-z,y); yaw about Godot Y -> Blender Z
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(g_loc[0], -g_loc[2], g_loc[1]))
    o = bpy.context.active_object
    o.scale = (g_scale[0], g_scale[2], g_scale[1])
    o.rotation_euler = (0, 0, g_yaw)
    o.data.materials.append(m)
    parts.append(o)


def beam(x0, x1, y, thick, m=METAL, dy=0.0):
    z0, z1 = zf(x0), zf(x1)
    mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
    length = math.dist((x0, z0), (x1, z1))
    yaw = math.atan2(x1 - x0, z1 - z0)
    cube((mx, y + dy, mz), (thick, thick, length / 2 + thick), yaw, m)


SEG = 12
for s in range(SEG):
    x0 = -HW + 2 * HW * s / SEG
    x1 = -HW + 2 * HW * (s + 1) / SEG
    beam(x0, x1, Y0, 0.16)                       # sill
    beam(x0, x1, Y1, 0.22)                       # chunky brow
    beam(x0, x1, Y1 + 0.02, 0.05, TEAL, dy=0.16) # thin teal accent along the brow
    beam(x0, x1, (Y0 + Y1) / 2, 0.1)             # mid divider
for x in (-HW, HW):                              # thick side pillars
    cube((x, (Y0 + Y1) / 2, zf(x)), (0.22, (Y1 - Y0) / 2, 0.22))
for x in (-HW / 3.0, HW / 3.0):                  # two interior mullions
    cube((x, (Y0 + Y1) / 2, zf(x)), (0.11, (Y1 - Y0) / 2, 0.11))

for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
bpy.context.active_object.name = "CockpitCanopy"
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("CANOPY_EXPORTED", OUT)
