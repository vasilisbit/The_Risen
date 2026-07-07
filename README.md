# The Risen

Mission-based third-person looter shooter. A Guardian fights across Earth, Mars,
and Venus to recover critical technology, collecting loot and upgrading gear
between missions aboard a starship hub.

Built with **Godot 4.7**, GDScript first (C# only where necessary).
Solo-developed. Design documents, task backlog, and analysis tooling live in the
companion planning repository
([game-dev-the-risen](https://github.com/IBilba/game-dev-the-risen)).

An earlier Unreal Engine 5.8 prototype of this project is preserved on the
`archive/ue5-prototype` branch.

## Requirements

- Windows 10/11, Godot **4.7** (standard build, GDScript)
- AI-assisted editor work uses the godot-ai MCP plugin (`addons/godot_ai`)
  plus its local Python server; see the planning repository for setup

## Opening the project

Open Godot 4.7, use "Import", and select `project.godot` in this folder
(or run `godot -e --path .` from a terminal here).

## Project structure

```
The_Risen/
├── project.godot
├── scenes/
│   ├── player/            Guardian character scene and scripts
│   ├── hub/               starship hub, hologram table, vendor
│   ├── missions/          earth/ mars/ venus/ level scenes
│   ├── enemies/           enemy archetypes and bosses
│   └── weapons/           weapon scenes and mods
├── ui/                    HUD, menus, vendor screens
├── scripts/               autoloads and shared systems (save, telemetry)
└── assets/
    ├── art/               meshes, materials, textures
    ├── audio/             music, SFX, voice
    └── thirdparty/        external and AI-generated imports
```

Naming follows the Godot style guide: `snake_case` file and folder names,
`PascalCase` node names and `class_name`s, `snake_case` functions and signals.

## Conventions

- Branches: `main` (stable builds only), `develop` (integration),
  `feature/t-00xx-name` (one per task card).
- Commits: Conventional Commits with the task id as scope, for example
  `feat(t-0002): Add Guardian shield recharge`.
- The `.godot/` cache folder is never committed.

## Status

Pre-production bootstrap: engine pivot from UE 5.8 to Godot 4.7 (July 2026).
Project scaffold created; hub scene is the next step.

## License

Private project; all rights reserved. Third-party and AI-generated asset
licenses are credited in-game before release.
