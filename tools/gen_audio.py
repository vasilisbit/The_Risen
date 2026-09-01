#!/usr/bin/env python3
"""Generate The Risen's real audio on fal.ai (stdlib only; run via `uv run python`).

SFX   -> fal-ai/elevenlabs/sound-effects/v2   (text, duration_seconds 0.5-22, loop)
Music -> fal-ai/stable-audio-3/small/music/base/text-to-audio  (prompt, duration)
Voice -> fal-ai/elevenlabs/tts/multilingual-v2  (text, voice) -- Forge Master vendor lines (T-0029)

Files land in assets/generated/audio/{sfx,music}/*.mp3 (picked up automatically by
scripts/audio_manager.gd, which prefers a file over its code-synthesised fallback) and
assets/generated/audio/vendor/*.mp3 (played per-action by scripts/vendor_shop.gd, with a
voice_lines.json metadata/licence sidecar written alongside).

    uv run python tools/gen_audio.py               # generate anything missing
    uv run python tools/gen_audio.py --force       # regenerate everything
    uv run python tools/gen_audio.py --only boss   # just one id (validate before a batch)

Auth: FAL_KEY from .env.local (gitignored), same as tools/falgen.py.
"""
import os, sys, time, json, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "generated", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "generated", "audio", "music")
VOICE_DIR = os.path.join(ROOT, "assets", "generated", "audio", "vendor")

SFX_MODEL = "fal-ai/elevenlabs/sound-effects/v2"
MUSIC_MODEL = "fal-ai/stable-audio-3/small/music/base/text-to-audio"
VOICE_MODEL = "fal-ai/elevenlabs/tts/multilingual-v2"  # ElevenLabs TTS ($0.10/1k chars)

# Forge Master vendor voice (T-0029). A gruff, warm mid-30s male armourer. Each line is
# tied to a SPECIFIC vendor action / tab so vendor_shop.gd can play the right one:
#   buy     -> Weapons tab, weapon purchased
#   upgrade -> Mods tab, mod installed (an upgrade)
#   sell    -> Sell tab, item sold
#   leave   -> shop closed / player leaves
# male mid-30s voice = ElevenLabs "Adam" (deep, natural US male).
VOICE_NAME = "Adam"
# id -> spoken line.
#   greeting        -> played once when the shop menu opens
#   bark_1..bark_3  -> idle lines the hub clerk says at random when the player is near him
VOICE = {
    "buy": "This will serve you well.",
    "upgrade": "Good upgrade, Guardian.",
    "sell": "Thank you for selling that.",
    "leave": "Return with honor.",
    "greeting": "Welcome to the Vanguard Armoury, Guardian. Let's forge something deadly.",
    "bark_1": "Every weapon here is forged for war.",
    "bark_2": "Bring me your Flux, Guardian, and I'll bring you firepower.",
    "bark_3": "Stay sharp out there. The dark doesn't wait.",
}

