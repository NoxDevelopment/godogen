# CONTENT SAMPLE — *The Grey Tithe* vertical slice

> **Companion to:** [`GDD.md`](GDD.md) · Closes benchmark **gap #2** (zero content — no sample section, encounter, monster, or branch map).
> **World:** [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md) (*The Grey Tithe*) · **Rules:** GDD §3 + `ff-2d6.json` · **Numbers:** [`BALANCE.md`](BALANCE.md)
> **Owner:** narrative lead · **Status:** DRAFT playable slice.

This is **real, playable content** proving the format: twelve fully-written numbered sections that form the opening of *The Grey Tithe* (Act I → the Harrowfell hub), a **branch map** of how they connect, **three monster stat blocks** using the `ff-2d6` values, and **one full encounter spec** (the First Toll — bottleneck BN1). Everything is original NoxDev canon; no FF IP.

---

## Authoring notation (how to read these sections)

Sections are written as they render in the **Book-Reading View** (GDD §6.4). The bracketed lines are **authoring metadata** — they do *not* show to the player in faithful mode (target numbers are hidden; effects fire automatically; codewords are silent). They map 1:1 to the `Section` data model (GDD §5).

- `→ N` — a choice's target section id (`choices[].target`). Hidden from the player in faithful mode.
- `[if COND]` — `choices[].condition` (item / codeword / gold / stat gate). A locked choice is hidden or shown greyed with reason (GDD §6.5).
- `[effect: …]` — `choices[].effects` / `onEnter` effects, all funneled through `apply_delta()` (never-exceed-Initial + death-at-0 enforced).
- `[codeword: X]` / `[set flag=…]` — writes to the codeword/flag store (GDD §3, §5).
- `[event: combat / luck / skill / …]` — an `events[]` entry that raises the matching overlay (Dice / Combat).
- `⚑` marks a **bottleneck** (see NARRATIVE_BIBLE B2); ☠ marks an **instant-death** terminal.

---

## The sections (§§1–12)

### §1 — The Last Coach North ⚑ *(start; onEnter: roll-up complete)*

The coachman will take you no further than the Verge-stone. He reins in where the king's road dissolves into black bog and rotting reed, and he will not meet your eye.

"Harrowfell's that way," he says, pointing his whip down a causeway of sunken planks. "Was. I don't go past the stone after dark, sin-eater, and it's near dark." He waits only long enough for your boots to hit the mud before he turns the horses.

The fog smells of wet ash and old coins. Somewhere ahead, past the reeds, a bell tolls once — slow, and wrong, as if rung underwater. You are here because Harrowfell sent a letter, and then Harrowfell stopped sending anything at all. Your satchel holds a sword, leather armour, a lantern, ten Provisions, and one Potion of your choosing. On your tongue you carry the old sin-eater's words — the trade of taking the debts of the dead so the living may rest.

The causeway forks at a leaning shrine.

- Take the plank causeway straight toward the tolling bell. → **2**
- Cut left through the reeds, where the ground looks firmer. → **12**
- Kneel at the shrine and read the weathered ledger-stone first. → **4**

---

### §2 — The Toll-Bridge in the Fog

The planks give out at the edge of a slow black channel. A stone toll-bridge crosses it — older than the causeway, older than Aldermere maybe, its parapet carved with columns of figures that might be prayer and might be arithmetic. A lantern burns blue at the far end, though no hand tends it.

As your boot touches the first stone, the fog on the bridge *gathers*. It folds itself upright into the shape of a robed figure, faceless, patient, its sleeves hanging empty. Cold rolls off it like the breath of a coin-cellar. When it speaks, the voice comes from several distances at once.

"*A crossing is a service,*" it says. "*A service incurs a debt. We are the Grey Assessor. We find your account… opened.*"

It extends one empty sleeve, palm-up, and waits for payment.

*This is the First Toll (⚑ BN1). See the full **Encounter** spec below.*

