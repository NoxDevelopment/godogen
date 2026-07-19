"""
Nox Loom MUD — TRADER ECONOMY (the "prosper without combat" loop).

Implements the GEMSTONE4_PARITY_SPEC Part 2 Trader design (the DragonRealms-style
skill-based mercantile layer grafted onto GS4's silver economy), fully data-driven
so it maps 1:1 onto a future Ruleset builder:

  * GOODS      — module-level table {name, low/high silver bands, weight, aliases}.
  * MARKETS    — per-town commodity pits with per-good stock / stock_max / baseline
                 / townBias rows.
  * PRICE      — price = lerp(high, low, stock/stock_max) * (1 + charismaBonus
                 + traderProfessionBonus) * townBias.  Selling INTO a market raises
                 its stock (price falls); buying LOWERS stock (price rises) — self-
                 correcting supply/demand.  A background tick drifts every market's
                 stock back toward its baseline, so buy-low/sell-high arbitrage
                 between the two towns regenerates over time.
  * TRADING    — a skill on the character (db.skills["trading"] rank+xp).  EVERY
                 economic verb (buy / sell / haggle / contract delivery) yields XP,
                 so a player LEVELS purely by trading — zero combat required.
  * APPRAISAL  — a second skill gating how accurately APPRAISE reveals a good's
                 true value (information-asymmetry mechanic).
  * CARAVAN    — carrying capacity = level*4 + 2*trading_rank (haul size is an
                 earned reward that scales with both level and Trading skill).

Commands (TraderCmdSet): WARES, APPRAISE, BUY, SELL, CONTRACT.

WORLD / LORE (original, GS4-structured — coherent with Agent A's world):
Two trading settlements on opposite sides of the Ossaneth highlands drive the
arbitrage loop:

  * EMBERHOLD — an inland forge-and-mine town under the Ossaneth peaks. Chokes
    on its own output: iron ore, silver ingots and timber pile up in SURPLUS and
    sell cheap, while grain, salt, spice and pearl are NEARLY OUT and fetch a
    premium. Patron: Bruknar, the Anvil-Father (smithing / stone).
  * SALTMERE — a coastal harbor town on the Verdant Reach. Salt, grain, furs,
    wool and pearl glut its wharf market and sell cheap; forge goods (iron ore,
    silver ingots, timber) and cut gems are scarce and dear. Patron: Ithe, Lady
    of Tides (sea / trade winds).

So the canonical run is: buy ore/silver cheap in Ravenholt, haul it over the
pass, sell dear in Harrowgate; load up on cheap salt/grain, haul it back, sell dear
in Ravenholt. The drift tick keeps regenerating both sides of the spread.

NOTE ON WORLD OWNERSHIP: Agent A owns the world graph. This module attaches its
commodity pits to real market rooms by, in order: (1) a documented candidate room
key, (2) any room tagged ("market", "economy"), (3) creating a standalone market
room so the module is runnable on its own. See MARKETS[*]["room_keys"] for the
keys — reconcile these with Agent A's actual room keys during integration.

EVENNIA CONVENTIONS honored:
  * Concrete base-class imports (DefaultScript, MuxCommand, CmdSet).
  * The drift Script is created in server/conf/at_server_startstop.at_server_start
    (see the integration snippet) so its LoopingCall timer actually arms.
  * Client OOB payloads are FLAT (scalars + lists-of-scalars only): silvers/skill
    updates go out as nox_econ=((),{flat dict}); the dict-like cargo/board data is
    sent as flat alternating lists the Godot client unpacks in pairs.
"""

import random

from evennia import create_object
from evennia.commands.cmdset import CmdSet
from evennia.commands.default.muxcommand import MuxCommand
from evennia.scripts.scripts import DefaultScript
from evennia.utils.search import search_tag

# Tag used to mark a room as one of our commodity pits (idempotent attach + drift).
MARKET_TAG = "market"
MARKET_TAG_CATEGORY = "economy"

# Starting purse + charisma for a fresh trader (demo defaults; a real char-gen
# system supplies these later).
STARTING_SILVERS = 500
DEFAULT_CHARISMA = 55  # GS4-style 0..100 stat


