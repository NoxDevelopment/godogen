# Fighting Fantasy — Inspiration Doc for the `ff-gamebook` Template

> **Purpose.** This document is the exhaustive inspiration/reference source for the NoxDev **`ff-gamebook`** Godot template (single-player + multiplayer). It captures the *feel*, the *rules*, the *screens*, and the *interaction design* of the Fighting Fantasy (FF) gamebook line by Steve Jackson & Ian Livingstone, plus the leading digital adaptations. The downstream GDD is built from this, so it errs on the side of completeness. Where a rule has canonical printed values, they are given exactly.

> **Scope note / IP.** Fighting Fantasy is a trademarked property (Steve Jackson, Ian Livingstone, and current rights holders). This template reproduces the *mechanics and UX patterns* of the branching-gamebook genre — the "2d6 + SKILL combat / Test your Luck / numbered paragraphs" family of systems — not FF's copyrighted text, artwork, monsters, or trademarks. Original NoxDev content (world, art via our pipeline, adventure text) fills the shell. Treat FF titles named below as *reference*, not assets to ship.

---

## 0. What Fighting Fantasy Is (one paragraph)

Fighting Fantasy is a series of illustrated single-player fantasy adventure gamebooks launched in 1982 with *The Warlock of Firetop Mountain*. The reader **is** the hero. Instead of reading front-to-back, you read a numbered **paragraph** (called a "reference" or "section"; a book has ~400 of them), and at the end you are offered **choices** — each choice tells you which numbered paragraph to "turn to". Interspersed are **dice-resolved events**: combat, luck tests, skill tests, and instant consequences. You track your character on a printed **Adventure Sheet**. The rhythm is *explore → take a risk → live with the consequence*, and the books are famously, deliberately lethal — many paths end in "Your adventure ends here." The genre it defines is our template.

---

## 1. CORE GAMEPLAY LOOP

### 1.1 The atomic loop (one "beat")

```
        ┌─────────────────────────────────────────────────────────┐
        │                                                         │
        ▼                                                         │
  READ passage  ──►  PRESENT choices / events  ──►  RESOLVE  ──►  TURN TO
  (numbered      │   • branching choices          • dice        new numbered
   section text  │   • combat encounter           • stat change  paragraph
   + optional    │   • Test your Luck             • item gain/   ───────────┘
   illustration) │   • Test your Skill              loss
                 │   • item/potion use            • death check
                 │   • forced event              
                 ▼
           (consequence is applied to the Adventure Sheet)
```

Every beat is: **read → decide/roll → consequence → jump**. There is no free movement or timeline; the numbered-paragraph graph *is* the world. Location, time, and state are all encoded by "which paragraph you are on" plus "what's on your Adventure Sheet."

### 1.2 The macro loop (a full playthrough)

1. **Set up the hero.** Roll SKILL, STAMINA, LUCK (see §2). Optionally choose Provisions, a starting weapon, and (in some books) one Potion. Record on Adventure Sheet.
2. **Enter at paragraph 1**, read the premise, and begin turning to sections.
3. **Explore & choose.** Most paragraphs end with 1–4 choices ("If you want to open the door, turn to 88; if you'd rather creep past, turn to 145"). Some are forced (single "turn to").
4. **Risk & resolve.** Encounters trigger combat, Luck tests, Skill tests, trap saves, riddles, and item checks. Stats rise and fall.
5. **Consequence.** Good outcomes give clues/items/shortcuts; bad ones cost STAMINA, LUCK, items, or send you down a worse branch.
6. **Terminal states:**
   - **Victory** — reach the winning paragraph (often only reachable if you collected the right items / knowledge along the way).
   - **Death / failure** — STAMINA hits 0, an **instant-death** paragraph, or a dead-end that strands you.
   - **Restart** — on death you begin again from paragraph 1 with a *freshly rolled* character (classic books give no checkpoints). Learning the map across attempts is part of the experience.

### 1.3 The three-beat rhythm (design DNA)

- **EXPLORE** — low-tension reading, atmosphere, world flavor, choice of direction.
- **RISK** — a gate that demands a roll or a gamble (fight it or flee? drink the potion? trust the stranger?).
- **CONSEQUENCE** — the dice/branch pays out; state changes; tension resets or spikes.

Faithful pacing alternates these. Too much explore = boring; too much risk = punishing. Good FF books cluster risk into memorable set-pieces (a boss, a trapped corridor, a river crossing) separated by exploration.

### 1.4 Difficulty / death philosophy

- **High lethality is a feature, not a bug.** Sudden "you are dead, start over" endings are canonical (*Deathtrap Dungeon*, *House of Hell*). The threat of death gives choices weight.
- **Knowledge is the meta-progression.** You "beat" a book by *learning* it across runs — which door, which item, which password.
- **True path.** Many books have a single winning route; wrong-but-survivable branches waste resources and make the finale unwinnable (e.g., you never got the magic weapon that can hurt the final boss).
- **Cheating pressure.** Printed books can't stop finger-in-the-page save-scumming; digital adaptations must *decide their stance* (see §5, §6) — ironman vs. bookmarks vs. checkpoints.

---

## 2. SYSTEMS & RULES (canonical values)

### 2.1 The Adventure Sheet (the character record)

The printed Adventure Sheet is a single page with labelled boxes. A faithful digital sheet mirrors these fields:

