# CLAUDE.md — The Risen (game repo)

Agent build guide for the Godot project. Read this first, then `handoff.md` /
`tracker.md` in the **planning repo** (`game-dev-the-risen`) for current status.

## What this is
**The Risen** — solo-dev, IGF-targeted (commercial) **first-person** looter-shooter
in **Godot 4.7-stable**, GDScript, **static typing**. Earth/Mars/Venus missions,
robot enemies, 3 classes (Assault/Support/Tank) with super+grenade+melee,
loot/rarity/mods, a hub (vendor + hologram mission table + mirror). M0–M7 complete;
M8 (art/asset polish) in progress.

## Driving the engine (godot-ai MCP)
Tight loop, do it constantly:
1. `project_run(mode:"main")` → boots the main menu.
2. `editor_manage game_eval` to jump scenes / set up state, e.g.
   `SaveManager.select_class("Assault"); get_tree().change_scene_to_file("res://scenes/hub/hub.tscn")`.
   Hub/Earth/Mars/Venus at `scenes/{hub/hub,missions/earth/earth,missions/mars/mars,missions/venus/venus}.tscn`.
3. `editor_screenshot(source:"game")` — **verify visually, always**, not just logic.
4. `project_manage stop`. **Reset the save after test runs**:
   `SaveManager.reset(); SaveManager.save_game()`.

### game_eval gotchas (these WILL bite)
- **Qualify `get_world_3d()`** as `some_node3d.get_world_3d()` — bare, it fails to
  compile against the eval's non-Node3D `self` and parks the game at a debugger
  break (then `project_manage stop` to recover).
- A one-line `if cond: a; return b` puts `return b` **inside** the if-body — use a
  ternary (`var x := a if cond else b`) instead.
- Multi-line `for`/`if` often mis-parse or return only the first item; prefer
  one-liners with `.map()`/`.filter()`/ternaries, or split across eval calls.
- Screenshots can go stale ("backgrounded") — stop+run to refocus.

## Physics collision layers (set in code, not scenes)
- **Layer 1** — world/static geometry **and the player**. Weapon/projectile/loot
  masks target this.
- **Layer 5 (value 16)** — **enemies** (`EnemyBase.ENEMY_LAYER`, mask `1|16`). The
  player is layer 1 / mask 1, so it **passes through** enemies (never pinned/stood
  on) while enemies still bump it and each other. The player's hitscan uses
  `Weapon.HIT_MASK = 1|16` to still hit them; other damage (grenade/rocket/melee/
  exploder) is group-based (`"enemy"`), so it needed no change.
- **Layer 3 (value 4)** — interactables (hologram spheres); the Guardian's
  `InteractRay` masks 4.
- **Render** layers (VisualInstance3D.layers, NOT physics): the player body is on
  `BODY_LAYER 1<<18` (main camera excludes it, mirror includes it); the mirror's
  wall/glass are on `NO_REFLECT 1<<19`.

## Asset pipeline (fal.ai + Blender + Godot)
> **Full pipeline reference:** planning repo **`docs/FAL_PIPELINE.md`** — the model map
> (which endpoint per job), what's new (Seedance video, Meshy 7 + rigging, Tripo Smart Mesh,
> Hi3D V3.0), the **Fold cinematic video** pipeline (`tools/gen_fold_video.py`), the
> **rigged-character** pipeline (Meshy rigging), costs, and the YouTube study list. Read it
> before generating anything new. Quick summary below.

AI 3D-gen **studios** (Tripo, Meshy) gate export behind paid plans — do NOT rely on
their free-tier download. Use **fal.ai's API** instead: it returns the file directly.
- Auth: `FAL_KEY` in **`.env.local`** (gitignored — never commit keys). Header is
  `Authorization: Key <FAL_KEY>`.
- **Helper**: `tools/falgen.py` (stdlib only) — run with `uv run --no-project python
  tools/falgen.py image "<prompt>" out.png [--model <id>]`, or `... raw <model>
  '<json>'` to debug a model's response shape. Add `tripo`/`patina` commands as needed.
- Models: `fal-ai/nano-banana-pro` (concepts + **FLAT albedo** textures + emission),
  `fal-ai/nano-banana-pro/edit`, `fal-ai/patina` (albedo→PBR set), `tripo3d/tripo/
  v2.5/text-to-3d` and `.../image-to-3d` (→ GLB), `fal-ai/elevenlabs/sound-effects/v2`
  (SFX), `fal-ai/stable-audio-25/text-to-audio` (music). Queue: `POST
  https://queue.fal.run/<model>` → poll `status_url` → fetch `response_url`; parse
  result URLs defensively.
- **Which 3D model (verified quality, 2026-08 — Earth + Mars built with this):**
  - **Tripo H3.1** (`tripo3d/h3.1/{text,image}-to-3d`, `pbr:true`, `geometry_quality`/
    `texture_quality:"detailed"`, `face_limit ~250–300k`) — **DEFAULT**. ~275k-tri
    crisp detailed models + 4K PBR at **~pennies/gen**, ~10–12 MB. Same quality as
    Hunyuan Pro, tiny cost. Used for all Earth buildings + Archive Core + Mars rock/
    structures/arch.
  - **Tripo P1** (`tripo3d/p1/...`, $0.40) — game-ready LOW-poly; reads soft/"playdough"
    up close. Superseded by H3.1 for hero assets.
  - **Hunyuan 3D v3.1 Pro** (`fal-ai/hunyuan-3d/v3.1/pro/{text,image}-to-3d`) —
    **$0.675/gen and ~84 MB** at 1 M faces. Great geometry but pricey + must decimate
    (Blender) — AVOID unless a specific look needs it.
  - Others: Tripo v2.5 ($0.01 high-poly→decimate), Rodin v2.5, Trellis, Meshy.
