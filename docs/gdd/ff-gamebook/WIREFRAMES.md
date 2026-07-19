# WIREFRAMES — `ff-gamebook`: screens, states & flow

> **Companion to:** [`GDD.md`](GDD.md) · Closes benchmark **gap #5** (screens described but never drawn — no wireframes, per-screen states, or flow map).
> **Owner:** UX/UI lead · **Status:** DRAFT for Jesus sign-off · **Design system:** bespoke parchment kit (`nox_ui`) · **Primary orientation:** portrait-native reading, landscape/desktop reflow for combat/map/sheet.
> **Grounds in:** GDD §6 (all 17 screens + §6.1 the NoxDev shell), INSPIRATION §3 (screen catalog + §3.0 screen map). Sample content uses the [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md) world *The Grey Tithe* (Harrowfell, the Grey Assessor, the Reckoner, codeword `RESTITUTION`) so mockups read as the real game, not lorem ipsum.

These are functional wireframes: **layout, hierarchy, and state**, not final art. Art direction (palette, plates, linework) lives in [`STYLE_GUIDE.md`](STYLE_GUIDE.md). Every box below is a region an artist skins and QA tests; a state the doc forgot is a state that ships broken.

---

## 1. UX principles (the rules that settle every UI argument)

1. **The page is sacred.** In the Reading View, prose and its illustration plate own the screen. Chrome (HUD, quick-buttons) is compact, dimmable, and never overlaps body text. If a decision is "more chrome vs. more page," the page wins.
2. **Dramatize the dice, honestly.** Every roll is a *visible, tactile, honest* event — real pips, the modifier math shown (`2d6=7 +SKILL 9 = 16`), never silently fudged. Quick/auto modes speed it but never hide the result.
3. **One tap to the sheet, from anywhere.** SKILL/STAMINA/LUCK are always on screen during play; the Adventure Sheet, Inventory, and Map are reachable in a single tap from the Reading View, Combat, and Pause.
4. **Automate the bookkeeping.** The player never hand-edits stats in faithful mode; the sheet maintains itself. The UI's job is to *show* state changes clearly (a wound animates the STAMINA readout), not to make the player do arithmetic.
5. **Accessible by construction.** Every screen supports text scaling, TTS narration, high-contrast/dyslexia themes, reduced motion, and focus-order keyboard/gamepad navigation — specced per screen below, not bolted on.

---

## 2. Platforms, input & responsive rules

| Concern | Rule |
|---|---|
| **Primary shape** | Mobile **portrait** is canonical for Reading/Choice/Dice/Sheet. The reading column is designed at ~360–420 dp wide. |
| **Reflow** | Combat, Map, Adventure Sheet, and MP Lobby **reflow to landscape/desktop** (two-column). Portrait stacks the same regions vertically. Breakpoint ≈ 600 dp short-edge. |
| **Input — touch** | Tap primary; long-press = detail/tooltip; shake-to-roll (accelerometer) optional in Dice. |
| **Input — mouse+kb** | Full pointer + keyboard: number keys 1–9 select choices, `Space`/`Enter` = roll/continue, `S`/`I`/`M` = Sheet/Inventory/Map, `Esc` = Pause. Focus ring visible. |
| **Input — gamepad** | D-pad/stick moves focus through choices; `A` confirm, `B` back, bumpers = Sheet/Map, `Start` = Pause. |
| **Min touch target** | 48×48 dp; choice buttons full-width, ≥56 dp tall with ≥8 dp spacing (prevents mis-taps into a fatal branch). |
| **Safe areas** | Respect notch/home-indicator insets; HUD and bottom choice stack sit inside safe area. |
| **Orientation lock** | Reading View may lock portrait by setting; Combat/Map permit both. |

---

## 3. Screen inventory & flow map

All 17 GDD §6 screens, and how they connect. Grounded in INSPIRATION §3.0.

