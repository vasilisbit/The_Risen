"""Generate the game's window/app icon emblem via fal.ai (nano-banana-pro).

A minimalist, symmetric emblem in the spirit of a clean single-colour game crest
(bold silhouette + subtle grunge) but ORIGINAL to The Risen: a "rising Guardian"
mark, off-white with a sliver of teal soulfire, rendered on flat black so
make_icon.py can key the background to full transparency.

Writes build/icon_source.png (1:1). Then run tools/make_icon.py to key out the
black background and emit build/windows_icon.ico + icon.png. ~$0.15 fal.

Run:  uv run --no-project python tools/gen_icon.py
"""
import subprocess, os

HERE = os.path.dirname(__file__) or "."
PROMPT = (
    "A minimalist flat vector emblem logo for a sci-fi game called THE RISEN. A single "
    "bold, symmetric mark suggesting a RISING guardian ascending: a strong central "
    "vertical spire flanked by two clean upswept angular wing-like prongs sweeping upward "
    "and outward from a solid base, simple geometric silhouette. The shape is a solid "
    "off-white / light silver-grey with a subtle weathered speckled grunge texture, and a "
    "single thin sliver of glowing teal-cyan soulfire light runs up the central core. "
    "Minimalist iconic game crest, perfectly symmetric, bold negative space, centered, "
    "on a pure flat solid black background (#000000, no gradient). High contrast, crisp "
    "clean edges, no text, no letters, no numbers, no watermark, no logo type."
)
out = os.path.join(HERE, "..", "build", "icon_source.png")
subprocess.run([
    "uv", "run", "--no-project", "python", os.path.join(HERE, "falgen.py"),
    "image", PROMPT, out, "--model", "fal-ai/nano-banana-pro",
], check=True)
print("wrote", os.path.normpath(out), "- now run tools/make_icon.py")
