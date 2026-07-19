# FPS Classic Template

Doom/Quake-style arena shooter base (fast run-and-gun), **pure first-party**
— no vendored kit. This is deliberately NOT another COGITO template: the
registry's `fps-immersive` and `horror-fps` are the slow immersive-sim lane
(full inventory/interaction stack, pinned to Godot 4.5 by COGITO), while
`fps-classic` is the fast lane — movement tech, hitscan/projectile weapons
and enemy pressure, first-party GDScript on the current 4.6 pin with nothing
COGITO drags in. Scaffold with:

```bash
python templates/tools/scaffold.py fps-classic <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins
to track.

## What you get

- **Quake-ish controller** (`scripts/player.gd` on the `Player`
  CharacterBody3D, groups `"player"` + `"persistent"`): WASD + mouselook
  (click captures the mouse, `pause` releases), sprint, and the classic
  movement core — ground friction + Quake accelerate, air acceleration with
  the small **air-speed cap** that produces real air control and strafe-jump
  gain, and **held-jump auto-hop** that skips the landing-frame friction so
  bunny-hops keep their speed. Health + armor with Quake-style absorption
  (`armor_absorb` of every hit eaten while armor lasts), and
  `apply_knockback()` so rocket splash shoves the player — self-splash
  included, which is the rocket jump. `take_damage()`, `add_health()`,
  `add_armor()`, `face_point()` are public — enemies, pickups and the boot
  probe drive the same routines gameplay uses. Every accel/friction number
  is an export: the fast feel is tuning, not hardcode.
- **Two arena weapons** (`scripts/weapons.gd` under the camera): a
  pellet-spread **hitscan shotgun** (8 pellets, seedable spread RNG, one
  ray per pellet against world|enemies) and a **projectile rocket launcher**
  (see below), on shared ammo pools with per-weapon cooldowns, hold-to-fire,
  and switching (Q cycles, 1/2 direct). `fire()`, `switch_to()`,
  `add_ammo()` are public; a color-coded blockout viewmodel shows the held
  weapon. Adding a weapon = one more `WEAPONS` dictionary entry.
- **Ray-swept projectiles** (`scripts/projectile.gd`, shared by both sides):
  flight is a per-physics-frame ray sweep — no physics body, never tunnels,
  robust headless. Player rockets (mask world|enemies) deal direct damage
  plus **distance-falloff splash** and knockback around the impact; enemy
  plasma bolts (mask world|player) are the same script with
  `splash_radius = 0`.
- **Code-built arena** (`scripts/arena.gd`): 40x40m floor, 5m perimeter
  walls, four cover pillars, and a ramp up to a raised platform holding the
  rocket-ammo perch — all `BoxMesh` + `BoxShape3D` pairs from one
  `_add_box()` helper on layer 1 `"world"`.
- **Item spawners** (`scripts/item_spawner.gd`, four in `main.tscn`:
  health/armor/shells/rockets): spinning color-coded pickups collected on
  walk-over (distance-checked, no Areas), that **refuse pickups the player
  can't use** (full health rejects a medkit, Quake style) and count a
  `respawn_time` countdown before popping back. `try_give()` is public.
- **Two enemy archetypes** on a shared chassis (`enemy_base.gd`: capsule
  body built in code, health + `take_hit` contract, gravity, `active` AI
  gate, and **raycast-feeler chase steering** — straight at the player when
  clear, bent 40° around world geometry otherwise; no navigation bake, so it
  is robust headless and in generated levels): the **melee rusher** sprints
  in and claws on a cooldown, the **ranged shooter** holds a preferred band
  and fires plasma bolts gated by a line-of-sight ray.
- **Wave director** (`scripts/wave_director.gd`): escalating waves (wave n =
  n+1 rushers + n shooters) at fixed ring points, alive/kill bookkeeping,
  next wave armed on clear. `spawn_enemy()` and `start_next_wave()` are
  public — everything that enters the arena goes through the director, so
  probe and scripted kills are real tracked kills.
- **Run shell** (`scripts/main.gd`): health/armor/ammo/kills/wave HUD +
  crosshair; death pauses the tree and opens the **run summary**
  (`scripts/run_summary.gd`: kills, wave reached, best-kills record; Enter
  or the button restarts). `last_run` / `best_kills` / `best_wave` land in
  `GameManager.flags`.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the player, `"game_manager"` + `"persistent"` on
  `GameManager`, `save_data()/load_data()` contracts (player saves
  health/armor/position/ammo/held weapon; GameManager saves flags),
  `"scalable_text"` HUD labels, `pause` action declared, the summary layer
  runs `PROCESS_MODE_ALWAYS`.

## The movement + combat core (the part worth understanding)

The controller is the three Quake functions, exported: ground frames run
`friction` then `accelerate` (speed along the wish direction gains
`accel * wish_speed * delta`, capped at `wish_speed`); air frames run the
same accelerate but cap the wish speed at `air_speed_cap` (~1 m/s). That cap
is the whole trick — pushing forward mid-air barely adds speed, but pushing
*sideways* while turning re-aims the entire velocity vector, which is air
control, and gains a little per jump, which is strafe-jumping. Holding jump
re-jumps on the landing frame *before* friction is applied, so hops chain
without losing speed. Change the feel by tuning exports, not by rewriting
the loop.

Combat never uses physics contacts: shotgun pellets, projectile flight,
enemy line-of-sight and the chase feeler are all `intersect_ray` against the
three named layers (1 world, 2 player, 3 enemies), and pickups/melee are
distance checks. That is why the whole loop runs headless and why the boot
probe can drive it deterministically — the only RNG in the template is the
shotgun spread, and it is seedable (`main.set_seed()`).

## How to extend

1. **More weapons**: add a `WEAPONS` entry in `weapons.gd` — hitscan needs
   `pellets/pellet_damage/spread_deg/reach`, projectile weapons set
   `"projectile": true` and configure their own `_fire_*` (copy
   `_fire_rocket()`; a grenade is a rocket with gravity added in
   `projectile.gd`). Declare a `weapon_3` action for direct select.
2. **More enemies**: extend `enemy_base.gd` and implement
   `_move(delta, player)` — the chassis provides body, health, gravity,
   feeler steering and the `active` gate. A Doom-style projectile spread or
   a circling strafer are `_move` variants; bosses are stat exports.
3. **Bigger arenas**: `arena.gd` is one `_add_box()` list — generate or
   hand-place more geometry on layer 1 and every ray (pellets, feelers,
   LOS) keeps working. Reposition `Waves` SPAWN_POINTS and the `Items`
   spawners to match.
4. **Wave design**: composition lives in `start_next_wave()` (count
   formulas) — per-wave enemy stats, boss waves every 5th, or timed spawns
   are edits to that one function; `spawn_enemy()` stays the single entry
   point.
5. **Game feel**: hook `weapons.fired` (camera kick), `player.took_damage`
   (hurt flash/shake), `projectile.exploded` (explosion VFX/decals) and
   `waves.enemy_killed` (kill pops) — the signals are already emitted.
6. **Deathmatch bots**: the player API is bot-complete — `face_point()` +
   `weapons.fire()` is exactly what the probe does; give enemies
   `take_damage`-style armor and item use for full arena bots.
7. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — player and GameManager already
   implement the `persistent` contract.
8. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   code-built primitives (arena boxes, capsule enemies, spinner pickups,
   box viewmodel) — replace the builders, keep the layers and the
   ray-based combat.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot (`--quit-after 120`) exit 0 with zero script
errors, probe byte-identical across 8 boots on 2 fresh scaffolds (the only
RNG is the seeded shotgun spread — runs are fully deterministic), plus a
900-frame soak exercising wave 1 combat (rusher melee, shooter bolts) with
zero errors. Boot probe:

```
DEBUG: fps-classic core loop ready — shotgun_kill=true rocket_splash=34 weapon_switch=rocket_launcher armor_pickup=50 melee_hit=hp100->96/armor50->42 health_pickup=true respawn_fired=true kills=1
```

(`shotgun_kill=true kills=1` = a director-spawned rusher died to one real
`weapons.fire()` shotgun blast — 8 seeded pellet rays, tracked as a real
director kill; `rocket_splash=34` = after `switch_to(1)`, a rocket aimed at
the floor 1.6m beside a shooter damaged it through the distance-falloff
splash only (the direct ray never touched it); `armor_pickup=50` = walking
onto the armor spawner consumed it via `try_give()`;
`melee_hit=hp100->96/armor50->42` = a rusher's own claw loop landed 12
damage and the armor absorbed its 66% share (8), health ate 4;
`health_pickup=true respawn_fired=true` = the health spawner consumed
(health was below max) and its respawn countdown — compressed to 0.15s, the
mechanics are rate-independent — fired and the item popped back.) The probe
hands its two surviving test enemies back to the arena (`active = true`) so
they join wave 1, which spawns after the boot window on purpose
(`first_wave_delay` 3s > the 2s probe). No warning lines: with no 2D camera
there is not even the Camera2D interpolation notice the 2D templates carry.
