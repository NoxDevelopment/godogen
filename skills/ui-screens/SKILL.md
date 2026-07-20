# UI Screens

Godot 4 Control-tree `.tscn` and Unity Canvas-layout JSON scaffolds for the five common game screens: **title**, **menu**, **hud**, **inventory**, **dialog**. Each subcommand emits a sensibly-laid-out scene that drops straight into the project — no UI guesswork required.

UI element textures (buttons, icons, portraits) are out of scope for this skill — **source** them reuse-first (`skills/asset-reuse`: owned/CC0 UI kits like `nox_ui`'s Kenney set + gallery/manifest before generating) via image-pipeline/ui-elements, and assign them to the placeholder `TextureRect` / `Button` paths in the emitted `.tscn`. Those texture slots are scaffolding — a screen still showing bare `ColorRect`/untextured placeholders is **not** shippable (`skills/parity-build/STANDARDS.md` → zero placeholder ColorRects); fill every slot with real art before it ships.

> **Style these screens — don't ship the default gray theme.** Generate a project `theme.tres` once with the [ui-theme](../ui-theme/SKILL.md) skill (from the same palette as `reference.png`) and set each emitted root Control's `theme` to `res://assets/ui/theme.tres`. A good layout in the default Godot theme still looks generic; the theme is what makes it look like *this game*.

## TL;DR

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py {title|menu|hud|inventory|dialog|list} [opts]
```

Targets 1920×1080 by default. All scenes use anchor-based layout so they scale cleanly to other resolutions.

## Subcommands

### title — Main menu / title screen

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py title \
  --title "Crimson Cape" \
  --buttons "Start,Continue,Options,Credits,Quit" \
  --generate-backdrop --backdrop-prompt "fantasy castle at sunset, dramatic clouds" \
  --style 16bit-game --preset fantasy_rpg \
  --engine both \
  -o assets/ui/title/
```

Emits `title.tscn` with: backdrop `TextureRect`, centered title `Label` (font_size 72), and a `VBoxContainer` of `Button`s stacked center. Without `--generate-backdrop`, the backdrop is a dark `ColorRect` **placeholder — a title screen must NOT ship on it**; source real backdrop art reuse-first (`skills/asset-reuse` → library/gallery/restyle before generating) and swap it into the `TextureRect`.

### menu — Pause menu (dim overlay + panel)

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py menu \
  --title "Paused" --buttons "Resume,Options,Save,Quit to Title" \
  --engine godot \
  -o assets/ui/pause/
```

Emits `menu.tscn` with a translucent black overlay over the gameplay scene and a centered `PanelContainer` with the title + buttons. `process_mode = PROCESS_MODE_ALWAYS` so it works when the game is paused.

### hud — In-game HUD overlay

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py hud --engine both -o assets/ui/hud/
```

Emits `hud.tscn`: `HealthBar` (ProgressBar) top-left, `AmmoLabel` top-right, `MinimapFrame` (PanelContainer with TextureRect) below ammo, `ActionPrompt` (Label) bottom-center. `mouse_filter = MOUSE_FILTER_IGNORE` so clicks pass through to gameplay.

The scaffold is a starting point — a shipping HUD follows the patterns below.

#### HUD patterns (UI/UX) — make it read at a glance, in the heat of play

The HUD is the screen the player stares at for hours; it's parity-critical
(`skills/parity-build/STANDARDS.md`). Rules that separate a real HUD from four
labels in the corners:

- **Anchor to corners/edges, never center-fixed.** Resources top-left, secondary
  status/minimap top-right, action bar/hotbar bottom-center, prompts bottom-center
  or over the target. Anchor-based so it survives every resolution.
- **Respect the TV/title safe area.** Inset the whole HUD ~5% from the edges
  (`offset` on the root margins) so nothing clips on overscan/notches.
- **Clicks pass through.** Root `mouse_filter = MOUSE_FILTER_IGNORE`; only
  interactive widgets (hotbar slots) opt back into `STOP`.
- **Diegetic where it fits the genre.** Health-as-suit-glow / ammo-on-the-gun reads
  more immersive than bars for sci-fi/horror; bars+numbers for RPG/strategy. Pick
  per reference game, don't default to bars everywhere.
- **Redundant encoding (accessibility, non-negotiable).** Every bar carries a
  number and/or icon — never color alone (`skills/accessibility`). Low-health state
  adds shape/pulse (respecting reduced-motion), not just "turns red".
- **Contextual prompts show the CURRENT binding**, pulled from `input-handling`,
  never a hardcoded key; they appear near the interactable and fade when gone.
- **Damage/feedback belongs to game-feel.** Damage vignette, hit flashes, floating
  combat text, low-health pulse — gate all of it on the reduced-motion setting
  (`skills/game-feel` `Feel.enabled`).
- **Objective / quest tracker + notification toasts** anchor to a consistent edge
  and auto-dismiss; don't let them overlap the action bar.
- **Everything defers to `theme.tres` and `typography`** — HUD numbers use the body/
  mono face at consistent sizes in the `scalable_text` group so the UI-scale setting
  grows them (`skills/ui-theme`, `skills/typography`, `skills/accessibility`).
- **Show only what's actionable.** Fade non-essential elements during calm; surface
  them on change. A permanently-full HUD reads as clutter.

### inventory — Grid inventory + stats side panel

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py inventory --grid 6x4 -o assets/ui/inventory/
```

Emits `inventory.tscn`: dim overlay + centered panel with HBoxContainer (GridContainer of `Slot_NN` panels on the left, `Stats` VBoxContainer on the right). Each slot is a 64×64 `PanelContainer` with a child `TextureRect` for the item icon — assign textures from your generated item set.

`--grid` accepts `WxH` (e.g. `8x6` for 48 slots). Default is `6x4` (24 slots).

### dialog — NPC dialog box

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py dialog -o assets/ui/dialog/
```

Emits `dialog.tscn`: bottom 1/3 PanelContainer with portrait (TextureRect) + speaker-name Label + RichTextLabel (BBCode-enabled) for the body + advance hint. Position your `DialogBox` instance on top of gameplay UI.

### list — Enumerate screens

```bash
python3 .claude/skills/ui-screens/tools/screen_gen.py list
```

## Cross-engine

All screen subcommands accept `--engine godot|unity|both|none`:

- **godot** — emits the `.tscn` scaffold ready to instance via `PackedScene.instantiate()`
- **unity** — emits a `.unity.json` describing the Canvas hierarchy (RawImage / Image / TMP_Text / Button / etc.) — recreate via Unity UI Builder or UI Toolkit. Full `.prefab` YAML auto-gen is too Unity-version-fragile and is intentionally out of scope.
- **both** — emit both
- **none** — emit nothing (useful when you only want the backdrop PNG from `title --generate-backdrop`)

## Pipeline — full UI pass

```bash
# 1. Generate UI element textures separately via image-pipeline
python3 .claude/skills/image-pipeline/tools/asset_gen.py image \
  --type icon --prompt "sword icon, top-down" --style 16bit-game \
  --preset fantasy_rpg -o assets/icons/sword.png

# 2. Generate all five screens with consistent aesthetic
for screen in title menu hud inventory dialog; do
  python3 .claude/skills/ui-screens/tools/screen_gen.py $screen \
    -o assets/ui/$screen/
done

# 3. Open Godot, instance the scenes, drag the icon textures into placeholders.
```

## What NOT to do

- Don't try to auto-generate Unity `.prefab` YAML — write the layout JSON and let the user/editor reconstruct in UI Builder. Unity's YAML format depends on the version, the render pipeline, the TMP version, etc.
- Don't put a backdrop PNG inside the inventory/HUD scenes — those are translucent overlays on top of gameplay; the backdrop is the game world
- Don't use the title backdrop for the pause menu — pause menus dim the existing scene with a `ColorRect`, they don't have their own backdrop

## Verification

JSON output includes paths for every emitted scene + sidecar. Open the `.tscn` in Godot's scene tab to verify the tree before instancing. Anchor-based layout means resizing the editor viewport correctly previews other resolutions.
