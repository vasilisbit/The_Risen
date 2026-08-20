#!/usr/bin/env python3
"""Generate the FOLD cinematic videos on fal.ai (stdlib only; run via `uv run python`).

The "Fold" is the warp-to-planet transition the ship makes when a mission is launched.
Per the user's design it is a PRE-BAKED cinematic (Seedance) that dissolves straight into
the real-time, interactive landing on the surface (scripts/landed_ship.gd). This tool bakes
one fold clip per planet:

  nano-banana-pro  -> a start frame (ship in space, the planet ahead)         [text-to-image]
  nano-banana-pro  -> an end frame   (diving through the atmosphere to surface)[text-to-image]
  seedance-2.0 i2v -> warp + approach + atmospheric entry, start->end frame    [image-to-video]
  ffmpeg           -> transcode the mp4 to Ogg Theora .ogv (Godot's core VideoStreamPlayer
                      only decodes Theora; mp4/h264 is not supported without a plugin)

Output: assets/generated/fold/<mission>.ogv  (+ the intermediate .mp4 and start/end .png for
reference). scripts/ship_travel.gd plays <mission>.ogv when present, and falls back to the
in-engine travel_cutscene when it is missing - so the game never depends on these files.

    uv run python tools/gen_fold_video.py                 # venus (default)
    uv run python tools/gen_fold_video.py --mission all    # earth + mars + venus
    uv run python tools/gen_fold_video.py --mission mars --force

Auth: FAL_KEY from .env.local (gitignored), same as tools/falgen.py / gen_audio.py.
Needs ffmpeg on PATH.
"""
import os, sys, time, json, subprocess, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "fold")

IMG_MODEL = "fal-ai/nano-banana-pro"
VID_MODEL = "bytedance/seedance-2.0/image-to-video"

DURATION = "5"          # seconds (Seedance supports 4-15)
RESOLUTION = "720p"     # 480p / 720p / 1080p
ASPECT = "16:9"         # matches the game viewport (fills the screen, no pillarbox)

# Per-mission prompts. START = a wide shot of the ship in space with the world ahead; END =
# the last frame the video should reach (diving through the atmosphere toward the surface the
# real mission then loads); MOTION = the camera/action for Seedance to interpolate between.
MISSIONS = {
    "earth": {
        "start": ("Cinematic wide establishing shot, deep space. A lone angular hard-surface "
                  "military spaceship, dark gunmetal hull with glowing blue engine trails, flying "
                  "toward camera-right. Ahead, large in frame: the planet EARTH, deep blue oceans, "
                  "green and brown continents, swirling white clouds, a thin blue atmosphere rim. "
                  "Scattered stars, volumetric sunlight, subtle film grain, photoreal, no text."),
        "end": ("Cinematic shot descending fast through broken grey storm clouds toward a ruined "
                "Earth city far below, shattered skyscrapers and a scarred grey skyline in haze, "
                "cold overcast light, dramatic, photoreal, no text."),
        "motion": ("The spaceship accelerates and jumps to faster-than-light warp with long "
                   "streaks of light, then decelerates as Earth swells to fill the frame; the ship "
                   "banks and dives toward the planet, plunging through the clouds toward the ruined "
                   "city below. Smooth cinematic chase camera following the ship, epic, no text."),
    },
    "mars": {
        "start": ("Cinematic wide establishing shot, deep space. A lone angular hard-surface "
                  "military spaceship, dark gunmetal hull with glowing blue engine trails, flying "
                  "toward camera-right. Ahead, large in frame: the planet MARS, a rusty red-orange "
                  "desert world with pale dust storms and dark canyon scars, thin hazy atmosphere. "
                  "Scattered stars, volumetric sunlight, subtle film grain, photoreal, no text."),
        "end": ("Cinematic shot descending through thin rust-coloured dust haze toward a vast red "
                "Martian canyon and a small mining outpost far below, butterscotch sky, blowing "
                "dust, dramatic, photoreal, no text."),
        "motion": ("The spaceship accelerates and jumps to faster-than-light warp with long "
                   "streaks of light, then decelerates as Mars swells to fill the frame; the ship "
                   "banks and dives toward the planet, plunging through the red dust haze toward the "
                   "canyon below. Smooth cinematic chase camera following the ship, epic, no text."),
    },
    "venus": {
        "start": ("Cinematic wide establishing shot, deep space. A lone angular hard-surface "
                  "military spaceship, dark gunmetal hull with glowing blue engine trails, flying "
                  "toward camera-right. Ahead, large in frame: the planet VENUS, a pale sulfuric "
                  "yellow-cream world completely veiled in thick swirling acid clouds, faint orange "
                  "glow. Scattered stars, volumetric sunlight, subtle film grain, photoreal, no text."),
        "end": ("Cinematic shot plunging down through thick swirling sulfuric yellow-orange "
                "Venusian clouds toward a dark volcanic surface far below, glowing orange lava "
                "cracks and a distant erupting volcano, oppressive haze, dramatic, photoreal, no text."),
        "motion": ("The spaceship accelerates and jumps to faster-than-light warp with long "
                   "streaks of light, then decelerates as Venus swells to fill the frame; the ship "
                   "banks and dives toward the planet, plunging through the thick sulfuric clouds "
                   "toward the glowing volcanic surface below. Smooth cinematic chase camera "
                   "following the ship, epic, no text."),
    },
}


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


