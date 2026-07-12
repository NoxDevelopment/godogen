# Dungeon Crawler Classic Template

Grid-based first-person dungeon crawler base (Lands of Lore: The Throne of
Chaos / Eye of the Beholder structure), **pure first-party** — no vendored
kit. The Wave-3 survey found no maintained MIT grid-crawler kit to pin, and
the genre is build-cheap once you see the trick: the whole "3D dungeon" is
grid math plus short tweens — the camera IS the party, stepped cell by cell
through geometry built in code from one ASCII map. Where `fps-classic` is
free movement + physics rays, this is the opposite lane: **no physics
anywhere** — movement, door bumps, lever pulls, pickups, combat reach and
enemy pathing are all grid queries, which is exactly why the loop is
headless-robust and fully deterministic. Scaffold with:

```bash
python templates/tools/scaffold.py dungeon-crawler-classic <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins
to track.

## What you get

- **The party as the camera** (`scripts/party.gd` on the `Party` Node3D,
  groups `"player"` + `"persistent"`): discrete cell-based movement —
  forward/back/strafe steps and 90° turns, each smoothed with a short tween
  (`step_time` / `turn_time` exports; hold a key to keep walking) — with a
  first-person `Camera3D` + torch `OmniLight3D` riding inside. Walking into
  a plain door bumps it open, into a locked door consumes a key (or
  refuses), into a wall or an enemy is blocked. `turn()`, `try_step()`,
  `warp_to()`, `attack()`, `use_potion()`, `interact()` and
  `take_enemy_hit()` are public — HUD buttons, hotkeys and the boot probe
  drive the same routines the input actions call.
- **Party of 3, front/back rows** (Lands of Lore style): two front-row
  fighters (range-1 melee) and a back-row caster whose spark bolt reaches 3
  open cells down the facing line and costs MP (slow regen ticks it back).
  Each member has HP/MP and a per-member attack cooldown; enemy melee
  always lands on the **first alive front-row member** — the back row is
  only exposed once both fronts are down. Rosters live in one
  `MEMBER_DEFS` constant: adding a member = one entry + a portrait panel.
- **Dungeon from an ASCII map** (`scripts/dungeon.gd`): a 14x13 starter map
  in the `MAP` constant — start room, corridors, a key room behind a plain
  door `d`, a lever room behind the locked door `D`, and a secret room
  behind `S` that only the lever `L` opens (intended loop: key → locked
  door → lever → secret). All geometry is code-built (floor + ceiling
  slabs, a wall box per solid cell that touches walkable space, thin door
  leaves oriented across the passage, lever prop, spinning pickups); doors
  and secret walls sink into the floor when opened. Doors, the lever and
  taken pickups write **GameManager flags** and restore themselves in
  `_ready`, so the dungeon stays solved across scene reloads.
- **Real-time grid enemies** (`scripts/enemy.gd`, one spawned per `E` map
  cell through `main.spawn_enemy()` — every death is a tracked kill): each
  occupies exactly one cell, steps toward the party on a move timer (greedy
  axis-priority chase that respects walls, closed doors/secrets, other
  enemies' occupancy and the party's own cell) and melees the front row on
  its own attack timer once cardinally adjacent — so enemies pour through
  doors only after you open them. `take_hit()` is the damage contract;
  `active` gates the AI while damage keeps working.
- **Items**: key and potion pickup cells collected on walk-over; the Drink
  button (R) heals the alive member with the **lowest HP** by 25.
- **Classic bottom-bar HUD** (`scripts/hud.gd`, the Lands of Lore anatomy):
  scrolling message log (RichTextLabel, auto-follow), three portrait panels
  — ColorRect placeholder portrait, name, HP/MP bars, per-member attack
  button (hotkeys 1-3) that dims on cooldown/no-MP/down — and a side column
  with the **compass** (N/E/S/W from party facing), keys/potions counters
  and kills. Buttons never take focus, so Space/Enter stay with interact
  and the summary.
- **Run shell** (`scripts/main.gd`): message routing, kill + secret-found
  bookkeeping into `GameManager.flags`, party wipe pauses the tree and
  opens the **run summary** (`scripts/run_summary.gd`: kills, secret found,
  best-kills record; Enter or the button restarts — world flags persist, so
  the reloaded dungeon stays solved).
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the party, `"game_manager"` + `"persistent"` on
  `GameManager`, `save_data()/load_data()` contracts (party saves
  cell/facing/members/keys/potions; GameManager saves flags),
  `"scalable_text"` on every HUD label/button, `pause` action declared, the
  summary layer runs `PROCESS_MODE_ALWAYS`.

## The grid illusion (the part worth understanding)

Everything is one 2D array. A cell is `Vector2i(x=column, y=row)`; facing is
an int 0-3 (N/E/S/W) mapping to a grid step in `DIRS` and a camera yaw of
`-facing * PI/2`. A "step" is: compute the target cell, ask the dungeon
`is_open()` (walls false, doors/secrets true only once opened) and
`occupant()`, then tween `position` to `world_pos(cell)`. A "turn" is a yaw
tween. That's the entire controller — there is no CharacterBody, no
collision shape, no raycast in the whole template. Combat reach is the same
query (front melee = occupant of the cell ahead; the caster's bolt scans up
to 3 open cells down the facing line and stops at closed doors), and enemy
chase is the same query from the other side. Because every mechanic is a
grid lookup plus a rate-independent timer/tween, the boot probe can
compress time (`cooldown_scale`, `step_time`) and the whole loop runs
byte-identically headless — the template contains **zero RNG**.

The map legend (`dungeon.gd` doc comment): `#` wall · `.` floor · `@` start
· `D` locked door · `d` plain door · `S` secret wall · `L` lever · `K` key
· `P` potion · `E` enemy spawn. Doors read their passage axis from their
solid neighbors; secret walls are drawn exactly like walls until the lever
sinks them.

