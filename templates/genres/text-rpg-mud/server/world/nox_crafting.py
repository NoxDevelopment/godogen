"""
Nox Loom MUD — Crafting + Apprenticeship (GEMSTONE4_PARITY_SPEC Part 2, data-driven).

This module implements the deep, career-defining crafting economy from the parity
spec: five TRADES (smithing, tailoring, alchemy, enchanting, herbalism), each with
its own MATERIALS, a rank-gated RECIPES table, and a full APPRENTICESHIP ladder
(Novice -> Apprentice -> Journeyman -> Skilled -> Highly-Skilled -> Master, GS4
rank ladder verbatim, cap 500). Crafting is a genuine NO-COMBAT PROGRESSION PATH:
gathering, refining and crafting all grant trade XP that ranks the trade up.

Design pillars (spec Part 2):
  * APPRENTICESHIP: you must LEARN <trade> from a trainer NPC before you may
    practise it. The trainer teaches; you become an apprentice of that craft.
  * GATHER -> REFINE -> CRAFT supply chain: raw materials (ore/hide/fiber/herb/
    reagent/crystal) are gathered at wilderness/dungeon nodes, refined into
    intermediates (ingot/leather/cloth/extract/charged-crystal), then crafted
    into finished goods. Trades interlock (a steel longsword wants tailor's
    cured leather; an enchanter's amulet wants a smith's ingot) into ONE economy.
  * QUALITY ENGINE: a roll vs (rank + governing-stat bonus - recipe difficulty)
    maps onto the 9-step quality ladder (Perfect..Flimsy) with concrete stat/
    damage/AvD deltas baked onto the crafted item.
  * WORK ORDERS: trainers post standing demand (EASY/CHALLENGING/HARD); filling
    them pays silver + prestige + bonus trade XP. Prestige unlocks MAKER MARKS so
    a master signs their goods (brand identity in the economy).

WORLD COUPLING (coherent across modules): this module owns NO room/NPC keys. It
couples to Agent A's world purely by TAGS — a room tagged ("smithing","nox_workshop")
is the smithy; an NPC tagged ("smithing","nox_trainer") is the weaponsmith who teaches
smithing; a room with db.nox_gather set to a node id is a gathering spot. The
integrator calls wire_crafting_world() in at_server_start with Agent A's real keys
(see WORLD_HOOKS below / integration notes) to stamp those tags.

EVENNIA CONVENTIONS honoured:
  * Interval Script (CraftingTickScript) is (re)created in the server process via
    ensure_crafting_scripts() — call it from at_server_start so its timer arms.
  * OOB payload push_trades() is FLAT (lists-of-scalars only) for the Godot client.
  * Base classes imported from concrete paths (evennia.commands.command.Command,
    evennia.scripts.scripts.DefaultScript).
  * Everything is DATA-DRIVEN module-level tables → maps cleanly to a Ruleset
    builder later.
"""

import random

from evennia.commands.command import Command
from evennia.commands.cmdset import CmdSet
from evennia.scripts.scripts import DefaultScript
from evennia.utils.evtable import EvTable
from evennia.utils.create import create_object, create_script


# =====================================================================
# APPRENTICESHIP RANK LADDER  (GS4-verbatim, spec §"native crafting")
# =====================================================================
# Novice 0-99 / Apprentice 100-199 / Journeyman 200-299 / Skilled 300-399 /
# Highly-Skilled 400-499 / Master 500. Cap per trade = 500 ranks.
RANK_CAP = 500

RANK_LADDER = [
    # (title, min_rank, max_rank, tier_ordinal)
    ("Novice", 0, 99, 0),
    ("Apprentice", 100, 199, 1),
    ("Journeyman", 200, 299, 2),
    ("Skilled", 300, 399, 3),
    ("Highly-Skilled", 400, 499, 4),
    ("Master", 500, 500, 5),
]

# XP → rank curve. Each successive rank costs a little more, so mastery is a long
# grind (thousands of crafts) exactly as the spec's advancement math intends,
# while early ranks come quickly enough to feel rewarding.
RANK_XP_BASE = 40      # xp to go 0 -> 1
RANK_XP_STEP = 6       # extra xp per rank thereafter

# Prestige (from work orders) needed before a crafter may sign a MAKER MARK.
MAKER_MARK_PRESTIGE = 100


# =====================================================================
# TRADES  (spec discipline table; kind + governing stats + workshop tag)
# =====================================================================
# workshop_tag  : the tag key (category "nox_workshop") a room must carry for
#                 recipes of this trade that require a bench.
# trainer_tag   : the tag key (category "nox_trainer") an NPC must carry to teach.
# stats         : governing stats (read from char.db.stats when a stat system
#                 lands; falls back to a level-derived bonus meanwhile).
TRADES = {
    "smithing": {
        "name": "Smithing",
        "kind": "physical_craft",
        "stats": ["strength", "constitution", "discipline"],
        "workshop_tag": "smithing",
        "trainer_tag": "smithing",
        "gather_desc": "ore veins",
        "desc": "Forging weapons, armour and tools from smelted metal. The "
                "smith's craft: ore to ingot to blade at the forge.",
    },
    "tailoring": {
        "name": "Tailoring",
        "kind": "physical_craft",
        "stats": ["dexterity", "discipline", "aura"],
        "workshop_tag": "tailoring",
        "trainer_tag": "tailoring",
        "gather_desc": "beast trails (hides & fibre)",
        "desc": "Curing hides and weaving cloth into leathers, garments and "
                "soft armour at the loom and tanning rack.",
    },
    "alchemy": {
        "name": "Alchemy",
        "kind": "magical_craft",
        "stats": ["intelligence", "wisdom", "discipline"],
        "workshop_tag": "alchemy",
        "trainer_tag": "alchemy",
        "gather_desc": "springs & reagent beds",
        "desc": "Distilling herbs, water and reagents into potions, tonics and "
                "elixirs over the cauldron and alembic.",
    },
    "enchanting": {
        "name": "Enchanting",
        "kind": "magical_craft",
        "stats": ["aura", "intelligence", "wisdom"],
        "workshop_tag": "enchanting",
        "trainer_tag": "enchanting",
        "gather_desc": "crystal hollows (arcane dust & crystal)",
        "desc": "Binding arcane dust and mana crystal into runes, foci and "
                "charmed trinkets at the enchanting brazier.",
    },
    "herbalism": {
        "name": "Herbalism",
        "kind": "gathering_craft",
        "stats": ["wisdom", "dexterity", "intuition"],
        "workshop_tag": "herbalism",       # apothecary bench; most recipes are field-craftable
        "trainer_tag": "herbalism",
        "gather_desc": "herb groves",
        "desc": "Foraging and preparing healing herbs into salves, poultices and "
                "bandages — much of it craftable in the field.",
    },
}


