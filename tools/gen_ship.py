#!/usr/bin/env python3
"""Turn the hero-ship concept image into a GLB with Tripo H3.1 (image-to-3d, the
best-control path per CLAUDE.md). Uploads the concept, submits, polls, downloads.

    python tools/gen_ship.py assets/generated/ship/ship_concept.png hero_ship

Output -> assets/generated/ship/<name>.glb
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated", "ship")
os.makedirs(OUT, exist_ok=True)
MODEL = "tripo3d/h3.1/image-to-3d"
FACE_LIMIT = 250000


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
    img_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(OUT, "ship_concept.png")
    name = sys.argv[2] if len(sys.argv) > 2 else "hero_ship"
    print("UPLOAD", img_path, flush=True)
    url = upload(img_path)
    print("URL", url, flush=True)
    payload = {"image_url": url, "pbr": True, "geometry_quality": "detailed",
               "texture_quality": "detailed", "face_limit": FACE_LIMIT}
    sub = req(f"https://queue.fal.run/{MODEL}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        print("SUBMIT-FAILED", json.dumps(sub)[:600], flush=True); return
    print("SUBMITTED, polling...", flush=True)
    t0 = time.time()
    while time.time() - t0 < 1500:
        st = req(su)
        s = st.get("status")
        if s == "COMPLETED":
            res = req(ru)
            g = glb_url(res)
            if g:
                dest = os.path.join(OUT, name + ".glb")
                urllib.request.urlretrieve(g, dest)
                print("DONE", dest, "from", g, flush=True)
            else:
                print("NO-URL", json.dumps(res)[:500], flush=True)
            return
        if s in ("FAILED", "ERROR"):
            print("FAILED", json.dumps(st)[:400], flush=True); return
        time.sleep(6)
    print("TIMEOUT", flush=True)


if __name__ == "__main__":
    main()
