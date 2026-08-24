#!/usr/bin/env python3
"""T-0042 (b) equippable ARMOUR PLATES for the Guardian: one mesh per slot
(Helmet / Chest Plate / Gauntlets) that LAYERS on the already-armoured base Guardian
via BoneAttachment3D and is tinted by the equipped piece's rarity.

Pipeline (docs/FAL_PIPELINE.md 9C/10.5): nano-banana-pro concept of the plate as a
STANDALONE piece of heavier over-armour that clearly reads as equipped gear on top of
the base suit (a chest rig / reinforced pauldrons+chest, an upgraded helmet, gauntlet
plates), Guardian palette (matte gunmetal + gold trim + glowing teal), 3/4 view, plain
bg -> Tripo H3.1 image-to-3d. Fit + scale in-engine per bone; rarity = a live tint.

    uv run --no-project python tools/gen_armor.py --piece chest --concept-only
    uv run --no-project python tools/gen_armor.py --piece chest      # validate ONE
    uv run --no-project python tools/gen_armor.py --piece all        # batch

Output -> assets/generated/armor/<piece>.glb (+ <piece>_concept.png).
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "armor")
NANO = "fal-ai/nano-banana-pro"
TRIPO = "tripo3d/h3.1/image-to-3d"
FACE_LIMIT = 100000

_STYLE = ("a single standalone sci-fi armour piece, heavy over-armour that layers on "
          "top of a soldier's suit, matte black and dark gunmetal plates, brushed "
          "gold trim on the edges, glowing teal energy accents, battle-worn, hard-"
          "surface game armour, three-quarter view, floating on a plain seamless "
          "neutral grey studio background, sharp 3D render, PBR materials, even studio "
          "lighting, no body, no person, no mannequin, no head inside, no text, no watermark")

PIECES = {
    "chest": ("a reinforced chest plate / chest rig with layered pectoral plates, a "
              "central teal power core, shoulder pauldron mounts, straps and armour "
              "panels, worn over the torso, " + _STYLE),
    "helmet": ("a reinforced full helmet with a wide glowing teal visor, armoured "
               "cheek and jaw plates, a small antenna, worn over the head, " + _STYLE),
    "gauntlets": ("a matched PAIR of heavy armoured forearm gauntlets with layered "
                  "plates, knuckle guards and teal accents, worn on the forearms, "
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


def gen_one(piece, force=False, skip_concept=False, concept_only=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    concept = os.path.join(OUT_DIR, f"{piece}_concept.png")
    glb = os.path.join(OUT_DIR, f"{piece}.glb")
    if os.path.exists(glb) and not force:
        print(f"SKIP {piece}: {glb} exists (use --force)", flush=True); return
    if not (skip_concept and os.path.exists(concept)):
        print(f"[{piece}] CONCEPT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": PIECES[piece], "aspect_ratio": "1:1",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("CONCEPT-FAILED", res["__error__"], flush=True); return
        u = first_img(res)
        if not u:
            print("CONCEPT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(u, concept)
        print(f"[{piece}] concept ->", concept, flush=True)
    if concept_only:
        return
    print(f"[{piece}] UPLOAD + MESH via Tripo H3.1 ...", flush=True)
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
    print(f"[{piece}] DONE ->", glb, "from", g, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--piece", default="chest", help="chest|helmet|gauntlets|all")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--skip-concept", action="store_true")
    ap.add_argument("--concept-only", action="store_true")
    a = ap.parse_args()
    pieces = list(PIECES) if a.piece == "all" else [a.piece]
    for pc in pieces:
        if pc not in PIECES:
            print("unknown piece", pc); continue
        gen_one(pc, a.force, a.skip_concept, a.concept_only)


if __name__ == "__main__":
    main()