H = {"Authorization": f"Key {_key()}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET", timeout=240):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{e.read().decode(errors='replace')[:800]}")


def run(model, payload, timeout=900):
    sub = _req(f"https://queue.fal.run/{model}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        return sub
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = _req(su)
        s = st.get("status")
        if s == "COMPLETED":
            return _req(ru)
        if s in ("FAILED", "ERROR"):
            raise SystemExit(f"gen failed: {json.dumps(st)[:500]}")
        time.sleep(5)
    raise SystemExit("timeout")


def _first_url(res, key):
    v = res.get(key)
    if isinstance(v, dict):
        return v.get("url")
    if isinstance(v, list) and v and isinstance(v[0], dict):
        return v[0].get("url")
    return None


def gen_image(prompt, dest):
    res = run(IMG_MODEL, {"prompt": prompt, "aspect_ratio": ASPECT, "resolution": "2K",
                          "output_format": "png", "num_images": 1})
    url = _first_url(res, "images")
    if not url:
        raise SystemExit(f"no image url in {json.dumps(res)[:400]}")
    urllib.request.urlretrieve(url, dest)
    return url


def gen_mission(mission, force):
    spec = MISSIONS[mission]
    ogv = os.path.join(OUT_DIR, mission + ".ogv")
    if os.path.exists(ogv) and not force:
        print("skip", ogv); return
    start_png = os.path.join(OUT_DIR, mission + "_start.png")
    end_png = os.path.join(OUT_DIR, mission + "_end.png")
    mp4 = os.path.join(OUT_DIR, mission + ".mp4")

    print(f"[{mission}] start frame", flush=True)
    start_url = gen_image(spec["start"], start_png)
    print(f"[{mission}] end frame", flush=True)
    end_url = gen_image(spec["end"], end_png)

    print(f"[{mission}] seedance video ({DURATION}s {RESOLUTION})", flush=True)
    res = run(VID_MODEL, {
        "prompt": spec["motion"], "image_url": start_url, "end_image_url": end_url,
        "aspect_ratio": ASPECT, "resolution": RESOLUTION, "duration": DURATION,
        "generate_audio": False,
    })
    vurl = _first_url(res, "video")
    if not vurl:
        raise SystemExit(f"no video url in {json.dumps(res)[:400]}")
    urllib.request.urlretrieve(vurl, mp4)

    print(f"[{mission}] transcode -> {os.path.basename(ogv)}", flush=True)
    subprocess.run(["ffmpeg", "-y", "-i", mp4, "-c:v", "libtheora", "-q:v", "8", "-an", ogv],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"[{mission}] -> {ogv}", flush=True)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    force = "--force" in sys.argv
    mission = "venus"
    if "--mission" in sys.argv:
        mission = sys.argv[sys.argv.index("--mission") + 1].lower()
    targets = list(MISSIONS.keys()) if mission == "all" else [mission]
    for m in targets:
        if m not in MISSIONS:
            raise SystemExit(f"unknown mission '{m}' (choose earth|mars|venus|all)")
        gen_mission(m, force)
    print("done")


if __name__ == "__main__":
    main()
