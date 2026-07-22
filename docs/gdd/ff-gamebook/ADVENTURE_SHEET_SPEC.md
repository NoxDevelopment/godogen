# Adventure Sheet — Rebuild Spec

Rebuild spec for the ff-gamebook Adventure Sheet so it reads as a **real, filled-in printed
pen-and-paper form** — a genuine Fighting Fantasy Adventure Sheet a player has rolled up and
written on — not a clean digital UI panel.

- **Applies:** [`visual-judge/SKILL.md`](../../../skills/visual-judge/SKILL.md) — the bar is named below and this doc ends with an acceptance rubric.
- **Refactor, not rewrite.** Target file: [`scripts/screens/adventure_sheet.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/screens/adventure_sheet.gd) (the VIEW) + [`scripts/screens/roll_up.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/screens/roll_up.gd) (the roll-your-own flow). Rules stay in [`scripts/rules/adventure_sheet.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/rules/adventure_sheet.gd) (`FFAdventureSheet`) — do NOT duplicate its invariant logic.
- **Shared toolkit:** all fonts/colours through [`scripts/screens/ff_ui.gd`](../../../templates/ready/narrative/ff-gamebook/skeleton/scripts/screens/ff_ui.gd) (`FFUI`), palette = STYLE_GUIDE §1.3 "veritas-gamebook".

---

## 1. The bar (what "real" means here)

Judge every pass side-by-side against these real references at the same scale:

### PRIMARY — the original Fighting Fantasy Adventure Sheet (the printed Puffin form)
The iconic single-page form bound into every FF gamebook (Warlock of Firetop Mountain onward). Its layout and rules, verified against the Titannica FF wiki and the FF rules summary:
- **Top-left stack of three score boxes:** `SKILL`, `STAMINA`, `LUCK`. Each is a **two-value box** — a large hand-written number that gets **crossed out and re-written** as it changes in play, sitting under (or beside) the **Initial** value that never changes. This "Initial vs current, current is scratched out repeatedly" is the single most recognisable tell of a real FF sheet.
- **Equipment List** — a ruled panel, a plain vertical list of lines the player hand-writes gear onto (sword, leather armour, lantern, …).
- **Gold** and **Jewels/Treasure** — small boxed tallies.
- **Provisions** — a small box (starts at 10; each restores STAMINA).
- **Potions** — the one chosen elixir (Skill / Strength / Fortune) noted by hand.
- **Monster Encounter Boxes** — a **grid of ~18 blank boxes** down the right side, each pre-printed with `SKILL` and `STAMINA` mini-labels, left empty for the player to pencil in each foe's stats during a fight, then scratch STAMINA down as they wound it. This grid is *the* visual signature of the FF sheet — a real sheet is mostly this grid.
- **Look:** a plain, slightly rough monochrome **printed form** on white/off-white paper, filled in with **biro/pencil handwriting** at slight angles, numbers crossed out and re-written.

### SECONDARY — classic AD&D / OSR / D&D 5e character sheets
For what "a real character sheet reads like": **ruled fill-in fields and ability-score boxes** with tiny printed captions and big hand-filled values (TSR AD&D 1e/2e sheets, the WotC 5e sheet, OSR one-page sheets). The tell is the **contrast between small engraved printed labels and large loose handwriting**, ruled lines the writing sits *on*, and boxes the writing overflows slightly. Sources confirm the fillable-field + ability-box idiom (Roll20 AD&D sheet wiki, WotC 5e fillable PDF, Mystic Waffle AD&D sheets).

**Current piece fails the bar because:** values are set in the Uncial display face (`_inked()` → `FFUI.font_runic()`), which reads as *typeset*, not *handwritten*; the sheet is read-only (no fill-in, no editing, no roll-your-own writing onto it); and the encounter grid is decorative rather than the dominant, usable feature it is on a real sheet.

---

## 2. Printed-form visual language

Keep the good chrome that already exists in `adventure_sheet.gd` (`_Ground`, `_Boxed`, `_Ruled`, `_WriteLine`, `_TitleRule`, foxing, corner ornaments, double-ruled frame). Push it further:

1. **Aged paper ground** — `_Ground` already draws `PARCHMENT_2` + warm wash + foxing. Add a faint, low-alpha **paper-grain / fibre noise** (a tiled noise texture at ~0.05 alpha, or `FastNoiseLite` in `_draw`) so the page isn't a flat fill. Keep the double-ruled frame + corner filigree.
2. **Masthead** — the title banner (`ADVENTURE SHEET`) stays in the engraved display face (`font_display_tracked`), centred, over the `_TitleRule`. Add the hero's name line beneath the masthead (see §5) in the **handwriting** face — the first proof the sheet was filled in by a person.
3. **Form labels** — every printed caption (`SKILL`, `INITIAL`, `NOW`, `EQUIPMENT & JEWELS`, `PROVISIONS`, `GOLD`, `MONSTER`, …) stays in the **engraved display face, tracked, small-caps, in `FFUI.INK`/`FFUI.FEN`** (via `_field_header()` / existing captions). These are the *printed* layer — they must never move or look hand-drawn.
4. **Ruled fields** — reuse `_Ruled` (horizontal rule-lines + red left margin rule) for Equipment and Notes. The writing must sit *on the baseline of a rule*, not float in a padded box. Guarantee blank ruled lines below the content (already done via `min_lines`) so a half-filled form still reads as a form.
5. **Boxed scores** — the two-box stat block (`_stat_field`) stays, but re-labelled to the FF idiom: caption `INITIAL` (small, fixed) and `NOW` (large). See §3 for the crossed-out treatment.

**Two typographic layers, never mixed:**
| Layer | Face | Colour | Role |
|-------|------|--------|------|
| Printed form | `FFUI.font_display()` (Cinzel), tracked small-caps | `INK` / `FEN` | labels, captions, rules, masthead |
| Hand-entered | **handwriting face (new — see §4)** | ink-blue / graphite (new colours) | every value the player/engine "wrote": scores, name, equipment, gold, encounter stats |

The current code's mistake is that hand-entered values use `font_runic()` (Uncial) — an ornamental *typeset* face. Replace `_inked()`'s font with the handwriting face.

---

## 3. Hand-entered values (the core fix)

Everything that would be *written onto a paper sheet* must render in a handwriting face with per-glyph life:

- **Font:** the new handwriting face (§4), NOT Uncial.
- **Ink colour:** add two palette constants to `FFUI` — `INK_PEN := Color("2a3550")` (a dark biro blue) and `GRAPHITE := Color("2e2b26")` (pencil). Scores/name in pen-blue; encounter-box scratchings in graphite. This visually separates "the player's pen" from the printed black form.
- **Jitter (the life):** wrap hand-entered values in a small helper `_handwritten(text, size, color)` that returns a `Label` with:
  - `rotation` randomised ±1.5° (seeded per field so it's stable across re-renders — seed from a hash of the field key, not `randf()` each frame),
  - `font_size` varied ±1px,
  - a tiny random baseline offset (±2px via `position`/`pivot`),
  - optional very-slight per-field colour value jitter (±3%) so not every number is the identical blue.
- **The crossed-out score (FF signature):** when a `NOW` value differs from `INITIAL`, render the stat's history as a real player would: the previous value **struck through** (a thin `_draw` line through a faint ghost number) with the new value written beside/below it. Keep it to the last 1–2 values so it reads, not clutters. This is the detail that makes it unmistakably an FF sheet in play. Implement as a small `_ScratchNumber` control that draws: faint ghost + strike line + current handwritten value.

> **Do not** animate jitter every frame — bake it once per value change. Re-render (`_render()`) reseeds deterministically from field key + value so the same state always looks the same (MP-safe, screenshot-stable for visual-judge).

---

## 4. The handwriting font (asset gap — must be added)

**We do not currently ship a handwriting font.** Our font packs ([`pieces/asset-kits/fonts/`](../../../pieces/asset-kits/fonts/) and the template's `assets/reused/fonts/`) contain only display/serif/pixel faces (Cinzel, MedievalSharp, UncialAntiqua, Pirata One, …) — confirmed by directory audit. So the build must **add one OFL handwriting face**.

Candidates (all SIL Open Font License, free for shipped/commercial use — verified on Google Fonts):
- **Caveat** — sleek, legible, natural stroke transitions; balanced spacing. **Recommended default** — most readable at small sizes (encounter-box numbers), still clearly handwritten.
- **Shadows Into Light (Two)** — clean neat monoline, slightly slanted, "journal note" feel. Good alternative for a neater hero.
- **Reenie Beanie** — loose ballpoint/felt-tip, spontaneous doodle look; most characterful but thinnest — use only for larger annotations (name, notes), not the tiny stat cells.

**Action for the build:**
1. Add the chosen `.ttf` (recommend **Caveat**, plus Reenie Beanie for large annotations) to `templates/ready/narrative/ff-gamebook/skeleton/assets/reused/fonts/`, with a matching `.import`.
2. Register in `FFUI`: `const FONT_HAND := "res://assets/reused/fonts/Caveat.ttf"` and `static func font_hand() -> FontFile`.
3. Add the OFL credit to the template's asset manifest / credits (same place Cinzel/MedievalSharp are credited).
4. Repoint `adventure_sheet.gd::_inked()` (rename to `_handwritten()`) to `FFUI.font_hand()`.

---

## 5. "Roll your own character" flow (write onto the sheet)

The roll-up already exists in `roll_up.gd` (dramatised honest roll of the engine's authoritative sheet: SKILL 1d6+6 / STAMINA 2d6+12 / LUCK 1d6+6, roll-quality colour, starting-kit summary, 3-card Potion chooser). **Refactor it so the roll writes onto the sheet in handwriting**, and add the two missing beats:

**Flow (target):**
1. **Roll the scores with the dice.** Reuse the existing dramatised roll, but route it through the **3D dice tray** (see [`DICE_3D_SPEC.md`](DICE_3D_SPEC.md)) — SKILL as `1d6` (+6 printed as the form's bonus), STAMINA as `2d6` (+12), LUCK as `1d6` (+6). As each stat settles, the rolled number is **written by hand into the `INITIAL` box AND the `NOW` box** (an animated "pen writes the number" — fade+slight-scale of the handwritten label, optional stroke reveal). Values come from `Adventure.sheet` (the authoritative `FFAdventureSheet`) — **no dice are rolled in the UI**, matching the honest-dice rule.
2. **Re-roll** — keep the existing accessibility-gated `↻ Reroll` (`Adventure.new_adventure()` + re-reveal). Frame it as "tear off a fresh sheet."
3. **Name your hero** — NEW. A text field (styled as a `_WriteLine` the player writes on) captions "NAME" in the printed face; the typed name renders live in the handwriting face on the masthead line. Store on the sheet: add `hero_name` to `FFAdventureSheet` as a `state.vars["hero_name"]` string (mirrors how `gold` lives in `state.vars`) with `save_data`/`load_data` already covering it via the shared `IFState` payload.
4. **Choose starting kit** — extend the existing Potion chooser. FF's canonical kit is fixed (sword, leather armour, lantern, 10 provisions) + one chosen Potion; keep the 3-card Potion chooser as the "choose your kit" beat, and render the granted kit **hand-written into the Equipment list** on confirm (not as icon chips only). If we want a richer "roll your own," allow a small optional swap (e.g. pick a weapon flavour) — but keep it faithful: the chosen items must flow through `FFAdventureSheet.add_item()` so they land in the shared `IFState` inventory that the sheet reads back.
5. **Begin** — writes the chosen Potion onto the sheet (`Adventure.sheet.potion = …`) and enters §1 (existing `_on_begin`). On entry the sheet is now a filled-in form with the hero's name, hand-written scores, and hand-written kit.

**Faithfulness:** the roll-up must not invent numbers — it dramatises `FFAdventureSheet.roll_up()` / `Adventure.new_adventure()`, which already encode the ff-2d6 formulas and set each Initial = rolled value = the per-run cap.

---

## 6. Monster Encounter Boxes (make them the real grid + usable)

On a real sheet this is the dominant feature. Upgrade `_encounter_box()` / the grid:
- **More boxes, denser grid.** Real sheets carry ~18 boxes. Render a scrollable grid (2–3 columns) of pre-printed boxes, each with printed `MONSTER` name-line + `SKILL` / `STAMINA` mini-cells (already the shape in `_encounter_box`).
- **Fill-in + editing.** During combat the box is filled with the foe's SKILL/STAMINA in **graphite handwriting**; as the foe is wounded, STAMINA is **scratched down** (reuse the `_ScratchNumber` from §3). Auto-populate from the active `FFCombat` encounter when one is running; also allow the player to **tap a blank box to hand-enter** a foe (pencil affordance, see §7) for foes they're tracking manually.
- **Blank boxes stay blank and ruled** so the grid reads as a form waiting to be used.

---

## 7. Editing (tap-to-edit + pencil affordance)

The sheet becomes lightly editable (the paper metaphor: you can always write on your own sheet), while numeric invariants stay owned by the rules layer:

- **Editable by hand (free text):** hero name, Equipment notes lines, Codewords & Notes, and blank Monster Encounter boxes. Tapping the field shows a **pencil glyph** affordance (a small ✎ chip, reuse `FFUI.chip`), swaps the handwritten label for a `LineEdit`/`TextEdit` styled to sit on the rule, and writes back to the shared `IFState` (`notes`, inventory, `hero_name`).
- **Editable numbers → route through the rules, never the view.** Scores (SKILL/STAMINA/LUCK current), provisions, gold, potion doses must **only** change via `FFAdventureSheet.apply_delta()` / `drink_potion()` / `eat_provision()`. A "faithful mode" toggle (default ON) keeps scores read-only except through play (combat, tests, potions) — matching the current design note. In an optional "sandbox/GM mode" toggle, tapping a score opens a stepper that calls `apply_delta({stat: ±1})` so the **engine clamp still enforces never-exceed-Initial** — the view never writes raw numbers.
- **Pencil affordance** = the universal edit cue: a small graphite ✎ at the corner of any editable field; on tap it lifts into edit state with a subtle "paper lift" (tiny shadow + 1px raise).

---

## 8. FF-rules faithfulness (invariants — unchanged, just surfaced)

The rules already live in `FFAdventureSheet` and the shared `IFState` clamp; the sheet must honour and *show* them, not re-implement them:
- **Current ≤ Initial** for SKILL/STAMINA/LUCK (`IFState._clamp_attr` honouring `attribute_max`; the one exception is Potion of Fortune raising Initial LUCK). The sheet **shows** this: the `NOW` value can never render above `INITIAL`; the standing caption "Current may fall in play but may never rise above its Initial value" stays.
- **Death = STAMINA 0.** When `FFAdventureSheet.is_dead()`, stamp the sheet (a hand-scrawled diagonal, or the STAMINA box struck through) — a real, in-fiction tell.
- **Potion of Fortune** is the only thing that raises an Initial (LUCK +1) — when it fires, animate the `INITIAL` LUCK box being re-written (rare event, worth the beat).
- All mutations flow through `apply_delta()` (the single funnel) → shared `IFState` → back to the sheet with zero glue (the state is already unified). The view just re-renders on `Adventure.notify_sheet_changed()`.

---

## 9. Wireframe (target layout)

```
┌══════════════════════════════════════════════════════════════════════┐  ← _Ground: aged paper,
│  ┌────────────────────────────────────────────────────────────────┐  │    double-ruled frame,
│  │           A D V E N T U R E   S H E E T                    [✎][✕]│  │    corner filigree, foxing
│  │   name:  ⟨ Alden of the Verge ⟩   ← handwriting on a _WriteLine  │  │  (masthead + hero name)
│  │  ══════════════════════◆══════════════════════════════════════   │  │  ← _TitleRule
│  │                                                                  │  │
│  │  ┌─ SKILL ──────┐  ┌─ STAMINA ─────┐  ┌─ LUCK ───────┐          │  │  ← _stat_field ×3
│  │  │ INIT   NOW   │  │ INIT   NOW    │  │ INIT   NOW    │          │  │    printed caps caption,
│  │  │  9    ⟨9⟩    │  │ 22   ⟨1̶8̶ 14⟩ │  │  8    ⟨8⟩     │          │  │    handwritten values,
│  │  └──────────────┘  └───────────────┘  └──────────────┘          │  │    NOW struck+rewritten
│  │  "current may fall but never rise above Initial"                 │  │    (_ScratchNumber)
│  │                                                                  │  │
│  │  ┌ PROVISIONS ┐ ┌ GOLD ┐ ┌ POTION ─────────┐                    │  │  ← consumables row
│  │  │  ⟨×10⟩     │ │ ⟨12⟩ │ │ Fortune ●● (tap) │                    │  │    handwritten values
│  │  └────────────┘ └──────┘ └─────────────────┘                    │  │
│  │                                                                  │  │
│  │  ┌ EQUIPMENT & JEWELS ────────────┐  ┌ MONSTER ENCOUNTER BOXES ┐ │  │  ← two columns on wide;
│  │  │──⟨ sword ⟩──────────────────── │  │ ┌MONSTER──┐ ┌MONSTER──┐ │ │  │    stacks on phone.
│  │  │──⟨ leather armour ⟩─────────── │  │ │ ______  │ │ ______  │ │ │  │    Equipment = _Ruled
│  │  │──⟨ lantern ⟩────────────────── │  │ │ SK  ST  │ │ SK  ST  │ │ │  │    ledger (handwritten);
│  │  │──────────────────────────────  │  │ └─────────┘ └─────────┘ │ │  │    encounter grid is the
│  │  │──────────────────────────────  │  │ ┌MONSTER──┐ ┌MONSTER──┐ │ │  │    dominant feature (~18
│  │  └────────────────────────────────┘  │ │ ⟨Orc⟩   │ │ ______  │ │ │  │    boxes, scroll), graphite
│  │  ┌ CODEWORDS & NOTES ─────────────┐  │ │ SK⟨6⟩ST⟨5̶ 2⟩││ SK  ST │ │ │  │    fill, STAMINA scratched
│  │  │ ◇ codeword   ⟨note…⟩ [✎]        │  │ └─────────┘ └─────────┘ │ │  │    down as foe is wounded
│  │  └────────────────────────────────┘  │  …                      │ │  │
│  │                                       └──────────────────────── │ │  │
│  └────────────────────────────────────────────────────────────────┘  │
└══════════════════════════════════════════════════════════════════════┘
```

---

## 10. Section → code map (refactor targets)

| Sheet section | Current code (`adventure_sheet.gd`) | Change |
|---|---|---|
| Two-layer typography | `_inked()` uses `font_runic()` | Rename `_handwritten()`, point at new `FFUI.font_hand()`; add ±jitter (seeded). |
| Handwriting font | — (none shipped) | Add Caveat (+Reenie Beanie) OFL to `assets/reused/fonts/`; add `FFUI.FONT_HAND`/`font_hand()`; credit in manifest. |
| Ink colours | `INK`/`VERDIGRIS`/`FLAME` reused for values | Add `FFUI.INK_PEN`, `FFUI.GRAPHITE`; use pen-blue for scores/name, graphite for encounter scratchings. |
| SKILL/STAMINA/LUCK boxes | `_stat_field()`, `_value_cell()` | Re-caption `INITIAL`/`NOW`; add `_ScratchNumber` for crossed-out history; NOW never renders > INITIAL. |
| Provisions / Gold / Potion | `_provisions_field()`, `_gold_field()`, `_potion_field()` | Values → handwriting; keep Potion tap-to-drink → `drink_potion()`. |
| Equipment ledger | `_ruled_list()` on `_Ruled` | Values → handwriting on the rule baseline; add tap-to-edit note lines. |
| Codewords & Notes | `_titled_box("CODEWORDS & NOTES", …)` | Notes editable (pencil ✎ → LineEdit → `IFState.notes`). |
| Monster Encounter grid | `_encounter_box()`, 6-box `GridContainer` | Expand to ~18 boxes, scrollable; auto-fill from active `FFCombat`; graphite fill + scratch-down; tap-blank-to-edit. |
| Hero name | — (none) | New masthead `_WriteLine` + `state.vars["hero_name"]`. |
| Roll-your-own | `roll_up.gd` (dramatised roll, potion chooser) | Route roll through 3D tray; animate "pen writes" into INIT/NOW; add name field + write kit into Equipment. |
| Editing / faithful mode | read-only in faithful mode (design note) | Add pencil affordance for free-text fields; sandbox stepper routes numbers through `apply_delta()`. |
| Invariants | owned by `rules/adventure_sheet.gd` + `IFState` clamp | Unchanged — view only reads + re-renders on `notify_sheet_changed()`. |

---

## 11. Acceptance rubric (visual-judge, ≥3 states)

Gather **≥3 sheet states** — (a) fresh roll-up (all NOW = INIT), (b) mid-adventure (STAMINA/LUCK scratched down, foes in the grid, half the equipment used), (c) near-death / Potion-of-Fortune moment — `Read` the actual screenshots, side-by-side vs a scanned original FF Adventure Sheet at the same scale. Score 0–3 (default lower when unsure):

| # | Dimension | 3 = clears the bar |
|---|---|---|
| 1 | Two-layer typography | Printed labels (engraved caps) vs hand-entered values (handwriting) are unmistakably different layers; values never look typeset. |
| 2 | Handwritten life | Values sit on rules/in boxes with slight, believable jitter; scores are crossed-out-and-rewritten like a real in-play sheet; not a uniform digital grid. |
| 3 | Encounter grid | Dense, dominant, usable ~18-box grid that fills in and scratches down during combat — the FF signature. |
| 4 | Paper craft | Aged grain, foxing, double-ruled frame, red margin rule hold up at 100%; no flat-panel tells. |
| 5 | Roll-your-own | The roll writes onto the sheet by hand (name + scores + kit); dramatises the engine's honest roll; re-roll works. |
| 6 | Editing | Tap-to-edit free-text fields with pencil affordance; numbers only change via the rules (invariant visibly holds: NOW ≤ INIT). |
| 7 | Parity vs FF sheet | Beside a real scanned FF Adventure Sheet it reads as the same *kind of object* — a filled-in printed form — at the same scale. |
| 8 | Context fit | Works in the live overlay at phone + desktop zoom (one continuous page that scrolls on phone). |

Any dimension 0 → REJECT. All ≥2 and parity (#7) ≥2 across all three states → SHIP. Else ITERATE with ranked gaps.

**Sources:** [Titannica FF Wiki — Game System](https://fightingfantasy.fandom.com/wiki/Game_System) · [How to play Fighting Fantasy — Loarbaind](https://www.loarbaind.com/blog/how-to-play-fighting-fantasy-game-rules) · [Wizard's Tower — printable FF adventure sheets](https://wizards-tower.com/2016/08/printable-fighting-fantasy-bookmark-adventure-sheets/) · [Roll20 AD&D 1e sheet](https://wiki.roll20.net/ADnD_1st_Edition_Character_sheet) · [WWG D&D 5e fillable sheet](https://wastedwizardgames.com/dnd/character-sheets/5e/fillable/) · [Mystic Waffle AD&D sheets](https://blog.mysticwaffle.com/advanced-dungeons-and-dragons-character-sheets) · Fonts (OFL): [Caveat](https://fonts.google.com/specimen/Caveat), [Shadows Into Light](https://fonts.google.com/specimen/Shadows+Into+Light), [Reenie Beanie](https://fonts.google.com/specimen/Reenie+Beanie).
