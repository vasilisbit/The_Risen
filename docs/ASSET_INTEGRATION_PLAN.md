# Asset integration plan

A phased plan for the asset library under `assets/thirdparty/`. Ordered by
impact-per-effort. **Phase 1 is implemented**; the rest are scoped for follow-up
passes so each can be tuned in-engine without destabilising the whole game.

Wiring convention (already built): the weapon viewmodel loads
`assets/thirdparty/weapons/<name>.{glb,gltf,tscn,scn}`; enemies load
`assets/thirdparty/characters/<type>....`. We use small **wrapper `.tscn`**
scenes that instance the real imported model with a fit transform, so no binary
files are copied and the source assets stay untouched.

## Licensing note (IGF = commercial)

- **CC0, no attribution, commercial-safe:** Kenney (Blaster Kit), Quaternius
  (Sci-Fi Essentials, Universal Base Characters, Universal Animation Library 1/2),
  KayKit (Space Base Bits). These are the safe backbone.
- **maxparata voxel packs, itch hologram shader, planet generator:** check each
  page's license before shipping.
- **`fab/` assets:** licensed per Fab listing - most Fab "free" items allow use
  in a product, but **verify each** and log it in `CREDITS.md`. Several have
  problems as downloaded (see Known issues).

## Known issues in the current download

- `fab/free_game_character_armored_troll_with_sword` is **missing its texture
  files** - it throws import errors every launch and stalls first start. Either
  re-export it with textures or drop a `.gdignore` in that folder to skip it.
- `fab/Demon Sword` and `fab/Platformer 8 Underworld` have **case-mismatched**
  texture paths (`textures` vs `Textures`) - they load on Windows but **will
  break on Linux/Mac export**. Fix the folder casing before relying on them.
- `fab/skm_robot` (the Forge Master clerk) **ships without its base-colour
  texture** (`phong1_Base_color.png` is referenced but missing), so it renders
  flat white. `hub_structure.gd` paints it gunmetal in code as a workaround; if
  you want the real look, re-export the FBX with its textures.

---

## Phase 1 - Weapons & enemies (IMPLEMENTED)

The constantly-on-screen actors - biggest visual lift.

| Game slot | Asset | Notes |
|---|---|---|
| Auto Rifle viewmodel | Quaternius `Gun_Rifle` | `weapons/auto_rifle.tscn` |
| Shotgun viewmodel | Fab Weapons FREE `shotgun_001` | `weapons/shotgun.tscn` (real pump shotgun) |
| Sniper viewmodel | Quaternius `Gun_Sniper` | `weapons/sniper.tscn` |
| Hand Cannon viewmodel | Quaternius `Gun_Revolver` | `weapons/hand_cannon.tscn` |
| Forge Master clerk | Fab `skm_robot3` | hub vendor stall; painted gunmetal (ships without its texture) |
| Rusher (melee) | Quaternius `Enemy_QuadShell` | `characters/rusher.tscn` |
| Shooter (ranged) | Quaternius `Enemy_EyeDrone` | hovering drone, raised 1 m |
| Exploder (suicide) | Quaternius `Enemy_Trilobite` | scaled down |

**Phase 1.5 (DONE):** `EnemyBase` now drives each model's own Walk/Idle clip off
the enemy's velocity - the Quaternius kit ships Walk/Run/Idle/Attack, so the
Rusher/Exploder/Shielded Brute walk and the hovering Shooter idles. The two Fab
FBX bosses (ghoul, monster) have no rig, so they stay static.
`EnemyBase.play_attack_animation()` exists for a future attack-clip hook.

## Phase 2 - Environment dressing (cover DONE; deeper dressing outstanding)

Turn the box levels into places. Instance props as visual children beside the
existing collision boxes (keep the code-generated collision).

| Area | Assets | Status |
|---|---|---|
| **Hub** (space station) | KayKit Space Base Bits: `basemodule_*`, `containers_*`, `cargo_*`, `drill_structure`; Sci-Fi Essentials `Prop_Console`/`Prop_SatelliteDish`; `fab/sci_fi_console`, `fab/military radio` | props placed (desks/lockers/shelves/crates); KayKit modules still available for a bigger station pass |
| **Earth** cover/detail | Sci-Fi Essentials `Prop_Crate*`, `Prop_Barrel*` | **cover DONE** (arena crates) |
| **Mars** rooms | Sci-Fi Essentials `Prop_Crate_Large/Crate`, `Prop_Barrel1/2` | **cover DONE**; `fab/UCreate Fractal Meshes` alien-tech dressing still optional |
| **Venus** volcano | `fab/rock_collection_04` (material-overridden volcanic) | **ascent cover DONE**; `fab/Inferno World` terrain + trees still optional |
| **Loot pickups** | small `Prop_Chest` with a rarity beacon | **DONE** (chests replaced the coloured boxes) |

