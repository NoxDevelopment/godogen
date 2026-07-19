# BALANCE — *The Grey Tithe* (enemy roster, economy, difficulty, probability)

> **Companion to:** [`GDD.md`](GDD.md) · Closes benchmark **gap #4** (balance is combat-only — no enemy tables, economy, or difficulty tuning).
> **World:** [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md) · **Content it tunes:** [`CONTENT_SAMPLE.md`](CONTENT_SAMPLE.md) · **Rules:** GDD §3 + `ff-2d6.json`
> **Owner:** systems/design lead · **Status:** DRAFT tuning model.

The GDD's combat *math* is exact and excellent, but it is the only number in the document. This doc adds the four things a shippable gamebook needs beyond the dice formula: an **enemy roster with SKILL/STAMINA tiers**, an **economy** (where Gold and Provisions come from and drain to), a **difficulty model**, and a **probability sanity-check** (win-rate feel across SKILL/LUCK ranges, and the LUCK-depletion curve — *is Test-your-Luck actually viable, and how often?*). All numbers use the canonical values from GDD §3.

**Player reference profile** (from GDD §3 roll-up): SKILL 7–12 (avg ≈9.5), STAMINA 14–24 (avg ≈19, ≈10 wounds to die), LUCK 7–12 (avg ≈9.5). Starting kit: sword, leather armour, lantern, **10 Provisions**, **1 Potion** (2 doses), and **2d6 Gold** (avg 7; see economy). These are the assumptions every table below is tuned against.

---

## 1. Enemy roster & SKILL/STAMINA tiers

Enemies are tiered by **threat to the reference hero**, not by lore. The governing lever is **SKILL differential** (`delta = playerSKILL − enemySKILL`) — as the probability section proves, delta swamps STAMINA. Design rule: **fodder is `delta ≥ +2` for an average hero; a "fair fight" is `delta ≈ 0`; anything `delta ≤ −2` is a set-piece the player should be able to avoid, buff for, or flee.**

| Tier | Role | SKILL | STAMINA | Delta vs avg hero (SK9.5) | Example enemies (*Grey Tithe*) |
|---|---|---|---|---|---|
| **T0 Fodder** | attrition, mood | 5–6 | 4–6 | +3.5 to +4.5 | Reed-Lurker (SK5/ST4), **Bog-Wight** (SK6/ST6), Tithe-Rat swarm (SK5/ST5) |
| **T1 Standard** | the honest fight | 7–8 | 7–10 | +1.5 to +2.5 | Tithe-taken Reveler (SK7/ST8), Cutthroat (SK7/ST7), **Grey Assessor** (SK8/ST9) |
| **T2 Elite** | needs a plan | 9–10 | 11–14 | −0.5 to +0.5 | Ossuary Warden (SK9/ST12), Feral Debt-Hound (SK10/ST10), Toll-Serjeant (SK9/ST13) |
| **T3 Mini-boss** | set-piece | 10–11 | 14–18 | −1.5 to −0.5 | Third-Gate Guardian (SK11/ST16), **Isolde-as-boss** (SK10/ST16, special) |
| **T4 Boss** | the finale | 12 | 20 | −2.5 | **The Reckoner** (SK12/ST20, special) |

**Roster detail (the fights the vertical slice + Act III use):**

