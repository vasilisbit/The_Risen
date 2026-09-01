# VFX workflow — The Risen

How the game's ability/impact effects are built, and how to add or change one. This is
the **authoring reference**; the *research* behind the approach (and why fal.ai is used
only where it is) lives in the planning repo `docs/VFX_FAL_RESEARCH.md` **§11**, reconciled
from 18 Godot-VFX tutorials (Gabriel Aguiar / Brackeys / Le Lu).

## 0. The one principle

**fal.ai does not make effects — Godot does.** Every effect is a **Godot** composition:
layered one-shot `GPUParticles3D` + shaders + `Decal` + `OmniLight` + camera shake, driven
by curves and a small set of textures. fal/Blender/Godot each supply *assets* that
composition consumes:

| Asset kind | Made with | Why |
|---|---|---|
| Particle/shader **shape+pattern masks** (flare, ring, hex, noise, voronoi, distortion, gradient) | **Godot-baked** (`tools/bake_vfx_textures.gd`, `FastNoiseLite`+`Image`) | Seamless, tileable, controllable, $0 — beats a raster gen. NOT AI. |
| Simple VFX **meshes** (slash crescent, dome, wave, debris) | **Blender** (`tools/gen_slash_mesh.py`) | 2–5-min primitives; Tripo is overkill |
| Ground **decals** (scorch / molten crater / crack) — albedo+normal+emission | **fal** nano-banana-pro → PIL soft-edge alpha → `fal-ai/patina` (`tools/gen_vfx_decals.py`) | photographic PBR detail is fal's real win |
| **SFX** (per-hit punch) | **fal** ElevenLabs (`tools/gen_audio.py`) | quick, cheap "feel" |

Explosions are **mesh+particle, single-frame masks — NOT flipbooks** (no Seedance→ffmpeg).

## 1. Files

- `tools/bake_vfx_textures.gd` — headless `SceneTree` baker → 9 masks in
  `assets/generated/vfx/tex/`. Run:
  `godot --headless --path . --script res://tools/bake_vfx_textures.gd [-- <one>]`
  (bake one name first to validate, then all).
- `tools/gen_slash_mesh.py` — Blender → `assets/generated/vfx/slash_arc.glb` (crescent).
  Run: `"…/Blender 5.2/blender.exe" --background --python tools/gen_slash_mesh.py`
- `tools/gen_vfx_decals.py` — fal decals → `assets/generated/vfx/decals/*.png`
  (`<name>.png` albedo+alpha, `<name>_normal.png`, crater `_emission.png`). Run:
  `uv run python tools/gen_vfx_decals.py [--only <name>] [--force] [--no-patina]`.
  Needs `FAL_KEY` in `.env.local`. ~$0.15/image + ~$0.05/patina.
- `tools/gen_audio.py` — fal SFX (+ music/voice). `uv run python tools/gen_audio.py`
  generates only missing ids; `--only <id>` for one; `--force` to redo. Files land in
  `assets/generated/audio/sfx/<id>.mp3`, auto-picked by `audio_manager.gd`.
- `scripts/vfx_kit.gd` (`class_name VfxKit`) — the reusable composition helper.
- `shaders/shield_dome.gdshader` — hex energy-shield / crackle-aura spatial shader.

## 2. VfxKit API

```gdscript
VfxKit.explosion(host, at, base_color, radius, style := "fire", decal_override := "")
VfxKit.slash(host, at, facing, color, reach)
```

`explosion` builds a self-freeing `Node3D` of layered one-shot particle systems + light +
shake (+ decal) at `at`. **Styles:**

| style | layers | used by |
|---|---|---|
| `fire` | fireball + sparks + smoke + shock ring + **scorch** decal + flash + shake | frag grenade, Storm-Barrage rocket, (magma with `decal_override="crater"`) |
| `soft` | rising green motes + soft bloom + (heal_ring decal) + flash | healing grenade |
| `flash` | hard white bloom + fast ring + light | flashbang |
| `emp` | bright ring + arc sparks + bloom (no smoke) | EMP punch, Juggernaut charge-up, Dome shatter |
| `slam` | heavy ground ring + dust + **ground_crack** decal + shake | ground slam |

`decal_override` swaps the fire-style decal (magma passes `"crater"` for the glowing
crater). `slash` prefers the crescent GLB (billboarded, additive), falling back to a
cross-flare quad.

**Every layer degrades gracefully:** a missing mask → flat quad; a missing decal PNG →
skipped. So the effects always run even before assets are generated.

## 3. Shield shader (`shield_dome.gdshader`)

Additive, unshaded, cull-disabled spatial shader: a tiled **pattern** mask (hex for the
Dome, voronoi for the aura) broken up by scrolling **noise**, plus a **Fresnel rim** so the
silhouette glows. `strength` (0–1) dims it as a shield pool is spent. Params:
`pattern_tex`, `noise_tex`, `shield_color`, `pattern_scale`, `scroll_speed`, `brightness`,
`strength`. Applied to a hemisphere (`guardian_dome.gd`) and a sphere (`juggernaut_charge.gd`).

## 4. Adding / changing an effect

1. **Reuse a style if one fits** — call `VfxKit.explosion(...)` / `.slash(...)` with the
   ability's colour + radius. Most effects need no new code.
2. **New style** → add a `match` branch in `VfxKit.explosion` composing existing `_layer_*`
   helpers (fire/sparks/smoke/shock/motes/bloom). Prefer composition over new layers.