```
                                   ┌───────────────────┐
                                   │  TITLE / MAIN MENU │
                                   └─────────┬─────────┘
        ┌──────────┬──────────────┬──────────┼───────────┬──────────────┬───────────┐
        ▼          ▼              ▼          ▼           ▼              ▼           ▼
  [New Advent.] [Continue]  [Library/    [Options/    [Credits]   [MP: Host/Join] [Quit]
        │          │         Bookshelf]   Settings]                    │
        ▼          │              │                                    ▼
  ROLL-UP /        │              │                            MULTIPLAYER LOBBY
  CHAR CREATION    │              │                                    │
        │          │              ▼                                    │
        └────┬─────┴───────► BOOK-READING VIEW ◄───────────────────────┘
             │                (the heart)  ◄─────────────────────────────────────┐
             │                     │  opens overlays / transitions:               │
        ┌────┴───┬─────────┬───────┼──────────┬────────────┬───────────┐         │
        ▼        ▼         ▼       ▼          ▼            ▼           ▼         │
     DICE-    CHOICE/   COMBAT  ADVENTURE  INVENTORY /   MAP /      GALLERY      │
     ROLL     BRANCH    SCREEN   SHEET     EQUIP/POTIONS PROGRESS  (illustr.)    │
     OVERLAY  UI          │        │          │            │                     │
        │        │        │        └──────────┴────────────┴─────────────────────┘
        │        │        │                     │
        └────────┴────────┤              SAVE / LOAD / BOOKMARKS ──► (resume) ────┘
                          ▼
                 ┌────────┴────────┐
                 ▼                 ▼
            DEATH SCREEN     VICTORY SCREEN
                 │                 │
                 └──────► TITLE / restart / LIBRARY ◄──┘

  PAUSE  (overlay, reachable from any gameplay screen via Esc/Start) ──► Resume | Options | Save/Load | Quit-to-menu
```

| # | Screen | Reachable from | Purpose |
|---|---|---|---|
| 1 | Title / Main Menu | launch | Entry, Continue, MP entry |
| 2 | Library / Bookshelf | Title, Victory | Adventure select / gallery hub |
| 3 | Character Creation / Roll-Up | New Adventure | Roll SKILL/STAMINA/LUCK, pick Potion |
| 4 | **Book-Reading View** | Roll-Up, Continue, all overlays | The heart — prose + plate + choices |
| 5 | Choice / Branch UI | (part of Reading View) | Present branching options |
| 6 | Dice-Roll Overlay | Reading, Combat | Animated honest dice |
| 7 | Combat Screen | Reading (encounter) | Attack rounds, Luck-in-combat |
| 8 | Adventure Sheet | any gameplay | The self-maintaining character record |
| 9 | Inventory / Equipment / Potions | Reading, Sheet, Combat | Item use/equip |
| 10 | Map / Progress | any gameplay | Passage-graph auto-map (+ travel-map mode) |
| 11 | Save / Load / Bookmarks | Pause, Reading, Death | Slots, bookmarks, mode selector |
| 12 | Death Screen | STAMINA 0 / instant-death | End-of-run, restart/load |
| 13 | Victory Screen | winning section | Closing, unlocks |
| 14 | Settings / Options | Title, Pause | Reading/Audio/Combat/Dice/Access./Rules/Lang/Data |
| 15 | Gallery / Illustrations | Library, Pause | Unlocked plates |
| 16 | Multiplayer Lobby / Session | Title | Host/Join, roster, turn/vote |
| 17 | Pause | any gameplay | Resume/Options/Save/Quit (PROCESS_MODE_ALWAYS) |

---

## 4. Global HUD & shell

Present across gameplay (Reading, Combat, Map, Sheet, Inventory):

```
┌───────────────────────────────────────────────┐
│ ☰   §142   SKILL 9  STAMINA 18/24  LUCK 7   🔖 │   ← persistent HUD (top bar)
└───────────────────────────────────────────────┘
  ☰ = Pause/menu   §N = section indicator (hideable, faithful mode)
  🔖 = bookmark toggle   stats tap → Adventure Sheet
```
- **Always visible during play:** SKILL / STAMINA (current/initial) / LUCK; Pause (☰); bookmark.
- **Contextual quick-row** (Reading View bottom or HUD overflow): Sheet · Inventory · Map · Save.
- **Studio shell chrome** (per GDD §6.1): the Pause overlay, Save/Load, and Options are inherited from `nox_ui` and identical across templates.

---

## 5. Per-screen specs (load-bearing screens — full wireframes)

### 5.1 Title / Main Menu

