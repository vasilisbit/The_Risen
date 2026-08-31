#!/usr/bin/env python3
"""Generate The Risen's ground VFX decals on fal.ai (nano-banana-pro albedo -> soft-edge
alpha + patina PBR), consumed by Godot `Decal` nodes via scripts/vfx_kit.gd (_decal).

Reconciled VFX pipeline: fal's real VFX role is DECALS + SFX; the particle/pattern masks
are Godot-baked (tools/bake_vfx_textures.gd). See docs/VFX_WORKFLOW.md + planning
docs/VFX_FAL_RESEARCH.md §11.6.

Pipeline per decal:
  1. nano-banana-pro -> a top-down circular mark on ground  (raw/<name>_albedo.png)
  2. PIL -> soft-edge alpha (radial feather + per-type luminance emphasis) so it blends
     onto ANY ground when projected  (<name>.png, RGBA)
  3. crater only: an emission map of the glowing lava  (<name>_emission.png)
  4. fal-ai/patina -> a normal map for surface relief  (<name>_normal.png)

    uv run python tools/gen_vfx_decals.py                 # generate anything missing
    uv run python tools/gen_vfx_decals.py --only scorch   # one (validate before a batch)
    uv run python tools/gen_vfx_decals.py --force         # regenerate albedos too
    uv run python tools/gen_vfx_decals.py --no-patina     # skip normal maps (cheaper)

Auth: FAL_KEY from .env.local (via tools/falgen.py). ~$0.15/nano image + ~$0.05/patina.
"""
import os, sys, math, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECAL_DIR = os.path.join(ROOT, "assets", "generated", "vfx", "decals")
RAW_DIR = os.path.join(DECAL_DIR, "raw")
FALGEN = os.path.join(ROOT, "tools", "falgen.py")

# name -> (prompt, alpha_mode). alpha_mode: "dark" (char/cracks favour dark pixels),
# "full" (whole circular mark kept, just feathered), "crack" (only the dark cracks show).
DECALS = {
    "scorch": (
        "Top-down orthographic aerial view, perfect 1:1 square, of a circular explosion "
        "scorch burn mark on flat ground. Black soot and charred cracked earth radiating "
        "from the center, fading smoothly outward to clean bare grey dirt at the edges. "
        "Radial symmetric burn, no objects, no debris, no text, photorealistic, centered, "
        "dark sooty core.", "dark"),
    "crater": (
        "Top-down orthographic aerial view, perfect 1:1 square, of a small volcanic impact "
        "crater. A ring of dark charred cracked black rock around a glowing molten core: "
        "bright orange and yellow lava seams and cracks radiating from the center, red-hot "
        "embers. Fades to dark rock at the edges. Radial, centered, no objects, no text, "
        "photorealistic, intense molten glow.", "full"),
    "ground_crack": (
        "Top-down orthographic aerial view, perfect 1:1 square, of a radial fracture "
        "pattern in grey stone ground: sharp dark cracks spider-webbing outward from a "
        "central impact point, broken shattered rock, fading to intact stone at the edges. "
        "Clean grey rock background, no objects, no text, photorealistic, centered.", "crack"),
}


def _falgen(*args):
    subprocess.run([sys.executable, FALGEN, *args], check=True)


def _albedo(name, prompt, force):
    raw = os.path.join(RAW_DIR, f"{name}_albedo.png")
    if os.path.exists(raw) and not force:
        print("[reuse]", raw)
        return raw
    print("[gen]", name, "albedo")
    _falgen("image", prompt, raw)
    return raw


def _process(name, raw, mode):
    from PIL import Image
    src = Image.open(raw).convert("RGB")
    W, H = src.size
    px = src.load()
    cx, cy, R = W / 2.0, H / 2.0, min(W, H) / 2.0
    out = Image.new("RGBA", (W, H))
    op = out.load()
    emis = Image.new("RGBA", (W, H), (0, 0, 0, 255)) if name == "crater" else None
    ep = emis.load() if emis else None
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            d = math.hypot(x - cx, y - cy) / R
            edge = max(0.0, min(1.0, 1.0 - (d - 0.72) / 0.26))
            edge = edge * edge * (3 - 2 * edge)              # smoothstep feather
            if mode == "dark":
                dark = max(0.0, min(1.0, (0.72 - lum) / 0.72))
                a = edge * (0.30 + 0.85 * dark)
            elif mode == "crack":
                dark = max(0.0, min(1.0, (0.55 - lum) / 0.55))
                a = edge * (0.05 + 1.15 * dark)              # mostly the cracks
            else:  # full
                a = edge
            op[x, y] = (r, g, b, int(max(0.0, min(1.0, a)) * 255))
            if ep is not None:
                # emission = the hot (bright, warm) lava; boost orange/yellow
                warm = max(0.0, (r - b) / 255.0)
                hot = max(0.0, min(1.0, (lum - 0.35) / 0.65)) * (0.4 + 0.6 * warm)
                ep[x, y] = (int(r * hot), int(g * hot * 0.8), int(b * hot * 0.4), 255)
    out.save(os.path.join(DECAL_DIR, f"{name}.png"))
    print("[save]", f"{name}.png")
    if emis is not None:
        emis.convert("RGB").save(os.path.join(DECAL_DIR, f"{name}_emission.png"))
        print("[save]", f"{name}_emission.png")


def _patina(name):
    albedo = os.path.join(DECAL_DIR, f"{name}.png")
    prefix = os.path.join(DECAL_DIR, name)
    print("[patina]", name)
    _falgen("patina", albedo, prefix, "--maps", "normal")


def main():
    os.makedirs(RAW_DIR, exist_ok=True)
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    force = "--force" in sys.argv
    do_patina = "--no-patina" not in sys.argv
    for name, (prompt, mode) in DECALS.items():
        if only and name != only:
            continue
        raw = _albedo(name, prompt, force)
        _process(name, raw, mode)
        if do_patina:
            _patina(name)
    print("done.")


if __name__ == "__main__":
    main()
