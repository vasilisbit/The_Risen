# Asset sources — where to get / generate art & audio for The Risen

A vetted list of places to source or generate assets, checked for the two things
that matter for this project.

## Two hard rules

1. **Commercial-safe licensing.** The Risen targets **IGF** (a commercial
   context), so every asset must permit commercial use *and* redistribution
   inside a game. This rules out anything CC-BY-**NC** (non-commercial) — e.g.
   our GDQuest 3D tutorial assets, and the free tiers of several AI tools below.
2. **Godot-friendly formats.** Prefer **glTF** (`.glb`/`.gltf`). FBX/OBJ/DAE
   import fine. Avoid UE-only assets (Nanite meshes, UE material graphs,
   Blueprints) — they won't bring their look into Godot cleanly. For HDRIs use
   `.hdr`/`.exr`; for audio `.wav`/`.ogg`.

**Attribution:** CC0 needs none. CC-BY needs credit — log it in `CREDITS.md`
(repo root) the moment you add the asset, or it's easy to forget before ship
(that's card T-0039).

---

## Fab (you already have assets here)

Fab is Epic's merged marketplace (Quixel Megascans + old UE Marketplace +
Sketchfab). It works for us **if you filter carefully**:

- Filter **format = glTF or FBX**; confirm the listing's license line allows use
  in a commercial product.
- **Skip** listings that are "UE5 project / Nanite / material-instance only" —
  those are built for Unreal and won't transfer.
- The merged **Quixel Megascans** (textures/HDRIs/scanned props) on Fab are great
  for the industrial (Earth) and volcanic (Venus) environments.
- Good Fab categories for us: weapon models, robot/character meshes, sci-fi
  props, VFX textures, skyboxes.

---

## Free CC0 libraries (safest — commercial OK, mostly no attribution)

Checked and matched to what The Risen actually needs:

### Weapons
- **Kenney — Blaster Kit** — https://kenney.nl/assets/blaster-kit
  CC0, **glTF** (+OBJ/FBX/DAE/STL), removable scopes & magazines, single shared
  texture, **no credit required**, explicitly Godot-ready. *Best first stop for
  our four guns.* This is what the `assets/thirdparty/weapons/` pipeline expects.
- **Quaternius — Sci-Fi Gun Pack / Modular Gun Pack** — CC0, glTF/GLB —
  https://quaternius.com/packs/scifigun.html ·
  https://quaternius.com/packs/scifimodularguns.html (also on https://poly.pizza)

### Enemies / characters
- **Quaternius — Sci-Fi Essentials Kit** — CC0, includes **animated robot
  enemies**, guns, crates, screens —
  https://quaternius.com/packs/scifiessentialskit.html
  Fits the machine-enemy "Risen" theme; a strong swap for the capsule enemies.

### Environment / textures / HDRIs
- **Poly Haven** — CC0 HDRIs, PBR textures, some models; no login, commercial OK
  — https://polyhaven.com (skies for the space view: https://polyhaven.com/hdris/skies)
- **ambientCG** — CC0 PBR materials (rock/metal/lava) — https://ambientcg.com
- **Kenney — Space Kit / Sci-Fi RTS** — CC0 props — https://kenney.nl/assets

### Audio
- **Sonniss #GameAudioGDC bundle** — royalty-free, **commercial OK, no
  attribution**, released yearly — https://gdc.sonniss.com
- **Kenney audio** — CC0 SFX — https://kenney.nl/assets (Audio category)
- **Freesound** — https://freesound.org — ⚠️ **mixed licenses per sound**: filter
  to CC0, or credit CC-BY sounds; avoid CC-BY-NC.

### Aggregators
- **Poly Pizza** (https://poly.pizza) — CC0 low-poly models (hosts Quaternius/Kenney).
- **OpenGameArt** (https://opengameart.org) — mixed licenses, **check each item**.

---

## AI generation (mind the free-tier license traps)

Useful, but **most free tiers are non-commercial** — you must be on a paid plan
for anything that ships in an IGF build.

| Tool | Use | Commercial license |
|---|---|---|
| **Meshy** (meshy.ai) | text/image → 3D (glTF/FBX) | ⚠️ free tier = CC-BY 4.0 / **non-commercial**; **Pro+** grants commercial rights |
| **Tripo** (tripo3d.ai) | text/image → 3D | ⚠️ same shape — commercial needs a **paid plan** |
| **Blockade Labs — Skybox AI** (skybox.blockadelabs.com) | text → 360° space skybox, HDRI export | ⚠️ free = **CC-BY-NC**; **Pro** required for commercial |
| **ElevenLabs** (elevenlabs.io) | SFX / voice generation | check plan; commercial on paid tiers |
| **Suno / Udio** | music generation | verify the current commercial tier before shipping a track |
| **Dream Textures** (Blender add-on) | Stable-Diffusion textures | depends on the SD model's license |

Rule of thumb: **if it's free, assume non-commercial until the license page says
otherwise**, and keep the receipt (screenshot the license tier you generated on).

---

## How the weapon pipeline works (already wired)

`scripts/weapon_viewmodel.gd` auto-loads a real model when you drop one in:

1. Put the file in `assets/thirdparty/weapons/` named after the weapon, lowercase,
   spaces → underscores: `auto_rifle`, `shotgun`, `sniper`, `hand_cannon`.
2. Extension priority: `.glb` → `.gltf` → `.tscn` → `.scn`. First match wins.
3. No file → the built-in primitive silhouette is used (nothing breaks).
4. Fit the import via the `MODEL_FIT` dict in that script (`scale`, `rot` in
   degrees, `offset`). Target: barrel down **-Z**, grip **-Y**, ~0.4 m long.

`assets/thirdparty/weapons/auto_rifle.tscn` is a worked example proving the path —
replace it with a Kenney/Fab model to see a real gun in hand.

Enemy, environment, and skybox swaps are **not** auto-wired yet — that's the
art-pass work (T-0030/T-0031).

---

## Suggested order

1. **Weapons** (Kenney Blaster Kit) — on screen constantly, and the new
   nameplates/mods make them the focal point. Pipeline is ready today.
2. **Enemies** (Quaternius robots) — biggest visual lift from the capsules.
3. **Environment textures + a space skybox** (Poly Haven) — cheap, high impact.
4. **Audio** (Sonniss) to replace the procedural synth.
