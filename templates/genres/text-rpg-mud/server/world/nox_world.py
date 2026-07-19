"""
Nox Loom MUD — WORLD + LORE builder (GemStone-IV-structured, original setting).

This module is the canonical source of the game world's GEOGRAPHY, TOWNS, SHOPS,
and NAMED NPCs. It is intentionally DATA-DRIVEN: the world is described in
module-level tables (rooms, exits, npcs, zones) and `build_world()` instantiates
them via Evennia's `create_object`. That maps 1:1 onto a future Ruleset/World
builder — swap the tables, keep the builder.

WORLD (original, not GemStone's Elanthia):
    World .......... AURETHIA — a world woven upon the Great Loom by the first gods.
    Continent ...... OSSANETH — the known continent; frontier of the fading
                     Threadwright kingdoms on the shore of Harrowmere Bay.
    Cosmology ...... Reality is a WEAVE of threads (fate + mana). The gods are
                     Weavers; the dark gods are Threadcutters who would unmake it.
    See world/LORE.md for the full pantheon, calendar, races and timeline.

WHAT THIS BUILDS (idempotent — skips if the starter town already exists):
    * HARROWGATE — starter human frontier HARBOR town on Harrowmere Bay, patron
      goddess Mordwyn (death/rebirth → the respawn/temple anchor). Central square
      hub (5 rooms) + gates + docks + the full fixed service set:
      weaponsmith, armorer, general provisioner, alchemist, furrier, pawnshop,
      bank (counting house), temple, inn+tavern, Trader's Guild (the Threadhouse),
      and a Moot Hall (town law / lockers).
    * THE KING'S ROAD + MISTWOOD FOREST — a wilderness travel stretch (7 rooms)
      linking the two towns, with a wayshrine to Vaeric (god of roads).
    * RAVENHOLT — a walled inland TRADE town (7 rooms) built around the Grand
      Bazaar + a Caravan Yard where the wandering merchant arrives.
    * THE RATWARREN — a starter DUNGEON / hunting area (6 rooms) beneath the
      south gate, tagged as a huntable zone so the ecology module can attach
      creature populations, spawn caps and loot.

STABILITY CONTRACT (other modules depend on these — DO NOT rename casually):
    * Every object built here is tagged with category ``nox_world`` (rooms/exits)
      or ``nox_npc`` (npcs). Look things up by TAG, not by fragile key strings.
    * Shop rooms carry tag ``shop`` + a type tag (weaponsmith/armorer/general/…)
      and ``room.db.shop_type``. Economy/crafting modules attach markets here.
    * NPCs carry a role tag (shopkeeper/innkeeper/trainer/banker/taskmaster/…)
      and ``npc.db.role`` / ``npc.db.shop_type``. Trainer/creature modules bind here.
    * Huntable zone rooms carry tag ``huntable`` + a zone tag; the spawner reads
      ``room.db.zone`` and ``room.db.tier``.
    * The public registries at the bottom (TOWNS, SHOP_ROOMS, NPC_KEYS, ZONES)
      are the documented import surface for other modules.
"""

from evennia import create_object
from evennia.objects.models import ObjectDB
from evennia.utils.search import search_object, search_object_by_tag

from typeclasses.rooms import Room
from typeclasses.exits import Exit
from typeclasses.characters import Character
from typeclasses.objects import Object

# ---------------------------------------------------------------------------
# TAG CATEGORIES (the stable lookup namespace for the whole world)
# ---------------------------------------------------------------------------
CAT_WORLD = "nox_world"   # every room/exit/prop we build
CAT_NPC = "nox_npc"       # every named NPC we build
CAT_ZONE = "nox_zone"     # zone membership (harrowgate/mistwood/ravenholt/ratwarren)
CAT_SHOP = "nox_shop"     # shop-type tag (weaponsmith/armorer/general/…)
CAT_ROLE = "nox_role"     # npc-role tag (shopkeeper/innkeeper/trainer/…)

WORLD_NAME = "Aurethia"
CONTINENT = "Ossaneth"
STARTER_TOWN_HUB = "Harrowgate Town Square, Central"  # idempotency sentinel + spawn