# =====================================================================
# MATERIALS  (spec Material table: category / tier / source / refine chain)
# =====================================================================
# category : ore|ingot|hide|leather|fiber|cloth|herb|reagent|gem|crystal
# tier     : common|magical-common|uncommon|rare
# source   : "gather" (from a node) | "refine" (a recipe output)
MATERIALS = {
    # --- smithing chain: ore -> ingot ---
    "iron_ore":      {"name": "chunk of iron ore",       "category": "ore",     "tier": "common",         "source": "gather"},
    "copper_ore":    {"name": "chunk of copper ore",     "category": "ore",     "tier": "common",         "source": "gather"},
    "coal":          {"name": "lump of coal",            "category": "ore",     "tier": "common",         "source": "gather"},
    "iron_ingot":    {"name": "iron ingot",              "category": "ingot",   "tier": "common",         "source": "refine"},
    "steel_ingot":   {"name": "steel ingot",             "category": "ingot",   "tier": "magical-common", "source": "refine"},
    # --- tailoring chain: hide -> leather / fibre -> cloth ---
    "raw_hide":      {"name": "raw beast hide",          "category": "hide",    "tier": "common",         "source": "gather"},
    "plant_fiber":   {"name": "bundle of plant fibre",   "category": "fiber",   "tier": "common",         "source": "gather"},
    "cured_leather": {"name": "square of cured leather", "category": "leather", "tier": "common",         "source": "refine"},
    "linen_cloth":   {"name": "bolt of linen cloth",     "category": "cloth",   "tier": "common",         "source": "refine"},
    # --- alchemy / herbalism reagents ---
    "red_herb":      {"name": "sprig of bloodleaf",      "category": "herb",    "tier": "common",         "source": "gather"},
    "blue_herb":     {"name": "sprig of azurebell",      "category": "herb",    "tier": "common",         "source": "gather"},
    "spring_water":  {"name": "flask of spring water",   "category": "reagent", "tier": "common",         "source": "gather"},
    "herbal_extract":{"name": "vial of herbal extract",  "category": "reagent", "tier": "magical-common", "source": "refine"},
    # --- enchanting arcana ---
    "arcane_dust":   {"name": "pinch of arcane dust",    "category": "reagent", "tier": "magical-common", "source": "gather"},
    "mana_crystal":  {"name": "raw mana crystal",        "category": "crystal", "tier": "uncommon",       "source": "gather"},
    "charged_crystal":{"name": "charged mana crystal",   "category": "crystal", "tier": "uncommon",       "source": "refine"},
}


# =====================================================================
# GATHER NODES  (spec GatheringNode: region yields + depletion/respawn)
# =====================================================================
# A room becomes a node when mark_gather_node(room, node_id) stamps db.nox_gather.
# Each GATHER draws 1 item from the weighted yield table, depletes stock by 1, and
# grants XP to `trade` (only if the gatherer has LEARNED that trade). Stock
# regenerates toward `capacity` on the CraftingTickScript heartbeat.
GATHER_NODES = {
    "ironvein": {
        "name": "an exposed iron vein",
        "trade": "smithing",
        "capacity": 24,
        "regen": 3,                       # stock restored per tick
        "xp": 8,
        "yields": [("iron_ore", 5), ("copper_ore", 3), ("coal", 2)],
    },
    "beast_trail": {
        "name": "a game trail thick with spoor",
        "trade": "tailoring",
        "capacity": 20,
        "regen": 3,
        "xp": 8,
        "yields": [("raw_hide", 5), ("plant_fiber", 4)],
    },
    "herb_grove": {
        "name": "a grove of wild herbs",
        "trade": "herbalism",
        "capacity": 20,
        "regen": 4,
        "xp": 8,
        "yields": [("red_herb", 5), ("blue_herb", 4)],
    },
    "clear_spring": {
        "name": "a cold clear spring",
        "trade": "alchemy",
        "capacity": 30,
        "regen": 5,
        "xp": 6,
        "yields": [("spring_water", 6), ("blue_herb", 1)],
    },
    "crystal_hollow": {
        "name": "a hollow glittering with crystal",
        "trade": "enchanting",
        "capacity": 16,
        "regen": 2,
        "xp": 10,
        "yields": [("arcane_dust", 5), ("mana_crystal", 2)],
    },
}


