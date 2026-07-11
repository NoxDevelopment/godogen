@tool
extends "res://addons/popochiu/engine/interfaces/i_character.gd"

# classes ----
const PCHero := preload("res://game/characters/hero/character_hero.gd")
# ---- classes

# nodes ----
var Hero: PCHero : get = get_Hero
# ---- nodes

# functions ----
func get_Hero() -> PCHero: return get_runtime_character("Hero")
# ---- functions

