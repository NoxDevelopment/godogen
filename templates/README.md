# NoxDev Genre Template Registry

Genre-template library for game generation. One registry, two consumers:

- **Skills (godogen/gamegen):** `/godogen metroidvania "…"` reads `registry.json`, scaffolds the skeleton, vendors pinned addons, then continues the normal godogen pipeline (visual target → decompose → tasks) *inside* a project that already has the genre's hard systems working.
- **godotsmith / Studio:** the godotsmith server exposes the same registry through `/api/templates` (list + instantiate) so the Studio UI can offer a genre picker at project creation.

Both consumers call the same tools in `tools/`.

## Layout

```
templates/
  registry.json          # the machine-readable registry (this is the API)
  README.md              # this file
  tools/
    vendor_addons.py     # clone pinned addons into a project's addons/
    scaffold.py          # skeleton copy + vendoring + name patch, end to end
  genres/
    <id>/
      TEMPLATE.md        # human guide: what you get, how to extend
      skeleton/          # a minimal, runnable Godot project (no addons inside)
```

Skeletons are committed **without** their third-party addons; addons are vendored at scaffold time at pinned commits so every instantiation is reproducible and the license manifest is always regenerated.

## registry.json schema (schemaVersion 1)

Top level: `{ "schemaVersion": 1, "updated": "YYYY-MM-DD", "templates": [ ... ] }`

Each template entry:

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | Stable identifier; what users type (`/godogen metroidvania`), what scaffold.py takes as its first arg. |
| `name` | string | Display name for pickers. |
| `engine` | `"godot"` | Engine family. Unity/Unreal variants land as separate entries with the same `id` and a different `engine` (see roadmap §5.1). |
| `engineVersion` | string | **Pinned per kit.** The engine version the template was validated against (e.g. `4.6.1-stable`). Addon pins are chosen for this version — do not mix. |
| `description` | string | One paragraph: what the scaffolded project does out of the box. |
| `status` | `"validated"` \| `"draft"` | `validated` = scaffolded + headless-imported + run with zero script errors against `engineVersion`. Pickers should hide or badge `draft`. |
| `skeleton` | path | Skeleton project dir, relative to this directory. |
| `doc` | path | TEMPLATE.md for the genre, relative to this directory. |
| `vendoredAddons` | array | Third-party kits vendored at scaffold time — see below. |
| `primitives` | array | godogen skills (+params) that pair with this template. The orchestrator invokes/offers these after scaffolding: `{skill, params, note}`. Skills live in `skills/<skill>/SKILL.md`. |
| `systems` | array | Drop-in system template dirs to copy wholesale, namespaced by source repo (`godotsmith:templates/menu_system` = that dir inside godotsmith's skill pack). They follow the godotsmith template ABI (below). |
| `docTemplates` | array | Doc scaffolds (GDD/ADR) to instantiate into the project's docs/. Same namespacing as `systems`. |
| `assetPlanHints` | array of strings | Seeds for the asset-planner: what art this genre needs. Same spirit as STRUCTURE.md's `## Asset Hints`. |

### vendoredAddons entries

| Field | Meaning |
|-------|---------|
| `name` | Addon name (used in LICENSES.md and logs). |
| `repo` | Git clone URL. |
| `ref` | Branch or tag to clone (shallow). |
| `commit` | Full SHA pin. If the ref moves, the tool fetches/checks out exactly this commit; a template is only `validated` for this SHA. |
| `version` | Human-readable version note. |
| `license` | SPDX id. **MIT-only policy** for vendored kits (see roadmap §5 license landmines). |
| `licenseFile` | Path of the license file in the upstream repo; copied into the vendored dir. |
| `payload` | Directory inside the repo to copy (most addon repos nest the addon under `addons/<Name>`; script-only kits may use `"."` or `src/`). |
| `targetDir` | Where the payload lands in the project (usually `addons/<Name>`). |
| `enablePlugins` | res:// paths of plugin.cfg files to enable in `project.godot` `[editor_plugins]`. Omit to auto-detect every plugin.cfg in the payload; use `[]` for script-only kits with nothing to enable. |
| `patches` | Optional list of `{file, find, replace, reason}` applied to the vendored copy after checkout. `file` is relative to the payload; `find` must match exactly (a miss hard-fails vendoring so pins and patches get re-verified together). Use sparingly — e.g. guarding an addon's editor plugin against instant-quit `--import` runs. |

## Tools

```bash
# Full instantiation (what skills and godotsmith call):
python templates/tools/scaffold.py <genre-id> <target-dir> --name "Game Name" [--godot <exe>]

# Vendoring only (re-pin addons into an existing, already-imported project):
python templates/tools/vendor_addons.py --template <genre-id> --project <dir> [--force]
```

`vendor_addons.py` clones each addon shallowly at the pin (with `core.longpaths=true` — several kits exceed Windows' 260-char limit), copies only the payload, applies any registry-declared `patches` (pin-verified find/replace fixes, e.g. headless-import guards), enables plugins in `[editor_plugins]`, copies the upstream license file into the vendored dir, and regenerates `addons/LICENSES.md` (name, version, pinned commit, license, source URL).

`scaffold.py` = copy skeleton → patch `config/name` → vendor addons (plugin enable deferred) → **bootstrap `--import` with plugins disabled** → enable plugins. The ordering matters: editor plugins that load before the first asset import / UID cache exist (Popochiu, MetSys, most non-trivial addons) spew bogus errors, so scaffold imports first and enables after — the same order a human follows. Godot is found via `--godot`, `$GODOT`, `godot` on PATH, or common install dirs; with no Godot available, plugins are enabled immediately and the first editor import shows one-time bootstrap noise.

After scaffolding, the project must be clean:

```bash
godot --headless --path <target-dir> --import          # zero script errors
godot --headless --path <target-dir> --quit-after 60   # boots the main scene, zero script errors
```

## Template ABI (must hold for every skeleton)

New templates honor the conventions shared with godotsmith's drop-in templates
(`godotsmith/.claude/skills/godotsmith/templates/README.md`):

- Audio buses `Master`, `Music`, `SFX` exist (skeletons ship `default_bus_layout.tres` wired in `[audio]`).
- Groups: `"player"` on the player node, `"game_manager"` on the global manager, `"persistent"` on nodes that save state (they implement `save_data() -> Dictionary`), `"scalable_text"` on accessibility-scaled labels.
- Scripts reference nodes by the exact `$Path/To/Node` the scene defines; signals declared at top, handlers at bottom.
- Pause UI uses `PROCESS_MODE_ALWAYS`.
- Input actions used by scripts are declared in `project.godot` `[input]` (skeletons bake in the matching input-handling action set, `pause` included).

This keeps godotsmith's `menu_system` / `save_system` / `settings_system` drop-ins copy-pasteable into any scaffolded genre project without adaptation.

## Adding a genre (checklist)

1. Pick the base kit from the roadmap's genre→kit map (MIT only; check the engine-version pin — e.g. MetSys `master` tracks Godot 4.7-dev, branch `4.6` is for 4.6.x; COGITO pins 4.4).
2. Build `genres/<id>/skeleton/` — minimal but **runnable**: project.godot (ABI buses/inputs/groups), one or two content scenes proving the kit is wired, no third-party code inside.
3. Add the registry entry with full pins; `status: "draft"`.
4. Validate: scaffold into a scratch dir, `--import` then `--quit` headless with the pinned engine — zero script errors (addon parse errors mean a wrong pin).
5. Write `TEMPLATE.md` (what you get / how to extend / kit docs links); flip to `status: "validated"`.
