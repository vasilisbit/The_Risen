#!/usr/bin/env python3
"""T-0043 custom Forge Master vendor: the hub armourer NPC, rigged with an idle
(route 2 = Meshy rig). Replaces the Fab skm_robot3 stand-in in the hub bay AND
the vendor-screen backdrop.

Grounded workflow (docs/FAL_PIPELINE.md 6, 9A, 10.8, 10.9), mirrors gen_guardian.py:
  concept (nano-banana-pro, clean A-pose front + identity-locked back) ->
  mesh (meshy/v7/multi-image-to-3d, a-pose, PBR, textured, game-ready topology) ->
  rig+idle (fal-ai/meshy/rigging, humanoid, animation_action_id=0 = Idle) ->
  the rig's `animation_glb` (rigged mesh WITH the idle baked) is saved directly as
  forge_master.glb, then a light Blender cleanup pass renames the clip to "idle",
  strips root motion and does a weight sanity pass.

    uv run --no-project python tools/gen_forge_master.py --stage concept   # front + back pngs
    uv run --no-project python tools/gen_forge_master.py --stage mesh       # -> forge_master_mesh.glb
    uv run --no-project python tools/gen_forge_master.py --stage rig         # -> forge_master.glb (+ idle)
    uv run --no-project python tools/gen_forge_master.py --stage all
    uv run --no-project python tools/gen_forge_master.py --stage concept --force

Output -> assets/generated/hub/
  forge_master_front.png, forge_master_back.png    (concept)
  forge_master_mesh.glb (+ meshy PBR textures)     (raw a-pose mesh)
  forge_master.glb                                 (Meshy-rigged mesh WITH idle)
  rig_response.json                                (full rig payload, for inspection)
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "hub")
NANO = "fal-ai/nano-banana-pro"
NANO_EDIT = "fal-ai/nano-banana-pro/edit"
MESH = "meshy/v7/multi-image-to-3d"
RIG = "fal-ai/meshy/rigging"

# One visual language with the Guardian + ship + the T-0041 arsenal: matte black /
# dark gunmetal armour plates, subtle brushed-gold trim, glowing teal energy lines.
# The Forge Master is a HEAVY-SET ARMOURER ROBOT (broad shoulders, thick mechanical
# arms) -- reads as a smith/vendor and dodges AI-face issues. A warm forge-orange
# glow at the chest furnace distinguishes him from the teal-cored Guardian while the
# gunmetal/gold/teal palette keeps them a matched set. A-pose, arms out, feet apart,
# empty open hands, NO tools/props in the hands (rigging needs clear separated limbs).
# Head-to-toe, plain solid background, clean 3D-lit render (FAL_PIPELINE 10.8).
_STYLE = ("full body head to toe, standing A-pose with arms out and feet apart, "
          "empty open hands, no weapons, no tools, no props, plain seamless light "
          "grey studio background, even neutral studio lighting, sharp 3D character "
          "render, realistic PBR materials, crisp high detail, centered, "
          "symmetrical, no text, no watermark, no logo, no extra characters")

FRONT_PROMPT = ("A sci-fi armourer robot blacksmith called the Forge Master, front "
                "view. A heavy-set humanoid vendor robot with broad armoured "
                "shoulders and thick powerful mechanical arms, a stocky sturdy "
                "build. Matte black and dark gunmetal armour plates over reinforced "
                "hydraulics, subtle brushed-gold trim on the plate edges, glowing "
                "teal energy lines, a sturdy faceplate with a single glowing teal "
                "optic, and a glowing warm forge-orange furnace core in the chest "
                "like a portable forge. Layered pauldrons, heavy armoured gauntlets, "
                "heavy armoured boots, an industrial weapon-smith look. " + _STYLE)

BACK_PROMPT = ("Show the exact same sci-fi Forge Master armourer robot from directly "
               "behind: a clean BACK view, same standing A-pose with arms out and "
               "feet apart, same matte black gunmetal armour with gold trim and "
               "glowing teal energy lines, same broad heavy-set build, same plain "
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
    front = os.path.join(OUT_DIR, "forge_master_front.png")
    back = os.path.join(OUT_DIR, "forge_master_back.png")
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
    front = os.path.join(OUT_DIR, "forge_master_front.png")
    back = os.path.join(OUT_DIR, "forge_master_back.png")
    glb = os.path.join(OUT_DIR, "forge_master_mesh.glb")
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


def stage_rig(force=False):
    """Rig + idle. The `animation_glb` is the rigged mesh WITH the idle baked, so we
    save it directly as forge_master.glb (a single static-idle vendor needs no merge).
    The bind-pose rigged_character_glb is kept for reference."""
    os.makedirs(OUT_DIR, exist_ok=True)
    mesh = os.path.join(OUT_DIR, "forge_master_mesh.glb")
    out = os.path.join(OUT_DIR, "forge_master.glb")
    if not os.path.exists(mesh):
        print("no mesh -- run --stage mesh first", flush=True); return
    if os.path.exists(out) and not force:
        print(f"SKIP rig: {out} exists (use --force)", flush=True); return
    mu = upload(mesh, "model/gltf-binary")
    print("[rig] fal-ai/meshy/rigging ($0.80) ...", flush=True)
    payload = {"model_url": mu, "height_meters": 2.0,
               "enable_animation": True, "animation_action_id": 0}  # 0 = Idle
    res = run(RIG, payload)
    if "__error__" in res:
        print("RIG-FAILED", res["__error__"], flush=True); return
    with open(os.path.join(OUT_DIR, "rig_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    # Prefer the animated GLB (mesh + rig + idle); fall back to bind pose.
    u = _url_of(res.get("animation_glb")) or _url_of(res.get("rigged_character_glb"))
    if not u:
        print("RIG-NO-GLB", json.dumps(res)[:600], flush=True); return
    bind = _url_of(res.get("rigged_character_glb"))
    if bind:
        urllib.request.urlretrieve(bind, os.path.join(OUT_DIR, "forge_master_rigged.glb"))
    urllib.request.urlretrieve(u, out)
    print("[rig] DONE ->", out, "from", u, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", default="concept", help="concept|mesh|rig|all")
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
        else:
            print("unknown stage", s); return


if __name__ == "__main__":
    main()