# ---------------------------------------------------------------------------
# PANTHEON — the Weavers (light) / the Sundered (dark) / the Grey Threads (neutral)
# GS4-structured: a king-god, a resurrection deity, an undeath antagonist, a
# destruction "triad", plus domain gods bound to the calendar and to temples.
# Consumed by the lore graph / LLM context and the calendar (month → deity).
# ---------------------------------------------------------------------------
PANTHEON = {
    # ---- The Radiant Weave (light-aligned Weavers) ----
    "Aureon": {"align": "light", "domain": "law, kingship, order, the crown",
               "symbol": "a golden loom-cross", "rank": "King of the Gods"},
    "Sylwenna": {"align": "light", "domain": "wisdom, knowledge, the weaving of fate",
                 "symbol": "a silver spindle", "spouse": "Aureon"},
    "Mordwyn": {"align": "light", "domain": "death, rebirth, winter, safe passage",
                "symbol": "an ivory key", "role": "keeper of the Ivory Gate — RESURRECTION"},
    "Thessaly": {"align": "light", "domain": "nature, harvest, healing, autumn",
                 "symbol": "a sheaf of grain", "spouse": "Baen Torvald"},
    "Baen Torvald": {"align": "light", "domain": "the forge, craft, stone",
                     "symbol": "a veiled hammer", "patron_of": "dwarves"},
    "Solheim": {"align": "light", "domain": "the sun, summer, fire",
                "symbol": "a blazing disc", "spouse": "Eluvaine"},
    "Eluvaine": {"align": "light", "domain": "love, spring, fertility",
                 "symbol": "a white rose", "patron_of": "halflings"},
    "Vaeric": {"align": "light", "domain": "roads, travel, messengers, luck",
               "symbol": "a silver hart", "role": "wayshrine god"},
    "Nyssa": {"align": "light", "domain": "night, dreams, sleep",
              "symbol": "a crescent veil", "role": "chief foe of the dark gods"},
    "Kaethis": {"align": "light", "domain": "strength, valor, honest combat",
                "symbol": "an iron gauntlet"},
    "Maroth": {"align": "light", "domain": "the seas, storms, tides",
               "symbol": "a coral trident"},
    "Cael": {"align": "light", "domain": "festivals, music, mirth",
             "symbol": "a laughing mask", "twin": "Iriel"},
    "Iriel": {"align": "light", "domain": "art, prophecy, visions",
              "symbol": "an open eye", "twin": "Cael"},
    # ---- The Sundered (dark-aligned Threadcutters) ----
    "Malgra": {"align": "dark", "domain": "tyranny, domination, darkness",
               "symbol": "a black crown", "rank": "Queen of the Sundered"},
    "Vorlyx": {"align": "dark", "domain": "undeath, lies, soul-binding",
               "symbol": "a green coiled serpent", "role": "raiser of the undead"},
    "Xeru": {"align": "dark", "domain": "nightmares, madness, terror",
             "symbol": "a black jackal", "triad": True},
    "Thann'Vok": {"align": "dark", "domain": "annihilation, demon-summoning",
                  "symbol": "a six-rayed void-star", "epithet": "the Unmaker",
                  "role": "would cut the Loom's threads", "triad": True},
    "Ghorros": {"align": "dark", "domain": "suffering, torture",
                "symbol": "a barbed chain"},
    "Karneth": {"align": "dark", "domain": "bloodlust, war-frenzy",
                "symbol": "a red scimitar"},
    "Ossivane": {"align": "dark", "domain": "forbidden knowledge, fire-theft",
                 "symbol": "a burning book", "epithet": "the Grandfather"},
    # ---- The Grey Threads (neutral) ----
    "Nemora": {"align": "neutral", "domain": "final and true death",
               "symbol": "a silver sickle", "role": "pariah among the gods"},
    "Zaleth": {"align": "neutral", "domain": "the moons, chaos, unlucid freedom",
               "symbol": "a fractured moon"},
    "Volneth": {"align": "neutral", "domain": "the release of the undead",
                "symbol": "a broken shackle", "role": "patron of the Order that frees undead"},
}
# The destruction axis behind cataclysms and undead incursions.
SUNDERED_TRIAD = ["Vorlyx", "Xeru", "Thann'Vok"]

# 12 months + 7 days, each named for a god (1:1 real-time Elanthian-style calendar).
CALENDAR = {
    "months": ["Mordwyn", "Ossivane", "Maroth", "Eluvaine", "Karneth", "Sylwenna",
               "Aureon", "Solheim", "Thessaly", "Iriel", "Baen Torvald", "Malgra"],
    "days": ["Restday", "Volnesday", "Kaethis' Day", "Sylwennight", "Marothday",
             "Day of the Hart", "Feastday"],
}

# ---------------------------------------------------------------------------
# ZONE DEFINITIONS (bounded sub-graphs the ecology / event modules read)
# ---------------------------------------------------------------------------
ZONES = {
    "harrowgate": {"name": "Harrowgate", "kind": "town", "climate": "temperate-maritime",
                   "patron": "Mordwyn", "hub": STARTER_TOWN_HUB},
    "mistwood": {"name": "Mistwood Forest", "kind": "wilderness", "climate": "temperate-maritime",
                 "level_band": [1, 6], "ambient": "misty old-growth forest"},
    "ravenholt": {"name": "Ravenholt", "kind": "town", "climate": "temperate-continental",
                  "patron": "Aureon", "hub": "Ravenholt, Market Square"},
    "ratwarren": {"name": "The Ratwarren", "kind": "dungeon", "climate": "underground",
                  "level_band": [1, 8], "ambient": "flooded sewer catacomb",
                  "spawn_cap": 12, "respawn_secs": 45,
                  "patron_threat": "Vorlyx"},  # undead seep in the deeps
}


# ---------------------------------------------------------------------------
# LOW-LEVEL BUILDERS
# ---------------------------------------------------------------------------
_REVERSE = {
    "north": "south", "south": "north", "east": "west", "west": "east",
    "northeast": "southwest", "southwest": "northeast",
    "northwest": "southeast", "southeast": "northwest",
    "up": "down", "down": "up", "out": "in", "in": "out",
}
_DIR_ALIASES = {
    "north": ["n"], "south": ["s"], "east": ["e"], "west": ["w"],
    "northeast": ["ne"], "northwest": ["nw"], "southeast": ["se"], "southwest": ["sw"],
    "up": ["u"], "down": ["d"], "out": ["o", "exit"], "in": [],
}