3. **New mask** → add a `_bake_*` to `bake_vfx_textures.gd`, rebake. **New decal** → add to
   `DECALS` in `gen_vfx_decals.py`. **New SFX** → add to `SFX` in `gen_audio.py`, then
   `am.play_sfx("<id>", at)` from the ability.
4. **SFX** already covers: `explosion`, `enemy_hit`, `player_hit`, the 4 guns, and the
   ability set `melee_blade / melee_emp / melee_slam / super_dome / super_charge /
   grenade_heal / grenade_flash`.

## 5. Gotchas (learned in-engine)

- `ParticleProcessMaterial.scale_min/max` are **multipliers** on the quad size, then
  `scale_curve` multiplies again — real size = `quad × scale × curve`. Put real metres in
  the quad size and keep scale ~0.5–1.2, or smoke renders as huge dark discs.
- `explosiveness` must be **0–1** (it clamps). Use `1.0` for a burst.
- Additive sprite mats: `SHADING_MODE_UNSHADED` + `BLEND_MODE_ADD` + `BILLBOARD_PARTICLES`
  + `billboard_keep_scale=true` + `vertex_color_use_as_albedo=true`; smoke uses `MIX`.
- Effects need **WorldEnvironment glow** to bloom — the missions have it; the Dome/aura
  rim and fireball rely on it.
- **Decals** project down their local −Y within a box (`size`); they fade over ~6 s.
  Post-process the fal albedo to a **soft radial alpha** so it blends onto any ground.
  Give the molten crater an **emission** map (`_emission.png` + `emission_energy`) to glow.
- Camera shake = `guardian.add_recoil(0.0, amount)` on the player group, distance-scaled.
- **Verify with a throwaway harness** (floor + glow env + camera) that fires the effect on
  a fast loop, so a single game screenshot reliably catches the brief bright window — one
  capture usually lands between bursts. Delete the harness after. Reset nothing
  (`SaveManager.reset()` is never called).

## 6. Cost so far

Texture kit + meshes: **$0** (Godot/Blender). Decals: ~**$0.5** (3 albedos + 3 patina).
Ability SFX: ~**$0.02**. The bulk of the work is Godot authoring, as intended.

## 7. Muzzle flash (`fp_viewmodel.gd`)

Per-shot flash on the first-person gun, spawned **inside the viewmodel's own SubViewport**
so it composites with the arms. `weapon_manager._fire()` calls
`fpvm.muzzle_flash(weapon_name, Weapon.ELEMENT_COLORS[weapon.element])`, so:

- **Colour = the weapon's energy element** — Kinetic pale / Solar orange / Arc cyan / Void
  purple (`Weapon.ELEMENT_COLORS`, set by the solar/arc/void injector mods).
- **Shape differs per gun type** via `MUZZLE_SIZE` (shotgun wide, sniper long/narrow, auto
  rifle small, hand cannon punchy).
- **Position = the true barrel tip**, computed once per weapon swap by `_compute_muzzle()`:
  the forward-most (most −Z) mesh vertex of the gun model in holder space, cached in
  `_muzzle_local`. This auto-aligns to each gun regardless of its own mesh rotation (the
  hand cannon models its barrel along +X, the others along −Z) — no per-gun hand-tuning.
- The flash = a big billboarded **spiky `muzzle` star** (baked, irregular rays) + a bright
  `flare` core + a one-shot **burst of stretched sparks shooting forward out of the barrel**
  (`_muzzle_sparks`, aimed down `_muzzle_forward()` = the viewmodel camera's look direction) +
  an element-tinted `OmniLight`. All `no_depth_test` so they read over the gun. The forward
  sparks are what sell "coming out of the gun" in the end-on first-person view.

To retune a gun's flash size, edit `MUZZLE_SIZE`; the position is automatic.

## 9. Bullet-impact sparks (`VfxKit.impact`)

Where a shot lands: `weapon.fire()` calls `VfxKit.impact(host, hit_pos, hit_normal, color, kind)`
for every hit (world or enemy). It spawns a short burst of velocity-aligned **spark streaks
bouncing off the surface** (emitted along the hit normal, `_streak_mat` — additive, not
billboarded) + a quick `flare` flash. **Colour = the weapon's energy element**; **size/count =
gun type** (`VfxKit.IMPACT`: sniper big & bright, shotgun small ×many-pellets, etc.). Only the
heavier single-shot guns (scale ≥ 1.2) add a dynamic `OmniLight`, so a shotgun blast or
sustained auto fire doesn't spawn a swarm of lights.

## 8. Travelling slash wave (`slash_wave.gd`)

The Assault **Energy Blade** throws a `SlashWave` (crescent GLB, billboarded + additive)
that **flies forward, damages each enemy it passes once** (200, melee-multiplied,
attributed to "Energy Blade"), and **fades out after `MAX_DIST` (9 m)** — a ranged slash,
not a point-blank cone. `EnergyBlade._execute()` builds it, `setup(from, dir, damage,
color)` then `add_child` (setup only stores; `_ready` applies the transform once in-tree).
Targeting reuses the melee surface-distance approach (group "enemy" minus body radius) so it
catches big bosses by their body, not their foot origin. Tunables at the top of the script:
`SPEED`, `MAX_DIST`, `HIT_RADIUS`.
