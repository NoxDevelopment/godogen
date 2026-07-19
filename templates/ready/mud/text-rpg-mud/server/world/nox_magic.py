"""
Nox Loom MUD — MAGIC, MOONS & SOCIETIES (GemStone-IV-parity, original world).

This module implements Part 2 of the parity spec's magic design against our OWN
world (the realm of **Aethryn**, its four moons, its temple order) rather than
copying Elanthia. Everything is DATA-DRIVEN: spell circles, spells, moons and
societies live in module-level tables so a future Ruleset builder can author them.

WORLD NOTE (coherence): Agent A owns the canonical world+lore. The proper nouns
here are the MAGIC domain's slice of that world and are exposed as data
(``NOX_MAGIC_LORE``, ``NOX_MOONS``, ``NOX_SOCIETIES``) so sibling modules can
reference the same keys. Town/temple keys used: ``emberfall`` (starting town,
holds the Temple of Aurel), plus moongate anchor nodes this module builds itself
so the feature works standalone if Agent A's towns are not yet present.

Design mapped from the spec:
  * Three spheres (Elemental / Spiritual / Mental); circles numbered base+slot
    (e.g. 401, 906). A spell's slot is its rank requirement in that circle.
  * PREPARE holds a spell (~instant); CAST spends mana + sets a cast roundtime.
    Warding spells resolve CS - TD + d100 > 100; bolts use aiming vs DS.
  * Effects cover damage / heal / defensive-buff (-> db.active_spells so the
    client's ACTIVE SPELLS panel shows a countdown) / utility (light).
  * FOUR MOONS advanced by a MoonClock script; a FULL moon boosts its aligned
    circle ("moon magic"). A MOONGATE network offers lunar fast-travel gated by
    moon visibility (DR-origin, clearly a lunar alternative to roads).
  * SOCIETIES: a Voln-like order (Order of the Silver Vigil) joinable at the
    temple, with a rank ladder and a granted favor/ability.

Integration is by returned snippets (see this agent's notes); no shared files are
edited here.
"""

import random

from evennia.commands.default.muxcommand import MuxCommand
from evennia.scripts.scripts import DefaultScript
from evennia.server.sessionhandler import SESSIONS
from evennia.utils.create import create_object
from evennia.utils.search import search_script, search_tag

# ---------------------------------------------------------------------------
# LORE (magic-domain slice of Agent A's world; keys are reconcilable)
# ---------------------------------------------------------------------------

NOX_MAGIC_LORE = {
    "world_name": "Aethryn",
    "starting_town": "emberfall",
    "temple": {
        "key": "emberfall",
        "name": "the Temple of Aurel",
        "desc": (
            "A domed sanctuary of pale gold stone in Emberfall. Four oculi in the "
            "dome are cut to catch the light of each of Aethryn's moons in turn. "
            "Priests of the Silver Vigil keep the eternal lamp and receive petitioners."
        ),
    },
    # The magic pantheon, one god tied to each moon (Agent A may expand these).
    "gods": {
        "aurel": ("Aurel", "Keeper of the Gold Lamp — healing, mercy, the dawn-vow"),
        "vesh": ("Vesh", "the Crimson Forge — fire, wrath, the tempering of steel"),
        "morrow": ("Morrow", "the Pale Shepherd — spirits, the passage, the raising of the fallen"),
        "nihl": ("Nihl", "the Void Between — shadow, secrets, forbidden arcana"),
    },
}

# ---------------------------------------------------------------------------
# SPELL CIRCLES  (base number, sphere, casting stat, aligned moon)
# ---------------------------------------------------------------------------
# sphere -> casting stat per spec (AUR elemental / WIS spiritual / LOG mental).

NOX_CIRCLES = {
    "minor_spiritual": {
        "name": "Minor Spiritual",
        "base": 100,
        "sphere": "spiritual",
        "stat": "wisdom",
        "moon": "aurel",
        "shared": True,  # learnable by most professions
    },
    "minor_elemental": {
        "name": "Minor Elemental",
        "base": 400,
        "sphere": "elemental",
        "stat": "aura",
        "moon": "vesh",
        "shared": True,
    },
    "cleric_base": {
        "name": "Cleric Base",
        "base": 300,
        "sphere": "spiritual",
        "stat": "wisdom",
        "moon": "morrow",
        "shared": False,
    },
    "wizard_base": {
        "name": "Wizard Base",
        "base": 900,
        "sphere": "elemental",
        "stat": "aura",
        "moon": "nihl",
        "shared": False,
    },
}

# ---------------------------------------------------------------------------
# SPELLS  (number = circle base + slot; slot == ranks required in that circle)
# ---------------------------------------------------------------------------
# kind: warding-attack | bolt | heal | buff | utility
# For buffs/utility, ``duration`` seconds feeds the client ACTIVE SPELLS panel;
# ``ds`` is the defensive-strength bonus a buff grants while active.

