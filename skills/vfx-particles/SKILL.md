# VFX Particles

Emit Godot 4 **GPUParticles2D** `.tscn` presets — the particle layer that sells
impact: the burst on a hit, dust under a jump, sparkle on a pickup, confetti on a
win. Distinct from `shader-craft` (screen-space effects) and `game-feel`
(time/scale juice); these three together are "polish."

## TL;DR

```bash
python3 .claude/skills/vfx-particles/tools/particles_gen.py explosion --color "#ffb347" -o assets/vfx/explosion.tscn
```

Instance the scene at the effect position; call `restart()` for one-shots, or set
`emitting = true` for loops.

## Presets

| Preset | One-shot? | Use |
|---|---|---|
| `explosion` | yes | Death, bomb, big impact (radial, gravity-fall) |
| `impact` | yes | Bullet/melee hit spark (directional, fast) |
| `dust` | yes | Landing/footstep puff (ground-hugging, rises slightly) |
| `sparkle` | loop | Pickup shimmer, magic item idle |
| `trail` | loop | Projectile / dash trail (attach to a moving node) |
| `magic` | loop | Spell charge, aura (rises, slow) |
| `smoke` | loop | Fire/chimney/wreckage (slow, large, rises) |
| `confetti` | yes | Victory, level-up (wide, spinning, gravity) |

`--color` tints the particles. For non-square particles, assign a soft-dot
texture to the `GPUParticles2D` (generate one with `image-pipeline --type icon`).

## Pairs with

- **game-feel** — fire an `impact`/`explosion` particle at the same frame as
  `Feel.impact()` for a complete hit (freeze + flash + shake + burst).
- **shader-craft** — combine with an additive/glow material for energy effects.
- **audio-pipeline** — a SFX on the same frame.

## Notes

- `local_coords = false` so emitted particles stay in world space (correct for
  a moving emitter like a trail).
- Tune `amount` / `lifetime` / `explosiveness` per game; presets are sensible
  starting points, not final values.
- Resource generator — no backend, no cost.

## Verification

These produce **visible in-game output** — don't ship on the preset table alone. Instance the scene, fire it once (`restart()` / `emitting = true`), and **look at it**: screenshot or grab a short clip and confirm color, lifetime, direction, and density read right against `reference.png`. Tune and re-check before committing.
