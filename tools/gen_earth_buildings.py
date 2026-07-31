#!/usr/bin/env python3
"""Regenerate the Earth street BUILDINGS as detailed models with Tripo H3.1
(text-to-3d), replacing the soft low-poly Tripo P1 buildings that read as
"playdough". Tripo H3.1 gives crisp detailed geometry + PBR at ~$0.1-0.3/gen
(vs Hunyuan Pro's $0.675), and face_limit caps the file size (uncapped 1M-poly
Hunyuan output was 84MB per asset - impractical). Output GLBs overwrite the same
chunk names in assets/generated/earth/chunks/ so earth_level.gd picks them up.

Only the 4 street BUILDING types are regenerated (apartment_block/tower/
shopfront_row/office_ruin); plaza structures + small props stay as P1 chunks.

Run all:      uv run --no-project python tools/gen_earth_buildings.py
Run subset:   uv run --no-project python tools/gen_earth_buildings.py tower
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "earth", "chunks")
os.makedirs(OUT, exist_ok=True)
MODEL = "tripo3d/h3.1/text-to-3d"
FACE_LIMIT = 300000


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


STYLE = ("gritty realistic post-apocalyptic war-torn city ruin, weathered grey "
         "concrete with rust and soot stains, bombed-out broken and damaged, "
         "sharp crisp architectural detail, windows and rebar and debris, "
         "Destiny 2 sci-fi game environment, cohesive matching art style, "
         "PBR textures, neutral even lighting")

CHUNKS = {
    "apartment_block": "a bombed-out mid-rise concrete apartment block, broken balconies, gaping shell holes, exposed rebar and rooms",
    "tower": "a tall multi-storey ruined skyscraper tower, collapsed upper floors, shattered glass facade, exposed steel frame",
    "shopfront_row": "a row of destroyed street-level city shopfronts and storefronts, broken windows, torn awnings, wrecked signage",
    "office_ruin": "a ruined multi-storey concrete office building, collapsed blown-out floors, broken windows, exposed structure and rebar",
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
    want = [a for a in sys.argv[1:] if not a.startswith("-")]
    targets = {k: v for k, v in CHUNKS.items() if not want or k in want}
    jobs = {}
    for name, obj in targets.items():
        payload = {"prompt": f"{obj}, {STYLE}", "pbr": True,
                   "geometry_quality": "detailed", "texture_quality": "detailed",
                   "face_limit": FACE_LIMIT}
        sub = req(f"https://queue.fal.run/{MODEL}", payload, "POST")
        jobs[name] = sub
        print("SUBMIT", name, "OK" if sub.get("status_url") else sub)

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
                    th = res.get("thumbnail")
                    if isinstance(th, dict) and th.get("url"):
                        urllib.request.urlretrieve(th["url"], os.path.join(OUT, name + "_hp.png"))
                    done[name] = "ok"
                    print("DONE", name)
                else:
                    done[name] = "no-url"
                    print("NOURL", name, json.dumps(res)[:300])
            elif s in ("FAILED", "ERROR"):
                done[name] = "failed"
                print("FAILED", name, json.dumps(st)[:200])
        if len(done) < len(jobs):
            time.sleep(6)
    print("SUMMARY", json.dumps(done))


if __name__ == "__main__":
    main()
