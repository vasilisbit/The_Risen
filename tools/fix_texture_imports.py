#!/usr/bin/env python
"""Fix import settings on generated 3D textures that were imported LOSSLESS with
mipmaps OFF (compress/mode=0) — the ground/terrain PBR PNGs and a few extracted
model jpgs. Lossless 3D textures cost ~4x the VRAM and shimmer at distance with no
mipmaps. This sets them to VRAM-compressed + mipmaps (T-0036/T-0037).

Only touches runtime 3D textures (same skip rules as downscale_textures.py: no
concepts, /raw/, ui/ 2D HUD icons, or fold/ video inputs). Idempotent.

    uv run --no-project python tools/fix_texture_imports.py [--apply]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "assets" / "generated"
APPLY = "--apply" in sys.argv

SKIP_SUBSTR = ("/raw/", "_concept", "_front", "_back", "_ship_ref")
SKIP_DIRS = ("assets/generated/fold", "assets/generated/ui")


def is_runtime_3d(rel: str) -> bool:
    p = rel.replace("\\", "/")
    if any(s in p for s in SKIP_SUBSTR):
        return False
    if any(p.startswith(d) for d in SKIP_DIRS):
        return False
    return p.endswith((".png", ".jpg", ".jpeg"))


def patch(text: str, is_normal: bool) -> tuple[str, list[str]]:
    changes = []
    out = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("compress/mode="):
            if s != "compress/mode=2":
                out.append("compress/mode=2"); changes.append("mode->2"); continue
        elif s.startswith("mipmaps/generate="):
            if s != "mipmaps/generate=true":
                out.append("mipmaps/generate=true"); changes.append("mipmaps->true"); continue
        elif s.startswith("compress/normal_map=") and is_normal:
            if s != "compress/normal_map=1":
                out.append("compress/normal_map=1"); changes.append("normal_map->1"); continue
        elif s.startswith("detect_3d/compress_to="):
            # stop the editor re-flipping compression on 3D-detect
            if s != "detect_3d/compress_to=0":
                out.append("detect_3d/compress_to=0"); changes.append("detect_3d->0"); continue
        out.append(line)
    return "\n".join(out) + ("\n" if text.endswith("\n") else ""), changes


def main() -> None:
    n = 0
    for imp in sorted(GEN.rglob("*.import")):
        src = imp.with_suffix("")  # strip .import
        rel = src.relative_to(ROOT).as_posix()
        if not is_runtime_3d(rel):
            continue
        text = imp.read_text(encoding="utf-8")
        if "compress/mode=0" not in text and "mipmaps/generate=false" not in text:
            continue  # already fine
        is_normal = ("normal" in rel.lower()) or ("normalgl" in rel.lower())
        new, changes = patch(text, is_normal)
        if changes:
            n += 1
            print(f"  {rel}: {', '.join(changes)}")
            if APPLY:
                imp.write_text(new, encoding="utf-8")
    print(f"{'APPLIED' if APPLY else 'DRY-RUN'}: {n} .import files to fix")


if __name__ == "__main__":
    main()
