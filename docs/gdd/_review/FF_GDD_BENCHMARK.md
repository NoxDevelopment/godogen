# FF-Gamebook GDD — Brutal Benchmark vs. Professional GDDs

**Reviewer stance:** adversarial. The job here is to find where our GDD falls short of
what shipped studios actually put in a design doc — not to reassure. Read it as a to-do
list, not a report card.

**What we measured against.** Six real documents from the Studio GDD Library
(`godogen/docs/inspiration/ff-gamebook/GAMESCRYE_GDDS.md`), read in full (text extracted
locally; the scanned ones rasterized and read page by page):

| Doc | What it is | Why it's the right yardstick |
|---|---|---|
| **Planescape: Torment — "Last Rites" packet** (v1.5, 47pp) | Vision + narrative bible + art manifesto | Closest genre cousin: prose-and-choice-driven RPG |
| **Metal Gear Solid 2 — "Grand Game Plan"** (Kojima, 38pp) | Theme-as-system + exhaustive character bible | The gold standard for theme driving every system |
| **Diablo — Condor pitch** (1994, 8pp) | Lean concept → greenlight | The most *production-complete* short doc: scope, schedule, monetization |
| **Grim Fandango — puzzle document** (LucasArts, ~71pp) | Single-discipline content spec | Gold standard for branching/puzzle-graph communication |
| **Claw — Design Bible** (Monolith, ~100pp) | Full buildable production bible | Gold standard for encounter + asset + balance specs |
| **"Silent Hill 2" — reconstruction** (student, 60pp) | The canonical GDD *template* | Cleanest example of the textbook section set |

> Note on fairness: **none** of the six carried a formal risk register, KPIs, or a
> budget. Those live in producer docs, not the design doc. Where our gaps below overlap
> that convention, they're flagged as lower-severity — except where our own stated
> ambition (all-in-v1) makes the omission genuinely dangerous.

---

## The verdict in one paragraph

Our GDD is an excellent **vision + rules + screen-inventory** document — genuinely
stronger than most of the six on faithful mechanics, accessibility, and reuse discipline.
But it is a **design *intent* doc pretending to be near buildable**, and it has almost
nothing of the two things that make the exemplars professional: (1) **actual content** —
not one sample section, monster stat block, encounter, or branch map exists, and for a
gamebook the content *is* the game; and (2) a **production spine** — no milestones, no
Must/Should/Could/Won't, no cut line, no owners, against an "all-in v1" scope that is the
riskiest thing in the document and is never risk-managed. Grim Fandango speced 80 puzzles
with solutions; Claw speced 14 levels with per-enemy stat+asset bundles; Diablo shipped a
12-month Gantt in an 8-page pitch. We ship zero of that.

---

## Coverage scorecard

Legend: ● strong · ◐ partial/thin · ○ missing

| Professional element | Our GDD | Best exemplar for it |
|---|---|---|
| Vision / pillars | ● | MGS2, Deus Ex |
| Core rules stated as exact numbers | ● (better than most) | (ours leads) |
| Accessibility as design | ● (better than all six) | (ours leads) |
| Reuse-first asset pipeline | ● (better than all six) | (ours leads) |
| Screen inventory | ● (17 screens, described) | Claw |
| System data model | ◐ | Claw |
| **Balance / economy / enemy tables** | ◐ (combat only) | Claw, SH2 |
| **Level / encounter / content specs** | ○ | Grim Fandango, Claw |
| **Narrative bible / world / characters / theme** | ○ | Planescape, MGS2 |
| **Branch/puzzle map & solvability spec** | ◐ (named, not drawn) | Grim Fandango |
| **UI wireframes / per-screen states / flow map** | ◐ (prose, no mockups) | SH2, Diablo |
| Technical design depth / budgets | ◐ | MGS2, Diablo |
| **Production: milestones / scope tiers / cut line / owners** | ○ | Diablo, MGS2 |
| **Audience / market / positioning** | ◐ (IP stance only) | Planescape, Diablo, SH2 |
| Art bible (style guide, not just sourcing) | ◐ | Planescape, MGS2 |
| Audio design | ◐ (one line) | MGS2 |
| Risk register | ○ | (none of the six — but see Gap 6) |
| Success metrics / KPIs / playtest protocol | ◐ (checklist, no measures) | (none of the six) |

---

## Ranked gaps (worst first)

### 1. No production spine — and an "all-in v1" scope with no cut line
**Severity: critical.** §12 lists "open decisions," which is not a plan. There are **no
milestones, no Must/Should/Could/Won't tiers, no named cut line, no owners, no schedule.**
Meanwhile the locked decisions commit v1 to: SP + hotseat + net co-op + LAN + AI DM + a
*dual* DM system + 4 save modes + 17 screens + ~150–400 sections + a bespoke art LoRA lane.
That is three or four products.

