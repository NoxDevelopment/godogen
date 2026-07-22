# ADVENTURE FORMAT — `ff-gamebook` installable adventure books (format v1)

> **Companion to:** [`GDD.md`](GDD.md) §6.1 #2 (Library / Bookshelf) and §5 (data-driven content).
> **Status:** SHIPPED (drop 1 of the adventure ecosystem — local-first, no networking).
> **Consumers:** the in-game **Library** screen (`scripts/screens/library_view.tscn`), the
> `AdventureLibrary` scanner (`scripts/adventure_library.gd`), the `Adventure` controller, and
> the offline validator `tools/validate_adventure.py`.

FF adventures are no longer hardcoded content — they are **installable BOOKS**. An adventure
is a self-contained package the game discovers at boot from two shelves:

| Shelf | Path | Who puts books there |
|---|---|---|
| **Bundled** | `res://data/adventures/<book-id>/` | shipped with the game / the Studio |
| **Installed** | `user://adventures/<book-id>/` | the player ("Install" = drop a folder or `.zip` in) |

A `.zip` dropped into `user://adventures/` is auto-extracted (once) into a folder of the same
name on the next Library scan, then treated exactly like a folder package.

---

## 1. Package layout

```
<book-id>/                     # folder name SHOULD equal book.json "id"
  book.json                    # the manifest (REQUIRED) — identity + shelf card + asset slots
  adventure.json               # the nox_if_engine scenario (REQUIRED; name set by "entry")
  assets/                      # OPTIONAL per-book payload
    plates/*.png|jpg|webp      #   illustration plates referenced by "slots"
    audio/*.ogg|mp3|wav        #   per-book music/sfx referenced by "slots"
```

Everything the book needs that is not already a **global** slot in `assets.manifest.json`
(fonts, icons, UI chrome, the stock music beds, stock portraits) ships inside the package.
A package never edits the game's global manifest.

## 2. `book.json` — the manifest

```jsonc
{
  "formatVersion": 1,               // REQUIRED int — this spec's version
  "id": "wreckers-light",           // REQUIRED — stable id, [a-z0-9-], unique on the shelf
  "title": "The Wrecker's Light",   // REQUIRED — shelf card + roll-up + saves
  "author": "NoxDev",               // REQUIRED
  "blurb": "A coastal tale of ...", // REQUIRED — 1-3 sentences for the shelf card
  "difficulty": 2,                  // REQUIRED int 1..5 (shelf pips; 3 = classic FF)
  "cover": "plate/wl_cover",        // REQUIRED — slot id of the cover plate (must resolve)
  "entry": "adventure.json",        // OPTIONAL — scenario file, default "adventure.json"
  "ruleset": "ff-2d6",              // OPTIONAL — must match adventure.json "ruleset"
  "version": "1.0.0",               // OPTIONAL — the book's own content version
  "slots": {                        // OPTIONAL — per-book asset slots (see §3)
    "plate/wl_cover": "assets/plates/cover.png",
    "plate/wl_shore": "res://assets/plates/generated/s1.png"
  }
}
```

Unknown keys are ignored (forward-compatible). `formatVersion` **greater** than the game's
supported version ⇒ the book is listed as incompatible and cannot be opened.

## 3. Asset slots — per-book overlay on the AssetBinder

The game resolves every art/audio surface by **stable slot id** through the `AssetBinder`
autoload (GDD §10a). A book's `slots` map extends that contract per book:

* **Key** — a slot id exactly as used by the scenario (`illustration: "plate/wl_shore"`,
  `music` moods, `portrait/...`). Namespacing plate ids per book (`plate/wl_*`) is
  RECOMMENDED so books never collide.
* **Value** — where the file lives:
  * a **relative path** (`assets/plates/cover.png`) — resolved against the package root
    (works for both `res://` bundled and `user://` installed books);
  * an **absolute `res://` path** — reuse of an already-shipped global asset (e.g. the
    generated veritas plates), zero duplication;
  * `user://` absolute is also accepted.
* While a book is **active** (selected in the Library), its slots are pushed as an overlay
  onto the AssetBinder: book slots win, then the global `assets.manifest.json`, then the
  labelled placeholder fallback. Selecting another book swaps the overlay — no code edits.
* A book MAY override a global slot id (e.g. reskin `audio/music/explore`) for its own
  session only; the overlay never persists.

**Reuse ladder applies** (GDD §7): reference shipped plates by `res://` before generating
new ones. Installed (`user://`) books load plates at runtime via `Image.load` — PNG/JPG/WebP.

## 4. `adventure.json` — the scenario

Unchanged `nox_if_engine` scenario format (see `addons/nox_if_engine/if_scenario.gd`
header): `id`, `name`, `meta`, `ruleset: "ff-2d6"`, `start`, `init`, `passages[]` with
choices / conditions / effects / `event` (`combat` | `luck_test` | `skill_test` |
`stamina_test`) / `encounter` / `ending`, plus the FF conventions (underscore outcome
choices `_onwin/_ondeath/_onlucky/...`, per-passage `music` mood, `illustration` slot id).
The scenario `id` SHOULD equal the book `id`.

Every book must pass the authoring validator (`IFAdventureValidator`, mirrored offline by
`tools/validate_adventure.py`): no dangling gotos, no unreachable sections, no dead-ends,
a reachable victory ending, and consistent flags/codewords/items.

## 5. Discovery, identity, saves

* **Scan order:** bundled shelf first, then installed; on a duplicate `id` the **installed**
  book wins (a player can override a bundled book with a patched copy).
* Bare legacy files `res://data/adventures/<id>.json` (no folder) are still discovered — a
  manifest is synthesized from the scenario's `id`/`name`/`meta` (backward-compatible load).
  Files starting with `_` and `*.scaffold.json` are ignored by the scanner.
* **Saves are per-adventure:** every save slot records `bookId` (+ title in its meta).
  Loading a save re-selects that book (scenario + slot overlay) before restoring state;
  Continue resumes the newest save *into the book it belongs to*. A save whose book is no
  longer installed is listed but refuses to load with a "book not installed" warning.

## 6. Validation — `tools/validate_adventure.py`

```
python tools/validate_adventure.py <package-dir|package.zip|bare-scenario.json>
       [--project-root <skeleton-dir>]   # to resolve res:// slot paths (default: auto)
```

Checks, mirroring the in-engine validator plus package concerns:

1. `book.json` schema — required fields, `formatVersion` supported, difficulty 1..5,
   id shape, `cover` resolvable through `slots` or the global manifest;
2. `adventure.json` structure — start exists, all `goto` targets exist (choices, check
   outcomes, goto-effects), reachability from `start`, dead-ends, victory reachable;
3. flag/codeword/var/item consistency — reads nothing ever writes and codewords never
   tested (warning-level, matching the in-engine `IFAdventureValidator`);
4. asset files exist (relative → package, `res://` → project root);
5. FF conventions — combat passages carry `_onwin`/`_ondeath` outcome choices, test
   passages carry `_onlucky`/`_onunlucky` or `_onsuccess`/`_onfailure`.

Exit code 0 = valid (warnings allowed), 1 = errors. The headless `library_probe` runs the
same graph checks in-engine on every shelf book, so CI catches a broken install either way.

## 7. Versioning rules

* `formatVersion` bumps only on breaking package-shape changes; additive keys don't bump.
* The game supports formatVersion `1`. Readers MUST ignore unknown keys, writers MUST NOT
  rely on them.
* Reference package: **`res://data/adventures/grey-tithe/`** (the flagship, restructured to
  this format). Second shipped proof: **`res://data/adventures/wreckers-light/`**.
