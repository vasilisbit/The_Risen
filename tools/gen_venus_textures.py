#!/usr/bin/env python3
"""Generate Venus ground PBR textures: nano-banana-pro FLAT albedo -> fal-ai/patina
(normal + roughness), the same pipeline used for the Earth/Mars grounds. Output ->
assets/generated/venus/<name>.png (+ _normal.png / _roughness.png), applied triplanar
by venus_level.gd (_venus_mat).

The albedo prompts DEMAND a flat unlit map: a glossy render would bake highlights
into the basecolor and ruin the PBR conversion (see CLAUDE.md asset pipeline).

Run all:      uv run --no-project python tools/gen_venus_textures.py
Run subset:   uv run --no-project python tools/gen_venus_textures.py obsidian
"""
import os, sys, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "venus")
os.makedirs(OUT, exist_ok=True)
ALBEDO_MODEL = "fal-ai/nano-banana-pro"


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


import time
KEY = _key()
H = {"Authorization": f"Key {KEY}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET"):
    b = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=b, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{detail[:600]}")


def run(model, payload, timeout=420):
    sub = _req(f"https://queue.fal.run/{model}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        return sub
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = _req(su)
        s = st.get("status")
        if s == "COMPLETED":
            return _req(ru)
        if s in ("FAILED", "ERROR"):
            raise SystemExit(f"{s}: {json.dumps(st)[:400]}")
        time.sleep(3)
    raise SystemExit("timed out")


def upload(path):
    name = os.path.basename(path)
    init = _req("https://rest.alpha.fal.ai/storage/upload/initiate",
                {"file_name": name, "content_type": "image/png"}, "POST")
    with open(path, "rb") as f:
        data = f.read()
    put = urllib.request.Request(init["upload_url"], data=data, method="PUT",
                                 headers={"Content-Type": "image/png"})
    with urllib.request.urlopen(put, timeout=180) as r:
        r.read()
    return init["file_url"]


def first_url(res):
    for k in ("images", "image", "outputs", "files"):
        v = res.get(k)
        if isinstance(v, dict):
            return v.get("url")
        if isinstance(v, list) and v:
            it = v[0]
            return it.get("url") if isinstance(it, dict) else it
    return None


FLAT = ("seamless tileable top-down orthographic FLAT UNLIT ALBEDO texture map, "
        "NO lighting, NO shadows, NO reflections, NO gradients, NO highlights, "
        "uniform even flat colour, PBR base color map, high detail")

TEX = {
    "volcanic_rock": "dark volcanic basalt cooled-lava ground surface, charcoal "
        "black-grey porous rough stone with deep cracks and rusty sulfur-orange "
        "mineral streaks, scorched Venus volcano terrain, " + FLAT,
    "obsidian": "black obsidian volcanic glass ground surface, dark glassy stone "
        "with subtle conchoidal fractures and faint deep purple-red sheen, smooth "
        "sharp-edged volcanic glass, " + FLAT,
    "ash": "grey-brown volcanic ash and cinder scree ground, fine powdery ash mixed "
        "with small dark scorched lava pebbles and cinders, dusty Venus volcanic "
        "terrain, " + FLAT,
}


def main():
    want = [a for a in sys.argv[1:] if not a.startswith("-")]
    targets = {k: v for k, v in TEX.items() if not want or k in want}
    for name, prompt in targets.items():
        albedo = os.path.join(OUT, name + ".png")
        res = run(ALBEDO_MODEL, {"prompt": prompt})
        url = first_url(res)
        if not url:
            print("NO_ALBEDO_URL", name, json.dumps(res)[:400], flush=True)
            continue
        urllib.request.urlretrieve(url, albedo)
        print("ALBEDO", name, flush=True)
        # PATINA -> normal + roughness
        src = upload(albedo)
        pr = run("fal-ai/patina", {"image_url": src, "maps": ["normal", "roughness"],
                                    "output_format": "png"})
        imgs = pr.get("images", [])
        for i, m in enumerate(["normal", "roughness"]):
            if i >= len(imgs):
                print("MISSING_MAP", name, m, flush=True)
                continue
            it = imgs[i]
            u = it.get("url") if isinstance(it, dict) else it
            urllib.request.urlretrieve(u, os.path.join(OUT, f"{name}_{m}.png"))
            print("PBR", name, m, flush=True)
    print("DONE", flush=True)


if __name__ == "__main__":
    main()