```
┌─────────────────────────────────┐
│                                 │
│      [ full-bleed key art:      │
│        the Nox-goddess over     │
│        the drowned Harrowfell ] │
│                                 │
│        T H E   G R E Y          │
│            T I T H E             │
│      ~ a NoxDev gamebook ~      │
│                                 │
│   ┌───────────────────────┐     │
│   │    New Adventure      │     │
│   ├───────────────────────┤     │
│   │    Continue           │◄─── highlighted if a save exists
│   ├───────────────────────┤     │
│   │    Library            │     │
│   ├───────────────────────┤     │
│   │    Multiplayer  ▸      │─── Host / Join / Hotseat submenu
│   ├───────────────────────┤     │
│   │    Options            │     │
│   ├───────────────────────┤     │
│   │    Credits            │     │
│   ├───────────────────────┤     │
│   │    Quit               │     │
│   └───────────────────────┘     │
│  v0.x            🔊 ambient loop │
└─────────────────────────────────┘
```
- **Purpose:** entry point; resume; route to MP/library/options.
- **Elements:** key art background, styled title, 7 menu buttons, version string, audio indicator, language flag (optional).
- **States:**
  - *first-time* (no save): **Continue** hidden or disabled+greyed; New Adventure focused.
  - *returning* (save exists): **Continue** shown, focused; tooltip "Harrowfell · §142 · STAMINA 18/24".
  - *loading* (booting into Continue): buttons disabled, page-turn wipe, spinner over art.
  - *error* (save file corrupt): Continue shows ⚠ badge; tap → dialog "Save could not be read — Load another / New Adventure".
- **Interactions/transitions:** New → **Roll-Up (5.7)**; Continue → **Reading View (5.2)** at `GameState.sectionId`; Multiplayer → **MP Lobby (§6)**; Library → **Bookshelf (§6)**; Options → **Settings (§6)**; Credits → credits scroll; Quit → confirm.
- **Data shown:** last-save summary from `GameState {sectionId, sheets, turn}`.
- **Accessibility:** menu is a vertical focus list (kb/gamepad); TTS reads title + focused item; reduced-motion disables the art parallax; high-contrast swaps to solid panel behind buttons.
- **Audio:** ambient wind + distant bell loop; page-turn sting on selection; low bell on Quit-confirm.

---

### 5.2 Book-Reading View (the heart) — portrait

```
┌───────────────────────────────┐
│ ☰  §142   SK 9  ST 18/24  LK 7 🔖│  ← HUD
├───────────────────────────────┤
│                               │
│   ┌───────────────────────┐   │
│   │                       │   │
│   │   [ illustration      │   │
│   │     plate: the Grey   │   │  ← inline plate (tap = expand)
│   │     Assessor at the   │   │
│   │     toll-bridge ]     │   │
│   │                       │   │
│   └───────────────────────┘   │
│                               │
│  ┌─ drop-cap ──────────────┐  │
│  │ T he bridge into        │  │
│  │ Harrowfell is barred by │  │
│  │ a robed shape that      │  │  ← prose (serif, scroll)
│  │ casts no shadow. "We    │  │
│  │ find your account,"     │  │
│  │ it says, "wanting."     │  │
│  │ It extends an open      │  │
│  │ palm and waits.         │  │
│  └─────────────────────────┘  │
│                               │
│  ┌─────────────────────────┐  │
│  │ Pay the toll (5 Gold)   │  │  ← choice buttons
│  ├─────────────────────────┤  │    (target numbers hidden)
│  │ Offer an item           │  │
│  ├─────────────────────────┤  │
│  │ 🔒 Refuse — draw steel   │  │  ← always available (leads to combat)
│  └─────────────────────────┘  │
│  [ 🎲 Test Luck ] [ 🍖 Eat ]   │  ← inline action chips (contextual)
├───────────────────────────────┤
│  📜 Sheet  🎒 Inv  🗺 Map  💾 Save │  ← quick-row
└───────────────────────────────┘
```
- **Purpose:** read the numbered section, then choose — where ~80% of play happens.
- **Elements:** HUD; illustration plate (inline, tap-to-expand; absent on plateless sections); prose block (serif, drop-cap or section number, scrollable); choice list (full-width buttons, target numbers hidden in faithful mode); inline action chips (`Test Luck`, `Eat Provisions`, `Attack`) surfaced only when the section allows; quick-row.
- **States:**
  - *default:* plate + prose + 1–4 choices.
  - *forced continue:* single **"Turn the page ►"** button instead of a choice list.
  - *plateless:* plate region collapses; prose fills.
  - *loading* (fetching next section / AI-DM color): choices disabled, subtle page-turn shimmer, skeleton line for prose; if AI DM is generating flavor, a small "the DM considers…" caption with a **Skip to authored text** affordance (graceful fallback per GDD §9b).
  - *first-time:* one-time coach-marks point at the HUD ("your stats live here") and a choice ("tap to decide — some doors don't reopen").
  - *conditional-locked choice:* shown greyed with a reason chip (e.g., "Needs: Silver Key") or hidden entirely, per setting.
  - *revisited section:* previously-taken choices dimmed / marked "read".
  - *error* (missing target — should never ship; validator-caught): choice disabled with ⚠ and a debug toast in dev builds.