# id -> (prompt, duration_seconds, loop)
SFX = {
    "warp": ("Sci-fi FTL warp jump: a rising energy whoosh building fast into a deep "
             "powerful bass boom as a spaceship folds space and jumps to lightspeed", 4, False),
    "engine": ("Steady sci-fi spaceship engine thrust: a smooth low rumble with a soft high "
               "electric whine, powerful cruising starship, seamless loop", 10, True),
    "footstep": ("A single quick footstep boot scuff on hard ground, dry and short", 1, False),
    "wind": ("Eerie alien planet ambience: low howling desert wind with a faint hollow "
             "atmospheric drone, seamless loop", 15, True),
    # Weapons — one shot per file (the game fires one per trigger pull), dry and punchy so
    # rapid fire doesn't smear. Futuristic ballistic guns with a teal-energy metallic tail.
    "auto_rifle": ("A single sharp futuristic assault rifle gunshot, fast light mechanical "
                   "crack with a short metallic energy zap tail, dry close-up, no reverb", 0.7, False),
    "shotgun": ("A single heavy sci-fi combat shotgun blast, deep punchy boom with a chunky "
                "mechanical clack, powerful, dry close-up", 0.9, False),
    "sniper": ("A single powerful futuristic sniper rifle shot, loud sharp supersonic crack "
               "with a metallic ring and a quick tail, high-caliber, close-up", 1.0, False),
    "hand_cannon": ("A single heavy sci-fi hand cannon revolver shot, deep booming gunshot "
                    "with a metallic energy snap, powerful, dry close-up", 0.8, False),
    "explosion": ("A punchy sci-fi grenade explosion, deep bass boom with a sharp debris crack "
                  "and short crackling tail, close-up", 1.6, False),
    "enemy_hit": ("A short wet impact hitting an alien creature, dull chitin-flesh thud with a "
                  "faint energy squelch, dry and close", 0.5, False),
    "player_hit": ("A heavy blunt impact on armor, dull metallic thud with a low painful crunch, "
                   "dry close-up", 0.6, False),
    "ui_hover": ("A soft short futuristic UI hover blip, clean subtle high-tech beep", 0.5, False),
    "ui_click": ("A crisp futuristic UI confirm click, clean bright high-tech button press", 0.5, False),
    # Ability SFX for the rebuilt VFX (melees + supers + the two non-frag grenades).
    "melee_blade": ("A single sharp energy blade slash: a fast whoosh with a bright metallic "
                    "energy ring and a short crackling tail, sci-fi, dry close-up", 0.7, False),
    "melee_emp": ("A short EMP punch: a sharp crackling electric zap with a low electromagnetic "
                  "thump, sci-fi, dry close-up", 0.6, False),
    "melee_slam": ("A heavy ground slam impact: a sharp powerful concrete-cracking BOOM with a "
                   "punchy mid-range thud and crunching debris, a short low rumble tail, "
                   "impactful and audible, dry close-up", 1.1, False),
    "super_dome": ("A protective energy shield dome activating: a deep resonant hum rising with "
                   "a shimmering crystalline energy sweep, powerful sci-fi", 1.6, False),
    "super_charge": ("A heroic power-up surge: a rising electric energy whoosh building into a "
                     "strong empowering pulse, triumphant sci-fi", 1.4, False),
    "grenade_heal": ("A gentle healing burst: a soft warm chime with a soothing shimmering "
                     "swell, positive magical sci-fi, close-up", 1.2, False),
    "grenade_flash": ("A blinding flashbang detonation: a sharp high-pitched ringing burst with "
                      "a bright piercing whine, disorienting, close-up", 1.2, False),
    # Enemy vocalizations (Destiny-2 Hive inspired): teal-soulfire alien creatures. Played
    # by enemy_base on spawn, then at random 8-18 s intervals while alive (positional).
    "enemy_rusher": ("A monstrous small alien creature shrieking a frenzied high-pitched "
                     "battle screech as it charges, guttural wet snarl, aggressive, dry", 1.6, False),
    "enemy_shooter": ("An eerie alien acolyte creature letting out a low guttural menacing "
                      "cackling laugh, raspy and otherworldly, sinister, dry close-up", 1.8, False),
    "enemy_exploder": ("A cursed unstable alien creature emitting a rising ominous gurgling "
                       "bubbling hiss, wet and swelling, dread building, dry", 1.8, False),
    "boss_brute": ("A huge armored alien brute bellowing a deep powerful guttural monster "
                   "roar, heavy menacing and commanding, slight echo", 2.4, False),
    "boss_phantom": ("An eerie ghostly alien sorcerer emitting a distorted reverberating "
                     "cackle and a warping ethereal shriek, otherworldly whispers, haunting", 2.4, False),
    "boss_tyrant": ("A colossal molten fire demon roaring a deep booming furious infernal "
                    "roar with crackling flames and embers, monstrous and enormous", 2.6, False),
}
# name -> (prompt, duration). Combat/boss loops the manager crossfades between; the file is
# looped in engine, so ask for a seamless, evolving-but-uniform bed with no hard ending.
MUSIC = {
    "hub": ("Calm ambient sci-fi space station music, slow atmospheric synth pads and gentle "
            "warm drones, floating, spacious and hopeful, no drums, no percussion, seamless loop", 45),
    "travel": ("Cinematic sci-fi space travel cue: a hopeful adventurous synth swell that builds "
               "and rises into a triumphant warp-jump hit, short stinger, orchestral electronic hybrid", 18),
    "earth_combat": ("Driving sci-fi combat music for a firefight in ruined Earth city streets, "
                     "pulsing electronic bass, steady militaristic drums, tense heroic synth "
                     "ostinato, urgent and energetic, seamless loop, no ending", 40),
    "mars_combat": ("Intense fast sci-fi combat music for a battle on Mars, aggressive distorted "
                    "bass, hard fast percussion, dark driving synth arpeggios, relentless and "
                    "adrenaline-fueled, seamless loop, no ending", 40),
    "venus_combat": ("Brutal infernal sci-fi combat music for a firefight on volcanic Venus, "
                     "molten low distorted bass, heavy tribal war drums, searing metallic synth "
                     "leads, oppressive heat and menace, relentless, seamless loop, no ending", 40),
    "boss": ("Epic ominous sci-fi boss battle music, massive pounding war drums, dark brass and "
             "choir stabs, menacing low drone, dread and grandeur, cinematic orchestral "
             "electronic hybrid, seamless loop, no ending", 50),
}


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


