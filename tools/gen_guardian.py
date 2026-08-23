#!/usr/bin/env python3
"""T-0042 custom Guardian: the player character, rigged (route 2 = Meshy rig).

Grounded workflow (docs/FAL_PIPELINE.md 6, 9A, 10.8, 10.9):
  concept (nano-banana-pro, clean A-pose front + matching back) ->
  mesh (meshy/v7/multi-image-to-3d, a-pose, PBR, textured, game-ready topology) ->
  rig (fal-ai/meshy/rigging, humanoid; idle/walk/run animations).

Staged ON PURPOSE so we validate the (cheap) mesh in-engine/Blender BEFORE paying
the $0.80 rigging fee, and iterate the concept for pennies. matches the pipeline
doc's "validate ONE gen before batching".

    uv run --no-project python tools/gen_guardian.py --stage concept   # front + back pngs
    uv run --no-project python tools/gen_guardian.py --stage mesh       # -> guardian_mesh.glb
    uv run --no-project python tools/gen_guardian.py --stage rig        # -> guardian_rigged.glb + anims
    uv run --no-project python tools/gen_guardian.py --stage all
    uv run --no-project python tools/gen_guardian.py --stage concept --force

Output -> assets/generated/guardian/
  guardian_front.png, guardian_back.png            (concept)
  guardian_mesh.glb (+ meshy PBR textures)         (raw a-pose mesh)
  guardian_rigged.glb                              (Meshy-rigged, bind pose)
  anim_idle.glb, anim_walk.glb, anim_run.glb       (locomotion clips on the rig)
  rig_response.json                                (full rig payload, for inspection)
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "guardian")
NANO = "fal-ai/nano-banana-pro"
NANO_EDIT = "fal-ai/nano-banana-pro/edit"
MESH = "meshy/v7/multi-image-to-3d"
RIG = "fal-ai/meshy/rigging"
MULTIANIM = "fal-ai/meshy/rigging/multi-animation"

# Gun-pose candidates from Meshy's animation library (docs.meshy.ai/en/api/
# animation-library). Only the FP arms need these (the legs are masked out), so an
# arms-forward rifle-aim pose is what we want for the armed/FP hold; reload + shoot
# are grabbed too for the later combat moveset (FAL_PIPELINE 6.1). IDs can shift, so
# we pull a spread and pick the best arm pose in Blender.
MOVESET_IDS = [233, 234, 89, 95, 104, 170, 98]
MOVESET_NAMES = {233: "walk_shoot_fwd", 234: "walk_shoot_back", 89: "combat_stance",
                 95: "gun_hold", 104: "side_shot", 170: "standing_reload", 98: "run_shoot"}

# One visual language with the ship + the T-0041 arsenal: matte black / gunmetal
# armour plates, subtle gold trim, glowing teal energy accents, battle-worn. A
# SEALED-HELM Guardian with a glowing teal visor and ARMOURED GAUNTLETS -- the
# gauntlets matter because the first-person view sees the hands close up, and
# armoured gloves dodge the AI-fingers problem while reading as a real soldier.
# A-pose, arms out, feet apart, NO weapons/props in the hands (rigging needs
# clear, separated limbs). Head-to-toe in frame, plain solid background, a clean
# 3D-lit render (flat 2D art turns to 3D badly -- FAL_PIPELINE 10.8).
_STYLE = ("full body head to toe, standing A-pose with arms out and feet apart, "
          "empty open hands, no weapons, no props, plain seamless light grey "
          "studio background, even neutral studio lighting, sharp 3D character "
          "render, realistic PBR materials, crisp high detail, centered, "
          "symmetrical, no text, no watermark, no logo, no extra characters")

FRONT_PROMPT = ("A sci-fi armoured super-soldier hero character called a Guardian, "
                "front view. Sealed full helmet with a glowing teal visor slit, "
                "matte black and dark gunmetal armour plates over a dark fitted "
                "undersuit, subtle brushed-gold trim on the edges, glowing teal "
                "energy lines and a small teal chest core, layered pauldrons, "
                "armoured gauntlets and armoured boots, athletic proportions, "
                "heroic looter-shooter guardian. " + _STYLE)

BACK_PROMPT = ("Show the exact same sci-fi Guardian character from directly "
               "behind: a clean BACK view, same standing A-pose with arms out and "
               "feet apart, same matte black gunmetal armour with gold trim and "
               "glowing teal energy lines, same helmet from the back, same plain "
               "grey studio background and lighting. Keep the identical character, "
               "materials and colours. " + _STYLE)


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
        return {"__error__": f"{e.code}: {e.read().decode(errors='replace')[:600]}"}


def run(model, payload, timeout=1200):
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
            return {"__error__": json.dumps(st)[:600]}
        time.sleep(6)
    return {"__error__": "timeout"}


def upload(path, ctype="image/png"):
    name = os.path.basename(path)
    init = req("https://rest.alpha.fal.ai/storage/upload/initiate",
               {"file_name": name, "content_type": ctype}, "POST")
    up_url, file_url = init["upload_url"], init["file_url"]
    with open(path, "rb") as f:
        data = f.read()
    put = urllib.request.Request(up_url, data=data, method="PUT",
                                 headers={"Content-Type": ctype})
    with urllib.request.urlopen(put, timeout=180) as r:
        r.read()
    return file_url


def first_img(res):
    v = res.get("images")
    if isinstance(v, list) and v:
        it = v[0]
        return it.get("url") if isinstance(it, dict) else it
    return None


def _url_of(v):
    if isinstance(v, dict):
        return v.get("url")
    if isinstance(v, str):
        return v
    return None


def glb_url(res):
    for k in ("model_glb", "model_mesh", "rigged_character_glb"):
        u = _url_of(res.get(k))
        if u:
            return u
    mu = res.get("model_urls")
    if isinstance(mu, dict):
        for v in mu.values():
            u = _url_of(v)
            if isinstance(u, str) and u.endswith(".glb"):
                return u
    return None


def stage_concept(force=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    front = os.path.join(OUT_DIR, "guardian_front.png")
    back = os.path.join(OUT_DIR, "guardian_back.png")
    if os.path.exists(front) and not force:
        print(f"SKIP concept: {front} exists (use --force)", flush=True)
    else:
        print("[concept] FRONT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": FRONT_PROMPT, "aspect_ratio": "3:4",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("FRONT-FAILED", res["__error__"], flush=True); return
        u = first_img(res)
        if not u:
            print("FRONT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(u, front)
        print("[concept] front ->", front, flush=True)

    if os.path.exists(back) and not force:
        print(f"SKIP back: {back} exists (use --force)", flush=True)
        return
    print("[concept] BACK via nano-banana-pro/edit (identity-locked) ...", flush=True)
    fu = upload(front)
    res = run(NANO_EDIT, {"prompt": BACK_PROMPT, "image_urls": [fu],
                          "aspect_ratio": "3:4", "resolution": "2K", "num_images": 1})
    if "__error__" in res:
        print("BACK-FAILED", res["__error__"], flush=True); return
    u = first_img(res)
    if not u:
        print("BACK-NO-URL", json.dumps(res)[:400], flush=True); return
    urllib.request.urlretrieve(u, back)
    print("[concept] back ->", back, flush=True)


def stage_mesh(force=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    front = os.path.join(OUT_DIR, "guardian_front.png")
    back = os.path.join(OUT_DIR, "guardian_back.png")
    glb = os.path.join(OUT_DIR, "guardian_mesh.glb")
    if not os.path.exists(front):
        print("no concept -- run --stage concept first", flush=True); return
    if os.path.exists(glb) and not force:
        print(f"SKIP mesh: {glb} exists (use --force)", flush=True); return
    imgs = [upload(front)]
    if os.path.exists(back):
        imgs.append(upload(back))
    print(f"[mesh] meshy/v7/multi-image-to-3d ({len(imgs)} views, a-pose) ...", flush=True)
    payload = {"image_urls": imgs, "pose_mode": "a-pose", "should_texture": True,
               "enable_pbr": True, "should_remesh": True, "topology": "triangle",
               "target_polycount": 30000, "symmetry_mode": "on"}
    res = run(MESH, payload)
    if "__error__" in res:
        print("MESH-FAILED", res["__error__"], flush=True); return
    g = glb_url(res)
    if not g:
        print("MESH-NO-URL", json.dumps(res)[:600], flush=True); return
    urllib.request.urlretrieve(g, glb)
    with open(os.path.join(OUT_DIR, "mesh_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    print("[mesh] DONE ->", glb, "from", g, flush=True)


def _download_anims(res):
    """Save any locomotion clips found in a rigging response. basic_animations
    shape varies (dict of name->url|obj, or a list), so download generically."""
    saved = []
    ba = res.get("basic_animations")
    items = {}
    if isinstance(ba, dict):
        items = ba
    elif isinstance(ba, list):
        items = {f"clip{i}": v for i, v in enumerate(ba)}
    for name, v in items.items():
        u = _url_of(v)
        if u and u.endswith(".glb"):
            dst = os.path.join(OUT_DIR, f"anim_{name}.glb")
            urllib.request.urlretrieve(u, dst)
            saved.append(dst)
    # the enable_animation preset (idle) comes back as animation_glb
    u = _url_of(res.get("animation_glb"))
    if u and u.endswith(".glb"):
        dst = os.path.join(OUT_DIR, "anim_idle.glb")
        urllib.request.urlretrieve(u, dst)
        saved.append(dst)
    return saved


def stage_rig(force=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    mesh = os.path.join(OUT_DIR, "guardian_mesh.glb")
    rigged = os.path.join(OUT_DIR, "guardian_rigged.glb")
    if not os.path.exists(mesh):
        print("no mesh -- run --stage mesh first", flush=True); return
    if os.path.exists(rigged) and not force:
        print(f"SKIP rig: {rigged} exists (use --force)", flush=True); return
    mu = upload(mesh, "model/gltf-binary")
    print("[rig] fal-ai/meshy/rigging ($0.80) ...", flush=True)
    payload = {"model_url": mu, "height_meters": 1.8,
               "enable_animation": True, "animation_action_id": 0}  # 0 = Idle
    res = run(RIG, payload)
    if "__error__" in res:
        print("RIG-FAILED", res["__error__"], flush=True); return
    with open(os.path.join(OUT_DIR, "rig_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    u = _url_of(res.get("rigged_character_glb"))
    if not u:
        print("RIG-NO-GLB", json.dumps(res)[:600], flush=True); return
    urllib.request.urlretrieve(u, rigged)
    anims = _download_anims(res)
    print("[rig] DONE ->", rigged, flush=True)
    print("[rig] anims:", anims, flush=True)


def stage_moveset(force=False):
    """Meshy multi-animation: several gun poses on the same rig ($0.08). Downloads
    each clip GLB to raw/ for a Blender merge into guardian.glb."""
    os.makedirs(OUT_DIR, exist_ok=True)
    raw = os.path.join(OUT_DIR, "raw")
    mesh = os.path.join(raw, "guardian_mesh.glb")
    if not os.path.exists(mesh):
        mesh = os.path.join(OUT_DIR, "guardian_mesh.glb")
    if not os.path.exists(mesh):
        print("no mesh -- run --stage mesh first", flush=True); return
    marker = os.path.join(raw, "move_walk_shoot_fwd.glb")
    if os.path.exists(marker) and not force:
        print(f"SKIP moveset: {marker} exists (use --force)", flush=True); return
    mu = upload(mesh, "model/gltf-binary")
    print(f"[moveset] multi-animation ids={MOVESET_IDS} ($0.08) ...", flush=True)
    res = run(MULTIANIM, {"model_url": mu, "height_meters": 1.8,
                          "animation_action_ids": MOVESET_IDS})
    if "__error__" in res:
        print("MOVESET-FAILED", res["__error__"], flush=True); return
    with open(os.path.join(raw, "moveset_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    anims = res.get("animations")
    if not isinstance(anims, list):
        print("MOVESET-NO-ANIMS", json.dumps(res)[:500], flush=True); return
    saved = []
    for i, a in enumerate(anims):
        u = _url_of(a)
        if not (u and u.endswith(".glb")):
            # entry may be an object with a glb field
            u = _url_of(a.get("glb")) if isinstance(a, dict) else None
        if not u:
            continue
        aid = MOVESET_IDS[i] if i < len(MOVESET_IDS) else i
        name = MOVESET_NAMES.get(aid, "id%d" % aid)
        dst = os.path.join(raw, "move_%s.glb" % name)
        urllib.request.urlretrieve(u, dst)
        saved.append(dst)
    print("[moveset] saved:", saved, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="concept",
                    help="concept|mesh|rig|moveset|all")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    stages = ["concept", "mesh", "rig"] if a.stage == "all" else [a.stage]
    for s in stages:
        if s == "concept":
            stage_concept(a.force)
        elif s == "mesh":
            stage_mesh(a.force)
        elif s == "rig":
            stage_rig(a.force)
        elif s == "moveset":
            stage_moveset(a.force)
        else:
            print("unknown stage", s); return


if __name__ == "__main__":
    main()
