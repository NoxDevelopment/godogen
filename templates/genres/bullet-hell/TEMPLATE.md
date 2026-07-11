# Bullet-Hell / Shmup Template

Bullet-hell base on **BulletUpHell** (Dark-Peace). Scaffold with:

```bash
python templates/tools/scaffold.py bullet-hell <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). BulletUpHell is vendored
from the `Demo-V4.4` branch at a pinned commit — that is the repo's default branch
and the maintained Godot-4 line (plugin version 4.4; release tags stop at 4.2.3),
so do not re-pin without re-validating.

## What you get

- **BulletUpHell wired end to end**: the `Spawning` autoload (pooled, shape-based
  bullets living in one shared `Area2D`), the editor plugin registering the
  SpawnPattern / BulletPattern / SpawnPoint custom node types, and the addon's
  default bullet art/animations.
- **One arena** (`scenes/main.tscn`): walled 1152x648 playfield with
  - a **bullet definition** (`BulletProps/StandardBullet`, id `"standard"`):
    140 px/s, dies after 10 s or when leaving the play box;
  - a **spawn pattern** (`Patterns/RingPattern`, id `"ring"`): `PatternCircle`,
    12-way ring, infinite iterations, one volley every 0.8 s;
  - a **spawner** (`Spawner/SpawnPoint`): fires `"ring"` from boot
    (`auto_start_on_cam = false` so it also runs headless), 64-bullet pool.
- **Player ship** (`scenes/player.tscn` + `scripts/player.gd`): 8-directional
  movement clamped to the arena, held-`dash` **focus slowdown** (shmup staple),
  a deliberately small hurtbox (6 px circle + white core dot), 3 lives with
  blink-invulnerability and respawn, all hit detection through
  `Spawning.bullet_collided_body`.
- **HUD**: lives + live bullet count (reads `Spawning.poolBullets.size()`).
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the ship, `"game_manager"` + `"persistent"` on the
  `GameManager` autoload, `save_data()/load_data()` on both, `"scalable_text"`
  on HUD labels, topdown input action set baked into `project.godot`.

## How BulletUpHell is wired (the part worth understanding)

Bullets are **not nodes** — they are pooled physics shapes inside a shared
`Area2D` managed by the `Spawning` autoload. Three id-keyed pieces cooperate:

1. **BulletPattern node** (`BuHBulletProperties.gd`) registers bullet *props*
   under an id (`"standard"`), then frees itself.
2. **SpawnPattern node** (`BuHPattern.gd`) registers a *pattern* (`PatternCircle`
   resource: `bullet` id, `nbr`, `iterations`, cooldowns) under an id (`"ring"`).
3. **SpawnPoint node** calls `Spawning.spawn(self, "ring", "0")` — `"0"` is the
   default shared area shipped inside `Spawning.tscn`.

What bullets can hit = the shared area's `collision_mask`. `main.gd` sets it to
the player layer (2) at boot; bodies in group **"Player"** (capital P — addon
convention) auto-despawn bullets that touch them, and every touch also emits
`Spawning.bullet_collided_body`, which `player.gd` uses for damage. The ship is
additionally registered as the `"Player"` **special target**
(`Spawning.edit_special_target`), which is what homing patterns aim at.

Two quirks handled for you:

- Custom `BulletProps` sub-resources serialized by hand need a valid packed
  `__data__` header (`PackedByteArray(255, 255, 255, 255, 0, 0, 0, 0)` = packed
  empty dict); without it every editor import floods `packed_data_container`
  errors. The skeleton's `main.tscn` carries it — copy that block when adding
  bullet types by hand (adding them in the editor inspector does it for you).
- Vendoring applies four pinned patches to `Spawning.tscn` stripping stale
  upstream texture UIDs (the repo commits no `.import` files, so fresh imports
  mint new UIDs and the committed ones warn on every boot).

## How to extend

1. **More bullet types**: duplicate the `StandardBullet` node, give it a new
   `id` and tweak the `BulletProps` sub-resource (speed, homing_*, spec_*).
2. **More patterns**: add SpawnPattern nodes with `PatternLine`, `PatternOne`,
   `PatternCustomShape` (draw the Path2D curve) resources; point a SpawnPoint at
   each id. The addon's `ExampleScenes/` demo all seven pattern types.
3. **Bosses/waves**: a boss is a moving `Spawner` with several SpawnPoints and a
   `TriggerContainer` sequencing them; wave scripting = enabling SpawnPoints
   (`active`) over time from a wave manager.
4. **Player shots**: fire a second shared area (`Spawning` supports several) with
   a mask of the enemy layer, or plain Area2D projectiles — enemy counts are low.
5. **Menus/saving**: godotsmith `menu_system` / `save_system` /
   `settings_system` drop in unchanged.
6. **Art**: see `assetPlanHints`; bullet visuals swap via `animState` resources
   on the BulletProps (`anim_idle` etc.), ship/spawner are Polygon2D blockouts.

## Validation status

`status: "validated"` — scaffolded (bootstrap import + deferred plugin enable),
`--headless --import` exit 0 with **zero script errors**, 240-frame headless
boot exit 0. Boot probe:

```
DEBUG: bullet-hell core loop ready — spawner=true player=true active_bullets=12
```

(12 = the first ring volley live in `Spawning.poolBullets`.) The bullet→player
damage loop was also exercised headless (scratch harness): parking the ship in
the ring's path dropped lives 3→2 via `bullet_collided_body`. Remaining log
lines are engine shutdown accounting from the addon's bullet pooling
(`65 RID allocations of type 'GodotShape2D' were leaked at exit`, ObjectDB /
resources-in-use notices — present with the bare addon too, exit code 0, not
script errors; same class as Popochiu's NavRegion2D note in Wave 0).

## Vendored addon notes

- License: MIT (`addons/BulletUpHell/LICENSE.md`, manifest in `addons/LICENSES.md`).
- Docs: https://dark-peace.nekoweb.org/docs/bullet-up-hell/ (install + API);
  in-addon `ExampleScenes/` cover pattern types, cooldowns, homing, triggers.
- The addon self-registers the `Spawning` autoload when the plugin is enabled;
  the skeleton also bakes it into `project.godot` so headless runs work before
  the editor ever opens the project.