# ---------------------------------------------------------------------------
# GOODS — the tradeable commodity types. low/high are the silver price band
# (price floats between them by supply); weight is per-unit (flavor / future
# encumbrance). Bands echo the spec's examples (Salt 27-51, gems ~1600).
# ---------------------------------------------------------------------------
GOODS = {
    "grain":        {"name": "sacks of grain",     "low": 18,  "high": 40,   "weight": 3,
                     "aliases": ["grain", "sacks", "wheat"]},
    "salt":         {"name": "blocks of salt",     "low": 27,  "high": 51,   "weight": 2,
                     "aliases": ["salt", "blocks"]},
    "timber":       {"name": "bundles of timber",  "low": 30,  "high": 65,   "weight": 6,
                     "aliases": ["timber", "wood", "lumber", "bundles"]},
    "wool":         {"name": "bales of wool",      "low": 45,  "high": 95,   "weight": 2,
                     "aliases": ["wool", "bales"]},
    "furs":         {"name": "bundles of furs",    "low": 80,  "high": 180,  "weight": 3,
                     "aliases": ["furs", "fur", "pelts"]},
    "iron_ore":     {"name": "crates of iron ore", "low": 55,  "high": 120,  "weight": 8,
                     "aliases": ["iron_ore", "iron", "ore", "iron ore"]},
    "silver_ingot": {"name": "silver ingots",      "low": 200, "high": 420,  "weight": 5,
                     "aliases": ["silver_ingot", "silver", "ingot", "ingots", "silver ingot"]},
    "spice":        {"name": "casks of spice",     "low": 120, "high": 260,  "weight": 1,
                     "aliases": ["spice", "spices", "casks"]},
    "pearl":        {"name": "strands of pearl",   "low": 300, "high": 620,  "weight": 1,
                     "aliases": ["pearl", "pearls", "strand", "strands"]},
    "cut_gem":      {"name": "cut gemstones",      "low": 900, "high": 1600, "weight": 1,
                     "aliases": ["cut_gem", "gem", "gems", "gemstone", "gemstones", "cut gem"]},
}


# ---------------------------------------------------------------------------
# MARKETS — the two commodity pits. Each per-good row: [stock, stock_max,
# baseline, townBias]. stock<baseline => scarcity (dear); stock>baseline =>
# glut (cheap). townBias skews demand: >1 the town wants it (pays/charges more),
# <1 the town is drowning in it. The two towns are mirror images so a two-way
# arbitrage loop always exists.
# ---------------------------------------------------------------------------
MARKETS = {
    "Ravenholt": {
        "board_title": "Ravenholt Commodity Exchange",
        "town_blurb": "Ledger-slates and iron-bound tally boxes crowd the exchange floor "
                      "where caravans from across Ossaneth unload their cargo.",
        # Candidate room keys to attach to (first found wins). "Market Row" is the
        # existing demo room so this pit lights up in the current running world.
        "room_keys": ["Ravenholt Grand Bazaar", "Ravenholt Commodity Exchange", "Ravenholt Market",
                      "Ravenholt Market Row", "Market Row"],
        # good_id: [stock, stock_max, baseline, townBias]
        "stock": {
            "iron_ore":     [92, 100, 85, 0.85],   # SURPLUS  -> buy cheap here
            "silver_ingot": [88, 100, 80, 0.90],   # surplus  -> buy cheap
            "timber":       [85, 100, 80, 0.90],   # surplus  -> buy cheap
            "cut_gem":      [30, 100, 45, 1.05],
            "wool":         [20, 100, 45, 1.10],
            "furs":         [15, 100, 40, 1.10],
            "spice":        [12, 100, 35, 1.15],
            "grain":        [8,  100, 40, 1.15],    # NEARLY OUT -> sell dear here
            "salt":         [6,  100, 35, 1.20],    # NEARLY OUT -> sell dear here
            "pearl":        [5,  100, 30, 1.20],    # NEARLY OUT -> sell dear here
        },
    },
    "Harrowgate": {
        "board_title": "Harrowgate Wharf Market",
        "town_blurb": "Gull-cry and tide-slap drift off Harrowmere Bay through the open market. "
                      "Barrels of brine and bolts of cloth stack to the eaves.",
        "room_keys": ["The Threadhouse", "Harrowgate Wharf Market", "Harrowgate Market",
                      "Harrowgate Harbor Market"],
        "stock": {
            "salt":         [90, 100, 82, 0.85],   # SURPLUS  -> buy cheap here
            "grain":        [88, 100, 80, 0.85],   # surplus  -> buy cheap
            "furs":         [82, 100, 78, 0.90],   # surplus  -> buy cheap
            "pearl":        [80, 100, 72, 0.90],   # surplus  -> buy cheap
            "wool":         [78, 100, 70, 0.90],
            "spice":        [18, 100, 40, 1.10],
            "timber":       [14, 100, 38, 1.10],
            "cut_gem":      [10, 100, 32, 1.15],    # NEARLY OUT -> sell dear here
            "iron_ore":     [7,  100, 35, 1.20],    # NEARLY OUT -> sell dear here
            "silver_ingot": [6,  100, 30, 1.20],    # NEARLY OUT -> sell dear here
        },
    },
}

# Merchant's margin — the spread between what a pit charges to buy FROM it and
# what it pays when you sell INTO it. Small vs. the cross-town scarcity spread,
# so arbitrage is always profitable but not free money on the spot.
BUY_MARKUP = 0.05

# Trading-skill rank ladder (GS4-verbatim apprenticeship bands, 0..500).
RANK_BANDS = [
    (500, "Master"),
    (400, "Highly-Skilled"),
    (300, "Skilled"),
    (200, "Journeyman"),
    (100, "Apprentice"),
    (0,   "Novice"),
]


# ===========================================================================
# SUPPLY STATE
# ===========================================================================
def supply_state(stock, stock_max):
    """Return (key, label, ansi_color) for a stock level (spec's four bands)."""
    pct = (stock / stock_max * 100.0) if stock_max else 0.0
    if pct < 10:
        return ("nearly_out", "Nearly Out", "|r")
    if pct < 50:
        return ("going_fast", "Going Fast", "|y")
    if pct < 80:
        return ("good_stores", "Good Stores", "|g")
    return ("surplus", "Surplus", "|c")


