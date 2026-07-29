#!/usr/bin/env python3
"""fal.ai generation helper for The Risen (stdlib only; run via `uv run python`).

Pipeline (budget-conscious): nano-banana-pro -> FLAT albedo textures, patina ->
PBR sets, tripo -> GLB models. Queue API: POST https://queue.fal.run/<model>,
poll status_url, fetch response_url. Auth: `Authorization: Key <FAL_KEY>` read
from .env.local (gitignored). See CLAUDE.md "Asset pipeline" for the rules.

Usage:
  uv run python tools/falgen.py image "<prompt>" out.png [--model fal-ai/nano-banana-pro]
  uv run python tools/falgen.py raw <model> '<json payload>'     # debug: print full response
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_key():
    for name in (".env.local", ".env"):
        p = os.path.join(ROOT, name)
        if os.path.exists(p):
            for line in open(p, encoding="utf-8"):
                line = line.strip()
                if line.startswith("FAL_KEY="):
                    return line.split("=", 1)[1].strip()
    return os.environ.get("FAL_KEY", "")


KEY = load_key()
if not KEY:
    print("ERROR: no FAL_KEY in .env.local or env"); sys.exit(1)
HEADERS = {"Authorization": f"Key {KEY}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET"):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=HEADERS, method=method)
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{detail[:800]}")


def run(model, payload, timeout=420):
    sub = _req(f"https://queue.fal.run/{model}", payload, "POST")
    status_url = sub.get("status_url"); response_url = sub.get("response_url")
    if not status_url:
        return sub  # some models answer synchronously
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = _req(status_url)
        s = st.get("status")
        if s == "COMPLETED":
            return _req(response_url)
        if s in ("FAILED", "ERROR"):
            raise SystemExit(f"generation {s}: {json.dumps(st)[:600]}")
        time.sleep(3)
    raise SystemExit("timed out")


def first_url(res):
    for k in ("images", "image", "outputs", "files"):
        v = res.get(k)
        if isinstance(v, dict):
            return v.get("url")
        if isinstance(v, list) and v:
            it = v[0]
            return it.get("url") if isinstance(it, dict) else it
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__); return
    cmd = sys.argv[1]
    if cmd == "image":
        prompt, out = sys.argv[2], sys.argv[3]
        model = "fal-ai/nano-banana-pro"
        if "--model" in sys.argv:
            model = sys.argv[sys.argv.index("--model") + 1]
        res = run(model, {"prompt": prompt})
        url = first_url(res)
        if not url:
            print("NO_URL; raw:", json.dumps(res)[:800]); return
        urllib.request.urlretrieve(url, out)
        print("SAVED", out, "from", url)
    elif cmd == "raw":
        model, payload = sys.argv[2], json.loads(sys.argv[3])
        print(json.dumps(run(model, payload), indent=2)[:2000])
    else:
        print("unknown command", cmd)


if __name__ == "__main__":
    main()
