# Camera Rigs

Godot 4 camera rig scaffolds: `Camera2D` for platformers and top-downs, `Camera3D` for third-person and first-person, plus screen-shake mixin and bounds clamp. Each rig is a self-contained `.tscn` + `.gd` you can drop into a scene and parent to your player. Pure text — no ComfyUI / Tripo3D / model dependencies.

## TL;DR

```bash
python3 .claude/skills/camera-rigs/tools/camera_gen.py {rig|shake|bounds|list} [opts]
```

## Why this skill exists

Every Godot project rebuilds the same camera patterns from scratch:

1. **Smooth follow with deadzone** — pinch-perfect for platformers but the math (lerp factor vs. damping vs. spring) is fussy enough that agents usually copy a hard-tuned version from an old project.
2. **Bounds clamping** — keep the camera inside a level rectangle so it doesn't show the void at edges. `Camera2D.limit_*` works for 2D but the 3D equivalent is a manual clamp every `_process()`.
3. **Screen shake** — universally needed and universally re-implemented as a one-off, usually wrong (additive shake on top of follow drifts unless decoupled into a `RemoteTransform2D` or a `shake_offset` summed at render).
4. **First-vs-third person 3D** — different rigs but always tied to mouse capture + sensitivity, deadzone for right stick, pitch clamp.

This skill emits **opinionated, working defaults** so the agent can spend its time on game logic.

## Subcommands

### rig — Emit one of the named camera rigs

```bash
python3 .claude/skills/camera-rigs/tools/camera_gen.py rig \
  --kind platformer \
  --output scenes/camera/
```

Output dir gets `<kind>_camera.tscn` and `<kind>_camera.gd`. Drop into your player's scene; for 2D rigs, parent the Camera2D under the player. For 3D rigs the `.tscn` is a self-contained scene to instance.

| Kind | Class | Use case |
|------|-------|----------|
| `platformer` | `Camera2D` | Smooth follow with horizontal deadzone, vertical look-ahead on jump/fall, configurable lerp. |
| `topdown` | `Camera2D` | Symmetric deadzone (no preferred axis), aim-toward-cursor offset (toggle with `--aim`). |
| `sidescroller` | `Camera2D` | Tight horizontal lock, fixed vertical position (Metroid/Castlevania style). |
| `third-person` | `Camera3D` + `SpringArm3D` | Orbit with mouse + right stick, collision-aware via SpringArm, configurable distance + pitch limits. |
| `first-person` | `Camera3D` | Headbob, mouse-look with pitch clamp, optional FOV-zoom on aim (`--zoom-aim`). |
| `topdown-3d` | `Camera3D` | Fixed-angle isometric-ish overhead with smooth follow. |
| `cinematic` | `Camera2D` or `Camera3D` (pass `--dim 2d`/`3d`) | Tween-driven dolly between named markers; for cutscenes. |

All rigs expose:
- `target: NodePath` — the node to follow (Player by default).
- `follow_speed: float` — smoothing factor (8.0 default; lower = laggier, higher = snappier).
- `enabled: bool` — disable to freeze in place without queue_free.

### shake — Emit a screen-shake mixin

```bash
python3 .claude/skills/camera-rigs/tools/camera_gen.py shake \
  --dim 2d \
  --output scenes/camera/
```

Writes `screen_shake_2d.gd` (or `screen_shake_3d.gd` if `--dim 3d`) — attach to your camera node, then call:

```gdscript
$Camera2D.shake(intensity, duration, frequency)
# intensity in pixels (2D) or world units (3D); duration in seconds; frequency in Hz.
```

Implementation uses Perlin-ish smooth noise (not random per-frame jitter — looks better) and decays the intensity with `pow(t, decay_exp)` where `decay_exp` is configurable (default 2.0 for quadratic falloff). Multiple `shake()` calls **stack** (max of active envelopes, not sum — prevents runaway).

### bounds — Emit a bounds-clamp mixin

```bash
python3 .claude/skills/camera-rigs/tools/camera_gen.py bounds \
  --dim 2d \
  --output scenes/camera/
```

For `--dim 2d`, this just emits a sample `.gd` showing how to set `Camera2D.limit_left/right/top/bottom` from a `Rect2` resource (the engine handles the rest). For `--dim 3d`, it emits a real per-frame clamp that pins the camera's `global_position` to an `AABB`.

### list — Enumerate available rigs

```bash
python3 .claude/skills/camera-rigs/tools/camera_gen.py list
```

## Cardinal rules

- **Pick `process_callback = PROCESS_PHYSICS` if the followed target is a physics body.** Otherwise the camera is one frame behind on every update — visible as jitter at high speeds. The emitted rigs do this automatically when `--physics-target` is set.
- **Don't add shake on top of follow with `+=`.** Either use `offset` on the Camera node (cleanly added at render) or use a `RemoteTransform2D` for shake-only contribution. The emitted shake mixin uses `offset` and the rigs leave it alone.
- **Pitch clamp first-person cameras to [-89°, 89°].** Hitting ±90° flips the up vector and the world inverts. The emitted `first-person` rig clamps.
- **Mouse capture belongs in your game's pause flow, not the camera.** The emitted FPS rig only sets `Input.mouse_mode = MOUSE_MODE_CAPTURED` in `_ready()`; release/restore is your pause-menu's job.
- **Smooth-follow `lerp` is frame-rate dependent if naive.** All emitted rigs use `pow(1.0 - smoothing, delta * 60.0)` style (a.k.a. exponential damping) so the look matches at 30/60/144 Hz.

## Files

- `tools/camera_gen.py` — the CLI (single file).
- `SKILL.md` — this file.

## Composition

- **godot-task** — once the rig is emitted, godot-task can instance it under your player scene.
- **input-handling** — `third-person` / `first-person` rigs use `look_up`, `look_down`, `look_left`, `look_right` actions plus `aim` (for zoom). Use input-handling's `fps` template, which includes all of them.
- **shader-craft** — for cinematic black bars / vignette, pair the `cinematic` rig with a `ColorRect` post-effect from shader-craft.
- **scene-art** — large parallax backdrops generated by scene-art are wider than the screen; the bounds clamp here pairs with them naturally.
