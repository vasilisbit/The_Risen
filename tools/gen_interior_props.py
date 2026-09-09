#!/usr/bin/env python3
"""Generate grungy ship-interior detail props with Tripo H3.1 (text-to-3d, detailed
+ PBR), to dress the cockpit/hub like the reference video. Output GLBs ->
assets/generated/interior/, placed by hub_structure.gd.

Run all:     python tools/gen_interior_props.py
Run subset:  python tools/gen_interior_props.py overhead_struts forge_counter
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "interior")
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


STYLE = ("grungy lived-in sci-fi spaceship interior, weathered dark gunmetal painted "
         "metal with panels bolts wear and grime, thin teal accent lights, industrial, "
         "cohesive matching art style, realistic, PBR textures, neutral even lighting")

PROPS = {
    "overhead_struts": "a section of spaceship overhead ceiling support structure, a horizontal industrial metal truss framework of crossing girders beams and brackets with cables, long and flat, made to hang under a ceiling",
    "pipe_bundle": "a bundle of spaceship pipes and conduits, several parallel industrial metal tubes cables and valves on mounting brackets, long straight run made to sit along a wall",
    "side_console": "an upright spaceship wall control console station, a tall angled panel with dark display screens buttons switches and readouts on a slim base, standing floor unit",
    "forge_counter": "a rugged sci-fi merchant shop counter desk, a long solid trading counter with a heavy worktop, front panels and a small terminal, weapon-shop vendor stall counter, sturdy and wide",
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
    targets = {k: v for k, v in PROPS.items() if not want or k in want}
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
