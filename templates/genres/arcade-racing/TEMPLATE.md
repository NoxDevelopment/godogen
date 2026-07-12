# Arcade Racing Template

Arcade racing base on **Godot-Easy-Vehicle-Physics** (GEVP) plus first-party
checkpoint/lap race logic. Scaffold with:

```bash
python templates/tools/scaffold.py arcade-racing <target-dir> --name "Game Name"
```

Engine pin: **Godot 4.6.x** (validated on 4.6.1-stable).
Kit pin: `DAShoe1/Godot-Easy-Vehicle-Physics` **main @ `c392257f`** (2025-08-17,
MIT) — upstream publishes no release tags, so the pin is branch@SHA.
Script-only addon (no editor plugin to enable).

## What you get

- **GEVP arcade car** (`addons/gevp/scenes/arcade_car.tscn`, instanced in
  `scenes/main.tscn`): ray-cast wheels, torque-curve engine, automatic
  gearbox, suspension, slip — the "arcade" tuning preset of the addon's four
  (arcade / simcade / drift / monster truck; swap the instanced scene to
  change handling).
- **VehicleController** (addon) with its exported input-map names rebound to
  the NoxDev action set: `throttle` (W/RT), `brake` (S/LT), `steer_left`/
  `steer_right` (A/D + stick), `handbrake` (Space), `shift_up`/`shift_down`
  (E/Q). Clutch and transmission-toggle are disabled (blank string = feature
  off, an addon convention).
- **Chase camera**: the addon's follow camera (`camera.gd`) targeting the car.
- **Race logic, first-party** (`scripts/race_manager.gd` on the Main node):
  - three ordered checkpoint gates (`scripts/checkpoint.gd`, Area3D relays —
    gates are dumb, ordering lives in the manager as the child order of
    `Checkpoints`);
  - a start/finish line that **arms the lap timer** on first crossing and
    **completes a lap** when re-crossed with all gates passed in order;
  - lap / best-lap timing (best lap recorded to
    `GameManager.flags["best_lap_time"]` → picked up by godotsmith's
    save_system);
  - signals `checkpoint_passed(index, total)` and `lap_completed(lap, time)`
    for game-feel/audio hooks;
  - HUD: lap, lap/best time, next gate, speed (from `vehicle.speed`) + gear.
- **Blockout track**: 600x600 m ground plane, translucent-free box gates laid
  out as an L (straight to gate 1, right turns onward) — deliberately minimal;
  real track layout is a world-layout pass.
- **NoxDev template ABI**: `Master`/`Music`/`SFX` buses, `"game_manager"` +
  `"persistent"` on the GameManager autoload, `save_data()` contract,
  `"scalable_text"` HUD labels, `pause` action declared.

## Wrong-order handling (the part worth understanding)

`race_manager._on_gate_crossed` ignores any gate that isn't
`_gates[next_gate]` — driving backwards or cutting the track can never
advance the lap. A lap only counts when the start/finish line is crossed with
`next_gate == _gates.size()`. To add gates: add Area3D children (with
`checkpoint.gd`) to `Checkpoints` in racing order — nothing else changes.

## How to extend

1. **Track**: replace the ground plane with real track geometry (keep
   collision layer 1 `world`); reposition the gates along the racing line.
   GEVP handles slopes/jumps — it's a ray-cast vehicle, not a kinematic hack.
2. **Handling**: `vehicle.gd` exposes ~60 tuned exports (steering assists,
   torque curve, per-axle tire grip). Start from the other presets
   (`simcade_car.tscn`, `drift_car.tscn`) before hand-tuning.
3. **Opponents / AI**: GEVP vehicles are input-driven (`throttle_input`,
   `steering_input` floats) — an AI driver is a script that writes those from
   a path follower instead of the VehicleController. The Wave-2 survey notes
   TheDuckCow's road-generator for track + lane-following AI when you need it.
4. **Timing extras**: sector splits fall out of `checkpoint_passed`; ghost
   laps = record `vehicle.global_transform` per physics tick during a lap.
5. **Engine audio**: instance `addons/gevp/scenes/engine_sound.tscn` under the
   car (RPM-pitched loop; it ships a 4000rpm sample).
6. **Menus/saves**: godotsmith drop-ins fit the ABI unchanged.

## Validation status

`status: "validated"` — scaffolded (addon vendored at the pin),
`--headless --import` exit 0 with zero errors, 900-frame headless boot exit 0
with zero script errors. Boot probe (probe holds `throttle` programmatically):

```
DEBUG: arcade-racing vehicle ready — vehicle=true wheels=true gates=3 start_finish=true
DEBUG: arcade-racing checkpoint crossed — gate=1/3 lap=0 lap_time=3.13s
```

(the car accelerates from the grid, crosses the start/finish line — which
arms the timer, hence `lap_time` > 0 — and triggers gate 1's ordered
crossing ~3 s in; a clean log otherwise.)
