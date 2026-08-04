#!/usr/bin/env python3
"""Generate a dedicated Venus boss-room weak-point CRYSTAL with Tripo H3.1 (detailed +
PBR) - a glowing magma crystal shard cluster the player shoots to drop the Ember
Tyrant's shield, replacing the reused obsidian shard. Output lands in
assets/generated/venus/rocks/venus_crystal.glb and is loaded by weak_point.gd.

Run:  uv run --no-project python tools/gen_venus_crystal.py
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "venus", "rocks")
os.makedirs(OUT, exist_ok=True)
MODEL = "tripo3d/h3.1/text-to-3d"
FACE_LIMIT = 200000


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


H = {"Authorization": f"Key {_key()}", "Content-Type": "application/json"}


def req(url, data=None, method="GET"):
    b = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=b, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return {"__error__": f"{e.code}: {e.read().decode(errors='replace')[:300]}"}


CHUNKS = {
    "venus_crystal": ("a tall upright cluster of glowing magma crystal shards, sharp "
                      "jagged faceted translucent crystalline gemstones growing upward, "
                      "molten orange-red and amber glowing volcanic crystal formation, "
                      "bright emissive hot core, sci-fi game asset, single compact "
                      "cluster on a small rocky base, PBR textures, neutral lighting"),
}


def glb_url(res):
    for k in ("model_glb", "model_mesh"):
        v = res.get(k)
        if isinstance(v, dict) and v.get("url"):
            return v["url"]
    mu = res.get("model_urls")
    if isinstance(mu, dict):
        for v in mu.values():
            if isinstance(v, str) and v.endswith(".glb"):
                return v
            if isinstance(v, dict) and v.get("url", "").endswith(".glb"):
                return v["url"]
    return None


def main():
    jobs = {}
    for name, obj in CHUNKS.items():
        payload = {"prompt": obj, "pbr": True, "geometry_quality": "detailed",
                   "texture_quality": "detailed", "face_limit": FACE_LIMIT}
        sub = req(f"https://queue.fal.run/{MODEL}", payload, "POST")
        jobs[name] = sub
        print("SUBMIT", name, "OK" if sub.get("status_url") else sub, flush=True)

    done = {}
    t0 = time.time()
    while len(done) < len(jobs) and time.time() - t0 < 1500:
        for name, sub in jobs.items():
            if name in done:
                continue
            su, ru = sub.get("status_url"), sub.get("response_url")
            if not su:
                done[name] = "submit-failed"
                continue
            st = req(su)
            s = st.get("status")
            if s == "COMPLETED":
                res = req(ru)
                url = glb_url(res)
                if url:
                    urllib.request.urlretrieve(url, os.path.join(OUT, name + ".glb"))
                    done[name] = "ok"
                    print("DONE", name, flush=True)
                else:
                    done[name] = "no-url"
                    print("NOURL", name, json.dumps(res)[:300], flush=True)
            elif s in ("FAILED", "ERROR"):
                done[name] = "failed"
                print("FAILED", name, json.dumps(st)[:200], flush=True)
        if len(done) < len(jobs):
            time.sleep(6)
    print("SUMMARY", json.dumps(done), flush=True)


if __name__ == "__main__":
    main()
