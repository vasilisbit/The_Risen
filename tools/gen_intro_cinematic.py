#!/usr/bin/env python3
"""Generate the NEW-CHARACTER intro cinematic on fal.ai (stdlib only; run via `uv run python`).

A ~2-minute BLACK-AND-WHITE cinematic lore intro, female-narrated over an orchestral bed,
that plays once when the player starts a new character and ends on the Guardian waking in
the cockpit -> gameplay. Full plan: game-dev-the-risen/docs/INTRO_CINEMATIC_PLAN.md.

Method (consistency on a budget):
  nano-banana-pro/edit -> 16 B&W keyframes, one STYLE string + the hero-ship / Guardian refs
                          composited in so look + identity never drift              [image]
  minimax/h3 i2v       -> 15 clips, each animating frame[i] (start) -> frame[i+1] (end).
                          CHAINED: the end frame of clip N == the start frame of clip N+1,
                          so cuts are seamless match-dissolves and we pay for 16 images, not 30.
  stable-audio + tts   -> orchestral score + female narration                        [audio]
  ffmpeg               -> xfade the clips, ONE uniform B&W grade + grain + letterbox over the
                          whole timeline, lay ducked music + VO, transcode to Ogg Theora .ogv
                          (Godot's core VideoStreamPlayer only decodes Theora).

Output: assets/generated/intro/intro.ogv (+ intro.mp4, the keyframe pngs, clip mp4s, audio).

    uv run --no-project python tools/gen_intro_cinematic.py --stage probe     # check H3 enums cheaply
    uv run --no-project python tools/gen_intro_cinematic.py --stage frames    # keyframes only (~$2.5)
    uv run --no-project python tools/gen_intro_cinematic.py --stage video     # H3 clips (~$9.6)
    uv run --no-project python tools/gen_intro_cinematic.py --stage audio      # score + VO (~$0.3)
    uv run --no-project python tools/gen_intro_cinematic.py --stage assemble   # ffmpeg -> intro.ogv
    uv run --no-project python tools/gen_intro_cinematic.py --stage all
      optional: --dur 8   --res 768P   --force   --only 3   --voice Rachel

Auth: FAL_KEY from .env.local (gitignored), same as tools/falgen.py / gen_fold_video.py.
Needs ffmpeg on PATH.
"""
import os, sys, time, json, subprocess, urllib.request, urllib.error

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "generated", "intro")
FR_DIR = os.path.join(OUT_DIR, "frames")
CLIP_DIR = os.path.join(OUT_DIR, "clips")
AUD_DIR = os.path.join(OUT_DIR, "audio")

IMG_MODEL = "fal-ai/nano-banana-pro/edit"
IMG_MODEL_T2I = "fal-ai/nano-banana-pro"           # pure text->image (frames with no ref to edit)
VID_MODEL = "minimax/h3/image-to-video"
MUSIC_MODEL = "fal-ai/stable-audio-3/small/music/base/text-to-audio"
TTS_MODEL = "fal-ai/elevenlabs/tts/eleven-v3"   # expressive: inline [tags] direct the delivery

ASPECT = "16:9"
IMG_RES = "2K"          # keyframe resolution (crisp source; the video is downscaled anyway)
DUR = 8                 # seconds per clip (H3 default 5; --dur to override, probe first)
VID_RES = "768P"        # 480P / 768P / 2K / 4K -> 768P keeps all-motion 2 min inside budget

# The user's hero ship (nano-banana request 019fcd3f-...), reused from gen_fold_video.py so the
# Vanguard reads identically here. Composited into ship frames via nano-banana-pro/edit.
SHIP_REF = "https://v3b.fal.media/files/b/0aa4ff96/6H6Lp2ifD7jVbyPJly2af_KPxDEVFi.png"
SHIP_DESC = ("this exact spaceship - a sleek black hard-surface hull with fine filigree trim "
             "and two large curved glowing wing-blades - keep its silhouette identical")

# One look for the whole film. Appended to every frame prompt. B&W is enforced here.
STYLE = (" -- black and white, high-contrast monochrome cinematic film still, dramatic "
         "chiaroscuro lighting, deep inky blacks and bright silver highlights, fine 35mm film "
         "grain, anamorphic widescreen, volumetric haze and god rays, epic scale, photoreal, "
         "no text, no captions, no words, no subtitles, no letterbox bars.")