NOX_SPELLS = {
    # ---- Minor Spiritual (100s) — shared support circle -------------------
    101: {
        "name": "Spirit Warding I", "circle": "minor_spiritual", "kind": "buff",
        "mana": 2, "cast_rt": 3.0, "duration": 300, "ds": 10,
        "prep": "You trace a warding sigil and feel the air about you thicken.",
        "cast": "A translucent nimbus of spirit settles over {t}.",
        "desc": "A minor defensive ward that raises magical defenses.",
    },
    103: {
        "name": "Guiding Light", "circle": "minor_spiritual", "kind": "utility",
        "mana": 1, "cast_rt": 2.0, "duration": 600, "light": True,
        "prep": "You cup your hands and whisper the dawn-vow of Aurel.",
        "cast": "A soft golden mote kindles above {t}, shedding gentle light.",
        "desc": "Conjures a floating mote of light that follows the caster.",
    },
    107: {
        "name": "Spirit Barrier", "circle": "minor_spiritual", "kind": "buff",
        "mana": 5, "cast_rt": 3.0, "duration": 420, "ds": 25,
        "prep": "You draw a full circle of light about your feet.",
        "cast": "A shimmering barrier of spirit encloses {t}.",
        "desc": "A stronger ward layering defensive strength.",
    },
    # ---- Minor Elemental (400s) — shared attack/utility circle ------------
    401: {
        "name": "Elemental Defense", "circle": "minor_elemental", "kind": "buff",
        "mana": 3, "cast_rt": 3.0, "duration": 300, "ds": 15,
        "prep": "Motes of raw element orbit your outstretched hand.",
        "cast": "A crackling elemental shell wraps {t}.",
        "desc": "Sheathes the target in reactive elemental force.",
    },
    406: {
        "name": "Cinderbolt", "circle": "minor_elemental", "kind": "bolt",
        "mana": 4, "cast_rt": 3.0, "power": 18,
        "prep": "An ember gathers, hissing, at your fingertip.",
        "cast": "You loose a searing bolt of cinders at {t}!",
        "desc": "A hurled bolt of burning ember. Bolt — resolves vs the target's DS.",
    },
    410: {
        "name": "Mage Lantern", "circle": "minor_elemental", "kind": "utility",
        "mana": 2, "cast_rt": 2.0, "duration": 900, "light": True,
        "prep": "You shape a sphere of cold flame in your palm.",
        "cast": "A steady sphere of cold flame rises to light {t}'s way.",
        "desc": "A brighter, longer-lasting elemental light.",
    },
    # ---- Cleric Base (300s) — spiritual profession circle -----------------
    303: {
        "name": "Prayer of Mending", "circle": "cleric_base", "kind": "heal",
        "mana": 6, "cast_rt": 3.0, "power": 35,
        "prep": "You clasp your holy symbol and intone Morrow's litany.",
        "cast": "Pale light knits the wounds of {t} closed.",
        "desc": "Restores health to a wounded target (or self).",
    },
    308: {
        "name": "Wrath of Morrow", "circle": "cleric_base", "kind": "warding-attack",
        "mana": 7, "cast_rt": 3.0, "power": 30,
        "prep": "You raise your symbol; the air grows cold and grave-still.",
        "cast": "Spectral chains of judgment lash out at {t}!",
        "desc": "A warding attack that scourges the unrighteous. CS vs TD.",
    },
    # ---- Wizard Base (900s) — elemental profession circle -----------------
    906: {
        "name": "Voidfire Bolt", "circle": "wizard_base", "kind": "bolt",
        "mana": 8, "cast_rt": 3.0, "power": 40,
        "prep": "Black flame coils up your forearm, edged in violet.",
        "cast": "You hurl a lance of voidfire that screams toward {t}!",
        "desc": "A powerful bolt of Nihl's void-flame. Bolt — vs the target's DS.",
    },
    911: {
        "name": " Arcane Aegis", "circle": "wizard_base", "kind": "buff",
        "mana": 10, "cast_rt": 4.0, "duration": 480, "ds": 40,
        "prep": "You weave a lattice of arcane glyphs into the air.",
        "cast": "A geometric shell of arcane force snaps into place around {t}.",
        "desc": "The strongest ward available — a full arcane aegis.",
    },
}
# fix stray key spacing for the aegis name
NOX_SPELLS[911]["name"] = "Arcane Aegis"


def circle_of(spellnum):
    return NOX_CIRCLES.get(NOX_SPELLS[spellnum]["circle"])


def slot_of(spellnum):
    """Rank (slot) required in the circle == number - circle base."""
    return spellnum - circle_of(spellnum)["base"]


# ---------------------------------------------------------------------------
# THE FOUR MOONS OF AETHRYN
# ---------------------------------------------------------------------------
# Each moon has its own period (real-second ticks per phase step) so they
# desync into shifting conjunctions. Phase 4 == FULL (boosts aligned circle),
# phase 0 == NEW (moon dark; its moongate cannot be opened).

MOON_PHASES = [
    "new", "waxing crescent", "first quarter", "waxing gibbous",
    "full", "waning gibbous", "last quarter", "waning crescent",
]
FULL_PHASE = 4
NEW_PHASE = 0

