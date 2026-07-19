---
name: typography
description: Make in-game text LOOK like the world — typeface selection, pairing, and styling so prose/headings/HUD read as illuminated-manuscript script (fantasy gamebooks), terminal glow (cyberpunk), pulp caps (noir), etc. Covers font sourcing (reuse-first), display/body pairing, drop-caps & illuminated initials, BBCode/RichTextLabel styling, readability + accessibility. Use whenever text appears on screen and default/plain type would break the aesthetic.
---

# Typography — text is art, not a debug label

Plain default Godot font on a fantasy page (or anywhere) is a parity failure. Text carries as much of the look as the illustration — style it to the world.

## Reuse-first fonts (never ship the engine default)
Source from our OFL/CC0 font packs before anything else — the categorized library has ~10 font packs (`pieces/asset-kits/_library/by-theme/`/`by-style/font`, e.g. `Cinzel`, `MedievalSharp`, `UncialAntiqua`, `ark_pixel_ofl`, `pixel_operator_cc0`). Match the game's theme; record the license (OFL/CC0) for the credits screen. Generate/commission a face only if nothing fits.

## The core move: pair a DISPLAY face with a BODY face
- **Display** (titles, section headings, drop-caps, menu labels) — characterful, on-theme (blackletter/uncial/engraved for fantasy; wide mono/glitch for sci-fi; condensed serif for noir).
- **Body** (prose, HUD values, tooltips) — the *readable* one; still on-theme but never at the cost of legibility.
Never set everything in the display face — it becomes unreadable. Contrast display vs body is what reads as "designed."

## Per-genre type systems (presets)
- **Fantasy gamebook / illuminated:** uncial/engraved display (Cinzel/UncialAntiqua) + a warm readable serif body on parchment ink; **drop-cap** first letter of each section (2–3 lines tall, display face, accent color, optional ornamented/illuminated initial via a small image), generous line-height, slight ink-brown color (not pure black), subtle emboss/shadow for "pressed into the page."
- **Cyberpunk/terminal:** mono/wide face, scanline/glow (shader-craft), uppercase HUD, tracking.
- **Noir/pulp:** condensed serif caps, high contrast, film-grain.
- **Retro/pixel:** a true pixel font at an integer scale (never a downscaled TTF — snap to the grid; see `pixel-perfect`).

## Techniques (Godot)
- Style prose with **RichTextLabel + BBCode** (`bbcode_enabled`, `fit_content`, autowrap); custom fonts via a theme (`normal_font`/`bold_font`/`mono_font` + sizes) or `add_theme_font_override`.
- **Drop-cap:** wrap the first letter in a larger display-font span (`[font_size=...][color=...]X[/color][/font_size]`) or a `[img]` illuminated initial; indent the following lines.
- Depth: `outline_size`/`outline_color` for legibility over art; a 1px offset shadow for "ink"; letter-spacing/line-spacing theme constants for rhythm.
- HUD/labels: the body/mono face, consistent sizes, `scalable_text` group for accessibility scaling.

## Readability + accessibility (non-negotiable)
Cool ≠ unreadable. Keep body legible; offer the accessibility toggles (dyslexia-friendly font, high contrast, larger size, reduced text FX) from `accessibility`. The style is the default, not the only option.

## Verify by eye
Screenshot the actual text on the actual background at real size — display/body pairing, drop-cap, contrast over art. If it reads like a plain label, it's not done. See `parity-build/STANDARDS.md`.