# A master Guardian reference is generated first (stage frames) and its fal URL reused to edit
# the Guardian into later frames so the armour design stays consistent. Filled at runtime.
GUARDIAN_REF = None
_FAILED = []
GUARDIAN_DESC = ("a lone armoured Guardian - a sci-fi warrior in a sealed modular helmet with a "
                 "narrow glowing visor slit, layered matte battle-worn armour plates, a torn "
                 "cape - keep this exact character design identical")

# 16 keyframes. ref: None = text->image; "ship"/"guardian" = edit that reference in. The frames
# are chained: clip i animates FRAMES[i] -> FRAMES[i+1] with MOTION[i].
FRAMES = [
    ("00_guardian_cliff", "ref:guardian",
     "Wide silhouette of a lone armoured Guardian standing on the edge of a high cliff, seen "
     "from behind against a vast dying star low on the horizon, torn cape stirring in the wind, "
     "an ocean of cloud far below, tiny lone figure, immense sky."),
    ("01_light_in_palm", "ref:guardian",
     "Extreme close-up of the Guardian's open armoured gauntlet held up, cradling a single "
     "brilliant point of pure white light that blooms and glows, reflections dancing on the "
     "metal plates, dark background, reverent."),
    ("02_rampart_line", "ref:guardian",
     "A long line of lone armoured Guardian sentinels standing watch along a high fortress "
     "rampart, cloaks stirring, looking out over a vast luminous future city glowing far below "
     "under a stormy sky, a solemn quiet vigil, heroic wide shot."),
    ("03_sky_tears", None,
     "A jagged blazing rift tearing open across a stormy night sky above a city skyline, like a "
     "vertical door of light ripped into the clouds, wrong light pouring out, debris and embers "
     "rising toward it, ominous, awe and dread."),
    ("04_earth_burns", None,
     "The planet Earth seen from low orbit filling the frame, continents and a fine glittering "
     "grid of city lights, waves of bright glowing embers and light spreading outward across the "
     "dark disc, thin atmosphere rim catching light, vast and silent, ominous."),
    ("05_ash_boulevard", None,
     "Ground level in a ruined grand city boulevard, a colossal toppled statue, gutted "
     "skyscrapers, thick ash falling like snow through shafts of pale light, abandoned, still, "
     "apocalyptic aftermath."),
    ("06_mars_fallen", None,
     "A vast Martian canyon under a dust-choked sky, a wrecked human mining outpost half buried "
     "in grey-red dust, blowing dust veils, a dead world, desolate wide shot."),
    ("07_debris_field", "ref:guardian",
     "A lone weathered armoured Guardian floating powered-down and motionless in deep space, "
     "drifting slowly among scattered fragments of metal and glinting stardust, cold distant "
     "starlight, silent and mournful, weightless wide shot."),
    ("08_fallen_helm", None,
     "Extreme close-up of a smooth futuristic armoured helmet resting quietly in shadow, a soft "
     "faint point of light glowing gently inside its visor slit, delicate frost crystals "
     "spreading across the polished metal surface, calm minimal still life, cinematic."),
    ("09_vanguard_adrift", "ref:ship",
     f"{SHIP_DESC}. The lone spaceship drifting powered-down among distant war debris, tiny "
     "against an immense dark starfield, a single small window faintly lit, abandoned, adrift on "
     "a dark tide, lonely wide shot."),
    ("10_cockpit_sleeper", "ref:guardian",
     "Interior of a dark starship cockpit, a single armoured Guardian pilot sealed and asleep "
     "slumped in the command chair, frost on the canopy glass, one small console light pulsing "
     "faintly in the gloom, cold, still, a hundred-year sleep."),
    ("11_indicator_blink", None,
     "Extreme macro close-up of a single small indicator light on a dark control panel blinking "
     "in the blackness, then steadying to a solid glow, dust motes, shallow focus, a heartbeat "
     "returning."),
    ("12_archive_pulse", None,
     "Beneath a ruined city, a huge ancient buried structure in shadow, a pulse of light rising "
     "up through cracks in the rubble floor, illuminating dust, mysterious, something waking "
     "underground, low angle."),
    ("13_archive_core", None,
     "A towering monolith of light standing in a vast dark subterranean chamber, rows of alien "
     "glyphs igniting one after another up its surface, an ancient Archive powering on, sacred "
     "and immense, wide shot."),
    ("14_cockpit_wake", "ref:ship",
     "Interior starship cockpit reawakening: banks of consoles and holographic HUD lines "
     "drawing and lighting up in sequence around the command chair, reflections sweeping across "
     "a Guardian's visor, systems booting, hopeful, dynamic."),
    ("15_eyes_open", "ref:guardian",
     "Extreme close-up of a Guardian's visor as the eyes and the suit's seam-lights relight from "
     "black to brilliant, the camera pushing straight in toward the growing light until it fills "
     "the frame, rebirth, the moment of waking."),
]

