# Character & enemy models

Enemy models are **auto-wired** (like weapons). Drop a model here named after the
enemy's scene basename and `EnemyBase._apply_external_model()` loads it and hides
the primitive capsule:

| Enemy | File name (any one extension) |
|---|---|
| Melee Rusher | `rusher.glb` / `.gltf` / `.tscn` |
| Ranged Shooter | `shooter.glb` … |
| Exploder | `exploder.glb` … |
| Shielded Brute | `shielded_brute.glb` … |
| Teleporting Phantom | `phantom.glb` … |
| Ember Tyrant | `ember_tyrant.glb` … |

**Fit:** the model must face **-Z** (forward) and stand ~**1.8 m** (bosses are
taller — Brute ~3 m, Tyrant ~4 m). Pre-orient/scale it in the import if needed.
The capsule **collision** is untouched — the model is visual only.

**Good CC0 source (no attribution):** Quaternius *Sci-Fi Essentials Kit* includes
**animated robot enemies** — https://quaternius.com/packs/scifiessentialskit.html
(also on https://poly.pizza). Fits the "Risen" machine-enemy theme.

See `docs/ASSET_SOURCES.md` for the full list and licensing rules.
