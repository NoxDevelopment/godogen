# Action Adventure 3D Template (Zelda-like dungeon, 3D)

A third-person **3D action-adventure** (Zelda-3D lineage) — the 3D-quest genre.
A sword-swinging hero explores a dungeon, fights enemies, finds a key, unlocks
the boss door, and beats the boss. Scaffold with:

```bash
python templates/tools/scaffold.py action-adventure-3d <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable), Forward+ renderer. Pure
first-party Godot, no addons.

## What you get

- **`GameManager` autoload** (`scripts/game_manager.gd`) — the quest + combat
  **state** as pure, seedable-free, headless-testable logic, with the dungeon's
  ordering rules **enforced in one place**:
  - **Hearts** (`player_hp` / `PLAYER_MAX_HP`) — `damage_player` / `heal_player`,
    and death when they hit 0 (`player_died`).
  - The **gated quest chain**: `collect_key()` → `try_open_door()` (succeeds
    **only with the key**) → `damage_boss()` (**refused until the door is open**)
    → defeating the boss **wins** (`quest_won`). You cannot skip a step.
  - `register_enemy_defeated()` tallies the room, `save_data()/load_data()`
    persist the whole run.
- **Third-person player** (`scenes/player.tscn` + `scripts/player.gd`) — a
  `CharacterBody3D` with world-relative movement under a **fixed follow camera**,
  a jump, a **sword swing** (a short-lived `Area3D` hitbox in front that damages
  any enemy it touches), and **lock-on** (`L` — face + strafe the nearest foe).
- **Enemies + boss** (`scenes/enemy.tscn` + `scripts/enemy.gd`) — chase the
  player, deal **contact damage** on a cooldown, and take sword hits; a normal
  enemy owns its HP and reports its death, the **boss** routes damage through
  `GameManager` (door-gated, wins the run when it falls).
- **The dungeon, built in code** (`scripts/world.gd`) — a lit room + boss chamber
  split by a **doorway divider**, a **key** pickup (`Area3D`), a **locked door**
  (a `StaticBody3D` that a keyed player opens by touching, then vanishes), the
  room enemies + the boss, and a **HUD** (hearts + a live objective line). The
  scene (`world.tscn`) stays a bare `Node3D` + script.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses; `GameManager` in the
  `"game_manager"` + `"persistent"` groups with `save_data()/load_data()`; the
  input map (`move_*`, `jump`, `attack`, `lock_on`, `pause`, `restart`);
  `"scalable_text"` on the HUD.

## The design (the part worth understanding)

Every rule that matters — hearts, the key/door/boss ordering, the win — lives in
`GameManager` and emits `state_changed`; the 3D world only reads that state and
drives the presentation (movement, camera, enemy AI, the door mesh). That split
is why the whole **dungeon quest is testable without rendering a frame**:
`reset_quest()`, then `collect_key()` / `try_open_door()` / `damage_boss()`
enforce the chain, and the world just visualises it.

## How to extend

1. **Real models**: swap the capsule player/enemy and box dungeon for GLBs
   (`3d-asset-pipeline` / `blender-bridge` normalise → GLB) and dungeon materials
   (the `dungeon-tile` seamless texture preset); keep the scripts.
2. **More combat**: add a shield/parry, a charged spin attack, or a bow — all
   hang off `player.gd`'s attack branch and new `Area3D` hitboxes; give enemies
   telegraphs + attack states in `enemy.gd`.
3. **More dungeon**: add rooms + more keys/doors by staging more `Area3D`
   pickups + `StaticBody3D` doors in `world.gd`; the gate rules generalise
   (make `has_key` a set of key ids).
4. **Camera**: the follow camera is deliberately simple — add mouse-look /
   right-stick orbit by driving a `SpringArm3D` yaw in `player.gd`.
5. **NPCs / story**: give the boss or a quest-giver a `companion-npcs` persona +
   Dialogue Manager for pre-boss lines.
6. **Menus/saving**: godotsmith `menu_system` / `save_system` / `settings_system`
   drop in unchanged; the run already serialises.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
script errors, and three headless probes:

- **Quest-engine probe** (pure `GameManager`, `fails=0`): reset shape; player
  damage → death (+ `player_died`, no damage after death); the **key→door gate**
  (door won't open without the key, an open door doesn't re-open); the **boss
  gate** (the boss can't be hit before the door is open) and the **win** (+
  `quest_won` + the `dungeons_cleared` flag); death stops all progress; and a
  `save_data()/load_data()` round-trip of hp/key/door/boss/enemies.
- **Scene smoke** (`world.tscn`): boots with zero script errors and prints its
  readiness (`enemies=2 boss_hp=8 …`).
- **3D integration probe** (`fails=0`): in the real scene the **player falls and
  lands on the floor** (y≈1.0), **2 room enemies + a boss** spawn, and driving
  the player through the dungeon **collects the key**, **unlocks the door** (real
  `Area3D` overlaps), and defeating the boss **wins the run** — the whole quest
  chain, end to end.