- **Interactions/transitions:** tap choice → page-turn/crossfade → next Reading View (or **Combat 5.4** / **Dice 5.3** / Death/Victory); plate tap → fullscreen plate; quick-row → **Sheet 5.5 / Inventory / Map 5.8 / Save**; HUD stats → **Sheet**; ☰ → **Pause**.
- **Data shown:** `Section {text, illustration, choices[]}`; HUD from active `AdventureSheet`; `§N` from `GameState.sectionId`.
- **Accessibility:** body text scalable 100–200%; dyslexia font toggle; TTS reads prose then enumerates choices ("Choice 1 of 3: Pay the toll"); focus order = prose → choices → action chips → quick-row; reduced motion swaps page-turn for instant cut; choice buttons carry semantic labels including any cost.
- **Audio:** page-turn on transition; soft pen-scratch when a stat changes on enter; ambient bed continues from Map/explore music.

---

### 5.3 Dice-Roll Overlay

```
┌───────────────────────────────┐
│░░░░░░░░ (page dimmed) ░░░░░░░░░│
│   ┌───────────────────────┐   │
│   │   TEST YOUR LUCK       │   │  ← context label
│   │                       │   │
│   │    ╔═══╗   ╔═══╗       │   │
│   │    ║ ⚄ ║   ║ ⚁ ║      │   │  ← 3D d6 tray (honest pips)
│   │    ╚═══╝   ╚═══╝       │   │
│   │                       │   │
│   │   2d6 = 7   ≤ LUCK 7   │   │  ← math shown explicitly
│   │                       │   │
│   │   ┌───────────────┐   │   │
│   │   │   LUCKY!      │   │   │  ← outcome banner
│   │   └───────────────┘   │   │
│   │   LUCK 7 → 6 (−1)      │   │  ← depletion shown
│   │                       │   │
│   │   [ Tap to continue ] │   │
│   └───────────────────────┘   │
└───────────────────────────────┘
```
- **Purpose:** resolve any roll (Test Luck/Skill/Stamina, Attack Strength) with an honest, dramatized result.
- **Elements:** context label; 1–2 animated d6; modifier + total line; success/fail banner; depletion line (for Luck); Tap-to-continue (hidden in Quick mode).
- **States:**
  - *ready:* "Tap to roll" / "Shake to roll".
  - *rolling:* dice tumble (respects animation-speed setting).
  - *result-lucky / result-unlucky / success / fail / wounded* — distinct banner + color + SFX.
  - *quick/auto:* overlay flashes result ~250 ms and auto-advances (no tap).
  - *reduced-motion:* dice snap to final pips instantly, no tumble.
- **Interactions/transitions:** tap/shake → roll → apply consequence → return to caller (Reading or Combat). In combat, chains into next round.
- **Data shown:** the roll, `AdventureSheet` stat being tested, resulting delta (via `apply_delta`); `GameState.rngSeed` drives the roll (replayable/verifiable).
- **Accessibility:** result announced by TTS ("Rolled 7, under Luck 7 — Lucky. Luck now 6"); high-contrast dice faces; never rely on color alone (banner text + icon).
- **Audio:** dice-shake + tumble + settle SFX; distinct "lucky" chime vs. "unlucky" thud; honest — no audio implies a result that didn't happen.

---

### 5.4 Combat Screen — landscape (portrait stacks the same regions)