# =====================================================================
# RECIPES  (spec Recipe table: inputs -> output, min_rank, difficulty,
#           workshop; output kind "material" refines, "item" crafts a thing)
# =====================================================================
# difficulty : 1..12 tier (Extremely Easy .. Extremely Difficult); the quality
#              engine multiplies it into the roll target.
# min_rank   : the trade rank gate — recipe is LOCKED until you reach it.
# workshop   : trade key of the required bench, or None for field-craftable.
# output     : {"kind":"material","material":id,"qty":n}
#              | {"kind":"item","key":..,"desc":..,"attrs":{..}}
RECIPES = {
    # ---------------- SMITHING ----------------
    "smelt_iron_ingot": {
        "trade": "smithing", "name": "smelt an iron ingot", "min_rank": 0,
        "difficulty": 1, "workshop": "smithing", "xp": 15,
        "inputs": {"iron_ore": 2, "coal": 1},
        "output": {"kind": "material", "material": "iron_ingot", "qty": 1},
    },
    "smelt_steel_ingot": {
        "trade": "smithing", "name": "smelt a steel ingot", "min_rank": 60,
        "difficulty": 3, "workshop": "smithing", "xp": 30,
        "inputs": {"iron_ingot": 2, "coal": 2},
        "output": {"kind": "material", "material": "steel_ingot", "qty": 1},
    },
    "iron_dagger": {
        "trade": "smithing", "name": "forge an iron dagger", "min_rank": 0,
        "difficulty": 2, "workshop": "smithing", "xp": 20,
        "inputs": {"iron_ingot": 1},
        "output": {"kind": "item", "key": "an iron dagger",
                   "desc": "A short, workmanlike iron dagger with a leather-wrapped grip.",
                   "attrs": {"item_type": "weapon", "damage": 6, "avd": 20}},
    },
    "iron_shortsword": {
        "trade": "smithing", "name": "forge an iron shortsword", "min_rank": 40,
        "difficulty": 3, "workshop": "smithing", "xp": 32,
        "inputs": {"iron_ingot": 2},
        "output": {"kind": "item", "key": "an iron shortsword",
                   "desc": "A straight iron shortsword, plain but serviceable.",
                   "attrs": {"item_type": "weapon", "damage": 10, "avd": 24}},
    },
    "steel_longsword": {
        "trade": "smithing", "name": "forge a steel longsword", "min_rank": 120,
        "difficulty": 5, "workshop": "smithing", "xp": 55,
        "inputs": {"steel_ingot": 2, "cured_leather": 1},   # cross-trade: tailor's leather grip
        "output": {"kind": "item", "key": "a steel longsword",
                   "desc": "A fine steel longsword with a leather-wound hilt.",
                   "attrs": {"item_type": "weapon", "damage": 16, "avd": 30}},
    },
    "reinforced_helm": {
        "trade": "smithing", "name": "forge a reinforced helm", "min_rank": 220,
        "difficulty": 7, "workshop": "smithing", "xp": 85,
        "inputs": {"steel_ingot": 3},
        "output": {"kind": "item", "key": "a reinforced steel helm",
                   "desc": "A heavy steel helm, ridged and reinforced across the crown.",
                   "attrs": {"item_type": "armor", "armor": 12}},
    },
    "masterforged_greatsword": {
        "trade": "smithing", "name": "forge a masterforged greatsword", "min_rank": 320,
        "difficulty": 9, "workshop": "smithing", "xp": 120,
        "inputs": {"steel_ingot": 4, "charged_crystal": 1},  # cross-trade: enchanter's crystal
        "output": {"kind": "item", "key": "a masterforged greatsword",
                   "desc": "A immense two-handed blade, its fuller lit by a crystal set in the pommel.",
                   "attrs": {"item_type": "weapon", "damage": 28, "avd": 34}},
    },

    # ---------------- TAILORING ----------------
    "cure_leather": {
        "trade": "tailoring", "name": "cure a square of leather", "min_rank": 0,
        "difficulty": 1, "workshop": "tailoring", "xp": 15,
        "inputs": {"raw_hide": 2},
        "output": {"kind": "material", "material": "cured_leather", "qty": 1},
    },
    "weave_linen": {
        "trade": "tailoring", "name": "weave a bolt of linen", "min_rank": 0,
        "difficulty": 1, "workshop": "tailoring", "xp": 15,
        "inputs": {"plant_fiber": 3},
        "output": {"kind": "material", "material": "linen_cloth", "qty": 1},
    },
    "leather_gloves": {
        "trade": "tailoring", "name": "stitch leather gloves", "min_rank": 0,
        "difficulty": 2, "workshop": "tailoring", "xp": 20,
        "inputs": {"cured_leather": 1},
        "output": {"kind": "item", "key": "a pair of leather gloves",
                   "desc": "Supple leather gloves, close-stitched at the seams.",
                   "attrs": {"item_type": "armor", "armor": 3}},
    },
    "padded_vest": {
        "trade": "tailoring", "name": "sew a padded vest", "min_rank": 50,
        "difficulty": 3, "workshop": "tailoring", "xp": 32,
        "inputs": {"linen_cloth": 2, "cured_leather": 1},
        "output": {"kind": "item", "key": "a padded vest",
                   "desc": "A quilted linen vest faced with cured leather.",
                   "attrs": {"item_type": "armor", "armor": 6}},
    },
    "traveler_cloak": {
        "trade": "tailoring", "name": "tailor a traveller's cloak", "min_rank": 150,
        "difficulty": 5, "workshop": "tailoring", "xp": 55,
        "inputs": {"linen_cloth": 3},
        "output": {"kind": "item", "key": "a traveller's cloak",
                   "desc": "A hooded linen cloak, hemmed for the road.",
                   "attrs": {"item_type": "clothing", "armor": 1}},
    },
    "studded_armor": {
        "trade": "tailoring", "name": "craft studded leather armour", "min_rank": 250,
        "difficulty": 7, "workshop": "tailoring", "xp": 85,
        "inputs": {"cured_leather": 4, "iron_ingot": 1},   # cross-trade: smith's studs
        "output": {"kind": "item", "key": "a suit of studded leather armour",
                   "desc": "Layered leather set with rows of iron studs.",
                   "attrs": {"item_type": "armor", "armor": 14}},
    },

    # ---------------- ALCHEMY ----------------
    "distill_extract": {
        "trade": "alchemy", "name": "distill a herbal extract", "min_rank": 0,
        "difficulty": 2, "workshop": "alchemy", "xp": 18,
        "inputs": {"red_herb": 2, "spring_water": 1},
        "output": {"kind": "material", "material": "herbal_extract", "qty": 1},
    },
    "minor_healing_potion": {
        "trade": "alchemy", "name": "brew a minor healing potion", "min_rank": 0,
        "difficulty": 2, "workshop": "alchemy", "xp": 22,
        "inputs": {"herbal_extract": 1, "spring_water": 1},
        "output": {"kind": "item", "key": "a minor healing potion",
                   "desc": "A small vial of ruby liquid that knits minor wounds.",
                   "attrs": {"item_type": "potion", "effect": "heal", "potency": 20}},
    },
    "stamina_tonic": {
        "trade": "alchemy", "name": "mix a stamina tonic", "min_rank": 40,
        "difficulty": 3, "workshop": "alchemy", "xp": 30,
        "inputs": {"blue_herb": 2, "spring_water": 1},
        "output": {"kind": "item", "key": "a stamina tonic",
                   "desc": "A fizzing blue tonic that restores vigour.",
                   "attrs": {"item_type": "potion", "effect": "stamina", "potency": 30}},
    },
    "mana_elixir": {
        "trade": "alchemy", "name": "compound a mana elixir", "min_rank": 120,
        "difficulty": 5, "workshop": "alchemy", "xp": 55,
        "inputs": {"herbal_extract": 1, "mana_crystal": 1, "spring_water": 1},
        "output": {"kind": "item", "key": "a mana elixir",
                   "desc": "A luminous elixir that rekindles spent mana.",
                   "attrs": {"item_type": "potion", "effect": "mana", "potency": 40}},
    },
    "greater_healing_potion": {
        "trade": "alchemy", "name": "brew a greater healing potion", "min_rank": 220,
        "difficulty": 7, "workshop": "alchemy", "xp": 85,
        "inputs": {"herbal_extract": 2, "red_herb": 2, "spring_water": 2},
        "output": {"kind": "item", "key": "a greater healing potion",
                   "desc": "A deep crimson draught that mends grievous wounds.",
                   "attrs": {"item_type": "potion", "effect": "heal", "potency": 60}},
    },

    # ---------------- HERBALISM (much of it field-craftable: workshop None) ----------------
    "grind_poultice": {
        "trade": "herbalism", "name": "grind a healing poultice", "min_rank": 0,
        "difficulty": 1, "workshop": None, "xp": 15,
        "inputs": {"red_herb": 2},
        "output": {"kind": "item", "key": "a healing poultice",
                   "desc": "A pungent green poultice of mashed bloodleaf.",
                   "attrs": {"item_type": "salve", "effect": "heal", "potency": 12}},
    },
    "herbal_bandage": {
        "trade": "herbalism", "name": "bind a herbal bandage", "min_rank": 0,
        "difficulty": 2, "workshop": None, "xp": 20,
        "inputs": {"linen_cloth": 1, "red_herb": 1},   # cross-trade: tailor's linen
        "output": {"kind": "item", "key": "a herbal bandage",
                   "desc": "A linen bandage steeped in bloodleaf sap.",
                   "attrs": {"item_type": "salve", "effect": "heal", "potency": 18}},
    },
    "antidote_salve": {
        "trade": "herbalism", "name": "prepare an antidote salve", "min_rank": 40,
        "difficulty": 3, "workshop": None, "xp": 28,
        "inputs": {"blue_herb": 2, "spring_water": 1},
        "output": {"kind": "item", "key": "an antidote salve",
                   "desc": "A cooling azurebell salve that draws out venom.",
                   "attrs": {"item_type": "salve", "effect": "antidote", "potency": 25}},
    },
    "restorative_incense": {
        "trade": "herbalism", "name": "compound restorative incense", "min_rank": 150,
        "difficulty": 5, "workshop": "herbalism", "xp": 55,   # needs an apothecary bench
        "inputs": {"red_herb": 3, "arcane_dust": 1},
        "output": {"kind": "item", "key": "a cone of restorative incense",
                   "desc": "A fragrant cone that soothes mind and body when burned.",
                   "attrs": {"item_type": "incense", "effect": "restore", "potency": 35}},
    },

    # ---------------- ENCHANTING ----------------
    "charge_crystal": {
        "trade": "enchanting", "name": "charge a mana crystal", "min_rank": 0,
        "difficulty": 3, "workshop": "enchanting", "xp": 20,
        "inputs": {"mana_crystal": 1, "arcane_dust": 2},
        "output": {"kind": "material", "material": "charged_crystal", "qty": 1},
    },
    "rune_of_warding": {
        "trade": "enchanting", "name": "inscribe a rune of warding", "min_rank": 0,
        "difficulty": 2, "workshop": "enchanting", "xp": 22,
        "inputs": {"arcane_dust": 3},
        "output": {"kind": "item", "key": "a rune of warding",
                   "desc": "A palm-sized stone incised with a faintly glowing ward-rune.",
                   "attrs": {"item_type": "trinket", "effect": "ward", "potency": 10}},
    },
    "glyph_focus": {
        "trade": "enchanting", "name": "bind a glyph focus", "min_rank": 80,
        "difficulty": 4, "workshop": "enchanting", "xp": 42,
        "inputs": {"charged_crystal": 1, "iron_ingot": 1},   # cross-trade: smith's ingot
        "output": {"kind": "item", "key": "a glyph focus",
                   "desc": "An iron-framed crystal focus that sharpens spellcraft.",
                   "attrs": {"item_type": "focus", "effect": "focus", "potency": 15}},
    },
    "amulet_of_vigor": {
        "trade": "enchanting", "name": "enchant an amulet of vigour", "min_rank": 180,
        "difficulty": 6, "workshop": "enchanting", "xp": 70,
        "inputs": {"charged_crystal": 2, "cured_leather": 1},
        "output": {"kind": "item", "key": "an amulet of vigour",
                   "desc": "A leather-corded amulet set with twin humming crystals.",
                   "attrs": {"item_type": "amulet", "effect": "vigor", "potency": 25}},
    },
    "staff_core": {
        "trade": "enchanting", "name": "forge a staff-core enchantment", "min_rank": 300,
        "difficulty": 9, "workshop": "enchanting", "xp": 120,
        "inputs": {"charged_crystal": 3, "mana_crystal": 2},
        "output": {"kind": "item", "key": "an enchanted staff core",
                   "desc": "A lattice of charged crystal, ready to be seated in a staff.",
                   "attrs": {"item_type": "focus", "effect": "focus", "potency": 45}},
    },
}


