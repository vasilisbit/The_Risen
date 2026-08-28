#!/usr/bin/env python3
"""Generate The Risen's HUD/UI icon set on fal.ai (nano-banana-pro).

T-0045. Produces a cohesive, Destiny-style set of FLAT MONOCHROME glyph icons
with a clean alpha channel, so each HUD can tint them in-engine (ability colour,
weapon-slot/rarity gold, shield cyan, ...).

Technique (bulletproof alpha): prompt each icon as a *pure white glyph on a
solid pure black background* (unambiguous for the model), then key it in Pillow
by luminance -> alpha (black => transparent, white => opaque, anti-aliased edges
=> partial alpha). RGB is forced to white so the result tints cleanly. This does
not rely on the model emitting a real alpha channel.

Run via: uv run --no-project python tools/gen_ui_icons.py <one KEY | batch | sheet>
  one KEY   generate a single icon (validation)
  batch     generate every icon
  sheet     compose a contact sheet of whatever icons already exist (no gen)

Icons land in assets/generated/ui/<key>.png (RGBA). Raw model output is kept in
assets/generated/ui/raw/<key>_raw.png for reference.
"""
import os, sys, io, json, urllib.request
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import falgen  # reuse the queue runner + key loader

ROOT = falgen.ROOT
OUT = os.path.join(ROOT, "assets", "generated", "ui")
RAW = os.path.join(OUT, "raw")
MODEL = "fal-ai/nano-banana-pro"

STYLE = (
    "Flat 2D video-game HUD icon. A single pure white glyph, perfectly centered, "
    "on a solid pure black (#000000) background. Bold clean geometric vector line-art, "
    "thick and CONSISTENT line weight, crisp high-contrast, filled solid white shapes, "
    "symmetric, readable at small size. Sci-fi military insignia style in the spirit of "
    "Destiny 2 ability and gear icons. Fills ~80% of the frame with a small margin. "
    "NO text, NO letters, NO numbers, NO gradient, NO drop shadow, NO grey, NO extra "
    "objects, NO background detail — only the white glyph on flat black."
)

# key -> subject description
ICONS = {
    # --- ability cluster (bottom-left) ---
    "super": "a radiant multi-pointed starburst super-ability emblem, sharp rays of light bursting from a bright core",
    "grenade": "a round fragmentation grenade seen from the side with a short lit fuse on top, a thrown-grenade ability glyph",
    "melee": "a single clenched armored fist punching forward toward the viewer with a few sharp angular impact-flash lines radiating from the knuckles, a melee-strike ability glyph, NO frame, NO box, NO border, NO square around it",
    # --- weapon types (weapon panel + loot icons); side profile, barrel to the LEFT ---
    "wpn_auto_rifle": "a side profile silhouette of a sci-fi automatic assault rifle with a boxy receiver, straight magazine and long thin barrel, barrel pointing LEFT",
    "wpn_shotgun": "a side profile silhouette of a heavy pump-action combat shotgun with a short wide barrel and pump under the barrel, barrel pointing LEFT",
    "wpn_sniper": "a side profile silhouette of a long sci-fi sniper rifle with a prominent scope on top and a folding bipod, barrel pointing LEFT",
    "wpn_hand_cannon": "a side profile silhouette of a chunky sci-fi revolver hand-cannon pistol with a fat cylinder and short barrel, barrel pointing LEFT",
    # --- armour slots (loot icons) ---
    "armor_helmet": "a front view of a sci-fi guardian combat helmet with a horizontal visor slit",
    "armor_chest": "a front view of a sci-fi armored chest breastplate with a central ridge and shoulder guards",
    "armor_gauntlets": "a single sci-fi armored gauntlet, a forearm guard with layered knuckle plates",
    # --- vitals (top-centre bar caps) ---
    "shield": "a heraldic energy-shield emblem, a rounded shield outline with a bold chevron across it",
    "health": "an angular vitality emblem, a bold upward chevron arrow inside a hexagon, representing health (NOT a medical cross)",
}


def gen(key: str) -> None:
    prompt = "%s Subject: %s." % (STYLE, ICONS[key])
    payload = {
        "prompt": prompt,
        "aspect_ratio": "1:1",
        "resolution": "1K",
        "output_format": "png",
        "num_images": 1,
    }
    print("... generating", key)
    res = falgen.run(MODEL, payload)
    url = falgen.first_url(res)
    if not url:
        print("NO_URL for", key, ":", json.dumps(res)[:500]); return
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    raw_bytes = urllib.request.urlopen(url, timeout=180).read()
    raw_path = os.path.join(RAW, key + "_raw.png")
    with open(raw_path, "wb") as f:
        f.write(raw_bytes)
    key_to_alpha(raw_bytes, os.path.join(OUT, key + ".png"))
    print("SAVED", os.path.join("assets/generated/ui", key + ".png"))


def key_to_alpha(raw_bytes: bytes, out_path: str, size: int = 512) -> None:
    """White-glyph-on-black -> white RGBA glyph with luminance alpha, trimmed & centered."""
    img = Image.open(io.BytesIO(raw_bytes)).convert("RGB")
    lum = img.convert("L")  # luminance == alpha (black bg -> 0, white glyph -> 255)
    # Trim to the glyph's bounding box (drop the black margin), then re-pad square.
    bbox = lum.point(lambda v: 255 if v > 16 else 0).getbbox()
    if bbox:
        lum = lum.crop(bbox)
    w, h = lum.size
    side = max(w, h)
    pad = int(side * 0.12)  # small even margin
    canvas = Image.new("L", (side + 2 * pad, side + 2 * pad), 0)
    canvas.paste(lum, ((canvas.width - w) // 2, (canvas.height - h) // 2))
    canvas = canvas.resize((size, size), Image.LANCZOS)
    white = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    white.putalpha(canvas)
    white.save(out_path)


def contact_sheet() -> None:
    """Compose an on-screen preview: each icon tinted gold on a dark card."""
    keys = [k for k in ICONS if os.path.exists(os.path.join(OUT, k + ".png"))]
    if not keys:
        print("no icons yet"); return
    cell, cols = 150, 4
    rows = (len(keys) + cols - 1) // cols
    gold = (212, 175, 96)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (22, 24, 28, 255))
    for i, k in enumerate(keys):
        ic = Image.open(os.path.join(OUT, k + ".png")).convert("RGBA").resize((110, 110), Image.LANCZOS)
        # tint white glyph -> gold, keep alpha
        r, g, b, a = ic.split()
        tinted = Image.merge("RGBA", (
            r.point(lambda v: int(v * gold[0] / 255)),
            g.point(lambda v: int(v * gold[1] / 255)),
            b.point(lambda v: int(v * gold[2] / 255)), a))
        cx = (i % cols) * cell + (cell - 110) // 2
        cy = (i // cols) * cell + (cell - 110) // 2
        sheet.alpha_composite(tinted, (cx, cy))
    path = os.path.join(OUT, "_contact_sheet.png")
    sheet.convert("RGB").save(path)
    print("SHEET", path)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__); return
    cmd = sys.argv[1]
    if cmd == "one":
        gen(sys.argv[2])
    elif cmd == "batch":
        for k in ICONS:
            if os.path.exists(os.path.join(OUT, k + ".png")) and "--force" not in sys.argv:
                print("skip (exists)", k); continue
            gen(k)
        contact_sheet()
    elif cmd == "sheet":
        contact_sheet()
    else:
        print("unknown", cmd)


if __name__ == "__main__":
    main()
