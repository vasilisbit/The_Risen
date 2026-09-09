#!/usr/bin/env python3
"""T-0044 custom enemies + bosses: the six Risen combatants, rigged (route 2 = Meshy
rig). Replaces the Quaternius Sci-Fi Essentials robots (Rusher/Shooter/Exploder) and
the Fab FBX bosses (Shielded Brute / Teleporting Phantom / Ember Tyrant).

ART DIRECTION (locked 2026-08-27): "teal soulfire Hive, cohesive" -- classic Destiny
Hive silhouettes (bone/chitin carapace, skull faces, ridged armour, ceremonial gold
runes) but the glowing soulfire in cracks/eyes is TEAL with brushed-gold trim, matching
the Guardian / ship / Forge Master / T-0041 arsenal. The Ember Tyrant keeps molten-orange
fire (its Venus element). Reads as one universe.

Grounded workflow (docs/FAL_PIPELINE.md 6, 9A, 10.8, 10.9), mirrors gen_forge_master.py:
  concept (nano-banana-pro, clean A-pose front + identity-locked back) ->
  mesh (meshy/v7/multi-image-to-3d, a-pose, PBR, textured, game-ready topology) ->
  rig+idle (fal-ai/meshy/rigging, humanoid, animation_action_id=0 = Idle; the call also
  returns basic_animations walk/run clips) ->
  the rig's `animation_glb` (rigged mesh WITH the idle baked) is saved as <type>.glb; the
  bind-pose rig + the walk/run clips are kept in raw/ for a Blender merge (idle+walk into
  one AnimationPlayer) + a cleanup pass (rename clips, strip junk, weight sanity, face -Z).

    uv run --no-project python tools/gen_enemies.py --enemy rusher --stage all
    uv run --no-project python tools/gen_enemies.py --enemy all --stage concept
    uv run --no-project python tools/gen_enemies.py --enemy shielded_brute --stage mesh --force

Output -> assets/generated/enemies/
  <type>_front.png, <type>_back.png            (concept)
  raw/<type>_mesh.glb (+ meshy PBR textures)   (raw a-pose mesh)
  raw/<type>_rigged.glb                        (Meshy-rigged, bind pose, reference)
  raw/<type>_walk.glb, raw/<type>_run.glb      (basic_animations locomotion clips)
  <type>.glb                                   (Meshy-rigged mesh WITH idle; the drop-in)
  raw/<type>_rig_response.json                 (full rig payload, for inspection)
"""
import os, sys, time, json, argparse, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "enemies")
RAW_DIR = os.path.join(OUT_DIR, "raw")
NANO = "fal-ai/nano-banana-pro"
NANO_EDIT = "fal-ai/nano-banana-pro/edit"
MESH = "meshy/v7/multi-image-to-3d"
RIG = "fal-ai/meshy/rigging"
MULTIANIM = "fal-ai/meshy/rigging/multi-animation"

# Attack/fire clips from Meshy's library (docs.meshy.ai/en/api/animation-library).
# Only rusher, shielded_brute and shooter CALL play_attack_animation(); all enemies
# share the Meshy skeleton, so one moveset scout on any mesh yields clips reusable
# across the roster in the Blender merge. Melee (weaponless swipe/punch) for the
# thrall/brute + a standing fire for the shooter's arm-cannon.
ATTACK_IDS = {4: "attack", 92: "combo_attack", 97: "left_slash", 96: "punch",
              104: "side_shot", 98: "run_and_shoot"}

# Shared render style: A-pose with CLEARLY SEPARATED limbs (rigging needs clean, split
# arms/legs -- a hunched creature pose rigs badly), empty open hands, no held props, plain
# background, sharp 3D-lit render (flat 2D art turns to 3D badly -- FAL_PIPELINE 10.8).
_STYLE = ("full body head to toe, standing in a clear symmetrical A-pose with both arms "
          "held out away from the body and feet apart, limbs clearly separated and not "
          "touching the torso, empty open hands, no weapons, no tools, no props, plain "
          "seamless light grey studio background, even neutral studio lighting, sharp 3D "
          "character render, realistic PBR materials, crisp high detail, centered, "
          "symmetrical, no text, no watermark, no logo, no extra characters")

# Common Hive-flavour language so the six read as one faction.
_HIVE = ("chitinous exoskeleton carapace plating with ridged bony armour, charcoal-black "
         "and bone-grey chitin, ornate brushed-gold ceremonial rune trim on the plate "
         "edges, glowing TEAL soulfire light leaking from cracks, seams and eye sockets")