# =====================================================================
# QUALITY LADDER  (spec 9-step ladder + concrete stat/dmg/AvD deltas)
# =====================================================================
# Each entry: (name, min_margin, str_du_delta, dmg_pct_delta, avd_delta).
# margin = (rank + stat_bonus + d100) - (difficulty * DIFF_WEIGHT).
DIFF_WEIGHT = 25
QUALITY_LADDER = [
    ("perfect",   180,  2,  6,  3),
    ("superior",  140,  2,  4,  2),
    ("elegant",   100,  1,  3,  2),
    ("fine",       70,  1,  2,  1),
    ("nice",       40,  0,  1,  1),
    ("plain",      10,  0,  0,  0),
    ("simple",    -15, -2, -1,  0),
    ("crude",     -40, -5, -3, -1),
    ("flimsy",    -70,-10, -6, -3),
]
FAIL_MARGIN = -70          # below this the attempt fails (materials lost)


# =====================================================================
# WORLD HOOKS  (integrator-edited coupling to Agent A's rooms/NPCs)
# =====================================================================
# The integrator fills these with Agent A's REAL room/NPC keys and calls
# wire_crafting_world() from at_server_start. Keys that don't resolve are
# skipped and returned, so a mismatch is visible, never fatal.
#
#   trainers : trade -> NPC db_key that teaches it (LEARN works in its room)
#   workshops: trade -> room db_key that is that trade's bench
#   nodes    : room db_key -> gather node id (see GATHER_NODES)
WORLD_HOOKS = {
    "trainers": {
        "smithing":   "Doran Kell",
        "tailoring":  "Galt the Furrier",
        "alchemy":    "Mistress Yveline",
        "enchanting": "the enchanter",
        "herbalism":  "Mistress Yveline",
    },
    "workshops": {
        "smithing":   "Bellows & Brand, Weaponsmith",
        "tailoring":  "The Skinner's Rest, Furrier",
        "alchemy":    "The Copper Alembic, Alchemist",
        "enchanting": "the enchanting sanctum",
        "herbalism":  "The Copper Alembic, Alchemist",
    },
    "nodes": {
        # room db_key -> node id
        "the old mine":      "ironvein",
        "the wild trail":    "beast_trail",
        "the herb garden":   "herb_grove",
        "the forest spring": "clear_spring",
        "the crystal cave":  "crystal_hollow",
    },
}


# =====================================================================
# RANK / XP HELPERS
# =====================================================================
def rank_title(rank):
    """Return the ladder title for an integer rank."""
    for title, lo, hi, _ord in RANK_LADDER:
        if lo <= rank <= hi:
            return title
    return "Master" if rank >= RANK_CAP else "Novice"


def tier_ordinal(rank):
    """Return the 0-5 tier ordinal for an integer rank."""
    for _title, lo, hi, ordv in RANK_LADDER:
        if lo <= rank <= hi:
            return ordv
    return 5 if rank >= RANK_CAP else 0


def xp_for_next(rank):
    """XP required to advance from `rank` to `rank+1` (rising cost curve)."""
    if rank >= RANK_CAP:
        return 0
    return RANK_XP_BASE + rank * RANK_XP_STEP


def init_trades(char):
    """Ensure the per-character trade store exists. Namespaced db fields."""
    if char.db.trades is None:
        char.db.trades = {}
    if char.db.materials is None:
        char.db.materials = {}
    if char.db.workorders is None:
        char.db.workorders = []
    if char.db.silver is None:
        char.db.silver = 0
    return char.db.trades


def has_learned(char, trade):
    trades = char.db.trades or {}
    return trade in trades


def learn_trade(char, trade, trainer_key):
    """Enrol the character as an apprentice of `trade` under `trainer_key`."""
    trades = init_trades(char)
    trades[trade] = {
        "rank": 0,
        "xp": 0,
        "prestige": 0,
        "apprenticed_to": trainer_key,
    }
    char.db.trades = trades


def add_trade_xp(char, trade, amount):
    """Add trade XP and auto-advance ranks across the rising-cost curve.

    Returns (ranks_gained, new_rank, new_title). Trade must already be learned.
    """
    trades = char.db.trades or {}
    if trade not in trades:
        return (0, 0, None)
    rec = trades[trade]
    rec["xp"] = int(rec.get("xp", 0)) + int(amount)
    gained = 0
    while rec["rank"] < RANK_CAP and rec["xp"] >= xp_for_next(rec["rank"]):
        rec["xp"] -= xp_for_next(rec["rank"])
        rec["rank"] += 1
        gained += 1
    if rec["rank"] >= RANK_CAP:
        rec["xp"] = 0
    char.db.trades = trades
    return (gained, rec["rank"], rank_title(rec["rank"]))