NOX_MOONS = {
    "aurel": {
        "name": "Aurel", "color": "|y", "hue": "gold",
        "circle": "minor_spiritual", "speed": 1, "start": 0,
        "flavor": "the gold moon of mercy and the dawn-vow",
    },
    "vesh": {
        "name": "Vesh", "color": "|r", "hue": "crimson",
        "circle": "minor_elemental", "speed": 1, "start": 3,
        "flavor": "the crimson moon of fire and wrath",
    },
    "morrow": {
        "name": "Morrow", "color": "|w", "hue": "pale",
        "circle": "cleric_base", "speed": 1, "start": 5,
        "flavor": "the pale moon of spirits and passage",
    },
    "nihl": {
        "name": "Nihl", "color": "|x", "hue": "void-black",
        "circle": "wizard_base", "speed": 1, "start": 6,
        "flavor": "the void moon of shadow and forbidden arcana",
    },
}

# moon boost applied to spell power / defensive strength when the aligned moon
# is FULL, plus a lesser boost on the gibbous shoulders.
MOON_FULL_MULT = 1.25
MOON_GIBBOUS_MULT = 1.10


class MoonClock(DefaultScript):
    """Global lunar clock: advances each moon's phase and announces changes.

    MUST be created in the SERVER process (at_server_start) or its interval
    timer will not arm. Stores phase indices flat (db.phase_<key>) so no nested
    dicts are persisted.
    """

    def at_script_creation(self):
        self.key = "moon_clock"
        self.desc = "Advances the phases of Aethryn's four moons; announces moonrise."
        self.interval = 30  # real seconds per phase step (demo cadence)
        self.persistent = True
        self.db.tick = 0
        for key, moon in NOX_MOONS.items():
            self.attributes.add("phase_%s" % key, moon["start"] % len(MOON_PHASES))

    # -- accessors ---------------------------------------------------------
    def phase_index(self, key):
        return int(self.attributes.get("phase_%s" % key, default=0))

    def phase_name(self, key):
        return MOON_PHASES[self.phase_index(key) % len(MOON_PHASES)]

    def is_full(self, key):
        return self.phase_index(key) % len(MOON_PHASES) == FULL_PHASE

    def is_dark(self, key):
        return self.phase_index(key) % len(MOON_PHASES) == NEW_PHASE

    def is_visible(self, key):
        """A moon is up (usable for moongates) whenever it is not fully dark."""
        return not self.is_dark(key)

    def power_mult(self, circle_key):
        """Moon-magic multiplier for a given circle from its aligned moon."""
        for key, moon in NOX_MOONS.items():
            if moon["circle"] == circle_key:
                idx = self.phase_index(key) % len(MOON_PHASES)
                if idx == FULL_PHASE:
                    return MOON_FULL_MULT
                if idx in (FULL_PHASE - 1, FULL_PHASE + 1):
                    return MOON_GIBBOUS_MULT
                return 1.0
        return 1.0

    # -- tick --------------------------------------------------------------
    def at_repeat(self):
        self.db.tick = (self.db.tick or 0) + 1
        for key, moon in NOX_MOONS.items():
            if self.db.tick % moon["speed"] != 0:
                continue
            old = self.phase_index(key)
            new = (old + 1) % len(MOON_PHASES)
            self.attributes.add("phase_%s" % key, new)
            col = moon["color"]
            if new == FULL_PHASE:
                SESSIONS.announce_all(
                    "%s%s|n rises FULL over Aethryn — %s. Its magic swells."
                    % (col, moon["name"], moon["flavor"]))
            elif new == NEW_PHASE:
                SESSIONS.announce_all(
                    "%s%s|n goes dark; its moongate closes until it waxes again."
                    % (col, moon["name"]))
            elif new == FULL_PHASE - 1:
                SESSIONS.announce_all(
                    "%s%s|n waxes gibbous, nearly full." % (col, moon["name"]))


def get_moonclock():
    hits = search_script("moon_clock")
    return hits[0] if hits else None


# ---------------------------------------------------------------------------
# SOCIETIES  (cross-profession; you may belong to ONE at a time)
# ---------------------------------------------------------------------------
# ranks: list of (title, granted_favor_key or None, description). Rank 1 is
# entry. A favor is an unlockable self-buff ability (see SOCIETY FAVOR).

NOX_SOCIETIES = {
    "silver_vigil": {
        "name": "the Order of the Silver Vigil",
        "short": "Silver Vigil",
        "join_at": "emberfall",           # temple town key
        "deity": "aurel",
        "max_rank": 26,
        "creed": (
            "Sworn to Aurel's lamp, the Silver Vigil hunts the restless dead and "
            "shepherds lost spirits to Morrow's road. Each rank earns a new symbol."
        ),
        # favor_key -> (min_rank, name, ds_bonus, duration, message)
        "favors": {
            "courage": (1, "Symbol of Courage", 15, 240,
                        "You touch your Silver Vigil symbol; steadfast courage steels you."),
            "return": (10, "Symbol of Return", 30, 300,
                       "Your symbol blazes silver-white, wards against the grave."),
            "sanctify": (20, "Symbol of Sanctification", 50, 360,
                         "Holy radiance pours from your symbol, hallowing the ground."),
        },
    },
    "ember_pact": {
        "name": "the Ember Pact",
        "short": "Ember Pact",
        "join_at": "emberfall",
        "deity": "vesh",
        "max_rank": 20,
        "creed": (
            "Vesh's oathbound smiths and battle-mages. The Pact tempers its members "
            "like steel — power bought with pain, favors earned at the forge-altar."
        ),
        "favors": {
            "temper": (1, "Ember Temper", 12, 240,
                       "Vesh's heat runs through you; your skin hardens like fired clay."),
            "forgeheart": (10, "Forgeheart", 28, 300,
                           "Molten resolve floods your chest; blows glance from you."),
        },
    },
}