def _room(key, desc, zone, *, outdoor=False, extra_tags=(), **dbfields):
    """Create a tagged Room. Idempotent-safe only via the top-level guard."""
    r = create_object(Room, key=key)
    r.db.desc = desc
    r.db.zone = zone
    r.db.outdoor = outdoor  # weather module reads this
    r.tags.add(zone, category=CAT_ZONE)
    r.tags.add("room", category=CAT_WORLD)
    for t in extra_tags:
        r.tags.add(t, category=CAT_WORLD)
    for field, value in dbfields.items():
        setattr(r.db, field, value)
    return r


def _link(src, direction, dest, *, back=None):
    """Create a directional exit src->dest (with movement alias) and the reverse.

    `back` overrides the reverse direction (buildings use back='out').
    Pass back=False to make the exit one-way.
    """
    ex = create_object(Exit, key=direction, aliases=list(_DIR_ALIASES.get(direction, [])),
                        location=src, destination=dest)
    ex.tags.add("exit", category=CAT_WORLD)
    if back is False:
        return
    rev = back if back else _REVERSE[direction]
    rex = create_object(Exit, key=rev, aliases=list(_DIR_ALIASES.get(rev, [])),
                        location=dest, destination=src)
    rex.tags.add("exit", category=CAT_WORLD)


def _shop(square, direction, key, desc, zone, shop_type, **dbfields):
    """Create a shop room, tag it as a shop of `shop_type`, and wire square<->shop."""
    r = _room(key, desc, zone, outdoor=False, extra_tags=("shop", "interior"),
              shop_type=shop_type, is_shop=True, **dbfields)
    r.tags.add("shop", category=CAT_WORLD)
    r.tags.add(shop_type, category=CAT_SHOP)
    _link(square, direction, r, back="out")
    return r


def _npc(key, room, role, desc, *, deity=None, shop_type=None, **dbfields):
    """Create a named, stationary NPC (Character typeclass) and tag its role.

    NPCs are locked so they can't be picked up/puppeted by players. Other modules
    (economy/crafting/magic/combat) attach services/trainers/creatures via the
    role tag + db fields set here.
    """
    n = create_object(Character, key=key, location=room)
    n.db.desc = desc
    n.db.is_npc = True
    n.db.role = role
    n.db.home_room = room.key
    if deity:
        n.db.deity = deity
    if shop_type:
        n.db.shop_type = shop_type
    for field, value in dbfields.items():
        setattr(n.db, field, value)
    n.tags.add("npc", category=CAT_NPC)
    n.tags.add(role, category=CAT_ROLE)
    # NB: NPCs are NOT tagged with CAT_SHOP (that category is room-only, so
    # shops_by_type() returns shop ROOMS, not keepers). Find a keeper via its
    # room, its role tag, or db.shop_type.
    # keep NPCs put: no puppeting, no getting.
    n.locks.add("puppet:false();get:false()")
    return n


def _sign(room, key, desc):
    """A readable signpost/notice prop (base Object) for travel wayfinding."""
    s = create_object(Object, key=key, location=room)
    s.db.desc = desc
    s.tags.add("signpost", category=CAT_WORLD)
    s.locks.add("get:false()")
    return s