# ===========================================================================
# CHARACTER STATE HELPERS (namespaced db fields; nothing shared touched)
# ===========================================================================
def get_wallet(char):
    """Silver purse (init on first touch)."""
    if char.db.silvers is None:
        char.db.silvers = STARTING_SILVERS
    return char.db.silvers


def get_charisma(char):
    if char.db.charisma is None:
        char.db.charisma = DEFAULT_CHARISMA
    return char.db.charisma


def get_skills(char):
    """db.skills = {"trading": {"rank":int,"xp":int}, "appraisal": {...}}."""
    sk = char.db.skills
    if not sk:
        sk = {"trading": {"rank": 0, "xp": 0}, "appraisal": {"rank": 0, "xp": 0}}
        char.db.skills = sk
    for name in ("trading", "appraisal"):
        if name not in sk:
            sk[name] = {"rank": 0, "xp": 0}
    return sk


def skill_rank(char, skill):
    return int(get_skills(char)[skill]["rank"])


def rank_title(rank):
    for floor, title in RANK_BANDS:
        if rank >= floor:
            return title
    return "Novice"


def xp_needed(rank):
    """XP to advance from `rank` to `rank+1` — a gentle, ever-steepening grind."""
    return 15 + rank * 3


def add_skill_xp(char, skill, amount):
    """Add XP, rolling over into ranks (cap 500). Returns list of announce strings."""
    sk = get_skills(char)
    entry = sk[skill]
    entry["xp"] = int(entry.get("xp", 0)) + int(amount)
    ups = []
    while entry["rank"] < 500 and entry["xp"] >= xp_needed(entry["rank"]):
        entry["xp"] -= xp_needed(entry["rank"])
        entry["rank"] += 1
        ups.append(
            "|GYour %s skill advances to rank %d (%s).|n"
            % (skill.capitalize(), entry["rank"], rank_title(entry["rank"]))
        )
    if entry["rank"] >= 500:
        entry["xp"] = 0
    char.db.skills = sk  # re-assign so the Attribute persists
    return ups


def caravan_capacity(char):
    """Max commodity units haulable = level*4 + 2*trading_rank (spec formula)."""
    level = int(char.db.level or 1)
    return level * 4 + 2 * skill_rank(char, "trading")


def get_cargo(char):
    if char.db.cargo is None:
        char.db.cargo = {}
    return char.db.cargo


def cargo_units(char):
    return sum(int(q) for q in get_cargo(char).values())


def charisma_bonus(char):
    """Charisma -> price bonus, clamped [-0.30, +0.40] (0..100 stat)."""
    cha = get_charisma(char)
    return max(-0.30, min(0.40, (cha - 50) / 125.0))


def trader_profession_bonus(char):
    """Trading rank -> up to +0.60 sell bonus (DR ~60% mercantile edge at mastery)."""
    return min(0.60, skill_rank(char, "trading") / 500.0 * 0.60)


# ===========================================================================
# MARKET / ROOM HELPERS
# ===========================================================================
def market_rooms():
    """All rooms currently carrying one of our commodity pits."""
    return list(search_tag(key=MARKET_TAG, category=MARKET_TAG_CATEGORY))


def find_market_for_town(town):
    """Return the market Room whose pit belongs to `town`, or None."""
    for room in market_rooms():
        data = room.db.nox_market or {}
        if data.get("town") == town:
            return room
    return None


def room_market(room):
    """Return the pit data dict on a room, or None if it isn't a market."""
    if not room:
        return None
    return room.db.nox_market


def base_unit_price(market, good_id):
    """Spec price core: lerp(high, low, stock/stock_max) * townBias.

    lerp(high, low, t) with t = stock/stock_max: empty stock (t=0) -> high
    (scarcity premium); full stock (t=1) -> low (glut discount).
    """
    good = GOODS[good_id]
    row = market["stock"][good_id]
    stock, stock_max, _baseline, bias = row
    t = (stock / stock_max) if stock_max else 0.0
    high, low = good["high"], good["low"]
    lerped = high + (low - high) * t
    return lerped * bias


def buy_price(char, market, good_id):
    """What the pit charges the player to BUY one unit (base + merchant margin,
    trimmed by the buyer's charisma)."""
    base = base_unit_price(market, good_id)
    markup = BUY_MARKUP - charisma_bonus(char) * 0.30  # smooth talker pays less
    markup = max(-0.05, markup)
    return int(round(base * (1 + markup)))


def sell_price(char, market, good_id, haggle_mult):
    """What the pit pays the player to SELL one unit (spec formula: base *
    (1 + charismaBonus + traderProfessionBonus) * haggle)."""
    base = base_unit_price(market, good_id)
    mult = (1 + charisma_bonus(char) + trader_profession_bonus(char)) * haggle_mult
    return int(round(base * mult))


