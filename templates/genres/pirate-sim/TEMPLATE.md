# Pirate Career Sim Template (age-of-sail, systemic)

An **age-of-sail pirate CAREER SIM** in the lineage of *Sid Meier's Pirates!*, but
with **deeper, fully-systemic** mechanics: sail a seeded Caribbean, trade a live
supply/demand economy, duel + board ships, juggle four rival nations' standing, keep
a crew from mutiny, grow a captain across a bounded career, and **retire into a
ranked score**. Scaffold with:

```bash
python templates/tools/scaffold.py pirate-sim <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot, no
addons.

## KEY DESIGN DECISION — a pure deterministic TICK model (no physics nodes)

A career sim is a web of interlocking **economic + combat + reputation** systems, not
a real-time arcade game, so `PirateEngine` is a pure `extends RefCounted`
`class_name` with **no Godot-node dependency and no physics server**. The whole
career is a deterministic sequence of **DAY** ticks — sail / trade / fight / careen /
divide-plunder / retire — where every price, wind, broadside, boarding roll, mutiny
check and rival move is a pure function of the engine state + **one seeded RNG** whose
state is part of save/load. Given a seed and a fixed action sequence (a human's
inputs, or an auto-play policy) the **entire** career — the world map, the economy
drift, every duel, the final retirement rank — is **100% reproducible + byte-identical
on replay**. A `MAX_CAREER_DAYS` cap plus "every action costs ≥1 day" bounds the
career, so the sim **always terminates** in a **WIN** (retire at/above a rank) or a
**LOSS** (ship sunk with no reserves / crew mutiny / retire below the rank threshold).

## The ten interlocking systems (all real formulas — no stubs / no hardcoded winner)

- **World** — a seeded map of **16 ports across 4 rival nations** (Crown / Empire /
  Republic / Company), each with a position, owner, wealth tier, garrison, and a full
  **per-good local economy**.
- **Sailing + wind** — travel between ports costs **days** via a deterministic wind
  model: the prevailing bearing rotates each day, and sailing downwind is fast while
  hard upwind is slow (navigation skill eases the penalty). The same weather also sets
  sea-combat initiative (the **weather gauge**).
- **Trade economy** — **6 goods** (sugar / tobacco / cloth / rum / spice / ivory) with
  per-port supply/demand **prices on a real scarcity curve** (`base ·
  clamp((demand/stock)^elasticity)`). Buying/selling **moves the local price** (unit-by-
  unit **price impact**), and prices **drift back** to equilibrium over time — so
  cross-port **arbitrage is emergent + profitable**, never scripted.
- **Sea combat** — a deterministic **turn-based ship duel**: maneuver each turn for the
  **wind gauge** (the holder fires first + dictates range), fire broadsides whose damage
  scales with **cannons × gunnery × range × a salvo roll**, and pick **round / chain /
  grape** shot to wreck **hull / sails / crew** → resolve to **sink / flee / board**,
  bounded by a turn cap.
- **Boarding** — a deterministic **crew-vs-crew melee** from crew count × morale ×
  captain **fencing** → capture the ship + cargo, or get repelled (and maybe overrun).
- **Nation reputation** — a **4-nation standing vector**; attacking a nation lowers its
  standing and lifts its **sworn enemy's**; **Letters of Marque** sanction privateering
  (patron gains, no piracy penalty; raiding your patron voids the marque); very low
  standing makes a nation's ports **hostile** (they spawn warship hunters).
- **Crew & morale** — periodic **wages**, daily **food**, and **plunder shares**; a
  hard life at sea bleeds morale, an unmet payroll bleeds it faster, and at the mutiny
  threshold the **crew mutinies and the career ends**. Dividing plunder + shore leave
  restore it.
- **Captain progression** — **fame / gold / land grants**; four **skills**
  (navigation / gunnery / fencing / wit) that improve with use; **aging** across a
  bounded career → a **retirement rank** computed from the final score.
- **Treasure / quests** — seeded **treasure-map fragments** (found in prizes) assemble
  into a map you **dig** for a windfall, plus a **bounded ordered quest chain**
  (deliver / bounty steps) that pays fame + gold.
- **AI rivals** — rival pirate captains sailing, trading (arbitrage gold), and
  clashing under the same deterministic rules, rising + falling in fame.

## What you get

- **`PirateEngine`** (`scripts/pirate_engine.gd`, ~1,000 lines) — the pure engine, no
  Godot-node dependency, fully headless-testable. Every rule — world gen, the pricing
  curve + price impact + drift, the wind + travel model, the broadside + boarding
  solvers, the reputation/marque logic, wages/morale/mutiny, skills + fame + ranks,
  quests/treasure, the rivals — lives here and is **pure**. `is_legal()` rejects
  illegal actions; `to_dict()/from_dict()` + `career_checksum()` save the whole career
  and prove determinism. Three deterministic **auto-play policies** (`trade`,
  `reckless`, `neglect`) drive a whole career to a WIN or a LOSS with no UI.
- **`GameManager` autoload** (`scripts/game_manager.gd`) — owns one `PirateEngine` and
  adds the **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; the `"game_manager"`
  + `"persistent"` groups with `save_data()/load_data()` (the whole career persists —
  world, economy, ship, cargo, crew, reputation, skills, quests + RNG); `pause` +
  `restart` input; `"scalable_text"`.
- **Port map** (`scenes/port_map.tscn` + `scripts/port_map.gd`) — the play surface built
  in code: the seeded map (ports coloured by nation + the player + a wind arrow) drawn
  via `_draw()`, plus the **captain** panel (gold/fame/land/morale/skills/reputation),
  the **ship** panel, a **trade** panel (per-good buy/sell + a quantity slider +
  Buy/Sell), the **port list** (sail with the shown day-cost), a **combat** panel
  (the encounter + Sink/Cripple/Board stance buttons), **crew & career** actions
  (divide plunder, shore leave, recruit, dig treasure, retire), an **Auto-Step** demo,
  and a log.

## The engine (the part worth understanding)

Keep `PirateEngine`, call `sail_to()` / `buy()` / `sell()` / `attack(stance)` /
`divide_plunder()` / `retire()`, and read `net_worth()` / `final_score()` /
`career_checksum()`. Because it is pure it is fully playable + testable with **no UI**
and **drops in as the career/economy core of a larger game**. All tuning is explicit
constants at the top of the file (sea size + port count, the goods + pricing curve,
the wind, the combat + boarding constants, wages/morale, ranks, the quest chain, the
ship archetypes), so it is auditable and easy to re-balance.

## How to extend

1. **More ports / goods**: grow `NUM_PORTS`, `GOODS`, or the ship archetypes — the
   pricing curve and the auto-play route finder pick them up automatically.
2. **Real characters**: give each nation governor + rival captain a `companion-npcs`
   persona + voice (tavern rumours, marque offers, pre-duel taunts).
3. **Deeper fleets**: the capture hook already seizes cargo — extend it to keep prize
   ships and sail a **squadron**, or a shipwright to upgrade hull/sails/cannons.
4. **Land war**: `garrison` + hostile-port logic is present — add port **sieges** and
   governorships on top of the reputation vector.
5. **Art**: swap the flat map dots + text panels for a real sea chart, ship sprites,
   and port cards (recipes: ship/port icons via `qwen-icon`, a sea-chart backdrop via
   `zit-txt2img`, rival portraits via `card-creature-art`).
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the career already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --editor --import` exits 0 with zero
script errors + all vars typed, and **six headless probes** (all `fails=0`):