def stat_bonus(char, trade):
    """Governing-stat bonus for a trade.

    Reads char.db.stats (a future stat system) when present; otherwise derives a
    modest bonus from character level so crafting works today and scales cleanly
    when real attributes land. GS4-style: bonus ~ (stat-50)/2, summed & averaged.
    """
    stats_cfg = TRADES[trade]["stats"]
    char_stats = char.db.stats or {}
    level = int(char.db.level or 1)
    contribs = []
    for s in stats_cfg:
        val = char_stats.get(s)
        if val is None:
            # no stat block yet — proxy from level (centres near 0 at low level)
            contribs.append(level * 1.5)
        else:
            contribs.append((val - 50) / 2.0)
    return int(round(sum(contribs) / max(1, len(contribs))))


# =====================================================================
# RECIPE / MATERIAL HELPERS
# =====================================================================
def trade_recipes(trade):
    """All recipe ids for a trade, ordered by required rank then name."""
    ids = [rid for rid, r in RECIPES.items() if r["trade"] == trade]
    return sorted(ids, key=lambda rid: (RECIPES[rid]["min_rank"], RECIPES[rid]["name"]))


def recipe_unlocked(char, recipe_id):
    """True if the character has learned the trade AND meets the rank gate."""
    r = RECIPES.get(recipe_id)
    if not r:
        return False
    trades = char.db.trades or {}
    rec = trades.get(r["trade"])
    if not rec:
        return False
    return rec.get("rank", 0) >= r["min_rank"]


def known_recipes(char, trade):
    """Recipe ids currently craftable by rank (spec 'db.recipes_known' view)."""
    return [rid for rid in trade_recipes(trade) if recipe_unlocked(char, rid)]


def mat_name(material_id):
    return MATERIALS.get(material_id, {}).get("name", material_id)


def have_qty(char, material_id):
    return int((char.db.materials or {}).get(material_id, 0))


def add_material(char, material_id, qty):
    init_trades(char)
    mats = char.db.materials or {}
    mats[material_id] = mats.get(material_id, 0) + qty
    char.db.materials = mats


def consume_material(char, material_id, qty):
    mats = char.db.materials or {}
    mats[material_id] = mats.get(material_id, 0) - qty
    if mats[material_id] <= 0:
        mats.pop(material_id, None)
    char.db.materials = mats


def missing_inputs(char, recipe_id):
    """Return {material: shortfall} for any inputs the character lacks."""
    r = RECIPES[recipe_id]
    short = {}
    for mid, need in r["inputs"].items():
        have = have_qty(char, mid)
        if have < need:
            short[mid] = need - have
    return short


# =====================================================================
# QUALITY ENGINE
# =====================================================================
def roll_quality(char, recipe_id):
    """Roll the craft outcome.

    Returns a dict: {success, quality, margin, roll, str_du, dmg_pct, avd}.
    success=False means the attempt failed and materials are forfeit.
    """
    r = RECIPES[recipe_id]
    rank = int((char.db.trades or {}).get(r["trade"], {}).get("rank", 0))
    sbonus = stat_bonus(char, r["trade"])
    roll = random.randint(1, 100)
    target = r["difficulty"] * DIFF_WEIGHT
    margin = (rank + sbonus + roll) - target
    if margin < FAIL_MARGIN:
        return {"success": False, "quality": None, "margin": margin, "roll": roll,
                "str_du": 0, "dmg_pct": 0, "avd": 0}
    for name, minm, sdu, dmg, avd in QUALITY_LADDER:
        if margin >= minm:
            return {"success": True, "quality": name, "margin": margin, "roll": roll,
                    "str_du": sdu, "dmg_pct": dmg, "avd": avd}
    # margin between FAIL_MARGIN and lowest band -> flimsy floor
    name, _m, sdu, dmg, avd = QUALITY_LADDER[-1]
    return {"success": True, "quality": name, "margin": margin, "roll": roll,
            "str_du": sdu, "dmg_pct": dmg, "avd": avd}


# =====================================================================
# WORK ORDERS  (spec: standing demand -> silver + prestige + XP; maker marks)
# =====================================================================
WORKORDER_TIERS = {
    # tier -> (qty, silver_per_unit_base, prestige, xp_mult)
    "easy":        (2, 12, 3, 0.5),
    "challenging": (3, 22, 6, 0.8),
    "hard":        (4, 40, 12, 1.2),
}


def _next_order_id(char):
    ids = [o.get("id", 0) for o in (char.db.workorders or [])]
    return (max(ids) + 1) if ids else 1


def offer_work_order(char, trade, tier, master_key):
    """Create a work order for a random rank-appropriate recipe of `trade`.

    Picks from the crafter's currently-unlocked, item-producing recipes so the
    order is always fulfillable. Returns the order dict (or None if none fit).
    """
    candidates = [rid for rid in known_recipes(char, trade)
                  if RECIPES[rid]["output"]["kind"] == "item"]
    if not candidates:
        return None
    recipe_id = random.choice(candidates)
    qty, silver_per, prestige, xp_mult = WORKORDER_TIERS[tier]
    r = RECIPES[recipe_id]
    reward_silver = qty * (silver_per + r["difficulty"] * 4)
    reward_xp = int(r["xp"] * xp_mult * qty)
    order = {
        "id": _next_order_id(char),
        "trade": trade,
        "recipe": recipe_id,
        "qty": qty,
        "produced": 0,
        "tier": tier,
        "master": master_key,
        "reward_silver": reward_silver,
        "reward_xp": reward_xp,
        "reward_prestige": prestige,
    }
    orders = char.db.workorders or []
    orders.append(order)
    char.db.workorders = orders
    return order


def credit_work_orders(char, recipe_id):
    """Advance any accepted work orders that want `recipe_id`. Returns completed."""
    orders = char.db.workorders or []
    completed = []
    for o in orders:
        if o["recipe"] == recipe_id and o["produced"] < o["qty"]:
            o["produced"] += 1
            if o["produced"] >= o["qty"]:
                completed.append(o)
    if completed:
        for o in completed:
            char.db.silver = int(char.db.silver or 0) + o["reward_silver"]
            add_trade_xp(char, o["trade"], o["reward_xp"])
            trades = char.db.trades or {}
            if o["trade"] in trades:
                trades[o["trade"]]["prestige"] = \
                    int(trades[o["trade"]].get("prestige", 0)) + o["reward_prestige"]
                char.db.trades = trades
        char.db.workorders = [o for o in orders if o not in completed]
    else:
        char.db.workorders = orders
    return completed


