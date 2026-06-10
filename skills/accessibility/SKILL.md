# Accessibility

A discipline skill (no tools — rules that constrain how the game is built). Games
default to *inaccessible*: tiny text, color-only signals, mandatory fast inputs,
flashing effects, no captions. This is the checklist that prevents shipping those,
applied **during** scaffolding, not bolted on after.

> **The bar:** a colorblind player, a low-vision player, a one-handed player, and
> a player sensitive to motion/flashing can all *start and play* the game. None of
> these is a niche — together they're a large share of any audience.

## The non-negotiables (build these in from the start)

### Vision
- **Never encode meaning in color alone.** A red enemy + a green pickup must also
  differ in *shape/icon/label*. (Pairs with `ui-theme` — pick a colorblind-safe
  palette; verify with a deuteranopia/protanopia check.)
- **Scalable text.** No hard-coded `font_size` that can't grow. Offer a UI-scale
  setting (the `ui-theme` font sizes + a `Control` scale) of at least 1.0–1.5×.
  Minimum body text ~ the equivalent of 18–24px at 1080p.
- **High-contrast text** over backgrounds (aim WCAG AA ~4.5:1). Add a text
  outline/shadow or a panel behind text on busy scenes — never raw text on art.

### Motion / photosensitivity
- **Reduced-motion setting** that dampens or disables: screen-shake (`game-feel`
  `Feel.enabled = false` or a shake-scale of 0), parallax, big camera moves,
  full-screen flashes. **Gate `Feel.shake()`/`flash()` on it.**
- **No rapid full-screen flashing** (seizure safety — keep below ~3 flashes/sec,
  avoid large-area red flashes). Auto-fail any "flash the whole screen" effect.

### Input
- **Fully remappable controls** (use the `input-handling` skill's rebinding UI).
  Never assume a specific key.
- **No mandatory rapid mashing / precise timing as the only path.** Offer a
  hold-instead-of-mash or toggle-instead-of-hold option; consider an
  assist/slow-mode for timing-gated content.
- **Controller AND keyboard** both work for every action.

### Audio / language
- **Captions/subtitles for all spoken or critical audio**, on by default for
  story content, with a readable caption style (the `ui-theme` panel + text).
- **Don't rely on sound alone** for a critical cue — pair it with a visual.
- **Externalize all UI/dialogue strings** for localization (see the recommended
  `localization` skill — keep strings out of code from day one).

## Per-screen / per-system hooks

- **Settings menu** (the `ui-screens` `menu`) must expose: UI scale, reduced
  motion, master/music/sfx volume, subtitles on/off, control remap, and (if used)
  colorblind mode. Persist via the `save-system` skill.
- **HUD** (`ui-screens` `hud`): health/ammo must read without color (shape +
  number), respect the UI-scale setting.
- **Tutorials/prompts**: show the *current* control binding, not a hard-coded key.

## Verify-before-ship checklist

- [ ] Grayscale screenshot: is every gameplay signal still distinguishable?
- [ ] UI at 1.5× scale: does anything clip or overlap? (anchors fix most of this)
- [ ] Reduced-motion ON: shake/flash/parallax actually dampen?
- [ ] Play one level keyboard-only, then controller-only.
- [ ] Captions present + readable for any voiced/critical audio.
- [ ] No effect flashes the screen > 3×/sec.

## Why a discipline skill (no tool)

Like `style-anchor` and `world-layout`, the value is the *constraint at authoring
time* — the agent designs accessible scaffolds (scalable UI, remappable input,
reduced-motion-aware feel) rather than generating an inaccessible game and
retrofitting. The other skills supply the mechanisms (`ui-theme` palette/scale,
`input-handling` remap, `game-feel` `enabled` gate, `save-system` settings
persistence); this skill makes sure they're used.
