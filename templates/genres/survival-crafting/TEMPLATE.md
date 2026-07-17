# Survival Crafting Template (Don't Starve / Valheim-lite gather / craft / survive, 2D)

A Don't-Starve / Valheim-lineage **survival-crafting** game run as a **deterministic
fixed-timestep sim**: gather wood/stone/food from seeded resource nodes, **craft** tools +
a campfire + cooked meals, manage **hunger / warmth / health** across a **day-night cycle**
(night is cold — keep a fire lit), and survive N days. It is OUR OWN engine with generic
content (no trademarks) — a pure, seedable, deterministic engine. Scaffold with:

```bash
python templates/tools/scaffold.py survival-crafting <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). Pure first-party Godot,
no addons.

## What you get

- **`SurvivalEngine`** (`scripts/survival_engine.gd`) — a pure `RefCounted` engine with ZERO
  Godot-node dependency and ZERO `Time` calls. One seeded RNG places the world + drives events,
  so a whole playthrough replays **byte-identically** from a seed:
  - **A seeded world** of resource nodes (trees → wood, rocks → stone, berry bushes →
    food + fiber) that **deplete** on harvest and **regrow** over time.
  - **An inventory + a crafting system** — recipes with resource costs and an optional fire
    requirement: **axe** (faster wood), **campfire** (a warmth source), **meal** (better
    hunger restore), **shelter** (a night warmth bonus).
  - **Campfires** that burn **fuel** down (refuelable with wood) and provide **warmth** within
    a radius.
  - **A day-night cycle** where **night is cold** (warmth drains fast unless near a lit fire)
    and hunger drains always; a **health** model that bleeds when hunger OR warmth hit 0 and
    slowly regenerates when both are healthy; **death** (health 0) vs a survive-all-days **win**.
  - **`checksum()`** — an FNV-1a fold over quantized needs + world state — the cross-process
    determinism proof.
  - `save_data()` / `load_data()` snapshot the **entire** run including RNG state.
- **A heuristic survival auto-seat** — eat/cook when hungry, build + refuel + huddle at a
  campfire before/through the night, craft an axe, and gather whatever it's short on.
  `auto_step()` / `auto_play_to_end()` run a whole playthrough.
- **`GameManager` autoload** — steps the sim in real time (one tick/frame interactive,
  multi-tick autoplay), plus the NoxDev save/load ABI.
- **Play surface** (`scenes/survival_view.tscn` + `scripts/survival_view.gd`) — the world of
  resource nodes, campfires with a night **warmth-glow**, the player, a day/**night tint** that
  deepens after dusk, and a health/hunger/warmth + inventory HUD. **WASD** move · **E** harvest
  · **Q** eat · **X/C/V/B** craft · **F** refuel · **T** autoplay · **R** restart.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; a node-free engine.

## The engine (the part worth understanding)

Every rule — world generation, node depletion/regrow, the recipe/crafting system, campfires +
fuel + warmth radius, the day-night needs model, health, and the survival auto-seat — lives in
`SurvivalEngine` as pure data + functions stepped by `tick(input)`. The view only renders state
and forwards a move + one-shot action, which is why the whole run is playable and testable with
**no UI**, and why it **drops in as the survival core** of a bigger open-world game: keep the
engine, feed a `{move, act, target}` dict per tick, read `pos` / `nodes` / `inv` / `health`.

The design centre is the **day-night survival loop**: the whole game is the tension between
spending daylight gathering + crafting and being ready — with a lit fire and food — when the
cold night comes. Because the world is seeded, every run is reproducible, which lets NoxQA
smoke-run the survival AI through a full week headlessly and diff the checksum.

## How to extend

1. **A crafting menu + hotbar + structure placement**: surface the recipe tree and let the
   player place campfires/shelters where they choose.
2. **Threats at night**: add monsters that spawn in the dark and avoid firelight (the fire
   radius is already the safe zone).
3. **Biomes + more resources + a tech tree**: extend `_gen_world` + `RECIPES` into tiers
   (stone tools → metal → structures).
4. **Temperature + seasons + weather**: modulate warmth decay by season/rain (the warmth model
   is the hook).
5. **Farming + taming**: plant crops that grow over days; tame an animal companion.
6. **Base building + storage**: chests, walls, and a base the fire defends.
7. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system` drop in
   unchanged; the whole run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero script errors
(all vars typed, first try), a **40-frame headless main-scene smoke** runs clean, and the
headless **determinism + playability probe** (`_probes/determinism_probe.tscn`) passes
(`PROBE PASS`):

- **seed determinism** — the same seed played to a terminal twice yields an identical final
  `checksum()`; a **different seed places a different world**.
- **partial determinism** — 500 ticks of the same seed produce an identical checksum across runs.
- **the full loop works** — the survival AI **crafts an axe + a campfire** and **survives all
  the days** with health left, proving gathering, crafting, the fire/warmth system, the
  day-night needs, and the win condition. Validated: the AI **survives to day 9 at full health**
  (axe crafted, a campfire kept lit).

Run it yourself:

```bash
/c/godot/godot --headless --path <skeleton> --import
/c/godot/godot --headless --path <skeleton> res://_probes/determinism_probe.tscn
# → DEBUG full_chk=<n> won=true day=9 health=100 axe=true fires=1 wood=10
# → PROBE PASS
```
