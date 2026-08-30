# Building the Windows Desktop release (T-0038)

How to produce the shipped `The Risen` Windows `.exe`. The export **config**
(`export_presets.cfg`, `build/windows_icon.ico`) is committed; the **build output**
(`exports/`) is git-ignored.

## Prerequisites (one time)
- **Godot 4.7-stable** editor — here: `C:\Tools\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`.
- **Export templates for 4.7.stable** installed at
  `%APPDATA%\Godot\export_templates\4.7.stable\` (must contain
  `windows_release_x86_64.exe`, `windows_debug_x86_64.exe`, `version.txt`, …).
  Install via the editor (**Editor → Manage Export Templates → Download and Install**)
  or by unpacking the official
  `Godot_v4.7-stable_export_templates.tpz` (the `templates/` folder's contents go
  directly into the version folder above).

## Preset — "Windows Desktop" (`export_presets.cfg`)
- **Single-file exe**: `binary_format/embed_pck=true` (PCK embedded in the `.exe`;
  no side-car `.pck` to ship).
- **Architecture**: `x86_64`. **Textures**: `s3tc_bptc=true` (desktop).
- **Custom icon**: `application/icon="res://build/windows_icon.ico"` (multi-size ICO,
  faithful to `icon.svg`; regenerate with `tools/make_icon.py`).
- **Version / PE metadata** (`application/modify_resources=true`): product **The Risen**,
  file/product version **1.0.0.0**, company **Vasileios Bitzas**, copyright, description.
  Bump `application/file_version` + `application/product_version` per release.
- **export_filter=all_resources** — ships every Godot resource incl. `assets/thirdparty/*`
  (needed at runtime even though git-ignored in the repo). Non-resource files (`tools/*.py`,
  `docs/*.md`, `.env.local`) are **not** exported; `.env*`/`tools` are also excluded explicitly.
- **`_mcp_game_helper` autoload is kept in the build on purpose** — it no-ops when the
  debugger channel is inactive (i.e. in an exported release), so excluding
  `addons/godot_ai/` would break the autoload and crash on boot. Leave the addon in.
- **Console wrapper**: `debug/export_console_wrapper=1` → a `The_Risen.console.exe` is
  emitted next to the game exe (handy for reading boot logs; not the shipped entry point).

## Build (CLI, headless)
Stop the running game first if the editor is playing. Then:

```bash
"C:\Tools\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe" \
  --headless --path "<repo>\The_Risen" \
  --export-release "Windows Desktop" "<repo>\The_Risen\exports\windows\The_Risen.exe"
```

Output: `exports/windows/The_Risen.exe` (+ `.console.exe`). Embedded PCK → the single
`.exe` is the game.

## Sanity check
- `--export-release` exits 0 with no `ERROR:` lines.
- Boot the exe; it reaches the **main menu**, then **Earth** loads and completes without
  a crash (DoD). Read `The_Risen.console.exe` output for load errors if headless.
- Size target **< 2 GB** (actual build is well under).

## Notes
- Two Godot processes on one project can contend on `.godot/`; if the editor holds import
  locks, close it (or stop play) before a headless export.
- Icon/version PE patching is built into the Godot 4.x Windows exporter
  (`modify_resources=true`) — no external `rcedit` needed unless code-signing.
