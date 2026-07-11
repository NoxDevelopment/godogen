# Top-Down Action Template

Top-down action base (Hotline-Miami-like), **pure first-party** — no vendored kit.
The roadmap survey found nothing permissive worth adopting for this genre, and the
core loop is cheap to build correctly, so everything here is plain Godot. Scaffold with:

```bash
python templates/tools/scaffold.py top-down-action <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins to track.

## What you get

- **Player** (`scenes/player.tscn` + `scripts/player.gd`): 8-directional
  `CharacterBody2D` movement (accelerate/friction), mouse aim (the `AimPivot`
  barrel tracks the cursor), **hitscan raycast shot** with a visible `Line2D`
  tracer and fire-rate cooldown, **dash** (burst + cooldown, i-frames while
  dashing), health with a post-hit grace window and respawn at the spawn point.
- **Three practice targets** (`scenes/target.tscn`): shootable dummies
  (`take_hit(damage, from)` contract), hit-flash, destroyed counter in
  `GameManager.flags["targets_destroyed"]`, HUD count.
- **Chaser enemy** (`scenes/enemy.tscn` + `scripts/enemy.gd`):
  `NavigationAgent2D` pathing over the arena's `NavigationRegion2D`, repaths to
  the player 4x/sec, deals contact damage on a cooldown, is itself shootable.
  It waits two physics frames before pathing (navigation maps sync on the first
  physics frame — query earlier and you get empty paths).
- **Arena** (`scenes/main.tscn`): walled 1152x648 room, hand-authored
  rectangular navigation polygon, HUD (HP + targets left), spawn point.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses
  (`default_bus_layout.tres`), `"player"` + `"persistent"` groups on the player,
  `"game_manager"` + `"persistent"` on the `GameManager` autoload,
  `save_data()/load_data()` on both, `"scalable_text"` on HUD labels, and the
  full **topdown input action set** (`move_up/down/left/right`, `attack` = LMB,
  `dash` = Space, `interact`, `inventory`, `pause` — keyboard + gamepad).

## Damage contract (the part worth understanding)

Anything shootable implements `take_hit(damage: int, from: Node)`. The player's
hitscan ray (`shot_mask` = world + enemies layers) calls it on whatever it hits
first; walls simply stop the ray. The enemy uses the same contract against the
player for contact damage. New destructibles: put them on physics layer 3
(`enemies`), implement `take_hit`, optionally join the `"targets"` group to be
counted by the HUD.

Collision layers: 1 = `world` (walls), 2 = `player`, 3 = `enemies`
(enemy + targets). The enemy collides with world/player/enemies; the player
with world/enemies.

## How to extend

1. **Levels**: duplicate `main.tscn`; keep one `NavigationRegion2D` per floor
   and re-author (or bake) its polygon around the new walls. Everything else is
   instance-and-place.
2. **Weapons**: `player._shoot()` is one hitscan — vary `shot_damage`,
   `shot_cooldown`, `shot_range`, or fork it into a projectile spawner. The
   `shot_fired(from, to, hit)` signal is where muzzle flash / shake / audio hook in
   (pair with the `game-feel` skill).
3. **Enemies**: `enemy.gd` is the chase archetype; subclass for shooters
   (raycast the player back) or patrollers (waypoint list before aggro). Give
   enemies `NavigationObstacle2D`s if they should avoid each other.
4. **Melee / throwables**: Hotline-Miami staples — melee is a short-range
   `take_hit` sweep off the same contract; throwables are RigidBody2D +
   `take_hit` on impact.
5. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged (buses and groups already match).
6. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   flat-color `Polygon2D` blockouts on purpose; replace with sprites, keep the
   collision shapes.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot exit 0 with zero script errors. Boot probe:

```
DEBUG: top-down-action core loop ready — player=true targets=3 enemy_chasing=true
```

(`enemy_chasing=true` = the NavigationAgent2D holds a live path to the player.)
The full shot loop was also exercised headless (scratch harness): one hitscan
took a target 3→2 HP; three destroyed it, updated the `"targets"` group count
and the `targets_destroyed` flag. The only log line is a benign engine notice
(Camera2D switching to physics interpolation mode).