- **Who does it better:** the **Diablo** pitch — 8 pages — still carries a **12-month
  Gantt** with staggered Design/Art/Programming/Sound lanes, dependency order (Interface →
  DRLG → Structure → Testing/Balance) and reserves "at least 4 months of bug testing and
  play balance." **MGS2** opens with a dated schedule (Nov '98 → Winter '01) and
  **segments scope by player type** (existing vs. new → different chapters).
- **Fix:** add a Production section. MoSCoW the feature list; draw the phased ladder
  (SP+hotseat = Must/v1; net co-op+LAN = Should; AI DM = Could/fast-follow — which §12.3
  even hints at but never commits). Name the cut line in writing. Add a milestone table
  (prototype → vertical slice → content-complete → feature-lock → gold) with an exit
  criterion each. Assign an owner per system.

### 2. Zero content — no sample section, encounter, monster, or branch map
**Severity: critical (for this genre specifically).** For a gamebook the content *is* the
product, yet the GDD contains not one authored section, not one monster stat block, not one
encounter, not one worked branch. §10 promises "one complete original adventure" and stops.

- **Who does it better:** **Grim Fandango** specs **80 puzzles, each with a mandatory
  "Solution:" block**, grouped into dependency clusters annotated by shape ("three linear
  chains of length 2"), with per-Year location node-maps pinning cast to rooms. **Claw**
  specs **14 levels, each enemy as a production bundle** — Logic name, Image Set, animation
  frame counts, Health/Smarts/Damage attributes, and level-designer deployment notes.
- **Fix:** add a Content section with (a) a **vertical-slice section table** (5–10 real
  sample sections with prose + choices + effects), (b) an **enemy roster** with SKILL/
  STAMINA/modifiers stat blocks, (c) a **branch/flow diagram** of the slice, and (d) a
  worked "true path" showing codeword gating. Even 10 real sections would move this from
  intent to spec.

### 3. No narrative bible — no world, no characters, no theme, no plot
**Severity: high.** The GDD nails the *mechanics* of branching but defines **zero story**.
"NoxDev's own world (no FF IP)" is asserted; nothing about that world, its cast, its theme,
or its plot exists. A branching-narrative game with no narrative bible is a car with no
engine.

- **Who does it better:** **Planescape's "Mangy Cast"** gives full illustrated bios for 7
  allies + 4 antagonists — each with want/need, a 3-adjective voice, and in-character
  quotes — and states its central conceit *as a mechanic* ("the game is the character
  generator"). **MGS2** leads with **theme** ("what do we leave our children"; "every
  character lies once") and engineers systems to serve it.
- **Fix:** author a Narrative & Branching doc (template now in the library): logline,
  1–3 themes, world rules, principal cast (want/need/voice/arc), a continuity ledger, and
  the branch structure pattern (Ashwell). This is also what the AI DM in §9 needs as its
  canon — right now the AI DM has no world to be authoritative about.

### 4. Balance is combat-only — no enemy tables, economy, or difficulty tuning
**Severity: high.** The core combat math is exact and excellent (see strengths). But that's
the *only* number. There is no enemy roster with values, no economy (where Gold/Provisions
come from and drain to), no difficulty model, no probability analysis (win-rate vs. enemy
SKILL, expected LUCK depletion over a run), and no tuning plan.

- **Who does it better:** **Claw** tabulates **per-move damage in both Normal and Easy
  modes**. **Silent Hill 2** carries **weapon-property matrices** (range, blow-sequence,
  magazine size, rate-of-fire) and splits difficulty into two independent axes (riddle vs.
  enemy) — and even kills a known stamina exploit by design.
- **Fix:** add balance tables to the Systems doc — enemy roster, economy in/out, a
  difficulty model (the four save modes are not a difficulty model), and a short
  probability sanity-check on the combat/LUCK curves.

### 5. Screens are described but never drawn — no wireframes, states, or flow map
**Severity: medium-high.** §6's 17-screen inventory is genuinely good — better than most of
the six at *enumerating* screens. But it's all prose: **no wireframe/mockup, no per-screen
state spec** (empty / loading / error / first-time), and **no flow-map diagram**.

- **Who does it better:** **Silent Hill 2** uses the professional triad — **flowcharts +
  numbered functional requirements + mock-up screens** — plus a full controller map.
  **Diablo** hand-drew its isometric grid and town/dungeon layout right in the pitch.
- **Fix:** add wireframes (even ASCII) for the load-bearing screens (Reading View, Combat,
  Adventure Sheet, Roll-Up), a screen flow-map diagram, and a states line per screen. The
  UX/UI & Screens template now in the library has the skeleton.

### 6. No risk register — and the biggest risk (over-scope + AI-DM authority) is unmanaged
**Severity: medium (elevated by our own ambition).** None of the six had a formal register,
so this isn't a "pros always do it" gap — but our scope makes it one anyway. The two live
risks — (a) all-in-v1 over-scope, and (b) the AI DM mutating game state / breaking the win
condition — are the load-bearing risks of the whole project and get one reassuring sentence
("engine-authoritative") rather than a mitigation plan with triggers.

- **Who does it better (in spirit):** **MGS2** turns competitive weakness into a documented
  trade-off ("we will *not* pursue cinematic visuals; cap models at 1,500 polys to spend the
  budget on 300 on-screen enemies") and even runs a **cultural-risk analysis of its
  antagonist**. That's risk thinking embedded in design.
- **Fix:** add a short risk register (risk / likelihood / impact / mitigation / trigger /
  owner) covering over-scope, AI-DM authority, netcode NAT traversal, and content-authoring
  throughput. Ours can be five rows; it just has to exist.

### 7. No audience / market / positioning section
**Severity: medium.** §1 has an IP stance but no target audience, no platform/pricing/
lifecycle, and — despite citing inkle and Tin Man Games in the *inspiration* doc — **no
competitive feature-comparison** in the GDD itself.

- **Who does it better:** **Planescape's "Management & Marketing Realities"** (.357 Bullet
  Points — the reviewer-facing hooks, feature counts, license angle). **Diablo's** whole
  MARKETING section modeled monetization on Magic: The Gathering. **SH2** has a Market
  Analysis with a defined 13–25 demographic and a feature-comparison table.
- **Fix:** add an Audience & Market section: who it's for, platforms/pricing/lifecycle, and
  a feature-comparison table vs. Sorcery!/80 Days/Gamebook Adventures naming our wedge.

### 8. Art bible and audio are sourcing plans, not direction
**Severity: medium.** §7's reuse ladder is a real strength on *where assets come from* — but
there's no **style guide** (palette, composition rules, what "on-model" means for the hero,
character/prop/environment language), and audio is one line (music + SFX from the library)
with no per-state music intent, adaptive rules, or VO/TTS spec.

- **Who does it better:** **Planescape's Team Vision Statement** *is* a style filter
  ("don't draw a sailing ship — replace the sails with cobwebs, the hull with a ribcage").
  **MGS2** specs per-character audio hooks (Fortune's saxophone; the Female Ninja recorded
  with three actors to keep identity ambiguous).
- **Fix:** add a one-page art style guide and an audio-intent table (music per state:
  menu/explore/tension/combat/death/victory; SFX families; the honest-dice audio moment).

---

## What our GDD does genuinely well (don't lose these)

These are places we **beat the exemplars** — keep them as-is:

1. **Exact rules up front.** SKILL 1d6+6, STAMINA 2d6+12, LUCK 1d6+6; combat = 2d6+SKILL
   each side, 2 STAMINA per wound; the never-exceed-Initial invariant enforced centrally.
   Most of the six were *prose-only* on their systems (Planescape, MGS2 both). Ours is
   specified tightly enough to build the combat loop from.
2. **Accessibility treated as design, not polish** (TTS, dyslexia-friendly scalable type,
   settings-gated rerolls, four save modes for different player temperaments). **None** of
   the six exemplars did this at all.
3. **Reuse-first asset discipline** — the rung-3-before-rung-6 ladder and the explicit
   "a plan that's all rung-6 is a failed plan." The exemplars all assumed bespoke art;
   ours has a real production-cost instinct baked in.
4. **One serializable state object doubling as save + net-sync + replay** (§5, §8) is a
   genuinely strong technical instinct — cleaner than the exemplars' implicit approaches.
5. **Clear pillars and a stated "parity bar" for done** (§1, §11) — the vision discipline
   MGS2 preaches, applied honestly.
6. **IP-safety stance stated up front** — a real-world constraint the classics never had to
   consider, handled cleanly.

---

## The one-line ask

Our GDD is a strong **Full GDD skeleton with a great rules core**. To reach professional
grade it needs three child docs it currently only gestures at — a **Narrative & Branching
bible** (Gap 3), a **Content/encounter spec with a vertical slice** (Gaps 2, 4), and a
**Production plan with a cut line** (Gap 1) — plus wireframes (Gap 5) and a five-row risk
register (Gap 6). Templates for every one of these now live in the Studio GDD Library
(`Noxdev-Studio/docs/gdd-templates/`).
