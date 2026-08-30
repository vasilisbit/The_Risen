"""Generate the game's window/app icon emblem via fal.ai (nano-banana-pro).

Writes build/icon_source.png (1:1). Then run tools/make_icon.py to flood-fill the
corners and emit build/windows_icon.ico + icon.png. Committed source so the icon is
reproducible. ~$0.15 fal.

Run:  uv run --no-project python tools/gen_icon.py
"""
import subprocess, os, sys

HERE = os.path.dirname(__file__) or "."
PROMPT = (
    "App icon / game logo emblem for a sci-fi first-person looter-shooter titled THE "
    "RISEN. A single bold centered emblem: a stylized armored Guardian helmet seen "
    "head-on, smooth dark gunmetal plating with clean facets, a glowing teal-cyan energy "
    "visor slit and thin cracks of teal soulfire light, subtle brushed-gold trim edges, "
    "sitting on a very dark navy near-black background with a soft circular teal rim-glow "
    "behind it. Flat modern app-icon style, strong silhouette, high contrast, crisp, "
    "minimal, iconic, perfectly centered square composition, readable when shrunk to a "
    "tiny size, NO text, NO letters, professional game icon."
)
out = os.path.join(HERE, "..", "build", "icon_source.png")
subprocess.run([
    "uv", "run", "--no-project", "python", os.path.join(HERE, "falgen.py"),
    "image", PROMPT, out, "--model", "fal-ai/nano-banana-pro",
], check=True)
print("wrote", os.path.normpath(out), "- now run tools/make_icon.py")
