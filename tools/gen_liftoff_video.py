#!/usr/bin/env python3
"""Generate the LIFT-OFF cinematic on fal.ai (stdlib only; run via `uv run python`).

Plays AFTER the in-engine lift-off animation (the ship climbing off the pad) on any planet:
the hero ship rises out of the atmosphere into space and flies into the mothership hangar
to dock/rest, then the game returns to the hub. ONE generic clip, reused for all 3 planets.

Uses the exact ship the user picked (nano-banana request 019fcd3f-..., a black/gold hull with
glowing teal wing-blades) as the identity reference, via nano-banana-pro/edit to compose it
into the two key frames, then Seedance interpolates between them:

  nano-banana-pro/edit(ship) -> start frame (ship rising through the upper atmosphere)
  nano-banana-pro/edit(ship) -> end frame   (ship approaching the mothership hangar bay)
  seedance-2.0 image-to-video -> ascent -> space -> dock                   [start->end]
  ffmpeg -> Ogg Theora liftoff.ogv (Godot core VideoStreamPlayer is Theora-only)

Output: assets/generated/fold/liftoff.ogv  (+ .mp4 and the two frames for reference).

    uv run --no-project python tools/gen_liftoff_video.py [--force]

Auth: FAL_KEY from .env.local. Needs ffmpeg on PATH.
"""
import os, sys, time, json, subprocess, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "fold")

IMG_EDIT = "fal-ai/nano-banana-pro/edit"
VID_MODEL = "bytedance/seedance-2.0/image-to-video"

# The user's chosen hero ship (nano-banana request 019fcd3f-d7f3-7813-afe3-0b893735c9c1).
SHIP_REF = "https://v3b.fal.media/files/b/0aa4ff96/6H6Lp2ifD7jVbyPJly2af_KPxDEVFi.png"

ASPECT = "16:9"
RESOLUTION = "720p"
DURATION = "6"

SHIP_DESC = ("this exact spaceship - a sleek black hard-surface hull with fine gold filigree "
             "trim and two large curved glowing teal-cyan wing-blades - keep its design and "
             "colours identical")

START_PROMPT = (f"Cinematic wide shot: {SHIP_DESC}, seen from behind and to the side, ascending "
                "steeply as it climbs out of a planet's upper atmosphere - a thin glowing blue "
                "atmospheric rim and cloud tops falling away far below, the curved planet horizon "
                "beneath, dark starry space filling the top of the frame, engines and teal blades "
                "glowing bright. Dramatic, photoreal, film grain, no text.")

END_PROMPT = (f"Cinematic wide shot in deep space: {SHIP_DESC}, flying toward the huge open glowing "
              "hangar-bay mouth of a massive grey capital mothership that fills the right of the "
              "frame, warm light spilling from the docking bay, stars around. The small ship is "
              "approaching to dock. Dramatic, photoreal, film grain, no text.")

MOTION = ("The spaceship ascends out of the atmosphere into dark space, then levels off and flies "
          "toward the mothership's glowing hangar bay to dock. Smooth cinematic camera following "
          "the ship from behind, the mothership growing larger as the ship approaches. Epic, no text.")


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


def edit_image(prompt, dest):
    res = run(IMG_EDIT, {"prompt": prompt, "image_urls": [SHIP_REF], "aspect_ratio": ASPECT,
                         "resolution": "2K", "output_format": "png", "num_images": 1})
    url = _first_url(res, "images")
    if not url:
        raise SystemExit(f"no image url in {json.dumps(res)[:400]}")
    urllib.request.urlretrieve(url, dest)
    return url


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    force = "--force" in sys.argv
    ogv = os.path.join(OUT_DIR, "liftoff.ogv")
    if os.path.exists(ogv) and not force:
        print("skip", ogv); return
    start_png = os.path.join(OUT_DIR, "liftoff_start.png")
    end_png = os.path.join(OUT_DIR, "liftoff_end.png")
    mp4 = os.path.join(OUT_DIR, "liftoff.mp4")

    print("[liftoff] start frame (ascent)", flush=True)
    start_url = edit_image(START_PROMPT, start_png)
    print("[liftoff] end frame (mothership dock)", flush=True)
    end_url = edit_image(END_PROMPT, end_png)

    print(f"[liftoff] seedance video ({DURATION}s {RESOLUTION})", flush=True)
    res = run(VID_MODEL, {
        "prompt": MOTION, "image_url": start_url, "end_image_url": end_url,
        "aspect_ratio": ASPECT, "resolution": RESOLUTION, "duration": DURATION,
        "generate_audio": False,
    })
    vurl = _first_url(res, "video")
    if not vurl:
        raise SystemExit(f"no video url in {json.dumps(res)[:400]}")
    urllib.request.urlretrieve(vurl, mp4)

    print("[liftoff] transcode -> liftoff.ogv", flush=True)
    subprocess.run(["ffmpeg", "-y", "-i", mp4, "-c:v", "libtheora", "-q:v", "8", "-an", ogv],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"[liftoff] -> {ogv}", flush=True)
    print("done")


if __name__ == "__main__":
    main()
