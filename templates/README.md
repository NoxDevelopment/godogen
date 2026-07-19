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
  CATALOG.md             # human index: every template by readiness + genre
  tools/
    vendor_addons.py     # clone pinned addons into a project's addons/
    scaffold.py          # Godot: skeleton copy + vendoring + name patch, end to end
    scaffold_unity.py    # Unity: skeleton copy + UPM pin merge + batchmode validation
  ready/                 # verified real look/feel + systems at/near parity
    <genre>/<id>/
      TEMPLATE.md        # human guide: what you get, how to extend
      skeleton/          # a minimal, runnable Godot project (no addons inside)
  needs-work/            # scaffolds/gameplay-bases still short of full parity
    <genre>/<id>/
      TEMPLATE.md        # ditto (Unity ids carry the Unity lane house rules)
      skeleton/          # Godot project, or a text-only Unity project (Assets/ + Packages/ + ProjectSettings/)
```

Reorganized 2026-07-19 from a flat `genres/<id>/` tree to
`<readiness>/<genre>/<id>/`. Readiness (`ready` vs `needs-work`) is Jesus's
sign-off gate; genre is durable. The registry's `skeleton`/`doc` paths and
`CATALOG.md` are the source of truth — consumers resolve paths from the
registry, never by hardcoding the tree.

Skeletons are committed **without** their third-party addons; addons are vendored at scaffold time at pinned commits so every instantiation is reproducible and the license manifest is always regenerated.

## registry.json schema (schemaVersion 1)

Top level: `{ "schemaVersion": 1, "updated": "YYYY-MM-DD", "templates": [ ... ] }`

Each template entry:

| Field | Type | Meaning |
|-------|------|---------|
| `id` | string | Stable identifier; what users type (`/godogen metroidvania`), what scaffold.py takes as its first arg. |
| `name` | string | Display name for pickers. |
| `engine` | `"godot"` \| `"unity"` | Engine family. Unity/Unreal variants land as separate entries with a **suffixed id** (`<id>-unity`, `<id>-unreal`) so id lookup stays unambiguous (roadmap §5.1). Unity entries swap some fields — see the Unity section below. |
| `engineVersion` | string | **Pinned per kit.** The engine version the template was validated against (e.g. `4.6.1-stable`; Unity entries pin the LTS stream, e.g. `6000.0 LTS`, with the exact validated build in `validatedEditor`). Addon pins are chosen for this version — do not mix. |
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

### Unity entries (`engine: "unity"`)

Unity templates carry `upmPackages` **instead of** `vendoredAddons` (third-party
code arrives through Unity's package manager, pinned by exact version, not by
git vendoring), plus two Unity-only fields:

| Field | Meaning |
|-------|---------|
| `engineVersion` | The LTS stream the skeleton targets (e.g. `6000.0 LTS`). The skeleton's `ProjectSettings/ProjectVersion.txt` pins an exact build inside that stream; any editor from the same stream opens it without an upgrade prompt. |
| `validatedEditor` | Exact editor build the batchmode validation ran clean against (e.g. `6000.0.40f1`). Present only on `status: "validated"` entries. |
| `skeleton` | A Unity project dir: `Assets/` (C# sources + editor bootstrap), `Packages/manifest.json`, minimal `ProjectSettings/` (`ProjectVersion.txt` + `ProjectSettings.asset`). **No `.unity` scenes, no `.meta` files** — scenes are built from code by the skeleton's `Assets/Editor/NoxBootstrap.cs` on first import; metas are generated by the editor. |
| `upmPackages` | `[{name, version}]` — exact-version UPM pins. `scaffold_unity.py` merges them into the scaffolded `Packages/manifest.json` (registry wins over the skeleton copy), so re-pinning is a one-line registry edit — the same discipline as `vendoredAddons` commits. |
| `validateMethod` | Fully-qualified static editor method run during batchmode validation (e.g. `NoxDev.Editor.NoxBootstrap.BuildDemoScene`). Proves editor scripts execute — the Unity analogue of Godot's `--import` gate. |

For Unity, `status: "validated"` means: `scaffold_unity.py` ran
`Unity.exe -batchmode -quit -nographics -projectPath <p> -executeMethod <validateMethod> -logFile <log>`
on a real editor from the pinned stream, and the parsed log had **zero
`error CS####` / compile failures / batchmode aborts** and the demo scene was
built and saved. Unity not being installed is a first-class case: scaffolding
still completes (exit 0 with a "validation skipped" warning) and the entry
stays `"draft"` with an honest `statusNote` until a licensed editor validates it.
Unity lane house style (no committed scenes, text-only skeletons, input
polling, uGUI-not-TMP, ABI mapping) is documented in
`needs-work/action/top-down-action-unity/TEMPLATE.md`.

