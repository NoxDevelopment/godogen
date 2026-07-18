# RPG Systems (nox_rpg)

Opt-in, **deterministic** RPG gameplay systems for game templates — the Fugue-pattern
systems the **Immersion Engine** (spec P3) layers on: **inventory**, **crafting**, and
**faction reputation**, composed over one shared store. Pure `RefCounted` GDScript
(no scene-tree, no RNG) so every system is headless-testable and byte-reproducible —
the same discipline as `if-engine` and `nox_netcode`.

Drop the `nox_rpg` addon into any Godot template that wants RPG depth; the systems are
data-driven (items/recipes/tiers are JSON), so a game reskins them without code.

## The systems

| File | Class | Role |
|------|-------|------|
| `rpg_inventory.gd` | `RPGInventory` | id-keyed integer stacks with optional per-item **stack limits** + **weight** and a carry-weight cap. `add`/`remove` return the amount actually moved; `has_all`/`consume_all` are the atomic bundle ops crafting + trading build on. `save_data`/`load_data`. |
| `rpg_crafting.gd` | `RPGCrafting` | data-driven **recipes** (`inputs`→`outputs`) that can gate on a **skill level**, a **faction tier**, and a **station**. `craft()` is **atomic** — it checks inputs, requirements, and output space first, then consumes + produces, or changes nothing. |
| `rpg_factions.gd` | `RPGFactions` | integer **reputation** per faction with a named **tier ladder** (hated…exalted); `at_least(faction, tier)` is the gate other systems (recipes, merchants, quests) read. |
| `rpg_trading.gd` | `RPGTrading` | **faction-priced buy/sell** between a player and a merchant inventory (gold is the `"gold"` item). Buy prices scale by faction tier (friendlier = cheaper); merchant buys back at half base. Atomic. |
| `rpg_jobs.gd` | `RPGJobs` | **time-gated jobs** that pay gold/items + reputation on completion. Deterministic tick counter drives `progress()`; `complete()` pays out when `ready()`. |
| `rpg_schedule.gd` | `RPGSchedule` | **deterministic NPC daily schedules** — `activity_at(npc, hour)` → `{location, activity}`, hour-blocks that wrap midnight, home/idle fallback. The hook that drives ambient NPC life. |

## Data

`data/sample_items.json` (item catalog: stackMax + weight) and `data/sample_recipes.json`
(recipes with skill/faction/station gates) are worked examples — a template supplies its
own. Recipe shape:

```json
{ "forge_sword": {
    "inputs":  { "iron_ingot": 3, "leather": 1 },
    "outputs": { "iron_sword": 1 },
    "requires": { "skill": { "name": "smithing", "level": 2 },
                  "faction": { "id": "smiths_guild", "tier": "friendly" } },
    "station": "forge" } }
```

## Validation

Headless determinism probe (`probe/rpg_probe.tscn`) — **VALIDATED on Godot 4.6.1,
`fails=0` across 39 checks**: inventory stack/weight caps + add/remove math, faction tiers
+ `at_least` gates, crafting station/skill/faction gates, **atomic** craft (a craft that
can't complete changes nothing), **determinism** (same op sequence → identical state), a
save/load round-trip, **trading** (faction-priced buy/sell + not-enough-gold degrade),
**jobs** (tick → ready → pay gold/items/rep), and **NPC schedules** (working/tavern/
midnight-crossing sleep + home fallback).

```bash
Godot --headless --path <proj> res://addons/nox_rpg/probe/rpg_probe.tscn
# => DEBUG: nox_rpg — inventory+crafting+factions … fails=0 => OK
```

## Status / roadmap (Immersion Engine P3)

Shipped + validated (Godot 4.6.1, probe `fails=0`): **inventory · crafting · factions ·
trading · jobs · NPC schedules** — the full non-GPU P3 systems set, all deterministic and
composing over the shared inventory store. Remaining: **cutscene video** (LTX 2.3), the P4
GPU-gated piece.
