---
name: credits
description: Auto-assemble a game's credits/attribution screen from asset-manifest provenance — every reused/generated asset, font, LoRA/style pack, and tool attributed with its license, so the STANDARDS "credits" box is closed by construction instead of hand-maintained. Use when wiring the Credits screen, before ship, or whenever new assets land and attribution must stay current.
---

# Credits — attribution assembled from provenance, not typed by hand

Credits are a **Definition of Done requirement** (`skills/parity-build/STANDARDS.md`
→ "Credits screen/system — attribution for assets/audio/LoRAs/tools, licenses
honored"). Hand-typed credits rot the moment a new asset lands. This skill derives
them from the source of truth: the [`asset-manifest`](../asset-manifest/SKILL.md).

## The pipeline (two steps, one source of truth)

1. **Export provenance** from the manifest — grouped by license, with LoRAs,
   generation tools, and an `unlicensed` ship-blocker list:
   ```bash
   python3 .claude/skills/asset-manifest/tools/manifest.py export \
     --format credits --output build/credits_assets.json
   ```
2. **Assemble** — merge that with a hand-authored `credits.extra.json` (people/
   roles, fonts, audio libraries, engine, tools, special thanks):
   ```bash
   python3 .claude/skills/credits/tools/credits_gen.py init-extra   # once, then fill in
   python3 .claude/skills/credits/tools/credits_gen.py assemble \
     --assets build/credits_assets.json --extra credits.extra.json \
     --theme res://assets/ui/theme.tres --output-dir assets/ui/credits/
   ```

Everything an asset carries (`--license/--source/--author/--url` on `manifest.py
add`) flows straight into the screen — so credits stay correct as long as assets
are registered with provenance. **Enforce that:** any asset added without a
`--license` surfaces under `unlicensed` and `assemble` warns — treat it as a ship
blocker, not a nit.

## Outputs

| File | Use |
|---|---|
| `credits.txt` | Plain text for the **nox_ui inline Credits panel** — short games paste this into `NoxShellConfig.credits`. |
| `credits.bbcode.txt` | BBCode (headings/centering) baked into the scene below. |
| `credits.md` | Human-readable draft for review / repo docs. |
| `credits.gd` + `credits.tscn` | Themed, **auto-scrolling** Credits scene for asset-heavy games (Esc → menu, Enter pauses the crawl). |

## Two integration modes

- **Short games** → paste `credits.txt` into `NoxShellConfig.credits`; the
  [`ui-shell`](../ui-shell/SKILL.md) main menu already renders a Credits panel from
  that field. No new scene.
- **Asset-heavy games** → ship the scrolling `credits.tscn` and route the shell's
  Credits button (or the end-of-game flow) to it. It calls `NoxShell.to_menu()` on
  back, so it drops into the shell without edits.

## Reuse-first, typography-aware, accessible

- **Reuse-first:** the credits *content* IS the reuse ledger — it exists to
  attribute the owned/CC0/generated assets the reuse ladder pulled in. Any credits
  backdrop art is sourced reuse-first and manifest-tracked like any other asset.
- **Typography deferred:** the scene sets the project `theme.tres` (pass `--theme`)
  and uses BBCode headings — display/body faces come from
  [`typography`](../typography/SKILL.md); this tool never hardcodes a font.
- **Accessible:** the crawl auto-pauses when `NoxSettings.reduced_motion` is set
  (see [`accessibility`](../accessibility/SKILL.md)) and is always manually
  scrollable/pausable — motion is never the only way to read it.

## Cardinal rules

- **Never hand-maintain the asset list.** Re-run `assemble` after every asset
  drop; only `credits.extra.json` (people, fonts, tools) is edited by hand.
- **No blank licenses ship.** `unlicensed` > 0 fails the credits check.
- **Fonts and LoRAs count.** OFL/CC0 fonts (recorded by `typography`) go in
  `credits.extra.json`; LoRA/style packs are pulled automatically from manifest
  `params.lora`. Both must appear.

## Verify

Run `assemble`, confirm `unlicensed_count == 0`, boot the scene scoped
(`--path .`) and **screenshot the scrolling credits** — headings read in the
display face, every license/source present, back-to-menu works. See
`parity-build/STANDARDS.md`.

## Files

- `tools/credits_gen.py` — the CLI (single file, stdlib only).
- `SKILL.md` — this file.

## Composition

- **asset-manifest** — the provenance source; `export --format credits` feeds this skill.
- **ui-shell** — inline Credits panel (short) or hosts the scrolling scene (rich).
- **typography** — supplies the fonts (via `theme.tres`) and the OFL/CC0 entries for `credits.extra.json`.
- **audio-pipeline** — audio-library attributions go in `credits.extra.json` `audio[]`.