```
┌──────────────────────────────────────────────────────────────┐
│ ☰  §144   COMBAT                          Quick Combat [ off ] │
├───────────────────────────────┬──────────────────────────────┤
│  ENEMY                         │   ROUND 3                     │
│  ┌─────────────┐  Grey Assessor│   You     2d6=8 +SK 9 = 17    │
│  │ [portrait]  │  SKILL   8    │   Enemy   2d6=6 +SK 8 = 14    │
│  │  robed      │  STAMINA      │   ► You wound the Assessor −2 │
│  │  toll-wraith│  ▓▓▓▓▓░░ 6/10 │   ────────────────────────    │
│  └─────────────┘               │   [ combat log, scrolls ↑ ]   │
│                                │   R2 tie — no damage          │
│  YOU                           │   R1 Assessor wounds you −2   │
│  SK 9   ST 16/24   LK 6        │                               │
├───────────────────────────────┴──────────────────────────────┤
│ [ Attack ] [ Test Luck ] [ Escape ] [ Use Item ] [ Eat ]      │
└──────────────────────────────────────────────────────────────┘
```
- **Purpose:** resolve an encounter round-by-round, incl. Luck-in-combat, escape, items.
- **Elements:** enemy panel(s) (name/portrait/SKILL/STAMINA bar) — stacks/rows for multi-enemy "gang"; player stat strip; round-resolution area (both Attack Strengths, totals, result line); scrolling combat log; action buttons; Quick Combat toggle.
- **States:**
  - *round-start:* Attack enabled, others contextual.
  - *resolving:* buttons disabled while **Dice 5.3** plays; result writes to log.
  - *luck-prompt:* after wounding/being wounded, a contextual **"Test your Luck to modify damage?"** yes/no.
  - *escape-offered / escape-unavailable:* Escape enabled only if the section offers it (else greyed with "This foe blocks escape").
  - *multi-enemy:* enemy row; a target selector on the player's attack; any enemy beating your roll can wound you.
  - *quick-combat:* rounds auto-run; log fills; stops on win/loss/escape or an item prompt.
  - *victory / defeat:* transition to next Section or **Death 5.9**.
  - *blessed-weapon gate* (Reckoner): if `blessedWeapon` false, Attack shows "Your blade passes through him" — no damage — nudging the player toward the true path.
- **Interactions/transitions:** Attack → Dice → apply 2 STAMINA to loser → luck-prompt → next round; Escape → −2 STAMINA → escape target section; Use Item/Eat → **Inventory** context (Eat disabled mid-round per rules); win → Reading; loss → Death.
- **Data shown:** `Encounter {enemies[{name,skill,stamina,portrait,modifiers}], escapeTarget, gangRules}`; player `AdventureSheet`; rolls from seeded RNG.
- **Accessibility:** log is a live region (TTS reads each round: "You 17, Assessor 14 — you wound it, Assessor Stamina 6"); STAMINA conveyed as number + bar (not color alone); Quick Combat is itself an accessibility aid; keyboard: `A` attack, `L` luck, `E` escape.
- **Audio:** weapon clash on hit, parry ring on tie, wound grunt, victory sting / death cue; music shifts to the combat bed on entry (see STYLE_GUIDE audio).

---

### 5.5 Adventure Sheet

```
┌───────────────────────────────┐
│ ☰   ADVENTURE SHEET        ✕  │
├───────────────────────────────┤
│  ── STATS ──                  │
│  SKILL      9  / 9   (init 9) │
│  STAMINA   16  / 24  (init 24)│
│  LUCK       6  / 7   (init 7) │
│  ── CONSUMABLES ──            │
│  Provisions  ▓▓▓▓▓▓░░  6/10   │
│  Gold        12 gp            │
│  Potion   Fortune  ●● (2)     │  ← tap-to-use
│  ── EQUIPMENT ──              │
│  • Sword (leather armour)     │
│  • Lantern                    │
│  • Silver Key                 │
│  ── CODEWORDS / NOTES ──      │
│  ◇ RESTITUTION   ◇ hasSeal    │
│  "The ledger cannot record a  │
│   debt forgiven."             │
│  ── ENCOUNTER LOG ──          │
│  Grey Assessor  SK8 ST10 ✗    │
└───────────────────────────────┘
```
- **Purpose:** the self-maintaining character record — a headline feature vs. paper.
- **Elements:** SKILL/STAMINA/LUCK (current/initial); Provisions (bar+count), Gold, Potion (type+doses); equipment list; codewords/notes; monster encounter boxes (history).
- **States:**
  - *read-only* (faithful default): no field editable.
  - *tap-to-use:* Potion/usable items highlighted; tap → confirm → `apply_delta`.
  - *empty inventory:* "Your pack is empty" placeholder.
  - *cap-hit feedback:* a restore that would exceed Initial shows "capped at Initial" micro-toast (teaches the invariant).
  - *debug/sandbox:* fields editable (dev only, never in shipped faithful mode).
