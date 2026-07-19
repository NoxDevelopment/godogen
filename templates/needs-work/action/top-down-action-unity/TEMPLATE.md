# Top-Down Action Template (Unity)

Unity port of the `top-down-action` archetype (Hotline-Miami-like), **pure
first-party** — no third-party kits, only pinned official UPM packages. This is
the first template in the Unity lane; the lane rules below apply to every
`engine: "unity"` entry that follows. Scaffold with:

```bash
python templates/tools/scaffold_unity.py top-down-action-unity <target-dir> --name "Game Name"
```

Engine pin: **Unity 6000.0 LTS** (`ProjectVersion.txt` targets 6000.0.40f1;
any 6000.0.x editor opens it without an upgrade prompt).

## Unity lane rules (house style)

1. **No committed `.unity` scene files.** Unity scenes are YAML riddled with
   `fileID` cross-references — hostile to hand-authoring, review, and merges.
   Skeletons ship an editor bootstrap script (`Assets/Editor/NoxBootstrap.cs`)
   that builds the demo scene **from code** on first import and saves it to
   `Assets/Scenes/Main.unity`. Same discipline as the Godot lane's code-built
   geometry: every object is constructed by reviewable code. Rebuild any time
   via the **NoxDev > Rebuild Demo Scene** menu item.
2. **No committed `.meta` files in skeletons.** Unity generates GUIDs on first
   import. Scaffolded *projects* keep their metas (normal Unity workflow);
   skeletons stay meta-free so the template diff is pure source.
3. **Text-only skeletons.** `Assets/` (C# + whatever is honestly authorable as
   text), `Packages/manifest.json`, and a minimal `ProjectSettings/` set
   (`ProjectVersion.txt` + `ProjectSettings.asset`, which is plain YAML —
   harvested from a stock `-createProject` run and patched, not hand-invented).
   Unity regenerates every other settings asset with defaults.
4. **UPM pins live in the registry.** `upmPackages: [{name, version}]` is the
   Unity analogue of `vendoredAddons`: `scaffold_unity.py` merges the registry
   pins into `Packages/manifest.json` at scaffold time (registry wins), so
   re-pinning is a one-line registry edit. Skeleton manifests should match the
   registry; the merge is the enforcement.
5. **No `.inputactions` assets.** They are JSON but noisy; skeletons poll
   devices directly through the Input System API (`Keyboard.current`,
   `Mouse.current`, `Gamepad.current`). `activeInputHandler: 1` (Input System
   only) is set in `ProjectSettings.asset`.
6. **Legacy uGUI `Text` for skeleton HUDs**, not TextMeshPro — TMP demands an
   "Import TMP Essentials" resource step that pops dialogs and adds binary
   assets. Games can upgrade after scaffolding.
7. **The NoxDev ABI maps to C# contracts** (see below), so cross-engine ports
   keep the same save-file shape and damage semantics.

## How validation runs

`scaffold_unity.py` locates an editor (`--unity`, `$UNITY`, `PATH`, Unity Hub
install dirs `C:\Program Files\Unity\Hub\Editor\*`, then the Hub CLI) and runs:

```
Unity.exe -batchmode -quit -nographics -projectPath <p> \
    -executeMethod NoxDev.Editor.NoxBootstrap.BuildDemoScene -logFile <p>/Logs/noxdev_validate.log
```

The first run resolves UPM packages and imports everything (minutes). The log
is parsed for `error CS####` / `Scripts have compiler errors` / batchmode
aborts — any hit fails validation (exit 2). The `-executeMethod` pass proves
the editor scripts *execute* (and the demo scene builds + saves), not merely
compile — the analogue of the Godot lane's `--headless --import` gate.

**Unity absent is a first-class case:** the scaffold still completes (a Unity
project is plain files; the editor resolves packages and runs the bootstrap on
first open) and the tool exits 0 with a clear "validation skipped" warning.
Registry entries may only carry `status: "validated"` when batchmode ran clean
on the maintainer's machine against the pinned engine stream; otherwise they
stay `"draft"` with an honest `statusNote`.

## What you get

- **Player** (`Assets/Scripts/PlayerController.cs`): 8-directional Rigidbody2D
  movement (accelerate/friction), mouse aim (the `AimPivot` barrel tracks the
  cursor), **hitscan raycast shot** (`Physics2D.RaycastAll`, first non-self hit)
  with a `LineRenderer` tracer and fire-rate cooldown, **dash** (burst +
  cooldown, i-frames while dashing), health with a post-hit grace window and
  respawn at the spawn point. Gamepad: left stick move, east button dash,
  right trigger fire.