| Field | What it is | Notes |
|---|---|---|
| **SKILL** | Combat & general prowess | Has an **Initial** value and a **Current** value. Current can drop (wounds, curses) but *never exceeds Initial*. |
| **STAMINA** | Health / endurance | Initial + Current. Drops from wounds, hunger, poison; restored by Provisions/potions/rest. Death at **0**. Never exceeds Initial. |
| **LUCK** | Fortune / fate | Initial + Current. Consumed by "Testing your Luck." Never exceeds Initial (a few items grant temporary boosts). |
| **Provisions** | Rations/meals | Numeric count. Eating restores STAMINA (commonly **+4**), usually only allowed "when not in combat." Start with ~**10**. |
| **Gold** | Currency (Gold Pieces) | For merchants, bribes, tolls, gambling. |
| **Equipment / Backpack** | Items carried | Sword, lantern, rope, keys, quest items, clues. Free-text list on paper; structured inventory digitally. |
| **Potions** | One chosen luck/skill/stamina elixir (in many books) | See §2.5. |
| **Jewels/Treasure**, **Notes/Clues** | Misc | Codewords, map fragments, passwords, monster weaknesses. |
| **Monster Encounter Boxes** | Scratch space for combat | Rows to write each enemy's SKILL/STAMINA and track their current STAMINA during a fight. |

**Golden rule of the sheet:** *Current* stats may fall but can never rise above their *Initial* values (except explicit magical exceptions). This is the single most important invariant to enforce in code.

### 2.2 Rolling up the hero (character creation)

All rolls use standard six-sided dice (d6):

- **SKILL = 1d6 + 6** → range **7–12**.
- **STAMINA = 2d6 + 12** → range **14–24**.
- **LUCK = 1d6 + 6** → range **7–12**.

These rolled values are *both* the Initial and the starting Current. Players quickly learn that a low SKILL roll makes a book brutally hard — some digital versions let you re-roll or gently curve this. A faithful default: **roll once, commit** (with an optional "reroll" toggle in settings for accessibility).

**Starting kit (typical):** a sword, leather armour, a lantern, **10 Provisions**, and in many titles **one Potion** of the player's choice (Skill / Strength / Fortune). Some books add gold, a shield, or book-specific gear.

### 2.3 Combat (the core resolution system)

Combat is a series of **Attack Rounds** against one enemy at a time. Each enemy has its own **SKILL** and **STAMINA**.

**One Attack Round:**
1. **Your Attack Strength** = **2d6 + your current SKILL**.
2. **Enemy Attack Strength** = **2d6 + enemy SKILL**.
3. **Compare:**
   - Higher total **wounds** the loser: subtract **2 STAMINA** from the loser.
   - **Tie** = both blows parried, no damage. Round ends; roll again.
4. Repeat until one combatant's **STAMINA reaches 0** (that combatant is dead/defeated).

Key combat rules & options:

- **Weapons/armour** are mostly flavor in classic FF; special weapons may add to Attack Strength or be *required* to harm certain foes (e.g., only a blessed blade hurts a wraith).
- **Luck in combat (optional each time you wound or are wounded):** After you deal a wound you may **Test your Luck** to deal *extra* damage (**Lucky: enemy loses 2 more**, total 4; **Unlucky: enemy loses only 1**). After you *take* a wound you may Test your Luck to reduce it (**Lucky: you lose only 1**; **Unlucky: you lose 1 more**, total 3). Every such test still burns LUCK (§2.4) — a risk/reward gamble.
- **Escape.** Some encounters permit fleeing ("turn to X to escape"). Escaping usually costs an **automatic 2 STAMINA** (a parting blow, no return attack) and you forfeit any treasure — and only allowed where the text offers it.
- **Multiple enemies.** Rules vary by book: commonly you roll your Attack Strength once and compare against **each** enemy in turn; you can only *wound* the one you're actively targeting, but *any* enemy that beats your Attack Strength can wound you. Some books have you fight them one at a time. The engine must support "gang" rounds.
- **Special foes.** Creatures with rules like "reduce your SKILL by 1 while you fight it," "immune unless X," "regenerates STAMINA each round," "fear test before combat," etc. The engine needs per-enemy modifiers/hooks.

### 2.4 Testing Your Luck

Whenever the text says "Test your Luck":

1. Roll **2d6**.
2. **Roll ≤ current LUCK → you are Lucky.** **Roll > current LUCK → you are Unlucky.**
3. **Regardless of result, reduce current LUCK by 1.**

So LUCK is a *depleting resource*: the more you rely on it, the worse your odds become. Being Lucky/Unlucky routes you to different paragraphs or changes damage. Some items/events restore LUCK (never above Initial, save explicit exceptions). This "your luck runs out" tension is central to FF's feel and must be modeled faithfully (test decrements even on a failed test).

### 2.5 Testing Your Skill (and other attribute tests)

- **Test your Skill:** roll **2d6**; **≤ current SKILL = success**, **> = failure**. Used for feats of agility/combat prowess (leaping a chasm, dodging a dart). SKILL is *not* consumed by the test (unlike LUCK).
- **Test your Stamina** (rarer): same 2d6 ≤ current STAMINA mechanic for endurance feats.
- Some later/advanced books add attributes (e.g., FEAR in *House of Hell*, HONOUR, FAITH, MAGIC points) tested the same way. The engine should treat "named attribute + 2d6 ≤ current test" as generic.

### 2.6 Potions (starting elixir)

In many books the hero picks **one** potion at start, with (classically) **two doses**:
- **Potion of Skill** — restores SKILL to Initial.
- **Potion of Strength** — restores STAMINA to Initial.
- **Potion of Fortune** — restores LUCK to Initial **and raises Initial LUCK by 1** (the only common way to exceed the starting cap).

Potions can be quaffed at (almost) any time except mid-combat-round in some rulesets. Model as consumable with a fixed dose count and a "restore-to-initial (or initial+1)" effect.

### 2.7 Provisions, Gold, Equipment