- **Workflow** (best control): nano-banana concept image → **Tripo H3.1 image-to-3d**
  (`orientation:"align_image"`) → Blender MCP (render-check / decimate) → Godot import.
  Text-to-3d H3.1 for quick props. Flat surfaces: nano-banana albedo + **fal-ai/patina**
  (normal/roughness). **Tripo GLBs already carry PBR (Color/NormalGL/ORM) — no PATINA
  on models.** Placement helper: unit-cube-normalize → scale to target metres → seat
  base via measured world AABB (see `_place_chunk`/`_place_rock`/`_place_struct`).
- **Godot import GOTCHA:** the glTF importer **extracts** embedded images to loose
  `*_Color/NormalGL/ORM.jpg` files the imported `.scn` references → **commit those
  extracted textures** (deleting them = "Resource file not found"). Overwriting a GLB
  needs its `.glb.import` deleted + a rescan; heavy multi-GLB scans can drop the editor
  plugin (wait ~30 s + reconnect).
- **Budget** ($20 pool): P1 hero assets ~$0.40 each (a full level's set ≈ $5–8);
  textures are pennies. Validate a model with ONE gen before batching.
- **Un-UV'd meshes** (OSM/greybox): apply generated albedo via
  `StandardMaterial3D.uv1_triplanar = true` + `uv1_scale` — world-projected, tiles
  without needing UVs. (Earth city greybox was textured this way; `earth_level.gd`.)
- **Blender toolkit MCP** for cleanup: decimate raw AI meshes (they come ~1–2 M
  tris) to game-ready (~10–30 k), generate collision, re-export GLB.
- **Texture budgets**: floor/large ≤1024 px; embedded-in-GLB ≤512 px; APIs return
  2–4K, always downscale before commit.
- **GLB webp gotcha**: when shrinking embedded textures, the bytes must match the
  declared `mimeType` (`image/webp` via EXT_texture_webp) or Godot's decoder breaks.

**The one texture lesson that matters:** if a texture source is meant for PATINA,
the prompt must demand a "FLAT UNLIT ALBEDO TEXTURE MAP — NO lighting, NO
reflections, NO gradients". A pretty glossy render bakes its highlights into the
basecolor and the material is ruined. Verify flatness numerically (channel std)
before spending on PBR conversion.


### Importing owned assets (check the inventory first!)
The user has a **large `assets/thirdparty/` library** — CHECK it (planning-repo
memory `thirdparty-asset-inventory`) before generating or web-searching.
- **FBX** imports at **100×** (cm→m) and often with local-**Z as world height** —
  always **measure world AABB in-engine** and set scale/rotation from that (e.g. the
  hub `Sci-fi Console Game.fbx` → scale 1.15 for ~1.5 m; `_console()` in
  `hub_structure.gd`).
- **KayKit** gltf is clean real-world scale (2 m tiles). Used for the Mars canyon
  backdrop (`mars_level._build_environment`, visual-only, no collision).
- Many Fab FBX **ship without textures** (render flat white) — apply a
  `material_override` (see the Forge Master mech, Phantom, Ember Tyrant).

## Conventions
- **Static typing** everywhere; tuning numbers in one place per system.
- Levels are **runtime-built in code** (`hub_structure.gd`, `earth_level.gd`,
  `mars_level.gd`, `venus_level.gd`) and bake their own `NavigationRegion3D`.
- Only **CC0 / Fab commercial-safe** assets (IGF/commercial). **No CC-BY-NC.**
- Verify look/feel with **screenshots**; passing logic ≠ correct rendering.

## Git
Commit **directly on `develop`**, no feature branches, **no `Co-Authored-By`**
trailer, **never push** unless asked. `git add` the `.uid` next to any new `.gd`.

## Key files
`scripts/guardian.gd` (player), `player_character.gd` (body/rig + `GRIPS`),
`fp_viewmodel.gd` (FP viewmodel + per-weapon `FRAMING`), `weapon.gd`/`weapon_manager.gd`,
`enemy_base.gd` (+ subclasses), `enemy_nameplate.gd` (health/shield/arc-shield shell),
`wave_manager.gd` (Mars), `game_state.gd` (fade transitions), `extraction_countdown.gd`,
`save_manager.gd`, `hub_structure.gd`, `mars_level.gd`.

## Generated content (fal.ai)
- **`tools/falgen.py`** — fal.ai queue helper; **`tools/gen_earth_chunks.py`** —
  batch Tripo-P1 chunk generator (shared style suffix keeps a set cohesive).
- **`assets/generated/earth/`** — nano-banana ground textures (concrete/asphalt/
  rubble) + `chunks/` (12 Tripo-P1 ruined-city GLBs, full PBR). Committed (not
  gitignored like `thirdparty/`, since the levels reference them).
- **`scripts/earth_level.gd`** now ASSEMBLES those chunks into the Earth level
  (scale → AABB-seat on ground → trimesh collision → navmesh) with a triplanar-
  textured street, afternoon `WorldEnvironment`, and containment walls. It reads its
  30 `spawn_point` markers as before (earth_mission drives the zone waves).
- **Earth + Mars + Venus are ALL rebuilt** on this pipeline (Tripo H3.1 models +
  nano-banana→PATINA PBR ground + per-planet sky shader + runtime fog atmosphere).
  Per-planet batch generators: `gen_earth_buildings.py`/`gen_earth_chunks.py`,
  `gen_mars_rocks.py`/`gen_mars_structures.py`, `gen_venus_rocks.py`/`gen_venus_textures.py`.
- **TODO:** real audio (music/SFX); LOD/culling (T-0036/37) + downscale the 2–4K
  ground pngs ≤1024. Budget ~$10 of $20 spent.
