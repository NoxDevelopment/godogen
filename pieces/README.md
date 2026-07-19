# Pieces & Templates Library

**Two layers.** A Kenney starter kit / SDK / framework is a **piece** (a building block),
NOT a finished game. Games are **composed** from pieces + real assets + genre logic + look/feel,
and live in `../templates/genres/` (screenshot-verified as real games).

- **`CATALOG.md`** — the full, license-verified catalog (full-game templates + pieces by category),
  sourced from GitHub `godot-template` topic/search, the Godot Asset Library Templates category,
  and official `godot-demo-projects`. Clone URLs included; fetch a piece on demand into its category folder.
- Category folders (`controllers/ multiplayer/ combat/ inventory/ dialogue/ ui/ cards/ systems/ fps-sdk/ asset-kits/`)
  hold pieces once adopted for a build. They're git-ignored (fetched on demand) so the repo stays lean.

**Workflow to build a game:** pick a full-game template as the base *or* compose pieces
(controller + combat + inventory + UI + save + audio) → wire genre logic → drop in real CC0 assets
→ screenshot-verify → register in `../templates/registry.json`.