# =====================================================================
# OOB CLIENT PUSH  (FLAT lists-of-scalars — Godot client renders trade ranks)
# =====================================================================
def push_trades(char):
    """Push the character's trade ranks to the rich client as a FLAT OOB payload."""
    trades = char.db.trades or {}
    names, ranks, titles, xp, xp_next, prestige = [], [], [], [], [], []
    for t, rec in trades.items():
        names.append(TRADES.get(t, {}).get("name", t))
        rk = int(rec.get("rank", 0))
        ranks.append(rk)
        titles.append(rank_title(rk))
        xp.append(int(rec.get("xp", 0)))
        xp_next.append(xp_for_next(rk))
        prestige.append(int(rec.get("prestige", 0)))
    char.msg(nox_trades=((), {
        "trades": names,
        "ranks": ranks,
        "tiers": titles,
        "xp": xp,
        "xp_next": xp_next,
        "prestige": prestige,
    }))


# =====================================================================
# WORLD WIRING  (tag Agent A's rooms/NPCs; couple by tag, not by key)
# =====================================================================
def mark_trainer(npc, trade):
    """Tag an NPC as the trainer for a trade (LEARN works in its room)."""
    npc.tags.add(trade, category="nox_trainer")


def mark_workshop(room, trade):
    """Tag a room as a workshop bench for a trade (CRAFT requires it)."""
    room.tags.add(trade, category="nox_workshop")


def mark_gather_node(room, node_id):
    """Turn a room into a gathering node. Idempotent; seeds full stock."""
    if node_id not in GATHER_NODES:
        return False
    room.db.nox_gather = node_id
    if room.db.nox_gather_stock is None:
        room.db.nox_gather_stock = GATHER_NODES[node_id]["capacity"]
    room.tags.add("gather", category="nox_gather")
    return True


def room_is_workshop(room, trade):
    return bool(room) and room.tags.has(trade, category="nox_workshop")


def find_trainer(room, trade):
    """Return the first NPC in the room tagged as trainer for `trade`, or None."""
    if not room:
        return None
    for obj in room.contents:
        try:
            if obj.tags.has(trade, category="nox_trainer"):
                return obj
        except Exception:
            continue
    return None


def wire_crafting_world(hooks=None):
    """Stamp crafting tags onto Agent A's world objects.

    Call from at_server_start (server process). Idempotent. Returns a dict of
    unresolved keys so a world-key mismatch is visible but never fatal.
    Import ObjectDB lazily so this file stays import-safe in tooling.
    """
    from evennia.objects.models import ObjectDB

    hooks = hooks or WORLD_HOOKS
    unresolved = {"trainers": [], "workshops": [], "nodes": []}

    def _first(key):
        return ObjectDB.objects.filter(db_key__iexact=key).first()

    for trade, key in hooks.get("trainers", {}).items():
        npc = _first(key)
        if npc:
            mark_trainer(npc, trade)
        else:
            unresolved["trainers"].append(key)

    for trade, key in hooks.get("workshops", {}).items():
        room = _first(key)
        if room:
            mark_workshop(room, trade)
        else:
            unresolved["workshops"].append(key)

    for key, node_id in hooks.get("nodes", {}).items():
        room = _first(key)
        if room:
            mark_gather_node(room, node_id)
        else:
            unresolved["nodes"].append(key)

    return unresolved


def ensure_crafting_scripts():
    """(Re)create the crafting heartbeat in the SERVER process so its timer arms.

    Per the hard-won Evennia convention, interval scripts only get a live task
    when created here (at_server_start), not when merely restored from the DB.
    """
    from evennia.scripts.models import ScriptDB
    ScriptDB.objects.filter(db_key="nox_crafting_tick").delete()
    create_script(CraftingTickScript)


# =====================================================================
# HEARTBEAT SCRIPT  (gather-node respawn — living economy)
# =====================================================================
class CraftingTickScript(DefaultScript):
    """Regenerates depleted gathering nodes toward capacity on a timer.

    This is what makes gathering a renewable, living-world resource rather than a
    one-shot: over-mined veins recover, so the crafting supply chain is
    self-sustaining without any player present (spec GatheringNode depletion/respawn).
    """

    def at_script_creation(self):
        self.key = "nox_crafting_tick"
        self.desc = "Crafting economy heartbeat — respawns gathering nodes."
        self.interval = 30          # real seconds between regen ticks
        self.persistent = True

    def at_repeat(self):
        from evennia.objects.models import ObjectDB
        for room in ObjectDB.objects.filter(db_key__isnull=False):
            node_id = room.db.nox_gather
            if not node_id or node_id not in GATHER_NODES:
                continue
            node = GATHER_NODES[node_id]
            cap = node["capacity"]
            cur = int(room.db.nox_gather_stock or 0)
            if cur < cap:
                room.db.nox_gather_stock = min(cap, cur + node["regen"])


# =====================================================================
# COMMANDS  (CraftCmdSet — add to CharacterCmdSet; see integration notes)
# =====================================================================
class CmdLearn(Command):
    """
    Apprentice yourself to a trade under a trainer.

    Usage:
      learn                 (list trades the trainer here teaches)
      learn <trade>

    You must be in the same room as a trainer who teaches the trade — the
    weaponsmith teaches smithing, the tailor teaches tailoring, and so on. Once
    apprenticed you may GATHER materials and CRAFT that trade's recipes, ranking
    up from Novice toward Master.
    """

    key = "learn"
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        room = caller.location
        trade = self.args.strip().lower()

        # trainers present in this room
        here = {t: find_trainer(room, t) for t in TRADES}
        present = {t: npc for t, npc in here.items() if npc}

        if not trade:
            if not present:
                caller.msg("There is no trade trainer here. Seek out a master "
                           "craftsman (a weaponsmith, tailor, alchemist, enchanter "
                           "or herbalist) in their workshop.")
                return
            lines = ["|wTraining available here:|n"]
            for t, npc in present.items():
                status = " |g(already learned)|n" if has_learned(caller, t) else ""
                lines.append(f"  {npc.key} teaches |c{TRADES[t]['name']}|n{status}")
            lines.append("Type |wlearn <trade>|n to apprentice yourself.")
            caller.msg("\n".join(lines))
            return

        if trade not in TRADES:
            caller.msg(f"There is no such trade as '{trade}'. Trades: "
                       + ", ".join(TRADES.keys()))
            return

        trainer = present.get(trade)
        if not trainer:
            caller.msg(f"There is no {TRADES[trade]['name']} trainer here to "
                       f"apprentice you. Find the one who teaches it.")
            return

        if has_learned(caller, trade):
            caller.msg(f"{trainer.key} says, \"You are already my apprentice in "
                       f"{TRADES[trade]['name']}. Get to work!\"")
            return

        learn_trade(caller, trade, trainer.key)
        caller.msg(f"|g{trainer.key} takes you on as an apprentice.|n\n"
                   f"You are now a |cNovice|n of |w{TRADES[trade]['name']}|n. "
                   f"{TRADES[trade]['desc']}\n"
                   f"Use |wrecipes {trade}|n to see what you can make, and "
                   f"|wgather|n at {TRADES[trade]['gather_desc']} for materials.")
        if room:
            room.msg_contents(f"{trainer.key} takes {caller.key} on as an "
                              f"apprentice {TRADES[trade]['name'].lower()}.",
                              exclude=[caller])
        push_trades(caller)