| Enemy | SKILL | STAM | Tier | Special rules (data-driven modifiers) | Gold on defeat |
|---|---|---|---|---|---|
| Reed-Lurker | 5 | 4 | T0 | Ambush: free first round unless player passed a Test your Skill | 0 |
| **Bog-Wight** | 6 | 6 | T0 | *Ledger-numbed:* ignores first wound/round on a 1-in-6; *releasable* by name | 0 |
| Tithe-Rat swarm | 5 | 5 | T0 | Gang: 3 bodies, one shared STAMINA pool; player rolls once vs all | 0 |
| Cutthroat (Ferrant's) | 7 | 7 | T1 | Only if player robs Ferrant; flees at ST≤2 | 2 |
| Tithe-taken Reveler | 7 | 8 | T1 | *Grief-wail:* Test your Luck on entry or −1 SKILL for the fight | 1 |
| **Grey Assessor** | 8 | 9 | T1 | *Toll-strike* (drains Gold/LUCK not STAM, 50%); *disperses not dies*; recurs ×3 | 0 (collects) |
| Feral Debt-Hound | 10 | 10 | T2 | Fast: wins ties; avoidable if `hasVessel` (Vessel calls it off) | 3 |
| Ossuary Warden | 9 | 12 | T2 | *Bone-plate:* wounds reduced to 1 unless `blessedWeapon` | 4 |
| Toll-Serjeant | 9 | 13 | T2 | Guards the shortcut; escape offered (−2 STAM) | 5 |
| Third-Gate Guardian | 11 | 16 | T3 | Price gated on `toll1_paid`; can be *paid past* instead of fought | 0 |
| **Isolde-as-boss** | 10 | 16 | T3 | Only if the player lacks `RESTITUTION`; *cannot be "won" cleanly* — see §4 | 0 |
| **The Reckoner** | 12 | 20 | T4 | *Immune to mortal steel* (needs `blessedWeapon`); *Calling-in* every 3rd round (Test Luck or −2 LUCK); true win is release not kill | — |

**Tuning invariants:**
- No T2+ fight is *forced* on a path that hasn't offered a buff (blessed weapon, Vessel, a Provision top-up) or an escape. Set-pieces must be survivable *or* skippable.
- Gang rounds (Tithe-Rats, multi-Reveler) use the GDD §3 gang rule; total STAMINA is tuned so a gang ≈ one T1 fight in expected damage taken.
- The Reckoner's STAMINA (20 → 10 wounds) is deliberately set so that even a max-SKILL hero (delta 0) is a coin-flip *in the fight path* — the fight is never the intended win (that's QUITTANCE). See §5.

---

## 2. Economy — Gold & Provisions (sources, sinks, curve)

The economy *is* theme #1 ("the ledger is always balanced"): resources are always slightly scarce, and the true path is affordable only if the player doesn't waste. Two currencies: **Gold** (buys capability) and **Provisions** (buys STAMINA). LUCK is a *third* pseudo-economy (see §5).

### 2.1 Gold