- **Provisions:** eat when allowed (usually "not during combat") for **+4 STAMINA** (never above Initial). Finite; running out means no field healing.
- **Gold Pieces:** earned from loot/rewards, spent at merchants, on bribes, tolls, gambling minigames, and information. Some paths gate on having enough gold.
- **Equipment/quest items:** the "keys" of the puzzle-box. Winning often requires having picked up specific items *and* not wasted them. The engine needs a flag/codeword system so later paragraphs can check "does the player have the Silver Mirror?" and branch accordingly.

### 2.8 Codewords / flags / state

Beyond stats and items, FF (esp. later books and the *Sorcery!* epic) uses **codewords** and hidden flags: "If you have the word FANGSKULL, turn to 250." Digitally this is a **key-value state store** (booleans, counters, collected-codeword set) queried by paragraph logic. Essential for faithful branching and for long, multi-book campaigns.

### 2.9 Dice usage summary (everywhere)

| Purpose | Roll | Success/effect rule |
|---|---|---|
| Roll up SKILL | 1d6+6 | initial 7–12 |
| Roll up STAMINA | 2d6+12 | initial 14–24 |
| Roll up LUCK | 1d6+6 | initial 7–12 |
| Attack Strength | 2d6 + SKILL | higher total wounds loser for 2 STAMINA |
| Test your Luck | 2d6 | ≤ LUCK = Lucky; **−1 LUCK always** |
| Test your Skill | 2d6 | ≤ SKILL = success |
| Test your Stamina | 2d6 | ≤ STAMINA = success |
| Random encounters / tables | 1d6 or 2d6 | book-specific tables ("roll 1d6: 1–2 = goblin…") |
| Eat Provisions | (no roll) | +4 STAMINA |

Physical dice are core to the *tactile ritual*. Digital versions preserve this with animated 3D dice, shake-to-roll, and honest visible results (§5).

---

## 3. SCENES / SCREENS & UI/UX

This section enumerates **every** screen a faithful digital FF needs, with layout + interactions. Two reference lenses run throughout: **(A) the classic printed book presentation** and **(B) digital adaptations** (Tin Man Games *Fighting Fantasy Classics* / *Legends*, inkle *Sorcery!*). A screen table follows, then the reference-adaptation deep-dive.

### 3.0 Screen map (what talks to what)

```
                          ┌──────────────┐
                          │  TITLE /      │
                          │  MAIN MENU    │
                          └──────┬───────┘
        ┌────────────┬──────────┼───────────┬────────────┐
        ▼            ▼          ▼           ▼            ▼
   [New Game]   [Continue]  [Library/   [Settings]   [Credits]
        │            │        Bookshelf]     
        ▼            │            │
  CHARACTER      ┌───┴────────────┘
  CREATION       ▼
  (roll stats)   BOOK-READING VIEW  ◄──────────────────────┐
        │        (passage text + illustration + choices)   │
        └───────────►│                                      │
                     │ opens overlays / transitions:        │
        ┌────────────┼──────────────┬─────────────┬────────┤
        ▼            ▼              ▼             ▼         │
   DICE-ROLL    COMBAT SCREEN   ADVENTURE     INVENTORY /   │
   OVERLAY                       SHEET        EQUIP/POTIONS  │
        │            │              │             │         │
        └────────────┴──────┬───────┴─────────────┘         │
                            ▼                               │
                      MAP / PROGRESS ───────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
         SAVE / LOAD   DEATH SCREEN   VICTORY SCREEN
                            │             │
                            └──────► back to MAIN MENU / restart
```

### 3.1 Screen-by-screen catalog

#### (1) Title / Main Menu
- **Elements:** game/book logo, evocative cover art or animated background, version, menu buttons: **New Adventure**, **Continue** (if a save exists), **Library / Bookshelf** (multi-book product), **Settings**, **Credits/About**, **Quit**. Optional: "Achievements/Deaths gallery," language selector, multiplayer entry (**Host / Join / Hotseat**).
- **Layout:** portrait-friendly single column (mobile-first) or centered panel over full-bleed art (desktop). Buttons large, tappable.
- **Interactions:** tap/click to route. Continue jumps straight to the last paragraph. Subtle audio sting + page-turn/ambient loop.

#### (2) Library / Bookshelf (multi-book hub — Tin Man pattern)
- **Elements:** a **shelf/grid of book spines or covers** (owned and, in a store model, locked/unowned). Selecting a book zooms its cover, revealing: **Read/Play**, **gallery of illustrations**, **book-specific options**, blurb, difficulty, completion %/achievements.
- **Layout:** horizontally scrollable shelf (skeuomorphic wood shelf) or cover grid.
- **Interactions:** tap spine → zoom → open. Long-press for details. For NoxDev this is the "campaign/adventure select" screen even in a single-book build.

#### (3) Character Creation / Roll-Up
- **Elements:** three stat panels (SKILL, STAMINA, LUCK) each with animated dice and the resulting value; starting-kit summary; **Potion chooser** (Skill/Strength/Fortune) with tooltip; optional name/portrait; **Roll** and **Begin** buttons; optional **Reroll** (setting-gated).
- **Layout:** vertical list of the three stats with dice tray; potion picker as a 3-card row.
- **Interactions:** tap **Roll** → dice tumble → values populate (SKILL 1d6+6, etc.). Pick a potion (single-select). Confirm writes the Adventure Sheet and enters paragraph 1. Communicate the stakes of a low roll (color-coded good/average/rough) without being punitive.

