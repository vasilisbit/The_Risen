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

---

## Phase 1 - Weapons & enemies (IMPLEMENTED)

The constantly-on-screen actors - biggest visual lift.

| Game slot | Asset | Notes |
|---|---|---|
| Auto Rifle viewmodel | Kenney `blaster-m` | `weapons/auto_rifle.tscn` |
| Shotgun viewmodel | Kenney `blaster-g` | `weapons/shotgun.tscn` |
| Sniper viewmodel | Kenney `blaster-e` | `weapons/sniper.tscn` |
| Hand Cannon viewmodel | Kenney `blaster-a` | `weapons/hand_cannon.tscn` |
| Rusher (melee) | Quaternius `Enemy_QuadShell` | `characters/rusher.tscn` |
| Shooter (ranged) | Quaternius `Enemy_EyeDrone` | hovering drone, raised 1 m |
| Exploder (suicide) | Quaternius `Enemy_Trilobite` | scaled down |

**Follow-up:** these enemy models are **animated** (idle/walk in the glTF) but we
currently show a static pose. Wiring an `AnimationPlayer` to the enemy state
machine (walk while chasing, attack on hit) is a Phase-1.5 polish.

## Phase 2 - Environment dressing

Turn the box levels into places. Instance props as visual children beside the
existing collision boxes (keep the code-generated collision).

| Area | Assets |
|---|---|
| **Hub** (space station) | KayKit Space Base Bits: `basemodule_*`, `containers_*`, `cargo_*`, `drill_structure`; Sci-Fi Essentials `Prop_Console`/`Prop_SatelliteDish`; `fab/sci_fi_console`, `fab/military radio` |
| **Earth** cover/detail | Sci-Fi Essentials `Prop_Crate*`, `Prop_Barrel*`, `Prop_Locker`, `Prop_Shelves*`; `fab/postwar-city-exterior-scene`; `fab/rock_collection_04` |
| **Mars** rooms | Sci-Fi Essentials crates/barrels; `fab/rock_collection_04`; `fab/UCreate Fractal Meshes` (alien-tech) |
| **Venus** volcano | `fab/Inferno World` (lava rocks/terrain), `fab/rock_collection_04`, `fab/packoftreeents` + `fab/Mobile Trees` (if a greener ascent), `fab/lush_green_mountains` (the folder even hints "venus perhaps") |
| **Loot pickups** | Sci-Fi Essentials `Prop_Ammo`, `Prop_HealthPack`, `Prop_KeyCard`, `Prop_Grenade` for the loot drops instead of coloured boxes |

## Phase 3 - Player character (third-person)

Replace the capsule player with a rigged, animated character.

- **Model:** Quaternius `Universal Base Characters` (`Superhero_Male/Female_FullBody.gltf`) - fits a Guardian.
- **Animations:** Quaternius `Universal Animation Library` 1 & 2 (`UAL2_Standard.glb`) retargeted to the base character; or `fab/Pistol and Rifle Locomotion Animations 1700` and the `fab/motifect_locomotion` set for gun-holding locomotion.
- **Effort:** high - needs an `AnimationTree`/state machine synced to movement
  (idle/walk/run/jump/aim/fire) and a third-person rig. Do after Phase 2.

## Phase 4 - Bosses & elite enemies

| Boss | Candidate |
|---|---|
| Shielded Brute (Earth) | `voxel-mechas/MechGolem` or `QuadrupedTank` (OBJ, static - or a scaled Quaternius robot) |
| Teleporting Phantom (Mars) | `fab/ghoul_stylized_monster` or `fab/monster` |
| Ember Tyrant (Venus) | `fab/monster` / `fab/free_game_character_armored_troll_with_sword` (once textures fixed) - big and menacing |
| Elite variants | remaining `voxel-mechas` (Arachnodroid, ReconBot, MechaTrooper, FieldFighter), `fab/warrior`, `fab/dark_knight`, `fab/rogue`, `fab/starsparrow` |

Note the voxel mechs are **OBJ (static, voxel style)** - they read differently
from the smooth Quaternius kit, so use them as a deliberate "heavy machine" tier
or not at all.

## Phase 5 - Sky, planets, holograms

- **Hub window planet + hologram-table planets:** `godot-3d-planet-generator`
  (Godot addon, `addons/naejimer_3d_planet_generator`) - real generated planets
  instead of the shader spheres. Wire into `hub_planet.gd` / `hologram_table.gd`.
- **Hologram table shimmer:** `hologram.shader` (knucklenoise) on the table
  projections for a crisper holographic look.
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
