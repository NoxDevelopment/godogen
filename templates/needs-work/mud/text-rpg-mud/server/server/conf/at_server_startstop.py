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
    from evennia import create_script
    from evennia.objects.models import ObjectDB
    from evennia.scripts.models import ScriptDB
    from evennia.utils import logger
    from typeclasses.nox_living import WorldClock

    # 1) Build the original AURETHIA region (Harrowgate + Ravenholt + Mistwood +
    #    Ratwarren; ~39 rooms, 16 NPCs). Idempotent — skips if already built.
    from world.nox_world import build_world, STARTER_TOWN_HUB
    build_world()

    # Remove legacy placeholder rooms superseded by build_world (safe: Aurethia
    # uses fully-qualified keys like "Harrowgate Town Square, Central").
    for _k in ("Town Square", "North Road", "Market Row"):
        for _r in ObjectDB.objects.filter(db_key=_k):
            _r.delete()

    # 2) World clock (timer only arms when created here, in the server process).
    ScriptDB.objects.filter(db_key="world_clock").delete()
    create_script(WorldClock)

    # 3) Deep systems — each guarded so one failing never breaks the world or others.
    try:
        from world.nox_economy import build_economy, MarketDriftScript
        build_economy(create_missing=True)
        ScriptDB.objects.filter(db_key="market_drift").delete()
        create_script(MarketDriftScript)
    except Exception:
        logger.log_trace("nox_economy wiring failed")
    try:
        from world.nox_crafting import wire_crafting_world, ensure_crafting_scripts
        wire_crafting_world()
        ensure_crafting_scripts()
    except Exception:
        logger.log_trace("nox_crafting wiring failed")
    try:
        from world.nox_magic import build_magic_world, MoonClock, SpellUpkeep
        from evennia.utils.search import search_script
        build_magic_world()
        if not search_script("moon_clock"):
            create_script(MoonClock)
        if not search_script("spell_upkeep"):
            create_script(SpellUpkeep)
    except Exception:
        logger.log_trace("nox_magic wiring failed")

    # 4) Seed + seat the demo character in the Harrowgate hub (GS4 showcase state;
    #    real values come from the trader/crafting/magic systems as they're played).
    hub = ObjectDB.objects.filter(db_key=STARTER_TOWN_HUB).first()
    for pc in ObjectDB.objects.filter(db_key="noxadmin"):
        if not pc.db.vitals:
            pc.at_object_creation()
        pc.db.vitals = {"health": [92, 100], "mana": [64, 120], "spirit": [9, 10], "stamina": [78, 100]}
        pc.db.mind = 55
        pc.db.stance = "forward"
        pc.db.level = 12
        if hub and pc.location != hub:
            pc.location = hub
            pc.save()


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
