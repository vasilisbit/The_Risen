#!/usr/bin/env python3
"""Hazard/projectile prop models (nano-banana-pro concept -> Tripo H3.1 image-to-3d).

Two props the game currently draws as primitives:
  flaming_knife -> Storm Barrage super rockets (was a capsule)  -> assets/generated/vfx/
  molten_rock   -> Venus volcano magma bombs (was a sphere)     -> assets/generated/venus/

Same proven workflow as gen_weapons.py (FAL_PIPELINE §9C/§10.8): one clean, sharp,
1:1, solid-background single-object render, then Tripo H3.1 (pbr, detailed) for the
GLB. These are un-rigged props; the engine AABB-fits + tints them at runtime
(MeshUtil.load_prop), so no Blender canonicalise step is needed.

    uv run --no-project python tools/gen_projectiles.py --prop molten_rock   # validate ONE
    uv run --no-project python tools/gen_projectiles.py --prop all
    uv run --no-project python tools/gen_projectiles.py --prop flaming_knife --force
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NANO = "fal-ai/nano-banana-pro"
TRIPO = "tripo3d/h3.1/image-to-3d"
FACE_LIMIT = 60000

# prop -> (out subdir, concept prompt). Concepts are ONE object, centered, sharp,
# plain neutral background, no text (a dirty/flat ref turns to 3D badly, §10.8).
PROPS = {
    "flaming_knife": ("vfx",
        "a single ornate sci-fi throwing knife / combat dagger seen in three-quarter "
        "side view with the sharp blade pointing LEFT, straight double-edged blade "
        "glowing molten orange-hot along its edges with a few incandescent cracks, "
        "dark forged-steel blade, short wrapped grip with a small guard, "
        "single weapon object, centered, plain seamless neutral grey studio background, "
        "sharp studio product render, crisp edges, high detail, PBR materials, even "
        "neutral studio lighting, no hands, no arms, no person, no text, no watermark"),
    "molten_rock": ("venus",
        "a single jagged chunk of molten volcanic rock, a roughly spherical lava boulder, "
        "dark charred basalt crust cracked open to reveal glowing incandescent orange-red "
        "molten lava in the deep fissures, rugged irregular surface, single rock object, "
        "centered, plain seamless neutral grey studio background, sharp studio product "
        "render, crisp edges, high detail, PBR materials, even neutral studio lighting, "
        "no text, no watermark, no logo"),
    "landing_beacon": ("ship",
        "a single futuristic sci-fi landing-pad marker beacon light, a slim vertical bollard "
        "post housing of dark gunmetal metal with a tall glowing warm amber-gold light lens "
        "strip running up its face emitting soft light, subtle brushed-gold trim and a small "
        "base, hard-surface sci-fi design cohesive with a gunmetal-and-gold spaceship, single "
        "object, upright, centered, plain seamless neutral grey studio background, sharp studio "
        "product render, crisp edges, high detail, PBR materials, even neutral studio lighting, "
        "no hands, no person, no text, no watermark, no logo"),
    "grenade": ("vfx",
        "a single futuristic sci-fi hand grenade, compact rounded ogival casing of dark "
        "gunmetal armor plating with subtle brushed-gold trim seams and rivets, a glowing "
        "teal-cyan energy core band wrapping around the middle with thin cracks of teal "
        "soulfire light leaking from the seams, a small ridged fuse cap on top, hard-surface "
        "military sci-fi design cohesive with a teal-and-gold Guardian aesthetic, single "
        "object, upright, centered, plain seamless neutral grey studio background, sharp "
        "studio product render, crisp edges, high detail, PBR materials, even neutral studio "
        "lighting, no hands, no person, no text, no watermark, no logo"),
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


def gen_one(prop, force=False, skip_concept=False):
    subdir, prompt = PROPS[prop]
    out_dir = os.path.join(ROOT, "assets", "generated", subdir)
    raw_dir = os.path.join(out_dir, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    concept = os.path.join(raw_dir, f"{prop}_concept.png")
    glb = os.path.join(out_dir, f"{prop}.glb")

    if os.path.exists(glb) and not force:
        print(f"SKIP {prop}: {glb} exists (use --force)", flush=True)
        return

    if not (skip_concept and os.path.exists(concept)):
        print(f"[{prop}] CONCEPT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": prompt, "aspect_ratio": "1:1",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("CONCEPT-FAILED", res["__error__"], flush=True); return
        url = first_img(res)
        if not url:
            print("CONCEPT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(url, concept)
        print(f"[{prop}] concept ->", concept, flush=True)
    else:
        print(f"[{prop}] reusing concept", concept, flush=True)

    print(f"[{prop}] UPLOAD + MESH via Tripo H3.1 ...", flush=True)
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
    print(f"[{prop}] DONE ->", glb, "from", g, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--prop", default="molten_rock", help="flaming_knife|molten_rock|all")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--skip-concept", action="store_true")
    a = ap.parse_args()
    props = list(PROPS) if a.prop == "all" else [a.prop]
    for p in props:
        if p not in PROPS:
            print("unknown prop", p, "->", list(PROPS)); continue
        gen_one(p, a.force, a.skip_concept)


if __name__ == "__main__":
    main()
