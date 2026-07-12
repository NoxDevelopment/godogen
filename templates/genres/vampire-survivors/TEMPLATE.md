# Vampire Survivors-like Template

Auto-attack swarm roguelite base (Vampire-Survivors-like), **pure
first-party** — no vendored kit. The Wave-3 survey found no clearly-maintained
MIT swarm/horde kit to pin (BulletUpHell — already in the registry for
bullet-hell — covers dense *projectile* patterns, not enemy swarms), and the
genre's core loop is build-cheap: a swarm loop, pooled projectiles/gems, and a
data-driven upgrade table are all plain Godot. Scaffold with:

```bash
python templates/tools/scaffold.py vampire-survivors <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins
to track.

## What you get

- **Auto-attacking survivor** (`scenes/player.tscn` + `scripts/player.gd`):
  WASD movement; the weapon fires itself on a timer at the nearest active
  enemy in `weapon_range` (nearest-enemy targeting via the spawner's query).
  Projectiles are pooled first-party `Polygon2D`s advanced in the player's
  loop — no physics bodies. `fire_at_nearest()` is public (the timer's own
  routine) so bots/probes can drive the weapon directly. Health with post-hit
  grace; death emits `died` (no respawn — this is a roguelite).
- **Enemy swarm director** (`scripts/enemy_spawner.gd`, group
  `"enemy_spawner"`): timed waves spawn in an off-screen ring around the
  player and scale in count (+2/wave), speed (+3 px/s per wave, capped) and
  health (+1 every 3 waves). Every active enemy is moved by **one**
  `_physics_process` loop with pooling — see below. Contact damage on a
  per-enemy cooldown; `max_active` (240) caps the swarm. `spawn_wave()` /
  `spawn_enemy_at()` are the director/boss hooks; `set_seed()` for
  deterministic rings.
- **XP gems + magnet** (`scripts/gem_manager.gd` + `scenes/xp_gem.tscn`):
  every kill drops a pooled gem where the enemy died; gems idle until the
  player's `magnet_radius` reaches them, then fly in and feed
  `player.gain_xp()` — same pooled single-loop pattern as the swarm.
- **Level-up flow** (`scripts/level_up_ui.gd` + `scripts/upgrade.gd`):
  the upgrade pool is data-driven — every `Upgrade` .tres in
  `resources/upgrades/` (ships damage / fire rate / move speed / magnet
  radius / max HP) is scanned at boot; new upgrades are new files, zero code.
  On level-up the UI pauses the tree and offers 3 distinct picks (click or
  keys 1-3, `choice_1..3` actions); multi-level XP bursts queue one pick at a
  time. `choose(i)` is the programmatic entry point.
- **Run shell** (`scripts/main.gd`): survival timer + kill counter + HP +
  level/XP HUD; death pauses the run and opens the **run summary**
  (`scripts/run_summary.gd`: time/kills/level, best-kills record; Enter or
  the button restarts). `last_run` / `best_kills` / `best_time` land in
  `GameManager.flags`.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the player, `"game_manager"` + `"persistent"` on
  `GameManager`, `save_data()/load_data()` contracts (player saves stats,
  level, XP, position), `"scalable_text"` on HUD/UI labels, `pause` action
  declared, pause-shown UIs run `PROCESS_MODE_ALWAYS`.

## The swarm loop (the part worth understanding)

Enemies and gems are **not** physics objects and have **no per-node
process**: `enemy.tscn` / `xp_gem.tscn` are a `Node2D` + `Polygon2D` holding
data (`hp`, `speed`, `damage`, `value`, `active`), and the spawner / gem
manager each move *all* of their active nodes in one `_physics_process` over
a flat array — straight chase toward the player, distance checks for contact
damage, magnet flight, and pickups. Dead nodes go back to a pool
(`visible = false`, `active = false`) instead of being freed, so the hot loop
never allocates. That single-loop-plus-pool shape is what keeps 200+ enemies
(and the projectile/gem counts that come with them) cheap; it is also the
shape to keep when you extend — new behavior belongs in the director loops
(or a new manager with the same pattern), not in per-enemy scripts.

Weapon targeting and projectile hit-tests both run through
`spawner.nearest_enemy(pos, max_dist)` — a linear scan that is fine at this
scale. If you push far past `max_active`, swap its internals for a spatial
grid without touching any caller.

## How to extend

1. **Upgrades**: drop new `.tres` files in `resources/upgrades/` — pick a
   `stat` handled by `player.apply_upgrade()`, or add a new `match` arm there
   for new stats (projectile count, pierce, area). Weapon *unlocks* fit as a
   `stat` that flips a player flag.
2. **Enemy variety**: tint/scale via extra `spawn_enemy_at()` args, or give
   the spawner a wave table (Array of dictionaries: count/speed/hp/scene) —
   elites are just bigger numbers plus a multi-gem drop in
   `_on_enemy_killed`.
3. **More weapons**: copy the `fire_at_nearest()` + pooled-projectile pattern
   into a second fire timer (orbiting or AoE weapons can skip projectiles and
   distance-check the spawner's actives directly, iso-arpg nova style).
4. **Gem tiers**: `spawn_gem(pos, value)` already takes a value — map elite
   kills to bigger values and tint via `xp_gem.gd`.
5. **Meta progression**: `GameManager.flags` already records
   `best_kills`/`best_time`; spend a currency flag on permanent stat boosts
   applied in `player._ready()`.
6. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — player and GameManager already
   implement the `persistent` contract.
7. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   `Polygon2D` blockouts; replace with sprites, keep the pooled node shape.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot (`--quit-after 120`) exit 0 with zero script
errors, stable across repeated runs. Boot probe:

```
DEBUG: vampire-survivors core loop ready — wave_size=6 auto_kill=true kills=1 xp_collected=true level_up=[fire_rate] applied=true
```

(`wave_size=6` = the first timed wave spawned on the first physics frame;
`auto_kill` = the auto-weapon's own `fire_at_nearest()` routine killed a
close-spawned enemy — targeting, projectile flight, `take_hit`, pool return;
`xp_collected` = the dropped gem magnet-flew to the player and fed
`gain_xp()`; `level_up=[...] applied=true` = a forced level-up went through
the real pausing 3-choice UI and the chosen upgrade measurably changed the
player stat. The offered upgrade varies per run — the pick is random.) The
only log line is the benign Camera2D physics-interpolation notice also
present in top-down-action and iso-arpg.