- Pay in Gold — set a coin on the parapet. `[if gold ≥ 2]` → **3**
- Pay in kind — offer an item from your pack. → **5**
- Pay in blood — let it take its measure of you. → **6**
- Refuse. Draw your blade. `[event: combat → Grey Assessor]` → **7**

---

### §3 — Paid in Coin

You set two gold pieces on the wet stone. The Assessor does not pick them up; the coins simply *aren't there* the moment your fingers leave them, and neither is the cold.

"*Received,*" it says. "*Entered. Carried forward.*" The figure thins back into fog — but not before one empty sleeve tilts toward you, almost courteous, almost a threat. "*You are, we note, a payer of debts. The ledger remembers its good accounts. We will meet again at the third gate, and the price is set by the first.*"

[effect: −2 GOLD] · [set toll1_paid = gold] · [tithe_debt +0]

The blue lantern gutters. The bridge is open. Beyond it, the drowned rooftops of Harrowfell lean out of the fog.

- Cross into Harrowfell. → **8**

---

### §4 — The Ledger-Stone

The shrine is a Ledgerkeeper's marker — you know the grey robes carved on it, the scales that weigh not gold but *years*. Most of the inscription is moss. Three lines are still legible, and they read like a threat left for a debtor:

> *What is owed at the first gate? Not gold. Not blood. A name you would keep.*
> *The forgiven debt cannot be found in any book.*
> *Beware the kindness of the man who cannot let his daughter rest.*

You do not understand it yet. But the words settle into you the way a splinter does, and you will feel them again before the end.

