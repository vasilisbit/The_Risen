#!/usr/bin/env python3
"""T-0042 first-person VIEWMODEL: armoured arms+hands modelled already GRIPPING each
gun, used as the FP viewmodel instead of the shared body rig.

Why: the Meshy-rigged Guardian body can't hold a gun two-handed (arms too short to
reach the handguard + the auto-rig hands are a single fingerless bone, so a support
hand just splays open). Real FPS games use a dedicated arms+gun viewmodel - arms and
gauntlet hands sculpted around the weapon - which is what this generates.

Pipeline (docs/FAL_PIPELINE.md 9C/10.8): nano-banana-pro concept of two armoured
gauntlets gripping the gun (3/4 view, plain bg) -> Tripo H3.1 image-to-3d (pbr,
detailed). Armoured GAUNTLET hands (not bare fingers) hide the AI-hands problem and
match the Guardian. One arms+gun mesh per weapon; the world/inventory keep the
T-0041 gun models (separate view vs world models, as most FPS do).

    uv run --no-project python tools/gen_viewmodel.py --gun auto_rifle --concept-only
    uv run --no-project python tools/gen_viewmodel.py --gun auto_rifle   # validate ONE
    uv run --no-project python tools/gen_viewmodel.py --gun all          # batch

Output -> assets/generated/viewmodels/<gun>_vm.glb (+ <gun>_vm_concept.png).
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "viewmodels")
NANO = "fal-ai/nano-banana-pro"
TRIPO = "tripo3d/h3.1/image-to-3d"
FACE_LIMIT = 150000

# The arms match the Guardian: dark gunmetal armoured gauntlets, subtle gold trim,
# glowing teal accents, black underglove. Two hands GRIP the gun (right on the grip,
# left on the handguard/foregrip), gun held horizontal pointing RIGHT. 3/4 side view,
# forearms cut at the elbow, plain seamless grey bg -> clean image-to-3d.
_STYLE = ("first-person game weapon viewmodel, two armoured forearms and gauntlet "
          "hands firmly gripping the weapon with both hands - right hand on the "
          "grip, left hand on the front handguard - fingers wrapped around it, gun "
          "held horizontal pointing to the right, dark gunmetal armoured gauntlets "
          "with black underglove, subtle gold trim, glowing teal accents, forearms "
          "ending at the elbow, three-quarter side view, plain seamless neutral grey "
          "studio background, sharp 3D render, PBR materials, even studio lighting, "
          "no body, no head, no text, no watermark")

GUNS = {
    "auto_rifle": ("a futuristic assault rifle with an integrated holographic sight, "
                   "straight box magazine, vented barrel shroud, dark gunmetal with "
                   "teal energy cell, " + _STYLE),
    "shotgun": ("a futuristic heavy combat shotgun, chunky twin barrels, pump-action "
                "foregrip the left hand grips, short and heavy, " + _STYLE),
    "sniper": ("a futuristic precision sniper rifle, long heavy barrel, large mounted "
               "scope, teal charge coils, the left hand on the forward stock, " + _STYLE),
    "hand_cannon": ("a futuristic heavy revolver hand cannon held in BOTH hands in a "
                    "two-handed pistol grip, large cylinder, gold trim, teal chamber, "
                    + _STYLE),
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
        return {"__error__": f"{e.code}: {e.read().decode(errors='replace')[:500]}"}


def run(model, payload, timeout=900):
    sub = req(f"https://queue.fal.run/{model}", payload, "POST")
    if "__error__" in sub:
        return sub
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
            return {"__error__": json.dumps(st)[:500]}
        time.sleep(5)
    return {"__error__": "timeout"}


def upload(path):
    init = req("https://rest.alpha.fal.ai/storage/upload/initiate",
               {"file_name": os.path.basename(path), "content_type": "image/png"}, "POST")
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
    concept = os.path.join(OUT_DIR, f"{gun}_vm_concept.png")
    glb = os.path.join(OUT_DIR, f"{gun}_vm.glb")
    if os.path.exists(glb) and not force:
        print(f"SKIP {gun}: {glb} exists (use --force)", flush=True); return
    if not (skip_concept and os.path.exists(concept)):
        print(f"[{gun}] CONCEPT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": GUNS[gun], "aspect_ratio": "1:1",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("CONCEPT-FAILED", res["__error__"], flush=True); return
        u = first_img(res)
        if not u:
            print("CONCEPT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(u, concept)
        print(f"[{gun}] concept ->", concept, flush=True)
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
        print("MESH-NO-URL", json.dumps(res)[:500], flush=True); return
    urllib.request.urlretrieve(g, glb)
    print(f"[{gun}] DONE ->", glb, "from", g, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gun", default="auto_rifle", help="auto_rifle|shotgun|sniper|hand_cannon|all")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--skip-concept", action="store_true")
    ap.add_argument("--concept-only", action="store_true")
    a = ap.parse_args()
    guns = list(GUNS) if a.gun == "all" else [a.gun]
    for g in guns:
        if g not in GUNS:
            print("unknown gun", g); continue
        gen_one(g, a.force, a.skip_concept, a.concept_only)


if __name__ == "__main__":
    main()