ENEMIES = {
    # --- regular enemies (~1.8 m) -------------------------------------------------
    "rusher": dict(
        height=1.8, poly=28000,
        name="Risen Rusher (Hive Thrall-like melee)",
        front=("A gaunt skeletal Hive alien creature soldier, the Risen Rusher, front "
                "view. An emaciated hunched humanoid predator with " + _HIVE + ", built "
                "over a bony frame with long clawed arms and hands, sharp digitigrade "
                "legs, and a fanged skull-like head with two glowing teal soulfire eyes. "
                "A fast, aggressive, feral melee horror. " + _STYLE),
    ),
    "shooter": dict(
        height=1.8, poly=28000,
        name="Risen Shooter (Hive Acolyte-like ranged)",
        front=("A robed Hive alien acolyte, the Risen Shooter, front view. An upright "
                "humanoid creature draped in tattered chitinous ceremonial robes and "
                "carapace armour, with " + _HIVE + ", a hooded single-eyed skull head "
                "with one large glowing teal soulfire eye, and thin clawed empty hands. "
                "A heavy teal-glowing energy conduit is fused along one forearm like a "
                "built-in cannon. A ranged caster acolyte. " + _STYLE),
    ),
    "exploder": dict(
        height=1.8, poly=26000,
        name="Volatile Exploder (Hive Cursed Thrall-like suicide)",
        front=("A bloated Hive alien creature, the Volatile Exploder, front view. A "
                "swollen distended humanoid with a grotesquely bulging glowing abdomen "
                "about to burst, with " + _HIVE + " cracked apart over the swollen belly "
                "to leak intense bright teal soulfire, stubby arms and legs, and a small "
                "fanged skull head with glowing teal eyes. A volatile suicide bomber "
                "creature. " + _STYLE),
    ),
    # --- bosses (taller) ----------------------------------------------------------
    "shielded_brute": dict(
        height=3.0, poly=42000,
        name="Shielded Brute (Hive Knight-like heavy boss)",
        front=("A towering heavily-armoured Hive alien knight, the Shielded Brute, a "
                "massive boss, front view. A huge broad-shouldered hulking humanoid clad "
                "in thick layered chitinous plate armour with " + _HIVE + ", enormous "
                "armoured forearms and layered pauldrons, and a horned skull-faced helm "
                "with a glowing teal soulfire visor. An imposing armoured juggernaut. "
                + _STYLE),
    ),
    "phantom": dict(
        height=2.4, poly=34000,
        name="Teleporting Phantom (Hive Wizard-like caster boss)",
        front=("An ethereal floating Hive alien sorcerer, the Teleporting Phantom, a "
                "boss, front view. A tall gaunt humanoid wraith wrapped in tattered "
                "flowing chitinous ceremonial robes that trail into wisps, with " + _HIVE
                + ", a smooth eyeless skull face, and long spindly clawed empty arms held "
                "out. Intense glowing teal soulfire pours from the hands, eye sockets and "
                "the seams of the robe. A spectral ghostly sorcerer. " + _STYLE),
    ),
    "ember_tyrant": dict(
        height=4.0, poly=42000,
        name="Ember Tyrant (Hive Ogre-like fire boss, molten-orange)",
        # The ONE exception to the teal palette: its Venus fire element -> molten orange.
        front=("A colossal hulking Hive alien ogre, the Ember Tyrant, a huge infernal "
                "fire boss, front view. An enormous muscular humanoid brute with a massive "
                "upper body, huge heavy arms and fists, hunched broad shoulders, and a "
                "small horned skull head dominated by one giant glowing molten-orange eye. "
                "Charred blackened chitinous exoskeleton carapace plating with ridged "
                "volcanic armour, cracked open to reveal glowing molten-orange lava and "
                "ember light within, brushed-gold ceremonial rune trim, streams of molten "
                "fire running through every crack. A towering volcanic juggernaut. "
                + _STYLE),
    ),
}


def _back_prompt(cfg):
    return ("Show the exact same creature, the " + cfg["name"].split(" (")[0] + ", from "
            "directly behind: a clean BACK view, same standing A-pose with both arms held "
            "out and feet apart, same materials, same colours, same build and silhouette, "
            "same plain grey studio background and lighting. Keep the identical character. "
            + _STYLE)


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


