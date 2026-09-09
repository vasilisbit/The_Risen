# The Risen — First-Person View & Viewmodel: What We Built and Why

A design/decision report for the Phase-3 first-person work (the focus of the
recent sessions), plus the supporting fixes shipped alongside it. Written so the
reasoning survives a hand-off to another machine/session. Broader project history
lives in `game-dev-the-risen/tracker.md` and `handoff.md`.

Camera is **first person** (a locked design decision). Everything here serves the
goal: *a real, good-feeling FPS view — you see a weapon held in real hands, you
can inspect your character in a mirror, and none of the seams show.*

---

## 1. True first-person camera

**What:** The eye sits at `EYE_HEIGHT 1.45`, `EYE_BACK -0.08` (slightly IN FRONT
of the neck) in `guardian.gd`. The real body is on its own render layer
`BODY_LAYER (1<<18)`; the **main camera excludes that layer**, the **hub mirror's
camera includes it**.

**Why:** We first tried showing the real animated body directly and letting you
look down at your chest/legs. Two things forced the current design:
- Pulling the camera *back* (to see the chest-held gun) made it read as
  **third-person** — you saw the back of your own neck. Rejected by playtest.
- Even at the eyes, looking down showed your own neck/back, which looked wrong.

Putting the body on a layer the main camera skips means **you never see your own
body directly** (true FPS), while the mirror's separate camera still renders it,
so you can inspect yourself. Spawn markers sit ~1 m up, so `_snap_to_floor()`
drops the body to the ground on spawn (otherwise the camera visibly settled).

## 2. The weapon viewmodel (the big one)

**What:** `fp_viewmodel.gd`. The arms+gun render in an **isolated SubViewport**
(own world, own light, transparent background) and are composited on top of the
main view via a `CanvasLayer`/`TextureRect`. The rig is a **second
`PlayerCharacter`** holding the equipped weapon.

**Why a separate viewport, not the real body:** the gun rides on the character's
chest, only ~8 cm from an eye-level camera. We measured it — at that distance the
gun fills the screen, clips into walls, and bobs with the breathing animation.
No camera position is both *first-person* (in front of the neck) and *far enough*
from the chest-gun to frame it like a viewmodel; the neck and the gun are in the
same place. A dedicated viewmodel that lives in its own little world sidesteps
all of that — it's how every FPS actually does it.

**Why it shows only forearms+hands (the "arms-only" mask):** the rig is one
skinned mannequin mesh, so we can't just hide the torso. First we clipped it with
a near plane — that always left a **hard cut** across the forearm (the arm
connects to the torso, so any flat clip slices through it). The fix: bake a
**per-vertex keep/drop mask into vertex colours** (`player_character.arms_only`,
`ARM_KEEP`) — a vertex is kept when its dominant skin bone is a **forearm/hand**
bone, and a discard shader drops everything else. Result: **no torso, no clip, no
cut**, and it's the *same* skinned hands, not crude primitives. We deliberately
dropped the *upper* arms/shoulders from the keep list — kept in, they sat as big
bulky masses right next to the camera and read as deformed blobs. The arm shader
uses a `source_color` uniform for the suit colour (a plain `vec3` was interpreted
in the wrong colour space and came out washed-out pale).

**Framing/feel:** `cam_position`/`cam_look_at` put the gun on the right with a
level barrel pointing at centre. `kick(weapon_name)` snaps the rig back+up on
every shot (per-weapon `KICK` weights) then eases home — that's the recoil.

**Known gap:** the framing is tuned around the auto rifle; recoil numbers want a
live-feel pass.

## 3. Per-weapon grips and hands

**What:** weapons attach to the rig's `weapon_r` socket with a per-weapon
transform (`GRIPS`). One-handed weapons collapse the left arm (`HIDE_LEFT_ARM`,
Hand Cannon) so no support arm draws.

**Why the shotgun has a weird rotation:** the rifle/sniper/hand-cannon are glTF
(Sci-Fi Essentials) and share a uniform `rot(90,0,0)` grip. The **shotgun is the
one FBX** and imports on a different axis convention, so the uniform grip pointed
its barrel the wrong way. We solved it by aiming its barrel (+X) down the socket's
forward axis and reading back the local Euler.

**Open gap — shotgun support hand:** it can't reach the pump. The left hand is
placed by the shared rifle-idle animation, whose grip is too long for the shorter
shotgun. Fixing it needs per-weapon hand **IK** or a **Blender-posed** viewmodel
(see §7). Currently accepted.

## 4. The hub mirror

**What:** `mirror.gd`. Renders from a **camera reflected across the mirror plane**
and samples that render in **screen space** (per the referenced GodotMirror
technique). Full-length mirror mounted flush on the weapon-bay wall.

**Why this and not a hand-aimed camera:** reflecting the *real* camera is what
makes scale, handedness and parallax correct at every position and angle; a
fixed camera with a distance-fudged FOV never could.

**Two problems and their fixes:**
- **Black-out at angles.** A distance-based near plane grew with viewer distance
  and clipped the whole reflection to black from across the room. Replaced with
  **render-layer occlusion**: the wall the mirror hangs on + the glass are on a
  no-reflect layer (`1<<19`) the reflection camera skips. Works at any angle.
- **Too bright / washed out.** The reflection was a display-referred image but was
  sampled as linear ALBEDO and tonemapped a *second* time. The mirror shader now
  **decodes sRGB→linear**, so it's tonemapped exactly once and matches the room.

## 5. Inventory keeps the world running

**What:** opening the inventory no longer pauses the tree; a jump started before
opening **finishes its arc**. The player's own input (move/jump/fire/abilities)
is held while browsing (so a panel click doesn't fire the gun), but physics keeps
running underneath.

**Why:** the pause froze the player mid-air, which felt broken. Destiny (the
visual reference throughout) keeps the world live behind menus.

## 6. Grenade

**What:** throws ~18–20 m (`THROW_SPEED` 17, fuse 2.5 s) and the yellow ball is a
built model — gunmetal capsule casing, a glowing element band that still pulses as
the fuse runs down, and a fuse cap.

**Why:** user wanted more range and a real object; the longer fuse keeps a long
throw from airbursting mid-arc.

## 7. What's left / next (mostly a Blender job)

Blender is installed and its MCP is connected (RFingAdam/mcp-blender or
ahujasid/blender-mcp; see the `blender-mcp-recommendation` memory). The next-most
valuable model jobs, in order:
1. **A real FP-arms mesh** — import the UEFN mannequin, delete everything but the
   forearms+hands, keep the skin, export. Point the viewmodel rig at it, replacing
   the in-engine vertex-mask. Same hands, cleaner, and it lets us author real
   per-weapon hand poses.
2. **Per-weapon two-hand poses** (fixes the shotgun support hand).
3. Better weapon models / a proper Guardian character to replace the placeholder
   mannequin + primitive guns.

Everything must stay commercial-safe (CC0/Fab), no CC-BY-NC.

**Also outstanding, engine-side:** a human playtest for *feel* (almost everything
was verified in-engine by screenshot, never by live input); recoil/sway tuning;
M8 art + AI-asset passes (real music/SFX); M9 packaging/IGF.