MOTION = [
    "Slow cinematic reveal emerging from darkness; the lone Guardian holds still on the cliff as wind moves the cape and cloud; the dying star glows. Very slow, epic, no text.",
    "Slow push in toward the open gauntlet as the point of light blooms brighter, metal reflections shifting. Reverent, gentle, no text.",
    "Slow crane upward revealing the full rank of Guardians along the rampart and the luminous city below; storm light flickers. Grand, no text.",
    "The blazing rift rips further open across the sky, embers and debris streaming upward into it, light spilling out. Ominous, building, no text.",
    "Blossoms of fire spread outward across the dark face of the Earth as the camera drifts slowly closer to the burning grid of cities. Catastrophic, slow, no text.",
    "The camera drifts downward through falling ash into the ruined boulevard past the toppled statue; ash sifts down. Desolate, slow, no text.",
    "Slow pan across the dead Martian outpost as dust veils blow past; nothing moves. Mournful, no text.",
    "Slow dolly through the silent field of drifting wreckage and broken Guardian armour tumbling in the void. Weightless, sorrowful, no text.",
    "Slow push in on the cracked drifting helmet as the visor light dims to black and frost creeps across the metal. Intimate, fading, no text.",
    "The dark powered-down Vanguard rotates slowly into view against the vast starfield, its single window faintly lit. Lonely, adrift, no text.",
    "The camera drifts slowly toward the frozen sleeping pilot in the command chair as the lone console light pulses. Cold, still, no text.",
    "Extreme macro: the single indicator light blinks in the black, then steadies to a solid glow; dust motes drift. A heartbeat returning, no text.",
    "A pulse of light rises up through the cracked rubble floor, brightening the buried chamber and the dust in the air. Something waking, no text.",
    "Rows of glyphs ignite one after another climbing the monolith of light in the dark chamber. Sacred, building, no text.",
    "Consoles and holographic HUD lines draw and light up in sequence around the cockpit, reflections sweeping across the visor; systems boot. Hopeful, dynamic, no text.",
    "The camera pushes straight in toward the visor as the eyes and suit seam-lights relight from black to brilliant white until the light fills the whole frame. Rebirth, no text.",
]

# --- narration + score prompts (stage audio) ---
# Eleven v3: inline [tags] steer emotion/delivery; ellipses + line breaks pace the read. Written
# to run ~105s of dramatic narration so the assembler can land the final line on the eyes-open shot.
NARRATION = (
    "[somber] Before the fall... we called ourselves Guardians.\n\n"
    "[reflective] We carried the Light — the last ember of a dying sun — and we swore... that no "
    "darkness would take the worlds of humankind.\n\n"
    "For a hundred years, we held the line. [resigned] We believed we always would.\n\n"
    "[ominous] The Ember Collective did not come with fleets. They came with doors... torn into "
    "the sky... spilling fire from somewhere older than the stars.\n\n"
    "[grave] Earth was the first to burn. Its cities fell from the inside out... its oceans went "
    "to ash.\n\n"
    "Then Mars. [whispering] Then the long silence between the worlds.\n\n"
    "[sorrowful] One by one... the Guardians fell. And the Light went out of the world.\n\n"
    "[quiet] The Vanguard drifted a hundred years... a dead ship on a dark tide... its last pilot "
    "asleep in the cold.\n\n"
    "[hopeful] But a single light was never meant to go out. It only waited.\n\n"
    "[building] Now something stirs beneath the ash of Earth. An Archive... a memory of how the "
    "doors were opened...\n\n"
    "[resolute] and how they can be closed. Forever.\n\n"
    "[awe] The ship is waking. The Light remembers your name.\n\n"
    "[commanding] Rise... Guardian."
)
SCORE_PROMPT = (
    "Slow, solemn, epic orchestral cinematic score for a science-fiction lore intro. Begins "
    "quiet and mournful with low sustained strings and a lone cello, distant French horns, a "
    "faint female choir; builds gradually with swelling strings and soft timpani, then rises to "
    "a hopeful, heroic full-orchestra and choir climax in the final third. No drums until late, "
    "no electronic elements, seamless, evolving but uniform, no abrupt ending, film trailer mood."
)
SCORE_SECONDS = 120
DEFAULT_VOICE = "Rachel"   # mature, warm-but-grave female ElevenLabs voice


