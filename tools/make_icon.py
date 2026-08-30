"""Build the game window icon from the fal.ai-generated emblem.

Input : build/icon_source.png  (nano-banana-pro Guardian-helmet emblem; the kit's
        transparent/white corners are flood-filled to dark navy so it reads as a
        clean full-bleed app icon).
Output: build/windows_icon.ico  (multi-size Windows icon, used by export_presets.cfg)
        icon.png                (256px project icon, project.godot config/icon)

Regenerate the source emblem via tools/gen_icon.py (fal.ai), then run this.
Run:  uv run --no-project python tools/make_icon.py
"""
from PIL import Image, ImageDraw
import os

HERE = os.path.dirname(__file__) or "."
ROOT = os.path.normpath(os.path.join(HERE, ".."))
SRC = os.path.join(ROOT, "build", "icon_source.png")
BG = (9, 16, 27)  # dark navy to match the emblem's own backdrop

img = Image.open(SRC).convert("RGB")
w, h = img.size
# Flood-fill the (near-white) background inward from each corner. This only
# recolours the connected corner region, never the helmet's interior highlights.
for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
    ImageDraw.floodfill(img, corner, BG, thresh=60)

rgba = img.convert("RGBA")
sizes = [256, 128, 64, 48, 32, 16]
frames = [rgba.resize((s, s), Image.LANCZOS) for s in sizes]

ico = os.path.join(ROOT, "build", "windows_icon.ico")
frames[0].save(ico, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[1:])
print("wrote", ico, "sizes", sizes)

# 256px project icon (project.godot config/icon = res://icon.png)
png = os.path.join(ROOT, "icon.png")
frames[0].save(png)
print("wrote", png)