# ---------------------------------------------------------------------------
# THE WORLD BUILD
# ---------------------------------------------------------------------------
def build_world():
    """Idempotently construct Aurethia's starter region. Safe to call every start.

    Returns a summary dict (rooms/npcs/exits created) or {'skipped': True}.
    """
    if ObjectDB.objects.filter(db_key=STARTER_TOWN_HUB).exists():
        return {"skipped": True, "reason": "world already built"}

    before_rooms = ObjectDB.objects.filter(db_typeclass_path__icontains="rooms.Room").count()

    # =====================================================================
    # HARROWGATE — starter harbor town. Central square hub + 4 sub-squares.
    # =====================================================================
    central = _room(
        STARTER_TOWN_HUB,
        "A broad cobbled square anchors the frontier town of Harrowgate. At its "
        "heart a weathered fountain runs beneath a marble statue of Mordwyn, the "
        "veiled goddess of the Ivory Gate, an ivory key held out in her carven "
        "hand. Salt wind off Harrowmere Bay carries the cry of gulls and the "
        "clamour of trade. Streets radiate to every quarter of the town.",
        "harrowgate", outdoor=True, is_hub=True, safe=True)

    sq_n = _room("Harrowgate Town Square, North",
                 "The northern reach of the square, where the cobbles give way to "
                 "the packed earth of the road to the North Gate. A whitewashed "
                 "temple stands to the west and the warm glow of an inn to the east.",
                 "harrowgate", outdoor=True, safe=True)
    sq_s = _room("Harrowgate Town Square, South",
                 "The southern square slopes toward the old south gate and the "
                 "rusted sewer grate beside it. The mingled smells of tanned hide "
                 "and a pawnbroker's must hang in the air.",
                 "harrowgate", outdoor=True, safe=True)
    sq_e = _room("Harrowgate Town Square, East",
                 "The east quarter rings with hammer-song. A weaponsmith's forge "
                 "glows to the east, an armorer's shop stands north, and the sharp "
                 "reek of an alchemist's shop drifts from the south.",
                 "harrowgate", outdoor=True, safe=True)
    sq_w = _room("Harrowgate Town Square, West",
                 "The west quarter is the town's counting-heart: a stone bank, a "
                 "well-stocked provisioner, and the pillared hall of the "
                 "Threadwrights' merchant guild face the square here.",
                 "harrowgate", outdoor=True, safe=True)

    _link(central, "north", sq_n)
    _link(central, "south", sq_s)
    _link(central, "east", sq_e)
    _link(central, "west", sq_w)

    # ---- Gates, docks, moot hall (hang off the hub / sub-squares) ----
    north_gate = _room("Harrowgate, North Gate",
                       "A timber-and-iron gate in the town's palisade. Beyond it "
                       "the King's Road winds north toward the dark eaves of "
                       "Mistwood Forest and, days beyond, the walled town of "
                       "Ravenholt. A guard nods travellers through.",
                       "harrowgate", outdoor=True, is_gate=True)
    _link(sq_n, "north", north_gate)

    south_gate = _room("Harrowgate, South Gate",
                       "The lesser south gate, half-forgotten, opens onto scrub and "
                       "the coast road. Beside it a heavy iron grate hangs open over "
                       "a reeking stair that drops into the Ratwarren sewers below.",
                       "harrowgate", outdoor=True, is_gate=True)
    _link(sq_s, "south", south_gate)

    harbor = _room("Harrowgate Harbor",
                   "Salt-bleached docks reach out over the grey chop of Harrowmere "
                   "Bay. Fishing smacks and a lone trade cog ride at their moorings, "
                   "rigging creaking. Gulls wheel and quarrel over the fish-market "
                   "slabs. (Sea routes lie beyond, not yet open.)",
                   "harrowgate", outdoor=True, is_dock=True)
    _link(sq_e, "southeast", harbor, back=None)

    moot = _room("Harrowgate Moot Hall",
                 "The town hall of Harrowgate: a draughty stone chamber lined with "
                 "public lockers and a wall of writs, debts and wanted-notices. The "
                 "constable keeps the peace and the town ledger from behind a worn "
                 "oak counter.",
                 "harrowgate", extra_tags=("interior", "civic"), is_civic=True)
    _link(central, "northwest", moot, back="out")

    # ---- The fixed SERVICE SET (each a tagged shop room + a named keeper) ----
    temple = _room("Temple of the Ivory Gate",
                   "Cool white stone and the scent of winter-lilies. Before a black "
                   "altar stands an arch of pale ivory — the Ivory Gate of Mordwyn, "
                   "through which the faithful dead are said to return to life. "
                   "Offering-basins flank the altar; a priestess tends the flame.",
                   "harrowgate", extra_tags=("interior", "temple"),
                   is_temple=True, is_altar=True, is_respawn=True, deity="Mordwyn")
    temple.tags.add("temple", category=CAT_WORLD)
    _link(sq_n, "west", temple, back="out")

    inn = _room("The Salted Griffin Inn",
                "A low-beamed common room warmed by a driftwood fire, thick with "
                "pipe-smoke, ale and the murmur of travellers' talk. A rumor-board "
                "by the door bristles with pinned notices; a stair climbs to the "
                "rooms above where a weary adventurer may rest and recover.",
                "harrowgate", extra_tags=("interior", "inn"),
                is_inn=True, is_rest=True)
    inn.tags.add("inn", category=CAT_WORLD)
    _link(sq_n, "east", inn, back="out")

    smith = _shop(sq_e, "east", "Bellows & Brand, Weaponsmith",
                  "Racks of blades line the walls — arming swords, war-axes, "
                  "spear-heads and daggers — lit red by a roaring forge. The ring "
                  "of hammer on anvil never quite stops. A broad-shouldered smith "
                  "works the coals, taking custom orders as readily as coin.",
                  "harrowgate", "weaponsmith")
    armory = _shop(sq_e, "north", "The Ironward, Armorer",
                   "Suits of mail, banded leather and plate hang from crossbeams "
                   "like sleeping sentinels. Shields of every make lean in ordered "
                   "rows. The air smells of oil and steel. The armorer eyes each "
                   "customer's build with a fitter's practised measure.",
                   "harrowgate", "armorer")
    alchemist = _shop(sq_e, "south", "The Copper Alembic, Alchemist",
                      "Shelves of stoppered vials, dried herbs in hanging bunches, "
                      "and copper stills that drip and hiss fill this cramped, "
                      "pungent shop. Potions glow faintly on the counter. The "
                      "herbalist grinds something bitter with a pestle.",
                      "harrowgate", "alchemist")
    furrier = _shop(sq_s, "west", "The Skinner's Rest, Furrier",
                    "Pelts, hides and stranger trophies — mandibles, claws, tufts "
                    "of fur — hang cured from every rafter. A stout furrier haggles "
                    "over each skin brought in from the wilds, coin-purse ready.",
                    "harrowgate", "furrier")
    pawn = _shop(sq_s, "east", "Harrowgate Pawnshop",
                 "A cluttered front room where a sharp-eyed broker BUYS the odds "
                 "and ends adventurers drag in; a curtained back room holds his "
                 "used stock, offered for SALE to those hunting a bargain.",
                 "harrowgate", "pawnshop", has_back_room=True)
    general = _shop(sq_w, "north", "Harrowgate General Provisioner",
                    "A dry, well-ordered store stacked to the beams with the "
                    "traveller's needful things: backpacks and belt-pouches, coils "
                    "of rope, torches and lantern-oil, tinder, rations and skins of "
                    "water. The old provisioner knows his stock to the last nail.",
                    "harrowgate", "general")
    bank = _shop(sq_w, "west", "Harrowgate Counting House",
                 "A sober stone hall floored in slate, its far end barred by an "
                 "iron-grilled counter. Behind it a banker weighs silver, issues "
                 "promissory notes, and keeps the accounts of half the town in "
                 "ledgers chained to the desks.",
                 "harrowgate", "bank")
    bank.tags.add("bank", category=CAT_WORLD)
    guild = _shop(sq_w, "south", "The Threadhouse",
                  "The pillared commerce-hall of the Threadwrights' Guild, hung "
                  "with the woven sigils of a hundred trading houses. Clerks tally "
                  "cargo manifests at long tables; a task-board of guild bounties "
                  "dominates one wall. This is where trade routes and contracts "
                  "are bought, sold and sworn.",
                  "harrowgate", "guild", is_guild=True, is_bounty_board=True)
    guild.tags.add("guild", category=CAT_WORLD)

    # ---- Harrowgate named NPCs (service anchors + townsfolk agents) ----
    _npc("Sister Almeth", temple, "priest",
         "A grey-robed priestess of Mordwyn, calm-eyed and unhurried, an ivory key "
         "hung at her throat. She tends the altar-flame and speaks softly of the "
         "Ivory Gate and the return of the fallen.",
         deity="Mordwyn", services=["heal", "resurrect", "offering", "bless"])
    _npc("Innkeeper Hollis Barrow", inn, "innkeeper",
         "A round, red-faced man with a spotless apron and a bottomless supply of "
         "gossip, forever polishing a tankard that never seems to get clean.",
         services=["rest", "room", "food", "drink", "rumors"])
    _npc("Doran Kell", smith, "shopkeeper",
         "A broad, soot-streaked weaponsmith with forearms like ship's timber and "
         "a critical squint for any blade that isn't his own work.",
         shop_type="weaponsmith", is_trainer=True, trains=["weaponsmithing"])
    _npc("Sera Vantle", armory, "shopkeeper",
         "A lean, precise armorer with a tailor's eye, chalk always tucked behind "
         "one ear for marking a customer's measure.",
         shop_type="armorer", is_trainer=True, trains=["armorsmithing"])
    _npc("Mistress Yveline", alchemist, "shopkeeper",
         "A slight, stained-fingered herbalist whose sharp gaze misses nothing and "
         "whose shelves hold a remedy — or a poison — for most ailments.",
         shop_type="alchemist", is_trainer=True, trains=["alchemy", "herbalism"])
    _npc("Galt the Furrier", furrier, "shopkeeper",
         "A stout, leather-aproned man reeking pleasantly of tannin, who can price "
         "a pelt at a glance and rarely to the seller's advantage.",
         shop_type="furrier", buys=["pelt", "hide", "trophy"])
    _npc("Fenwick the Broker", pawn, "shopkeeper",
         "A thin, sharp-eyed pawnbroker with quick fingers and quicker sums, who "
         "buys low, sells high, and smiles the whole while.",
         shop_type="pawnshop", buys=["misc"], sells=["used"])
    _npc("Old Perch", general, "shopkeeper",
         "A wiry, white-whiskered shopkeeper perched on a stool behind his counter, "
         "who can lay a hand on any item in his crowded store without looking.",
         shop_type="general")
    _npc("Bergen Coyle", bank, "banker",
         "A precise, ink-stained banker in a sober coat, spectacles low on his "
         "nose, who trusts silver rather more than he trusts men.",
         shop_type="bank", services=["deposit", "withdraw", "note", "exchange"])
    _npc("Guildmistress Corvane", guild, "trainer",
         "The stern, silver-haired mistress of the Threadwrights' Guild, draped in "
         "a merchant's finery, who weighs every visitor as a potential ledger-entry.",
         is_trainer=True, trains=["trading", "appraisal"], services=["contracts", "membership"])
    _npc("Taskmaster Rhodric", guild, "taskmaster",
         "A scarred, plain-spoken veteran who runs the guild's bounty-board, "
         "matching adventurers to the town's dirty work for silver and standing.",
         is_bounty_giver=True, services=["bounty", "reward"])
    _npc("Constable Vael", moot, "constable",
         "The town constable: a grizzled, watchful woman in a mail shirt with the "
         "town seal at her collar, keeper of Harrowgate's law and its lockers.",
         services=["law", "locker"])

    # Signposts / wayfinding at the gates.
    _sign(north_gate, "a weathered signpost",
          "Carved and painted arrows point along the King's Road: NORTH — the Old "
          "Bridge, Mistwood Forest, and Ravenholt beyond. A smaller notice warns "
          "travellers of brigands and worse under the misty trees.")
    _sign(south_gate, "a rusted warning-board",
          "A rust-streaked board nailed beside the sewer grate reads: BY ORDER OF "
          "THE CONSTABLE — the Ratwarren below is overrun with vermin. Cullers "
          "wanted; the unwary need not return.")

    # =====================================================================
    # THE KING'S ROAD + MISTWOOD FOREST — wilderness travel stretch north.
    # =====================================================================
    milepost = _room("The King's Road, First Milepost",
                     "The King's Road runs north from Harrowgate's gate, a rutted "
                     "track of packed earth between hedgerows. A moss-grown milepost "
                     "marks the way; ahead the land dips toward the sound of a river.",
                     "mistwood", outdoor=True)
    _link(north_gate, "north", milepost)

    bridge = _room("The King's Road, Old Bridge",
                   "A humpbacked stone bridge, ancient and lichen-clad, carries the "
                   "road over the swift brown Harrow. Water chuckles among the piers "
                   "below. North of the span the dark treeline of Mistwood begins.",
                   "mistwood", outdoor=True)
    _link(milepost, "north", bridge)

    eaves = _room("Mistwood, Forest Eaves",
                  "The road plunges under the eaves of Mistwood, where old oaks and "
                  "black pines close overhead and a low mist coils between the "
                  "trunks. Birdsong falls away; every snapped twig sounds loud. "
                  "Paths wind deeper north and a game-trail forks east.",
                  "mistwood", outdoor=True, huntable=True, tier=1)
    eaves.tags.add("huntable", category=CAT_WORLD)
    _link(bridge, "north", eaves)

    tangle = _room("Mistwood, Tangled Path",
                   "The way narrows to a root-choked path through dense underbrush. "
                   "Grey moss beards the branches and the mist muffles all sound. "
                   "Something large has broken the ferns off to the side of the trail.",
                   "mistwood", outdoor=True, huntable=True, tier=1)
    tangle.tags.add("huntable", category=CAT_WORLD)
    _link(eaves, "north", tangle)

    shrine = _room("Mistwood, Wayshrine of Vaeric",
                   "A little clearing where a weathered stone shrine to Vaeric, god "
                   "of roads and safe travel, stands wound with faded ribbons and "
                   "the offerings of hopeful travellers — a coin, a horseshoe, a "
                   "pilgrim's worn sandal. The silver hart is carved above the niche.",
                   "mistwood", outdoor=True, is_shrine=True, deity="Vaeric")
    _link(tangle, "east", shrine, back="west")

    far_eaves = _room("Mistwood, Northern Eaves",
                      "The trees begin to thin and the mist lifts; the road firms "
                      "underfoot again as it climbs toward open country. Cart-ruts "
                      "reappear, and ahead the land opens northward.",
                      "mistwood", outdoor=True, huntable=True, tier=1)
    far_eaves.tags.add("huntable", category=CAT_WORLD)
    _link(tangle, "north", far_eaves)

    approach = _room("The King's Road, Ravenholt Approach",
                     "The road crests a low rise and Ravenholt comes into view: a "
                     "grey walled town on the plain, banners at its gate-towers, "
                     "smoke from a hundred chimneys. Caravans are strung along the "
                     "road ahead, waiting their turn at the south gate.",
                     "mistwood", outdoor=True)
    _link(far_eaves, "north", approach)

    # =====================================================================
    # RAVENHOLT — walled inland TRADE town built around the Grand Bazaar.
    # =====================================================================
    rav_gate = _room("Ravenholt, South Gate",
                     "The great south gate of Ravenholt: twin towers of grey stone, "
                     "portcullis raised, gate-wardens waving through a slow river of "
                     "carts and pack-mules. Within, the roar of a market town rises "
                     "to meet you.",
                     "ravenholt", outdoor=True, is_gate=True)
    _link(approach, "north", rav_gate)

    rav_square = _room("Ravenholt, Market Square",
                       "The beating heart of Ravenholt, a vast paved square under a "
                       "statue of Aureon crowned in gold. Every quarter of the town "
                       "opens off it, but all roads seem to lead into the covered "
                       "sprawl of the Grand Bazaar to the north.",
                       "ravenholt", outdoor=True, is_hub=True, safe=True)
    _link(rav_gate, "north", rav_square)

    bazaar = _room("Ravenholt Grand Bazaar",
                   "A cavernous covered market, roofed in weathered canvas and "
                   "ringing with a hundred haggling tongues. Stalls and pitches "
                   "crowd every aisle, selling everything the caravans drag in from "
                   "across Ossaneth. This is the trade-floor other merchants build "
                   "their stalls upon.",
                   "ravenholt", extra_tags=("interior", "shop", "market"),
                   is_shop=True, shop_type="market", is_market=True)
    bazaar.tags.add("shop", category=CAT_WORLD)
    bazaar.tags.add("market", category=CAT_SHOP)
    _link(rav_square, "north", bazaar, back="south")

    caravan = _room("Ravenholt Caravan Yard",
                    "A great dusty yard behind the bazaar, stacked with crates and "
                    "smelling of oxen and axle-grease, where the long-haul caravans "
                    "and travelling merchants make up their trains. On Feastday the "
                    "wandering merchant pitches here.",
                    "ravenholt", extra_tags=("interior",),
                    is_caravan_yard=True, wandering_merchant_stop=True)
    _link(bazaar, "east", caravan, back="west")

    rav_exchange = _shop(rav_square, "east", "Ravenholt Exchange",
                         "A grand banking hall of marble and brass, far busier than "
                         "Harrowgate's — the financial heart of the trade road, "
                         "where notes are cleared, cargoes financed, and fortunes "
                         "counted behind a long grille.",
                         "ravenholt", "bank")
    rav_exchange.tags.add("bank", category=CAT_WORLD)

    rav_general = _shop(rav_square, "west", "Ravenholt Provisioner",
                        "A large, briskly-run supply house catering to caravanners: "
                        "trail rations, harness, waterskins, oil and rope stacked in "
                        "bulk, and a clerk who sells by the crate as gladly as the "
                        "piece.",
                        "ravenholt", "general")

    rav_inn = _room("The Broken Wheel, Tavern",
                    "A big, boisterous caravan-tavern hard by the gate, its sign a "
                    "shattered cartwheel. Teamsters, guards and merchants pack the "
                    "long tables, and the air is loud with deals, dice and travel "
                    "talk. Beds for the road-weary lie upstairs.",
                    "ravenholt", extra_tags=("interior", "inn"),
                    is_inn=True, is_rest=True)
    rav_inn.tags.add("inn", category=CAT_WORLD)
    _link(rav_square, "south", rav_inn, back="out")

    # ---- Ravenholt named NPCs ----
    _npc("Bazaar Master Lysanne", bazaar, "trainer",
         "The elegant, ledger-sharp overseer of the Grand Bazaar, who rents the "
         "stalls, settles disputes, and knows the going price of everything from "
         "here to the coast.",
         is_trainer=True, trains=["trading", "haggling"], services=["stall", "appraisal"])
    _npc("Banker Osric", rav_exchange, "banker",
         "A smooth, immaculately-dressed banker of the Exchange, more comfortable "
         "with a promissory note than a coin, who clears the trade road's debts.",
         shop_type="bank", services=["deposit", "withdraw", "note", "exchange"])
    _npc("Tobin Ashford", rav_general, "shopkeeper",
         "A brisk, no-nonsense provisioner used to outfitting whole caravans, who "
         "quotes prices by the crate before you've finished asking.",
         shop_type="general")
    _npc("Innkeeper Marta", rav_inn, "innkeeper",
         "The broad, booming mistress of the Broken Wheel, who runs her rowdy "
         "tavern with a ladle in one hand and an eye on every purse in the room.",
         services=["rest", "room", "food", "drink", "rumors"])
    _npc("Caravan Master Deggan", caravan, "taskmaster",
         "A weather-beaten caravan master forever counting crates, who hires guards "
         "and hands out escort work between Ravenholt and Harrowgate.",
         is_bounty_giver=True, services=["escort", "caravan"])

    _sign(rav_square, "a great painted directory",
          "A tall painted board lists Ravenholt's quarters: BAZAAR (north) — "
          "EXCHANGE (east) — PROVISIONER (west) — THE BROKEN WHEEL (south) — and, "
          "back through the SOUTH GATE, the King's Road to Mistwood and Harrowgate.")

    # =====================================================================
    # THE RATWARREN — starter DUNGEON / hunting area beneath the south gate.
    # 6 rooms, escalating tier; tagged huntable so the spawner attaches mobs.
    # =====================================================================
    grate = _room("The Ratwarren, Sewer Grate",
                  "The iron stair drops into a low brick tunnel awash with ankle-deep "
                  "filth. Green light from the grate above barely reaches here; "
                  "beyond, the dark drips and squeaks with unseen life. The way out "
                  "climbs back up to the south gate.",
                  "ratwarren", huntable=True, tier=0, extra_tags=("interior", "dungeon"))
    grate.tags.add("huntable", category=CAT_WORLD)
    _link(south_gate, "down", grate, back="up")

    tunnel = _room("The Ratwarren, Dripping Tunnel",
                   "A long brick culvert, slick with slime and echoing with the "
                   "patter of clawed feet. Nests of gnawed bone and rag clot the "
                   "ledges. The stench of vermin is overpowering.",
                   "ratwarren", huntable=True, tier=0, extra_tags=("interior", "dungeon"))
    tunnel.tags.add("huntable", category=CAT_WORLD)
    _link(grate, "north", tunnel)

    junction = _room("The Ratwarren, Flooded Junction",
                     "Several culverts meet in a wide, waist-deep pool of black "
                     "water. Things ripple beneath the surface. A crude driftwood "
                     "walkway crosses toward a fungal glow to the east and a dry "
                     "passage climbing north.",
                     "ratwarren", huntable=True, tier=1, extra_tags=("interior", "dungeon"))
    junction.tags.add("huntable", category=CAT_WORLD)
    _link(tunnel, "north", junction)

    fungal = _room("The Ratwarren, Fungal Cavern",
                   "The brickwork gives way to raw, dripping stone, its walls furred "
                   "with luminous fungus that casts a sickly blue light. Cave "
                   "kobolds have daubed crude sigils here; their reek mixes with the "
                   "spores.",
                   "ratwarren", huntable=True, tier=1, extra_tags=("interior", "dungeon"))
    fungal.tags.add("huntable", category=CAT_WORLD)
    _link(junction, "east", fungal, back="west")

    bonepit = _room("The Ratwarren, Bone Pit",
                    "A domed chamber whose floor is a drift of picked bones, some of "
                    "them disquietingly large — and human. The air here is cold and "
                    "wrong; the followers of Vorlyx are said to seed such places, "
                    "and the bones do not always lie still.",
                    "ratwarren", huntable=True, tier=2, extra_tags=("interior", "dungeon"),
                    is_boss_room=False, threat="Vorlyx")
    bonepit.tags.add("huntable", category=CAT_WORLD)
    _link(junction, "north", bonepit)

    cistern = _room("The Ratwarren, Collapsed Cistern",
                    "The deepest reach of the warren: a vast, half-collapsed cistern "
                    "where black water mirrors a ceiling lost in dark. Something has "
                    "made its lair on the rubble island at the centre — the master "
                    "of the Ratwarren, and the reason cullers are paid so well.",
                    "ratwarren", huntable=True, tier=3, extra_tags=("interior", "dungeon"),
                    is_boss_room=True, threat="Vorlyx")
    cistern.tags.add("huntable", category=CAT_WORLD)
    _link(bonepit, "down", cistern, back="up")

    after_rooms = ObjectDB.objects.filter(db_typeclass_path__icontains="rooms.Room").count()
    return {
        "skipped": False,
        "world": WORLD_NAME,
        "continent": CONTINENT,
        "rooms_created": after_rooms - before_rooms,
        "towns": ["Harrowgate", "Ravenholt"],
        "zones": list(ZONES.keys()),
        "hub": STARTER_TOWN_HUB,
    }