class CmdTrades(Command):
    """
    Show the trades you practise and your rank in each.

    Usage:
      trades

    Displays your rank, apprenticeship tier (Novice -> Master), XP progress toward
    the next rank, prestige, and carried silver. Also lists the raw materials you
    are carrying for crafting.
    """

    key = "trades"
    aliases = ["skills"]
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        trades = caller.db.trades or {}
        if not trades:
            caller.msg("You have not apprenticed to any trade yet. Find a trainer "
                       "and use |wlearn <trade>|n to begin.")
        else:
            table = EvTable("Trade", "Tier", "Rank", "XP -> Next", "Prestige",
                            border="cells")
            for t, rec in trades.items():
                rk = int(rec.get("rank", 0))
                nxt = xp_for_next(rk)
                xpstr = "MAX" if nxt == 0 else f"{int(rec.get('xp',0))}/{nxt}"
                table.add_row(TRADES.get(t, {}).get("name", t), rank_title(rk),
                              f"{rk}/{RANK_CAP}", xpstr, int(rec.get("prestige", 0)))
            caller.msg(f"|wYour trades|n  (silver: {int(caller.db.silver or 0)})\n{table}")

        # carried materials
        mats = caller.db.materials or {}
        mats = {m: q for m, q in mats.items() if q > 0}
        if mats:
            matstr = ", ".join(f"{q}x {mat_name(m)}" for m, q in sorted(mats.items()))
            caller.msg(f"|wRaw materials carried:|n {matstr}")
        push_trades(caller)


class CmdRecipes(Command):
    """
    List the recipes of a trade — which you can make and which are still locked.

    Usage:
      recipes <trade>

    Recipes are gated by rank: as you rank up from Novice toward Master, higher
    recipes unlock. Each line shows the rank required, the inputs, and whether you
    currently hold the materials.
    """

    key = "recipes"
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        trade = self.args.strip().lower()
        if not trade or trade not in TRADES:
            caller.msg("Usage: |wrecipes <trade>|n  (trades: "
                       + ", ".join(TRADES.keys()) + ")")
            return

        rec = (caller.db.trades or {}).get(trade)
        cur_rank = int(rec.get("rank", 0)) if rec else None
        header = f"|w{TRADES[trade]['name']} recipes|n"
        if rec:
            header += f"  — you are {rank_title(cur_rank)} (rank {cur_rank})"
        else:
            header += "  — |r(not learned; find a trainer)|n"
        caller.msg(header)

        table = EvTable("Recipe", "Req.Rank", "Bench", "Inputs", "Status",
                        border="cells")
        for rid in trade_recipes(trade):
            r = RECIPES[rid]
            inputs = ", ".join(f"{q}x {mat_name(m)}" for m, q in r["inputs"].items())
            bench = r["workshop"] or "field"
            if cur_rank is None:
                status = "|rlocked|n"
            elif cur_rank < r["min_rank"]:
                status = f"|ylocked (rank {r['min_rank']})|n"
            else:
                short = missing_inputs(caller, rid)
                status = "|gready|n" if not short else "|Cneed mats|n"
            table.add_row(f"|c{rid}|n\n {r['name']}", r["min_rank"], bench,
                          inputs, status)
        caller.msg(str(table))
        caller.msg("Craft with |wcraft <recipe>|n at the matching workshop.")


class CmdGather(Command):
    """
    Gather raw materials from a resource node in the wilds or a dungeon.

    Usage:
      gather

    Some rooms hold resource nodes — ore veins, game trails, herb groves, springs,
    crystal hollows. GATHER draws raw materials and, if you have learned the trade
    that works those materials, grants trade XP (so gathering is progression too).
    Nodes deplete with use and slowly replenish over time.
    """

    key = "gather"
    aliases = ["forage", "mine", "harvest"]
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        room = caller.location
        node_id = room.db.nox_gather if room else None
        if not node_id or node_id not in GATHER_NODES:
            caller.msg("There is nothing here to gather. Seek out ore veins, herb "
                       "groves, game trails, springs or crystal hollows in the wilds.")
            return

        node = GATHER_NODES[node_id]
        stock = int(room.db.nox_gather_stock or 0)
        if stock <= 0:
            caller.msg(f"{node['name'].capitalize()} is exhausted for now; it will "
                       f"replenish in time.")
            return

        # weighted pick from the node's yield table
        pool = []
        for mid, weight in node["yields"]:
            pool.extend([mid] * weight)
        got = random.choice(pool)
        qty = 1
        add_material(caller, got, qty)
        room.db.nox_gather_stock = stock - 1

        msg = (f"You work {node['name']} and recover |c{qty}x {mat_name(got)}|n. "
               f"({room.db.nox_gather_stock} left here)")
        trade = node["trade"]
        if has_learned(caller, trade):
            gained, new_rank, title = add_trade_xp(caller, trade, node["xp"])
            msg += f"\nYou gain {node['xp']} {TRADES[trade]['name']} XP."
            if gained:
                msg += (f" |gYou advance to rank {new_rank} — {title}!|n")
        else:
            msg += (f"\n|y(Apprentice to {TRADES[trade]['name']} to earn XP from "
                    f"this work.)|n")
        caller.msg(msg)
        if room:
            room.msg_contents(f"{caller.key} gathers from {node['name']}.",
                              exclude=[caller])
        push_trades(caller)


