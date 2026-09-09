#!/usr/bin/env python3
"""Generate the Mars mining-base structures + a distant mountain with Tripo H3.1
(detailed + PBR), replacing the KayKit Space Base props so the whole map reads as
one cohesive fal.ai-generated Mars. Output GLBs -> assets/generated/mars/structures/,
placed (with collision) by mars_level.gd.

Run all:      uv run --no-project python tools/gen_mars_structures.py
Run subset:   uv run --no-project python tools/gen_mars_structures.py mars_drill
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "mars", "structures")
os.makedirs(OUT, exist_ok=True)
MODEL = "tripo3d/h3.1/text-to-3d"
FACE_LIMIT = 250000


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


STYLE = ("weathered sci-fi Mars mining and research base equipment, dusty rusty "
         "painted metal with panels and bolts, industrial, cohesive matching art "
         "style, realistic, PBR textures, neutral even lighting")

CHUNKS = {
    "mars_drill": "a large industrial Mars mining drill rig, tall lattice drilling tower with pipes hydraulics and machinery on a base",
    "mars_landing_pad": "a circular sci-fi Mars landing pad platform with perimeter marker lights, hazard stripes and low support struts, flat",
    "mars_habitat_tall": "a tall cylindrical sci-fi Mars habitat tower module with small windows, antennae, external ladders and vents",
    "mars_habitat_low": "a low dome sci-fi Mars habitat module building, curved ribbed metal shell with an airlock door and vents",
    "mars_containers": "a stack of three rugged sci-fi Mars cargo shipping containers, industrial metal crates with hazard markings",
    "mars_solar": "a ground-mounted sci-fi Mars solar panel array, several angled dusty photovoltaic panels on a metal frame",
    "mars_rover": "a six-wheeled sci-fi Mars exploration rover vehicle, dusty armored hull with a sensor mast and equipment",
    "mars_mountain": "a massive distant Mars mountain, a huge eroded red rock peak with layered martian sediment, imposing tall rugged silhouette",
    "mars_gate": "a colossal sci-fi ceremonial ARCHWAY GATE, two massive tall pillars on the left and right supporting a huge ornate arched top beam, a giant EMPTY HOLLOW open doorway opening in the middle to walk through, like a triumphal arch or temple gateway, nothing blocking the central passage, weathered Mars base architecture",
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
