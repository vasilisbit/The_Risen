#!/usr/bin/env python3
"""Canonicalise a raw fal weapon GLB into Godot convention (headless Blender).

Tripo's `orientation=align_image` leaves the gun sitting at the concept's 3/4
angle (length diagonal in XY). This bakes a clean, predictable pose so ONE grip
transform works for every gun:

    barrel/muzzle -> -X   (matches the Quaternius gun wrappers: -X barrel, Y-up,
                           so the existing player_character.GRIPS rot(90,0,0) and
                           the fp_viewmodel.FRAMING keep working unchanged)
    sight / top   -> +Y   (up)
    thickness     ->  Z
    centred on the origin, principal length scaled to ~TARGET_LEN metres.

Deterministic axis/sign rules (PCA over the mesh):
  - principal axis = longest extent = barrel<->stock.
  - up axis (2nd extent): sign chosen so the LARGER vertical protrusion (the
    magazine/grip) points DOWN (-Y).
  - muzzle end: the length-end with the THINNER mean cross-section (barrel) ->
    faces -Z. Override per gun with --flip-muzzle when a chunky barrel fools it.
  - --flip-up flips the up axis if a gun's mag read is ambiguous.

Run (headless):
    "<blender>" --background --python tools/orient_weapons.py -- auto_rifle
    "<blender>" --background --python tools/orient_weapons.py -- shotgun --flip-muzzle --len 0.7
Reads  assets/generated/weapons/raw/<gun>.glb
Writes assets/generated/weapons/<gun>.glb   (GLB, textures embedded)
"""
import bpy, sys, os, math, numpy as np, mathutils

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(bpy.data.filepath or __file__))) \
    if False else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEAP = os.path.join(ROOT, "assets", "generated", "weapons")

# Per-gun default length in metres (barrel-to-stock). Tuned so each reads to
# scale next to the ~1.8 m Guardian; fine adjustments happen via viewmodel FRAMING.
DEFAULT_LEN = {"auto_rifle": 0.64, "shotgun": 0.62, "sniper": 0.92, "hand_cannon": 0.34}
# Grip pivot as a fraction of length (toward stock +X, below centre -Y), derived
# from the Quaternius Gun_Rifle whose pivot the GRIPS/FRAMING were tuned against.
GRIP_FRAC = {"auto_rifle": (0.227, -0.110), "shotgun": (0.227, -0.110),
             "sniper": (0.30, -0.110), "hand_cannon": (0.12, -0.16)}


def argv():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    gun = a[0] if a else "auto_rifle"
    flip_muzzle = "--flip-muzzle" in a
    flip_up = "--flip-up" in a
    length = DEFAULT_LEN.get(gun, 0.64)
    if "--len" in a:
        length = float(a[a.index("--len") + 1])
    return gun, flip_muzzle, flip_up, length


def main():
    gun, flip_muzzle, flip_up, target_len = argv()
    raw = os.path.join(WEAP, "raw", f"{gun}.glb")
    out = os.path.join(WEAP, f"{gun}.glb")
    if not os.path.exists(raw):
        print("MISSING", raw); return

    bpy.ops.wm.read_homefile(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=raw)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("NO-MESH"); return
    # Join to one object so the whole gun transforms together.
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active

    mw = ob.matrix_world.copy()
    vs = np.array([(mw @ v.co)[:] for v in ob.data.vertices])
    c = vs.mean(axis=0)
    X = vs - c
    cov = np.cov(X.T)
    w, V = np.linalg.eigh(cov)
    order = np.argsort(w)[::-1]
    L = V[:, order[0]] / np.linalg.norm(V[:, order[0]])  # length
    U = V[:, order[1]] / np.linalg.norm(V[:, order[1]])  # up/down

    pL = X @ L
    pU = X @ U

    # up sign: put the bigger vertical protrusion (mag/grip) DOWN (-Y)
    if abs(pU.max()) > abs(pU.min()):
        U = -U
        pU = -pU
    if flip_up:
        U = -U; pU = -pU

    # muzzle sign: thinner length-end (barrel) faces -X, so back(stock, thicker)->+X
    def radial(mask):
        sub = X[mask]
        perp = sub - np.outer(sub @ L, L)
        return math.sqrt((perp ** 2).sum(axis=1).mean())
    r_hi = radial(pL > np.quantile(pL, 0.85))
    r_lo = radial(pL < np.quantile(pL, 0.15))
    # x_src(+X=back/stock) points to the THICKER end; muzzle (thinner) -> -X
    x_src = L if r_hi >= r_lo else -L
    if flip_muzzle:
        x_src = -x_src

    # Orthonormal source frame -> world axes; R rows map src basis to X/Y/Z.
    # up -> +Y, back -> +X (muzzle -X), thickness -> +Z (right-handed).
    y_src = U - (U @ x_src) * x_src
    y_src /= np.linalg.norm(y_src)
    z_src = np.cross(x_src, y_src)
    z_src /= np.linalg.norm(z_src)
    R = np.array([x_src, y_src, z_src])

    length = (X @ L).max() - (X @ L).min()
    scale = target_len / length
    new = (R @ X.T).T * scale
    # Move the origin to the GRIP (not the bbox centre) so the socket + the
    # existing GRIPS rot(90,0,0) place the gun exactly like the Quaternius rifle
    # they were tuned for: its pivot sits +0.227*len toward the stock (+X) and
    # -0.110*len below centre (-Y). Per-gun nudges still go through GRIPS["pos"].
    gx, gy = GRIP_FRAC.get(gun, (0.227, -0.110))
    new = new - np.array([gx * target_len, gy * target_len, 0.0])
    me = ob.data
    for i, co in enumerate(new):
        me.vertices[i].co = mathutils.Vector((float(co[0]), float(co[1]), float(co[2])))
    me.update()
    ob.matrix_world = mathutils.Matrix.Identity(4)

    vs2 = np.array([v.co[:] for v in me.vertices])
    size = (vs2.max(axis=0) - vs2.min(axis=0))
    print("SIZE", [round(float(s), 3) for s in size],
          "x", [round(float(vs2[:, 0].min()), 3), round(float(vs2[:, 0].max()), 3)],
          "y", [round(float(vs2[:, 1].min()), 3), round(float(vs2[:, 1].max()), 3)])

    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # The mesh is already posed in glTF/Godot axes (up=+Y, muzzle=-Z) inside
    # Blender space, so write axes literally -- yup conversion would re-rotate it.
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_yup=False)
    print("WROTE", out)


main()