## Tools

```bash
# Full instantiation (what skills and godotsmith call):
python templates/tools/scaffold.py <genre-id> <target-dir> --name "Game Name" [--godot <exe>]

# Vendoring only (re-pin addons into an existing, already-imported project):
python templates/tools/vendor_addons.py --template <genre-id> --project <dir> [--force]

# Unity templates (engine: "unity"):
python templates/tools/scaffold_unity.py <genre-id> <target-dir> --name "Game Name" [--unity <exe>]
```

`vendor_addons.py` clones each addon shallowly at the pin (with `core.longpaths=true` — several kits exceed Windows' 260-char limit), copies only the payload, applies any registry-declared `patches` (pin-verified find/replace fixes, e.g. headless-import guards), enables plugins in `[editor_plugins]`, copies the upstream license file into the vendored dir, and regenerates `addons/LICENSES.md` (name, version, pinned commit, license, source URL).

`scaffold.py` = copy skeleton → patch `config/name` → vendor addons (plugin enable deferred) → **bootstrap `--import` with plugins disabled** → enable plugins. The ordering matters: editor plugins that load before the first asset import / UID cache exist (Popochiu, MetSys, most non-trivial addons) spew bogus errors, so scaffold imports first and enables after — the same order a human follows. Godot is found via `--godot`, `$GODOT`, `godot` on PATH, or common install dirs; with no Godot available, plugins are enabled immediately and the first editor import shows one-time bootstrap noise.

`scaffold_unity.py` = copy skeleton → patch `productName` in `ProjectSettings.asset` → merge the registry's `upmPackages` pins into `Packages/manifest.json` → **batchmode validation** (`-batchmode -quit -nographics -executeMethod <validateMethod> -logFile`), parsing the log for `error CS####` / compile failures / batchmode aborts. Unity is found via `--unity`, `$UNITY`, `Unity` on PATH, Unity Hub install dirs (`C:\Program Files\Unity\Hub\Editor\*`), then the Hub CLI — preferring the editor matching the skeleton's `ProjectVersion.txt`, then the same `major.minor` stream. With no Unity available the scaffold still completes and exits 0 with a "validation skipped" warning (the editor resolves packages and runs the scene bootstrap on first open). An installed-but-unlicensed editor is also reported honestly (validation skipped, scaffold ok).

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
2. Build `needs-work/<genre>/<id>/skeleton/` — minimal but **runnable**: project.godot (ABI buses/inputs/groups), one or two content scenes proving the kit is wired, no third-party code inside. New templates start under `needs-work/`; move to `ready/<genre>/<id>/` (and update the registry `skeleton`/`doc` paths + `CATALOG.md`) once Jesus signs off.
3. Add the registry entry with full pins; `status: "draft"`.
4. Validate: scaffold into a scratch dir, `--import` then `--quit` headless with the pinned engine — zero script errors (addon parse errors mean a wrong pin).
5. Write `TEMPLATE.md` (what you get / how to extend / kit docs links); flip to `status: "validated"`.