def roll_haggle(char):
    """Resolve a haggle to a price multiplier + a 0..1 'how well it went' score.

    Charisma tilts the negotiation; a random swing keeps it lively. No dice-off
    mini-game (per spec) — it's a stat check that returns a multiplier."""
    swing = random.uniform(-0.05, 0.08)
    mult = 1.0 + charisma_bonus(char) * 0.5 + swing
    mult = max(0.90, min(1.20, mult))
    quality = (mult - 0.90) / 0.30  # 0..1
    return mult, quality


def resolve_good(text):
    """Map free-text ('iron ore', 'ore', 'iron_ore') to a good id, or None."""
    if not text:
        return None
    key = text.strip().lower()
    key_us = key.replace(" ", "_")
    for gid, good in GOODS.items():
        if key in (gid,) or key_us == gid:
            return gid
        if key in good["aliases"] or key_us in good["aliases"]:
            return gid
    # loose substring match on names/aliases as a last resort
    for gid, good in GOODS.items():
        if key in good["name"].lower():
            return gid
        for al in good["aliases"]:
            if key in al or al in key:
                return gid
    return None


def silver(n):
    """Format a silver amount with thousands separators."""
    return "{:,}".format(int(n))


# ===========================================================================
# CLIENT OOB PUSH (FLAT payload only)
# ===========================================================================
def push_econ(char):
    """Push silvers + skills + caravan/cargo to the rich client as a FLAT OOB
    payload (nox_econ), then refresh the standard vitals bars via push_state().

    Everything here is a scalar or a list-of-scalars — the cargo mapping is sent
    as a flat alternating [good, qty, good, qty, ...] list the client unpacks in
    pairs (the webclient serializer collapses nested dicts, so we never send one).
    """
    sk = get_skills(char)
    tr, ap = sk["trading"], sk["appraisal"]
    cargo_flat = []
    for gid, qty in get_cargo(char).items():
        cargo_flat += [GOODS.get(gid, {}).get("name", gid), int(qty)]
    room = char.location
    mk = room_market(room) if room else None
    contract = char.db.trade_contract or {}
    char.msg(nox_econ=((), {
        "silvers": int(get_wallet(char)),
        "charisma": int(get_charisma(char)),
        "trading_rank": int(tr["rank"]),
        "trading_title": rank_title(int(tr["rank"])),
        "trading_xp": int(tr["xp"]),
        "trading_next": int(xp_needed(int(tr["rank"]))),
        "appraisal_rank": int(ap["rank"]),
        "appraisal_title": rank_title(int(ap["rank"])),
        "appraisal_xp": int(ap["xp"]),
        "capacity": int(caravan_capacity(char)),
        "cargo_units": int(cargo_units(char)),
        "cargo": cargo_flat,
        "market_town": (mk.get("town") if mk else ""),
        "contract_good": (GOODS.get(contract.get("good"), {}).get("name", "")
                          if contract else ""),
        "contract_qty": int(contract.get("qty", 0)) if contract else 0,
        "contract_dest": (contract.get("dest_town", "") if contract else ""),
        "contract_payout": int(contract.get("payout", 0)) if contract else 0,
    }))
    # Refresh the standard vitals/level bars too (Character owns push_state).
    if hasattr(char, "push_state"):
        char.push_state()


# ===========================================================================
# WORLD BUILD / ATTACH — call from at_server_start (see integration snippet)
# ===========================================================================
def build_economy(create_missing=True):
    """Attach each town's commodity pit to a real room and (re)seed static config.

    Idempotent: existing stock is PRESERVED across reloads (so live prices / drift
    survive), only the static config (stock_max / baseline / bias / town / title)
    is refreshed. Attachment order per town:
        1) first existing room matching a documented candidate key,
        2) else any room already tagged (market, economy) with no town yet,
        3) else create a standalone market room (only if create_missing).
    """
    from evennia.objects.models import ObjectDB

    attached = {}
    for town, cfg in MARKETS.items():
        room = _find_or_make_market_room(town, cfg, ObjectDB, create_missing)
        if not room:
            continue

        existing = room.db.nox_market or {}
        existing_stock = existing.get("stock", {})
        # Build the fresh stock table, preserving live stock counts where present.
        stock_table = {}
        for gid, (stock0, smax, base, bias) in cfg["stock"].items():
            live = existing_stock.get(gid)
            cur = int(live[0]) if (live and isinstance(live, (list, tuple))) else int(stock0)
            cur = max(0, min(cur, smax))
            stock_table[gid] = [cur, int(smax), int(base), float(bias)]

        room.db.nox_market = {
            "town": town,
            "board_title": cfg["board_title"],
            "stock": stock_table,
        }
        # Enrich the room description with the market blurb (once).
        if cfg["town_blurb"] not in (room.db.desc or ""):
            room.db.desc = ((room.db.desc or "").rstrip()
                            + ("\n\n" if room.db.desc else "")
                            + cfg["town_blurb"]).strip()
        room.tags.add(MARKET_TAG, category=MARKET_TAG_CATEGORY)
        room.tags.add(town.lower().replace(" ", "_"), category="town")
        attached[town] = room
    return attached