class CmdCraft(Command):
    """
    Craft a recipe at a workshop — consumes materials, rolls quality, grants XP.

    Usage:
      craft <recipe>

    You must have learned the trade, met the recipe's rank gate, hold the input
    materials, and (for bench recipes) be standing in the matching workshop — a
    smithy for smithing, a laboratory for alchemy, and so on. Field recipes (some
    herbalism) need no bench. Outcome quality (Perfect..Flimsy) scales with your
    rank, governing stats and a bit of luck, and is stamped on the finished item.
    Fulfilling an accepted work order pays silver + prestige + bonus XP.
    """

    key = "craft"
    aliases = ["make", "forge", "brew"]
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        recipe_id = self.args.strip().lower().replace(" ", "_")
        if not recipe_id:
            caller.msg("Craft what? Use |wrecipes <trade>|n to see recipe ids, "
                       "then |wcraft <recipe>|n.")
            return
        r = RECIPES.get(recipe_id)
        if not r:
            caller.msg(f"There is no recipe '{recipe_id}'. Use |wrecipes <trade>|n.")
            return

        trade = r["trade"]
        if not has_learned(caller, trade):
            caller.msg(f"You have not apprenticed to {TRADES[trade]['name']}. Find "
                       f"its trainer and |wlearn {trade}|n first.")
            return
        if not recipe_unlocked(caller, recipe_id):
            cur = int((caller.db.trades or {})[trade].get("rank", 0))
            caller.msg(f"You are only rank {cur} in {TRADES[trade]['name']}; "
                       f"'{r['name']}' requires rank {r['min_rank']}.")
            return

        # workshop gate
        room = caller.location
        need_bench = r["workshop"]
        if need_bench and not room_is_workshop(room, need_bench):
            caller.msg(f"'{r['name']}' must be worked at a {TRADES[need_bench]['name']} "
                       f"workshop. You are not at one.")
            return

        # material gate
        short = missing_inputs(caller, recipe_id)
        if short:
            need = ", ".join(f"{n} more {mat_name(m)}" for m, n in short.items())
            caller.msg(f"You lack materials for '{r['name']}': need {need}. "
                       f"|wgather|n or craft the intermediate materials first.")
            return

        # consume inputs
        for mid, qnum in r["inputs"].items():
            consume_material(caller, mid, qnum)

        # roll outcome + roundtime flavour
        result = roll_quality(caller, recipe_id)
        out = r["output"]

        if not result["success"]:
            gained, new_rank, title = add_trade_xp(caller, trade, max(2, r["xp"] // 4))
            caller.msg(f"|rYour attempt at {r['name']} fails|n (roll {result['roll']}, "
                       f"margin {result['margin']}). The materials are ruined. "
                       f"You still glean a little experience from the mistake.")
            if gained:
                caller.msg(f"|gYou advance to rank {new_rank} — {title}!|n")
            push_trades(caller)
            return

        quality = result["quality"]

        if out["kind"] == "material":
            add_material(caller, out["material"], out["qty"])
            gained, new_rank, title = add_trade_xp(caller, trade, r["xp"])
            caller.msg(f"You work the {r['name']} and produce |c{out['qty']}x "
                       f"{mat_name(out['material'])}|n |w({quality})|n.")
            caller.msg(f"You gain {r['xp']} {TRADES[trade]['name']} XP.")
            if gained:
                caller.msg(f"|gYou advance to rank {new_rank} — {title}!|n")
            push_trades(caller)
            return

        # ---- finished ITEM ----
        item = create_object("typeclasses.objects.Object",
                             key=out["key"], location=caller)
        item.db.desc = out["desc"]
        # base attrs + quality deltas stamped on the item
        base_attrs = dict(out.get("attrs", {}))
        if "damage" in base_attrs:
            base_attrs["damage"] = max(1, int(round(
                base_attrs["damage"] * (1 + result["dmg_pct"] / 100.0))))
        if "avd" in base_attrs:
            base_attrs["avd"] = base_attrs["avd"] + result["avd"]
        for k, v in base_attrs.items():
            item.attributes.add(k, v)
        item.db.quality = quality
        item.db.quality_mods = {"str_du": result["str_du"],
                                "dmg_pct": result["dmg_pct"],
                                "avd": result["avd"]}
        item.db.crafted_by = caller.key
        item.db.crafted_trade = trade

        # maker mark once prestige-worthy and Journeyman+
        rec = (caller.db.trades or {})[trade]
        marked = ""
        if (int(rec.get("prestige", 0)) >= MAKER_MARK_PRESTIGE
                and tier_ordinal(int(rec.get("rank", 0))) >= 2):
            item.db.maker_mark = caller.key
            item.db.desc = out["desc"] + f" It bears the maker's mark of {caller.key}."
            marked = f" It bears your maker's mark."

        gained, new_rank, title = add_trade_xp(caller, trade, r["xp"])
        caller.msg(f"You craft |c{out['key']}|n of |w{quality}|n quality.{marked}")
        caller.msg(f"You gain {r['xp']} {TRADES[trade]['name']} XP.")
        if gained:
            caller.msg(f"|gYou advance to rank {new_rank} — {title}!|n")
        if room:
            room.msg_contents(f"{caller.key} crafts {out['key']}.", exclude=[caller])

        # work-order fulfillment
        completed = credit_work_orders(caller, recipe_id)
        for o in completed:
            caller.msg(f"|GWork order #{o['id']} complete!|n {o['master']} pays you "
                       f"{o['reward_silver']} silver and {o['reward_prestige']} "
                       f"prestige for {o['qty']}x {RECIPES[o['recipe']]['name']}.")
        push_trades(caller)


class CmdWorkOrders(Command):
    """
    View, request, or abandon crafting work orders from a trainer.

    Usage:
      workorders                         (list your active orders)
      workorders request [easy|challenging|hard]
      workorders abandon <id>

    A trainer of a trade you practise will post standing demand: craft N of a
    given item for silver + prestige + bonus XP. Request one while in the
    trainer's room. Prestige earned this way eventually unlocks your MAKER MARK.
    Fulfil orders simply by crafting the item — see CRAFT.
    """

    key = "workorders"
    aliases = ["workorder", "orders"]
    locks = "cmd:all()"
    help_category = "Crafting"

    def func(self):
        caller = self.caller
        init_trades(caller)
        args = self.args.strip().lower().split()
        orders = caller.db.workorders or []

        if not args:
            if not orders:
                caller.msg("You have no active work orders. Visit a trainer of a "
                           "trade you practise and |wworkorders request|n.")
                return
            table = EvTable("#", "Trade", "Make", "Progress", "Reward", border="cells")
            for o in orders:
                table.add_row(o["id"], TRADES[o["trade"]]["name"],
                              f"{o['qty']}x {RECIPES[o['recipe']]['name']}",
                              f"{o['produced']}/{o['qty']}",
                              f"{o['reward_silver']}s +{o['reward_prestige']}p")
            caller.msg(f"|wYour work orders|n\n{table}")
            return

        if args[0] == "abandon":
            if len(args) < 2 or not args[1].isdigit():
                caller.msg("Usage: |wworkorders abandon <id>|n")
                return
            oid = int(args[1])
            new = [o for o in orders if o["id"] != oid]
            if len(new) == len(orders):
                caller.msg(f"You have no work order #{oid}.")
                return
            caller.db.workorders = new
            caller.msg(f"You abandon work order #{oid}.")
            return

        if args[0] == "request":
            tier = args[1] if len(args) > 1 else "easy"
            if tier not in WORKORDER_TIERS:
                caller.msg("Difficulty must be easy, challenging or hard.")
                return
            room = caller.location
            # a trainer here for one of your practised trades issues the order
            for t in caller.db.trades or {}:
                trainer = find_trainer(room, t)
                if trainer:
                    order = offer_work_order(caller, t, tier, trainer.key)
                    if not order:
                        caller.msg(f"{trainer.key} says, \"You've no recipes I can "
                                   f"set you to yet. Rank up and come back.\"")
                        return
                    caller.msg(f"|g{trainer.key} posts you a {tier} work order "
                               f"(#{order['id']}):|n craft {order['qty']}x "
                               f"{RECIPES[order['recipe']]['name']} for "
                               f"{order['reward_silver']} silver, "
                               f"{order['reward_prestige']} prestige and "
                               f"{order['reward_xp']} bonus XP.")
                    return
            caller.msg("There is no trainer here for a trade you practise.")
            return

        caller.msg("Usage: |wworkorders|n | |wworkorders request [tier]|n | "
                   "|wworkorders abandon <id>|n")


class CraftCmdSet(CmdSet):
    """Crafting + apprenticeship commands. Merge into CharacterCmdSet."""

    key = "CraftCmdSet"

    def at_cmdset_creation(self):
        self.add(CmdLearn())
        self.add(CmdTrades())
        self.add(CmdRecipes())
        self.add(CmdGather())
        self.add(CmdCraft())
        self.add(CmdWorkOrders())