## Phase 3 - Player character (third-person)

Replace the capsule player with a rigged, animated character.

- **Model:** Quaternius `Universal Base Characters` (`Superhero_Male/Female_FullBody.gltf`) - fits a Guardian.
- **Animations:** Quaternius `Universal Animation Library` 1 & 2 (`UAL2_Standard.glb`) retargeted to the base character; or `fab/Pistol and Rifle Locomotion Animations 1700` and the `fab/motifect_locomotion` set for gun-holding locomotion.
- **Effort:** high - needs an `AnimationTree`/state machine synced to movement
  (idle/walk/run/jump/aim/fire) and a third-person rig. Do after Phase 2.

## Phase 4 - Bosses & elite enemies (boss models DONE)

**Boss models wired** (2026-07-23) as `characters/<class>.tscn` wrappers the
enemy pipeline auto-loads, each sized to its collision capsule:
- Shielded Brute = scaled Quaternius `Enemy_QuadShell` (~3 m, robot-cohesive).
- Teleporting Phantom = Fab `ghoul_stylized_monster` (~2.4 m).
- Ember Tyrant = Fab `monster` (Monster UE, ~4 m).
Elite variants (below) are still open. The Ember Tyrant FBX ships without its
textures (renders pale) - a material tint or re-export is a follow-up polish.

### Original candidates

| Boss | Candidate |
|---|---|
| Shielded Brute (Earth) | `voxel-mechas/MechGolem` or `QuadrupedTank` (OBJ, static - or a scaled Quaternius robot) |
| Teleporting Phantom (Mars) | `fab/ghoul_stylized_monster` or `fab/monster` |
| Ember Tyrant (Venus) | `fab/monster` / `fab/free_game_character_armored_troll_with_sword` (once textures fixed) - big and menacing |
| Elite variants | remaining `voxel-mechas` (Arachnodroid, ReconBot, MechaTrooper, FieldFighter), `fab/warrior`, `fab/dark_knight`, `fab/rogue`, `fab/starsparrow` |

Note the voxel mechs are **OBJ (static, voxel style)** - they read differently
from the smooth Quaternius kit, so use them as a deliberate "heavy machine" tier
or not at all.

## Phase 5 - Sky, planets, holograms (DONE)

- **Hub window planet:** **DONE** - shows a detailed planet for the last-visited
  mission (Earth = oceans/continents/clouds). Uses the project's own self-lit
  `shaders/planet.gdshader`; the `godot-3d-planet-generator` addon (MIT, still
  installed at `addons/naejimer_3d_planet_generator`) was tried but its ported
  clouds shader rendered as a flat wash with specular artifacts at this scale, so
  the custom shader won. The addon is available for a future dedicated planet view.
- **Hologram-table planets:** **DONE (as holographic projections)** -
  `hologram_table.gd` keeps its shimmering shader spheres (they read as
  holograms and carry the locked-state labels) and now adds a **holographic
  projector beam** rising from the table base to each planet (dimmed for locked
  worlds). A solid generated planet was deliberately not used here - it wouldn't
  read as a hologram on a hologram table.
- **Hologram shader:** the itch `hologram.shader` is Godot-3 (`hint_color`) and
  was left unported; the custom `hologram_planet.gdshader` already provides the
  scanline/fresnel/flicker shimmer, so it wasn't needed.
- **Skybox:** none downloaded yet - keep the `space_sky` shader.
- **Skybox:** none downloaded yet - keep the `space_sky` shader, or generate a
  Poly Haven / Blockade (paid tier) space HDRI later.

## Phase 6 - Weapon variety & ability VFX

- More gun models for loot variety: Sci-Fi Essentials `Gun_*`,
  `fab/tesseract_revolver`, `fab/Weapons FREE`, Kenney's other blasters.
- Ability animations: `fab/motifect_fantasy_and_magic` (super), `fab/motifect_martial_arts` (melee) - once the player is a rigged character (Phase 3).

---

## Suggested order

1. **Phase 1** (done) - weapons + enemies.
2. **Phase 2** - environment dressing (hub first - it's the front door; then level cover/pickups). Highest remaining impact, low risk.
3. **Phase 5** - planets/holograms (self-contained, high wow-factor).
4. **Phase 4** - bosses.
5. **Phase 3** - third-person animated player (biggest effort; do last).
6. **Phase 6** - loot-gun variety + ability VFX.

Log every asset used in `CREDITS.md` as it goes in.