def _find_or_make_market_room(town, cfg, ObjectDB, create_missing):
    # 1) documented candidate keys (first hit wins; skip a room already used by
    #    the OTHER town so two towns never collapse onto one room).
    for key in cfg["room_keys"]:
        for room in ObjectDB.objects.filter(db_key=key):
            data = room.db.nox_market or {}
            if data.get("town") in (None, town):
                return room
    # 2) any tagged market room not yet bound to a town.
    for room in market_rooms():
        data = room.db.nox_market or {}
        if not data.get("town"):
            return room
    # 3) create a standalone market room so the module runs on its own.
    if create_missing:
        from typeclasses.rooms import Room
        room = create_object(Room, key=cfg["room_keys"][0])
        room.db.desc = cfg["town_blurb"]
        return room
    return None


# ===========================================================================
# BACKGROUND DRIFT SCRIPT — regenerates arbitrage every tick.
# ===========================================================================
class MarketDriftScript(DefaultScript):
    """Global economic heartbeat: each tick every commodity pit's stock drifts
    back toward its baseline, so surpluses erode and shortages refill — and the
    buy-low/sell-high spread between the two towns continually regenerates.

    MUST be (re)created in at_server_start so its LoopingCall timer arms.
    """

    def at_script_creation(self):
        self.key = "market_drift"
        self.desc = "Drifts every commodity market's stock toward its baseline."
        self.interval = 30  # real seconds per drift tick (demo cadence)
        self.persistent = True

    def at_repeat(self):
        for room in market_rooms():
            data = room.db.nox_market
            if not data:
                continue
            stock_table = data.get("stock", {})
            changed = False
            for gid, row in stock_table.items():
                stock, smax, baseline, bias = row
                gap = baseline - stock
                if gap == 0:
                    continue
                step = max(1, int(round(abs(gap) * 0.15)))
                step = min(step, abs(gap))
                stock += step if gap > 0 else -step
                row[0] = max(0, min(stock, smax))
                changed = True
            if changed:
                room.db.nox_market = data  # re-assign so the Attribute persists


# ===========================================================================
# COMMANDS
# ===========================================================================
class CmdWares(MuxCommand):
    """
    View the local commodity board.

    Usage:
      wares

    Shows every good the local market trades, its current price, its supply
    state (Nearly Out / Going Fast / Good Stores / Surplus) and how many units
    are in stock — plus your purse, your caravan load, and your Trading skill.
    Buy where a good is in Surplus, haul it to a town where it is Nearly Out,
    and sell for a profit.
    """

    key = "wares"
    aliases = ["board", "commodities", "market"]
    locks = "cmd:all()"
    help_category = "Trade"

    def func(self):
        caller = self.caller
        mk = room_market(caller.location)
        if not mk:
            caller.msg("There is no commodity market here. Find a town's trading pit.")
            return

        rows = []
        for gid, row in sorted(mk["stock"].items(),
                               key=lambda kv: base_unit_price(mk, kv[0])):
            stock, smax, _base, _bias = row
            _skey, slabel, scol = supply_state(stock, smax)
            price = buy_price(caller, mk, gid)
            rows.append((GOODS[gid]["name"], price, scol, slabel, stock, smax))

        width = max(len(r[0]) for r in rows)
        out = ["|w%s|n" % mk["board_title"],
               "|W%-*s  %10s  %-12s  %s|n" % (width, "Commodity", "Buy@", "Supply", "Stock")]
        for name, price, scol, slabel, stock, smax in rows:
            out.append("%-*s  %10s  %s%-12s|n  %d/%d"
                       % (width, name, silver(price), scol, slabel, stock, smax))

        cap = caravan_capacity(caller)
        load = cargo_units(caller)
        tr = get_skills(caller)["trading"]
        out.append("")
        out.append("Purse: |Y%s silver|n   Caravan: |c%d/%d units|n   "
                    "Trading: |G%s (rank %d)|n"
                    % (silver(get_wallet(caller)), load, cap,
                       rank_title(int(tr["rank"])), int(tr["rank"])))
        cargo = get_cargo(caller)
        if cargo:
            held = ", ".join("%s x%d" % (GOODS.get(g, {}).get("name", g), q)
                             for g, q in cargo.items())
            out.append("Hauling: %s" % held)
        out.append("(BUY <n> <good> / SELL <n> <good> / APPRAISE <good> / CONTRACT)")
        caller.msg("\n".join(out))


