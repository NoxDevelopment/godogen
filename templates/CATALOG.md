# NoxDev Template Catalog

Human index of every game template, grouped by **readiness → genre**.
Machine source of truth is [`registry.json`](registry.json); paths there are authoritative.
Reorganized 2026-07-19 from a flat `genres/` tree. Readiness is Jesus's sign-off gate.

**78 templates** · ready **4** · needs-work **74**

## ✅ Ready (Jesus-verified look/feel + systems at/near parity) — 4

### action (1)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `top-down-action` | Top-Down Action (Hotline-Miami-like) | godot | full-game | `ready/action/top-down-action/` |

### board (2)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `cosmic-horror-coop` | Cosmic-Horror Co-op (investigation + doom, 2D board game) | godot | validated | `ready/board/cosmic-horror-coop/` |
| `euro-engine-builder` | Euro Engine-Builder (competitive resource→production→VP engine, 2D) | godot | validated | `ready/board/euro-engine-builder/` |

### mud (1)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `text-rpg-mud` | (text-rpg-mud) | evennia+godot | deep-systems-live | `ready/mud/text-rpg-mud/` |

## 🛠️ Needs-work (scaffold / gameplay-base short of full parity) — 74

### action (11)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `action-adventure-3d` | Action Adventure 3D (Zelda-like dungeon, 3D) | godot | validated | `needs-work/action/action-adventure-3d/` |
| `bullet-hell` | Bullet Hell / Shmup | godot | validated | `needs-work/action/bullet-hell/` |
| `bullet-hell-unity` | Bullet-Hell (Unity) | unity | validated | `needs-work/action/bullet-hell-unity/` |
| `fighting-1v1` | Fighting Game (Street Fighter/MK-lite 1v1 with frame data, 2D) | godot | validated | `needs-work/action/fighting-1v1/` |
| `fps-classic` | FPS Classic (arena shooter — Kenney Starter Kit FPS) | godot | base | `needs-work/action/fps-classic/` |
| `fps-immersive` | FPS / Immersive Sim (3D) | godot | validated | `needs-work/action/fps-immersive/` |
| `horror-fps` | Horror FPS (first-person horror) | godot | validated | `needs-work/action/horror-fps/` |
| `martial-arts-brawler` | Martial Arts Brawler (Jade-Empire-style 2D beat-'em-up RPG) | godot | validated | `needs-work/action/martial-arts-brawler/` |
| `top-down-action-unity` | Top-Down Action (Unity) | unity | validated | `needs-work/action/top-down-action-unity/` |
| `twin-stick-shooter` | Twin-Stick Shooter (Enter the Gungeon/Nuclear Throne-lite arena survival, 2D) | godot | validated | `needs-work/action/twin-stick-shooter/` |
| `vampire-survivors` | Vampire Survivors-like (auto-attack swarm roguelite) | godot | base | `needs-work/action/vampire-survivors/` |

### arcade (8)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `arcade-racing` | Arcade Racing (Kenney Starter Kit Racing) | godot | base | `needs-work/arcade/arcade-racing/` |
| `crowd-rush` | Crowd Rush (hypercasual crowd-runner) | godot | validated | `needs-work/arcade/crowd-rush/` |
| `dot-io` | Dot IO (Hole.io / Agar.io grow-by-absorbing arena, 2D) | godot | validated | `needs-work/arcade/dot-io/` |
| `endless-runner` | Endless Runner (Subway Surfers / Temple Run 3-lane dodge, 2D) | godot | validated | `needs-work/arcade/endless-runner/` |
| `ragdoll-locomotion` | Ragdoll Locomotion (QWOP-style physics-comedy walker + MP) | godot | validated | `needs-work/arcade/ragdoll-locomotion/` |
| `rhythm` | Rhythm Game (Guitar Hero/DDR/osu!mania-lite 4-lane note highway, 2D) | godot | validated | `needs-work/arcade/rhythm/` |
| `spinning-top-battler` | Spinning Top Battler (Beyblade-style arena, 2D) | godot | validated | `needs-work/arcade/spinning-top-battler/` |
| `sports-arcade` | Arcade Sports (top-down 3v3 arcade soccer with team AI, 2D) | godot | validated | `needs-work/arcade/sports-arcade/` |

### rpg (8)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `animal-society-rpg` | Animal Society RPG (survival + migration, 2D) | godot | validated | `needs-work/rpg/animal-society-rpg/` |
| `classic-roguelike` | Classic Roguelike (Rogue/NetHack-lineage turn-based dungeon crawl, 2D) | godot | validated | `needs-work/rpg/classic-roguelike/` |
| `crpg-party` | Party CRPG (Baldur's-Gate-lite D&D-5e-lite adventure + initiative combat, 2D) | godot | validated | `needs-work/rpg/crpg-party/` |
| `dungeon-crawler-classic` | Dungeon Crawler Classic (grid-based first-person) | godot | validated | `needs-work/rpg/dungeon-crawler-classic/` |
| `iso-arpg` | Isometric ARPG (Diablo-like) | godot | validated | `needs-work/rpg/iso-arpg/` |
| `metroidvania` | Metroidvania (2D side-scroller) | godot | validated | `needs-work/rpg/metroidvania/` |
| `tactics-srpg` | Tactics SRPG (Fire Emblem/XCOM grid tactics with weapon triangle, 2D) | godot | validated | `needs-work/rpg/tactics-srpg/` |
| `zelda-like` | Zelda-like (top-down action-adventure) | godot | validated | `needs-work/rpg/zelda-like/` |

### board (1)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `wildlife-expedition` | Wildlife Expedition (nature-exploration + wildlife-documentation board game, 2D) | godot | validated | `needs-work/board/wildlife-expedition/` |

### card (6)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `auto-battler` | Auto Battler (Super Auto Pets / How Many Dudes team-shop roguelite, 2D) | godot | validated | `needs-work/card/auto-battler/` |
| `autobattler-horde` | Autobattler Horde (How Many Dudes-style army-scaler, 2D) | godot | validated | `needs-work/card/autobattler-horde/` |
| `deckbuilder` | Deckbuilder (Slay-the-Spire-like) | godot | validated | `needs-work/card/deckbuilder/` |
| `gacha-summon` | Gacha Summon (collection / pity system, 2D) | godot | validated | `needs-work/card/gacha-summon/` |
| `poker-roguelike` | Poker Roguelike (Balatro-style deck-scoring roguelike, 2D) | godot | validated | `needs-work/card/poker-roguelike/` |
| `tcg-duel` | TCG Duel (turn-based card game, 2D) | godot | validated | `needs-work/card/tcg-duel/` |

### puzzle (9)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `block-puzzle` | Block Puzzle (Tetris-lite falling-block line-clearer, 2D) | godot | validated | `needs-work/puzzle/block-puzzle/` |
| `bubble-shooter` | Bubble Shooter (Puzzle Bobble / Bust-a-Move hex match, 2D) | godot | validated | `needs-work/puzzle/bubble-shooter/` |
| `educational-quiz` | Educational Quiz (adaptive timed multiple-choice with a report card, 2D) | godot | validated | `needs-work/puzzle/educational-quiz/` |
| `hidden-object` | Hidden Object (seek-and-find with decoys, hints + timer, 2D) | godot | validated | `needs-work/puzzle/hidden-object/` |
| `match-three` | Match-Three (Kenney Starter Kit Match-3) | godot | base | `needs-work/puzzle/match-three/` |
| `merge-puzzle` | Merge Puzzle (2048-lineage slide-and-merge; a top mobile puzzle, 2D) | godot | validated | `needs-work/puzzle/merge-puzzle/` |
| `peg-roguelike` | Peg Roguelike (Peglin-style pachinko roguelike, 2D) | godot | validated | `needs-work/puzzle/peg-roguelike/` |
| `solitaire` | Solitaire (Klondike patience, draw-1, 2D) | godot | validated | `needs-work/puzzle/solitaire/` |
| `word-puzzle` | Word Puzzle (Wordle-style letter deduction + marathon, 2D) | godot | validated | `needs-work/puzzle/word-puzzle/` |

### strategy (6)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `ant-colony` | Ant Colony (colony ecosystem sim, 2D) | godot | validated | `needs-work/strategy/ant-colony/` |
| `city-builder` | City Builder (grid economy, 2D) | godot | validated | `needs-work/strategy/city-builder/` |
| `god-game` | God Game (top-down deity strategy sim, 2D) | godot | validated | `needs-work/strategy/god-game/` |
| `rts` | Real-Time Strategy (StarCraft/AoE-lite base-build + army, 2D) | godot | validated | `needs-work/strategy/rts/` |
| `tbs-4x` | Turn-Based 4X (Civilization-lite eXplore/eXpand/eXploit/eXterminate, 2D) | godot | validated | `needs-work/strategy/tbs-4x/` |
| `tower-defense` | Tower Defense (lane + towers, 2D) | godot | validated | `needs-work/strategy/tower-defense/` |

### sim (12)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `dating-sim` | Dating Sim (stat-raiser + affection routes + calendar; adult-CAPABLE via a content gate, 2D) | godot | validated | `needs-work/sim/dating-sim/` |
| `dept-store-sim` | Department Store Sim (80s big-box department-store & mail-order sim, 2D) | godot | validated | `needs-work/sim/dept-store-sim/` |
| `falling-sand` | Falling Sand (cellular-automata physics sandbox, 2D) | godot | validated | `needs-work/sim/falling-sand/` |
| `farm-management-sim` | Farm Management Sim (whole-farm operation & commodity economy sim, 2D) | godot | validated | `needs-work/sim/farm-management-sim/` |
| `farming-sim` | Farming Sim (Stardew-like, 2D) | godot | validated | `needs-work/sim/farming-sim/` |
| `idle-clicker` | Idle Clicker (Cookie Clicker-lite incremental with generators + prestige, 2D) | godot | validated | `needs-work/sim/idle-clicker/` |
| `life-sim` | Life Sim (The Sims-lite needs/job/relationships/aspiration, 2D) | godot | validated | `needs-work/sim/life-sim/` |
| `mall-tycoon` | Mall Tycoon (80s shopping-mall management sim, 2D) | godot | validated | `needs-work/sim/mall-tycoon/` |
| `pirate-sim` | Pirate Career Sim (age-of-sail, systemic) | godot | validated | `needs-work/sim/pirate-sim/` |
| `survival-crafting` | Survival Crafting (Don't Starve/Valheim-lite gather/craft/survive, 2D) | godot | validated | `needs-work/sim/survival-crafting/` |
| `video-store-sim` | Video Store Sim (80s VHS-rental-store management sim, 2D) | godot | validated | `needs-work/sim/video-store-sim/` |
| `voxel-sandbox` | Voxel Sandbox (Minecraft-like, 3D) | godot | validated | `needs-work/sim/voxel-sandbox/` |

### narrative (7)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `ff-gamebook` | FF Gamebook (illustrated Fighting-Fantasy book) | godot | validated | `needs-work/narrative/ff-gamebook/` |
| `gamebook` | Gamebook (solo pen-and-paper RPG) | godot | validated | `needs-work/narrative/gamebook/` |
| `gamebook-if` | Gamebook IF (playable computed if-engine gamebook) | godot | validated | `needs-work/narrative/gamebook-if/` |
| `gamebook-if-unity` | Nox Loom Gamebook (Unity) | unity | validated | `needs-work/narrative/gamebook-if-unity/` |
| `noir-detective` | Noir Detective (investigation + deduction, 2D) | godot | validated | `needs-work/narrative/noir-detective/` |
| `point-and-click` | Point-and-Click Adventure | godot | validated | `needs-work/narrative/point-and-click/` |
| `visual-novel` | Visual Novel (with dice checks) | godot | validated | `needs-work/narrative/visual-novel/` |

### multiplayer (2)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `obby-3d-multiplayer` | Obby 3D Multiplayer (3D obstacle course, netcode drop-in) | godot | validated | `needs-work/multiplayer/obby-3d-multiplayer/` |
| `obby-multiplayer` | Obby Multiplayer (2D obstacle course, netcode drop-in) | godot | validated | `needs-work/multiplayer/obby-multiplayer/` |

### adult (4)

| id | name | engine | status | path |
|----|------|--------|--------|------|
| `adult-management` | Adult Management (mature-themed venue/agency tycoon — SYSTEMS ONLY, 2D) | godot | validated | `needs-work/adult/adult-management/` |
| `adult-puzzle-dating` | Adult Puzzle Dating (HuniePop-style match-3 to dating meter — SYSTEMS ONLY, 2D) | godot | validated | `needs-work/adult/adult-puzzle-dating/` |
| `adult-sandbox` | Adult Sandbox (mature-themed open life/relationship sandbox — SYSTEMS ONLY, 2D) | godot | validated | `needs-work/adult/adult-sandbox/` |
| `adult-trainer` | Adult Trainer (mature-themed raise/trainer sim, Princess-Maker lineage — SYSTEMS ONLY, 2D) | godot | validated | `needs-work/adult/adult-trainer/` |

