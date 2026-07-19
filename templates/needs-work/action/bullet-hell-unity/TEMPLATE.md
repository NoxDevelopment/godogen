# Bullet-Hell Template (Unity)

Unity port of the `bullet-hell` archetype (danmaku / shmup), **pure
first-party** — no third-party kits, only pinned official UPM packages. This is
the **second** template in the Unity lane; it follows every Unity lane rule
established by `top-down-action-unity` (read that template's rules section
first — they are the house style for all `engine: "unity"` entries). Scaffold
with:

```bash
python templates/tools/scaffold_unity.py bullet-hell-unity <target-dir> --name "Game Name"
```

Engine pin: **Unity 6000.0 LTS** (`ProjectVersion.txt` targets 6000.0.40f1;
any 6000.0.x editor opens it without an upgrade prompt).

## The one big porting decision: BulletUpHell is not portable

The Godot `bullet-hell` template is built on **BulletUpHell** (Dark-Peace) — a
third-party GDScript addon that keeps every bullet as a pooled physics *shape*
inside one shared `Area2D`, stepped from a `Spawning` autoload. The Unity lane
forbids third-party kits (lane rule: pure first-party, only pinned official UPM
packages), and there is no first-party Unity equivalent to vendor. So the
mechanic is **reimplemented from scratch** in C#, faithful to the addon's
architecture rather than to any one Unity asset:

- Bullets are **not GameObjects with their own `Update`**. They are pooled
  objects processed **centrally** by a single `BulletSystem` in one
  `FixedUpdate` — position integration, lifetime, out-of-box death, and
  collision, all in one pass. That is exactly how BulletUpHell steps bullets
  from its autoload, and it is what keeps hundreds of bullets cheap.
- The id-keyed registration model is preserved: a `BulletDefinition` node
  registers a bullet type by id (`"standard"`), a `PatternDefinition` node
  registers a volley by id (`"ring"`), and a `Spawner` fires a pattern by id —
  the direct analogue of the addon's BulletProps / SpawnPattern / SpawnPoint
  nodes, so "add a bullet type / pattern by dropping a node and giving it an id"
  still holds.

## What you get

- **BulletSystem** (`Assets/Scripts/BulletSystem.cs`): the first-party bullet
  engine — auto-creating singleton, an object pool (pre-warmed to 64, grows on
  demand), id-keyed `BulletProps` / `SpawnPattern` registries, the registered
  `"Player"` special target, a `BulletHitBody` event, `ActiveBulletCount`, and
  the central per-`FixedUpdate` step that moves every live bullet and resolves
  hits. Ships a runtime disc-sprite generator so bullets are visible even
  without the editor-assigned sprite.
- **Bullet** (`Assets/Scripts/Bullet.cs`): a deliberately dumb pooled bullet —
  state + visual, stepped by `BulletSystem`, never self-driving.
- **Standard bullet** (`BulletDefinition`, id `"standard"`): 2.4 u/s, 0.12 u
  radius, dies after 10 s or on leaving the death box (wider than the arena so
  bullets clear the walls first). The Unity port of the addon's `BulletProps`.
- **Ring pattern** (`PatternDefinition`, id `"ring"`): a 12-way full-circle
  volley from a 0.4 u spawn ring, one volley every 0.8 s, infinite iterations.
  The Unity port of `PatternCircle`.
- **Spawner** (`Assets/Scripts/Spawner.cs`): fires `"ring"` from its first
  physics tick (runs headless — no camera-visibility gate), owning the volley
  cadence and iteration budget. The Unity port of `BuHSpawnPoint`.
- **Player ship** (`Assets/Scripts/PlayerShip.cs`): 8-directional kinematic
  `Rigidbody2D` movement clamped to the arena, a **held-focus slowdown** (the
  shmup precision-dodge staple: 7 u/s → 3 u/s), a deliberately **small 0.12 u
  hurtbox** with a white core dot, 3 lives with a post-hit invulnerability
  window + blink and respawn at the start. Keyboard WASD/arrows + held
  Space/Shift for focus; gamepad left stick / d-pad + held south button.