def _key():
    p = os.path.join(ROOT, ".env.local")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8"):
            if line.strip().startswith("FAL_KEY="):
                return line.strip().split("=", 1)[1]
    return os.environ.get("FAL_KEY", "")


H = {"Authorization": f"Key {_key()}", "Content-Type": "application/json"}


def _req(url, data=None, method="GET", timeout=300):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers=H, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} on {method} {url}\n{e.read().decode(errors='replace')[:900]}")


def run(model, payload, timeout=1200):
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
            raise SystemExit(f"gen failed: {json.dumps(st)[:600]}")
        time.sleep(5)
    raise SystemExit("timeout")


def _first_url(res, *keys):
    for key in keys:
        v = res.get(key)
        if isinstance(v, dict) and v.get("url"):
            return v["url"]
        if isinstance(v, list) and v and isinstance(v[0], dict) and v[0].get("url"):
            return v[0]["url"]
    return None


def _dl(url, dest):
    urllib.request.urlretrieve(url, dest)
    return dest


def _dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(out.stdout.strip())
    except ValueError:
        return 0.0


# ---------------- stages ----------------

def gen_frames(force, only):
    global GUARDIAN_REF
    os.makedirs(FR_DIR, exist_ok=True)
    # 1) master Guardian reference (character sheet-ish hero portrait) for identity lock
    gref_png = os.path.join(FR_DIR, "_guardian_ref.png")
    gref_url_file = os.path.join(FR_DIR, "_guardian_ref.url")
    if os.path.exists(gref_url_file) and not force:
        GUARDIAN_REF = open(gref_url_file).read().strip()
    else:
        print("[frames] master Guardian reference", flush=True)
        res = run(IMG_MODEL_T2I, {
            "prompt": ("Full-body hero portrait of " + GUARDIAN_DESC +
                       ", standing facing camera, dramatic rim light, plain dark background." + STYLE),
            "aspect_ratio": ASPECT, "resolution": IMG_RES, "output_format": "png", "num_images": 1})
        GUARDIAN_REF = _first_url(res, "images")
        if not GUARDIAN_REF:
            raise SystemExit(f"no guardian ref url in {json.dumps(res)[:400]}")
        _dl(GUARDIAN_REF, gref_png)
        open(gref_url_file, "w").write(GUARDIAN_REF)

    # 2) the 16 story keyframes
    for i, (name, ref, prompt) in enumerate(FRAMES):
        if only is not None and i != only:
            continue
        png = os.path.join(FR_DIR, f"{name}.png")
        url_file = os.path.join(FR_DIR, f"{name}.url")
        if os.path.exists(url_file) and not force:
            print("skip", name); continue
        full = prompt + STYLE
        print(f"[frames] {i:02d} {name}", flush=True)
        try:
            if ref == "ref:ship":
                res = run(IMG_MODEL, {"prompt": full, "image_urls": [SHIP_REF], "aspect_ratio": ASPECT,
                                      "resolution": IMG_RES, "output_format": "png", "num_images": 1})
            elif ref == "ref:guardian":
                res = run(IMG_MODEL, {"prompt": full, "image_urls": [GUARDIAN_REF], "aspect_ratio": ASPECT,
                                      "resolution": IMG_RES, "output_format": "png", "num_images": 1})
            else:
                res = run(IMG_MODEL_T2I, {"prompt": full, "aspect_ratio": ASPECT, "resolution": IMG_RES,
                                          "output_format": "png", "num_images": 1})
        except SystemExit as e:
            print(f"[frames] !! {name} FAILED, skipping: {str(e)[:200]}", flush=True)
            _FAILED.append(name)
            continue
        url = _first_url(res, "images")
        if not url:
            print(f"[frames] !! {name} no url, skipping: {json.dumps(res)[:200]}", flush=True)
            _FAILED.append(name)
            continue
        _dl(url, png)
        open(url_file, "w").write(url)
    if _FAILED:
        print("[frames] done WITH FAILURES:", ", ".join(_FAILED))
    else:
        print("[frames] done")


