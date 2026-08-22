#!/usr/bin/env python3
"""T-0041 weapon models: distinct sci-fi guns for the four weapon kinds.

Grounded workflow (docs/FAL_PIPELINE.md 10.8/10.9/9C):
  1. nano-banana-pro -> a clean, SHARP, 1:1, solid-background 3/4 product render
     of ONE weapon (a bad ref makes every generator fail). One cohesive
     looter-shooter arsenal: dark gunmetal + brushed steel, teal energy accents,
     gold trim -- matching the game's black/gold/teal ship palette.
  2. Tripo H3.1 image-to-3d (pbr, detailed, orientation=align_image) -> GLB.
     ~$0.01/gen, the proven workhorse; ships PBR (Color/Normal/ORM).

Guns are METAL: the raw gen ORM tends dull. Godot side re-punches metalness on
import (player_character._metalize_weapon); optionally run the albedo through
fal-ai/patina too (see falgen.py).

    uv run --no-project python tools/gen_weapons.py --gun auto_rifle   # validate ONE
    uv run --no-project python tools/gen_weapons.py --gun all          # batch
    uv run --no-project python tools/gen_weapons.py --gun sniper --force
    uv run --no-project python tools/gen_weapons.py --gun shotgun --skip-concept  # reuse concept

Output -> assets/generated/weapons/raw/<gun>.glb (+ <gun>_concept.png).
Then run orient_weapons.py to canonicalise raw/<gun>.glb -> <gun>.glb (the file
Godot loads: barrel -Z, sight +Y, centred, ~0.64 m).
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "weapons")
RAW_DIR = os.path.join(OUT_DIR, "raw")  # untouched fal meshes; orient_weapons.py -> canonical
NANO = "fal-ai/nano-banana-pro"
TRIPO = "tripo3d/h3.1/image-to-3d"
FACE_LIMIT = 120000

# One arsenal, one visual language: dark gunmetal + brushed steel, glowing teal
# energy accents, gold trim, worn. Each is a SINGLE weapon, 3/4 side view, barrel
# to the left, plain seamless neutral-grey studio background, sharp product render,
# NO hands / text / watermark (10.8: flat/dirty refs turn to 3D badly).
_STYLE = ("dark gunmetal body with brushed steel panels, glowing teal energy "
          "cells, subtle gold trim accents, worn battle-used metal, hard-surface "
          "sci-fi game weapon, single weapon object, three-quarter side view with "
          "the barrel pointing left, centered, plain seamless neutral grey studio "
          "background, sharp studio product render, crisp edges, high detail, PBR "
          "materials, even neutral studio lighting, no hands, no arms, no person, "
          "no text, no watermark, no logo")

GUNS = {
    "auto_rifle": ("futuristic automatic assault rifle, sleek angular receiver, "
                   "integrated holographic sight, straight box magazine, vented "
                   "barrel shroud, collapsible stock, medium length, " + _STYLE),
    "shotgun": ("futuristic heavy combat shotgun, chunky wide twin barrels, "
                "pump-action foregrip, thick tactical body, short and heavy, teal "
                "energy vents near the breach, " + _STYLE),
    "sniper": ("futuristic precision sniper rifle, very long slender heavy barrel "
               "with a muzzle brake, large mounted scope, teal charge coils along "
               "the barrel, skeletal stock, folded bipod, " + _STYLE),
    "hand_cannon": ("futuristic hand cannon, a heavy ornate revolver pistol, large "
                    "rotating cylinder, short thick barrel, one-handed compact "
                    "frame, gold engraved trim, teal glowing chamber, " + _STYLE),
}


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
        return {"__error__": f"{e.code}: {e.read().decode(errors='replace')[:400]}"}


def run(model, payload, timeout=900):
    sub = req(f"https://queue.fal.run/{model}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        return sub
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = req(su)
        s = st.get("status")
        if s == "COMPLETED":
            return req(ru)
        if s in ("FAILED", "ERROR"):
            return {"__error__": json.dumps(st)[:400]}
        time.sleep(5)
    return {"__error__": "timeout"}


def upload(path):
    name = os.path.basename(path)
    init = req("https://rest.alpha.fal.ai/storage/upload/initiate",
               {"file_name": name, "content_type": "image/png"}, "POST")
    up_url, file_url = init["upload_url"], init["file_url"]
    with open(path, "rb") as f:
        data = f.read()
    put = urllib.request.Request(up_url, data=data, method="PUT",
                                 headers={"Content-Type": "image/png"})
    with urllib.request.urlopen(put, timeout=180) as r:
        r.read()
    return file_url


def first_img(res):
    v = res.get("images")
    if isinstance(v, list) and v:
        it = v[0]
        return it.get("url") if isinstance(it, dict) else it
    return None


def glb_url(res):
    for k in ("model_glb", "model_mesh"):
        v = res.get(k)
        if isinstance(v, dict) and v.get("url"):
            return v["url"]
    mu = res.get("model_urls")
    if isinstance(mu, dict):
        for v in mu.values():
            u = v.get("url") if isinstance(v, dict) else v
            if isinstance(u, str) and u.endswith(".glb"):
                return u
    return None


def gen_one(gun, force=False, skip_concept=False, concept_only=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(RAW_DIR, exist_ok=True)
    concept = os.path.join(OUT_DIR, f"{gun}_concept.png")
    glb = os.path.join(RAW_DIR, f"{gun}.glb")  # raw fal output -> orient_weapons.py canonicalises

    if os.path.exists(glb) and not force:
        print(f"SKIP {gun}: {glb} exists (use --force)", flush=True)
        return

    if not (skip_concept and os.path.exists(concept)):
        print(f"[{gun}] CONCEPT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": GUNS[gun], "aspect_ratio": "1:1",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("CONCEPT-FAILED", res["__error__"], flush=True); return
        url = first_img(res)
        if not url:
            print("CONCEPT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(url, concept)
        print(f"[{gun}] concept ->", concept, flush=True)
    else:
        print(f"[{gun}] reusing concept", concept, flush=True)

    if concept_only:
        return

    print(f"[{gun}] UPLOAD + MESH via Tripo H3.1 ...", flush=True)
    img_url = upload(concept)
    payload = {"image_url": img_url, "pbr": True, "orientation": "align_image",
               "geometry_quality": "detailed", "texture_quality": "detailed",
               "texture_alignment": "original_image", "face_limit": FACE_LIMIT}
    res = run(TRIPO, payload)
    if "__error__" in res:
        print("MESH-FAILED", res["__error__"], flush=True); return
    g = glb_url(res)
    if not g:
        print("MESH-NO-URL", json.dumps(res)[:400], flush=True); return
    urllib.request.urlretrieve(g, glb)
    print(f"[{gun}] DONE ->", glb, "from", g, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gun", default="auto_rifle",
                    help="auto_rifle|shotgun|sniper|hand_cannon|all")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--skip-concept", action="store_true")
    ap.add_argument("--concept-only", action="store_true")
    a = ap.parse_args()
    guns = list(GUNS) if a.gun == "all" else [a.gun]
    for g in guns:
        if g not in GUNS:
            print("unknown gun", g, "->", list(GUNS)); continue
        gen_one(g, a.force, a.skip_concept, a.concept_only)


if __name__ == "__main__":
    main()