- **Three practice targets** (`Assets/Scripts/Target.cs`): shootable dummies
  (`IDamageable`), hit-flash, destroyed counter in the
  `GameManager` `"targets_destroyed"` flag, HUD count.
- **Chaser enemy** (`Assets/Scripts/Enemy.cs`): direct-steering chase
  (re-targets 4x/sec), contact damage on a cooldown, itself shootable.
  *Engine note:* Godot's version paths with `NavigationAgent2D`; Unity has no
  first-party 2D navmesh (NavMesh is 3D, NavMeshPlus is third-party), so the
  skeleton seeks directly — correct for the open arena. For walled interiors,
  replace the `FixedUpdate` steering with A* over a Tilemap or vendor a 2D nav
  package.
- **GameManager** (`Assets/Scripts/GameManager.cs`): auto-creating singleton
  with world **flags**, plus **JSON save/load** (Newtonsoft) that gathers every
  `ISaveable` in the scene into one document keyed by `SaveKey`.
- **Arena** (built by `Assets/Editor/NoxBootstrap.cs`): walled 18x10-unit room,
  orthographic camera, HUD (HP + targets left), flat-color sprite blockouts
  from a generated `white_square.png`.
- **Main** (`Assets/Scripts/Main.cs`): wires player health + target events into
  the HUD and emits the boot probe
  `DEBUG: top-down-action core loop ready — player=... targets=... enemy_chasing=...`.

## ABI mapping (Godot template ABI → Unity)

| Godot ABI | Unity port |
|-----------|-----------|
| `"persistent"` group + `save_data() -> Dictionary` / `load_data(data)` | `ISaveable` interface: `SaveKey`, `SaveData() -> Dictionary<string, object>`, `LoadData(...)`; `GameManager.SaveGame()/LoadGame()` gathers all implementors into one JSON document (`Application.persistentDataPath/save.json`) |
| `"game_manager"` group / autoload | `GameManager.Instance` (auto-creating singleton, `DontDestroyOnLoad`) |
| `"player"` group | `"Player"` tag (builtin) |
| `take_hit(damage: int, from: Node)` | `IDamageable.TakeHit(int damage, GameObject from)` |
| `"targets"` group count | `Main.TargetsAlive` (`FindObjectsByType<Target>`) |
| `Master`/`Music`/`SFX` buses (`default_bus_layout.tres`) | not ported yet — add an `AudioMixer` with matching groups when audio lands (mixer assets are binary-ish; deferred to keep the skeleton text-only) |
| input actions in `project.godot` `[input]` | direct Input System device polling (see lane rule 5) |

Save-file shape matches the Godot template byte-for-concept:
`{"game_manager": {"flags": {...}}, "player": {"position": {"x","y"}, "health"}}`.

## Damage contract (the part worth understanding)

Anything shootable implements `IDamageable.TakeHit(damage, from)` (declared in
`GameManager.cs`). The player's hitscan ray calls it on the first non-self
collider hit; plain colliders (walls) simply stop the ray. The enemy uses the
same contract against the player for contact damage. New destructibles: add a
Collider2D + `IDamageable` and you're in the loop.

## How to extend

1. **Levels**: fork `NoxBootstrap.BuildDemoScene` (or author scenes in-editor —
   the no-committed-scenes rule is for the *template*, not your game).
2. **Weapons**: `PlayerController.Shoot()` is one hitscan — vary `shotDamage`,
   `shotCooldown`, `shotRange`, or fork it into a projectile spawner. The
   `ShotFired(from, to, hit)` event is where muzzle flash / shake / audio hook in.
3. **Enemies**: `Enemy.cs` is the chase archetype; subclass for shooters
   (raycast the player back) or patrollers (waypoint list before aggro).
4. **Saving/menus**: `GameManager.SaveGame()/LoadGame()` already round-trips
   every `ISaveable`; menus/settings systems are not ported yet (the godotsmith
   drop-ins are Godot-only).
5. **Art**: see `assetPlanHints` in the registry entry. All visuals are
   flat-color sprite blockouts on purpose; replace the sprites, keep colliders.

## Validation status

`status: "validated"` — scaffolded twice (deep and short target paths) with
`scaffold_unity.py` against **Unity 6000.0.40f1**: batchmode exit 0, zero
`error CS####` lines, `NoxDev.Editor.NoxBootstrap.BuildDemoScene` executed and
saved `Assets/Scenes/Main.unity` + `Assets/Sprites/white_square.png`, zero
asset-import failures. One environment caveat found during validation: target
paths deep enough to push `Library/PackageCache/...` past Windows' 260-char
MAX_PATH produce benign `DirectoryNotFoundException` noise on Input System
editor UI resources (compile and scene build still succeed) — keep scaffold
targets reasonably short or enable Windows long paths.