def _frame_url(name):
    return open(os.path.join(FR_DIR, f"{name}.url")).read().strip()


def gen_video(force, only, dur):
    os.makedirs(CLIP_DIR, exist_ok=True)
    for i in range(len(FRAMES) - 1):
        if only is not None and i != only:
            continue
        mp4 = os.path.join(CLIP_DIR, f"clip_{i:02d}.mp4")
        if os.path.exists(mp4) and not force:
            print("skip", os.path.basename(mp4)); continue
        start = _frame_url(FRAMES[i][0])
        end = _frame_url(FRAMES[i + 1][0])
        print(f"[video] clip {i:02d} ({dur}s {VID_RES})  {FRAMES[i][0]} -> {FRAMES[i+1][0]}", flush=True)
        res = run(VID_MODEL, {
            "prompt": MOTION[i], "image_url": start, "end_image_url": end,
            "duration": dur, "resolution": VID_RES})
        vurl = _first_url(res, "video")
        if not vurl:
            raise SystemExit(f"no video url for clip {i} in {json.dumps(res)[:400]}")
        _dl(vurl, mp4)
    print("[video] done")


def gen_audio(force):
    os.makedirs(AUD_DIR, exist_ok=True)
    music = os.path.join(AUD_DIR, "score.mp3")
    vo = os.path.join(AUD_DIR, "vo.mp3")
    voice = _arg("--voice", DEFAULT_VOICE)
    if force or not os.path.exists(music):
        print("[audio] orchestral score", flush=True)
        res = run(MUSIC_MODEL, {"prompt": SCORE_PROMPT, "duration": SCORE_SECONDS, "output_format": "mp3"})
        url = _first_url(res, "audio_file", "audio")
        if not url:
            raise SystemExit(f"no music url in {json.dumps(res)[:400]}")
        _dl(url, music)
    if force or not os.path.exists(vo):
        print(f"[audio] female narration v3 (voice={voice})", flush=True)
        res = run(TTS_MODEL, {"text": NARRATION, "voice": voice, "stability": 0.35})
        url = _first_url(res, "audio", "audio_file")
        if not url:
            raise SystemExit(f"no tts url in {json.dumps(res)[:400]}")
        _dl(url, vo)
        json.dump({"text": NARRATION, "model": TTS_MODEL, "voice": voice,
                   "licence": "synthetic speech, fal.ai output licence, IGF-safe (no real person)"},
                  open(os.path.join(AUD_DIR, "voice_lines.json"), "w"), indent=2)
    print("[audio] done")


