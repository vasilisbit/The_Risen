"""Blender-side cleanup + animation merge for the T-0044 enemies. Runs inside Blender
(via the MCP `execute_blender_code`  ->  exec(open(THIS).read()); merge_enemy(...)  ,
or headless: `blender --background --python tools/merge_enemy_anim.py -- <key> ...`).

Per enemy it takes the Meshy-rigged base GLB (mesh + rig + baked idle, from
gen_enemies.py --stage rig) and merges in extra clips (its own walk, plus the shared
melee `attack` for melee enemies), producing the drop-in assets/generated/enemies/<key>.glb
with a clean AnimationPlayer (idle + walk [+ attack]) that EnemyBase._wire_model_animation
drives. Also: strips the Meshy bone-widget icosphere, renames clips, neutralizes root
drift (in-place locomotion/attack, since Godot drives position), and dials the
emission-from-albedo strength down so only the teal soulfire glows (not the whole body).

CLIP SPECS: list of (src_glb, name, neutralize_root). name in {walk, attack, ...}.
"""
import bpy, os

EMISSION_DEFAULT = 0.35
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in dir() else \
    r"C:\Users\biovo\Desktop\GitHub Projects\The_Risen"
ENE = os.path.join(ROOT, "assets", "generated", "enemies")
RAW = os.path.join(ENE, "raw")


def _ctx():
    """A VIEW_3D override so the glTF importer has a valid context under the MCP; {} when
    headless (import works without it there)."""
    try:
        for win in bpy.context.window_manager.windows:
            for area in win.screen.areas:
                if area.type == 'VIEW_3D':
                    region = next((r for r in area.regions if r.type == 'WINDOW'), None)
                    if region:
                        return dict(window=win, area=area, region=region)
    except Exception:
        pass
    return {}


def _import(path):
    with bpy.context.temp_override(**_ctx()):
        bpy.ops.import_scene.gltf(filepath=path)


def _cbfc(act):
    """fcurves of a Blender 5.x slotted action."""
    out = []
    for lay in act.layers:
        for st in lay.strips:
            for cb in st.channelbags:
                out.extend(cb.fcurves)
    return out


def _neutralize_root(act):
    """Zero the Hips horizontal translation (axes 0,1) so the clip plays in place; keep
    the vertical (axis 2) bob/crouch."""
    for fc in _cbfc(act):
        if fc.data_path.endswith('"Hips"].location') and fc.array_index in (0, 1):
            v0 = fc.keyframe_points[0].co[1]
            for kp in fc.keyframe_points:
                kp.co[1] = v0; kp.handle_left[1] = v0; kp.handle_right[1] = v0


def _rename_base_actions():
    """Map the imported base action name(s) to idle/walk. Meshy's idle imports as
    'Armature|Idle|baselayer'; an already-merged base may already have idle+walk."""
    for a in bpy.data.actions:
        low = a.name.lower()
        if "idle" in low:
            a.name = "idle"
        elif "walk" in low:
            a.name = "walk"
        a.use_fake_user = True
    # single unknown action -> idle
    if len(bpy.data.actions) == 1 and bpy.data.actions[0].name not in ("idle", "walk"):
        bpy.data.actions[0].name = "idle"; bpy.data.actions[0].use_fake_user = True


def _strip_widgets():
    """Remove the Meshy bone-widget icospheres (clear custom_shape refs + delete tiny
    meshes) so nothing extra rides along."""
    for o in bpy.context.scene.objects:
        if o.type == 'ARMATURE':
            for pb in o.pose.bones:
                pb.custom_shape = None
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and len(o.data.vertices) < 500:
            bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        if 'not_exported' in c.name:
            bpy.data.collections.remove(c)


def merge_enemy(key, clip_specs, emission=EMISSION_DEFAULT):
    base = os.path.join(ENE, f"{key}.glb")
    assert os.path.exists(base), f"missing base rig {base} (run gen_enemies.py --stage rig)"
    bpy.ops.wm.read_homefile(use_empty=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)

    _import(base)
    _rename_base_actions()
    _strip_widgets()
    base_objs = set(bpy.context.scene.objects)
    base_arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')

    for src, name, neutralize in clip_specs:
        assert os.path.exists(src), f"missing clip {src}"
        known = set(bpy.data.actions)
        _import(src)
        new_objs = [o for o in bpy.context.scene.objects if o not in base_objs]
        new_acts = [a for a in bpy.data.actions if a not in known]
        if new_acts:
            act = new_acts[0]
            act.name = name
            act.use_fake_user = True
            if neutralize:
                _neutralize_root(act)
        for o in new_objs:
            try:
                bpy.data.objects.remove(o, do_unlink=True)
            except Exception:
                pass
    _strip_widgets()

    # emission-from-albedo -> only the teal reads as glow, not the whole body
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    n.inputs['Emission Strength'].default_value = emission

    if not base_arm.animation_data:
        base_arm.animation_data_create()
    idle = bpy.data.actions.get("idle")
    if idle:
        base_arm.animation_data.action = idle
        try:
            base_arm.animation_data.action_slot = idle.slots[0]
        except Exception:
            pass

    with bpy.context.temp_override(**_ctx()):
        bpy.ops.export_scene.gltf(filepath=base, export_format='GLB',
                                  export_animations=True, export_animation_mode='ACTIONS',
                                  export_apply=False, use_selection=False)
    print(f"MERGED {key}: actions={[a.name for a in bpy.data.actions]} -> {base} "
          f"({os.path.getsize(base)} bytes)", flush=True)
    return base


# Which clips each enemy gets. walk = its own basic_animations; attack = the shared
# rusher melee scout (same Meshy skeleton). Only rusher/shielded_brute get a melee attack
# (shooter's fire clips read as acrobatic dodges -> deferred; exploder/phantom/tyrant run
# their own sequences and never call play_attack_animation).
ATTACK_SRC = os.path.join(RAW, "rusher_move_attack.glb")

def specs_for(key):
    walk = os.path.join(RAW, f"{key}_walking_glb.glb")
    if key == "rusher":            # base already has idle+walk merged
        return [(ATTACK_SRC, "attack", True)]
    if key == "shielded_brute":
        return [(walk, "walk", True), (ATTACK_SRC, "attack", True)]
    return [(walk, "walk", True)]  # shooter, exploder, phantom, ember_tyrant


if __name__ == "__main__":
    import sys
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    keys = argv if argv else ["rusher", "shooter", "exploder", "shielded_brute",
                              "phantom", "ember_tyrant"]
    for k in keys:
        merge_enemy(k, specs_for(k))