- **GameManager** (`Assets/Scripts/GameManager.cs`): auto-creating singleton
  with world **flags**, plus **JSON save/load** (Newtonsoft) gathering every
  `ISaveable` in the scene into one document keyed by `SaveKey`. Shared,
  byte-for-concept, with `top-down-action-unity`.
- **Arena** (built by `Assets/Editor/NoxBootstrap.cs`): walled 18×10-unit
  playfield, orthographic camera, HUD (Lives + live Bullets count), flat-color
  sprite blockouts from a generated `white_square.png`.
- **Main** (`Assets/Scripts/Main.cs`): wires player lives + the live bullet
  count into the HUD and emits the boot probe
  `DEBUG: bullet-hell core loop ready — spawner=... player=... active_bullets=...`.

## ABI mapping (Godot template ABI → Unity)

The NoxDev template ABI is shared with `top-down-action-unity`; only the
bullet-engine rows are new to this template.

| Godot ABI | Unity port |
|-----------|-----------|
| `"persistent"` group + `save_data() -> Dictionary` / `load_data(data)` | `ISaveable` interface (`SaveKey`, `SaveData`, `LoadData`); `GameManager.SaveGame()/LoadGame()` gathers all implementors into one JSON document at `Application.persistentDataPath/save.json` |
| `"game_manager"` group / autoload | `GameManager.Instance` (auto-creating singleton, `DontDestroyOnLoad`) |
| `"player"` group | `"Player"` tag (builtin) |
| `take_hit(damage: int, from: Node)` | `IDamageable.TakeHit(int damage, GameObject from)` |
| BulletUpHell `Spawning` autoload | `BulletSystem.Instance` (auto-creating singleton) |
| `Spawning.poolBullets.size()` | `BulletSystem.ActiveBulletCount` |
| `Spawning.bullet_collided_body` signal | `BulletSystem.BulletHitBody` event `(GameObject body, BulletProps props)` |
| `Spawning.edit_special_target("Player", ship)` | `BulletSystem.RegisterTarget("Player", transform, hurtboxRadius)` |
| `Spawning.get_shared_area("0").collision_mask` (what bullets can hit) | the registered special target: bullets test distance against the one registered `"Player"` transform + hurtbox radius (no physics layer surgery; deterministic and headless-safe) |
| `BulletProps` sub-resource (id `"standard"`) via `BuHBulletProperties` node | `BulletProps` (serializable) registered by `BulletDefinition` node |
| `PatternCircle` resource (id `"ring"`) via `BuHPattern` node | `SpawnPattern` (serializable) registered by `PatternDefinition` node |
| `BuHSpawnPoint.spawn(pattern_id)` | `Spawner` (cadence + iterations) → `BulletSystem.EmitVolley(patternId, origin)` (pooling + emission) |
| `Master`/`Music`/`SFX` buses (`default_bus_layout.tres`) | not ported yet — add an `AudioMixer` with matching groups when audio lands (mixer assets are binary-ish; deferred to keep the skeleton text-only, same call as `top-down-action-unity`) |
| input actions in `project.godot` `[input]` | direct Input System device polling (Unity lane rule: no `.inputactions` asset) |

Save-file shape matches the Godot template byte-for-concept:
`{"game_manager": {"flags": {...}}, "player": {"position": {"x","y"}, "lives"}}`.
(The bullet-hell player persists **lives**, not health — the same key the Godot
`player.gd` writes.)

## The damage/collision contract (the part worth understanding)

