"""
Characters — GemStone-IV-style stat block + OOB state push to the rich client.

The character carries GS4-flavored vitals and condition, and pushes them to the
client as out-of-band messages (Evennia forwards unknown msg() kwargs to the
webclient as ["cmdname", [], {kwargs}]). The Godot client renders them into the
vitals bars, mind-state ladder, stance, encumbrance, injuries figure, active-spell
list, hands, and room panels. Data-driven so sci-fi/cyberpunk/horror worlds swap the
labels (mana->essence->cyber->sanity) without touching the client.
"""

from evennia.objects.objects import DefaultCharacter

from .objects import ObjectParent

# GS4 mind-state / experience-saturation acuity ladder (clear -> saturated).
MIND_LADDER = [
    "clear as a bell", "fresh and clear", "clear", "muddled",
    "becoming numbed", "numbed", "must rest", "saturated",
]


class Character(ObjectParent, DefaultCharacter):
    """A GemStone-style character with vitals, condition, wounds and spells."""

    def at_object_creation(self):
        super().at_object_creation()
        self.db.vitals = {
            "health": [100, 100],
            "mana": [84, 120],
            "spirit": [10, 10],
            "stamina": [100, 100],
        }
        self.db.mind = 15          # 0-100 experience saturation
        self.db.stance = "guarded"  # offensive|advance|forward|neutral|guarded|defensive
        self.db.encumbrance = 12    # 0-100 %
        self.db.level = 1
        self.db.rt = 0.0            # roundtime seconds remaining
        self.db.casttime = 0.0
        self.db.hands = {"left": "empty", "right": "empty", "spell": "none"}
        self.db.wounds = {}         # location -> rank 1..3 (e.g. {"right arm": 2})
        self.db.active_spells = []  # [{"name":..., "left":secs}]
        self.db.posture = "standing"

    # ------------------------------------------------------------------ OOB
    def push_state(self):
        # NOTE: Evennia's webclient OOB serializer flattens nested dicts to their
        # keys, so the payload MUST be scalars + lists-of-scalars only (no nested
        # dicts / lists-of-dicts). Vitals go as flat [cur,max] lists; wounds/spells
        # as flat alternating lists the client unpacks in pairs.
        v = self.db.vitals or {}
        h = self.db.hands or {}
        mind = int(self.db.mind or 0)
        idx = min(len(MIND_LADDER) - 1, int(mind / 100.0 * len(MIND_LADDER)))
        wounds_flat = []
        for loc, rank in (self.db.wounds or {}).items():
            wounds_flat += [loc, int(rank)]
        spells_flat = []
        for sp in (self.db.active_spells or []):
            spells_flat += [sp.get("name", "?"), int(sp.get("left", 0))]
        self.msg(nox_state=((), {
            "health": list(v.get("health", [0, 0])),
            "mana": list(v.get("mana", [0, 0])),
            "spirit": list(v.get("spirit", [0, 0])),
            "stamina": list(v.get("stamina", [0, 0])),
            "mind": mind,
            "mind_label": MIND_LADDER[idx],
            "stance": self.db.stance or "guarded",
            "encumbrance": int(self.db.encumbrance or 0),
            "level": int(self.db.level or 1),
            "rt": float(self.db.rt or 0.0),
            "casttime": float(self.db.casttime or 0.0),
            "hand_left": h.get("left", "empty"),
            "hand_right": h.get("right", "empty"),
            "hand_spell": h.get("spell", "none"),
            "posture": self.db.posture or "standing",
            "wounds": wounds_flat,
            "spells": spells_flat,
        }))

    def push_room(self):
        loc = self.location
        if not loc:
            return
        also = [o.key for o in loc.contents
                if o is not self and o.is_typeclass("typeclasses.characters.Character", exact=False)]
        exits = [e.key for e in loc.exits] if hasattr(loc, "exits") else \
                [e.key for e in loc.contents if getattr(e, "destination", None)]
        self.msg(nox_room=((), {"title": loc.key, "also": also, "exits": exits}))

    # ------------------------------------------------------------------ hooks
    def at_post_puppet(self, **kwargs):
        super().at_post_puppet(**kwargs)
        self.push_state()
        self.push_room()

    def at_post_move(self, source_location, **kwargs):
        super().at_post_move(source_location, **kwargs)
        self.push_room()
        self.push_state()
