# Textures & shaders — what the surfaces need

The levels, hub and props are lit but **flat-shaded**: walls/floors/counters are
solid-colour `StandardMaterial3D` created in code (see `*_level.gd`,
`hub_structure.gd`). That reads as "greybox with lighting". This file lists what
textures and shaders would make those surfaces look finished, where to get them
(all **CC0**, commercial-safe for IGF), and what's worth doing now vs later.

## The one thing to fix regardless: texture folder casing

Several imported kits reference `textures/…` but the folder on disk is
`Textures/…` — **Sci-Fi Essentials, Universal Base Characters, and some `fab/`
packs**. Windows is case-insensitive so it works now, but Godot warns:
*"…will not open when exported to other case-sensitive platforms."* → **it will
break a Linux/Mac/most console export.** Fix by renaming each `textures` folder
to match what the `.import`/`.gltf` expects (or vice-versa) before shipping. This
is not optional for release.

## Surfaces and the maps they want

A good PBR material = **Albedo + Normal + Roughness + Metallic (+ AO)**. Godot's
`StandardMaterial3D` takes all of these; just assign the textures and set
`uv1_scale` for tiling. Targets:

| Surface | Where | Look | Maps to grab |
|---|---|---|---|
| **Hub / ship walls & floor** | `hub_structure.gd` | brushed-metal panels, subtle trim | metal-panel albedo/normal/rough/metal, tiling |
| **Earth streets / rooftops** | `earth_level.gd` | worn concrete, asphalt, rusted metal | concrete + metal PBR sets |
| **Mars rock & rooms** | `mars_level.gd` | red rock, sandy floor, alien-tech panels | red-rock/sand PBR + a sci-fi panel |
| **Venus rock & obsidian** | `venus_level.gd` | dark volcanic rock, obsidian, ash | dark-rock/obsidian PBR |
| **Cover crates/barrels** | props (already textured) | — | already have the Sci-Fi Essentials trim atlas |
| **Window glass** | `hub_structure.gd` | clean glass with edge highlight | a glass shader (below), no texture needed |
| **Lava (Venus)** | `venus_level.gd` | flowing molten rock | a scrolling emissive shader (below) |

### Where to get CC0 textures
- **ambientCG** — https://ambientcg.com — the best CC0 source for tiling PBR
  (Metal, Concrete, Rock, Ground, SciFi panels). Download the "PBR" zip; it has
  every map.
- **Poly Haven** — https://polyhaven.com/textures — CC0 PBR, high quality.
- **Sci-Fi Essentials trim sheets** (already in the project:
  `Sci-Fi Essentials Kit[Standard]/Textures/T_Trim_*`) — reuse these on the ship
  walls so the hub matches the props for free.

## Shaders

Custom shaders already in the project (`shaders/`): `space_sky.gdshader`,
`planet.gdshader`, `hologram_planet.gdshader`, plus the downloaded
`assets/thirdparty/hologram.shader` (knucklenoise, for the hologram table). What
else is worth writing:

| Shader | For | Notes |
|---|---|---|
| **Trim / panel** | ship + facility walls | samples a trim atlas by UV band; cheap way to make flat walls read as panelled. Or just a tiled PBR material - no shader needed. |
| **Glass** | cockpit window | `StandardMaterial3D` with transparency + a fresnel rim is enough (no custom shader). |
| **Lava flow** | Venus river/pool | scroll two emissive noise layers; ~15 lines of `.gdshader`. High impact. |
| **Elemental shield shell** | Heroic/Legendary enemies | currently a rim-lit sphere material - a fresnel + hex-scroll shader would sell it better. |
| **Forcefield / hologram** | vendor counter top, hologram table | apply `assets/thirdparty/hologram.shader` for scanline shimmer. |

Most of these are **not** blocking - the game is fully playable flat-shaded.

## Do now vs later

- **Now (cheap, high impact):**
  - Reuse the Sci-Fi Essentials trim textures on the hub/ship walls (already in
    the project, no download).
  - Apply `hologram.shader` to the hologram table and/or the counter top.
- **Later (part of the art pass, Phase 2/8 of `ASSET_INTEGRATION_PLAN.md`):**
  - Full PBR texture sets from ambientCG/Poly Haven for each level's walls/floors.
  - The lava-flow and improved shield shaders.
- **Before release (mandatory):**
  - Fix the **texture folder casing** so the export doesn't lose materials.

Log any texture/shader asset you add in `CREDITS.md`.