# ---------------------------------------------------------------------------
# LOOKUP HELPERS (the supported API for other modules)
# ---------------------------------------------------------------------------
def get_room(key):
    """Return the Room with this exact key (first match) or None."""
    matches = search_object(key, typeclass=Room)
    return matches[0] if matches else None


def get_npc(key):
    """Return the NPC Character with this exact key (first match) or None."""
    for obj in search_object(key, typeclass=Character):
        if obj.db.is_npc:
            return obj
    return None


def rooms_by_zone(zone_key):
    """All rooms tagged as belonging to a zone (harrowgate/mistwood/ravenholt/ratwarren)."""
    return search_object_by_tag(zone_key, category=CAT_ZONE)


def shops_by_type(shop_type):
    """All shop rooms of a given type (weaponsmith/armorer/general/bank/…)."""
    return search_object_by_tag(shop_type, category=CAT_SHOP)


def npcs_by_role(role):
    """All NPCs of a given role (shopkeeper/innkeeper/banker/taskmaster/…)."""
    return search_object_by_tag(role, category=CAT_ROLE)


# ---------------------------------------------------------------------------
# PUBLIC REGISTRIES — the documented, stable import surface for other modules.
# Keys are the STABLE room/NPC keys; look up live objects via get_room/get_npc,
# or (preferred) via the *_by_tag helpers above.
# ---------------------------------------------------------------------------
TOWNS = {
    "harrowgate": {
        "name": "Harrowgate", "zone": "harrowgate", "patron": "Mordwyn",
        "hub": STARTER_TOWN_HUB, "gates": ["Harrowgate, North Gate", "Harrowgate, South Gate"],
        "is_starter": True,
    },
    "ravenholt": {
        "name": "Ravenholt", "zone": "ravenholt", "patron": "Aureon",
        "hub": "Ravenholt, Market Square", "gates": ["Ravenholt, South Gate"],
        "is_starter": False,
    },
}

