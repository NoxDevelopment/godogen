# Crowd Rush Template

Hypercasual 3D crowd-runner base (Count Masters / Crowd City lane-runner
structure), **pure first-party** — no vendored kit. The Wave-3 survey found no
maintained MIT crowd-runner kit to pin, and the genre is build-cheap: one
MultiMesh, phyllotaxis disc math, and count arithmetic are all plain Godot.
Scaffold with:

```bash
python templates/tools/scaffold.py crowd-rush <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable). No addons, no pins
to track.

## What you get

- **The crowd** (`scripts/crowd.gd` on the `Crowd` node, groups `"player"` +
  `"persistent"`): auto-runs forward along -Z at `run_speed`, steers
  horizontally with A/D-arrows or mouse-x (keyboard overrides the mouse until
  it moves again), leader clamped to the track width. Every unit is drawn by
  **one MultiMesh** (`scripts/formation.gd` builds it — capsule mesh, 400
  slots allocated once) in a phyllotaxis disc around the leader; growing is
  `visible_instance_count` + new units flowing outward from the leader,
  shrinking folds the disc inward. `apply_gate()`, `kill_units()`,
  `kill_unit_at()`, `set_count()` and `teleport_to()` are public — gates,
  obstacles, clashes, bots and the boot probe all mutate the crowd through
  the same routines. Count 0 = wiped, `died` ends the run. A floating
  `Label3D` shows the live count; the chase camera is a plain `Camera3D`
  child.
- **Gates** (`scripts/gate.gd`, group `"gates"`, four in `main.tscn` as two
  choice pairs): each panel carries an `operation` (`add`/`mul`) and
  `amount` — "+10", "-5", "x2" labels are derived, green = grows the crowd,
  red = shrinks it. The crowd's forward step hands every unconsumed gate
  `try_cross(prev_z, new_z, leader_x, crowd)`; the panel whose lane the
  **leader** is in applies once and consumes itself (its same-z partner
  stays live, so a pair is a real either/or). Visuals are code-built
  translucent panels + `Label3D`.
- **Spike-strip obstacle** (`scripts/obstacle.gd`, group `"obstacles"`): an
  AABB across part of the track. While the crowd's leader is inside
  `active_window` it hit-tests **every unit slot** against the box and kills
  the individual units sweeping through — the rest of the crowd flows on.
  The positions tested are the exact positions the MultiMesh renders.
- **Enemy crowd** (`scripts/enemy_crowd.gd`, group `"enemy_crowds"`): a
  blocking crowd in the same MultiMesh formation (red). When the two discs
  touch (`disc_radius` of both + padding), the run freezes and units
  annihilate **1:1** at `clash_rate` pairs/second until one side is empty —
  the bigger crowd survives with exactly the difference; a tie wipes both
  and ends the run. `clash_started` / `clash_ended` are the juice hooks.
- **Finish line + tower** (`scripts/finish_line.gd`): crossing the line
  compares survivors against `boss_count` — strictly more wins; score =
  surviving units. Code-built line strip, FINISH banner and a numbered end
  tower.
- **Run shell** (`scripts/main.gd`): crowd-count + distance HUD; finish or
  wipe pauses the tree and opens the **run summary**
  (`scripts/run_summary.gd`: win/lose, survivors vs tower, distance,
  best-survivors record; Enter or the button restarts). `last_run` /
  `best_survivors` / `best_distance` land in `GameManager.flags`.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"player"` +
  `"persistent"` groups on the crowd, `"game_manager"` + `"persistent"` on
  `GameManager`, `save_data()/load_data()` contracts (crowd saves count,
  distance, position), `"scalable_text"` on HUD/UI labels, `pause` action
  declared, the summary layer runs `PROCESS_MODE_ALWAYS`.

## The crowd MultiMesh (the part worth understanding)

