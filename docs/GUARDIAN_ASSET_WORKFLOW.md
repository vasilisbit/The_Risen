# Guardian asset workflow (T-0042)

How the player **Guardian** and its gear were built on the fal.ai pipeline: the
rigged 3rd-person body, the bespoke first-person arms+gun viewmodel, and the
equippable armour plates. This is the concrete, learned-the-hard-way companion to
[`FAL_PIPELINE.md`](FAL_PIPELINE.md) (§6 rigging, §9 workflows, §10 tool notes) —
read that first for the model map and costs; read this for how the three Guardian
pipelines actually fit together in Godot and the gotchas that cost the most time.

The Guardian is the project's **first custom rigged actor** (the T-0041 weapons were
the first custom gear). Three separate asset paths feed it, because **one rig cannot
do all three jobs** — see each section for why.

- Body rig → `assets/generated/guardian/guardian.glb`, `tools/gen_guardian.py`
- FP viewmodels → `assets/generated/viewmodels/*_vm.glb`, `tools/gen_viewmodel.py`, `scripts/fp_viewmodel.gd`
- Armour plates → `assets/generated/armor/{helmet,chest,gauntlet_l,gauntlet_r}.glb`, `tools/gen_armor.py`, `scripts/guardian_armor.gd`

---

## The one number that explains everything: the 0.0117 armature scale

The Meshy auto-rig exports with an **armature scale of ~0.0117** (a ~85× shrink; the
mesh is authored at ~100× and scaled back down). Everything downstream inherits this:

- A `BoneAttachment3D` follows a bone's **global** transform, which carries that
  ~0.0117 scale. So a child mesh at local `scale = 4` renders at ~`0.05 m` — an
  invisible speck. Hand-held weapons and armour plates need a **big** local scale
  (~20–55, i.e. ~100× a "normal" value) to appear at human size.
- Positions expressed in a bone's local space are in that same shrunk unit — **~85
  local units per world metre** — so bone-local offsets look large (e.g. `y = 16`
  ≈ `0.19 m` down the forearm).

If a bone-attached mesh is "missing", it is almost always this: it rendered, at
3 cm, inside the body. Confirm by hiding the body mesh and looking for specks, or by
measuring the world-space AABB of the plate mesh.

---

## Pipeline A — the rigged body (`tools/gen_guardian.py`)

3rd-person body only: the **hub mirror** and the **inventory preview**. Staged so the
cheap mesh is validated before paying for the rig (FAL_PIPELINE §6, §9A, §10.8-10.9):

1. **Concept** — `fal-ai/nano-banana-pro`: a clean **A-pose** front + matching back,
   arms out, feet apart, **empty open hands, no props** (rigging needs clearly
   separated limbs), sealed helmet + teal visor + armoured gauntlets, plain studio
   background, 3D-lit render (flat 2D art converts to 3D badly).
2. **Mesh** — `meshy/v7/multi-image-to-3d` (front+back, A-pose, PBR, game topology).
3. **Rig** — `fal-ai/meshy/rigging` (humanoid) + `fal-ai/meshy/rigging/multi-animation`
   for idle / walk / run. → `guardian.glb`.

`--stage concept|mesh|rig|all`, `--force` to overwrite.

**Rig realities (all of these bit us):**

- **Mixamo-style bone names**, e.g. `Head`, `Spine`(+`Spine01`/`Spine02`), `Hips`,
  `Left`/`Right` `Shoulder`-`Arm`-`ForeArm`-`Hand`. **No finger bones** — one bone
  per hand.
- **0.0117 armature scale** (see above).
- glTF import leaves animations **non-looping** — set `loop_mode = LOOP_LINEAR` on
  the `idle`/`walk`/`run` clips after load (see `guardian_preview.gd`, `guardian.gd`).
- The idle clip **moves the arms**; bone world positions drift frame to frame. When
  you need a stable pose to measure or place against, `AnimationPlayer.pause()` first.