- **Economy** — supply/demand pricing spreads across ports (producers cheap, consumers
  dear); buying **raises** the local price + selling **lowers** it (price impact); a
  real buy-low/sail/sell-high **arbitrage route is profitable**; a fleeced market
  **drifts back** to equilibrium.
- **Determinism** — the same seed reproduces a **byte-identical** career (identical
  FNV-1a checksum over quantized state), both mid-career and at the end, **across
  processes**; a different seed diverges; world-gen is seeded.
- **Sea combat** — broadsides deal damage, duels are **bounded** by the turn cap, both
  **sink and board** are reachable across matchups, round/chain/grape hit the right
  subsystem (hull/sails/crew), and a fixed matchup is **deterministic**.
- **Reputation** — attacking a nation lowers its standing + lifts its enemy's; a marque
  sanctions attacks on the patron's enemy (and raiding the patron voids it); the
  offer/accept is gated by standing; very low standing makes ports hostile.
- **Career** — the deterministic auto-play reaches a **WIN** (retire at "Corsair
  Captain"+) **and** a **LOSS** (ship sunk with no reserves; crew mutiny); every career
  **terminates** under the day cap; actions are rejected after the end.
- **Rules/UI/save-load** — illegal actions rejected (sail with no crew, buy over
  cargo/gold, sell more than aboard, attack with no encounter); the port-map scene
  builds its code UI (a CanvasLayer + labels + buttons + a slider + option buttons);
  a mid-career save → mutate → load equals the snapshot.