class CmdAppraise(MuxCommand):
    """
    Estimate a commodity's true worth (Appraisal-gated).

    Usage:
      appraise <good>

    A skilled appraiser reads a good's real value; a novice only guesses within
    a wide range. The better your Appraisal skill, the tighter (and eventually
    exact) the estimate. Appraising trains your Appraisal skill.
    """

    key = "appraise"
    aliases = ["value", "eval"]
    locks = "cmd:all()"
    help_category = "Trade"

    def func(self):
        caller = self.caller
        mk = room_market(caller.location)
        if not mk:
            caller.msg("There is nothing to appraise here — find a trading pit.")
            return
        gid = resolve_good(self.args)
        if not gid:
            caller.msg("Appraise what? Try: appraise iron ore")
            return
        if gid not in mk["stock"]:
            caller.msg("This market does not trade %s." % GOODS[gid]["name"])
            return

        true_price = base_unit_price(mk, gid)
        rank = skill_rank(caller, "appraisal")
        # Noise band shrinks from +-40% (novice) toward +-0% (master).
        noise = max(0.0, 0.40 * (1 - rank / 500.0))
        name = GOODS[gid]["name"]
        stock, smax, _b, _bias = mk["stock"][gid]
        _sk, slabel, scol = supply_state(stock, smax)

        if noise < 0.02:
            est = ("Its true market value is |Y%s silver|n per unit."
                   % silver(int(round(true_price))))
        else:
            lo = int(round(true_price * (1 - noise)))
            hi = int(round(true_price * (1 + noise)))
            est = ("You reckon it worth somewhere between |Y%s|n and |Y%s silver|n "
                   "per unit." % (silver(lo), silver(hi)))
        caller.msg("You appraise %s (%s%s|n). %s\nBand: %s-%s silver."
                   % (name, scol, slabel, est,
                      silver(GOODS[gid]["low"]), silver(GOODS[gid]["high"])))

        ups = add_skill_xp(caller, "appraisal", 2)
        for u in ups:
            caller.msg(u)
        push_econ(caller)


