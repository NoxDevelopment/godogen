# 3D Dice — Rebuild Spec

Rebuild spec for the ff-gamebook 3D dice so they read as **real dice thrown on a felt tray** — a
tactile, readable, well-lit d6 that settles and is read — not the current untextured flat cube with
a crude pip floating in an empty void.

- **Applies:** [`visual-judge/SKILL.md`](../../../skills/visual-judge/SKILL.md) — the bar is named below; acceptance rubric at the end.
- **Refactor, not rewrite.** Target files: [`scripts/screens/dice3d_tray.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/screens/dice3d_tray.gd) (`Dice3DTray`, the SubViewport tray) + [`scripts/dice_roll_popup.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/dice_roll_popup.gd) (the overlay that drives it).
- **The honest-dice contract already exists and MUST be preserved** (see §6) — this is a *look/feel* rebuild, not a mechanics change.
- FF uses **d6 only**: SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6, combat & Testing Luck 2d6.

---

## 1. The bar (what "good" means here)

Judge every pass side-by-side against these real references at the same scale:

### Physical d6 (the tactile target)
Real bone/ivory/resin dice: a **slightly warm off-white body** with visible material (bone grain / resin depth), **chamfered (beveled) edges** that catch a highlight, and **inset pips** — drilled concave dots (often ink-filled) that sit *below* the surface and catch a small shadow, making them readable from any angle. Casino-style dice have flush painted pips; classic RPG dice have engraved/inset pips. Either way the pip is a **3D feature that catches light**, not a flat decal.

### Digital dice done well — Dice So Nice! (Foundry VTT), Tabletop Simulator, dice-roller apps
The parity bar for in-app 3D dice. Dice So Nice! (verified on its docs) is the reference for **material + rendering depth**:
- **Materials:** plastic, metal, glass, wood, chrome, stone, velvet, resin, frosted, pristine, iridescent — each a real PBR-ish material, not a flat colour.
- **Per-face rendering** with a **label colour**, **outline colour**, **edge/bevel colour**, and **dice (body) colour** as separate controls — i.e. bevels and pip outlines are first-class.
- **Separate texture layer** on top of the material (grain, marble, etc.).
- **Full physics** (bounce, collide, settle) with sound.
- On a **felt/table surface with soft shadows and warm lighting**, dice **centred and large enough to read**, a clear settle-and-read beat.
Tabletop Simulator / good dice apps add: a **dice tray / bounded felt area**, **contact shadows** under each die, a **camera that frames the settled dice large**, and a readable **top-face** at rest.

**Current piece fails the bar because:** the die is a `BoxMesh` cube (sharp edges, flat `albedo` bone colour, `roughness 0.6`, no texture/normal/AO), pips are flattened spheres with no depth read, the "tray" is four flat-coloured boxes with no felt/wood texture and no contact shadow, there's no `WorldEnvironment` (no ambient/SSAO/tonemap), and the camera frames the dice small in an empty transparent void. It is placeholder-grade.

---

## 2. Die geometry + material

**Geometry — kill the sharp cube:**
- Replace the raw `BoxMesh` core with a **beveled/chamfered cube** so edges catch a highlight (the single biggest "these are real dice" upgrade). Options, in order of preference:
  1. **Rounded-box mesh** — a superellipsoid / rounded-corner cube built as an `ArrayMesh` (or a CSGBox3D rounded, baked to a mesh at build time), ~0.06–0.10 edge radius. Smooth normals on the bevels.
  2. Ship a **real d6 `.glb`** (bone/ivory) from the asset library and load it via AssetBinder by stable ID (`mesh/d6`), so Jesus can hot-swap dice models from the Studio. Keep a procedural fallback.
- Keep the physics collider a plain `BoxShape3D` (cheap, stable) — only the *visual* mesh is beveled.