- **Interactions/transitions:** ✕ / back → returns to caller; tap Potion → **Dice/effect** then back; opens over Reading/Combat as an overlay.
- **Data shown:** the full `AdventureSheet {skill,stamina,luck {init,cur}, provisions, gold, potion, equipment[], codewords, notes[]}`.
- **Accessibility:** TTS reads stat table row-wise; codewords listed as text (not just icons); scalable; the never-exceed-Initial invariant surfaced as text.
- **Audio:** parchment-unfurl on open; pen-scratch on any tap-to-use.

---

### 5.7 Character Creation / Roll-Up

```
┌───────────────────────────────┐
│      ROLL UP YOUR HERO        │
├───────────────────────────────┤
│  ╔═══╗                         │
│  ║ ⚅ ║  SKILL      = 1d6+6     │
│  ╚═══╝   →  9   ● average      │  ← color-coded quality
│                               │
│  ╔═══╗╔═══╗                    │
│  ║ ⚄ ║║ ⚄ ║ STAMINA = 2d6+12  │
│  ╚═══╝╚═══╝ → 24  ● strong     │
│                               │
│  ╔═══╗                         │
│  ║ ⚀ ║  LUCK       = 1d6+6     │
│  ╚═══╝   →  7   ● average      │
│  ────────────────────────────  │
│  STARTING KIT: sword, leather  │
│  armour, lantern, 10 Provisions│
│  ────────────────────────────  │
│  CHOOSE ONE POTION:            │
│  ┌────────┐┌────────┐┌────────┐│
│  │ Skill  ││Strength││Fortune ││  ← 3-card single-select
│  └────────┘└────────┘└────────┘│
│  [ Reroll ]        [ Begin ▸ ] │
└───────────────────────────────┘
```
- **Purpose:** roll SKILL 1d6+6 / STAMINA 2d6+12 / LUCK 1d6+6, pick a Potion, enter §1.
- **Elements:** three stat panels w/ dice + value + quality tag; starting-kit summary; 3-card Potion chooser; Roll/Reroll (setting-gated) + Begin.
- **States:**
  - *pre-roll:* values blank, Begin disabled.
  - *rolling:* dice tumble per stat (or all at once).
  - *rolled:* quality color (rough/average/strong) without being punitive; Begin enabled once a Potion is chosen.
  - *reroll-available / reroll-disabled:* Reroll hidden unless accessibility setting enables it.
  - *potion-unselected:* Begin disabled with hint "Choose a potion".
- **Interactions/transitions:** Roll → Dice; select Potion (single); Begin → writes `AdventureSheet`, seeds `GameState.rngSeed`, → **Reading View** §1.
- **Data shown:** initializes `AdventureSheet` (init=cur for all three stats).
- **Accessibility:** TTS narrates each roll and quality; Potion cards keyboard-selectable with tooltips read aloud; low roll never blocked (reroll aid).
- **Audio:** dice ritual SFX; a rising "hero theme" sting on Begin.

---

### 5.8 Map / Progress

```
┌───────────────────────────────┐
│ ☰   MAP            [Graph|Trav]│  ← mode toggle
├───────────────────────────────┤
│        (1)                    │
│         │                     │
│        (2)──(3)               │
│         │     ╲               │
│      ┌►(142)   (7)  ✝ (11)    │  ← ✝ = death seen here
│      │  ● YOU                 │
│      │   │                    │
│      │ (144 Assessor)         │
│      └── (visited, dimmed)    │
│                               │
│  Legend: ● you  ○ visited     │
│          ◇ branch  ✝ death    │
└───────────────────────────────┘
```
- **Purpose:** faithful passage-graph auto-map (default) + optional Sorcery!-style travel map.
- **Elements:** node graph (visited/current/branches), legend, mode toggle; travel-map mode shows a hand-drawn region with markers.
- **States:** *default* (nodes revealed as visited); *empty/first section* ("Your map is bare — explore to fill it"); *travel-mode* (only if the book enables map-as-movement); *loading* (large graph builds).
- **Interactions/transitions:** view-only in faithful mode (tap node → its blurb, not fast-travel); travel-mode tap → load destination section; back → caller.
- **Data shown:** visited set + current from `GameState`; branch edges from `Section.choices[].target`.
- **Accessibility:** graph has a text-list alternative ("Visited: §1, §2, §3, §142 (current)"); reduced motion disables pan inertia.
- **Audio:** quiet parchment/quill ambience; soft ping on node select.

---