H = {"Authorization": f"Key {_key()}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET"):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=180) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{e.read().decode(errors='replace')[:600]}")


def run(model, payload, timeout=420):
    sub = _req(f"https://queue.fal.run/{model}", payload, "POST")
    su, ru = sub.get("status_url"), sub.get("response_url")
    if not su:
        return sub
    t0 = time.time()
    while time.time() - t0 < timeout:
        st = _req(su)
        if st.get("status") == "COMPLETED":
            return _req(ru)
        if st.get("status") in ("FAILED", "ERROR"):
            raise SystemExit(f"gen failed: {json.dumps(st)[:400]}")
        time.sleep(4)
    raise SystemExit("timeout")


def main():
    force = "--force" in sys.argv
    only = None
    if "--only" in sys.argv:
        only = set(sys.argv[sys.argv.index("--only") + 1].split(","))
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)

    for sid, (prompt, dur, loop) in SFX.items():
        if only is not None and sid not in only:
            continue
        dest = os.path.join(SFX_DIR, sid + ".mp3")
        if os.path.exists(dest) and not force:
            print("skip", dest); continue
        print("SFX", sid, flush=True)
        res = run(SFX_MODEL, {"text": prompt, "duration_seconds": dur, "loop": loop,
                              "output_format": "mp3_44100_128", "prompt_influence": 0.45})
        urllib.request.urlretrieve(res["audio"]["url"], dest)
        print("  ->", dest, flush=True)

    for name, (prompt, dur) in MUSIC.items():
        if only is not None and name not in only:
            continue
        dest = os.path.join(MUSIC_DIR, name + ".mp3")
        if os.path.exists(dest) and not force:
            print("skip", dest); continue
        print("MUSIC", name, flush=True)
        res = run(MUSIC_MODEL, {"prompt": prompt, "duration": dur, "output_format": "mp3"})
        urllib.request.urlretrieve(res["audio"]["url"], dest)
        print("  ->", dest, flush=True)

    # Vendor voice lines (TTS). Also writes a metadata sidecar recording the exact text,
    # voice, model and licence for each clip (prompt/licence provenance, T-0029).
    os.makedirs(VOICE_DIR, exist_ok=True)
    meta = {
        "model": VOICE_MODEL, "voice": VOICE_NAME,
        "voice_description": "gruff warm mid-30s male armourer (Forge Master vendor)",
        "licence": ("Synthetic speech generated via fal.ai ElevenLabs Multilingual v2. Not a real "
                    "person; usable under the fal.ai output licence. Commercial/IGF-safe."),
        "lines": {},
    }
    for vid, text in VOICE.items():
        dest = os.path.join(VOICE_DIR, vid + ".mp3")
        meta["lines"][vid] = {"text": text, "file": vid + ".mp3"}
        if only is not None and vid not in only:
            continue
        if os.path.exists(dest) and not force:
            print("skip", dest); continue
        print("VOICE", vid, flush=True)
        res = run(VOICE_MODEL, {"text": text, "voice": VOICE_NAME,
                                "stability": 0.45, "similarity_boost": 0.8, "style": 0.2})
        urllib.request.urlretrieve(res["audio"]["url"], dest)
        print("  ->", dest, flush=True)
    with open(os.path.join(VOICE_DIR, "voice_lines.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    print("done")


if __name__ == "__main__":
    main()
