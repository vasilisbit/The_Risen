"""Build ONE cohesive grungy curved cockpit interior and export a GLB.

Replaces the procedural box blockout (scripts/hub_structure.gd) + the scattered
fal.ai props that never cohered. A single lofted hull: octagonal/vaulted curved
cross-section swept from a wraparound canopy at the front (-Z, out the window)
back to an enclosed vendor bay, with structural ribs, ceiling light strips, a
raised deck, and a framed windshield. Dressed further in Godot by re-mounting the
kept systems (helm seat, console, hologram table, vendor, mirror).

Authored in GODOT coords (x=width, y=up, -Z=forward/out the window) and converted
on creation to Blender Z-up via (x,y,z)->(x,-z,y), same as tools/blender_canopy.py,
so the export lands upright and correctly oriented in the hub.

Objects are split by material role (Hull / Deck / Ribs / Canopy / CanopyTeal /
Lights) so hub_structure.gd can assign the right material_override to each by node
name after instancing. No textures are baked in — Godot applies the existing
world-triplanar wall-panel material to the hull, which sidesteps glTF UV/tiling.

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background \
      --python tools/blender_ship_interior.py
or exec the file through the live Blender MCP.

Output: assets/generated/interior/ship_interior.glb

Coordinate anchors preserved so the kept systems re-mount unchanged:
  window/canopy front  z = -4.6      seat  (0,0,-3)   eye (0,1.55,-2.6)
  hologram table       origin        spawn (0,1,3)
  vendor / ForgeMaster (0,0,10.5)    rear wall z ~= 13.8   mirror x=-3.85 z=9.5
"""
import bpy, bmesh, math, os

ROOT = r"C:\Users\biovo\Desktop\GitHub Projects\The_Risen"
OUT = os.path.join(ROOT, "assets", "generated", "interior", "ship_interior.glb")

# ---------------------------------------------------------------- scene reset
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete()
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
    for b in list(coll):
        try:
            coll.remove(b)
        except Exception:
            pass


def g2b(g):
    """Godot (x,y,z) -> Blender (x,-z,y)."""
    return (g[0], -g[2], g[1])


# One bmesh per material role.
ROLES = ["Hull", "Deck", "Ribs", "Canopy", "CanopyTeal", "Lights"]
bm = {r: bmesh.new() for r in ROLES}


def V(role, g):
    return bm[role].verts.new(g2b(g))


def quad(role, g0, g1, g2, g3):
    bm[role].faces.new([V(role, g) for g in (g0, g1, g2, g3)])


def ngon(role, gs):
    bm[role].faces.new([V(role, g) for g in gs])


def box(role, cx, cy, cz, sx, sy, sz):
    x0, x1 = cx - sx / 2, cx + sx / 2
    y0, y1 = cy - sy / 2, cy + sy / 2
    z0, z1 = cz - sz / 2, cz + sz / 2
    c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    vs = [V(role, g) for g in c]
    for f in [(0, 1, 2, 3), (7, 6, 5, 4), (4, 5, 1, 0),
              (6, 7, 3, 2), (5, 6, 2, 1), (7, 4, 0, 3)]:
        bm[role].faces.new([vs[i] for i in f])


# ------------------------------------------------------------- hull geometry
WH = 2.3      # wall height before the ceiling chamfer
HC = 4.2      # ceiling shoulder height
APEX = 4.55   # vault apex
CI = 1.15     # ceiling chamfer inset
FRONT_Z = -4.6
REAR_Z = 13.8


def halfwidth(z):
    if z <= 4.0:
        return 5.0
    if z >= 5.6:
        return 4.2
    t = (z - 4.0) / 1.6
    return 5.0 + (4.2 - 5.0) * t


def ring(z):
    """7-point open-bottom cross-section (floor line is the Deck, not here)."""
    w = halfwidth(z)
    wc = w - CI
    return [(-w, 0.0, z), (-w, WH, z), (-wc, HC, z), (0.0, APEX, z),
            (wc, HC, z), (w, WH, z), (w, 0.0, z)]


# Loft the tube (walls + vaulted ceiling), front canopy plane -> rear.
stations = []
z = FRONT_Z
while z < REAR_Z - 1e-4:
    stations.append(z)
    z += 0.8
stations.append(REAR_Z)

for a, b in zip(stations[:-1], stations[1:]):
    ra, rb = ring(a), ring(b)
    for i in range(len(ra) - 1):
        quad("Hull", ra[i], ra[i + 1], rb[i + 1], rb[i])

# Rear bulkhead: close the rear ring into a solid wall (7-gon, floor line closes it).
ngon("Hull", ring(REAR_Z))

