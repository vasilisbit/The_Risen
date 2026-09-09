"""Headless render-check for a generated enemy GLB.
  blender --background --python tools/blender_enemy_check.py -- <glb> <out_png> [<out_png_back>]
Imports the GLB, frames it, renders front (and optional back) to PNG, prints stats.
"""
import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
glb = argv[0]
out_front = argv[1]
out_back = argv[2] if len(argv) > 2 else None

bpy.ops.wm.read_homefile(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
tris = 0
mn = [1e9] * 3; mx = [-1e9] * 3
for o in objs:
    o.data.calc_loop_triangles()
    tris += len(o.data.loop_triangles)
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i]); mx[i] = max(mx[i], w[i])
size = [mx[i] - mn[i] for i in range(3)]
ctr = [(mx[i] + mn[i]) / 2 for i in range(3)]
print("STATS meshes=%d tris=%d size x=%.2f y=%.2f z=%.2f" % (len(objs), tris, *size), flush=True)
anims = list(bpy.data.actions)
print("ACTIONS", [a.name for a in anims], flush=True)
print("OBJECTS", [(o.name, o.type) for o in bpy.context.scene.objects], flush=True)

# world + light
world = bpy.data.worlds.new("W"); world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.06, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
bpy.context.scene.world = world
for ang, e in [((0.9, 0, 0.6), 4.0), ((0.6, 0, -1.2), 2.5)]:
    l = bpy.data.lights.new("L", 'SUN'); l.energy = e
    lo = bpy.data.objects.new("Lo", l); bpy.context.collection.objects.link(lo)
    lo.rotation_euler = ang

scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'CYCLES'
scene.render.resolution_x = 800; scene.render.resolution_y = 1000
scene.render.film_transparent = False

cam_data = bpy.data.cameras.new("C"); cam = bpy.data.objects.new("C", cam_data)
bpy.context.collection.objects.link(cam); scene.camera = cam
reach = max(size) * 1.6 + 1.0

def shot(path, front=True):
    y = -reach if front else reach
    cam.location = (ctr[0], ctr[1] + y, ctr[2] + size[2] * 0.05)
    d = mathutils.Vector((ctr[0], ctr[1], ctr[2])) - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("WROTE", path, flush=True)

shot(out_front, True)
if out_back:
    shot(out_back, False)
