# Nox Loom — Pieces & Templates Library

**Two layers.** Games are *composed from pieces* + real assets + genre logic + look/feel.
A Kenney starter kit or an SDK is a **piece/base**, NOT a finished game.

- **Layer 1 — Pieces** (`pieces/<category>/`): reusable building blocks.
- **Layer 2 — Games** (`../templates/genres/`): assembled from pieces, screenshot-verified as real games.

All entries below are **permissive** (MIT / Apache-2.0 / BSD / MPL-2.0 / CC0 / Unlicense / Zlib),
verified by reading each repo's LICENSE. GPL/AGPL/CC-BY-NC and unlicensed candidates were rejected.
Where a demo's **code is MIT but its art is CC-BY-NC**, it's flagged `art:NC` — reuse the code, swap the art.

---

## Full-game templates (fuller than starter kits)
| Name | URL | License | Godot | Genre / note |
|---|---|---|---|---|
| liblast | github.com/unfa/liblast | MIT | 4.x | Complete libre multiplayer FPS |
| Maaack Game Template | github.com/Maaack/Godot-Game-Template | MIT | 4.3 | THE scaffold: menus/options/credits/scene-loader/save/rebind + example game |
| nezvers Godot-GameTemplate | github.com/nezvers/Godot-GameTemplate | MIT | 4.x | Full top-down shooter (menus/AI/pathfinding), original commercial-OK art |
| Nodragem top-down-action-adventure | github.com/Nodragem/top-down-action-adventure-starter-kit | CC0 | 4.3 | Zelda-like top-down action-adventure, ships CC0 art |
| top-down-action-rpg-template | github.com/noidexe/top-down-action-rpg-template | MIT | 4.2 | Top-down action RPG: combat/inventory/quests + demo art |
| Topdown Pixelart Starter | github.com/ForlornU/TopdownStarter | MIT | 4.3 | Top-down: 2 levels, combat, quests, NPC dialogue, pixel art |
| Godot JRPG | github.com/kuryart/godot-jrpg | MIT | 4.6 | RPG-Maker-style JRPG: battle, maps, menus, DB editor |
| Kings and Pigs | github.com/GameEmpire/Kings-and-Pigs | MIT+PixelFrog | 4.5 | 2D action-platformer, ships Pixel Frog sprites + audio |
| GameU 3D Platformer | github.com/ManOfDuck/GameU-3d-platformer | MIT+CC0 | 4.6 | 3D platformer (Kenney fork) |
| SurvivorsStarterKit | github.com/DarkRewar/SurvivorsStarterKit | MIT | 4.6(C#) | Vampire-Survivors: spells/enemies/boss/upgrades, KayKit CC0 |
| Godot-4 2D Bundle (10 games) | github.com/daikang09-bit/Godot-4-Demos-Beginners-Templates | MIT | 4.0+ | 10 complete 2D mini-games, full assets |
| Guitarrada | github.com/sendoestudio/guitarrada | MIT | 4.5 | Rhythm game + built-in level editor, A/V sync |
| ape1121 Tower-Defense | github.com/ape1121/Godot-4-Tower-Defense-Template | MIT | 4.x | Tower-defense: waves/towers/paths |
| godot-open-rpg (GDQuest) | github.com/gdquest-demos/godot-open-rpg | MIT | 4.4 | Turn-based party RPG (crpg + shadowrun-iso base), Kenney CC0 |
| godot-open-rts | github.com/lampe-games/godot-open-rts | MIT | 4.3 | Full RTS, Kenney CC0 3D |
| Kenney Starter Kits (FPS/Racing/City/3D-Platformer/Basic) | github.com/KenneyNL | MIT+CC0 | 4.5 | Genre STARTER BASES (not full games) |

## Pieces — controllers
| Piece | URL | License | Note |
|---|---|---|---|
| Expresso character-controller | github.com/expressobits/character-controller | MIT | FP: walk/crouch/sprint/swim/fly/headbob |
| Whimfoome FirstPersonStarter | github.com/Whimfoome/godot-FirstPersonStarter | MIT | FPS controller starter |
| PantheraDigital Modular Controller | github.com/PantheraDigital/Modular-Character-Controller-for-Godot | MIT | FP/TP/NPC, 2D+3D |
| Ev01 PlatformerController2D | github.com/Ev01/PlatformerController2D | MIT | 2D platformer: double-jump, coyote, buffering |
| catprisbrey Souls-like TP controller | github.com/catprisbrey/Third-Person-Controller--SoulsLIke-Godot4 | MIT | Souls-like melee, combos, 360° cam |
| AMSG advanced movement | github.com/ywmaa/Advanced-Movement-System-Godot | MIT | ALS-style, ships character+anims |
| Cats-Souls-like (full template) | github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template | Unlicense | modular souls-like + asset pack |

## Pieces — multiplayer
| netfox | github.com/foxssake/netfox | MIT | rollback + prediction/reconciliation + interpolation |
| Friendslop-Template | github.com/RGonzalezTech/Friendslop-Template | MIT | lobby/sync/spawn ENet starter |
| GodotSteam | codeberg.org/godotsteam/godotsteam | MIT | Steamworks: lobbies/P2P/achievements |
| Snopek rollback-netcode | gitlab.com/snopek-games/godot-rollback-netcode | MIT | deterministic rollback |
| Nakama Godot | github.com/heroiclabs/nakama-godot | Apache-2.0 | backend: accounts/chat/matchmaking |

## Pieces — combat / stats
| Fray | github.com/Pyxus/fray | MIT | fighting-game input + hitboxes + HSM |
| health-hitbox-hurtbox | github.com/cluttered-code/godot-health-hitbox-hurtbox | MIT | 2D+3D damage components |
| HealthComponent | github.com/BananaHolograma/HealthComponent | MIT | drop-in health/damage |
| EnhancedStat | github.com/Zennyth/EnhancedStat | MIT | reactive stats + modifiers |

## Pieces — inventory
| GLoot | github.com/peter-kish/gloot | MIT | grid/slot inventory + equipment + drag-drop |
| Expresso inventory-system | github.com/expressobits/inventory-system | MIT | modular MP inventory/crafting |

## Pieces — dialogue / narrative
| Dialogic | github.com/dialogic-godot/dialogic | MIT | VN/dialogue editor: characters, timelines, portraits |
| Dialogue Manager | github.com/nathanhoad/godot_dialogue_manager | MIT | branching dialogue |
| godot-ink | github.com/paulloz/godot-ink | MIT | inkle ink (C#) |
| VisualNovelKit | github.com/rakugoteam/VisualNovelKit | MIT | Ren'Py-style VN kit |

## Pieces — UI
| Maaack Menus | github.com/Maaack/Godot-Menus-Template | MIT | main/options/credits/scene-loader |
| Modular Settings Menu | github.com/MarkVelez/godot-modular-settings-menu | MIT | graphics/audio/controls/gameplay |
| Themey | github.com/wadlo/Themey | MIT+CC0 | ready UI theme packs (.tres + art) |
| ThemeGen | github.com/Inspiaaa/ThemeGen | MIT | programmatic themes |

## Pieces — cards / board
| Card Framework (chun92) | github.com/chun92/card-framework | MIT | drag-drop, Pile/Hand, JSON cards, CC0 samples |
| Slay-The-Robot | github.com/DesirePathGames/Slay-The-Robot | MIT | StS-style deckbuilder framework |
| deckbuilder-framework | github.com/insideout-andrew/deckbuilder-framework | MIT | draw/shuffle + full deck |

## Pieces — systems (AI / FSM / procgen / quest / save / camera)
| Beehave | github.com/bitbrain/beehave | MIT | behavior trees + debug view |
| LimboAI | github.com/limbonaut/limboai | MIT | BT + HSM (C++) visual editor |
| godot-statecharts | github.com/derkork/godot-statecharts | MIT | statecharts (nested/parallel FSM) |
| Better-Terrain | github.com/Portponky/better-terrain | Unlicense | autotile/terrain painting + runtime API |
| Gaea | github.com/gaea-godot/gaea | MIT | node-graph procgen 2D/3D |
| Terrain3D | github.com/TokisanGames/Terrain3D | MIT | editable 3D terrain (LOD/foliage/sculpt) |
| godot_voxel | github.com/Zylann/godot_voxel | MIT | voxel terrain/procgen module |
| ProtonScatter | github.com/HungryProton/scatter | MIT | procedural asset placement |
| Questify | github.com/TheWalruzz/godot-questify | MIT | graph quest editor + runtime |
| quest-system | github.com/shomykohai/quest-system | MIT | resource-based quests |
| SaveMadeEasy | github.com/AdamKormos/SaveMadeEasy | MIT | save/load nested vars + encryption |
| Phantom Camera | github.com/ramokz/phantom-camera | MIT | Cinemachine-style camera 2D/3D |
| godot-demo-projects | github.com/godotengine/godot-demo-projects | MIT | official 200+ demo parts bin |

## Pieces — fx / audio
| Resonate | github.com/hugemenace/resonate | MIT | audio manager: pooling/2D-3D/stems/crossfade |
| Sound Manager | github.com/nathanhoad/godot_sound_manager | MIT | music+SFX autoload |
| ceceppa shaders | github.com/ceceppa/godot-shaders | MIT | dissolve/hologram/distortion |
| GDQuest shaders | github.com/gdquest-demos/godot-shaders | MIT (art:NC) | 2D/3D shader library |

---
_Cloned into `pieces/<category>/` as they're adopted; the rest live here as the sourced catalog._
