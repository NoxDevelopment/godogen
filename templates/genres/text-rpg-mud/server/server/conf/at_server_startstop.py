"""
Server startstop hooks

This module contains functions called by Evennia at various
points during its startup, reload and shutdown sequence. It
allows for customizing the server operation as desired.

This module must contain at least these global functions:

at_server_init()
at_server_start()
at_server_stop()
at_server_reload_start()
at_server_reload_stop()
at_server_cold_start()
at_server_cold_stop()

"""


def at_server_init():
    """
    This is called first as the server is starting up, regardless of how.
    """
    pass


def at_server_start():
    """
    This is called every time the server starts up, regardless of
    how it was shut down.

    NoxDev: build the starter world once, and (re)create our interval scripts
    HERE (in the running server context) so their timers actually arm — scripts
    created from a standalone process, or merely restored from the DB, do not get
    a live task. This is the template's world-init hook.
    """
    from evennia import create_object, create_script
    from evennia.objects.models import ObjectDB
    from evennia.scripts.models import ScriptDB
    from typeclasses.rooms import Room
    from typeclasses.exits import Exit
    from typeclasses.characters import Character
    from typeclasses.nox_living import WorldClock, WanderScript

    # 1) Build the starter area once (idempotent).
    if not ObjectDB.objects.filter(db_key="Town Square").exists():
        sq = create_object(Room, key="Town Square")
        sq.db.desc = "A cobbled square at the heart of the settlement. Roads lead north and east."
        rd = create_object(Room, key="North Road")
        rd.db.desc = "A muddy road running north from the square."
        mk = create_object(Room, key="Market Row")
        mk.db.desc = "Stalls and shopfronts line this busy row."
        create_object(Exit, key="north", location=sq, destination=rd)
        create_object(Exit, key="south", location=rd, destination=sq)
        create_object(Exit, key="east", location=sq, destination=mk)
        create_object(Exit, key="west", location=mk, destination=sq)
        rat = create_object(Character, key="a giant rat", location=sq)
        rat.db.desc = "A mangy giant rat with yellowed teeth, twitching its whiskers."

    # 2) (Re)create interval scripts fresh so their LoopingCall timers arm.
    ScriptDB.objects.filter(db_key__in=["world_clock", "wander"]).delete()
    create_script(WorldClock)
    for mob in ObjectDB.objects.filter(db_key="a giant rat"):
        create_script(WanderScript, obj=mob)


def at_server_stop():
    """
    This is called just before the server is shut down, regardless
    of it is for a reload, reset or shutdown.
    """
    pass


def at_server_reload_start():
    """
    This is called only when server starts back up after a reload.
    """
    pass


def at_server_reload_stop():
    """
    This is called only time the server stops before a reload.
    """
    pass


def at_server_cold_start():
    """
    This is called only when the server starts "cold", i.e. after a
    shutdown or a reset.
    """
    pass


def at_server_cold_stop():
    """
    This is called only when the server goes down due to a shutdown or
    reset.
    """
    pass