class CmdBuy(MuxCommand):
    """
    Buy commodities from the local market.

    Usage:
      buy <quantity> <good>

    Buying LOWERS the market's stock, so each purchase nudges the price up.
    You cannot buy more than the pit has, more than you can afford, or more
    than your caravan can carry (capacity = level*4 + 2*Trading rank). Buying
    trains your Trading skill a little.
    """

    key = "buy"
    locks = "cmd:all()"
    help_category = "Trade"

    def func(self):
        caller = self.caller
        mk = room_market(caller.location)
        if not mk:
            caller.msg("There is no market here to buy from.")
            return
        qty, gid, err = _parse_qty_good(self.args)
        if err:
            caller.msg(err + "  (e.g. buy 5 iron ore)")
            return
        if gid not in mk["stock"]:
            caller.msg("This market does not trade %s." % GOODS[gid]["name"])
            return

        row = mk["stock"][gid]
        stock, smax, base, bias = row
        if stock <= 0:
            caller.msg("The market is completely out of %s." % GOODS[gid]["name"])
            return
        qty = min(qty, stock)

        cap = caravan_capacity(caller)
        room_left = cap - cargo_units(caller)
        if room_left <= 0:
            caller.msg("Your caravan is full (%d/%d units). Sell some cargo first."
                       % (cargo_units(caller), cap))
            return
        qty = min(qty, room_left)

        # Price each unit as stock falls (so bulk buys cost progressively more).
        total = 0
        bought = 0
        for _ in range(qty):
            if row[0] <= 0:
                break
            unit = buy_price(caller, mk, gid)
            if get_wallet(caller) - total < unit:
                break
            total += unit
            row[0] -= 1
            bought += 1
        if bought == 0:
            unit = buy_price(caller, mk, gid)
            caller.msg("You cannot afford even one unit (|Y%s silver|n each; you have "
                       "|Y%s|n)." % (silver(unit), silver(get_wallet(caller))))
            return

        caller.db.silvers = get_wallet(caller) - total
        cargo = get_cargo(caller)
        cargo[gid] = cargo.get(gid, 0) + bought
        caller.db.cargo = cargo
        mk["stock"] = mk["stock"]  # touch
        caller.location.db.nox_market = mk

        avg = total / bought
        caller.msg("You buy |c%d|n %s for |Y%s silver|n (avg |Y%s|n/unit)."
                   % (bought, GOODS[gid]["name"], silver(total), silver(int(round(avg)))))
        _sk, slabel, scol = supply_state(row[0], smax)
        caller.msg("The stall's stock of that good is now %s%s|n (%d/%d)."
                   % (scol, slabel, row[0], smax))

        ups = add_skill_xp(caller, "trading", max(1, bought // 2))
        for u in ups:
            caller.msg(u)
        push_econ(caller)


class CmdSell(MuxCommand):
    """
    Sell commodities into the local market (haggling via Charisma).

    Usage:
      sell <quantity> <good>

    You must be carrying the goods. Selling RAISES the market's stock, so each
    unit sold nudges the price down, and a market already in Surplus refuses to
    buy more. Your Charisma (and Trader profession bonus) sets the price you can
    haggle. Selling is the main way you train Trading — bigger, better-haggled
    sales earn more XP, so you LEVEL by trading, no combat required.
    """

    key = "sell"
    locks = "cmd:all()"
    help_category = "Trade"

    def func(self):
        caller = self.caller
        mk = room_market(caller.location)
        if not mk:
            caller.msg("There is no market here to sell to.")
            return
        qty, gid, err = _parse_qty_good(self.args)
        if err:
            caller.msg(err + "  (e.g. sell 5 iron ore)")
            return

        cargo = get_cargo(caller)
        have = int(cargo.get(gid, 0))
        if have <= 0:
            caller.msg("You are not carrying any %s." % GOODS[gid]["name"])
            return
        if gid not in mk["stock"]:
            caller.msg("This market has no interest in %s." % GOODS[gid]["name"])
            return
        qty = min(qty, have)

        row = mk["stock"][gid]
        stock, smax, base, bias = row
        if stock >= smax:
            caller.msg("The market is glutted with %s (Surplus) and refuses to buy "
                       "more. Haul it elsewhere." % GOODS[gid]["name"])
            return
        room_left = smax - stock
        qty = min(qty, room_left)

        mult, quality = roll_haggle(caller)
        total = 0
        sold = 0
        for _ in range(qty):
            if row[0] >= smax:
                break
            unit = sell_price(caller, mk, gid, mult)
            total += unit
            row[0] += 1
            sold += 1
        if sold == 0:
            caller.msg("The market cannot take any more %s right now." % GOODS[gid]["name"])
            return

        cargo[gid] = have - sold
        if cargo[gid] <= 0:
            del cargo[gid]
        caller.db.cargo = cargo
        caller.db.silvers = get_wallet(caller) + total
        caller.location.db.nox_market = mk

        avg = total / sold
        haggle_word = ("drove a hard bargain" if quality > 0.66 else
                       "haggled fairly" if quality > 0.33 else "took a soft price")
        caller.msg("You %s and sell |c%d|n %s for |Y%s silver|n (avg |Y%s|n/unit)."
                   % (haggle_word, sold, GOODS[gid]["name"], silver(total),
                      silver(int(round(avg)))))
        _sk, slabel, scol = supply_state(row[0], smax)
        caller.msg("The stall's stock of that good is now %s%s|n (%d/%d)."
                   % (scol, slabel, row[0], smax))

        # Trading XP scales with volume AND how well you haggled (spec: more
        # profit -> more Trading XP).
        xp = max(1, int(round(sold * (1.0 + quality)))) + int(total // 200)
        ups = add_skill_xp(caller, "trading", xp)
        for u in ups:
            caller.msg(u)
        push_econ(caller)


class CmdContract(MuxCommand):
    """
    Accept and fulfil a caravan delivery contract.

    Usage:
      contract                 - list offers here (or show your active contract)
      contract accept <n>      - take offer #n (loads the crate onto your caravan)
      contract deliver         - hand off at the destination market for payout
      contract abandon         - drop your current contract (goods are dumped)

    A contract loads a crate of goods onto your caravan for free; haul it to the
    named destination town's market and DELIVER for a fixed payout plus Trading
    XP. The beginner on-ramp before free-form speculation.
    """

    key = "contract"
    aliases = ["contracts", "deliver"]
    locks = "cmd:all()"
    help_category = "Trade"

    def func(self):
        caller = self.caller
        arg = (self.args or "").strip().lower()
        # 'deliver' alias with no subcommand -> deliver.
        if self.cmdstring.lower() == "deliver" and not arg:
            arg = "deliver"

        if arg.startswith("accept"):
            self._accept(caller, arg)
        elif arg.startswith("deliver"):
            self._deliver(caller)
        elif arg.startswith("abandon") or arg.startswith("cancel"):
            self._abandon(caller)
        else:
            self._list(caller)

    # -- listing / generation --------------------------------------------
    def _list(self, caller):
        active = caller.db.trade_contract
        if active:
            caller.msg("|wActive contract:|n deliver |c%d|n %s to |w%s|n for |Y%s silver|n."
                       % (active["qty"], GOODS[active["good"]]["name"],
                          active["dest_town"], silver(active["payout"])))
            caller.msg("Haul it to the %s market and type CONTRACT DELIVER."
                       % active["dest_town"])
            return
        mk = room_market(caller.location)
        if not mk:
            caller.msg("No shipping clerk here. Visit a town market to pick up work.")
            return
        offers = self._generate_offers(caller, mk)
        caller.db.trade_offers = offers
        if not offers:
            caller.msg("The shipping clerk has no work to offer right now.")
            return
        caller.msg("|wDelivery contracts available at %s:|n" % mk["board_title"])
        for i, off in enumerate(offers, 1):
            caller.msg("  %d) Deliver |c%d|n %s to |w%s|n  ->  |Y%s silver|n"
                       % (i, off["qty"], GOODS[off["good"]]["name"],
                          off["dest_town"], silver(off["payout"])))
        caller.msg("(CONTRACT ACCEPT <n> to take one)")

    def _generate_offers(self, caller, mk):
        origin = mk["town"]
        # Destination = the other town that is scarce (dear) in the good.
        dest_town = next((t for t in MARKETS if t != origin), None)
        if not dest_town:
            return []
        dest_mk = MARKETS[dest_town]["stock"]
        # Rank goods by how scarce they are at the destination (best payout first).
        scarce = sorted(dest_mk.items(), key=lambda kv: kv[1][0])
        offers = []
        for gid, (dstock, dmax, dbase, dbias) in scarce[:3]:
            qty = random.randint(5, 12)
            # Payout ~ what the goods fetch dear at the destination, minus a cut.
            unit = GOODS[gid]["high"] * dbias
            payout = int(round(unit * qty * 0.55)) + 40
            offers.append({
                "good": gid, "qty": qty, "origin_town": origin,
                "dest_town": dest_town, "payout": payout,
            })
        return offers

    # -- accept ----------------------------------------------------------
    def _accept(self, caller, arg):
        if caller.db.trade_contract:
            caller.msg("You already have an active contract. Deliver or abandon it first.")
            return
        offers = caller.db.trade_offers or []
        parts = arg.split()
        idx = None
        if len(parts) >= 2 and parts[1].isdigit():
            idx = int(parts[1])
        if not offers:
            caller.msg("List contracts first with CONTRACT.")
            return
        if idx is None or not (1 <= idx <= len(offers)):
            caller.msg("Accept which? Use CONTRACT ACCEPT <number> (1-%d)." % len(offers))
            return
        off = offers[idx - 1]
        cap = caravan_capacity(caller)
        if cargo_units(caller) + off["qty"] > cap:
            caller.msg("That crate (%d units) won't fit — caravan capacity %d/%d used."
                       % (off["qty"], cargo_units(caller), cap))
            return
        cargo = get_cargo(caller)
        cargo[off["good"]] = cargo.get(off["good"], 0) + off["qty"]
        caller.db.cargo = cargo
        caller.db.trade_contract = dict(off)
        caller.db.trade_offers = []
        caller.msg("You sign for the delivery and load |c%d|n %s onto your caravan.\n"
                   "Haul it to the |w%s|n market and CONTRACT DELIVER for |Y%s silver|n."
                   % (off["qty"], GOODS[off["good"]]["name"], off["dest_town"],
                      silver(off["payout"])))
        push_econ(caller)

    # -- deliver ---------------------------------------------------------
    def _deliver(self, caller):
        active = caller.db.trade_contract
        if not active:
            caller.msg("You have no active delivery contract.")
            return
        mk = room_market(caller.location)
        if not mk:
            caller.msg("There is no shipping clerk here.")
            return
        if mk["town"] != active["dest_town"]:
            caller.msg("This is %s — your contract delivers to |w%s|n. Keep hauling."
                       % (mk["town"], active["dest_town"]))
            return
        cargo = get_cargo(caller)
        gid, qty = active["good"], active["qty"]
        if int(cargo.get(gid, 0)) < qty:
            caller.msg("You are missing goods for this contract (need %d %s). "
                       "It cannot be completed." % (qty, GOODS[gid]["name"]))
            return
        cargo[gid] -= qty
        if cargo[gid] <= 0:
            del cargo[gid]
        caller.db.cargo = cargo
        caller.db.silvers = get_wallet(caller) + active["payout"]
        caller.db.trade_contract = None
        caller.msg("The shipping clerk checks the crate, stamps the manifest, and pays "
                   "you |Y%s silver|n. Contract complete!" % silver(active["payout"]))
        xp = 8 + qty
        for u in add_skill_xp(caller, "trading", xp):
            caller.msg(u)
        push_econ(caller)

    # -- abandon ---------------------------------------------------------
    def _abandon(self, caller):
        active = caller.db.trade_contract
        if not active:
            caller.msg("You have no active contract to abandon.")
            return
        cargo = get_cargo(caller)
        gid, qty = active["good"], active["qty"]
        if gid in cargo:
            cargo[gid] = max(0, cargo[gid] - qty)
            if cargo[gid] <= 0:
                del cargo[gid]
            caller.db.cargo = cargo
        caller.db.trade_contract = None
        caller.msg("You dump the undelivered crate and tear up the contract. "
                   "The guild will remember this.")
        push_econ(caller)


def _parse_qty_good(args):
    """Parse '<qty> <good>' -> (qty:int, good_id:str, err:str|None)."""
    text = (args or "").strip()
    if not text:
        return (0, None, "Specify a quantity and a good.")
    parts = text.split(None, 1)
    if len(parts) == 1:
        # allow 'buy iron ore' -> qty 1
        gid = resolve_good(parts[0])
        if gid:
            return (1, gid, None)
        return (0, None, "How many, and of what?")
    qty_tok, good_tok = parts[0], parts[1]
    if not qty_tok.lstrip("+").isdigit():
        # maybe the whole thing is a good name, qty 1
        gid = resolve_good(text)
        if gid:
            return (1, gid, None)
        return (0, None, "Quantity must be a number.")
    qty = int(qty_tok)
    if qty <= 0:
        return (0, None, "Quantity must be positive.")
    gid = resolve_good(good_tok)
    if not gid:
        return (0, None, "Unknown good '%s'." % good_tok)
    return (qty, gid, None)


class TraderCmdSet(CmdSet):
    """Trader-economy commands. Add to CharacterCmdSet (see integration snippet)."""

    key = "TraderCmdSet"
    priority = 1

    def at_cmdset_creation(self):
        self.add(CmdWares())
        self.add(CmdAppraise())
        self.add(CmdBuy())
        self.add(CmdSell())
        self.add(CmdContract())
