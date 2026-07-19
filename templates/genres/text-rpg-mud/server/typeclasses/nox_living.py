"""
Nox Loom MUD — living-world primitives.

The core of the "do not half-ass it" living world: things happen with NO player
present. A global WorldClock advances Elanthian time and announces dawn/dusk; a
WanderScript drives autonomous creature/NPC movement on a timer. These are the
engine hooks the GemStone-IV-parity content (creatures with ecology, townsfolk
with daily routines) will be built on.
"""

import random

from evennia.scripts.scripts import DefaultScript
from evennia.server.sessionhandler import SESSIONS


class WorldClock(DefaultScript):
    """Global heartbeat: advances the in-world hour and broadcasts day/night."""

    def at_script_creation(self):
        self.key = "world_clock"
        self.desc = "Elanthian world clock — advances time, announces dawn/dusk."
        self.interval = 12  # real seconds per in-world hour (demo cadence)
        self.persistent = True
        self.db.hour = 6

    def at_repeat(self):
        hour = (self.db.hour + 1) % 24
        self.db.hour = hour
        if hour == 6:
            SESSIONS.announce_all("|yThe sun crests the horizon; dawn breaks over Elanthia.|n")
        elif hour == 12:
            SESSIONS.announce_all("|yThe sun stands high overhead.|n")
        elif hour == 20:
            SESSIONS.announce_all("|CDusk settles over the land; the first stars appear.|n")
        elif hour == 0:
            SESSIONS.announce_all("|bMidnight. The world is dark and quiet.|n")

    def phase(self):
        h = self.db.hour or 6
        if 6 <= h < 20:
            return "day"
        return "night"


class WanderScript(DefaultScript):
    """Attach to a creature/NPC: it roams to a random adjacent room on a timer.

    Proves autonomous agent life — the mob moves and is announced to any players
    in the rooms it enters/leaves, with no player command driving it.
    """

    def at_script_creation(self):
        self.key = "wander"
        self.desc = "Autonomous wandering."
        self.interval = 6
        self.persistent = True

    def at_repeat(self):
        mob = self.obj
        if not mob or not mob.location:
            return
        exits = [x for x in mob.location.contents if getattr(x, "destination", None)]
        if not exits:
            return
        ex = random.choice(exits)
        origin = mob.location
        origin.msg_contents(f"|w{mob.key}|n wanders {ex.key}.", exclude=[mob])
        mob.move_to(ex.destination, quiet=True, move_type="traverse")
        if mob.location:
            mob.location.msg_contents(f"|w{mob.key}|n wanders in.", exclude=[mob])