def assemble(dur):
    """xfade the clips, one uniform B&W grade over the whole timeline, lay ducked score + VO."""
    clips = sorted(f for f in os.listdir(CLIP_DIR) if f.endswith(".mp4"))
    if not clips:
        raise SystemExit("no clips in " + CLIP_DIR + " (run --stage video first)")
    paths = [os.path.join(CLIP_DIR, c) for c in clips]
    xf = 0.4  # crossfade seconds
    # build the xfade chain
    inputs = []
    for p in paths:
        inputs += ["-i", p]
    fc = []
    prev = "0:v"
    offset = 0.0
    for i in range(1, len(paths)):
        offset += (dur - xf)
        out = f"v{i}"
        fc.append(f"[{prev}][{i}:v]xfade=transition=fade:duration={xf}:offset={offset:.2f}[{out}]")
        prev = out
    # IMPORTANT: encode the video as normal COLOR, exactly like the working fold clips - NO
    # `format=gray`. Godot's Theora decoder corrupts flat-chroma (grayscale-encoded) Theora into
    # macroblocks; the colour fold clips play clean. The keyframes are already monochrome content,
    # so the picture still reads B&W; the contrast + luminance + vignette LOOK is applied at
    # playback by a shader (scripts/intro_bw.gdshader via ship_travel.play_intro). Here we only
    # crop-fill each clip to a clean 1280x720 (the fold resolution) - no pad bars, no gray.
    grade = (f"[{prev}]scale=1280:720:force_original_aspect_ratio=increase,"
             f"crop=1280:720,setsar=1[vg]")
    fc.append(grade)
    total = offset + dur
    music = os.path.join(AUD_DIR, "score.mp3")
    # prefer the re-paced narration (final line delayed onto the eyes-open shot) when present
    vo_paced = os.path.join(AUD_DIR, "vo_paced.mp3")
    vo = vo_paced if os.path.exists(vo_paced) else os.path.join(AUD_DIR, "vo.mp3")
    have_audio = os.path.exists(music) and os.path.exists(vo)
    if have_audio:
        ai_m = len(paths)
        ai_v = len(paths) + 1
        inputs += ["-i", music, "-i", vo]
        # place the VO. If it nearly fills the film, end-align so the last line lands on the
        # eyes-open shot; otherwise FRONT-align (line 1 on the opening cliff) with a short lead-in
        # from black, letting the wake/rise climax play out on music alone.
        vo_len = _dur(vo)
        if vo_len >= total - 12:
            vo_start = max(1.5, total - 2.5 - vo_len)
        else:
            vo_start = 2.5
        fc.append(f"[{ai_m}:a]volume=0.7,afade=t=out:st={total-3:.2f}:d=3[m]")
        fc.append(f"[{ai_v}:a]adelay={int(vo_start*1000)}|{int(vo_start*1000)},volume=1.8[v0a]")
        fc.append(f"[m][v0a]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[amix]")
        fc.append(f"[amix]afade=t=out:st={total-2:.2f}:d=2[aout]")
        print(f"[assemble] VO {vo_len:.1f}s placed at {vo_start:.1f}s (ends ~{vo_start+vo_len:.1f}s of {total:.1f}s)", flush=True)
    mp4 = os.path.join(OUT_DIR, "intro.mp4")
    ogv = os.path.join(OUT_DIR, "intro.ogv")
    audio_out = os.path.join(OUT_DIR, "intro_audio.ogg")
    cmd = ["ffmpeg", "-y"] + inputs + ["-filter_complex", ";".join(fc), "-map", "[vg]"]
    if have_audio:
        cmd += ["-map", "[aout]", "-c:a", "aac", "-b:a", "256k", "-shortest"]
    cmd += ["-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", "-t", f"{total:.2f}", mp4]
    print("[assemble] ffmpeg ->", os.path.basename(mp4), f"({total:.1f}s)", flush=True)
    subprocess.run(cmd, check=True)
    # Godot's core VideoStreamPlayer only decodes Theora. Ship the video ALONE (no audio track -
    # the Theora+Vorbis mux corrupts Godot's decoder) as normal COLOUR at the fold's exact recipe
    # (-q:v 8, no -g) - the setting proven clean by the mission fold clips. The mixed audio goes to
    # a separate .ogg that ship_travel.play_intro starts in sync; the B&W look is a playback shader.
    print("[assemble] transcode -> intro.ogv (colour, fold recipe) + intro_audio.ogg", flush=True)
    subprocess.run(["ffmpeg", "-y", "-i", mp4, "-an", "-c:v", "libtheora", "-q:v", "8", ogv],
                   check=True)
    if have_audio:
        subprocess.run(["ffmpeg", "-y", "-i", mp4, "-vn", "-c:a", "libvorbis", "-q:a", "6", audio_out],
                       check=True)
    print("[assemble] ->", ogv)


def probe(dur):
    """Cheap sanity check: one tiny clip from two solid frames to confirm H3 enums / key work."""
    os.makedirs(FR_DIR, exist_ok=True)
    print(f"[probe] one {dur}s {VID_RES} H3 clip from the ship reference (confirms key + enums)", flush=True)
    res = run(VID_MODEL, {"prompt": "slow gentle push in, cinematic, no text",
                          "image_url": SHIP_REF, "duration": dur, "resolution": VID_RES})
    print(json.dumps(res)[:500])


def _arg(flag, default=None):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    if not _key():
        raise SystemExit("No FAL_KEY. Put FAL_KEY=... in The_Risen/.env.local (gitignored).")
    stage = _arg("--stage", "all")
    force = "--force" in sys.argv
    only = int(_arg("--only")) if "--only" in sys.argv else None
    dur = int(_arg("--dur", str(DUR)))
    global VID_RES
    VID_RES = _arg("--res", VID_RES)
    if stage in ("probe",):
        probe(dur)
    if stage in ("frames", "all"):
        gen_frames(force, only)
    if stage in ("video", "all"):
        gen_video(force, only, dur)
    if stage in ("audio", "all"):
        gen_audio(force)
    if stage in ("assemble", "all"):
        assemble(dur)
    print("done:", stage)


if __name__ == "__main__":
    main()
