"""Headless Blender: build a curved wraparound cockpit canopy frame and export GLB.
Run:  "<blender.exe>" --background --python tools/blender_canopy.py

The frame is a front-bulging arc of vertical ribs joined by top/mid/bottom rails,
sized to wrap the cockpit window (~5 m wide, y 1..4, at z=-5). Dark grungy metal with
thin teal accent rails. Godot places it around the window (hub_structure).
Output: assets/generated/interior/cockpit_canopy.glb
"""
import bpy, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(bpy.data.filepath))) if bpy.data.filepath else None
# When run via --python the .blend isn't saved; derive ROOT from this script's dir.
HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else None
PROJECT = os.path.dirname(HERE) if HERE else os.getcwd()
OUT = os.path.join(PROJECT, "assets", "generated", "interior", "cockpit_canopy.glb")

# --- clean scene -----------------------------------------------------------
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

# --- geometry params -------------------------------------------------------
R = 4.6                 # arc radius (bulges forward toward -Z)
CZ = -0.7               # arc centre z (so the front of the arc reaches ~z=-5.3)
Y0, Y1 = 1.0, 4.1       # canopy bottom/top
SPAN = math.radians(58) # half-angle of the wraparound
RIBS = 9
RIB_W, RIB_D = 0.07, 0.13
RAIL_R = 0.06

metal = bpy.data.materials.new("CanopyMetal")
metal.use_nodes = True
bsdf = metal.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.05, 0.06, 0.075, 1.0)
bsdf.inputs["Metallic"].default_value = 0.9
bsdf.inputs["Roughness"].default_value = 0.4

teal = bpy.data.materials.new("CanopyTeal")
teal.use_nodes = True
tb = teal.node_tree.nodes.get("Principled BSDF")
tb.inputs["Base Color"].default_value = (0.2, 0.7, 0.95, 1.0)
tb.inputs["Emission Color"].default_value = (0.2, 0.7, 0.95, 1.0)
tb.inputs["Emission Strength"].default_value = 3.0

parts = []


def arc_point(t):
    return (R * math.sin(t), CZ - R * math.cos(t))


def add_cube(loc, scale, rot=(0, 0, 0), mat=metal):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.rotation_euler = rot
    o.data.materials.append(mat)
    parts.append(o)
    return o


# vertical ribs following the arc, each turned to face the centre
for i in range(RIBS):
    t = -SPAN + (2 * SPAN) * i / (RIBS - 1)
    x, z = arc_point(t)
    add_cube((x, (Y0 + Y1) / 2, z), (RIB_W, (Y1 - Y0) / 2, RIB_D), (0, -t, 0))

# horizontal rails connecting consecutive ribs at 3 heights (teal on the middle)
for yi, yy in enumerate((Y0, (Y0 + Y1) / 2, Y1)):
    for i in range(RIBS - 1):
        t0 = -SPAN + (2 * SPAN) * i / (RIBS - 1)
        t1 = -SPAN + (2 * SPAN) * (i + 1) / (RIBS - 1)
        x0, z0 = arc_point(t0)
        x1, z1 = arc_point(t1)
        mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
        length = math.dist((x0, z0), (x1, z1))
        yaw = math.atan2(x1 - x0, z1 - z0)
        m = teal if yi == 1 else metal
        add_cube((mx, yy, mz), (RAIL_R, RAIL_R, length / 2), (0, yaw, 0), m)

# a chunkier top brow beam over the canopy
for i in range(RIBS - 1):
    t0 = -SPAN + (2 * SPAN) * i / (RIBS - 1)
    t1 = -SPAN + (2 * SPAN) * (i + 1) / (RIBS - 1)
    x0, z0 = arc_point(t0)
    x1, z1 = arc_point(t1)
    mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
    length = math.dist((x0, z0), (x1, z1))
    yaw = math.atan2(x1 - x0, z1 - z0)
    add_cube((mx, Y1 + 0.14, mz), (0.16, 0.16, length / 2 + 0.02), (0, yaw, 0))

# --- join + export ---------------------------------------------------------
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
joined = bpy.context.active_object
joined.name = "CockpitCanopy"

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("CANOPY_EXPORTED", OUT)
