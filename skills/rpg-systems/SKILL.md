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
`fails=0`**: inventory stack/weight caps + add/remove math, faction tiers + `at_least`
gates, crafting station/skill/faction gates, **atomic** craft (a craft that can't
complete changes nothing), **determinism** (same op sequence → identical state), and a
save/load round-trip.

```bash
Godot --headless --path <proj> res://addons/nox_rpg/probe/rpg_probe.tscn
# => DEBUG: nox_rpg — inventory+crafting+factions … fails=0 => OK
```

## Status / roadmap (Immersion Engine P3)

Shipped: **inventory · crafting · factions** (the interlocking core). Follow-on P3/B7
systems to compose over the same store: **trading** (a merchant view over two inventories +
faction-priced), **jobs** (time-gated tasks that pay/rep), and **NPC schedules** (a
deterministic day/clock driving NPC location/activity). **Cutscene video** (LTX 2.3) is the
P4 GPU-gated piece.