Every bullet is checked, centrally, against the single registered `"Player"`
special target each `FixedUpdate`: if the bullet center is within
`bulletRadius + hurtboxRadius` of the ship, `BulletSystem` (1) raises
`BulletHitBody(playerObject, props)` and (2) despawns the bullet — the addon's
"a bullet touching a Player body auto-despawns" behavior. `PlayerShip`
subscribes to `BulletHitBody` and applies `TakeHit(props.damage)`, gated by its
own grace window, so damage lands once and the ship is briefly invulnerable
after — exactly the split in `player.gd`. Bullets ignore walls (the Godot
shared area's mask excludes them); they clear the arena and die via the death
box. New hazards: register another special target or extend the step to test
additional `IDamageable` colliders with `Physics2D.OverlapCircle`.

## How to extend

1. **More bullet types**: duplicate the `BulletProps` node, give it a new `id`
   and tweak `speed` / `radius` / `lifeTime` / `deathBox` / `color`. Patterns
   reference it by id.
2. **More patterns**: add a `PatternDefinition` node (new `id`, `bulletId`,
   `count`, `angleTotal` for fans vs full rings, `cooldownSpawn`), then point a
   `Spawner.patternId` at it. `EmitVolley` handles full-ring vs partial-fan
   spacing automatically.
3. **Custom trajectories / homing**: call `BulletSystem.SpawnBullet(props, pos,
   velocity)` directly from a wave script, or extend `Bullet.Step` /
   `BulletSystem.FixedUpdate` for acceleration / curving / homing on the
   registered target.
4. **Bosses / waves**: a boss is a moving object with several `Spawner`s
   (different pattern ids); wave scripting = toggling `Spawner.active` over time
   from a wave manager.
5. **Player shots**: add a second bullet id on a distinct target set, or plain
   Area2D projectiles — enemy counts are low.
6. **Saving/menus**: `GameManager.SaveGame()/LoadGame()` already round-trips
   every `ISaveable`; menus/settings systems are not ported yet (the godotsmith
   drop-ins are Godot-only).
7. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   flat-color sprite blockouts on purpose; replace the sprites, keep the radii.

## Validation status

`status: "validated"` — scaffolded with `scaffold_unity.py` against **Unity
6000.0.40f1** (the same editor the first Unity port validated on):

```
Unity.exe -batchmode -quit -nographics -projectPath <p> \
    -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene -logFile <p>/Logs/noxdev_validate.log
```

Result: batchmode **exit 0**, zero `error CS####` lines, zero "Scripts have
compiler errors" / "Compilation failed" / batchmode aborts. The
`-executeMethod` pass ran and logged
`NoxBootstrap: demo scene built at Assets/Scenes/Main.unity (player=True)`,
saving `Assets/Scenes/Main.unity` + `Assets/Sprites/white_square.png` with zero
asset-import failures; the log tail reads `Exiting batchmode successfully now!`
/ `return code 0`. The first import resolves the pinned UPM packages and imports
everything; the log is parsed for `error CS####` / `Scripts have compiler
errors` / batchmode aborts (any hit fails validation, exit 2). The
`-executeMethod` pass proves the editor script *executes* and the demo scene
builds + saves — the Unity analogue of the Godot lane's `--headless --import`
gate. The `active_bullets` boot probe runs in Play mode (or a PlayMode test),
not during the scene-build gate — same as `top-down-action-unity`.

Two benign log artifacts seen during validation (neither is a script error;
exit code was 0):

- A `[Licensing::Client] Error: Code 10 while verifying Licensing Client
  signature` line early in the log — a Unity 6 batchmode signature-verification
  warning; the editor was licensed and ran the build regardless (this is *not*
  one of the "No valid Unity Editor license" failures the validator gates on).
- Shutdown accounting at exit (`abort_threads: ... mono_thread_manage will
  ignore it`, `debugger-agent: Unable to listen on <port>`) — the same class as
  the Godot lane's engine-shutdown notes; present after a clean run.

Inherited environment caveat from `top-down-action-unity`: keep scaffold target
paths reasonably short (or enable Windows long paths) so `Library/PackageCache/`
does not push past the 260-char `MAX_PATH`.