**Material — a real bone/parchment PBR material** (replace the flat `StandardMaterial3D`):
- `albedo` = a bone/ivory texture (warm off-white `~#efe7d2` base) with subtle mottling; `albedo_color` tint stays for per-die theming.
- `roughness` ~0.45–0.6 driven by a **roughness map** (bone isn't uniform); `metallic` 0.
- **Normal map** — a faint bone-grain / micro-scratch normal so the body isn't glassy-flat and edges read.
- Slight **rim/subsurface warmth** — enable a touch of `subsurf_scatter` or a warm `backlight` so the bone glows faintly like real bone/ivory (STYLE_GUIDE: warmth is rare, meaningful — the sacred dice earn it).
- The enemy die (`ENEMY_BONE`) stays a greyer, cooler variant of the same material.

**Pips — readable, inset, light-catching** (replace the flattened `SphereMesh` dots):
- **Preferred: baked face-texture atlas.** UV-map the 6 faces to a single **texture atlas** where each face's pips are painted as **engraved dots with baked ambient occlusion + a tiny drop shadow**, plus a matching **normal map** so the pips catch the key light as real recesses. This is the highest-quality, cheapest-at-runtime path and how good digital dice do it. Pip layout must match `PIP_LAYOUT` / the 2D `FFDie` so 3D and 2D read identically (opposite faces sum to 7; the honest mapping in `FACE_DIRS` stays).
- **Alternative (procedural): drilled pits.** Keep geometry pips but make them **concave** (a small inset disc/hemisphere pressed *into* the face, darker `Bog-Ink` material with higher roughness), larger than current, with the normals oriented so each pit catches a shadow. Current pips are too small and too flat to read at tray scale.
- **Numerals option (themed dice):** support a face atlas variant that shows engraved **numerals** instead of pips (many players prefer numerals; Dice So Nice offers both) — selectable via the theme hook (§7).

---

## 3. The tray / table surface

Replace the four flat-colour boxes with a real felt tray:
- **Felt floor** — a `PlaneMesh`/box with a **felt texture** (dark green or oxblood to sit in the veritas palette; `TRAY_FELT` becomes a textured material) + a **fabric normal map** so it reads as cloth, not a flat rectangle. A subtle **vignette / darkening toward the rim** focuses the eye on the dice.
- **Tray walls / lip** — the low containing walls get a **wood-grain texture** (`TRAY_WOOD` → textured) with a slight bevel, so it reads as a wooden dice tray, not grey blocks. Pull the walls in slightly (see §5) so dice stay framed.
- **Contact shadows** — the single most important grounding cue. Ensure shadow-casting is on (key light `shadow_enabled` already true) and add **SSAO** via a `WorldEnvironment` (§4) so each die drops a soft contact shadow onto the felt. Without this, dice float. A cheap **blob shadow** (a soft dark decal under each die) is an acceptable perf fallback for low-end.
- Assets by stable ID through AssetBinder (`texture/dice_felt`, `texture/dice_tray_wood`, `normal/dice_felt`) so the tray is Studio-swappable.

---

## 4. Lighting + environment

Add a **`WorldEnvironment`** to the SubViewport's `World3D` (currently absent — that's why it looks flat and voidy):
- **Ambient light** from a warm colour (`ambient_light_source = COLOR`, low energy) so shaded faces don't crush to black — replaces the current hacky "ambient OmniLight."
- **SSAO** on (soft contact shadows / crease darkening between pips and under dice).
- **Tonemap** AgX or ACES + slight **glow** on highlights so the bone catches a gentle sheen. Keep **transparent background** (`transparent_bg` stays true) so the tray still composites over the 2D page — set the env background to not draw a sky (ambient-only).
- Keep the **three-light rig** but tune it: warm **key** `DirectionalLight3D` (`#ffd9a0`, shadow on) from upper-front; cooler **fill** to open the shadow side; low **ambient** from the env. The current warm key + Fen-grey fill is the right idea — the missing piece is the env (ambient + SSAO + tonemap).
- Warmth is meaningful (STYLE_GUIDE §2.2 "the sacred dice — the one moment nothing competes with"): the roll is lit like a lantern-lit table.

---

## 5. Camera framing

The dice must be **centred and large enough to read the top face instantly**:
- Tighten the tray (`half_x`/`half_z`) and/or move the camera closer so a settled die occupies a meaningful share of the viewport height — a single d6 should read comfortably; two dice (combat / STAMINA) both fit and both read.
- Keep the **3/4 top-down perspective** (`fov ~42`, positioned above/front, `look_at` the tray centre) — that's the readable angle. Ensure the settled dice land within the framed area (constrain throw start positions + wall insets so a die never settles half-out-of-frame or against a wall hiding its top face).
- The SubViewportContainer min size (currently `420×210`) should be generous enough that pips read at the overlay's display scale; verify at phone width.

---

## 6. Settle-and-read (honest dice — PRESERVE the contract)

