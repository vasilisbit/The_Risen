# Credits

The people, tools and assets behind **The Risen**. This is the source list for the
in-game credits roll (`ui/credits.tscn`, T-0039) and mirrors the planning repo's
`docs/ASSET_LIST.md` 1:1 - keep the three in sync.

CC0 assets need no attribution but are listed for provenance. Only assets that
actually **ship and render** in the build are credited; retired placeholders are
noted at the bottom.

## Developer

**Vasileios Bitzas** - design, programming, art direction (solo).

## Engine & tools

| Tool | Provider | License | Use |
|---|---|---|---|
| Godot Engine 4.7 | Godot Foundation | MIT | Game engine (GDScript) |
| Godot AI (`addons/godot_ai`) | Godot AI | MCP dev tool | AI-assisted in-editor work |
| Blender 5.2 | Blender Foundation | GPL (tool) | Mesh authoring, rig merges |
| fal.ai | fal.ai | Paid-plan API (commercial output) | Hosted generative models (below) |
| Suno | Suno | Paid-plan (commercial output) | Intro cinematic orchestral score |

## Art & 3D - AI-generated (fal.ai, user's paid plan)

| Asset | fal endpoints |
|---|---|
| Guardian + first-person viewmodel | nano-banana-pro → Meshy v7 + rigging |
| Weapons ×4 (Auto Rifle/Shotgun/Sniper/Hand Cannon) | nano-banana-pro → Tripo H3.1 |
| Enemies + bosses ×6 | nano-banana-pro → Meshy v7 + rigging |
| Forge Master vendor | nano-banana-pro → Meshy v7 + rigging |
| Ship, interior, planets | nano-banana-pro → Tripo H3.1 (+ Blender cockpit) |
| Environments + PBR textures | nano-banana-pro → Tripo H3.1 → fal-ai/patina |
| Projectile / hazard props | nano-banana-pro → Tripo H3.1 |
| UI / HUD icons ×12 | nano-banana-pro |

## Audio - AI-generated

| Asset | Model / endpoint |
|---|---|
| Music (hub, travel, Earth/Mars/Venus combat, boss) | Stable Audio 3 (fal.ai) |
| SFX (guns, explosion, hits, footstep, wind, warp, engine, UI) | ElevenLabs sound-effects (fal.ai) |
| Vendor voice (Forge Master lines + barks) | ElevenLabs TTS (fal.ai) |
| Intro cinematic score ("The Risen - Awakening") | Suno |
| Intro cinematic narration | ElevenLabs v3 TTS, voice "Rachel" (fal.ai) |

## Cinematics - AI-generated

| Asset | Model / endpoints |
|---|---|
| **New-character intro film** ("A Guardian Awakens") | nano-banana-pro keyframes → MiniMax H3 image-to-video (fal.ai); B&W grade + score/narration mux; played in-engine as a WebP frame pack + Ogg via a custom core-Godot sequence player (no video addon) |
| Fold approach clips + lift-off-to-orbit clip | nano-banana-pro → Bytedance Seedance 2.0 (fal.ai) |

## Third-party assets (shipped)

| Asset | Author / source | License | Where used |
|---|---|---|---|
| Sci-Fi Essentials Kit | Quaternius (quaternius.com) | CC0 | Hub props - chairs, chests, crates, barrels, lockers, shelves |
| 3D Planet Generator addon | Rémi "naejimer" (github) | MIT | Included at `addons/naejimer_3d_planet_generator` (evaluated; the custom shader ships instead) |

## fal.ai models

nano-banana-pro / edit · Tripo H3.1 & P1 image/text-to-3d · Meshy v7 multi-image-to-3d
+ rigging · MiniMax H3 image-to-video · fal-ai/patina · Stable Audio 3 · ElevenLabs
sound-effects & v3 TTS · Bytedance Seedance 2.0. Non-fal: Suno (intro score).

## Special thanks

The Godot Engine community · the Blender & open-source 3D community · fal.ai ·
Quaternius for years of CC0 game art · friends, family & every playtester.

## Retired during M8 (no longer rendered, not credited)

Fab `skm_robot3`, Fab `shotgun_001`, Fab `monster` / `ghoul_stylized_monster`,
Quaternius Universal Base Characters, Fab `rock_collection_04`, KayKit Space Base
Bits, Kenney Blaster Kit - all replaced by the AI-generated assets above.

---

See `docs/ASSET_SOURCES.md` for vetted sources and licensing rules (IGF =
commercial: CC0 / Fab / paid-AI only, no CC-BY-NC).