# shop_type -> the room key(s) where that service lives (economy/crafting attach here)
SHOP_ROOMS = {
    "weaponsmith": ["Bellows & Brand, Weaponsmith"],
    "armorer": ["The Ironward, Armorer"],
    "alchemist": ["The Copper Alembic, Alchemist"],
    "furrier": ["The Skinner's Rest, Furrier"],
    "pawnshop": ["Harrowgate Pawnshop"],
    "general": ["Harrowgate General Provisioner", "Ravenholt Provisioner"],
    "bank": ["Harrowgate Counting House", "Ravenholt Exchange"],
    "guild": ["The Threadhouse"],
    "temple": ["Temple of the Ivory Gate"],
    "inn": ["The Salted Griffin Inn", "The Broken Wheel, Tavern"],
    "market": ["Ravenholt Grand Bazaar"],
    "civic": ["Harrowgate Moot Hall"],
}

# role -> NPC key(s). db.role, db.shop_type, db.services / db.trains carry detail.
NPC_KEYS = {
    "priest": ["Sister Almeth"],
    "innkeeper": ["Innkeeper Hollis Barrow", "Innkeeper Marta"],
    "banker": ["Bergen Coyle", "Banker Osric"],
    "constable": ["Constable Vael"],
    "taskmaster": ["Taskmaster Rhodric", "Caravan Master Deggan"],
    "trainer": ["Guildmistress Corvane", "Bazaar Master Lysanne"],
    "shopkeeper": [
        "Doran Kell", "Sera Vantle", "Mistress Yveline", "Galt the Furrier",
        "Fenwick the Broker", "Old Perch", "Tobin Ashford",
    ],
}

# Huntable zones the ecology/spawner module should populate (see ZONES for stats).
HUNTABLE_ZONES = ["ratwarren", "mistwood"]

# Respawn / temple altar anchors (respawn system reads these).
RESPAWN_ALTARS = ["Temple of the Ivory Gate"]

# Where the weekly wandering merchant should appear (Feastday).
WANDERING_MERCHANT_STOPS = ["Ravenholt Caravan Yard"]