- Body-attached extras (armour, held gun) go on **`BODY_LAYER = 1 << 18`**: the
  first-person camera culls that layer (so the body never occludes the FP view), the
  hub mirror renders it, and the inventory preview's own isolated world ignores the
  layer entirely.

---

## Pipeline B — the first-person viewmodel (`tools/gen_viewmodel.py`, `scripts/fp_viewmodel.gd`)

**Why not the body rig?** Two hard blockers, both from the auto-rig:

1. **Arms too short** — measured **~0.57 m** reach vs **~0.67 m** to a rifle
   handguard, so a two-handed grip can't close.
2. **Fingerless hands** — one bone per hand, so a support hand just splays open.

Real FPS games don't use the body rig for the viewmodel anyway — they use a
purpose-built **arms+gun mesh**. So do we.

- **Generate** (per weapon): `nano-banana-pro` concept of two **armoured gauntlets
  gripping the gun** (armoured gloves dodge the AI-fingers problem and match the
  Guardian) → `tripo3d/h3.1/image-to-3d` → `assets/generated/viewmodels/<gun>_vm.glb`.
  `--gun <name>|all`, `--concept-only`. Validate ONE before batching.
- **Render** — `fp_viewmodel.gd` draws the static mesh in its **own isolated
  `SubViewport`** (fixed camera at `cam_position` looking `-Z`), composited on top of
  the main view. It is a plain mesh, **not** a skeleton — recoil/reload dip are
  animated in code, not by clips.
- **Framing** — `VM_XFORM[weapon] = {pos, rot(deg), scale}` places each gun
  lower-right with the barrel pointing into the screen (`-Z`), plus `VM_BASE` as the
  fallback. **Each Tripo mesh keeps its own native barrel axis**, so `rot` is tuned
  per gun:
  - Auto Rifle / Shotgun / Sniper model the barrel along `-Z` already → `rot` is a
    small cosmetic cant (`~2,6,-8`).
  - **Hand Cannon** models the barrel along **+X** → it needs a **~+90° Y** turn
    (`+X → -Z`) or it literally points back at the player. (Rotation about Y by θ
    maps `+X → (cosθ, 0, -sinθ)`; θ = +90° gives `-Z`.)

The world/inventory keep the separate T-0041 world gun models — view model vs world
model, as most shooters do.

---

## Pipeline C — equippable armour plates (`tools/gen_armor.py`, `scripts/guardian_armor.gd`)

