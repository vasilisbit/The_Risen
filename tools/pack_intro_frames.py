#!/usr/bin/env python3
"""Pack the intro cinematic into a FREE, core-Godot playable form: a single frame-pack blob
plus the mixed audio, for scripts/ship_travel.gd's built-in image-sequence player.

Why this exists: Godot 4.7's core VideoStreamPlayer only decodes Theora, and every Theora encode
of this film macroblocks in-engine (see game-dev-the-risen/docs/INTRO_CINEMATIC_PLAN.md). The only
mp4 addon (GDE GoZen) is paid/compile-your-own. So instead of a video codec we ship the film as a
compact WebP frame sequence packed into ONE file (no 2700-file import churn) + the mixed audio as
Ogg Vorbis, and play them in sync from GDScript - no addon, no purchase, plays straight from res://.

Pipeline (needs ffmpeg on PATH):
  intro.mp4 --(ffmpeg fps filter)--> N WebP frames --> intro_frames.bin  (custom pack)
  intro.mp4 --(ffmpeg)------------->                    intro_audio.ogg  (vorbis, the baked mix)

Pack format `intro_frames.bin` (little-endian, matches Godot FileAccess defaults):
  magic "GZIF" | u32 version(=1) | u32 count | u32 fps_milli | u32 width | u32 height
  | count x u32 blob_length | then the WebP blobs back-to-back
Frame data starts at 24 + count*4; offset[i] = data_start + sum(len[0..i-1]).

    uv run --no-project python tools/pack_intro_frames.py            # 1280x720 @ 24fps, q66
    uv run --no-project python tools/pack_intro_frames.py --fps 20 --scale 960x540 --quality 60
"""
import os, sys, struct, subprocess, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INTRO_DIR = os.path.join(ROOT, "assets", "generated", "intro")
SRC_MP4 = os.path.join(INTRO_DIR, "intro.mp4")
OUT_PACK = os.path.join(INTRO_DIR, "intro_frames.bin")
OUT_AUDIO = os.path.join(INTRO_DIR, "intro_audio.ogg")
MAGIC = b"GZIF"


def _arg(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def main():
    if not os.path.exists(SRC_MP4):
        raise SystemExit(f"missing {SRC_MP4} (run tools/gen_intro_cinematic.py first)")
    fps = float(_arg("--fps", "24"))
    scale = _arg("--scale", "1280x720")            # WxH, or "" to keep source size
    quality = int(_arg("--quality", "66"))         # libwebp quality 0-100
    w, h = (int(x) for x in scale.split("x")) if scale else (0, 0)

    tmp = tempfile.mkdtemp(prefix="intro_frames_")
    try:
        vf = f"fps={fps}" + (f",scale={w}:{h}" if scale else "")
        print(f"[pack] extracting frames  ({vf}, q{quality}) ...", flush=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", SRC_MP4,
                        "-vf", vf, "-c:v", "libwebp", "-quality", str(quality),
                        os.path.join(tmp, "f%05d.webp")], check=True)
        print("[pack] extracting audio (ogg vorbis) ...", flush=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", SRC_MP4, "-vn",
                        "-c:a", "libvorbis", "-q:a", "5", OUT_AUDIO], check=True)

        files = sorted(f for f in os.listdir(tmp) if f.endswith(".webp"))
        if not files:
            raise SystemExit("ffmpeg produced no frames")
        blobs = [open(os.path.join(tmp, f), "rb").read() for f in files]
        if not scale:  # probe first frame size when we didn't force a scale
            out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                  "-show_entries", "stream=width,height", "-of", "csv=p=0",
                                  os.path.join(tmp, files[0])], capture_output=True, text=True)
            w, h = (int(x) for x in out.stdout.strip().split(","))

        with open(OUT_PACK, "wb") as fh:
            fh.write(MAGIC)
            fh.write(struct.pack("<IIIII", 1, len(blobs), int(round(fps * 1000)), w, h))
            for b in blobs:
                fh.write(struct.pack("<I", len(b)))
            for b in blobs:
                fh.write(b)

        total = os.path.getsize(OUT_PACK)
        print(f"[pack] {len(blobs)} frames {w}x{h} @ {fps}fps -> {OUT_PACK} "
              f"({total/1048576:.1f} MB)", flush=True)
        print(f"[pack] audio -> {OUT_AUDIO} ({os.path.getsize(OUT_AUDIO)/1048576:.1f} MB)")
        print("[pack] done")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
