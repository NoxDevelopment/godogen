# Game Feel

The "juice" layer. Good gameplay loops still feel flat without **feedback on
impact** — this skill emits a drop-in `GameFeel` autoload that gives a Godot 4
game hit-stop, slow-mo punches, damage flashes, scale-pops, screen-shake, and
knockback. It's the cheapest, highest-impact polish you can add.

> **When the game *plays* well but *feels* dead, this is the fix.** A hit that
> freezes for 80ms, flashes white, shakes the screen, and knocks the enemy back
> reads as 10× more impactful than the same hit with none of that — for ~5 lines.

## TL;DR

```bash
python3 .claude/skills/game-feel/tools/feel_gen.py --profile juicy -o scripts/game_feel.gd
```

Then register it as an **Autoload named `Feel`** (Project Settings → Autoload).
Now call from anywhere:

```gdscript
Feel.hit_stop()                       # freeze-frame on impact
Feel.flash($Sprite2D, Color.RED)      # damage tint
Feel.pop($Coin)                       # squash/stretch on pickup
Feel.shake(12.0)                      # explosion
Feel.knockback(enemy, dir)            # send the enemy flying
Feel.impact($Sprite2D, dir)           # the whole "got hit" combo in one call
```

## Profiles

Scale the default intensities; pick by genre, then tune the `const`s in the file:

| Profile | Feel |
|---|---|
| `subtle` | Cozy / narrative / puzzle — barely-there feedback |
| `standard` | Default — most action games |
| `juicy` | Punchy action platformer / roguelike |
| `arcade` | Maximum crunch — beat-em-up / bullet-hell |

## What's in the autoload

| Method | Use |
|---|---|
| `hit_stop(duration)` | Freeze-frame on impact (real-time timer, ticks at time_scale 0) |
| `time_punch(scale, duration)` | Slow-mo burst that eases back to normal (big hits, deaths) |
| `flash(node, color, duration)` | Modulate tint — white on hit, red on damage, green on heal |
| `pop(node, amount, duration)` | Elastic scale punch — pickups, button presses, spawns |
| `shake(amount, duration)` | Screen shake — delegates to the active Camera2D's `shake()` |
| `knockback(body, dir, force)` | CharacterBody2D velocity / RigidBody2D impulse |
| `impact(node, dir)` | The classic combo: hit_stop + flash + shake + knockback |

## Pairs with

- **camera-rigs** — its screen-shake mixin is what `Feel.shake()` drives. Connect
  the camera to the `Feel.shake_requested` signal (or give it a `shake()` method).
- **vfx-particles** — spawn an impact burst at the same moment for the full hit.
- **audio-pipeline** — a punchy SFX on the same frame completes the feel.

## Notes

- Everything is gated by `Feel.enabled` — flip it off for accessibility
  (reduced-motion) or debugging. See the **accessibility** skill: shake + flash
  should respect a reduced-motion setting.
- `hit_stop` uses an `ignore_time_scale` timer so it works while time is frozen.
- Resource/script generator — no backend, no cost, deterministic per profile.

## Verification

Juice is **visible output** — call each method (`Feel.impact()`, hit-stop, flash, pop) on a test sprite and **look at it** (screenshot/clip): confirm the flash, shake, and scale-pop actually read and don't overwhelm. For a template, this is the "Game feel" row of `skills/parity-build/STANDARDS.md`; keep it behind the reduced-motion gate (accessibility).