**Target curve:** the average hero should be able to afford **the one critical purchase (Saint Vexcel's blessed blade, 8 gp)** *plus* a small margin, but **not** everything — the player must choose. Total reachable Gold across the vertical slice ≈ **18–24 gp**; total desirable sinks ≈ **26 gp**. Scarcity ratio ≈ 0.8 (you can afford ~80% of what you want).

| Gold SOURCES | Amount | Notes |
|---|---|---|
| Starting purse | 2d6 (avg 7) | roll-up |
| Loot (T1–T2 kills) | 1–5 each | see roster; fodder drops nothing (theme: the dead are broke) |
| Found caches (3 in slice) | 2–4 each | reward for exploration, gated behind minor risk |
| Sell Potion dose to Ferrant | 3 | desperate-liquidity option; costs you the elixir |
| Rob Ferrant | +all stock, but | sets `ferrantHostile`, closes future supply — a trap |

| Gold SINKS | Cost | Notes |
|---|---|---|
| **Saint Vexcel's blade** (`blessedWeapon`) | **8** | *the* purchase; required for the fight path & Ossuary Warden |
| Provisions ×3 | 3 | field healing top-up |
| Torch | 1 | negates `darkPenalty` if you paid the lantern at BN1 |
| Tithe-draught (cure) | 5 | clears a Grey-Tithe affliction (contracted on Unlucky events) |
| Information (Seal location) | 4 | shortcut to `hasSeal` (or free via Odo's riddle) |
| The First Toll | 2 | BN1, if paid in gold |
| Assessor toll-strikes | 1/hit | combat leakage |

**Design consequence:** a player who fights everything and buys the cure + info + blade will run short and must *earn Grissel's trust for free* (the true-path key `RESTITUTION` costs **no gold** — mercy is the un-buyable coin, NARRATIVE_BIBLE A6 #10). A player who hoards gold by skipping the cure risks the Tithe affliction. Both are legitimate; neither is free.

### 2.2 Provisions

Provisions are the **STAMINA economy**: start 10, each restores **+4 STAMINA** (never above Initial), **not usable mid-combat-round** (GDD §3).

- **Total starting field-healing:** 10 × 4 = **40 STAMINA** — roughly 2× the hero's max pool, i.e. you can "refill" about twice over a full run if you spend nothing else.
- **Sinks:** eating (planned healing), befriending Vessel (−2 Provisions, NARRATIVE_BIBLE B5), some tolls/events may demand a Provision as tribute.
- **Sources:** buy ×3 from Ferrant (3 gp); rare found rations (1–2).
- **Tuning:** authored damage across the slice totals ≈ **28–34 STAMINA** of unavoidable loss on a *careful* path, so a starting 10 Provisions + starting STAMINA comfortably covers a clean run — but a reckless player (extra fights, Unlucky rolls) will burn Provisions fast and arrive at the Reckoner thin. The margin is intentional, not generous.

### 2.3 Potions (starting elixir)

One choice at roll-up, 2 doses, restore-to-Initial (Fortune also +1 Initial LUCK). Balance role: the Potion is the player's **emergency reserve** in whichever stat they judge their run is weakest — Strength (STAMINA) is the safe pick; Fortune (LUCK) is the high-skill pick that extends the Test-your-Luck economy (§5); Skill is the gambler's pick for the boss.

---

## 3. Difficulty model

The four save modes (Ironman/Bookmarks/Rewind/Checkpoints, GDD §4) are a **consequence** model, **not** a difficulty model — the benchmark correctly flags this. Difficulty is modeled on **two independent axes** (following the SH2 riddle-vs-enemy split praised in the benchmark), each with three settings, plus the orthogonal save-mode axis.

| Axis | Setting | What it changes | Default |
|---|---|---|---|
| **Combat harshness** | Merciful | enemy STAMINA −20% (round up); escape always offered | |
| | **Faithful** | canonical `ff-2d6` values exactly (all tables above) | ✅ |
| | Grim | fodder promoted a tier; no settings-gated reroll | |
| **Fortune aids** | Guided | 1 free re-roll of a failed critical Luck/Skill test per act; low-roll roll-up curve | |
| | **Faithful** | roll-once-commit; Luck depletes canonically | ✅ |
| | Purist | no aids; low roll-up stands; unwinnable states preserved (classic cruelty) | |
| **Consequence** (save mode) | Bookmarks / Rewind / Checkpoints / Ironman | reload policy only — orthogonal to the two axes above | Bookmarks |

**Accessibility ≠ Merciful:** the accessibility aids (TTS, text scale, settings-gated reroll at creation, reduced-motion dice) are available on **every** difficulty (GDD §11) — they change *access*, not *challenge*. A Purist player can still use TTS. This separation is a design commitment, not a toggle collision.

**Tuning target (Faithful/Faithful/Bookmarks default):** a first-time average-roll player who plays carefully, earns Grissel's trust, and buys the blade should reach the true ending in **2–4 attempts** — deaths are content, not walls. A max-SKILL/max-LUCK hero can win first-try; a min-roll hero (SK7/LK7) *can* win but leans hard on Provisions, avoidance, and the Potion.

---

## 4. Boss & set-piece balance notes

- **The Reckoner is not meant to be beaten in a fight.** With `blessedWeapon`, win% ranges from ~50% (SK12 hero) down to near-impossible (SK7). *Calling-in* (Test Luck or −2 LUCK every 3rd round) means a protracted fight also drains the LUCK the hero needs elsewhere — the fight *punishes* itself. This steers players toward the QUITTANCE (release) path, which is a **guaranteed** win if the keys were gathered. Balance intent: the true path is *easier* than the fight, and that asymmetry is the lesson (theme #3).
- **Isolde-as-boss** (only if the player lacks `RESTITUTION`) is authored so that "winning" the fight still fails the run (she is un-killable in the meaningful sense; reducing her STAMINA to 0 triggers a heartbreak ending, not victory). This is a deliberate *unwinnable-by-force* gate, flagged in the authoring validator as intentional (NARRATIVE_BIBLE B7).
- **Escape economy:** every T2+ escape costs the canonical 2 STAMINA (GDD §3) and forfeits that fight's Gold — fleeing is a valid strategy for a thin hero but taxes the economy, keeping it a real choice.

---

## 5. Probability sanity-check

All figures below are computed from the canonical rules (2d6+SKILL opposed rounds; 2 STAMINA per wound; Test your Luck = 2d6 ≤ current LUCK, −1 LUCK always). Verified numerically.

### 5.1 Per-round combat odds (by SKILL differential)

`delta = playerSKILL − enemySKILL`. "Round win" = you wound them; ties (no damage) are the remainder.

| delta | P(you wound, per round) | P(decisive round you win)* |
|---|---|---|
| −5 | 5.4% | 5.6% |
| −4 | 9.7% | 10.4% |
| −3 | 15.9% | 17.3% |
| −2 | 23.9% | 26.5% |
| −1 | 33.6% | 37.6% |
| **0** | **44.4%** | **50.0%** |
| +1 | 55.6% | 62.4% |
| +2 | 66.4% | 73.5% |
| +3 | 76.1% | 82.7% |
| +4 | 84.1% | 89.6% |

*ties (≈9–11%) excluded. **Takeaway:** SKILL differential is enormous — +2 nearly doubles your decisive-round edge over even. This is the classic FF truth and the reason SKILL is the single most run-defining roll.

### 5.2 Win-rate feel (whole-fight, average hero STAMINA 19 → 10 wounds to die)

Probability the hero *wins the fight* vs a foe of the given STAMINA, at each delta:

| delta | vs STA 6 (fodder) | STA 9 (Assessor) | STA 12 (Warden) | STA 16 (mini-boss) | STA 20 (Reckoner) |
|---|---|---|---|---|---|
| −4 | 12.0% | 1.1% | 0.3% | 0.0% | 0.0% |
| −3 | 34.5% | 7.9% | 3.2% | 0.4% | 0.0% |
| −2 | 65.4% | 30.3% | 18.3% | 5.5% | 1.4% |
| −1 | 88.8% | 65.6% | 52.2% | 28.6% | 13.3% |
| **0** | 98.1% | 91.0% | 84.9% | 68.5% | **50.0%** |
| +1 | 99.8% | 98.9% | 97.8% | 93.8% | 86.7% |
| +2 | 100% | 99.9% | 99.9% | 99.5% | 98.6% |

**Reading it:**
- An **average hero (delta ≈ +2 to +4 vs fodder/T1)** shrugs off the slice's standard fights — correct; the game's threat is *attrition and set-pieces*, not random encounters.
- **Elite (T2, delta ≈ 0)** fights are real: ~85% at STA12 sounds safe, but each fight *costs* STAMINA (the loser-rounds), draining the Provision economy — the danger is cumulative, not per-fight.
- **The Reckoner at delta 0 is a literal coin-flip (50%)**, and worse for lower-SKILL heroes (13% at delta −1). This confirms the fight path is a bad bet — the design *wants* you on the release path. Working as intended.
- A **min-SKILL hero (SK7)** facing SK9–12 foes at delta −2 to −5 must **avoid or buff**, never brute-force. The roster's escape/skip/Vessel options exist precisely for these heroes.

### 5.3 The LUCK-depletion curve — is Test-your-Luck viable, how often?

Test your Luck succeeds if 2d6 ≤ current LUCK, and **always** costs 1 LUCK. So each test is both *less* likely and *depletes* the pool:

| Current LUCK | P(Lucky) |
|---|---|
| 12 | 100% |
| 11 | 97.2% |
| 10 | 91.7% |
| 9 | 83.3% |
| 8 | 72.2% |
| 7 | 58.3% |
| 6 | 41.7% |
| 5 | 27.8% |
| 4 | 16.7% |
| 3 | 8.3% |
| 2 | 2.8% |
| 1 | 0% |

**Expected number of *successful* Luck tests over a whole run** (if the hero tests every point down to 0):

| Starting LUCK | Expected successes |
|---|---|
| 7 (min) | **1.56** |
| 9 (avg) | **3.11** |
| 12 (max) | **6.00** |

**Viability verdict:** the first **~2–3 tests** of a run are genuinely favorable for any hero (≥58% while LUCK ≥ 7). After that, the odds cross below 50% at **LUCK 6** and collapse fast. So an average hero has roughly **three good gambles per run**, a min-LUCK hero barely **one and a half**, and a max-LUCK (or Potion-of-Fortune) hero **six**. LUCK is exactly what the theme wants: a **precious, visibly-draining resource** you must spend deliberately.

**Authoring guidance derived from this:**
1. Gate at most **3–4 *critical* outcomes** behind Luck tests per run for the average hero; anything more makes low-LUCK rolls unwinnable and betrays the difficulty target.
2. Space Luck tests so the player can *choose* which to spend on (the tension is the budgeting) rather than forcing back-to-back drains.
3. Provide LUCK restoration on the true path (Potion of Fortune; a rare event at the Cathedra) so a careful player can "top up" for the finale's *Calling-in* drain — otherwise the Reckoner's LUCK-tax compounds an already-thin pool.
4. Luck-in-combat (the ±damage gamble, GDD §3) is only worth it early in a fight/run while P(Lucky) ≥ ~58%; late-run it's a trap — the combat log/UI should *show* current LUCK so players feel the depletion (ties to WIREFRAMES combat + dice overlay).

---

## Cross-references
- The world these numbers serve: [`NARRATIVE_BIBLE.md`](NARRATIVE_BIBLE.md).
- The content these values tune (roster fights, the shop, BN1 encounter): [`CONTENT_SAMPLE.md`](CONTENT_SAMPLE.md).
- The rules formulas: [`GDD.md`](GDD.md) §3; risk framing: GDD §14; the combat/HUD surfaces that display these: [`WIREFRAMES.md`](WIREFRAMES.md).