### 5.9 Death Screen ("Your account is settled")

```
┌───────────────────────────────┐
│                               │
│   [ somber death plate:        │
│     grey ledger-script         │
│     closing over you ]         │
│                               │
│      YOUR ADVENTURE ENDS       │
│                               │
│  "The Grey Assessor marks your │
│   account paid. You are added  │
│   to the ledger."             │
│                               │
│  ── RUN STATS ──              │
│  Sections read      37        │
│  Foes defeated       4        │
│  Gold at death      12        │
│  Cause: STAMINA 0 (Assessor)  │
│                               │
│  [ Restart (new roll) ]       │
│  [ Load / Bookmark ]  (mode)  │
│  [ Return to menu ]           │
└───────────────────────────────┘
```
- **Purpose:** end-of-run — evocative, not a bare fail-state (FF deaths are content).
- **Elements:** death plate; headline; how-you-died flavor; run stats; Restart / Load-or-Bookmark (mode-gated) / Menu; deaths-gallery hook.
- **States:** *ironman* (Load hidden — Restart only); *bookmarks/checkpoint* (Load/Resume shown); *first death* (gentle tooltip about save modes in Options); *victory-adjacent bad ending* (e.g., THE HOLLOW VICTORY — different flavor + art).
- **Interactions/transitions:** Restart → **Roll-Up** (fresh character, §1); Load → **Save/Load**; Menu → **Title**.
- **Data shown:** run tallies from `GameState`; cause-of-death from the terminal `Section`.
- **Accessibility:** TTS reads flavor + stats + options; reduced motion stills the plate; not color-dependent.
- **Audio:** low mournful cue (bell + strings); no music loop — silence after the sting.

---

### 5.10 Victory Screen

```
┌───────────────────────────────┐
│                               │
│   [ triumphant plate:          │
│     dawn over Harrowfell,      │
│     the Tithe lifting ]        │
│                               │
│        Q U I T T A N C E       │
│                               │
│  "You named her truly and let  │
│   the debt go unpaid. The Grey │
│   Ledger cannot hold what is   │
│   forgiven. Harrowfell wakes." │
│                               │
│  ── FINAL RECKONING ──        │
│  Ending: QUITTANCE (true)     │
│  Survivors saved:  9          │
│  Score:  1,240                │
│  Unlocked: Gallery ×3, NG+    │
│                               │
│  [ New Adventure ] [ Library ] │
│  [ Share ]         [ Menu ]    │
└───────────────────────────────┘
```
- **Purpose:** payoff; record completion; unlocks.
- **Elements:** victory plate; ending title (varies: QUITTANCE / HOLLOW VICTORY / INHERITED DEBT); closing narrative; final score/stats; unlocks; New/Library/Share/Menu.
- **States:** *true ending* vs. *pyrrhic/dark endings* (distinct art, text, score); *first-completion* (unlock celebration); *replay* (shows prior best).
- **Interactions/transitions:** New → Roll-Up; Library → **Bookshelf**; Share → share card; Menu → Title.
- **Data shown:** ending id + `caelHolds`/survivor tally from `GameState`; score.
- **Accessibility:** TTS reads ending + reckoning; reduced motion; captions on any stinger.
- **Audio:** triumphant/bittersweet theme keyed to which ending fired.

---

## 6. Remaining screens (compact specs — completes all 17)

### 6.1 Library / Bookshelf
- **Purpose:** adventure/campaign select + gallery hub (also the single-book "start" surface).
- **Elements:** shelf/grid of covers/spines; on select → cover zoom w/ Read, illustration gallery, blurb, completion %.
- **States:** *empty* ("No adventures installed"), *locked* (store model — greyed spine), *in-progress* (bookmark ribbon + %), *completed* (seal + endings collected).
- **Exits:** Read → Roll-Up/Continue; Gallery → **Gallery**; back → Title.

### 6.2 Choice / Branch UI
- **Purpose:** present the branches (usually inside Reading View 5.2).
- **Elements:** stacked full-width buttons; conditional choices hidden or shown locked w/ reason chip.
- **States:** *default*, *conditional-met* (shown), *conditional-unmet* (hidden or greyed+reason), *single forced continue*, *revisited* (dimmed).
- **Exits:** each → target Section / overlay.

