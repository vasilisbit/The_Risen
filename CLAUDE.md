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
AI 3D-gen studios (Tripo, Meshy) **gate export behind paid plans** — do NOT rely on
free-tier download. Use **fal.ai's API** instead: it returns the file directly.
- Auth: `FAL_KEY` in a **gitignored `.env`** (never commit keys).
- Models: `tripo3d/.../image-to-3d` (→ GLB), `fal-ai/patina` (image→PBR set),
  `fal-ai/nano-banana` (albedo/emission/concept), `fal-ai/elevenlabs/...` (SFX),
  `fal-ai/stable-audio-25/...` (music). Queue pattern: POST → poll `status_url` →
  fetch `response_url`; parse result URLs defensively.
- **Blender toolkit MCP** for cleanup: decimate raw AI meshes (they come ~1–2 M
  tris) to game-ready (~10–30 k), generate collision, re-export GLB.
- **Texture budgets**: floor/large ≤1024 px; embedded-in-GLB ≤512 px; APIs return
  2–4K, always downscale before commit.
- **GLB webp gotcha**: when shrinking embedded textures, the bytes must match the
  declared `mimeType` (`image/webp` via EXT_texture_webp) or Godot's decoder breaks.

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