#### (4) Book-Reading View (the heart)
- **Elements:**
  - **Passage text** — the numbered section prose, styled like a book page (serif body, generous line height, drop-cap or section number).
  - **Illustration plate** — the section's interior artwork (full-width plate above/inline, or tap-to-expand). Not every section has one; classic books used ~two dozen full-page plates plus smaller vignettes.
  - **Choice list** — the branching options rendered as tappable buttons/links at the bottom ("Open the door", "Creep past"), each mapped to a target paragraph. Forced single-continue = one "Turn the page ►" button.
  - **Persistent HUD/toolbar** — compact readout of SKILL / STAMINA / LUCK; quick buttons to **Adventure Sheet**, **Inventory**, **Map**, **Menu/Save**; a **bookmark** toggle. Optionally a small "section N" indicator.
- **Layout:** single scrolling column; text → illustration → choices, top-to-bottom. HUD pinned top or bottom. Mobile portrait is the canonical shape.
- **Interactions:** read (scroll), tap a choice → transition (page-turn/crossfade) to next section; embedded actions inline (e.g., a **[Test your Luck]** button, an **[Eat Provisions]** button, an **[Attack]** trigger) surface the right overlay. Adjustable text size, font, and theme (paper/parchment/dark). Choices already taken (on revisits) may be dimmed or shown as "read."