## How to extend

1. **Bigger dungeons**: edit the `MAP` constant (or generate one — it is
   just strings). Keep the border solid, flank door cells with walls so the
   leaf reads, and give levers/'S' pairs a story. Multi-level = swap the
   MAP per scene (or make it an export) and warp the party to the new
   `start_cell`.
2. **More members**: add a `MEMBER_DEFS` entry and a `Member4` portrait
   panel (copy a panel node, add it to `_member_panels`, declare an
   `attack_4` action). Row semantics come free from the `"row"` field.
3. **More enemies**: `enemy.gd` is one chassis — exports for
   health/damage/timers/color make archetypes data (a fast weak rat, a slow
   heavy knight). Ranged enemies = copy the caster's line-scan from
   `party.attack()` into an `_attack` variant.
4. **More items**: pickups are one `match` in `dungeon.collect_pickup()` +
   a mesh in `_restore_or_place_pickup()` — add scrolls, gems, wall-slot
   items. Member-targeted use (LoL style) = pass an index into
   `use_potion()`-style routines from portrait clicks.
5. **Spinning-attack doors / buttons**: `try_bump()` is the wall-interaction
   funnel and `pull_lever_at()` the switch funnel — pressure plates, wall
   buttons and illusion walls are new cases on the same two functions.
6. **Game feel**: hook `dungeon.door_opened` / `secret_opened` (rumble),
   `party.member_changed` after hits (portrait flash), and add a small
   camera dip in `try_step`'s tween for head-bob — the signals are already
   emitted.
7. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — party and GameManager already
   implement the `persistent` contract.
8. **Art — the lol-vga style pack**: this template's art/style layer is
   deliberately a set of **Studio-bound slots** for the Lands-of-Lore VGA
   style pack: the bench refs `bench/lol-ui-frame-v2` (~75% — full LoL HUD
   anatomy: portraits, parchment, compass, slots) and `bench/lol-corridor-v2`
   (~65% — one-point-perspective torchlit corridor) are the targets, with
   `bench/lol-portrait-v2` feeding the portrait lane and the planned
   `nxdv_vga256` LoRA covering scene-level textures. The slots: the three
   HUD `Portrait` ColorRects (portrait paintings), the bottom-bar panels
   (UI frame), `dungeon.gd`'s wall/floor/ceiling/door materials (corridor
   texture set), and `enemy.gd`'s `_build_body()` (billboard sprites or
   models). Replace the builders, keep the grid queries — see
   `assetPlanHints` in the registry entry.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot (`--quit-after 120`) exit 0 with zero script
errors, probe byte-identical across 6 boots on 2 fresh scaffolds (the
template has no RNG at all — runs are fully deterministic), plus a 900-frame
soak with the surviving enemies live post-probe, zero errors. Boot probe:

```
DEBUG: dungeon-crawler-classic core loop ready — step_turn=(2,2)N->(3,2)E locked_bump=true key_picked=true locked_door=true lever_secret=true secret_walk=true melee_front=Aiden:40->32 attack_kill=true potion_heal=Aiden:32->40 kills=1
```

(`step_turn` = a real `turn(1)` + tweened `try_step(0)` from the `@` start
changed facing N→E and cell (2,2)→(3,2); `locked_bump` = walking into the
locked door without the key refused — door closed, party unmoved;
`key_picked` = stepping onto the key cell in the key room collected it via
the same arrival path every pickup uses; `locked_door` = the bump consumed
the key, the door opened and the party walked into the doorway cell;
`lever_secret` = `interact()` pulled the lever in the cell ahead and the
secret wall cell went walkable; `secret_walk` = the party stepped through
where the wall stood; `melee_front=Aiden:40->32` = the secret-room skeleton,
woken on compressed timers, walked two cells toward the party on its own
move loop and its melee landed on the first front-row member — row
semantics; `attack_kill` = three real `attack(0)` presses (the portrait
button's exact routine) killed it, tracked as a director kill;
`potion_heal=Aiden:32->40` = the secret room's potion was picked up on
walk-over and drinking it healed the lowest-HP member.) The probe hands the
two surviving spawn-cell enemies back to the dungeon (`active = true`) and
warps the party home — world state (opened doors, spent key, pulled lever)
stays, exactly as it would for a player. No warning lines: with no 2D
camera there is not even the Camera2D interpolation notice the 2D templates
carry. The art layer ships as blockout placeholders on purpose — the
lol-vga style pack (bench/lol-*-v2 refs + the planned nxdv_vga256 LoRA)
fills the Studio-bound slots listed in §How-to-extend #8.
