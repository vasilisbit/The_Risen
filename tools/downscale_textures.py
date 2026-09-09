#!/usr/bin/env python
"""Downscale generated runtime textures to the PERFORMANCE_BUDGET limits and fix
lossless/no-mipmap import settings on the ground-terrain PNGs (T-0036/T-0037).

- Ground/terrain PBR PNGs + planet maps          -> max 1024, VRAM-compressed + mipmaps
- Extracted glTF model textures (_Color/_NormalGL/_ORM.jpg)
    * weapons / viewmodels (seen in FP close-up)  -> max 1024
    * everything else (rocks/structures/props)    -> max 512
- SKIPPED: /raw/, *_concept, *_front, *_back, fold/*, _ship_ref, ui/* (2D HUD),
  and anything already at/under its target.

Idempotent: only rewrites files larger than their target. Run:
    uv run --no-project python tools/downscale_textures.py [--apply]
Without --apply it only prints the plan (dry run).
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "assets" / "generated"
APPLY = "--apply" in sys.argv

SKIP_SUBSTR = ("/raw/", "_concept", "_front", "_back", "_ship_ref")
SKIP_DIRS = ("assets/generated/fold", "assets/generated/ui")
# Kept at native resolution on purpose: the Forge Master is shown large + close-up in the
# vendor / item screen, where 1024 read too soft (user feedback 2026-08-30). Do NOT downscale.
KEEP_FULL = ("assets/generated/hub/forge_master_texture_0.png",)


def target_for(rel: str) -> int | None:
    p = rel.replace("\\", "/")
    if any(s in p for s in SKIP_SUBSTR):
        return None
    if any(p.endswith(k) for k in KEEP_FULL):
        return None
    if any(p.startswith(d) for d in SKIP_DIRS):
        return None
    # FP close-up hero gear textures keep 1024.
    if "/weapons/" in p or "/viewmodels/" in p:
        return 1024
    # Extracted glTF model textures -> 512 (props/rocks/structures/armor/ship/interior console/vfx).
    if p.endswith(".jpg") and ("_Color" in p or "_NormalGL" in p or "_ORM" in p or "_Normal" in p or "_Metallic" in p or "_Roughness" in p):
        return 512
    # Standalone ground/terrain/planet PNGs (albedo/normal/roughness maps, planet equirect).
    if p.endswith(".png"):
        return 1024
    # Other loose jpgs (planet maps saved as jpg, etc.)
    if p.endswith(".jpg") or p.endswith(".jpeg"):
        return 1024
    return None


def main() -> None:
    plan = []
    for fp in sorted(GEN.rglob("*")):
        if fp.suffix.lower() not in (".png", ".jpg", ".jpeg"):
            continue
        rel = fp.relative_to(ROOT).as_posix()
        t = target_for(rel)
        if t is None:
            continue
        try:
            with Image.open(fp) as im:
                w, h = im.size
        except Exception as e:
            print(f"  !! cannot open {rel}: {e}")
            continue
        if max(w, h) <= t:
            continue
        plan.append((fp, rel, (w, h), t))

    total_before = sum(f.stat().st_size for f, *_ in plan)
    print(f"{'APPLY' if APPLY else 'DRY-RUN'}: {len(plan)} files to downscale "
          f"({total_before/1048576:.1f} MB current on-disk)")
    saved = 0
    for fp, rel, (w, h), t in plan:
        scale = t / max(w, h)
        nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
        before = fp.stat().st_size
        if APPLY:
            with Image.open(fp) as im:
                mode = im.mode
                im = im.resize((nw, nh), Image.LANCZOS)
                if fp.suffix.lower() in (".jpg", ".jpeg"):
                    if im.mode not in ("RGB", "L"):
                        im = im.convert("RGB")
                    im.save(fp, quality=92, optimize=True)
                else:
                    im.save(fp, optimize=True)
            after = fp.stat().st_size
            saved += (before - after)
            print(f"  {w}x{h}->{nw}x{nh}  {before//1024}->{after//1024}KB  {rel}")
        else:
            print(f"  {w}x{h}->{nw}x{nh} (target {t})  {before//1024}KB  {rel}")
    if APPLY:
        print(f"Reclaimed {saved/1048576:.1f} MB on disk. "
              f"Reimport in Godot (filesystem scan) to rebuild .godot/imported.")


if __name__ == "__main__":
    main()