There are **no unit nodes and no physics bodies anywhere** in this template.
A crowd is one `Node3D` (the leader) plus one MultiMesh; unit *i* lives at
`leader + slot_offset(i)` where `slot_offset` is the phyllotaxis (sunflower)
spiral — radius `spacing * sqrt(i)`, angle `i * golden_angle` — so the disc
stays evenly packed at any size, from 1 unit to the 400-slot capacity, with
zero repacking work. Growing/shrinking is `visible_instance_count`; per-slot
offsets lerp toward their formation target (`reform_speed`) so gained units
visibly pour out of the leader and survivors fold inward after losses.

Everything that "collides" is arithmetic against those same slot positions:
gates test the **leader's** lane at the crossing plane, the spike strip
AABB-tests each slot, the clash triggers on the two disc radii, the finish
tests the leader's z. That is what keeps 200+ units cheap — one
`_physics_process` writes `count` transforms per frame and nothing else
scales with crowd size. If you outgrow GDScript's transform loop (~thousands
of units), the shape to keep is the same and the loop moves to a shader or
C#; every caller already goes through `crowd.unit_position(i)`.

## How to extend

1. **Longer tracks**: stretch the `Track` mesh and place more `Gates`
   children / `Spikes` / `EnemyCrowd` nodes at descending z — every mechanic
   is self-contained on its node and finds the crowd by group. Procedural
   layout is a loop instantiating those scripts at spaced z values.
2. **More gate types**: gates are `operation` + `amount` — "x0.5", "-20",
   "+1" all work today. New operations (e.g. speed boosts) are one `match`
   arm in `crowd.apply_gate()` plus a label case in `gate.label_text()`.
3. **Moving obstacles**: give `obstacle.gd` a `_physics_process` position
   tween (side-to-side blade) — the AABB test already runs every frame, so
   moving hazards need no new collision logic.
4. **Fighting clashes**: the 1:1 drain is the arithmetic core; for the
   genre's brawl look, fling a unit pair per drain tick (spawn a one-shot
   tumbling capsule VFX at the contact edge) — keep the count math as is.
5. **Real runner meshes**: swap the `CapsuleMesh` in
   `Formation.make_unit_multimesh()` for your character mesh — one mesh
   shared by all units. Per-unit animation at scale = shader vertex
   animation (bake a run cycle into the material) rather than skeletons.
6. **Finish fights**: `finish_line.gd` emits `finished` with the counts —
   replace the instant comparison with a staged tower brawl by freezing the
   crowd (`running = false`) and draining against `boss_count` like the
   enemy clash does.
7. **Saving/menus**: godotsmith `save_system` / `menu_system` /
   `settings_system` drop in unchanged — crowd and GameManager already
   implement the `persistent` contract.
8. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   code-built primitives (panels, spikes, tower) — replace the builders,
   keep the AABBs and the single-MultiMesh constraint.

## Validation status

`status: "validated"` — scaffolded, `--headless --import` exit 0 with zero
errors, 120-frame headless boot (`--quit-after 120`) exit 0 with zero script
errors, probe byte-identical across 5 boots on 2 fresh scaffolds (the loop
has no RNG anywhere — runs are fully deterministic). Boot probe:

```
DEBUG: crowd-rush core loop ready — gates=[+10,x2] count=1->11->22 gate_math=true obstacle_kills=4 clash=18-12->6 clash_ok=true finish=win survivors=6 boss=5
```

(`count=1->11->22 gate_math=true` = real forward motion crossed the "+10"
then the "x2" gate in their lanes — `try_cross()` consumed each panel and
left its same-z partner live; `obstacle_kills=4` = the spike strip killed
exactly the 4 individual units whose slots swept through its AABB while the
crowd passed; `clash=18-12->6 clash_ok=true` = the enemy crowd froze the run
and 1:1 annihilation left exactly the difference; `finish=win` = 6 survivors
beat the tower's 5 and the summary + `best_survivors` flag landed.) The
probe compresses `run_speed`/`reform_speed`/`clash_rate` to fit the frame
budget — the mechanics are rate-independent. No warning lines: with no 2D
camera there is not even the Camera2D interpolation notice the 2D templates
carry.
