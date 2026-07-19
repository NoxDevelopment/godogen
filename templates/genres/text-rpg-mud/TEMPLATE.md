# text-rpg-mud — a living-world text MUD/MMORPG (GemStone IV parity target)

A real, persistent, multi-player text world: **Evennia** (BSD, Python) server +
(planned) **Godot** client, with a **living world** — autonomous agents and a world
clock that run with no player present. Parity target: **Simutronics' GemStone IV**
(see `godogen/docs/GEMSTONE4_PARITY_SPEC.md` — 89 parity items across UI/UX, systems
depth, and world/lore/living-agents).

> This is NOT the old single-player GDScript stub (that was untracked and never
> shipped). It is a genuine always-on server with DB persistence, accounts,
> sessions, many concurrent players, and telnet/websocket + an HTML5 webclient.

## What's real today (verified)
- **Live server** — Evennia 5.0.1 on PostgreSQL; telnet **4000**, websocket **4002**,
  HTML5 webclient **4001** all serve. World seeds a starter town.
- **Living world (proven, uncached)** — `typeclasses/nox_living.py`:
  - `WorldClock` — a global Script advancing Elanthian time, announcing dawn/dusk.
  - `WanderScript` — autonomous creature/NPC roaming on a timer.
  - Built + timer-armed in `server/conf/at_server_startstop.py::at_server_start`
    (the correct pattern — interval-script timers only arm in the server context).
- **Starter area** — Town Square / North Road / Market Row + a wandering giant rat.

## Setup (dev)
```bash
# 1) Python 3.11 venv + Evennia (NOT 3.13; 3.10 hit a shell-only recursion)
py -3.11 -m venv venv && venv/Scripts/python -m pip install evennia psycopg2-binary pywin32
# 2) PostgreSQL (SQLite hit an infinite-recursion bug in Django's query compiler here)
#    scoop install postgresql;  initdb -D pgdata --auth=trust;  pg_ctl -D pgdata -o "-p 5433" start
createdb -h 127.0.0.1 -p 5433 -U postgres nox_mud
# 3) migrate + admin + start   (from server/)
python -m evennia migrate
python -c "import os;os.environ['DJANGO_SETTINGS_MODULE']='server.conf.settings';import django;django.setup();from django.contrib.auth import get_user_model as G;U=G();U.objects.filter(username='admin').exists() or U.objects.create_superuser('admin','a@b.c','changeme')"
python -m evennia start          # then browse http://127.0.0.1:4001/webclient/
```
Note: create the superuser via `django.setup()` (above), **not** `evennia shell` /
`evennia start`'s TTY prompt — the interactive shell hits a recursion bug on Windows.

## Roadmap to GS4 parity (see the spec)
- **UI/UX** — adopt GS4's tag-stream protocol; build the Godot docked client (vitals
  bars, roundtime, hands, compass, active-spells, injuries figure, clickable nouns).
- **Systems depth** — professions, skill training, AS/DS+d100 combat with roundtime &
  criticals, spell circles, crafting/economy (driven by the Ruleset builder).
- **World/lore** — a Wehnimer's-Landing-style town + hunting zones; Elanthian pantheon
  & races (authored in the Worldbuilder); creatures with ecology.
- **Living agents** — townsfolk with daily routines, wandering merchants, creature
  spawns/respawns; NPC personalities from the companion library (consume-only), flavor
  from LLM generation.

Status: **server-live + living-world proven; awaiting Jesus's vet.** Not "done".