def society_rank_title(society_key, rank):
    soc = NOX_SOCIETIES[society_key]
    # simple laddered titles derived from rank fraction
    frac = rank / max(1, soc["max_rank"])
    if rank >= soc["max_rank"]:
        return "Master of %s" % soc["short"]
    if frac >= 0.66:
        return "Knight of %s" % soc["short"]
    if frac >= 0.33:
        return "Companion of %s" % soc["short"]
    return "Initiate of %s" % soc["short"]


# ---------------------------------------------------------------------------
# PER-CHARACTER MAGIC STATE
# ---------------------------------------------------------------------------

def ensure_caster(char):
    """Idempotently initialise a character's magic fields + starter access."""
    if char.attributes.get("magic_init"):
        return
    char.db.magic_init = True
    char.db.spells_known = list(char.db.spells_known or [])
    # Spell Research ranks per circle (== how high a spell number you may learn).
    ranks = dict(char.db.circle_ranks or {})
    ranks.setdefault("minor_spiritual", 3)
    ranks.setdefault("minor_elemental", 6)
    char.db.circle_ranks = ranks
    char.db.prepared_spell = None
    if char.db.society is None:
        char.db.society = None
        char.db.society_rank = 0
    # ensure active_spells exists (defined on Character, but be safe)
    if char.db.active_spells is None:
        char.db.active_spells = []


def casting_stat_bonus(char, stat):
    """Bonus = floor((raw-50)/2); defaults to a mid stat if none authored."""
    stats = char.db.stats or {}
    raw = int(stats.get(stat, 60))
    return (raw - 50) // 2


def casting_strength(char, spellnum):
    circle = circle_of(spellnum)
    ranks = int((char.db.circle_ranks or {}).get(circle_key_of(spellnum), 0))
    level = int(char.db.level or 1)
    statb = casting_stat_bonus(char, circle["stat"])
    mult = 1.0
    mc = get_moonclock()
    if mc:
        mult = mc.power_mult(circle_key_of(spellnum))
    # scaled so a GS4-style endroll (CS - TD + d100 > 100) is reachable: a mid
    # caster sits near ~90 CS, an even-level target near ~55 TD.
    base = 50 + level * 3 + ranks * 2 + statb
    return int(base * mult), mult


def circle_key_of(spellnum):
    return NOX_SPELLS[spellnum]["circle"]


def target_defense(target):
    level = int((target.db.level or 1))
    ds = active_ds(target)
    return 25 + level * 3 + ds


def active_ds(char):
    total = 0
    for sp in (char.db.active_spells or []):
        total += int(sp.get("ds", 0))
    return total


def add_active_spell(char, name, duration, ds=0):
    spells = list(char.db.active_spells or [])
    # refresh if already active
    for sp in spells:
        if sp.get("name") == name:
            sp["left"] = int(duration)
            sp["ds"] = int(ds)
            char.db.active_spells = spells
            return
    spells.append({"name": name, "left": int(duration), "ds": int(ds)})
    char.db.active_spells = spells


def apply_damage(target, amount):
    v = dict(target.db.vitals or {})
    hp = list(v.get("health", [0, 0]))
    hp[0] = max(0, hp[0] - int(amount))
    v["health"] = hp
    target.db.vitals = v
    if hasattr(target, "push_state"):
        target.push_state()
    return hp[0]


def apply_heal(target, amount):
    v = dict(target.db.vitals or {})
    hp = list(v.get("health", [0, 0]))
    hp[0] = min(hp[1], hp[0] + int(amount))
    v["health"] = hp
    target.db.vitals = v
    if hasattr(target, "push_state"):
        target.push_state()
    return hp[0]


def spend_mana(char, amount):
    v = dict(char.db.vitals or {})
    mana = list(v.get("mana", [0, 0]))
    mana[0] = max(0, mana[0] - int(amount))
    v["mana"] = mana
    char.db.vitals = v


# ---------------------------------------------------------------------------
# CORE CAST RESOLVER
# ---------------------------------------------------------------------------

