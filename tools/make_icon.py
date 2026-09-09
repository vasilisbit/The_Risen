"""Turn the fal.ai emblem (build/icon_source.png, mark on flat black) into a
TRANSPARENT window/app icon.

The background is keyed out by luminance (the off-white mark survives) OR'd with a
teal-ness key (the teal soulfire core survives), so black -> fully transparent while
the mark keeps crisp, anti-aliased edges. Emits:
  build/windows_icon.ico  (multi-size, used by export_presets.cfg -> the window/exe icon)
  icon.png                (256px, project.godot config/icon)

Regenerate the source via tools/gen_icon.py, then run this.
Run:  uv run --no-project python tools/make_icon.py
"""
from PIL import Image
import os

HERE = os.path.dirname(__file__) or "."
ROOT = os.path.normpath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "build", "icon_source.png")

LO, HI = 0.10, 0.40   # luminance smoothstep band (below LO -> transparent)

img = Image.open(SRC).convert("RGB")
px = img.load()
w, h = img.size
out = Image.new("RGBA", (w, h))
op = out.load()
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        # teal/cyan-ness: green+blue high while red low
        teal = max(0.0, (0.5 * (g + b) - r) / 255.0)
        a = (lum - LO) / (HI - LO)
        a = 0.0 if a < 0.0 else (1.0 if a > 1.0 else a)
        a = max(a, min(1.0, teal * 2.0))
        op[x, y] = (r, g, b, int(round(a * 255)))

# Autocrop to the mark's bounds (+ small margin), then pad to a centered square so
# the emblem fills the icon consistently.
bbox = out.getbbox()
if bbox:
    m = 12
    l, t, r2, b2 = bbox
    l = max(0, l - m); t = max(0, t - m); r2 = min(w, r2 + m); b2 = min(h, b2 + m)
    cropped = out.crop((l, t, r2, b2))
    side = max(cropped.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    out = sq

sizes = [256, 128, 64, 48, 32, 16]
frames = [out.resize((s, s), Image.LANCZOS) for s in sizes]

ico = os.path.join(ROOT, "build", "windows_icon.ico")
frames[0].save(ico, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[1:])
print("wrote", ico, "sizes", sizes)

png = os.path.join(ROOT, "icon.png")
frames[0].save(png)
print("wrote", png)
