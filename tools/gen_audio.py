#!/usr/bin/env python3
"""Generate The Risen's real audio on fal.ai (stdlib only; run via `uv run python`).

SFX  -> fal-ai/elevenlabs/sound-effects/v2   (text, duration_seconds 0.5-22, loop)
Music -> fal-ai/stable-audio-3/small/music/base/text-to-audio  (prompt, duration)

Files land in assets/generated/audio/{sfx,music}/*.mp3 and are picked up automatically
by scripts/audio_manager.gd (it prefers a file over its code-synthesised fallback).

    uv run python tools/gen_audio.py            # generate anything missing
    uv run python tools/gen_audio.py --force    # regenerate everything

Auth: FAL_KEY from .env.local (gitignored), same as tools/falgen.py.
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "generated", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "generated", "audio", "music")

SFX_MODEL = "fal-ai/elevenlabs/sound-effects/v2"
MUSIC_MODEL = "fal-ai/stable-audio-3/small/music/base/text-to-audio"

# id -> (prompt, duration_seconds, loop)
SFX = {
    "warp": ("Sci-fi FTL warp jump: a rising energy whoosh building fast into a deep "
             "powerful bass boom as a spaceship folds space and jumps to lightspeed", 4, False),
    "engine": ("Steady sci-fi spaceship engine thrust: a smooth low rumble with a soft high "
               "electric whine, powerful cruising starship, seamless loop", 10, True),
    "footstep": ("A single quick footstep boot scuff on hard ground, dry and short", 1, False),
    "wind": ("Eerie alien planet ambience: low howling desert wind with a faint hollow "
             "atmospheric drone, seamless loop", 15, True),
}
# name -> (prompt, duration)
MUSIC = {
    "hub": ("Calm ambient sci-fi space station music, slow atmospheric synth pads and gentle "
            "warm drones, floating, spacious and hopeful, no drums, no percussion, seamless loop", 45),
    "travel": ("Cinematic sci-fi space travel cue: a hopeful adventurous synth swell that builds "
               "and rises into a triumphant warp-jump hit, short stinger, orchestral electronic hybrid", 18),
}


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


H = {"Authorization": f"Key {_key()}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET"):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{e.read().decode(errors='replace')[:600]}")


def run(model, payload, timeout=420):
    sub = _req(f"https://queue.fal.run/{model}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        return sub
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = _req(su)
        if st.get("status") == "COMPLETED":
            return _req(ru)
        if st.get("status") in ("FAILED", "ERROR"):
            raise SystemExit(f"gen failed: {json.dumps(st)[:400]}")
        time.sleep(4)
    raise SystemExit("timeout")


def main():
    force = "--force" in sys.argv
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)

    for sid, (prompt, dur, loop) in SFX.items():
        dest = os.path.join(SFX_DIR, sid + ".mp3")
        if os.path.exists(dest) and not force:
            print("skip", dest); continue
        print("SFX", sid, flush=True)
        res = run(SFX_MODEL, {"text": prompt, "duration_seconds": dur, "loop": loop,
                              "output_format": "mp3_44100_128", "prompt_influence": 0.45})
        urllib.request.urlretrieve(res["audio"]["url"], dest)
        print("  ->", dest, flush=True)

    for name, (prompt, dur) in MUSIC.items():
        dest = os.path.join(MUSIC_DIR, name + ".mp3")
        if os.path.exists(dest) and not force:
            print("skip", dest); continue
        print("MUSIC", name, flush=True)
        res = run(MUSIC_MODEL, {"prompt": prompt, "duration": dur, "output_format": "mp3"})
        urllib.request.urlretrieve(res["audio"]["url"], dest)
        print("  ->", dest, flush=True)

    print("done")


if __name__ == "__main__":
    main()
