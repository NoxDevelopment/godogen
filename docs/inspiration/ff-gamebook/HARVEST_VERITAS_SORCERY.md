# Harvest — Veritas Tales · inkle *Sorcery!* · *Prince Jerian* / *Sir Brante* → `ff-gamebook`

> **Purpose.** Focused idea-harvest from three reference games for our illustrated Fighting-Fantasy gamebook (`ff-gamebook`, SP + MP + dual DM). This *supplements* the existing [`INSPIRATION.md`](INSPIRATION.md) (FF canon + Tin Man + a first Sorcery! pass) and [`../../gdd/ff-gamebook/GDD.md`](../../gdd/ff-gamebook/GDD.md) — it captures what those docs **don't already cover** and turns it into a ranked "fold into FF" list. Web-research → doc only; no template/code touched.
>
> **Why these three.** Two are the *namesakes of our art lanes*: **Veritas Tales** = the `veritas-gamebook` ink+watercolor FF-plate style (default, ship-ready); **Sir Brante** (and its same-studio successor **Prince Jerian**) = the `sir-brante` sepia-engraving variant. Sorcery! is the immersion/UX gold standard Jesus flagged.
>
> **IP stance (unchanged).** We harvest **mechanics + UX patterns only**. All world, art, monsters, text, spell names, faction names, and the "deaths economy" framing ship as **original NoxDev content** in *The Grey Tithe*. No trademarks, no reproduced text/art. Every idea below is genre-mechanic, not a reproducible asset.

---

## A. Veritas Tales: Witch of the Dark Castle

**What it is.** A "reading-style" fantasy adventure RPG (Steam 4508570; Digitalis Publishing / 15 Industry; July 8 2026; **Very Positive**, 87% of 159). Explicitly an homage to *GrailQuest, Sorcery!, Fighting Fantasy* — i.e. the exact lineage of our flagship. 150,000+ words, 20+ hrs, 300+ hand-drawn illustrations by one ex-Vanillaware artist (Nishimura) over six years; score by Hitoshi Sakimoto (*FF Tactics, Vagrant Story*). No generative AI ("a soul only found in something truly handmade"). This is the closest living relative to what we're building, done gorgeously — study it hard.

**What it does well (specifics):**

