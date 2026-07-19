# FPS / Immersive Sim Template (3D)

First-person immersive-sim base on **COGITO** (Phazorknight). Scaffold with:

```bash
python templates/tools/scaffold.py fps-immersive <target-dir> --name "Game Name" --godot C:/godot4.5/GodotConsole.exe
```

Engine pin: **Godot 4.5.x** (validated on 4.5.1-stable) with COGITO **v1.1.6**.
**This template does NOT run on Godot 4.6** — pass a 4.5.x executable explicitly
(see the engine-pin note below).

## Engine-pin note (read before re-validating)

- **Upstream moved to Codeberg.** COGITO development is on
  `codeberg.org/Phazorknight/Cogito`; the GitHub repo is a mirror whose release
  tags stop at v1.1.5. The registry pins **Codeberg `v1.1.6`** (SHA
  `8b38b0bb`), the current stable release, which self-reports Godot 4.5.1.
- **4.6 breaks it (tested 2026-07-11).** On Godot 4.6.1 COGITO imports but its
  scene manager fails to parse: the GDScript analyzer cannot resolve the typed
  members `CogitoQuestManager.active/completed/failed` (used in
  `cogito_scene_manager.gd`), which cascades into a parse error in
  `EasyMenus/Components/SaveSlotButton.gd`. On **4.5.1 the same pin imports and
  boots with zero script errors.** So the template pins 4.5 and must be
  scaffolded and validated with a 4.5.x Godot (`C:\godot4.5` here). If a future
  COGITO release supports 4.6, re-pin and re-validate against 4.6.1.
- Three MIT addons are vendored from the **same COGITO commit**: `cogito`,
  and the two it bundles — `input_helper` (nathanhoad) and `quick_audio`
  (bryceahn). Pinning all three to one SHA means their versions can never skew.

## What you get

- **COGITO fully wired**: the six autoloads (`Audio`, `InputHelper`,
  `CogitoGlobals`, `CogitoSceneManager`, `CogitoQuestManager`,
  `MenuTemplateManager`), the editor plugins, the COGITO theme, Jolt physics,
  and the full 32-action input map (movement, sprint/crouch, interact ×2,
  primary/secondary action, inventory + quickslots, wieldable cycling) with
  keyboard **and** gamepad bindings — baked into `project.godot`.
- **The COGITO player** (`cogito_player.tscn`): first-person controller with
  sprinting, jumping, crouching, sliding, stair + ladder handling, sitting,
  headbob, fall damage; the attribute system (health/stamina/visibility for
  stealth, extensible to RPG stats); the grid inventory (Resident-Evil-4 style)
  with quickslots and wieldables; the component-based interaction system.
- **One blockout test room** (`scenes/test_room.tscn` extending COGITO's
  `cogito_scene.gd`): walled 24x24 m box with skybox + sun, the player, an
  **openable door** (`door.tscn`) and a **carryable health-potion pickup**
  (`pickup_health_potion.tscn`) — both live in COGITO's `"interactable"` group,
  so walk up and the interaction prompt appears.
- **EasyMenus** main menu + pause menu with save slots (COGITO's own
  save/load), quest system, dynamic footstep system — all ready to build on.
- **NoxDev template ABI on top**: `Master`/`Music`/`SFX` buses by name
  (COGITO's OptionsMenu reads them for volume sliders), COGITO's `"Player"`
  group on the player plus NoxDev `"player"`, a `GameManager` autoload in the
  `"game_manager"`/`"persistent"` groups with the `save_data()` contract, and a
  `pause` action alongside COGITO's own `menu` action.

## The scene contract (the part worth understanding)

The **main scene is the room** (`test_room.tscn`), and its root **extends
`cogito_scene.gd`** — that is what registers the room with
`CogitoSceneManager`, positions the player at named connector nodes on scene
transitions, and (optionally) starts scene music. `CogitoSceneManager` holds
the current player via `_current_player_node`; the player registers itself on
`_ready`. Scene-to-scene travel goes through the scene manager (connectors),
not `change_scene_to_file`, so player/inventory state carries across.
Interactables are COGITO `CogitoObject`s (or component-composed nodes) that add
themselves to `"interactable"`; the player's interaction ray drives their
`interact()` methods.

## How to extend

1. **Rooms/levels**: duplicate `test_room.tscn`, keep the `cogito_scene.gd`
   root and add `Node3D` connector points; link rooms with COGITO's connector
   naming. Graybox with the `world-layout` skill; keep layer 1 = Environment,
   layer 2 = Interactables.
2. **Interactables**: COGITO ships doors, drawers, keypads, switches,
   turn-wheels, elevators, carryables, readable notes — instance from
   `addons/cogito/PackedScenes` (and `DemoScenes/DemoPrefabs`), or add
   interaction Components to your own `CogitoObject`.
3. **Items/wieldables**: items are resources under
   `addons/cogito/InventoryPD/Items` paired with a pickup scene and a 64x64
   icon; wieldables (flashlight, tools, weapons) live under `Wieldables`.
4. **Attributes**: extend the player's attribute set for RPG stats; interactions
   can gate on attribute checks (COGITO's "you can only lift this if strong
   enough" pattern).
5. **Boomer-shooter variant**: per the roadmap, pair this controller with
   FuncGodot `.map` levels and billboard enemies — the COGITO player is the
   shared base.
6. **Menus/audio**: COGITO's EasyMenus and dynamic footstep system are already
   in; the `audio-design` skill feeds surface-tagged footsteps, `game-feel`
   adds hit/camera feedback when combat wieldables land.

## Validation status

`status: "validated"` — scaffolded (bootstrap import + deferred plugin enable),
`--headless --import` on **Godot 4.5.1** exit 0 with **zero script errors**,
240-frame headless boot exit 0 with zero script errors. Boot probe:

```
DEBUG: fps-immersive core loop ready — player=true interactables=2 door=true pickup=true
```

(the COGITO player is registered with `CogitoSceneManager` and both the door
and pickup are in the `"interactable"` group). Remaining log lines are benign
and not script errors: one Jolt notice (`Custom solver bias for shapes is not
supported` — COGITO's own collision shapes, engine-level), repeated
`DynamicInputIcon: No rendering device detected` (Input Helper querying the GPU
under `--headless`), and ObjectDB/leak accounting at quit — same class as the
Wave-0 Popochiu NavRegion2D note.

## Vendored addon notes

- Vendoring applies one pinned patch to `addons/cogito/InventoryPD/UiScenes/
  Slot.tscn` stripping a stale texture UID (upstream commits no `.import` for
  `SlotBorder.png`, so fresh imports mint a new UID and the committed one warns
  on every boot). Game-runtime code paths are untouched.
- Licenses: all MIT — `addons/cogito/LICENSE`, `addons/input_helper/LICENSE`,
  `addons/quick_audio/LICENSE` (manifest in `addons/LICENSES.md`).
- Docs: https://cogito.readthedocs.io (getting started, tutorials, component
  reference); source: https://codeberg.org/Phazorknight/Cogito.
- The COGITO plugin self-registers its autoloads when enabled; the skeleton
  also bakes all six into `project.godot` so headless runs work before the
  editor ever opens the project.