[codeword: OMEN] *(a hint-flag the Structured DM uses to surface Odo's riddle earlier; grants no item)*

- Return to the fork and take the causeway toward the bell. → **2**

---

### §5 — Paid in Kind

You unbuckle your pack. The Assessor's faceless attention settles on it with the weight of an appraiser's glance, and you understand — sickly — that it is not choosing; *it already knows what you value most.*

"*The lantern,*" it says. "*You will want it, in the dark under the town. That is why it will do.*"

- Give up the lantern. → **5a**
- Refuse this — offer the rope and blanket instead. `[if has: rope]` → **5b**

**§5a —** You hand over the lantern. The Assessor folds it into a sleeve and is gone. You have paid, and you have paid *dearly*: the Cathedra is lightless.
[effect: remove item: lantern] · [set toll1_paid = item] · [set flag darkPenalty = true] → **8**

**§5b —** "*Insufficient,*" it says, without heat. "*We do not haggle. We assess.*" The cold sharpens.
- Then pay in blood. → **6**
- Then fight. `[event: combat → Grey Assessor]` → **7**

---

### §6 — Paid in Blood

"*As you wish,*" says the Assessor. "*Blood is an honest tender.*"

The empty sleeve passes an inch above your forearm and something *withdraws* — not blood exactly, but the warmth behind it, the small everyday luck of an unhurt body. **Test your Luck.**

[event: luck]
- **Lucky:** the toll is light — a shallow cost, quickly closed. [effect: −2 STAMINA] · [set toll1_paid = blood] → **8**
- **Unlucky:** it takes more than it offered to. [effect: −4 STAMINA] · [set toll1_paid = blood] · [tithe_debt +1] → **8**

*(Test your Luck also spends 1 LUCK, pass or fail — GDD §3.)*

---

### §7 — Refusal ⚑ *(the BN1 combat resolution)*

Your blade clears its sheath and the fog *screams* in three voices at once. This is a **combat encounter** — resolve it under the full Encounter spec below.

[event: combat → GREY_ASSESSOR · escapeTarget: none(bridge) · onWin: 7a · onDeath: DEATH_TOLL]

**§7a — (on defeating the Assessor)** The robe collapses into wet fog and the cold blows out like a snuffed candle. But as it disperses, the several-distanced voice laughs, unbothered: "*Dispersed. Not discharged. An unpaid account only grows, sin-eater. We will present it again — with interest.*"

[set toll1_paid = fought] · [tithe_debt +1] · [codeword: DEFIANT]

- Cross into Harrowfell, blade still wet. → **8**

---

### §8 — The Drowned Gate

Harrowfell begins where the water ends: a huddle of stone houses on a rise, half of them flooded to the sills, all of them shuttered. A militia barricade blocks the gate — overturned carts, a snapped pike, and a smell of tallow and sickness. Grey ledger-script, faint as frost, crawls up the doorframes: the mark of accounts called in.

A voice cracks from behind an arrow-slit in the moot-hall tower: "*Far enough! State your business, or the bog gets another body!*" A crossbow, badly held, wavers at your chest.

- Call back that Mother Grissel Thorne sent for you. → **9**
- Say nothing; test whether you can slip past the barricade in the fog. `[event: skill]` → **8a**
- Draw your blade and force the gate. → **8b**

**§8a — Test your Skill.** [event: skill]
- **Success:** you are over the carts and into the shadow of the eaves before the bolt thuds into a plank where you stood. → **9**
- **Failure:** the bolt catches you. [effect: −2 STAMINA] The voice reloads, cursing. → **8b**

**§8b —** The gate is not the enemy you want. A haggard serjeant steps out, crossbow spent, sword shaking — *this is Cael Dunmore* — and behind him three civilians cower. Forcing this costs you an ally you will need. [set flag caelFirstMet = hostile] → **9**

---

### §9 — The Square (the Harrowfell hub) ⚑

Inside the barricade, Harrowfell holds its breath. A dozen souls, no more. The fever-house lantern burns in a low stone building to your right, Mother Grissel's shadow moving behind the oilcloth. The moot-hall tower ahead is where Serjeant Cael has walled himself in with the last of the militia. In the flooded market square to your left, a single stall still burns bright and mercantile against the gloom — **Ferrant Coinwright**, doing business at the end of the world.

Everything you will need to end this — a true name, a seal, a blessed edge, and whether these people live or die — is somewhere in this square. Spend your time here well; the Verge is not patient.

*This is a **storylet hub** (NARRATIVE_BIBLE B5). Visit in any order; the Structured DM tracks state.*

- Go to Mother Grissel's fever-house. → **10**
- Climb to the moot-hall and speak with Serjeant Cael. → *(storylet: The Moot-Hall Stair)*
- Cross to Ferrant Coinwright's stall. → **11**
- You have gathered what you can. Descend toward the Cathedra. `[if visited ≥1 storylet]` → *(BN2: The Descent)*

---

### §10 — Mother Grissel's Fever-House

The room is close with the smell of tallow, thyme, and the sweet-rot undertone of the Grey Tithe. Three cots, two occupied, one covered. Mother Grissel Thorne does not look up from the poultice she is grinding — a big-knuckled woman, grey-haired, grief worn into her like a groove in a doorstep.

"So he sent a *sin-eater*." She says the word the way you'd name a bad debt. "Sit. You'll cost me a night's warmth just standing there letting the door breathe." She measures you with eyes that measure everything in doses and nights left. "You want to know what's killing my town. I'll tell you what I can afford to. The rest'll cost you — not gold. Trust. Come back when you've shown me you won't just *spend* us like he does."

[set flag metGrissel = true] *(the Confession storylet that grants `RESTITUTION` unlocks after trust is earned — see NARRATIVE_BIBLE B5)*

- Ask about the Reckoner. → **10a**
- Ask what she needs; offer a Provision to the sick. `[if provisions ≥ 1]` [effect: −1 PROVISION] [set flag showedMercy = true] → **10b**
- Leave; return to the square. → **9**

**§10a —** "Ambrose Vael. High Ledgerkeeper, once. Good man, once." Her grinding stops. "His girl died. He couldn't sign the account closed. So he opened it back up — and now he's opening *all* of them." She will say no more today. → **10**

**§10b —** She watches you feed the dying stranger and something in her face unclenches, one notch. "…Huh. Maybe you're not just his errand-boy." [advances the Confession chain] → **10**

---

### §11 — Ferrant Coinwright's Stall

Lantern-light, a velvet cloth over a plank, and on it: rope, torches, dried fish, a bottle marked with a physician's cross, and — wrapped in oilcloth like it's ashamed of itself — a sword with a saint's name etched down the fuller. Ferrant himself is neat, dry, and entirely at ease, which in Harrowfell is its own kind of horror.

"A customer! Gods bless the apocalypse, it's *marvelous* for margins." He spreads his hands. "Everything's for sale, friend, and I do mean everything. What'll it be — full belly, dry rope, or the only blade in the Verge that'll bite the Reckoner?"

*This is the **shop** (NARRATIVE_BIBLE A4 #3; prices in BALANCE.md economy).*

| Stock | Price (Gold) | Effect |
|---|---|---|
| Provisions ×3 | 3 | [effect: +3 PROVISIONS] |
| Torch | 1 | offsets `darkPenalty` |
| **Saint Vexcel's blade** | 8 | [codeword: `blessedWeapon`] — wounds the Reckoner |
| Tithe-draught (cure) | 5 | clears Grey Tithe affliction |
| **Information:** where the Seal lies | 4 | points to Odo (shortcut to `hasSeal` path) |

- Buy something. `[if gold ≥ price]` [effect: −price GOLD; grant item] → **11**
- Try to rob him. → **11a**
- Leave; return to the square. → **9**

**§11a —** Ferrant's smile doesn't move, but a second, uglier man steps out of the shadow behind the stall with a hook-knife. "Now, now. I *did* say everything's for sale. Theft, though — theft I price in blood." [event: combat → Cutthroat] [set flag ferrantHostile = true] *(robbing closes the blessed-weapon and cure supply — a true-path cost)*

---

### §12 — The Reeds ☠ *(instant-death terminal)*

The reeds are firmer for six steps. On the seventh, the ground is not ground.

The bog takes your leg to the knee, then the thigh, with the patient grip of something that has been *waiting* to be owed a body. As you go down you see them — pale shapes standing in the water all around, robed and faceless, and every one of them holds a little book, and in every book a hand is writing your name.

"*Account settled,*" says the fog.

Your adventure ends here.

[event: death · cause: "Claimed by the Tithe-taken in the fen"] → **DEATH SCREEN**

---

## Branch map (the slice)

```
                                  §1  The Last Coach North ⚑
                                   │  (fork at the shrine)
                 ┌─────────────────┼──────────────────────────┐
                 ▼                 ▼                          ▼
            §4 Ledger-Stone   §2 Toll-Bridge ⚑ BN1        §12 The Reeds ☠
            [codeword OMEN]        │  (the First Toll)      (instant death)
                 │        ┌────────┼─────────┬──────────┐
                 └───────►│        ▼         ▼          ▼
                     pay GOLD   pay ITEM  pay BLOOD   REFUSE→fight
                        §3         §5         §6          §7  (combat)
                         │      ┌──┴──┐       │        ┌───┴───┐
                         │    §5a  §5b(→6/7)  │      §7a win  DEATH_TOLL ☠
                         │      │              │        │
                         └──────┴──────┬───────┴────────┘
                                       ▼
                             §8  The Drowned Gate ⚑
                              │  (call / sneak / force)
                       ┌──────┼───────┐
                       ▼      ▼        ▼
                   (call)  §8a skill  §8b force
                       └──────┼───────┘
                              ▼
                    ┌──────►  §9  The Square (HUB) ⚑ ◄──────┐
                    │         │  (storylet hub — any order)  │
                    │   ┌─────┼───────────┬─────────────┐    │
                    │   ▼     ▼           ▼             ▼     │
                    │ §10   [Moot-Hall  §11 Ferrant   (BN2   │
                    │ Grissel  Stair]    stall         Descent│
                    │  │       Cael]      │             gate) │
                    │  ├─►10a  10b        ├─►buy             │
                    └──┘ (confession       └─►11a rob ☇       │
                         chain →              (ferrantHostile)│
                         RESTITUTION)         └───────────────┘
                                       │
                                       ▼  (needs ≥1 storylet visited)
                              BN2: THE DESCENT → Act III (three gates → Isolde → Reckoner)
```

**Legend:** ⚑ bottleneck · ☠ death terminal · ☇ optional fight. The slice is **branch-and-bottleneck**: the First Toll (BN1) fans into four payment branches that *all* reconverge at §8, then the Square (§9) is a re-enterable storylet hub before the BN2 descent. The `toll1_paid` value set here is *read again* at the Third Gate in Act III (loop-and-grow — NARRATIVE_BIBLE B1).

---

## Monster stat blocks (`ff-2d6` values)

Three foes that appear in or adjacent to this slice. All use canonical FF combat (GDD §3): Attack Strength = 2d6 + SKILL; higher total wounds the loser for 2 STAMINA. Full roster and tiering in [`BALANCE.md`](BALANCE.md).

---

### ☠ BOG-WIGHT (Tithe-taken, minor)
> *A drowned villager risen with an account still open — grey ledger-script weeping from waterlogged skin. Slow, but it does not stop, and it does not feel the blows it should.*

| Stat | Value |
|---|---|
| **SKILL** | **6** |
| **STAMINA** | **6** |
| Tier | Fodder (early) |
| Portrait | `bogwight_01` (library monster pack, restyled to veritas anchor) |

**Special rules:**
- **Ledger-numbed:** the first wound you deal each round is *ignored* on a roll of 1 on 1d6 (it doesn't feel it). Model as `modifier: chance_ignore_wound(1/6)`.
- **Release, not kill:** if the player speaks a matching name/codeword (rare), the Bog-Wight can be *released* instead of fought (STAMINA → 0 with no combat). Thematic hook, not required.
- No escape penalty beyond the standard 2 STAMINA where the text offers escape.

---

### ☠ GREY ASSESSOR (toll-wraith; the BN1 encounter)
> *Not a person — a manifestation of the Reckoner's ledger, folded out of cold fog to collect at thresholds. Faceless, courteous, and impossible to truly kill before the finale.*

| Stat | Value |
|---|---|
| **SKILL** | **8** |
| **STAMINA** | **9** (per manifestation) |
| Tier | Mini-boss / recurring gate |
| Portrait | `assessor_wraith` (bespoke veritas plate) |

**Special rules:**
- **Assessment (pre-combat):** on entering combat, the Assessor first demands a toll (the §2 choice). Combat only begins on refusal.
- **Toll-strike:** on any round the Assessor wins, instead of 2 STAMINA it may (50%, `1d6` even) drain **1 GOLD or 1 LUCK** instead of STAMINA (player's choice which) — it *collects* rather than kills. If the player has neither, it deals the normal 2 STAMINA.
- **Disperses, not dies:** at 0 STAMINA it disperses (§7a) — it is *not* discharged. It **recurs** twice more (escalating `tithe_debt`); the third meeting's price is set by `toll1_paid`.
- **No escape:** the bridge offers no escape route (`escapeTarget: none`); the player must pay or fight.
- **Cannot be permanently ended before the finale** (NARRATIVE_BIBLE A6 #7).

---

### ☠ THE RECKONER — Ambrose Vael (final; reference)
> *The grieving High Ledgerkeeper, remade into the instrument of his own impossible debt. Courteous, exhausted, certain. The last section.*

| Stat | Value |
|---|---|
| **SKILL** | **12** |
| **STAMINA** | **20** |
| Tier | Final boss |
| Portrait | `reckoner_final` (bespoke veritas key plate) |

**Special rules:**
- **Immune to mortal steel:** only a wound dealt with `blessedWeapon` (Saint Vexcel's blade) reduces his STAMINA at all. Without it, the fight is unwinnable (routes to ending CARRIED FORWARD — NARRATIVE_BIBLE B6 #4).
- **Calling-in:** every third round he "calls in a debt" — Test your Luck or lose 2 LUCK as an old account is levied against you.
- **The true win is not a kill:** using `RESTITUTION` + the Quittance Seal on Isolde *before* this fight dissolves him without combat (true ending QUITTANCE). Killing him with the blessed blade yields only the pyrrhic HOLLOW VICTORY (A6 #6).
- **Cultural-risk note:** authored to read as tragic, never mocked (NARRATIVE_BIBLE A4 #4).

---

## Full encounter spec — **THE FIRST TOLL (⚑ BN1)**

The load-bearing set-piece of the slice: the first time the player meets the world's central bargain — *pay a price, or fight.* It teaches the toll mechanic, seeds the `toll1_paid` loop-and-grow, and establishes the Grey Assessor as the throughline threat. Corresponds to `Encounter` in the data model (GDD §5).

**Trigger:** entering §2 (the toll-bridge) from §1 or §4.
**Type:** hybrid — a **decision-under-pressure** (toll) that becomes a **combat** only on refusal.
**Setting/mood:** fog-drowned stone bridge, blue untended lantern, ledger-carved parapet. Cold. Music: `tension` bed, no combat sting unless combat begins (STYLE_GUIDE audio).

**Actors:** the player; the **Grey Assessor** (stat block above).

**Flow:**
```
 §2 arrive ──► ASSESSMENT: "a crossing incurs a debt"
                 │
       ┌─────────┼───────────┬─────────────────┐
   pay GOLD   pay ITEM     pay BLOOD          REFUSE
   (≥2 gp)   (it names     (Test Luck:        (draw blade)
      │       the lantern)  Lucky −2 STA /        │
      ▼          │          Unlucky −4 +debt)     ▼
     §3        §5→5a/5b        §6              §7 COMBAT
  toll1=gold  toll1=item    toll1=blood     ┌───┴────┐
      │       darkPenalty       │        win §7a   lose
      │       (or →6/→7)        │        toll1=    DEATH_TOLL ☠
      └─────────┴───────────────┴────►§8   fought
                                          tithe_debt+1
                                          codeword DEFIANT
```

**Combat sub-spec (refusal path, §7):**
- Rounds resolve per GDD §3: each round both roll 2d6 + SKILL; higher wounds the loser 2 STAMINA.
- Assessor SKILL 8, STAMINA 9. Player typical SKILL 7–12.
- **Toll-strike** active: on Assessor-won rounds, `1d6` even → it drains 1 GOLD or 1 LUCK (player choice) instead of 2 STAMINA.
- **Luck-in-combat** available normally (GDD §3): after wounding, Test Luck for +2/−1 damage swing, etc.
- **No escape** (`escapeTarget: none`).
- **Quick Combat** toggle supported (GDD §6.7): auto-runs rounds.

**Outcomes & links:**
| Result | Effects | Next |
|---|---|---|
| Paid gold | −2 GOLD; `toll1_paid=gold` | §3 → §8 |
| Paid item (lantern) | remove lantern; `darkPenalty=true`; `toll1_paid=item` | §5a → §8 |
| Paid blood (Lucky) | −2 STAMINA, −1 LUCK; `toll1_paid=blood` | §6 → §8 |
| Paid blood (Unlucky) | −4 STAMINA, −1 LUCK, `tithe_debt+1` | §6 → §8 |
| Won the fight | `toll1_paid=fought`; `tithe_debt+1`; codeword `DEFIANT` | §7a → §8 |
| Lost the fight (STAMINA 0) | death | DEATH_TOLL ☠ |

**Why it matters (design intent):** BN1 is where the player first *characterizes themselves* through spending — coin, gear, body, or defiance — and the game quietly starts keeping score (`tithe_debt`, `toll1_paid`) for the Third Gate payoff and the endings. It is the thesis of *The Grey Tithe* in ninety seconds of play: **the ledger is always balanced; the only question is what you pay with.**

---

## Cross-references
- World & cast this is set in: [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md).
- Enemy tiers, economy prices, difficulty & probability behind these numbers: [`BALANCE.md`](BALANCE.md).
- Rules these sections invoke: [`GDD.md`](GDD.md) §3 (combat/Luck), §5 (Section/Encounter/AdventureSheet), §10 (authoring validation).
- Screens they render on: [`WIREFRAMES.md`](WIREFRAMES.md) (Reading View, Dice overlay, Combat).