1. **The "magical tome on a study desk" diegetic frame — stronger than "the page is sacred."** The whole game *is* a book open on a desk, and the character sheet, stats, inventory, **dice, coins, and pencils are physically laid out on the desk beside the tome** — permanently visible, not hidden behind a menu button. It's the printed-FF ritual (photocopied Adventure Sheet + two d6 on the table) rendered literally. Reviewers single this out as the standout design.
2. **The frame is also a *story* device.** Reviewers praise moments where "the world of the book and the world of the study become blurred" — the desk/reader layer is diegetic *and* narratively active, not just chrome. A meta-frame with payoff.
3. **Living, emoting hero portrait.** Your chosen character *stands and animates beside the text*, reacting/emoting as the story progresses (Vanillaware-style). Enemy/ally portraits carry deliberate hand-drawn roughness (visible linework, imperfections) — the "handmade" look is a feature, and maps 1:1 onto our `veritas-gamebook` plate style.
4. **Class pick shapes the whole run + the ruleset.** Choose **Warrior or Mage** at start. Combat is dice-driven — hit resolved by roll, **damage = difference between winner's attack stat and loser's defense** (a margin-of-success damage model, richer than FF's flat "−2 STAMINA"). Warriors do basic attacks; **Mages cast spells that *bypass the initiative roll*** — class asymmetry expressed as a combat-rules difference, not just flavor.
5. **Three route types per encounter: combat / negotiation / evasion — all viable.** Not every gate is a fight; the same obstacle can be talked past, dodged, or fought. Choices + rolls fork the outcome.
6. **Humane death by design: rewind-to-before-the-fatal-encounter + save-anywhere.** On death you rewind to right before the killing blow; it openly "encourages replaying and save-scumming." This is exactly our **Rewind** save mode, validated by a Very-Positive audience.
7. **Two-run "zapping" replay (RE2-inspired).** Finish one character and it flips straight into the other's playthrough; the second run *sees the consequences of the first*, and **items you collected in run 1 disappear in run 2**. A built-in, mechanics-driven reason for the "branching second playthrough with new outcomes."

**Honest weaknesses (lessons for us):**
- **Too many "guess-and-die" decisions** — choices that kill with no fair signal. Our authoring validator + "conditional choices show their reason" rule must prevent blind-death gates (or gate them behind an explicit lethal-difficulty mode).
- **No signposting of whether a True Ending exists** — players couldn't tell if replay was worthwhile. We should make completion state / remaining-endings legible (ties into our Victory + Gallery screens).

---

## B. inkle — *Sorcery!* (deeper pass; supplements INSPIRATION §3.3-B3)

INSPIRATION.md already covers the hand-drawn 3D travel-map, effort-slider combat, editable "the story remembers" rewind, and spelling-as-magic. **New/sharper detail worth folding:**

1. **Spellcasting is a genuine sub-game with real numbers.** 48 spells, **each a 3-letter word**; the 6 common ones are cheap (**3 STAMINA**), advanced/situational ones **require a carried item** to cast. **Wrong spell → it fizzles and still costs STAMINA.** So the spellbook itself is a puzzle you *learn* (which letters, which context, which item) — memory + risk, not a menu pick.
2. **The spell UI evolved for a reason — a concrete design lesson.** v1 spelling was "line up letters through die-cut holes in the paper" — pretty but *fiddly, with no screen room for tutorial/among-context help*, so players had to memorize everything. v2 replaced it with the **"spell globe"**: a letter-covered sphere that's "basically a pretty touch keyboard," diegetic **but** with room for contextual hints. Takeaway: **diegetic-but-legible beats diegetic-but-fiddly** — build the beautiful version *with* affordances/tutorial space from day one.
3. **Combat narrated on the fly, spellcasting as a first-class alternative to melee** — the fight reads as prose that responds to how you played, and magic is a parallel resolution path, not a bolt-on.

---

## C. *The Life and Suffering of Prince Jerian* & *Sir Brante* (Schisma Games)

**What they are.** Narrative RPGs about a single life lived across chapters in a rigid, caste-divided dark-fantasy empire. **Sir Brante** = namesake of our `sir-brante` sepia-engraving art lane. **Prince Jerian** (Steam 2936290; Schisma / 101XP; July 20 2026) = same universe, "completely different story," new mechanics for a crown-prince role. Tags span Narrative RPG / Life Sim / Political Sim / Interactive Fiction / Choose-Your-Own-Adventure. These are the reference for **making choices feel *heavy and permanent*** — the opposite pole from Veritas's save-scum-friendly rewind, and a deliberate design tension for us to expose as a mode.

**What they do well (specifics):**

1. **The "Four Deaths" economy — death as a *spendable resource*, not just a fail-state.** In Brante you have **4 Deaths**; the 4th is a **True Death** you can't return from. A **Lesser Death** is often *chosen*: you spend a life to earn a "hearty boon" — stat jumps, reputation, or unlocking events/Destinies otherwise unreachable, plus unique post-death dialogue and a permanent mark. **Dying is a tactical decision with a budget.** This is a brilliant reframing of FF's brutal permadeath into something with agency.
2. **Chapter / life-path arc with stats that compound.** Childhood → Adolescence → Adult(hood) chapters; stats earned early **carry and derive forward** (adult stats are computed from chapter 1-2 choices), and they steer you toward one of several **mutually-exclusive life paths** (Noble / Priest / Lotless). Long-arc, front-loaded consequence: who you were as a child shapes what's *possible* as an adult.
3. **Willpower as a meta-currency for passing/boosting checks.** A pooled resource (range ~−10…30) spent to clear stat gates and to buy stat increases (e.g. a costly event trades 15 willpower for +1 stat). Makes "can I do this?" a budgeting decision, not a coin-flip.
4. **Stat- and relationship-gated choices with visible costs.** Options appear/unlock based on stats, allegiances, and remembered choices; **"characters remember every allegiance and choice"** — they can revere you or become your downfall. Reactive NPC memory as a core loop, not garnish.
5. **Jerian adds a faction/nation-management layer + sanity.** You balance **treasury, noble houses, clergy, and commoner unrest**; "every decision brings consequences, and your mistakes will be paid for by the entire Empire." A **sanity/psychological-degradation** track ties choices to the protagonist's mind. Non-linearity "develops gradually through chapters" (branches diverge more as you go — a deliberate ramp).
6. **Permanent, legible weight.** The whole pitch is that nothing resets: injuries, marks, allegiances, spent deaths all persist. Choices feel heavy because the game *never lets you take them back* (no rewind), and it tells you the cost up front.

**Honest weaknesses (lessons for us):**
- **"Willpower robs the player of agency"** (a common community critique): when a meta-currency gates *too much*, players feel the system, not the story. If we adopt a willpower-like pool, keep it a spice, not the main gate.
- **Hidden consequences / guess-the-designer** frustration also shows up here — same lesson as Veritas: consequence should be *foreshadowed*, even if not spelled out.

---

## D. Prioritized "fold into FF" list

Ranked within each group. **Legend:** 🟢 build for v1 · 🟡 v1 if cheap / else fast-follow · 🔵 mode/COULD · ⚪ skip or watch. Cross-refs to GDD sections in brackets.

### (a) SYSTEM ideas (mechanics / loops)

1. 🟢 **"Deaths economy" as a save-mode, not just Ironman/Bookmarks/Rewind** *(Brante).* Add a **"Chosen Death"** ruleset to our existing death/save modes [GDD §4]: the hero has a small budget of *lesser deaths*; spending one on a fatal outcome revives you (with a permanent mark/penalty) **and** grants a state boon or unlocks a gated branch — a final "true death" ends the run. It reframes FF lethality as agency, pairs perfectly with our `apply_delta()`/codeword engine (a death = a codeword + a boon delta), and it's *original framing*, not FF canon. **Highest-value single steal here.**
2. 🟢 **Margin-of-success damage as a per-book combat variant** *(Veritas).* Our data-driven rules layer [GDD §5] already supports per-encounter modifiers; add an optional damage model where **damage = attackStrength − defense** instead of flat −2. Keep faithful FF (flat 2) as default; expose the Veritas-style margin model as a ruleset flag for books that want crunchier fights. Directly answers INSPIRATION §5.6's "2d6 attrition feels thin."
3. 🟢 **Three-route encounters (fight / talk / evade) as a first-class encounter shape** *(Veritas, and FF's own tradition).* Make "negotiation" and "evasion" resolutions as authorable as combat in the encounter schema [GDD §5 Encounter], each with its own stat/roll gate. This is also the natural surface for the AI-DM's intent-routing (see (c)).
4. 🟡 **Spellbook-as-sub-game (spelling/known-spell puzzle) for a Mage archetype** *(Sorcery! + Veritas Mage).* An optional MAGIC track: a small set of **learnable, item-or-STAMINA-costed spells**, where **casting the wrong/uncontexted spell fizzles and still costs STAMINA**. Model spells as codeword-gated actions with a cost + effect. Class asymmetry (Warrior basic vs Mage bypass-initiative) becomes a ruleset, matching FF's own advanced-attribute pattern (MAGIC/FAITH) [INSPIRATION §2.5]. v1 if a spell archetype is in the shipped adventure; else fast-follow.
5. 🟡 **Compounding chapter/life-arc stats** *(Brante).* For our ~150-400-section adventure, allow **act/chapter boundaries where earlier choices derive later capabilities** (a "who you became" checkpoint that seeds stats/codewords for the next act). Fits the structured-DM's storylet model [GDD §9a] and gives long-arc weight without a full life-sim.
6. 🔵 **Faction/pressure meters + reactive NPC memory** *(Jerian).* A few tracked "pressure" gauges (e.g. faction favor / regional unrest) that choices nudge and later sections read. Our codeword/flag store already does booleans+counters [GDD §2.8]; this is presentation + a handful of counters. Great for the structured-DM's "tension/threat pacing." COULD for v1; strong for a political/kingdom adventure later.
7. 🔵 **Two-run "zapping" replay with carry-over consequences** *(Veritas).* Structured New-Game+ where a second playthrough (different class/hero) sees the world changed by run 1 and loses/keeps specific items. Leans on our tiny serializable GameState. A replay-value feature, not core — COULD.
8. ⚪ **Willpower-style meta-currency for checks** *(Brante).* Watch, don't build: community consensus is it can "rob agency." Our LUCK-drain already *is* FF's canonical spend-to-succeed resource; adding a second pool risks the same complaint. Skip unless a specific book needs it.

### (b) SCREEN / UX ideas

1. 🟢 **The "desk beside the tome" reading frame** *(Veritas).* Elevate the Book-Reading View [GDD §6.4]: render the Adventure Sheet, dice, coins/gold, and potions as **persistently-visible objects on the desk around the open book**, not just a HUD strip + a Sheet button. This is the printed-FF ritual made literal and is Veritas's most-praised idea — and it *is* our `veritas-gamebook` art lane. Highest-value UX steal. (Keep it responsive: desk on desktop/landscape, collapsible on mobile portrait.)
2. 🟢 **Living, emoting hero portrait beside the text** *(Veritas).* A standing character illustration that reacts to beats (wound, luck, dread) — even a few swappable expression plates per hero, driven by state, sells "alive." Feeds our `veritas-gamebook` + optional `nxdv_knight` hero plates [GDD §7]; register expression states as asset slots in the Studio manifest [GDD §10a].
3. 🟢 **Foreshadow consequences; make completion legible** *(Veritas + Brante lessons).* Two concrete UX rules: (i) never ship an *unsignalled* insta-death choice in default difficulty — lethal gates get atmospheric foreshadowing or a visible lock/reason [GDD §6.5]; (ii) the Victory/Gallery screens [GDD §6.13/6.15] should show endings-found / completion so players know replay is worthwhile. Cheap, and directly fixes the two flaws reviewers cite.
4. 🟡 **Diegetic-but-legible spell UI (the "spell globe" lesson)** *(Sorcery!).* If we build the Mage track, build the beautiful diegetic caster **with tutorial/contextual space from day one** — Sorcery! shipped fiddly (letters-through-holes) then had to rebuild. Don't repeat their v1. Fold into WIREFRAMES if the spell system is greenlit.
5. 🔵 **Sorcery!-style travel-map as the movement UI** *(Sorcery!).* Already a COULD in the GDD [§6.10, §13-COULD]; nothing changes — noting the deeper detail (day/night, route-plotting, map *is* movement) is confirmed and belongs in that optional mode, not the faithful default.
6. 🔵 **Chosen-Death moment screen** *(Brante).* If we adopt the Deaths economy (a.1), it needs its own beat: a somber "spend a death?" decision screen showing the cost (the mark/penalty) vs the boon — reuse the Death Screen [GDD §6.12] shell with a choice instead of a dead-end.

### (c) Pairs with our MP + AI-DM

1. 🟢 **Three-route encounters are the AI-DM's home turf** *(Veritas → GDD §9b).* The fight/talk/evade encounter shape (a.3) is exactly the "legal choices the structured DM exposes" that the AI-DM maps free-text intent onto ("I try to bribe the guard" → the negotiation route). Building encounters this way makes the AI-DM's intent-routing land on real, authored, engine-authoritative options — no hallucinated actions.
2. 🟢 **Reactive NPC/faction memory is shared, DM-narrated state** *(Jerian/Brante → GDD §9a).* "Characters remember every allegiance" is just codewords/counters the structured DM already owns; the **AI-DM narrates the *reaction* ("the Steward's jaw tightens — he has not forgotten the toll you refused")** while the engine owns the flag. In co-op, this state is part of the tiny authoritative GameState [GDD §8], so every player sees consistent NPC memory. High-value, low-risk (color over authoritative math).
3. 🟡 **Deaths economy + co-op = a party revive/sacrifice rule** *(Brante → GDD §8 co-op house rules).* FF ships no party combat rules; the "spend a death for a boon" mechanic gives co-op a natural, dramatic **downed-ally sacrifice/revive** rule (a teammate spends a lesser death to save the party, gaining the mark). Solves a real gap in our co-op design with a mechanic we're already adopting.
4. 🟡 **AI-DM narrates margin-of-success + Chosen-Death beats** *(Veritas → GDD §9b).* The richer combat math (a.2) and the death-spend moment (a.1) give the AI-DM meatier, state-grounded moments to dramatize in prose ("the blow lands wide of a killing stroke") — color on top of numbers the engine computes. Keeps the DM authoritative-safe.

---

## E. Top 5-8 to fold in (ranked, cross-group)

1. **"Desk beside the tome" reading frame** *(Veritas, b.1)* — the single most distinctive, on-brand UX win; it *is* our `veritas-gamebook` lane made literal. Persistent diegetic sheet/dice/coins around the open book.
2. **"Chosen Death" save-mode / deaths-as-resource** *(Brante, a.1)* — reframes FF lethality into agency; slots into our existing save-mode + `apply_delta`/codeword engine as original framing; also unlocks a co-op revive rule.
3. **Three-route (fight/talk/evade) encounters** *(Veritas, a.3 / c.1)* — richer play *and* the perfect surface for the AI-DM's intent-routing; makes the DM land on authored, authoritative options.
4. **Living, emoting hero portrait beside the text** *(Veritas, b.2)* — cheap "alive" factor, directly feeds our art pipeline + Studio asset slots.
5. **Reactive NPC/faction memory, DM-narrated** *(Jerian/Brante, c.2)* — codewords we already have; AI-DM narrates the reaction, engine owns the flag; consistent across co-op.
6. **Margin-of-success combat as a per-book variant** *(Veritas, a.2)* — fixes "2d6 attrition feels thin," faithful FF stays default; DM gets meatier beats to narrate.
7. **Consequence-foreshadowing + legible completion** *(Veritas/Brante lessons, b.3)* — cheap authoring/UX rules that fix the exact flaws reviewers flagged in both franchises.
8. **Spellbook-as-sub-game (diegetic-but-legible)** *(Sorcery!+Veritas, a.4/b.4)* — optional Mage track; if built, build the caster UI *with* affordances from day one (don't repeat Sorcery!'s fiddly v1).

**Honest skips:** a second **willpower-style meta-currency** (a.8) — redundant with LUCK-drain and community-criticized; the **generative/new-section DM** stays WON'T-for-v1 (GDD §13); **two-run zapping** (a.7) and **faction meters** (a.6) are good-but-later COULDs, not v1 blockers.

---

### Sources
- Veritas Tales — [Steam](https://store.steampowered.com/app/4508570/) · [RPG Site review](https://www.rpgsite.net/review/20875-veritas-tales-witch-dark-castle-review) · [Kotaku (Vanillaware artist)](https://kotaku.com/vanillaware-artist-moved-into-the-mountains-for-six-years-to-create-lush-love-letter-to-old-school-rpgs-2000715013) · [Shacknews preview](https://www.shacknews.com/article/149749/veritas-tales-preview-steam-next-fest)
- inkle *Sorcery!* — [inkle page](https://www.inklestudios.com/sorcery/) · [Postmortem (Game Developer)](https://www.gamedeveloper.com/business/postmortem-i-steve-jackson-s-sorcery-i-series-by-inkle) · [inklecast: combat/dice/maps](https://www.inklestudios.com/2016/02/10/inklecast-sorcery-special2.html)
- *Prince Jerian* — [Steam](https://store.steampowered.com/app/2936290/) · [Turn Based Lovers](https://turnbasedlovers.com/news/narrative-rpg-the-life-and-suffering-of-prince-jerian-invites-players-to-test-its-opening-chapter/)
- *Sir Brante* — [Gameplay wiki](https://the-life-and-suffering-of-sir-brante.fandom.com/wiki/Gameplay) · [Lesser death wiki](https://the-life-and-suffering-of-sir-brante.fandom.com/wiki/Lesser_death) · [Wikipedia](https://en.wikipedia.org/wiki/The_Life_and_Suffering_of_Sir_Brante)
</content>
</invoke>
