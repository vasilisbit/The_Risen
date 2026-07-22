# Weapon models

Drop a weapon model here named after the weapon, lowercase, spaces → underscores:

| Weapon | File name (any one extension) |
|---|---|
| Auto Rifle | `auto_rifle.glb` / `.gltf` / `.tscn` |
| Shotgun | `shotgun.glb` … |
| Sniper | `sniper.glb` … |
| Hand Cannon | `hand_cannon.glb` … |

`scripts/weapon_viewmodel.gd` loads it automatically (priority: `.glb` → `.gltf`
→ `.tscn` → `.scn`). If no file is present the game falls back to its built-in
primitive silhouette, so nothing breaks while slots are empty.

**Fitting an import.** Imported meshes arrive at all sizes and facings. Tune the
per-weapon entry in `MODEL_FIT` (in `weapon_viewmodel.gd`): `scale`, `rot`
(degrees), `offset`. Target: barrel down **-Z** (forward), grip toward **-Y**, a
gun roughly **0.4 m** long.

**Good CC0 source (no attribution required):** the Kenney *Blaster Kit* ships
glTF with removable scopes/magazines — https://kenney.nl/assets/blaster-kit

`auto_rifle.tscn` here is a worked example (built from primitives) that proves
the pipeline — replace it with a real model when you have one. See
`docs/ASSET_SOURCES.md` for the full sourcing guide and licensing rules.