> **Status: REMOVED from display (2026-08-26).** The plate meshes never fit the Meshy
> rig cleanly across all three views (the body, hub mirror, and preview each pose the
> same rig differently, and the abstract Tripo plates don't hug the body), so they read
> as floating parts. `GuardianArmor.refresh` was reduced to a stub that just clears old
> plate nodes; equipped armour is **stat-only** now. The section below is kept as a
> record of the pipeline — if revisited, the plates need to be **modelled to fit the
> actual Guardian body** (or skinned to the rig), not generated as standalone props.


Over-armour that **layers on top** of the already-armoured base body, one mesh per
slot, tinted by the equipped piece's rarity, shared by the mission body + hub mirror
(`guardian.gd`) and the inventory preview (`guardian_preview.gd`).

- **Generate** — `nano-banana-pro` concept of the plate as a **standalone piece of
  heavier over-armour** (chest rig, upgraded helmet, gauntlet pair), Guardian palette,
  plain bg → `tripo3d/h3.1/image-to-3d`. `--piece chest|helmet|gauntlets|all`.
- **Gauntlet L/R split** — `gen_armor.py` makes a single **paired** `gauntlets.glb`.
  Each forearm bone needs its **own** mesh, so the pair was **bisected down the middle
  in Blender** and exported as `gauntlet_l.glb` / `gauntlet_r.glb` (they still share
  the paired mesh's textures — same UUID). This is a manual Blender step, not in the
  generator.
- **Attach** — `GuardianArmor.refresh(skeleton, equipped, sm)` clears old
  `ArmorPlate*` nodes and, per equipped slot, adds a `BoneAttachment3D` on the slot's
  bone with the plate mesh as a child. Rebuilt live on `SaveManager.loadout_changed`,
  so equip/unequip updates the body, mirror, and preview at once.
- **Placement** — `PLACEMENT[slot] = {attach:[...], pos, rot(deg), scale}` in
  **bone-local** space (the 0.0117-scaled frame — hence scales ~20–52 and large-looking
  offsets). `rot -90 X` stands the upright Tripo plate to face forward; the chest adds
  a **-90 Y** to turn its opening to the front. The **gauntlets carry per-attach
  `pos`/`rot`/`scale` overrides** (the mirrored left/right forearm bones need different
  values); other slots fall back to the slot-level values.
  - Practical tuning trick: place a plate at a **world target** with
    `mesh.position = attach.global_transform.affine_inverse() * world_point`, eyeball
    it in the preview, then **read back** `mesh.position/rotation_degrees/scale` — the
    bone-local result is pose-invariant, so it holds on the body + mirror too. Those
    read-back numbers are exactly what's baked into `PLACEMENT`.
- **Rarity overlay** (`RARITY_STYLE` + `_finish`) — reads at a glance, not a subtle
  hue: **Common** neutral gunmetal grey (no glow); **Rare** clear blue wash +
  emission; **Epic** and **Exotic** (legendary) clear purple wash + emission. Plates
  render on `BODY_LAYER` (`1 << 18`) like the body.

---

## Gotchas, consolidated

- **0.0117 armature scale** — the root cause of "invisible" attached meshes; use big
  scales and remember bone-local units are ~85/m. (Armour plates were shipping at
  ~3 cm before this was caught.)
- **Fingerless, short-armed rig** — no two-handed FP grip; that's why the FP view is a
  bespoke mesh, not the rig.
- **Non-looping glTF anims** — set `loop_mode` after load.
- **Idle animation drifts bones** — `AnimationPlayer.pause()` before measuring/placing.
- **`BODY_LAYER = 1 << 18`** — FP camera culls it, mirror shows it, preview's isolated
  world ignores the layer.
- **GLB reimport** — overwriting a `.glb` needs its `.glb.import` deleted + a rescan;
  set `gltf/embedded_image_handling = 2` to embed textures and avoid loose files.
- **Plugin drops on heavy scans** — multi-GLB imports can drop the godot-ai editor
  plugin; wait, poll `editor_state`, reconnect.

### In-engine verification (screenshots)

- Prefer `game_eval` save-to-PNG over `editor_screenshot(source:"game")`, which goes
  **stale** when the game window backgrounds:
  `get_viewport().get_texture().get_image().save_png("res://_x.png")` then read the
  file. Globalize with `ProjectSettings.globalize_path("user://…")` when saving to
  `user://`.
- **Do NOT `await create_timer()` after opening the inventory** — it pauses the tree
  and the eval hangs.
- The inventory preview is a `SubViewport` (`own_world_3d`); when the game window is
  backgrounded it can **stop re-rendering** and its texture freezes even under
  `force_draw`. If frames stop advancing (`Engine.get_frames_drawn()` stuck), relaunch
  and capture while the window is fresh/foreground.
- For clean preview shots, set the preview's `_spin_rate = 0`, pause its
  `AnimationPlayer`, and move its camera in close.
- **Never `SaveManager.reset()`** after tests. To preview a loadout you don't own the
  right pieces for, mutate `sm.data["equipped_armor"]` in memory + `loadout_changed.emit()`
  and **restore it** afterwards — never `equip_armor()` (it calls `save_game()` and
  overwrites the player's real save).

## Cost (fal.ai)

Using the FAL_PIPELINE §2/§6 figures: Tripo H3.1 image-to-3d ≈ **$0.01/gen** (the 4
viewmodels + 3 armour pieces ≈ a few cents plus their nano concepts), and the Meshy
rig + multi-animation is the one real cost at **$0.80/gen**. The whole Guardian
(concept + mesh + rig + 4 viewmodels + 3 armour plates) came in around **~$1–1.5**.
Validate ONE gen before batching.