### 6.3 Inventory / Equipment / Potions
- **Purpose:** item detail + use/equip/read/drop.
- **Elements:** item grid (icon/name/qty), equipped slots, potion doses, detail panel; tags (usable/passive/quest).
- **States:** *empty*, *context-gated* (e.g., Eat disabled mid-combat-round), *quest-item* (drop disabled), *use-confirm*.
- **Exits:** Use → effect/Dice or Section jump; back → caller.

### 6.4 Save / Load / Bookmarks
- **Purpose:** slots, unlimited bookmarks, autosave, mode selector.
- **Elements:** slot rows (thumbnail/§N/timestamp/stat snapshot); bookmark list; mode selector (Ironman/Bookmarks/Rewind/Checkpoints); New/Delete.
- **States:** *empty slot*, *autosave-in-progress*, *ironman* (single overwrite slot, no pre-death reload), *load-confirm*, *corrupt-slot* (⚠).
- **Exits:** Load → Reading; back → Pause/caller.

### 6.5 Settings / Options
- **Purpose:** the full studio Options (GDD §6.1).
- **Elements:** grouped tabs — **Reading** (font/size/spacing/theme), **Audio** (music/SFX/ambience/dice buses), **Combat** (Quick Combat/auto-advance), **Dice** (shake-to-roll/anim speed/instant), **Accessibility** (dyslexia font/high-contrast/TTS/reduced-motion/reroll aid), **Rules/Mode** (save mode), **Language**, **Data** (cloud/reset).
- **States:** *default*, *live-preview* (font/theme preview on a sample passage), *unsaved-changes* (apply/revert), *restart-required* (badge on language).
- **Exits:** back → Title/Pause (applies live where possible).

### 6.6 Gallery / Illustrations
- **Purpose:** view unlocked interior plates.
- **Elements:** grid of unlocked plates (locked = silhouette); fullscreen viewer w/ caption/section ref.
- **States:** *empty* ("Explore to unlock plates"), *partial*, *complete*.
- **Exits:** back → Library/Pause.

### 6.7 Multiplayer Lobby / Session
- **Purpose:** Host/Join, roster, turn/vote, connection status (GDD §8).
- **Elements:** Host/Join tabs; party roster (per-player sheets or shared); turn/vote indicator; leader/arbitration mode; chat/emotes; connection/latency badges; ready checks.
- **States:** *hosting-waiting*, *joining/searching (LAN discovery)*, *connecting*, *connected/ready*, *player-disconnected* (rehydrate-on-rejoin banner), *host-migration/error*.
- **Exits:** Start → **Roll-Up** (per-player or shared) → Reading; back → Title.

### 6.8 Pause (overlay, PROCESS_MODE_ALWAYS)
- **Purpose:** interrupt from any gameplay screen.
- **Elements:** Resume / Options / Save-Load / Quit-to-menu; dimmed backdrop of current screen.
- **States:** *default*; *quit-confirm* ("Unsaved progress since §N will be lost — Save first?"); *MP* (Resume pauses only locally; shows "session continues" note).
- **Exits:** Resume → back to gameplay; Options → **Settings**; Quit → Title (confirm).

---

## 7. Open UX questions

1. **Section numbers on/off default** — faithful hides "turn to N"; do we default the `§N` HUD indicator on or off? (Playtest for metagaming vs. orientation.)
2. **AI-DM latency affordance** — is the "the DM considers…" caption + Skip acceptable, or should authored text always render instantly with AI color streamed in *after*? (Ties to GDD §9b fallback.)
3. **Travel-map mode scope** — ship the Sorcery!-style travel map in v1 or gate it as a COULD (GDD §13)? Affects Map screen build cost.
4. **Combat portrait reflow** — does the round-resolution area go above or below the action buttons on narrow portrait? Needs a device playtest.
5. **Bookmark vs. autosave visibility** — how prominent should the mode selector be on first run so players don't accidentally play Ironman? (Death Screen first-death tooltip may not be enough.)
6. **Multi-enemy target selector** — tap-to-target vs. auto-cycle for "gang" rounds on small screens.

---

## Cross-references
- Screens enumerated in [`GDD.md`](GDD.md) §6; shell in §6.1; data model (`AdventureSheet`/`Section`/`Encounter`/`GameState`) in §5.
- World/sample content: [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md), [`CONTENT_SAMPLE.md`](CONTENT_SAMPLE.md).
- Look & sound of these screens: [`STYLE_GUIDE.md`](STYLE_GUIDE.md). Numbers behind combat/economy panels: [`BALANCE.md`](BALANCE.md).