def stage_concept(key, cfg, force=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    front = os.path.join(OUT_DIR, f"{key}_front.png")
    back = os.path.join(OUT_DIR, f"{key}_back.png")
    if os.path.exists(front) and not force:
        print(f"SKIP concept {key}: {front} exists (use --force)", flush=True)
    else:
        print(f"[{key}] concept FRONT via nano-banana-pro ...", flush=True)
        res = run(NANO, {"prompt": cfg["front"], "aspect_ratio": "3:4",
                         "resolution": "2K", "num_images": 1})
        if "__error__" in res:
            print("FRONT-FAILED", res["__error__"], flush=True); return
        u = first_img(res)
        if not u:
            print("FRONT-NO-URL", json.dumps(res)[:400], flush=True); return
        urllib.request.urlretrieve(u, front)
        print(f"[{key}] front ->", front, flush=True)

    if os.path.exists(back) and not force:
        print(f"SKIP back {key}: {back} exists (use --force)", flush=True)
        return
    print(f"[{key}] concept BACK via nano-banana-pro/edit (identity-locked) ...", flush=True)
    fu = upload(front)
    res = run(NANO_EDIT, {"prompt": _back_prompt(cfg), "image_urls": [fu],
                          "aspect_ratio": "3:4", "resolution": "2K", "num_images": 1})
    if "__error__" in res:
        print("BACK-FAILED", res["__error__"], flush=True); return
    u = first_img(res)
    if not u:
        print("BACK-NO-URL", json.dumps(res)[:400], flush=True); return
    urllib.request.urlretrieve(u, back)
    print(f"[{key}] back ->", back, flush=True)


def stage_mesh(key, cfg, force=False):
    os.makedirs(RAW_DIR, exist_ok=True)
    front = os.path.join(OUT_DIR, f"{key}_front.png")
    back = os.path.join(OUT_DIR, f"{key}_back.png")
    glb = os.path.join(RAW_DIR, f"{key}_mesh.glb")
    if not os.path.exists(front):
        print(f"no concept for {key} -- run --stage concept first", flush=True); return
    if os.path.exists(glb) and not force:
        print(f"SKIP mesh {key}: {glb} exists (use --force)", flush=True); return
    imgs = [upload(front)]
    if os.path.exists(back):
        imgs.append(upload(back))
    print(f"[{key}] mesh meshy/v7/multi-image-to-3d ({len(imgs)} views, a-pose, "
          f"{cfg['poly']} tris) ...", flush=True)
    payload = {"image_urls": imgs, "pose_mode": "a-pose", "should_texture": True,
               "enable_pbr": True, "should_remesh": True, "topology": "triangle",
               "target_polycount": cfg["poly"], "symmetry_mode": "on"}
    res = run(MESH, payload)
    if "__error__" in res:
        print("MESH-FAILED", res["__error__"], flush=True); return
    g = glb_url(res)
    if not g:
        print("MESH-NO-URL", json.dumps(res)[:600], flush=True); return
    urllib.request.urlretrieve(g, glb)
    with open(os.path.join(RAW_DIR, f"{key}_mesh_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    print(f"[{key}] mesh DONE ->", glb, flush=True)


def _download_anims(key, res):
    """Save the walk/run locomotion clips from a rigging response. basic_animations
    shape varies (dict of name->url|obj, or a list), so download generically to raw/."""
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
            dst = os.path.join(RAW_DIR, f"{key}_{name}.glb")
            urllib.request.urlretrieve(u, dst)
            saved.append(dst)
    return saved


def stage_rig(key, cfg, force=False):
    """Rig + idle. The `animation_glb` (rigged mesh WITH the idle baked) is saved as the
    drop-in <type>.glb; the bind-pose rig and the walk/run clips land in raw/ for the
    Blender merge + cleanup (rename clips, merge walk into the idle GLB, strip junk, face
    -Z). The final committed <type>.glb is written by that Blender pass."""
    os.makedirs(RAW_DIR, exist_ok=True)
    mesh = os.path.join(RAW_DIR, f"{key}_mesh.glb")
    out = os.path.join(OUT_DIR, f"{key}.glb")
    if not os.path.exists(mesh):
        print(f"no mesh for {key} -- run --stage mesh first", flush=True); return
    if os.path.exists(out) and not force:
        print(f"SKIP rig {key}: {out} exists (use --force)", flush=True); return
    mu = upload(mesh, "model/gltf-binary")
    print(f"[{key}] rig fal-ai/meshy/rigging ($0.80, h={cfg['height']}) ...", flush=True)
    payload = {"model_url": mu, "height_meters": cfg["height"],
               "enable_animation": True, "animation_action_id": 0}  # 0 = Idle
    res = run(RIG, payload)
    if "__error__" in res:
        print("RIG-FAILED", res["__error__"], flush=True); return
    with open(os.path.join(RAW_DIR, f"{key}_rig_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    u = _url_of(res.get("animation_glb")) or _url_of(res.get("rigged_character_glb"))
    if not u:
        print("RIG-NO-GLB", json.dumps(res)[:600], flush=True); return
    bind = _url_of(res.get("rigged_character_glb"))
    if bind:
        urllib.request.urlretrieve(bind, os.path.join(RAW_DIR, f"{key}_rigged.glb"))
    urllib.request.urlretrieve(u, out)
    anims = _download_anims(key, res)
    print(f"[{key}] rig DONE ->", out, flush=True)
    print(f"[{key}] locomotion clips:", anims, flush=True)


def stage_moveset(key, cfg, force=False, ids=None):
    """Meshy multi-animation: bake attack/fire clips against the enemy's rig ($0.08).
    Saves each clip GLB to raw/move_<name>.glb for the Blender merge. Because every
    enemy shares the Meshy skeleton, a scout on ONE mesh produces clips reusable across
    the roster. Pass ids=[..] to override the default ATTACK_IDS spread."""
    os.makedirs(RAW_DIR, exist_ok=True)
    mesh = os.path.join(RAW_DIR, f"{key}_mesh.glb")
    if not os.path.exists(mesh):
        print(f"no mesh for {key} -- run --stage mesh first", flush=True); return
    use_ids = ids if ids else list(ATTACK_IDS)
    marker = os.path.join(RAW_DIR, f"{key}_move_{ATTACK_IDS.get(use_ids[0], use_ids[0])}.glb")
    if os.path.exists(marker) and not force:
        print(f"SKIP moveset {key}: {marker} exists (use --force)", flush=True); return
    mu = upload(mesh, "model/gltf-binary")
    print(f"[{key}] moveset multi-animation ids={use_ids} ($0.08) ...", flush=True)
    res = run(MULTIANIM, {"model_url": mu, "height_meters": cfg["height"],
                          "animation_action_ids": use_ids})
    if "__error__" in res:
        print("MOVESET-FAILED", res["__error__"], flush=True); return
    with open(os.path.join(RAW_DIR, f"{key}_moveset_response.json"), "w") as f:
        json.dump(res, f, indent=2)
    anims = res.get("animations")
    if not isinstance(anims, list):
        print("MOVESET-NO-ANIMS", json.dumps(res)[:500], flush=True); return
    saved = []
    for a in anims:
        aid = a.get("action_id") if isinstance(a, dict) else None
        u = _url_of(a.get("animation_glb")) if isinstance(a, dict) else None
        if not (u and u.endswith(".glb")):
            continue
        name = ATTACK_IDS.get(aid, "id%s" % aid)
        dst = os.path.join(RAW_DIR, f"{key}_move_{name}.glb")
        urllib.request.urlretrieve(u, dst)
        saved.append(dst)
    print(f"[{key}] moveset saved:", saved, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--enemy", default="rusher",
                    help="rusher|shooter|exploder|shielded_brute|phantom|ember_tyrant|all")
    ap.add_argument("--stage", default="concept", help="concept|mesh|rig|moveset|all")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--ids", default="", help="comma action IDs for moveset (default ATTACK_IDS)")
    a = ap.parse_args()
    keys = list(ENEMIES) if a.enemy == "all" else [a.enemy]
    for k in keys:
        if k not in ENEMIES:
            print("unknown enemy", k, "-- choices:", list(ENEMIES)); return
    stages = ["concept", "mesh", "rig"] if a.stage == "all" else [a.stage]
    for k in keys:
        cfg = ENEMIES[k]
        for s in stages:
            if s == "concept":
                stage_concept(k, cfg, a.force)
            elif s == "mesh":
                stage_mesh(k, cfg, a.force)
            elif s == "rig":
                stage_rig(k, cfg, a.force)
            elif s == "moveset":
                ids = [int(x) for x in a.ids.split(",") if x.strip()] if a.ids else None
                stage_moveset(k, cfg, a.force, ids=ids)
            else:
                print("unknown stage", s); return


if __name__ == "__main__":
    main()