#### (5) Choice / Branch UI
- Usually **part of the reading view**, but worth specifying: options as a stacked list of full-width buttons; each shows its action text (never the target number in a faithful UI — hide "turn to 88" so players don't metagame, though a "classic mode" could show numbers). Conditional choices only appear if their requirement (item/codeword/gold/stat) is met, or appear greyed with a lock icon and reason.

#### (6) Dice-Roll Overlay
- **Elements:** a **dice tray** with 1–2 animated 3D d6, the modifier and total shown ("2d6 = 7, +SKILL 9 = **16**"), context label ("Your Attack Strength" / "Test your Luck"), and the outcome banner ("**LUCKY!**" / "You are wounded").
- **Layout:** modal overlay dimming the page, centered tray.
- **Interactions:** **tap to roll** or **shake device to roll** (accelerometer, per Tin Man). Result animates; **tap to continue** applies the consequence — unless **Quick/auto** mode is on, which resolves and advances without manual taps. Honesty matters: show the actual pips; never fudge silently (fudging, if offered as an accessibility aid, must be an explicit opt-in).

#### (7) Combat Screen
- **Elements:**
  - **Enemy panel(s)** — name, portrait/illustration, enemy **SKILL** and a **STAMINA bar/number** (one panel per foe; multi-enemy shows a row/stack).
  - **Player panel** — your SKILL, STAMINA, LUCK.
  - **Round resolution area** — your Attack Strength roll vs enemy's, with the two 2d6 rolls and totals; a log line ("You hit the Orc for 2 STAMINA").
  - **Action buttons** — **Attack (next round)**, **Test your Luck** (contextual: after landing/taking a hit, to modify damage), **Escape** (only when allowed), **Use Item/Potion**, **Eat Provisions** (if permitted).
  - **Combat log** — running text of each round.
- **Layout:** enemy(ies) top, player stats + log middle, action buttons bottom. Landscape works well on tablet/desktop; portrait stacks.
- **Interactions:** tap **Attack** → both Attack Strengths roll (dice overlay or inline) → damage applied → prompt optional Luck test → repeat until a STAMINA hits 0. **Quick Combat** toggle removes the per-round "tap to continue" and auto-rolls rounds (Tin Man feature). Clear win/lose transition (to next paragraph, or death screen).

#### (8) Adventure Sheet (character screen)
- **Elements:** faithful digital rendering of the printed sheet — **SKILL/STAMINA/LUCK** each showing Initial and Current; **Provisions**, **Gold**, **Potions** (with doses); **Equipment/backpack** list; **codewords/notes/clues**; optionally the **monster encounter boxes** history.
- **Layout:** a single "sheet" panel styled like parchment/ledger, scrollable. Sectioned: Stats / Consumables / Equipment / Notes.
- **Interactions:** mostly **read-only** (the game maintains it automatically — a headline feature vs. paper). Some items are **tap-to-use** here (drink potion, read a clue). Never allow arbitrary editing in faithful mode (that's cheating); a sandbox/debug mode may.

#### (9) Inventory / Equipment / Potions
- **Elements:** grid or list of items with icons, names, descriptions, quantities; equipped weapon/armour slot(s); potions with dose counters; usable vs. passive vs. quest tags.
- **Layout:** could be a tab within the Adventure Sheet, or its own screen. Grid of item cards; detail panel on select.
- **Interactions:** tap item → detail → **Use / Equip / Read / Drop** (as allowed by rules and current context — e.g., can't eat Provisions mid-combat-round). Contextual availability; quest items usually can't be dropped. Usage may trigger a paragraph jump or a stat change.

#### (10) Map / Progress View
- **Elements:** classic books had **no in-book map** (you drew your own on scratch paper), so this is a **digital-native convenience**: an **auto-map** of visited locations/sections, the current position, branches taken, and (optionally) unexplored exits. inkle's *Sorcery!* elevates this to a **hand-drawn 3D world map** you physically travel across, with day/night. Tin Man's *Legends*/*Classics* provide an **auto-mapping** overview of explored areas and previous playthroughs.
- **Layout:** either (a) a stylized node/paragraph graph, (b) a hand-drawn regional map with markers, or (c) a "you are here" panorama. Pan/zoom.
- **Interactions:** view-only in a faithful gamebook (you don't fast-travel arbitrarily); in a *Sorcery!*-style hybrid the map **is** the movement UI (tap a destination to travel, which loads the relevant passages). NoxDev should support both modes: **passage-graph auto-map** (default, faithful) and optional **travel-map** (Sorcery! hybrid).

#### (11) Save / Load / Bookmarks
- **Elements:** save slots with thumbnail/section number/timestamp/stat snapshot; **bookmarks** (Tin Man offers unlimited bookmarks to revisit hard sections); autosave indicator; "New game" and "Delete" actions; a **mode selector** (Ironman vs. Bookmarks vs. Checkpoint — see §5.2).
- **Layout:** list of slots; each row shows where/when.
- **Interactions:** save/load/delete; place/jump-to bookmark. The *policy* here is a design decision (faithful = one save that overwrites, or ironman with no reload before death), so expose it as a rule set, not just plumbing.

#### (12) Death Screen ("Your adventure ends here")
- **Elements:** an atmospheric death illustration/vignette, the flavor text of *how* you died, run stats (sections read, foes slain, gold, cause of death), and buttons: **Restart (new roll)**, **Load/Bookmark** (if allowed by mode), **Return to menu**. Optionally a "deaths gallery/collection" hook (collecting the many ways to die is a fan pastime).
- **Layout:** full-screen, somber; big headline, art, then options.
- **Interactions:** restart re-rolls the character and returns to paragraph 1; in bookmark/checkpoint modes, offer resume. Keep it evocative, not just a fail-state (FF deaths are content).

#### (13) Victory Screen
- **Elements:** triumphant art, closing narrative, final stats/score, unlocks (achievements, next book in a series, gallery), and buttons: **New Adventure**, **Library**, **Share**, **Menu**.
- **Layout:** full-screen celebratory.
- **Interactions:** proceed to sequel/next book, replay, or menu. Record completion on the bookshelf.

#### (14) Settings
- **Elements:** **Reading** (font family/size, line spacing, paper/parchment/sepia/dark theme), **Audio** (music, SFX, ambience, dice sounds), **Combat** (Quick Combat on/off, auto-advance), **Dice** (shake-to-roll, animation speed, physical-vs-instant), **Accessibility** (dyslexia-friendly font, high contrast, screen-reader/TTS narration, reduced motion, reroll-on-creation, difficulty aids), **Rules/Mode** (Ironman / Bookmarks / Checkpoints), **Language**, **Data** (cloud sync, reset). Multiplayer: session name, visibility.
- **Layout:** grouped scrollable list with sections and toggles/sliders.
- **Interactions:** live-apply where possible (font/theme preview on a sample passage).

#### (15) Gallery / Illustrations (nice-to-have, per Tin Man)
- View unlocked interior plates; a reward for exploration and a nod to the beloved FF art tradition.

#### (16) Multiplayer Lobby / Session (see §4)
- Host/Join, party roster, roll-up per player or shared party sheet, turn/vote indicator, chat/emotes, connection status.

### 3.2 Reference lens A — the CLASSIC printed book presentation

- **Physical object:** a mass-market paperback. **Front matter:** "How to Fight the Creatures of…" rules, "Adventure Sheet" to photocopy, an intro story, and often a "hint of dread" background.
- **Adventure Sheet:** a printed one-page form with boxed fields (SKILL/STAMINA/LUCK initial+current, Provisions, Gold, Equipment, Potion, and a grid of "Monster Encounter Boxes"). You fill it in **by pencil**, erasing as stats change — the tactile bookkeeping is part of the ritual (and its friction is exactly what digital fixes).
- **Body:** ~**400 numbered sections** printed *out of order* so you can't cheat by reading sequentially. Each section is a short prose block ending in choices ("turn to 250").
- **Illustrations:** a distinctive black-and-white interior art tradition — a set of **full-page plates** plus smaller in-text vignettes, by artists like Russ Nicholson, Iain McCaig, John Blanche. Cover art is a strong painted fantasy scene. Art *sells the horror/wonder* and marks key encounters.
- **Dice:** you supply two d6 (early US "grab-a-dice" editions even printed dice you'd flip to). The **roll is a physical act** at the table.
- **No map, no save:** you drew your own map on paper; "saving" meant a finger in the page (and everyone cheated a little). Death meant literally restarting.
- **Feel to preserve:** page-turn anticipation, the weight of a single die roll, the dread of a numbered jump, hand-kept records, and gorgeous plate art at big moments.

### 3.3 Reference lens B — DIGITAL adaptations

#### B1. Tin Man Games — *Fighting Fantasy Classics* (2018) & the older *Gamebook Adventures* engine
- **Shelf/library UX:** books shown as **covers/spines on a shelf**; tap to zoom → options + illustration gallery → open. A store model (buy individual books) runs on one shared engine.
- **Reading UX:** faithful **page presentation** — section prose with interior illustrations, choices as tappable links at the bottom; **adjustable text size**; **unlimited bookmarks** to revisit tough sections.
- **Automated Adventure Sheet:** stats, inventory, and knowledge tracked **for you** — no pencil. You can open it any time; enemy combat stats are viewable.
- **Dice & combat:** animated dice; **shake-the-device to reroll** (accelerometer); a **Quick Combat toggle** that strips the "Tap To Continue" prompts to auto-run battle rounds. Per-book options to speed combat, resize text, etc.
- **Auto-map:** tracks everywhere explored across current and previous playthroughs.
- **Takeaway for NoxDev:** *convenience without betrayal* — automate the bookkeeping, keep the dice honest and visible, let players tune speed (Quick Combat) and revisit (bookmarks). This is the closest "faithful but modernized" target.

#### B2. Nomad Games / Asmodee — *Fighting Fantasy Legends* (2017)
- A **reimagining**, not a straight port: three books (*Warlock of Firetop Mountain*, *Citadel of Chaos*, *City of Thieves*) fused into **one open world** you wander.
- **Overworld map:** you create a character and roam paths between locations (Port Blacksand, etc.) with **auto-mapping**.
- **Card-driven events:** each location has a **shuffled deck** of creatures/objects/events → different every run.
- **Dice combat, reinvented:** you get a pool of **attack dice**; roll them and matching **symbols** inflict damage; the loser is whoever hits 0 STAMINA. **Upgradeable dice** and **skill points** (invest in strength or luck) add RPG-lite meta-progression.
- **Takeaway for NoxDev:** shows the "roguelite gamebook" direction — persistent overworld, procedural encounter decks, and progression between runs. A good *optional* mode, but it drifts from strict faithfulness (reviews found the reinvented dice combat divisive/thin). Keep as an alt template, not the core.

#### B3. inkle — *Sorcery!* (Parts 1–4, 2013–2016; based on Steve Jackson's *Sorcery!* books)
- **Reading UX:** prose flows continuously; choices are woven into the text; a distinctive move is that your **past choices are summarized and editable** — you can *rewind* and try a different branch (inkle's "the story remembers, and you can revise it"), which humanely sidesteps FF's brutal reloading.
- **Movement/map UX:** a beautiful **hand-drawn, pannable/zoomable 3D world map** with **day/night**; you physically **plot your route** across the land, and reaching a place loads its narrative. Movement is spatial, not just "turn to."
- **Combat UX:** *replaces* dice combat with an **effort-slider duel** — each round you choose how much **power** to put behind a swing on a slider (0 = full defence up to a max set by your gear); if your value beats the foe's, they take damage equal to **your** attack power; attacking **drains your STAMINA** (your health *is* your resource, gambled each swing) and you **recover** some each round; defending (0) caps incoming damage to 1. Text **hints at the enemy's next move**, turning it into a bluff/read duel. Combat is **narrated in natural prose**, not stat lines.
- **Magic UX:** **spellcasting by spelling** — combine letter-runes to form spell names (early version: line up letters through die-cut "holes"; later version: a gorgeous **3D spell-casting globe** where you tap letters). Wrong spells fizzle and cost STAMINA; learning the spellbook is a game in itself.
- **Codewords/continuity:** heavy use of remembered state and cross-part imports, enabling a genuinely reactive 4-part epic.
- **Takeaway for NoxDev:** the **gold standard for immersion** — narrated combat, spatial map travel, editable history, and diegetic magic. But it *diverges* from canonical FF rules (no 2d6 Attack Strength, no Luck-test decrement). Treat *Sorcery!* as the "premium reimagined" reference for UX polish, and the Tin Man engine as the "rules-faithful" reference. NoxDev should let the template lean either way.

### 3.4 Cross-cutting UI/UX principles (synthesis)

1. **The page is sacred.** Typography, readability, and atmosphere of the reading view come first — it's where 80% of play happens.
2. **Automate bookkeeping, dramatize the dice.** Track the Adventure Sheet silently; make rolls a visible, tactile, honest moment.
3. **Respect the player's time with speed toggles** (Quick Combat, auto-advance, animation speed) without removing the option to savor.
4. **Convenience layers the paper never had:** auto-map, bookmarks, searchable inventory, "already read" dimming, cloud save.
5. **Decide your stance on death & reloading** and expose it as a *mode* (Ironman / Bookmarks / Rewind) — it defines the whole tone.
6. **Diegetic where possible** — dice trays, parchment sheets, spell globes, hand-drawn maps beat generic menus.
7. **Accessibility is not optional:** scalable dyslexia-friendly text, TTS narration, high contrast, reduced motion, reroll aids.

---

## 4. MULTIPLAYER

Classic FF is strictly **single-player** — a solo reader against the book. Multiplayer is a NoxDev value-add, so design options are laid out with tradeoffs. (Note the *Advanced Fighting Fantasy* tabletop RPG and *Warlock of Firetop Mountain* boardgame prove a GM/party FF *can* work — that's the design north star for co-op.)

### 4.1 Single-player baseline
One player, one Adventure Sheet, the loop of §1. Everything else builds on this. The SP path must remain first-class and fully playable offline.

### 4.2 LOCAL multiplayer options

**(a) Hotseat "pass-and-play" (one device, one book, shared hero).**
- All players share a single character/party and take turns making choices, reading aloud, and rolling. The device passes hand to hand.
- *Pros:* trivial to build (SP + a "whose turn" prompt), captures the campfire storytelling vibe, no networking. *Cons:* not simultaneous; downtime; awkward for hidden info.
- *Design:* a turn-rotation indicator; optional "reader" role vs "chooser" role; a big "Pass the device to Player N" screen between turns.

**(b) Hotseat competitive / voting party.**
- Each player has their **own** character/sheet playing the *same* book independently on the same device (racing/comparing), OR the group **votes** on each branch (majority/rotating tiebreak) while sharing one hero.
- *Pros:* social, quick to build on hotseat plumbing. *Cons:* independent-runs mode is really parallel SP; voting can feel design-by-committee.

**(c) Local co-op party over LAN (see 4.3 LAN) but co-located** — the "LAN party" case: everyone on the couch, own devices, shared session.

**(d) Shared-screen "GM + players"** — one big screen (TV) shows the passage/art; players use phones as controllers to vote/roll/manage their own sheet. Great living-room experience; more UI plumbing.

### 4.3 NET / online multiplayer & co-op options

**(a) Shared-party gamebook (co-op adventuring).**
- A **party of 2–6 heroes** progresses through one book together. Each player has their own Adventure Sheet (SKILL/STAMINA/LUCK/inventory); the group faces shared encounters.
- **Choice arbitration:** options — *rotating leader* (whoever's turn picks the branch), *vote*, or *host decides*. Combat can be *party combat* (each hero fights an assigned foe, or the party's combined rolls vs. a boss) — this needs house rules since FF combat is 1v1 by default. Loot/gold split rules needed.
- *Pros:* the most compelling MP fantasy (a dungeon crawl with friends). *Cons:* requires real multiplayer combat rules FF doesn't ship with; sync of shared narrative state; handling disconnects; pacing (everyone reads at different speeds).
- *Godot fit:* authoritative host holds the canonical game state (current section, all sheets, RNG seed); clients render and submit choices/rolls; host validates and broadcasts. High-level multiplayer (ENet/WebRTC) or a relay for NAT traversal.

**(b) Hotseat-over-network (turn-based, low bandwidth).**
- The simplest net mode: one shared hero, players take turns online (like play-by-post). State is tiny (section + sheet + codewords), so it syncs trivially and tolerates lag/async play.
- *Pros:* dead simple, robust, async-friendly (turn notifications). *Cons:* not real-time; downtime between turns.

**(c) AI Dungeon Master / narrator-adjudicator.**
- An **LLM-driven DM** (leveraging the NoxDev companion/ML stack) that **narrates** passages with dynamic flavor, **adjudicates** ambiguous player actions ("I try to bribe the guard"), improvises between canonical branches, and voices monsters. Can run for solo *or* co-op groups.
- **Two flavors:** (i) **DM as color/glue** over a fixed authored graph (safe, canonical, deterministic branches; LLM only enriches prose and handles free-text intents by mapping them to existing choices) — recommended default; (ii) **DM as generator** producing new sections on the fly (infinite adventure, high risk of incoherence/rule drift/hallucinated stats). 
- *Pros:* huge differentiator, solves "players want to do things the book didn't anticipate," great for co-op immersion, ties into NoxDev's AI investments. *Cons:* rules-enforcement must stay in code (the LLM must never silently change STAMINA — the engine owns the sheet and dice; the DM only *proposes*); latency, cost, safety, and consistency; needs guardrails so it can't break the win condition or fabricate items. **Keep the dice/stat engine authoritative; the AI narrates and routes, it does not adjudicate math.**

**(d) LAN party session.**
- Host advertises a session on the local network; friends join from phones/laptops; shared-party or shared-screen play with minimal latency and no internet dependency. A natural fit for Godot's LAN discovery.
- *Pros:* low latency, offline, great couch/event experience. *Cons:* discovery/firewall quirks; same shared-state design work as (a).

**(e) Asynchronous "shared journey / ghost" & competitive leaderboards.**
- Not co-op, but social: compare runs, share "how I died," inherit a friend's codewords, or race the same book for score/speed. Cheap to add, adds replay stickiness.

### 4.4 Multiplayer tradeoff summary

| Mode | Build cost | Latency needs | Faithful to FF? | Best for |
|---|---|---|---|---|
| SP | baseline | n/a | ✔ pure | the core |
| Hotseat pass-and-play | very low | none | ✔ (solo-shared) | couch/casual |
| Hotseat competitive/vote | low | none | ~ | parties |
| Net hotseat (turn-based) | low | tolerant | ~ | async friends |
| Shared-party co-op (net/LAN) | high | moderate | ✘ needs house rules | the "dream" mode |
| Shared-screen GM+phones | medium-high | low (local) | ~ | living room / events |
| AI DM (color-only) | medium | LLM latency | ✔ (engine authoritative) | immersion, solo+co-op |
| AI DM (generative) | high | LLM latency | ✘ risky | experimental |

**Recommendation for the template:** ship **SP + hotseat pass-and-play** as the guaranteed baseline; architect state as **authoritative host + tiny serializable game state (section id, per-player sheets, codeword set, RNG seed)** so **net hotseat** and **shared-party co-op / LAN** slot in cleanly; offer the **AI DM in "color + intent-routing" mode** as the flagship differentiator with the **rules engine kept strictly authoritative over dice and the Adventure Sheet.**

---

## 5. RISKS / GOTCHAS for a faithful, high-quality adaptation

### 5.1 Rules-fidelity traps
- **Stat caps.** *Current never exceeds Initial* (except explicit magical exceptions like Potion of Fortune). Easy to get wrong; enforce centrally.
- **Luck must decrement on every test**, pass or fail. Forgetting this removes the core "luck runs dry" tension.
- **Combat edge cases:** ties (no damage), the optional Luck-in-combat modifiers (2/4 and 1/3 damage swings), escape costing 2 STAMINA, and **multiple-enemy** resolution (rules vary book to book) — support per-encounter overrides.
- **Per-book rule variants.** FF isn't one ruleset: extra attributes (FEAR, HONOUR, FAITH, MAGIC), different creation, special combat (missile weapons, magic). Build a **data-driven rules layer**, not hardcoded logic.
- **Codeword/flag logic.** Missing or mis-scoped flags silently break the "true path" (player can reach the finale unable to win). Needs authoring tools + validation.

### 5.2 Death, saving & the "cheating" question
- **Pick a stance and make it a mode.** Pure faithful = restart-on-death, no reload (ironman). But modern audiences bounce off that. Offer **Ironman / Bookmarks (Tin Man) / Rewind (inkle) / Checkpoints** as explicit difficulty modes. Getting this wrong makes the game feel either sadistic or weightless.
- **Save-scumming vs. drama.** If reloading is trivial, choices lose stakes; if impossible, some players quit. The "rewind but the story remembers" model (inkle) is a strong middle ground.
- **Dead-ends & unwinnable states.** Faithful FF can strand you (out of the item needed to win, far from death). Decide whether to warn/soft-lock-detect or preserve the classic cruelty.

### 5.3 Dice integrity & perception
- **Honest RNG, visible dice.** Players are suspicious of digital dice. Show real pips; consider deterministic seeded RNG per run (also enables MP sync and "replay/verify"). If you offer any luck-fudging (accessibility), make it explicit and off by default.
- **Shake-to-roll / animation** must feel good but be skippable (speed settings, Quick Combat) — respect both the ritualist and the speedrunner.

### 5.4 Content, authoring & scale
- **~400 interlinked sections per book** is a large branching graph. You need an **authoring format** (structured markup / node editor) with: link validation (no dangling "turn to N"), reachability analysis, dead-end/unwinnable detection, flag/codeword consistency, and combat/stat scripting. Writing this by hand in raw data will rot fast.
- **Art pipeline.** Faithful FF leans on evocative interior plates. Budget the NoxDev art pipeline for per-section illustrations (and placeholders), plus cover, death, and victory art. Missing art hollows out the feel.
- **Text is the game.** Bad prose kills it; the template must make *writing and revising* passages first-class (hot-reload, preview, playtest-from-any-section debug jump).

### 5.5 IP & trademark
- FF names, monsters, worlds (Titan, Allansia), the trademark, and original text/art are **not** ours. Ship the *mechanics and UX*, fill with **original NoxDev world, art, and writing**. Do not reuse FF section text, artwork, monster names, or branding. Name the template/genre generically ("branching adventure gamebook").

### 5.6 UX pitfalls
- **Metagaming via visible section numbers** — hide "turn to N" in faithful mode (offer a "classic numbers" toggle for nostalgia).
- **Choice legibility** — conditional choices need clear reasons when locked (item/gold/codeword) without spoiling.
- **Reading fatigue** — typography, theming, TTS, and text scaling are core, not polish.
- **Combat monotony** — pure 2d6 attrition can feel swingy/repetitive; Quick Combat, good log/feedback, and optional depth (Luck gambles, item use) keep it engaging. (Both *Legends* and *Sorcery!* replaced dice combat precisely because the raw loop can feel thin — weigh a faithful-but-optional-depth combat vs. a reimagined one.)
- **Mobile-first vs. desktop** — the reading column is portrait-native; ensure the combat/map/sheet screens reflow for landscape/desktop.

### 5.7 Multiplayer-specific
- **FF has no native combat rules for a party** — you must invent (and playtest) co-op combat/loot/choice-arbitration house rules.
- **State authority & desync** — one authoritative host owns section id, all sheets, codewords, and the RNG seed; clients propose, host validates. Handle disconnects/rejoins and pacing differences.
- **AI DM must never own the math** — the engine is authoritative over dice and the Adventure Sheet; the LLM narrates and maps free-text intent onto legal choices only, or the game becomes inconsistent/exploitable.

---

## 6. Distilled recommendations for `ff-gamebook` (bridge to the GDD)

- **Core is faithful classic FF:** 1d6+6 / 2d6+12 / 1d6+6 creation; 2d6+SKILL combat wounding for 2; Test-your-Luck with the −1 decrement; Provisions +4; single-Potion choice; codeword/flag state; ~400-section graph.
- **Modernize the bookkeeping, not the soul:** automated Adventure Sheet, honest animated dice (shake-to-roll), Quick Combat, unlimited bookmarks, auto-map, scalable/accessible typography.
- **Expose death/save as a MODE** (Ironman / Bookmarks / Rewind / Checkpoints).
- **Data-driven rules layer** so per-book variants (extra attributes, special combat) and an alt **Sorcery!-style** or **Legends-style** mode are configuration, not rewrites.
- **Author-first tooling:** structured section format with link/flag/reachability validation and jump-to-section debug play.
- **MP:** SP + hotseat guaranteed; authoritative-host architecture for net hotseat / shared-party co-op / LAN; **AI DM (color + intent-routing)** as flagship, engine-authoritative on all math.
- **Screens to build (full list):** Title/Main Menu · Library/Bookshelf · Character Creation · **Book-Reading View** · Choice/Branch UI · Dice-Roll Overlay · Combat Screen · Adventure Sheet · Inventory/Equipment/Potions · Map/Progress · Save/Load/Bookmarks · Death Screen · Victory Screen · Settings · Gallery · Multiplayer Lobby/Session.

---

### Sources
- Tin Man Games — *Fighting Fantasy Classics*: [App Store](https://apps.apple.com/us/app/fighting-fantasy-classics/id1261201650) · [Tin Man Games](https://tinmangames.com.au/games/fighting-fantasy-classics/) · [TouchArcade review](https://toucharcade.com/2018/03/27/fighting-fantasy-classics-review/) · [Titannica wiki](https://fightingfantasy.fandom.com/wiki/Fighting_Fantasy_Classics)
- *Fighting Fantasy Legends* (Nomad/Asmodee): [Gamezebo review](https://www.gamezebo.com/reviews/fighting-fantasy-legends-review-the-dice-of-fate/) · [Bleeding Cool review](https://bleedingcool.com/games/review-fighting-fantasy-legends/) · [Titannica wiki](https://fightingfantasy.fandom.com/wiki/Fighting_Fantasy_Legends_(video_game))
- inkle — *Sorcery!*: [inkle Sorcery! page](https://www.inklestudios.com/sorcery/) · [Postmortem (Game Developer)](https://www.gamedeveloper.com/business/postmortem-i-steve-jackson-s-sorcery-i-series-by-inkle) · [inklecast on combat, dice, maps](https://www.inklestudios.com/2016/02/10/inklecast-sorcery-special2.html) · [combat breakdown (GameGrin)](https://www.gamegrin.com/reviews/sorcery-part-3-review)
