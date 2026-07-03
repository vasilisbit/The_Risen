# The Risen

Mission-based third-person looter shooter. A Guardian fights across Earth, Mars,
and Venus to recover critical technology, collecting loot and upgrading gear
between missions aboard a starship hub.

Built with **Unreal Engine 5.8**, Blueprints first (C++ only where necessary).
Solo-developed. Design documents, task backlog, and analysis tooling live in the
companion planning repository
([game-dev-the-risen](https://github.com/IBilba/game-dev-the-risen)).

## Requirements

- Windows 10/11, Unreal Engine **5.8** (Epic Games Launcher)
- The editor-side AI tooling uses the built-in Unreal MCP plugins
  (`ModelContextProtocol` + `AllToolsets`), pre-enabled in the `.uproject`

## Opening the project

Double-click `The_Risen.uproject`, or open it from the Epic Games Launcher.
The project is Blueprint-only; no code compilation is required.

## Project structure

```
The_Risen/
├── The_Risen.uproject
├── Config/                  project settings (default maps, project info)
└── Content/
    ├── Art/                 characters, environments, weapons, VFX
    ├── Audio/               music, SFX, voice
    ├── Blueprints/          player, enemies, weapons, pickups, game modes, managers
    ├── Levels/              L_MainMenu, L_Hub_Starship, L_Mission_Earth/Mars/Venus
    ├── UI/                  HUD, menus, vendor widgets
    └── ThirdParty/          Quixel, Mixamo, AI-generated imports
```

Asset naming uses the standard prefixes: `BP_` `WBP_` `ABP_` `M_` `MI_` `NS_`
`SM_` `L_` `T_`.

## Conventions

- Branches: `main` (stable builds only), `develop` (integration),
  `feature/t-00xx-name` (one per task card).
- Commits: Conventional Commits with the task id as scope, for example
  `feat(t-0002): Add Guardian shield recharge`.
- Generated folders (`Binaries/`, `DerivedDataCache/`, `Intermediate/`,
  `Saved/`, `Build/`) are git-ignored; never commit them.

## Status

Pre-production bootstrap (T-0001): project shell created; the hub level
`L_Hub_Starship` is the next in-editor step.

## License

Private project; all rights reserved. Third-party and AI-generated asset
licenses are credited in-game before release.
