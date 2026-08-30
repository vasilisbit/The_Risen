"""Build build/windows_icon.ico (multi-size) faithful to icon.svg.

icon.svg (128 viewBox):
  rect 128x128 rx16 fill #0b1c2e
  circle 44,52 r14 fill #1a8cff
  circle 84,44 r10 fill #e03a2a
  circle 72,80 r12 fill #ff8c1a
  line 24,104 -> 104,104 stroke #8fb3d9 w6 round caps
Drawn supersampled (x8 = 1024) then downsampled to each icon size.
"""
from PIL import Image, ImageDraw
import os

SS = 8  # supersample factor over the 128 viewBox
S = 128 * SS  # 1024


def rrect(d, box, r, fill):
    d.rounded_rectangle(box, radius=r, fill=fill)


def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i+2], 16) for i in (0, 2, 4)) + (255,)


def circle(d, cx, cy, r, fill):
    d.ellipse([(cx-r)*SS, (cy-r)*SS, (cx+r)*SS, (cy+r)*SS], fill=fill)


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
rrect(d, [0, 0, S-1, S-1], 16*SS, hx("#0b1c2e"))
circle(d, 44, 52, 14, hx("#1a8cff"))
circle(d, 84, 44, 10, hx("#e03a2a"))
circle(d, 72, 80, 12, hx("#ff8c1a"))
# rounded-cap line 24,104 -> 104,104 width 6
d.line([24*SS, 104*SS, 104*SS, 104*SS], fill=hx("#8fb3d9"), width=6*SS)
for x in (24, 104):
    circle(d, x, 104, 3, hx("#8fb3d9"))

sizes = [256, 128, 64, 48, 32, 16]
frames = [img.resize((s, s), Image.LANCZOS) for s in sizes]

_build = os.path.join(os.path.dirname(__file__) or ".", "..", "build")
os.makedirs(_build, exist_ok=True)
out = os.path.normpath(os.path.join(_build, "windows_icon.ico"))
frames[0].save(out, format="ICO", sizes=[(s, s) for s in sizes], append_images=frames[1:])
print("wrote", out, "sizes", sizes)
