# UI asset generation prompts (Nano Banana 2 / Gemini Image / similar)

Every UI element in The Risen is currently drawn in code (primitives, `_draw`
calls, plain `Label`s). This file lists each element you can replace with a
generated image, with a ready-to-paste prompt. Built for **Nano Banana 2**
(Google's Gemini image model) but works with any capable image generator
(Midjourney, SDXL, DALL·E, Ideogram).

## How to use

1. Paste the **Style preamble** below in front of each element prompt (keeps a
   consistent look across the whole UI).
2. Ask for a **transparent background (PNG with alpha)** for anything that
   overlays the game (icons, frames, crosshair, bars). Backgrounds/splashes can
   be opaque.
3. Generate at 2× the on-screen size for crispness, power-of-two where it's a
   texture (e.g. 256×256, 512×512).
4. Save into the matching `assets/thirdparty/ui/...` folder (make it), and note
   the source + license in `CREDITS.md`. **Nano Banana / Gemini images: check
   the plan's commercial terms** — The Risen is IGF-bound, so free-tier
   non-commercial output can't ship.
5. Keep a **seed / the first good image** and say "same style as this" for the
   rest, so the set matches.

### Style preamble (prepend to every prompt)

> Game UI asset for a sci-fi looter-shooter called "The Risen", Destiny-inspired.
> Dark near-black background theme with brushed gunmetal, thin glowing edges,
> gold (#F2C74E) primary accent and cool cyan secondary. Clean, high-contrast,
> readable at small sizes, subtle bevels, no text unless specified, no drop
> shadows baked in. Flat-ish semi-realistic game-UI style, crisp vector-like
> edges. Transparent background, PNG with alpha, centered, generous padding.

---

## 1. HUD

| Element | Where in code | Prompt (after the style preamble) |
|---|---|---|
| **Crosshair** | `DebugHUD/Crosshair` | "A minimal FPS crosshair: four short tapered marks around a tiny center dot, thin cyan lines with a faint gold core, 128×128, transparent." |
| **Health bar frame** | HP/Shield bars top-left | "A horizontal segmented status-bar frame, angled sci-fi ends, hollow interior to fill with a health color, gold trim, 512×64, transparent." |
| **Shield bar frame** | shield bar | "Same status-bar frame as the health bar but with a cyan-blue trim, for a shield gauge, 512×64, transparent." |
| **Weapon panel** | `weapon_hud.gd` | "A bottom-right weapon readout panel: a beveled dark trapezoid plate with a large ammo-number area and a small reserve area divided by a thin gold line, angular Destiny-style, 660×332, transparent." |
| **Ammo/mag glyph** | reserve '∞' | "A small ammunition/magazine glyph, gold on transparent, 64×64." |

## 2. Weapon icons (inventory + HUD) — one per type

Folder idea: `assets/thirdparty/ui/weapons/`. Side-on silhouettes, barrel left.

| Weapon | Prompt |
|---|---|
| **Auto Rifle** | "A side-profile icon of a sci-fi automatic rifle, boxy receiver, long barrel, tall magazine, gunmetal with blue energy accents, barrel pointing left, 256×256, transparent." |
| **Shotgun** | "A side-profile icon of a sci-fi combat shotgun, short fat twin-barrel with a pump, gunmetal with green accents, barrel left, 256×256, transparent." |
| **Sniper** | "A side-profile icon of a sci-fi sniper rifle, long thin barrel, prominent scope, violet energy accents, barrel left, 256×256, transparent." |
| **Hand Cannon** | "A side-profile icon of a sci-fi hand cannon / heavy revolver, stubby barrel, fat cylinder, amber accents, barrel left, 256×256, transparent." |

## 3. Rarity frames (item icon borders)

Folder: `assets/thirdparty/ui/rarity/`. Square frames to sit behind a weapon icon.

| Rarity | Prompt |
|---|---|
| **Common** | "A square item-slot frame, thin neutral grey-white border, faint inner glow, empty center, 256×256, transparent." |
| **Rare** | "Same square item-slot frame, blue (#3A9EFF) glowing border, 256×256, transparent." |
| **Epic** | "Same square item-slot frame, purple (#A45BFF) glowing border, slightly ornate corners, 256×256, transparent." |
| **Exotic** | "Same square item-slot frame, gold (#FFCB33) glowing border, ornate corners, a small notch/emblem top-center, premium feel, 256×256, transparent." |

## 4. Abilities (bottom-left cluster)

Folder: `assets/thirdparty/ui/abilities/`. Monochrome-on-transparent glyphs that
get tinted by class color in engine.

| Ability | Prompt |
|---|---|
| **Super — Storm Barrage** (Assault) | "A circular ability icon: a cluster of homing rockets radiating outward, aggressive, single-color white glyph on transparent, 256×256." |
| **Super — Guardian Dome** (Support) | "A circular ability icon: a protective dome/hemisphere shield over a figure, white glyph on transparent, 256×256." |
| **Super — Juggernaut Charge** (Tank) | "A circular ability icon: a charging armored figure with motion streaks, white glyph on transparent, 256×256." |
| **Grenade — Frag** | "A grenade ability glyph: a round fragmentation grenade with burst lines, white on transparent, 192×192." |
| **Grenade — Healing** | "A grenade ability glyph: a canister emitting a soft cross / plus, white on transparent, 192×192." |
| **Grenade — Flashbang** | "A grenade ability glyph: a stun grenade with radiating flash rays, white on transparent, 192×192." |
| **Melee — Energy Blade** | "A melee ability glyph: an energy blade slash arc, white on transparent, 192×192." |
| **Melee — EMP Punch** | "A melee ability glyph: a fist with an electric burst, white on transparent, 192×192." |
| **Melee — Ground Slam** | "A melee ability glyph: a downward fist with shockwave rings, white on transparent, 192×192." |
| **Super diamond frame** | "A diamond-shaped ability charge frame with a beveled gold edge and a hollow center, Destiny super style, 256×256, transparent." |
| **Ability tile frame** | "A small rounded-square ability tile frame, dark fill, thin gold edge, 128×128, transparent." |

## 5. Elements & weapon mods

Folder: `assets/thirdparty/ui/elements/`.

| Element/Mod | Prompt |
|---|---|
| **Solar** | "A small elemental symbol for Solar: a stylized flame/sun burst, orange (#FF8C2E) on transparent, 128×128." |
| **Arc** | "A small elemental symbol for Arc: a lightning bolt / electric arc, cyan (#59CCFF) on transparent, 128×128." |
| **Void** | "A small elemental symbol for Void: a collapsing purple sphere / singularity, violet (#B266FF) on transparent, 128×128." |
| **Kinetic** | "A small elemental symbol for Kinetic: a simple angular chevron/bullet mark, neutral white on transparent, 128×128." |
| **Fire-Rate mod** | "A weapon-mod chip icon: a coil / rate-of-fire meter, gunmetal square chip, gold detail, 128×128, transparent." |
| **Magazine mod** | "A weapon-mod chip icon: an extended magazine, gunmetal chip, 128×128, transparent." |

## 6. Armor icons

Folder: `assets/thirdparty/ui/armor/`.

| Slot | Prompt |
|---|---|
| **Helmet** | "A front-facing sci-fi helmet icon with a visor slit, gunmetal with gold trim, 256×256, transparent." |
| **Chest Plate** | "A sci-fi breastplate/chest armor icon, gunmetal with gold trim, 256×256, transparent." |
| **Gauntlets** | "A pair of sci-fi armored gauntlets icon, gunmetal with gold trim, 256×256, transparent." |

## 7. Enemy nameplate

| Element | Prompt |
|---|---|
| **Nameplate bar** | "A floating enemy health-bar frame, thin angular sci-fi ends, hollow fill area, red-tinted for enemies, 512×48, transparent." |
| **Boss nameplate** | "A wider, ornate enemy health-bar frame with gold trim and small side wings, for a boss, 640×64, transparent." |

## 8. Cards & panels (full-screen menus)

Folder: `assets/thirdparty/ui/panels/`. These are the biggest visual wins.

| Element | Prompt |
|---|---|
| **Upgrade / buff card** | "A vertical selection card frame, dark glass fill, thin colored top strip (leave blank to tint), beveled corners, room for a title and description, 300×360, transparent." |
| **Difficulty card** | "A vertical difficulty card frame matching the upgrade card, dark glass, gold edge, 300×340, transparent." |
| **Class card** (Assault/Support/Tank) | "A tall character-class selection card frame, sci-fi, dark glass with a colored header band and an emblem slot, 360×460, transparent." |
| **Inventory panel** | "A large inventory window frame, dark brushed-metal with a gold border, header bar, and two column dividers, 900×600, transparent." |
| **Vendor (Forge Master) panel** | "A shop terminal window frame, industrial forge aesthetic, dark metal with orange forge glow accents and a gold border, tab strip at top, 760×560, transparent." |
| **Objective list plate** | "A small top-left objective tracker plate, dark translucent strip with a gold left edge, 360×220, transparent." |
| **Extraction / wave banner** | "A centered mission banner ribbon, dark with gold edges, wide and short, for a countdown message, 720×90, transparent." |

## 9. Screens & branding (opaque, no alpha needed)

| Element | Prompt |
|---|---|
| **Game logo** | "A game logo wordmark reading 'THE RISEN', sci-fi military stencil with a subtle gold-to-orange gradient and a faint rising ember motif, on transparent." |
| **Main menu background** | "A moody sci-fi main-menu background: the view from a starship cockpit over a dark blue-to-black starfield with distant planets (Earth, Mars, Venus), cinematic, no UI, no text, 1920×1080." |
| **Death screen** | "A full-screen 'YOU DIED' overlay treatment: dark red vignette, cracked-glass edges, ominous, space for centered text, 1920×1080." |
| **Class-select background** | "A hangar / armory backdrop for a class selection screen, three lit pedestals, dark industrial, no text, 1920×1080." |
| **Flux currency icon** | "A small currency icon for 'Flux': a glowing gold hexagonal energy shard, 128×128, transparent." |
| **Planet holograms** | "A holographic planet projection: a wireframe-and-scanline globe of Earth in cyan-gold hologram style, semi-transparent, glitchy scanlines, on transparent, 512×512." (repeat for Mars = red, Venus = orange) |

---

## Wiring notes

- Icons/frames are `TextureRect`, `Sprite2D`, or a `StyleBoxTexture` on the
  existing panels — mostly a drop-in for the current `_draw`/`StyleBoxFlat` code.
- The weapon icons can feed `LootIcon` (`scripts/weapon_icon.gd`) and the weapon
  HUD glyphs (`scripts/weapon_hud.gd`) — swap the `_draw_weapon_glyph` calls for
  a texture lookup by weapon name.
- Rarity frames pair with `LootIcon.RARITY_COLORS`.
- Element symbols pair with `Weapon.ELEMENT_COLORS`.
- Do the **panels and cards first** — they're on screen the longest and lift the
  whole game's feel the most; icons second.
- Log every generated asset in `CREDITS.md` with the tool, tier and date.