def resolve_cast(caster, spellnum, target):
    """Apply a spell's effect. Returns a list of message lines to echo."""
    spell = NOX_SPELLS[spellnum]
    kind = spell["kind"]
    circle = circle_of(spellnum)
    mc = get_moonclock()
    mult = mc.power_mult(circle_key_of(spellnum)) if mc else 1.0
    lines = []
    tgt = target or caster
    cast_line = spell["cast"].format(t=(tgt.key if tgt is not caster else "you"))
    lines.append("|C%s|n" % cast_line)
    if mult > 1.0:
        moon = NOX_MOONS[circle["moon"]]
        lines.append("%s%s|n rides high — %s magic surges (x%.2f)!"
                     % (moon["color"], moon["name"], circle["name"], mult))

    if kind in ("bolt", "warding-attack"):
        if target is None or target is caster:
            return ["You need a valid target for %s." % spell["name"]]
        cs, _ = casting_strength(caster, spellnum)
        roll = random.randint(1, 100)
        if kind == "bolt":
            # Spell Aiming vs DS (ranged-style); reuse cs as aiming proxy.
            td = 25 + int(target.db.level or 1) * 3 + active_ds(target)
            margin = cs - td + roll
            label = "aim %d vs def %d + d100(%d) = %d" % (cs, td, roll, margin)
        else:
            td = target_defense(target)
            margin = cs - td + roll
            label = "CS %d - TD %d + d100(%d) = %d" % (cs, td, roll, margin)
        if margin > 100:
            power = int(spell["power"] * mult)
            bonus = max(0, (margin - 100) // 4)
            dmg = power + bonus
            remaining = apply_damage(target, dmg)
            lines.append("|r[%s -> HIT for %d]|n %s reels (%d health left)."
                         % (label, dmg, target.key, remaining))
        else:
            lines.append("|x[%s -> the spell fails to overcome %s's defenses.]|n"
                         % (label, target.key))
        return lines

    if kind == "heal":
        amt = int(spell["power"] * mult)
        remaining = apply_heal(tgt, amt)
        lines.append("|g%s is healed for %d (now %d health).|n"
                     % (("You" if tgt is caster else tgt.key), amt, remaining))
        return lines

    if kind == "buff":
        ds = int(spell.get("ds", 0) * mult)
        add_active_spell(tgt, spell["name"], spell["duration"], ds=ds)
        if hasattr(tgt, "push_state"):
            tgt.push_state()
        lines.append("|G%s now wards %s (+%d DS, %ds).|n"
                     % (spell["name"], ("you" if tgt is caster else tgt.key),
                        ds, spell["duration"]))
        return lines

    if kind == "utility":
        add_active_spell(tgt, spell["name"], spell["duration"], ds=0)
        if spell.get("light"):
            tgt.db.has_light = True
        if hasattr(tgt, "push_state"):
            tgt.push_state()
        lines.append("|Y%s sheds light for %ds.|n" % (spell["name"], spell["duration"]))
        return lines

    return lines


# ---------------------------------------------------------------------------
# SPELL UPKEEP  (ticks active-spell durations; announces fades)
# ---------------------------------------------------------------------------

class SpellUpkeep(DefaultScript):
    """Global: decrements every puppeted character's active spells + re-pushes.

    Must be created in the server process (at_server_start) to arm its timer.
    """

    def at_script_creation(self):
        self.key = "spell_upkeep"
        self.desc = "Decrements active-spell durations and expires them."
        self.interval = 5
        self.persistent = True

    def at_repeat(self):
        seen = set()
        for sess in SESSIONS.get_sessions():
            char = sess.puppet
            if not char or char.id in seen:
                continue
            seen.add(char.id)
            spells = list(char.db.active_spells or [])
            if not spells:
                continue
            changed = False
            still = []
            for sp in spells:
                sp["left"] = int(sp.get("left", 0)) - self.interval
                if sp["left"] <= 0:
                    changed = True
                    char.msg("|xThe %s fades." % sp.get("name", "spell"))
                    if "light" in sp.get("name", "").lower() or sp.get("light"):
                        char.db.has_light = False
                else:
                    still.append(sp)
            if changed or still != spells:
                char.db.active_spells = still
                if hasattr(char, "push_state"):
                    char.push_state()


# ---------------------------------------------------------------------------
# WORLD BUILD  (temple + moongate anchors; idempotent; called from server start)
# ---------------------------------------------------------------------------

def build_magic_world():
    """Create the Temple of Aurel and the four moongate anchor rooms.

    Idempotent (tagged with category 'nox_magic'). Anchors are standalone so the
    moongate network works even before Agent A authors the towns; when the towns
    exist, they simply coexist as lunar-travel nodes.
    """
    made = []
    ROOM = "typeclasses.rooms.Room"

    def get_or_make(tagkey, name, desc, **attrs):
        existing = search_tag(tagkey, category="nox_magic")
        for r in existing:
            # anchors are distinguished by their bound moon attribute
            if tagkey != "moongate_anchor" or r.attributes.get("moon") == attrs.get("moon"):
                return r, False
        room = create_object(ROOM, key=name)
        room.db.desc = desc
        room.tags.add(tagkey, category="nox_magic")
        for k, v in attrs.items():
            room.attributes.add(k, v)
        return room, True

    temple, new = get_or_make(
        "nox_temple", "the Temple of Aurel",
        NOX_MAGIC_LORE["temple"]["desc"],
        town="emberfall")
    temple.db.is_temple = True
    if new:
        made.append(temple.key)

    # moongate hub
    hub, new = get_or_make(
        "moongate_hub", "the Lunar Nexus",
        "A ring of four standing stones, each keyed to one of Aethryn's moons. "
        "When a moon rides the sky its stone glows; step through to travel.",
        town="emberfall")
    if new:
        made.append(hub.key)

    for key, moon in NOX_MOONS.items():
        anchor, new = get_or_make(
            "moongate_anchor", "%s's Shard" % moon["name"],
            "A floating shard of %s stone, resonant with %s. A moongate anchor."
            % (moon["hue"], moon["flavor"]),
            moon=key)
        anchor.db.moon = key
        if new:
            made.append(anchor.key)

    return made


def moongate_anchors():
    return list(search_tag("moongate_anchor", category="nox_magic"))


def find_anchor_for_moon(moonkey):
    for r in search_tag("moongate_anchor", category="nox_magic"):
        if r.attributes.get("moon") == moonkey:
            return r
    return None


def find_temple():
    hits = search_tag("nox_temple", category="nox_magic")
    return hits[0] if hits else None


# ---------------------------------------------------------------------------
# COMMANDS
# ---------------------------------------------------------------------------

class CmdSpells(MuxCommand):
    """
    List your known spells and your access to the spell circles.

    Usage:
      spells
    """
    key = "spells"
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        known = sorted(c.db.spells_known or [])
        ranks = c.db.circle_ranks or {}
        out = ["|wSpell circles you can study:|n"]
        for ckey, circle in NOX_CIRCLES.items():
            r = int(ranks.get(ckey, 0))
            moon = NOX_MOONS[circle["moon"]]
            out.append("  %-16s (%s sphere, ranks %d) — aligned to %s%s|n"
                       % (circle["name"], circle["sphere"], r, moon["color"], moon["name"]))
        out.append("")
        if not known:
            out.append("|xYou know no spells yet. Use |wlearn <number>|x to study one "
                       "(you must have enough ranks in its circle).|n")
        else:
            out.append("|wKnown spells:|n")
            for num in known:
                sp = NOX_SPELLS[num]
                out.append("  |c%d|n %-16s [%s] mana %d, RT %.0fs — %s"
                           % (num, sp["name"], sp["kind"], sp["mana"],
                              sp["cast_rt"], sp["desc"]))
        # what is learnable now but not known
        learnable = [n for n in NOX_SPELLS
                     if n not in known
                     and int(ranks.get(NOX_SPELLS[n]["circle"], 0)) >= slot_of(n)]
        if learnable:
            out.append("")
            out.append("|gLearnable now:|n " + ", ".join(
                "%d %s" % (n, NOX_SPELLS[n]["name"]) for n in sorted(learnable)))
        c.msg("\n".join(out))


class CmdLearn(MuxCommand):
    """
    Study a spell into memory. You must have ranks in its circle >= its slot.

    Usage:
      learn <spell number>
    """
    key = "learn"
    aliases = ["study"]
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        if not self.args.strip().isdigit():
            c.msg("Usage: learn <spell number>  (see |wspells|n).")
            return
        num = int(self.args.strip())
        if num not in NOX_SPELLS:
            c.msg("There is no spell numbered %d." % num)
            return
        if num in (c.db.spells_known or []):
            c.msg("You already know %s (%d)." % (NOX_SPELLS[num]["name"], num))
            return
        ckey = NOX_SPELLS[num]["circle"]
        have = int((c.db.circle_ranks or {}).get(ckey, 0))
        need = slot_of(num)
        if have < need:
            c.msg("|rYou need %d ranks in %s to learn %s; you have %d.|n"
                  % (need, NOX_CIRCLES[ckey]["name"], NOX_SPELLS[num]["name"], have))
            return
        known = list(c.db.spells_known or [])
        known.append(num)
        c.db.spells_known = known
        c.msg("|gYou commit |c%s|n (%d) to memory." % (NOX_SPELLS[num]["name"], num))


class CmdPrepare(MuxCommand):
    """
    Prepare a known spell, holding it ready to cast.

    Usage:
      prepare <spell number>
      prep <spell number>
    """
    key = "prepare"
    aliases = ["prep"]
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        if not self.args.strip().isdigit():
            c.msg("Usage: prepare <spell number>.")
            return
        num = int(self.args.strip())
        if num not in (c.db.spells_known or []):
            c.msg("You do not know that spell.")
            return
        sp = NOX_SPELLS[num]
        c.db.prepared_spell = num
        hands = dict(c.db.hands or {})
        hands["spell"] = sp["name"]
        c.db.hands = hands
        c.msg("|c%s|n |wYou prepare %s.|n" % (sp["prep"], sp["name"]))
        if hasattr(c, "push_state"):
            c.push_state()


class CmdCast(MuxCommand):
    """
    Cast a prepared spell, or prepare-and-cast in one step.

    Usage:
      cast [target]                 (casts the spell you prepared)
      cast <spell number> [target]  (prepare + cast at once)

    Warding/bolt spells need a target creature in the room. Heals/buffs default
    to yourself; give a target's name to cast on them.
    """
    key = "cast"
    aliases = ["c", "incant"]
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        args = self.args.strip().split()
        num = None
        target_name = None
        if args and args[0].isdigit():
            num = int(args[0])
            target_name = " ".join(args[1:]) or None
        else:
            num = c.db.prepared_spell
            target_name = " ".join(args) or None
        if num is None:
            c.msg("You have no spell prepared. Use |wprepare <number>|n first.")
            return
        if num not in (c.db.spells_known or []):
            c.msg("You do not know that spell.")
            return
        sp = NOX_SPELLS[num]

        # cast roundtime gate (flavor cast bar)
        if (c.db.casttime or 0) > 0:
            c.msg("|xYou are still recovering from your last casting.|n")
            return

        # mana check
        mana = (c.db.vitals or {}).get("mana", [0, 0])[0]
        if mana < sp["mana"]:
            c.msg("|rYou lack the mana to cast %s (need %d, have %d).|n"
                  % (sp["name"], sp["mana"], mana))
            return

        # resolve target
        target = None
        if target_name:
            hits = c.search(target_name, quiet=True)
            target = hits[0] if hits else None
            if not target:
                c.msg("You don't see '%s' here." % target_name)
                return

        spend_mana(c, sp["mana"])
        c.db.prepared_spell = None
        hands = dict(c.db.hands or {})
        hands["spell"] = "none"
        c.db.hands = hands
        c.db.casttime = float(sp["cast_rt"])

        lines = resolve_cast(c, num, target)
        c.msg("\n".join(lines))
        room = c.location
        if room:
            room.msg_contents("|c%s gestures and incants.|n" % c.key, exclude=[c])
        if hasattr(c, "push_state"):
            c.push_state()

        # clear the cast bar shortly after (re-push)
        try:
            from evennia.utils.utils import delay

            def _clear():
                c.db.casttime = 0.0
                if hasattr(c, "push_state"):
                    c.push_state()
            delay(sp["cast_rt"], _clear)
        except Exception:
            c.db.casttime = 0.0


class CmdMoons(MuxCommand):
    """
    Report the current phases of Aethryn's four moons and their magic.

    Usage:
      moons
    """
    key = "moons"
    aliases = ["moon", "sky"]
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        mc = get_moonclock()
        if not mc:
            self.caller.msg("The moon clock is not running.")
            return
        out = ["|wThe four moons of Aethryn:|n"]
        for key, moon in NOX_MOONS.items():
            phase = mc.phase_name(key)
            circle = NOX_CIRCLES[moon["circle"]]
            tag = ""
            if mc.is_full(key):
                tag = " |Y<FULL — %s magic boosted!>|n" % circle["name"]
            elif mc.is_dark(key):
                tag = " |x<dark — moongate closed>|n"
            out.append("  %s%-7s|n  %-16s aligned to %s%s"
                       % (moon["color"], moon["name"], "(%s)" % phase,
                          circle["name"], tag))
        self.caller.msg("\n".join(out))


class CmdMoongate(MuxCommand):
    """
    Open a moongate and step to a lunar anchor. Only works while that moon is up
    (not dark). Costs mana; a waning moon risks a failed gate.

    Usage:
      moongate               (list anchors + which moons are up)
      moongate <moon name>   (travel to that moon's anchor shard)
    """
    key = "moongate"
    aliases = ["mg", "gate"]
    locks = "cmd:all()"
    help_category = "Magic"

    MANA_COST = 15

    def func(self):
        c = self.caller
        ensure_caster(c)
        mc = get_moonclock()
        if not mc:
            c.msg("The moons do not answer; the moon clock is not running.")
            return
        arg = self.args.strip().lower()
        if not arg:
            out = ["|wMoongate anchors (travel costs %d mana):|n" % self.MANA_COST]
            for key, moon in NOX_MOONS.items():
                status = "|gup|n" if mc.is_visible(key) else "|xdark (closed)|n"
                anchor = find_anchor_for_moon(key)
                where = anchor.key if anchor else "(no anchor built)"
                out.append("  %s%-7s|n [%s] -> %s" % (moon["color"], moon["name"], status, where))
            c.msg("\n".join(out))
            return

        # match moon by name
        moonkey = None
        for key, moon in NOX_MOONS.items():
            if moon["name"].lower().startswith(arg) or key == arg:
                moonkey = key
                break
        if not moonkey:
            c.msg("No moon by that name. Try |wmoongate|n to list them.")
            return
        moon = NOX_MOONS[moonkey]
        if not mc.is_visible(moonkey):
            c.msg("|x%s is dark; its moongate cannot be opened.|n" % moon["name"])
            return
        mana = (c.db.vitals or {}).get("mana", [0, 0])[0]
        if mana < self.MANA_COST:
            c.msg("|rYou lack the mana to open a moongate (need %d).|n" % self.MANA_COST)
            return
        anchor = find_anchor_for_moon(moonkey)
        if not anchor:
            c.msg("That moon has no anchor shard in the world yet.")
            return
        spend_mana(c, self.MANA_COST)
        # waning-phase instability -> chance of failed gate (mana already spent)
        idx = mc.phase_index(moonkey) % len(MOON_PHASES)
        waning = idx > FULL_PHASE
        if waning and not mc.is_full(moonkey) and random.random() < 0.25:
            c.msg("|rThe waning gate of %s|r flickers and collapses! The power is wasted.|n"
                  % moon["name"])
            if hasattr(c, "push_state"):
                c.push_state()
            return
        c.msg("%sA disc of %s light tears open before you — you step through.|n"
              % (moon["color"], moon["hue"]))
        if c.location:
            c.location.msg_contents("%s steps into a moongate and vanishes." % c.key, exclude=[c])
        c.move_to(anchor, quiet=True, move_type="teleport")
        if c.location:
            c.location.msg_contents("%s steps out of a shimmering moongate." % c.key, exclude=[c])
        if hasattr(c, "push_state"):
            c.push_state()


class CmdJoin(MuxCommand):
    """
    Join a society. You must be at the society's hall (the temple) and may
    belong to only one society at a time.

    Usage:
      join                 (list societies you can join here)
      join <society>       (e.g. 'join silver vigil')
    """
    key = "join"
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        loc = c.location
        here_town = loc.db.town if loc else None
        is_temple = bool(loc and loc.db.is_temple)
        arg = self.args.strip().lower()
        joinable = {k: s for k, s in NOX_SOCIETIES.items()
                    if is_temple or s["join_at"] == here_town}
        if not arg:
            if not joinable:
                c.msg("There is no society hall here. Seek the Temple of Aurel in Emberfall.")
                return
            out = ["|wSocieties you may join here:|n"]
            for k, s in joinable.items():
                out.append("  |c%s|n — %s" % (s["short"], s["creed"]))
            out.append("Use |wjoin <name>|n to swear in.")
            c.msg("\n".join(out))
            return
        if not joinable:
            c.msg("You are not at a society hall. Seek the Temple of Aurel in Emberfall.")
            return
        # match
        key = None
        for k, s in joinable.items():
            if s["short"].lower().startswith(arg) or k == arg.replace(" ", "_") or arg in s["short"].lower():
                key = k
                break
        if not key:
            c.msg("No such society here.")
            return
        if c.db.society:
            cur = NOX_SOCIETIES[c.db.society]["short"]
            c.msg("|rYou already belong to %s. You may join only one society.|n" % cur)
            return
        c.db.society = key
        c.db.society_rank = 1
        s = NOX_SOCIETIES[key]
        c.msg("|GYou kneel and swear the oath of %s. You are now an %s.|n"
              % (s["name"], society_rank_title(key, 1)))
        if loc:
            loc.msg_contents("%s is sworn into %s." % (c.key, s["name"]), exclude=[c])


class CmdSociety(MuxCommand):
    """
    Show your society standing, or invoke a granted favor (a self-buff ability).

    Usage:
      society               (your rank + available favors)
      society advance       (advance one rank — demo: earned by service)
      society favor <name>  (invoke a favor you've earned, e.g. 'society favor courage')
    """
    key = "society"
    aliases = ["favor"]
    locks = "cmd:all()"
    help_category = "Magic"

    def func(self):
        c = self.caller
        ensure_caster(c)
        skey = c.db.society
        if not skey:
            c.msg("You belong to no society. Visit the temple and |wjoin|n one.")
            return
        s = NOX_SOCIETIES[skey]
        rank = int(c.db.society_rank or 1)
        arg = self.args.strip().lower()

        if not arg or arg == "status":
            out = ["|w%s|n" % s["name"],
                   "  Rank %d/%d — %s" % (rank, s["max_rank"], society_rank_title(skey, rank)),
                   "  |wFavors:|n"]
            for fkey, (minr, fname, ds, dur, _msg) in s["favors"].items():
                mark = "|g[ready]|n" if rank >= minr else "|x[rank %d]|n" % minr
                out.append("    %-22s +%d DS, %ds  %s  (|wsociety favor %s|n)"
                           % (fname, ds, dur, mark, fkey))
            c.msg("\n".join(out))
            return

        if arg.startswith("advance"):
            if rank >= s["max_rank"]:
                c.msg("You are already %s." % society_rank_title(skey, rank))
                return
            c.db.society_rank = rank + 1
            c.msg("|GThrough service to %s you rise to rank %d — %s.|n"
                  % (s["name"], rank + 1, society_rank_title(skey, rank + 1)))
            return

        if arg.startswith("favor"):
            fname_arg = arg.replace("favor", "", 1).strip()
            if not fname_arg:
                c.msg("Which favor? See |wsociety|n for your list.")
                return
            match = None
            for fkey, data in s["favors"].items():
                if fkey.startswith(fname_arg) or fname_arg in fkey:
                    match = (fkey, data)
                    break
            if not match:
                c.msg("You have no such favor.")
                return
            fkey, (minr, fname, ds, dur, msg) = match
            if rank < minr:
                c.msg("|rYou must reach rank %d to invoke %s.|n" % (minr, fname))
                return
            add_active_spell(c, fname, dur, ds=ds)
            c.msg("|Y%s|n |G(+%d DS, %ds)|n" % (msg, ds, dur))
            if hasattr(c, "push_state"):
                c.push_state()
            return

        c.msg("Usage: society | society advance | society favor <name>")


# ---------------------------------------------------------------------------
# CMDSET
# ---------------------------------------------------------------------------

from evennia.commands.cmdset import CmdSet


class MagicCmdSet(CmdSet):
    """Magic, moons and societies. Merge into CharacterCmdSet."""

    key = "MagicCmdSet"

    def at_cmdset_creation(self):
        self.add(CmdSpells())
        self.add(CmdLearn())
        self.add(CmdPrepare())
        self.add(CmdCast())
        self.add(CmdMoons())
        self.add(CmdMoongate())
        self.add(CmdJoin())
        self.add(CmdSociety())