# ------------------------------------------------------------------- deck
# Raised deck plate + a central inlaid runner + a couple of plating seams.
box("Deck", 0.0, -0.09, (FRONT_Z + REAR_Z) / 2, 10.6, 0.18, REAR_Z - FRONT_Z + 0.6)
box("Deck", 0.0, 0.02, (FRONT_Z + REAR_Z) / 2, 1.4, 0.04, REAR_Z - FRONT_Z)  # centre runner
for zz in (-1.5, 3.0, 7.5, 11.0):
    box("Deck", 0.0, 0.015, zz, 10.2, 0.03, 0.14)                             # cross seams

# ------------------------------------------------------------- front bulkhead
# Solid frame around the windshield opening x[-3.2,3.2] y[1.1,3.8]; the opening
# itself is left clear so space (and the helm's planet billboards) show through.
WINX = 3.2
WY0, WY1 = 1.1, 3.8
box("Hull", 0.0, WY0 / 2, FRONT_Z, 10.0, WY0, 0.2)                    # sill under window
box("Hull", 0.0, (WY1 + APEX) / 2, FRONT_Z, 2 * WINX, APEX - WY1, 0.2)  # brow over window
for sx in (-1, 1):
    box("Hull", sx * (WINX + (5.0 - WINX) / 2), (WY0 + WY1) / 2, FRONT_Z,
        5.0 - WINX, WY1 - WY0, 0.2)                                   # side panels

# ------------------------------------------------------------------- canopy
# A solid windshield frame bulging forward into the opening: sill/brow trim,
# side pillars, and two mullions splitting it into three panes, plus a teal
# accent line along the brow (reference: the lit canopy edge).
CZ = -4.75
BULGE = 0.65


def zf(x):
    return CZ - BULGE * (1.0 - (x / WINX) ** 2)


SEG = 10
for s in range(SEG):
    x0 = -WINX + 2 * WINX * s / SEG
    x1 = -WINX + 2 * WINX * (s + 1) / SEG
    mx = (x0 + x1) / 2
    box("Canopy", mx, WY0, zf(mx), 2 * WINX / SEG, 0.16, 0.16)         # sill trim
    box("Canopy", mx, WY1, zf(mx), 2 * WINX / SEG, 0.2, 0.2)           # brow trim
    box("CanopyTeal", mx, WY1 + 0.17, zf(mx), 2 * WINX / SEG, 0.05, 0.05)  # teal accent
for x in (-WINX, WINX):
    box("Canopy", x, (WY0 + WY1) / 2, zf(x), 0.2, WY1 - WY0, 0.2)      # A-pillars
for x in (-WINX / 3.0, WINX / 3.0):
    box("Canopy", x, (WY0 + WY1) / 2, zf(x), 0.1, WY1 - WY0, 0.1)      # mullions

# ------------------------------------------------------- ribs + ceiling lights
# Structural rib rings (vertical pilasters + a ceiling brace) at intervals, plus
# an emissive light runner down the vault and two side strips.
for zz in (-3.0, 0.0, 3.0, 6.0, 9.0, 12.0):
    w = halfwidth(zz)
    wc = w - CI
    for sx in (-1, 1):
        box("Ribs", sx * (w - 0.06), WH / 2 + 0.1, zz, 0.12, WH, 0.36)   # wall pilaster
    box("Ribs", 0.0, APEX - 0.1, zz, 2 * wc, 0.16, 0.34)                 # ceiling brace

box("Lights", 0.0, APEX - 0.04, (FRONT_Z + REAR_Z) / 2, 0.28, 0.05, REAR_Z - FRONT_Z - 0.4)
for sx in (-1, 1):
    box("Lights", sx * 3.4, HC + 0.02, (FRONT_Z + REAR_Z) / 2, 0.12, 0.05, REAR_Z - FRONT_Z - 2.0)

# --------------------------------------------------------- finalize objects
placeholder = {}
for r in ROLES:
    m = bpy.data.materials.get(r) or bpy.data.materials.new(r)
    placeholder[r] = m

for r in ROLES:
    b = bm[r]
    bmesh.ops.recalc_face_normals(b, faces=b.faces)
    mesh = bpy.data.meshes.new(r)
    b.to_mesh(mesh)
    b.free()
    mesh.materials.append(placeholder[r])
    obj = bpy.data.objects.new(r, mesh)
    bpy.context.scene.collection.objects.link(obj)

bpy.ops.object.select_all(action="SELECT")
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True)
print("SHIP_INTERIOR_EXPORTED", OUT)
