#!/usr/bin/env python3
"""Batch-generate the Earth ruined-city chunk set with Tripo P1 (text-to-3d).

A SHARED STYLE SUFFIX is appended to every prompt so the chunks stay visually
cohesive (same weathered-concrete / bombed-out Destiny-2 palette). All jobs are
submitted to the fal.ai queue up front, then polled + downloaded in parallel, so
the whole set finishes in a few minutes rather than serially.

Run: uv run --no-project python tools/gen_earth_chunks.py
Outputs GLB + preview PNG per chunk into assets/generated/earth/chunks/.
"""
import os, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "earth", "chunks")
os.makedirs(OUT, exist_ok=True)
MODEL = "tripo3d/p1/text-to-3d"


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
         "Destiny 2 sci-fi game environment, cohesive matching art style, "
         "game-ready low-poly, PBR textures, neutral even lighting")

CHUNKS = {
    "apartment_block": "a bombed-out mid-rise concrete apartment block, broken balconies, gaping shell holes, exposed rebar and rooms",
    "tower": "a tall multi-storey ruined skyscraper tower, collapsed upper floors, shattered glass facade, exposed steel frame",
    "shopfront_row": "a row of destroyed street-level city shopfronts and storefronts, broken windows, torn awnings, wrecked signage",
    "office_ruin": "a gutted concrete office building corner, blown-out floors, hanging debris, twisted window frames",
    "barricade": "a makeshift street barricade of stacked concrete blocks, sandbags and scrap metal, waist-high defensive cover",
    "wrecked_car": "a burnt-out rusted abandoned sedan car wreck, shattered windows, flat tires, scorched",
    "rubble_pile": "a large rubble and debris mound of broken concrete chunks, bricks and twisted rebar",
    "wall_section": "a broken freestanding concrete wall section with cracks, shell holes and faded graffiti, modular ruin piece",
    "overpass": "a collapsed elevated highway overpass segment, cracked road deck, toppled support pillars",
    "bunker": "a small fortified concrete guard bunker checkpoint, sandbag walls and narrow slit windows",
    "monument": "a destroyed stone city monument statue toppled on a cracked plaza pedestal, broken and defaced",
    "streetlight_props": "a cluster of bent broken city street props: leaning lamp post, dead traffic light, dumpster and debris",
}


def main():
    jobs = {}
    for name, obj in CHUNKS.items():
        sub = req(f"https://queue.fal.run/{MODEL}", {"prompt": f"{obj}, {STYLE}"}, "POST")
        jobs[name] = sub
        print("SUBMIT", name, "OK" if sub.get("status_url") else sub)

    done = {}
    t0 = time.time()
    while len(done) < len(jobs) and time.time() - t0 < 1200:
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
                url = (res.get("model_mesh") or {}).get("url")
                if url:
                    urllib.request.urlretrieve(url, os.path.join(OUT, name + ".glb"))
                    prev = (res.get("rendered_image") or {}).get("url")
                    if prev:
                        urllib.request.urlretrieve(prev, os.path.join(OUT, name + ".png"))
                    done[name] = "ok"
                    print("DONE", name)
                else:
                    done[name] = "no-url"
                    print("NOURL", name, json.dumps(res)[:200])
            elif s in ("FAILED", "ERROR"):
                done[name] = "failed"
                print("FAILED", name, json.dumps(st)[:200])
        if len(done) < len(jobs):
            time.sleep(6)
    print("SUMMARY", json.dumps(done))


if __name__ == "__main__":
    main()
