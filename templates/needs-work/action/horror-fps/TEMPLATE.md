# Horror FPS Template

First-person horror base: **COGITO** (immersive-sim stack, same pins as
fps-immersive) + **resonate** adaptive music stems + a first-party **sanity
system**. Scaffold with:

```bash
python templates/tools/scaffold.py horror-fps <target-dir> --name "Game Name" --godot C:/godot4.5/GodotConsole.exe
```

Engine pin: **Godot 4.5.x** (validated on 4.5.1-stable) — inherited from
fps-immersive: COGITO v1.1.6 targets 4.5.1 and its quest manager breaks the
4.6 GDScript analyzer. Pass a 4.5.x binary to scaffold and all headless
checks.

Kit pins:
- `Phazorknight/Cogito` **v1.1.6 @ `8b38b0bb`** (Codeberg, MIT) + bundled
  Input Helper + Quick Audio — identical to fps-immersive so both templates
  track COGITO together.
- `widgitgaming/godot/resonate` **v2.4.0 @ `e1cf2cff`** (GitLab, MIT) — the
  official continuation (maintained by Widgit Gaming since Jan 2026); the
  hugemenace GitHub repo is archived at v2.3.4.

## What you get

- **Everything fps-immersive has**: COGITO player (sprint/crouch/slide,
  attributes, grid inventory, wieldables), component interaction system,
  quest system, EasyMenus, the blockout test room with an openable door and
  a carryable health potion — see `templates/needs-work/action/fps-immersive/TEMPLATE.md`.
- **Sanity system** (`scripts/sanity.gd`, autoload `Sanity`): 0-100 stat
  with passive ambient drain (0.5/s), **safe-zone restore** (8/s inside
  Area3D light pools — `scenes` ship one warm `SafeLamp`), `scare(amount)`
  for scripted hits, and **hysteresis thresholds** (`low_sanity_entered` at
  ≤45, `low_sanity_exited` at ≥60) so the dread layer never flickers.
  Persists via the ABI `save_data()` contract.
- **Sanity presentation** (`shaders/sanity_overlay.gdshader` on a
  CanvasLayer ColorRect): closing dark vignette with a low-sanity pulse,
  driven by one `intensity` uniform (= `1 - Sanity.normalized()`).
- **Adaptive music** (resonate): a `MusicBank` ("horror") in the test room
  with one stemmed track ("ambient") — `calm` pad always on, `dread` drone
  gated by the sanity thresholds via `MusicManager.enable_stem`/
  `disable_stem` with crossfades. The stem WAVs are generated placeholders
  (3 s pad chord / detuned drone) — replace with real stems, keep the names.
  The track plays with `auto_loop=true` because the placeholders are plain
  non-looped WAVs; pre-looped stems can drop the flag.
- **Decoupled wiring**: `test_room.gd` is the only place stat → overlay →
  stems connect. Sanity knows nothing about rendering or audio (Amnesia-
  style architecture) — new reactions are one more signal connection.
- **Resonate autoloads declared in project.godot** (`SoundManager`,
  `MusicManager`) — the plugin normally registers them from its editor
  hook, which never runs in scaffolded/headless flows; declaring them
  directly is the same pattern the COGITO autoloads use.
- **NoxDev template ABI**: buses (stems play on `Music`), groups,
  `save_data()` contracts, `pause` alongside COGITO's `menu`.

## How to extend

1. **Stems**: add `MusicStemResource`s to the track (heartbeat, strings,
   whispers) and map them to sanity bands in `_on_sanity_changed` — or use
   `MusicManager.set_stem_volume(name, db)` for continuous intensity instead
   of on/off gating.
2. **Scares**: call `Sanity.scare(n)` from COGITO interactables/triggers
   (a `CogitoObject` script can call it on interact); pair with resonate's
   `SoundManager.play("stingers", ...)` one-shots.
3. **Darkness drain**: scale `ambient_drain` by light level (sample
   COGITO's visibility/stealth attribute — the player already computes it).
4. **Monsters**: COGITO ships enemy/NPC bases; on sighting, `scare()` +
   `enable_stem("dread", 0.2)` is the classic loop.
5. **Overlay**: extend the one shader (grain, chromatic aberration) rather
   than stacking CanvasLayers.

## Validation status

`status: "validated"` — scaffolded (all four addons vendored at pins, 4
plugins enabled after bootstrap import), `--headless --import` exit 0 with
zero script errors, 300-frame headless boot exit 0 with zero script errors.
Boot probe:

```
DEBUG: horror-fps core loop ready — player=true interactables=2 music_playing=true sanity=40 overlay_intensity=0.60 dread_stem_enabled=true
```

(COGITO player registered; door + potion interactable; resonate loaded and
the ambient track playing; a scripted `scare(60)` dropped sanity 100 → 40
through the low threshold, pushing the overlay shader to intensity 0.60 and
enabling the dread stem.) Residual log noise matches the validated
fps-immersive baseline exactly: COGITO's `DynamicInputIcon` no-rendering-
device notices (headless only) and the ObjectDB/resource shutdown warnings
on instant-quit runs.