**This already works correctly in `dice3d_tray.gd` and must be kept:**
- The **seeded rules core is authoritative** (`Adventure.test_luck` / `test_attribute` / `FFCombat.attack_round` from the ff-2d6 ruleset via `IFDice`) — it decides every face *before* the throw.
- The **physics is theatre only**: dice are thrown with random velocity/spin (`roll()`), tumble, and settle (`_await_settle`, bounded by `SETTLE_MAX`).
- On settle, each die is **snap-rotated** (`_snap_die`, `SNAP_TIME` tween) so the authoritative face points up (`FACE_DIRS`). **Physics never changes the result** — every peer sees the same faces regardless of the non-deterministic tumble. This is the honest-dice / seeded-RNG-authoritative approach (physics-as-performance) confirmed as the correct pattern for deterministic, replayable, MP-safe dice.
- The math is shown explicitly by the overlay (`dice_roll_popup.gd`: "2d6 = 7 +SKILL 9 = 16" / "≤ LUCK 7"), and reduced-motion snaps instantly.

**Polish the read moment (look/feel only):**
- On settle+snap, add a brief **hold + subtle highlight** on the winning top face (a soft glow pulse or a gentle camera ease-in) so the eye lands on the result — the "settle-and-read" beat. Duck music under the roll (already the intent per STYLE_GUIDE §2.2) and land a **bone-clatter → settle** SFX (`dice_shake` → `dice_land` already wired).
- Keep the snap fast enough to feel like the die *landed* that way, not obviously teleported (current `SNAP_TIME 0.18` is about right; make the settle→snap transition read as the die's final micro-tumble).

---

## 7. Customisable / themed dice hooks

Make dice Studio-themeable (Nox centralization pattern — swap once, updates everywhere):
- A small **`DiceTheme` resource** (or dictionary) selecting: body material/texture, pip-vs-numeral face atlas, body colour, pip/label colour, edge colour, felt + tray textures. Mirrors the Dice So Nice control set (dice/label/outline/edge colour + material + texture).
- Resolve theme assets via **AssetBinder stable IDs** (`mesh/d6`, `texture/dice_body`, `texture/dice_pips`, `texture/dice_felt`, `texture/dice_tray_wood`) so Jesus hot-swaps a whole dice look from the Studio with no code edits — same discipline as `FFUI` art binding.
- Per-die tint already flows through `roll(final_faces, tints)` (bone vs enemy-bone); extend so a theme, not just a colour, can be passed (you-vs-foe, or player-chosen dice skins).
- Ship one or two extra OFL/CC0 themes (e.g. a parchment/ivory set and a darker obsidian set) to prove the hook.

---

## 8. Multiplayer table-overlay direction

FF is "all-in MP" (per project memory). The dice must be MP-safe and eventually shared:
- **Already MP-safe:** because faces come from the seeded core, broadcasting the **seed + the resolved `final_faces`** (via `nox_netcode` — see [`addons/nox_netcode/net_events.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/addons/nox_netcode/net_events.gd)) lets every peer run its own physics theatre and still show identical results. Physics divergence between peers is cosmetic and irrelevant.
- **Direction — a shared dice table overlay:** in a session, a roll appears on a **shared table** for all players (whose roll it is, who's watching), each peer rendering the same authoritative faces. Combat already tints you-vs-foe; extend to N players' dice on one felt. Drive it from the netcode events so a roll broadcast by the active player animates on every client.
- Keep single-player identical — the overlay just doesn't broadcast.

---

## 9. Good vs current placeholder (side-by-side)

| Aspect | Current (placeholder) | Target (good) |
|---|---|---|
| Die shape | sharp `BoxMesh` cube | beveled/rounded d6, edges catch light |
| Body material | flat bone `albedo`, `roughness 0.6`, no maps | bone/ivory PBR: albedo+roughness+normal maps, faint subsurface warmth |
| Pips | small flattened spheres, no depth read | inset/engraved pips via baked atlas + normal (or deeper drilled pits); readable from any angle; numeral option |
| Surface | 4 flat-colour boxes | felt floor (fabric normal) + wood-grain tray lip, vignette |
| Grounding | none (dice float) | SSAO + shadow-cast contact shadows (or blob-shadow fallback) |
| Environment | no `WorldEnvironment` | env: warm ambient, SSAO, AgX tonemap, subtle glow |
| Lighting | key+fill+hacky ambient omni | key+fill + env ambient, tuned lantern warmth |
| Camera | dice small in a void | dice centred + large, top face reads instantly |
| Read moment | snap then done | settle → hold + winning-face highlight + clatter→land SFX |
| Theming | per-die colour tint only | full `DiceTheme` via AssetBinder stable IDs (Studio-swappable) |
| MP | honest & sync-ready (kept) | shared dice-table overlay via nox_netcode |

---

## 10. Section → code map (refactor targets)

| Concern | Current code (`dice3d_tray.gd`) | Change |
|---|---|---|
| Die mesh | `_make_die()` builds `BoxMesh` core | Beveled rounded-box `ArrayMesh` or AssetBinder `mesh/d6` glb; keep `BoxShape3D` collider. |
| Body material | inline flat `StandardMaterial3D` | Bone PBR material: albedo/roughness/normal maps + faint subsurf; theme-driven. |
| Pips | `SphereMesh` per pip, flattened via scale | Baked face-atlas (UV + normal) matching `PIP_LAYOUT`, or deeper drilled-pit geometry; numeral variant. |
| Tray | `_build_tray()`/`_static_box()` flat colours | Felt material (fabric normal) + wood-grain walls; pull walls in for framing. |
| Environment | none | Add `WorldEnvironment` (ambient + SSAO + tonemap + glow); keep `transparent_bg`. |
| Lighting | key/fill/ambient omni in `_ensure_built()` | Keep key+fill; move ambient to env; tune lantern warmth. |
| Camera | `cam.look_at_from_position(...)` | Tighten framing so dice read large + centred; verify at phone width. |
| Settle/snap (honest) | `roll()`, `_await_settle()`, `_snap_die()`, `FACE_DIRS` | **Preserve.** Add read-moment hold + winning-face highlight only. |
| Theming | `tints` param on `roll()` | Add `DiceTheme` via AssetBinder stable IDs. |
| MP | overlay-driven; faces from seeded core | Broadcast seed+faces via `nox_netcode`; shared dice-table overlay. |
| Overlay wiring | `dice_roll_popup.gd::_use_3d()`, `_tumble()` | Unchanged contract; route roll-up dice through the tray too (see ADVENTURE_SHEET_SPEC §5). |

---

## 11. Acceptance rubric (visual-judge, ≥3 samples)

Gather **≥3 samples** — (a) a single d6 (SKILL/LUCK roll), (b) two dice you-vs-you (2d6 Test/STAMINA), (c) combat two-tint (you-bone vs foe-grey) — at rest, `Read` the actual screenshots side-by-side vs a Dice So Nice / Tabletop Simulator dice-tray screenshot AND a photo of real bone d6 at the same scale. Score 0–3 (default lower when unsure):

| # | Dimension | 3 = clears the bar |
|---|---|---|
| 1 | Material believability | Reads as bone/ivory/resin (grain, roughness variation, faint warmth) — not a flat-shaded cube. |
| 2 | Pip readability | Top-face value is unmistakable at tray scale; pips read as inset light-catching features from any settled angle. |
| 3 | Edges/geometry | Beveled edges catch a highlight; the die looks manufactured, not a raw box. |
| 4 | Grounding | Each die drops a believable contact shadow on the felt; nothing floats. |
| 5 | Surface craft | Felt reads as cloth, tray as wood; the scene is a lit table, not a void. |
| 6 | Lighting | Warm, directional, with ambient fill + SSAO; highlights + soft shadows, no crushed blacks. |
| 7 | Framing + read moment | Dice centred + large; clear settle-and-read beat with the winning face emphasised. |
| 8 | Honesty preserved | Shown faces == authoritative seeded result across samples; MP peers would agree (physics is theatre). |
| 9 | Parity vs the bar | Beside Dice So Nice / TTS at the same scale, it holds up. |
| 10 | Robustness | Holds across 1-die, 2-die, and combat two-tint samples; no sample where a die settles unreadable or out of frame. |

Any dimension 0 → REJECT. All ≥2 and parity (#9) ≥2 across all samples → SHIP. Else ITERATE with ranked gaps.

**Sources:** [Dice So Nice! (Foundry VTT)](https://foundryvtt.com/packages/dice-so-nice) · [Dice So Nice! — Appearance guide](https://riccisi.gitlab.io/foundryvtt-dice-so-nice/guide/appearance/) · [seeded-dice-roller (deterministic dice)](https://github.com/lmagitem/seeded-dice-roller) · [Titannica FF Wiki — Game System (d6 mechanics)](https://fightingfantasy.fandom.com/wiki/Game_System).
